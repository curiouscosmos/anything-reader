//
//  LibraryAudioGenerationService.swift
//  Anything Reader
//
//  Exports a full normalized document as a single local audio file using the
//  existing Kokoro synthesis stack.
//

import AVFoundation
import Foundation

actor LibraryAudioGenerationService {
    static let shared = LibraryAudioGenerationService()

    private init() {}

    func generateAudioFile(
        from normalizedTextFileURL: URL,
        entryTitle: String,
        voice: KokoroVoiceOption
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

        let chunkAudioURLs = try await synthesizeAudioChunks(chunks, voice: voice)
        let generatedURL = try mergeAudioChunks(chunkAudioURLs, entryTitle: entryTitle, voice: voice)
        let destinationURL = try destinationURL(for: entryTitle, voice: voice, sourceURL: generatedURL)

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: generatedURL, to: destinationURL)

        cleanupTemporaryFiles([generatedURL] + chunkAudioURLs)
        return destinationURL
    }

    private func synthesizeAudioChunks(_ chunks: [String], voice: KokoroVoiceOption) async throws -> [URL] {
        var audioURLs: [URL] = []
        audioURLs.reserveCapacity(chunks.count)

        for chunk in chunks {
            try Task.checkCancellation()

            let trimmedChunk = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedChunk.isEmpty else { continue }

            let chunkURL = try await KokoroSpeechService.shared.synthesize(text: trimmedChunk, voice: voice)
            audioURLs.append(chunkURL)
        }

        return audioURLs
    }

    private func mergeAudioChunks(_ chunkAudioURLs: [URL], entryTitle: String, voice: KokoroVoiceOption) throws -> URL {
        guard let firstURL = chunkAudioURLs.first else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let firstFile = try AVAudioFile(forReading: firstURL)
        let outputFormat = firstFile.processingFormat
        let outputURL = try stagingURL(for: entryTitle, voice: voice)
        let outputFile = try AVAudioFile(forWriting: outputURL, settings: outputFormat.settings)

        for audioURL in chunkAudioURLs {
            let inputFile = try AVAudioFile(forReading: audioURL)
            guard inputFile.processingFormat.sampleRate == outputFormat.sampleRate else {
                throw CocoaError(.fileWriteInapplicableStringEncoding)
            }

            try append(file: inputFile, to: outputFile)
            try appendSilence(duration: 0.08, format: outputFormat, to: outputFile)
        }

        return outputURL
    }

    private func destinationURL(for entryTitle: String, voice: KokoroVoiceOption, sourceURL: URL) throws -> URL {
        let destinationDirectory = try uploadedFilesDirectory()
        let fileManager = FileManager.default

        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let timestamp = Self.filenameTimestampFormatter.string(from: .now)
        let baseName = sanitizedFileName("\(entryTitle) - \(voice.displayName) - \(timestamp)")
        let fileExtension = sourceURL.pathExtension.isEmpty ? "wav" : sourceURL.pathExtension
        return destinationDirectory.appendingPathComponent(baseName).appendingPathExtension(fileExtension)
    }

    private func stagingURL(for entryTitle: String, voice: KokoroVoiceOption) throws -> URL {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory

        guard fileManager.fileExists(atPath: temporaryDirectory.path) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let timestamp = Self.filenameTimestampFormatter.string(from: .now)
        let baseName = sanitizedFileName("\(entryTitle) - \(voice.displayName) - merged - \(timestamp)")
        return temporaryDirectory.appendingPathComponent(baseName).appendingPathExtension("wav")
    }

    private func append(file: AVAudioFile, to outputFile: AVAudioFile) throws {
        let bufferCapacity: AVAudioFrameCount = 4096
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: bufferCapacity) else {
            throw CocoaError(.fileReadUnknown)
        }

        while file.framePosition < file.length {
            let remainingFrames = file.length - file.framePosition
            let framesToRead = AVAudioFrameCount(min(Int64(bufferCapacity), remainingFrames))
            try file.read(into: buffer, frameCount: framesToRead)
            guard buffer.frameLength > 0 else { break }
            try outputFile.write(from: buffer)
        }
    }

    private func appendSilence(duration: TimeInterval, format: AVAudioFormat, to outputFile: AVAudioFile) throws {
        let frameCount = AVAudioFrameCount(max(1, Int(duration * format.sampleRate)))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw CocoaError(.fileWriteUnknown)
        }

        buffer.frameLength = frameCount

        if let channelData = buffer.floatChannelData {
            for channel in 0..<Int(format.channelCount) {
                channelData[channel].initialize(repeating: 0, count: Int(frameCount))
            }
        }

        try outputFile.write(from: buffer)
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

    private func cleanupTemporaryFiles(_ urls: [URL]) {
        let fileManager = FileManager.default
        for url in urls {
            if fileManager.fileExists(atPath: url.path) {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    private static let filenameTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd_HHmmssSSS"
        return formatter
    }()

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
}
