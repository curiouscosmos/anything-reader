//
//  LibraryAudioGenerationService.swift
//  Anything Reader
//
//  Exports a full normalized document as a compressed local audio file using
//  Kokoro synthesis workers and direct AAC encoding.
//

import AVFoundation
import Foundation

actor LibraryAudioGenerationService {
    static let shared = LibraryAudioGenerationService()

    private let workers = (0..<2).map { _ in KokoroSpeechRenderer() }

    private init() {}

    func prewarm(voice: KokoroVoiceOption) async {
        let renderer = workers[0]
        _ = try? await renderer.prewarm(voice: voice)
    }

    func generateAudioFile(
        from normalizedTextFileURL: URL,
        entryTitle: String,
        voice: KokoroVoiceOption,
        progressHandler: (@Sendable (Double) async -> Void)? = nil
    ) async throws -> URL {
        guard FileManager.default.fileExists(atPath: normalizedTextFileURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let textData = try Data(contentsOf: normalizedTextFileURL)
        guard let text = String(data: textData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let chunks = await MainActor.run {
            ReaderPlaybackChunkService.chunks(from: text)
        }
        guard !chunks.isEmpty else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let destinationURL = try destinationURL(for: entryTitle, voice: voice)
        let stagingURL = temporaryOutputURL(for: destinationURL)

        do {
            try await writeAACFile(
                chunks: chunks,
                voice: voice,
                to: stagingURL,
                progressHandler: progressHandler
            )

            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }

            try fileManager.moveItem(at: stagingURL, to: destinationURL)
        } catch {
            try? FileManager.default.removeItem(at: stagingURL)
            throw error
        }

        return destinationURL
    }

    private func writeAACFile(
        chunks: [String],
        voice: KokoroVoiceOption,
        to outputURL: URL,
        progressHandler: (@Sendable (Double) async -> Void)? = nil
    ) async throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }

        let sampleRate: Double = 24_000
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let audioFile = try AVAudioFile(
            forWriting: outputURL,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        try await withThrowingTaskGroup(of: ChunkSamples.self) { group in
            var nextIndexToWrite = 0
            var pendingChunks: [Int: [Float]] = [:]
            var isFirstChunk = true
            var writtenChunkCount = 0

            for (index, chunk) in chunks.enumerated() {
                group.addTask {
                    try Task.checkCancellation()

                    let trimmedChunk = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedChunk.isEmpty else {
                        return ChunkSamples(index: index, samples: [])
                    }

                    let renderer = self.workers[index % self.workers.count]
                    let samples = try await self.renderSamples(trimmedChunk, voice: voice, using: renderer)
                    return ChunkSamples(index: index, samples: samples)
                }
            }

            for try await item in group {
                pendingChunks[item.index] = item.samples

                while let samples = pendingChunks.removeValue(forKey: nextIndexToWrite) {
                    if !samples.isEmpty {
                        try writeSamples(samples, to: audioFile, format: format)

                        if !isFirstChunk {
                            try writeSilence(seconds: 0.08, to: audioFile, format: format)
                        }
                        isFirstChunk = false
                    }

                    nextIndexToWrite += 1
                    writtenChunkCount += 1
                    if let progressHandler {
                        await progressHandler(min(1, Double(writtenChunkCount) / Double(chunks.count)))
                    }
                }
            }
        }

        if let progressHandler {
            await progressHandler(1)
        }
    }

    private func renderSamples(
        _ text: String,
        voice: KokoroVoiceOption,
        using renderer: KokoroSpeechRenderer
    ) async throws -> [Float] {
        do {
            return try await renderer.renderSamples(text: text, voice: voice)
        } catch {
            let fallbackChunks = fallbackChunks(for: text)
            guard fallbackChunks.count > 1 else {
                throw error
            }

            var samples: [Float] = []
            for fallbackChunk in fallbackChunks {
                try Task.checkCancellation()
                let nestedSamples = try await renderSamples(
                    fallbackChunk,
                    voice: voice,
                    using: renderer
                )
                samples.append(contentsOf: nestedSamples)
            }
            return samples
        }
    }

    private func writeSamples(_ samples: [Float], to audioFile: AVAudioFile, format: AVAudioFormat) throws {
        guard !samples.isEmpty else { return }

        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw CocoaError(.fileWriteUnknown)
        }

        buffer.frameLength = frameCount
        samples.withUnsafeBufferPointer { samplePointer in
            guard let source = samplePointer.baseAddress,
                  let channelData = buffer.floatChannelData?[0] else {
                return
            }

            channelData.update(from: source, count: samples.count)
        }

        try audioFile.write(from: buffer)
    }

    private func writeSilence(seconds: TimeInterval, to audioFile: AVAudioFile, format: AVAudioFormat) throws {
        let frameCount = AVAudioFrameCount(max(1, Int(seconds * format.sampleRate)))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw CocoaError(.fileWriteUnknown)
        }

        buffer.frameLength = frameCount

        if let channelData = buffer.floatChannelData?[0] {
            channelData.initialize(repeating: 0, count: Int(frameCount))
        }

        try audioFile.write(from: buffer)
    }

    private func destinationURL(for entryTitle: String, voice: KokoroVoiceOption) throws -> URL {
        let destinationDirectory = try uploadedFilesDirectory()
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let timestamp = Self.filenameTimestampFormatter.string(from: .now)
        let baseName = sanitizedFileName("\(entryTitle) - \(voice.displayName) - \(timestamp)")
        return destinationDirectory.appendingPathComponent(baseName).appendingPathExtension("m4a")
    }

    private func temporaryOutputURL(for destinationURL: URL) -> URL {
        let fileName = destinationURL.deletingPathExtension().lastPathComponent
            + "-" + UUID().uuidString
            + ".partial.m4a"
        return FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    }

    private func fallbackChunks(for text: String) -> [String] {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard words.count > 1 else { return [text] }

        let targetWordCount = max(1, min(words.count / 2, 40))
        guard targetWordCount < words.count else { return [text] }

        var chunks: [String] = []
        var index = 0

        while index < words.count {
            let endIndex = min(index + targetWordCount, words.count)
            let chunk = words[index..<endIndex].joined(separator: " ")
            if !chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                chunks.append(chunk)
            }
            index = endIndex
        }

        return chunks.isEmpty ? [text] : chunks
    }

    private func sanitizedFileName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics
            .union(.whitespaces)
            .union(CharacterSet(charactersIn: "-_()."))

        let collapsed = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let fileName = String(collapsed)
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return fileName.isEmpty ? "Generated Audio" : fileName
    }

    private func uploadedFilesDirectory() throws -> URL {
        let fileManager = FileManager.default
        guard let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileWriteUnknown)
        }

        let appDirectory = supportDirectory.appendingPathComponent("Anything Reader", isDirectory: true)
        let uploadsDirectory = appDirectory.appendingPathComponent("Uploaded Files", isDirectory: true)

        if !fileManager.fileExists(atPath: uploadsDirectory.path) {
            try fileManager.createDirectory(at: uploadsDirectory, withIntermediateDirectories: true)
        }

        return uploadsDirectory
    }

    private static let filenameTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd_HHmmssSSS"
        return formatter
    }()

    private struct ChunkSamples {
        let index: Int
        let samples: [Float]
    }
}
