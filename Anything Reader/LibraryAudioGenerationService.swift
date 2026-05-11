//
//  LibraryAudioGenerationService.swift
//  Anything Reader
//
//  Exports a full normalized document as a compressed local audio file using
//  the active TTS provider.
//

import AVFoundation
import Foundation

// Exports a normalized document into a local AAC file using the active TTS provider.
actor LibraryAudioGenerationService {
    // Shared singleton because export generation is invoked from the reader shell and background workflows.
    static let shared = LibraryAudioGenerationService()

    private init() {}

    // Warms the selected voice so the first real export starts faster.
    func prewarm(voice: ReaderTTSVoiceSelection) async {
        _ = try? await renderSamples(text: voice.sampleText, voice: voice)
    }

    // Converts a normalized text file into a compressed audio file ready for playback.
    func generateAudioFile(
        from normalizedTextFileURL: URL,
        entryTitle: String,
        voice: ReaderTTSVoiceSelection,
        destinationDirectoryURL: URL? = nil,
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

        let destinationURL = try destinationURL(
            for: entryTitle,
            voice: voice,
            destinationDirectoryURL: destinationDirectoryURL
        )
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

    // Writes the synthesized samples into an AAC container on disk.
    private func writeAACFile(
        chunks: [String],
        voice: ReaderTTSVoiceSelection,
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

        var writtenChunkCount = 0
        var isFirstChunk = true

        for chunk in chunks {
            let trimmedChunk = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedChunk.isEmpty else {
                continue
            }

            let samples = try await renderSamples(text: trimmedChunk, voice: voice)
            if !samples.isEmpty {
                try writeSamples(samples, to: audioFile, format: format)

                if !isFirstChunk {
                    try writeSilence(seconds: 0.08, to: audioFile, format: format)
                }
                isFirstChunk = false
            }

            writtenChunkCount += 1
            if let progressHandler {
                await progressHandler(min(1, Double(writtenChunkCount) / Double(chunks.count)))
            }
        }

        if let progressHandler {
            await progressHandler(1)
        }
    }

    // Synthesizes one chunk at a time so long documents can be exported reliably.
    private func renderSamples(text: String, voice: ReaderTTSVoiceSelection) async throws -> [Float] {
        let outputURL = try await synthesizeToWav(text: text, voice: voice)
        return try readSamples(from: outputURL)
    }

    // Routes synthesis to the configured provider-specific implementation.
    private func synthesizeToWav(text: String, voice: ReaderTTSVoiceSelection) async throws -> URL {
        switch voice.providerID {
        case .kokoro:
            let kokoroVoice = KokoroVoiceCatalog.voice(named: voice.voiceName)
            return try await KokoroSpeechService.shared.synthesize(text: text, voice: kokoroVoice)
        case .moonshine:
            return try await MoonshineSpeechService.shared.synthesize(text: text, voice: voice)
        }
    }

    // Reads PCM samples from the temporary WAV file returned by the speech runtime.
    private func readSamples(from url: URL) throws -> [Float] {
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw CocoaError(.fileReadUnknown)
        }

        try audioFile.read(into: buffer)

        guard let channelData = buffer.floatChannelData?[0] else {
            return []
        }

        return Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
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

    private func destinationURL(
        for entryTitle: String,
        voice: ReaderTTSVoiceSelection,
        destinationDirectoryURL: URL? = nil
    ) throws -> URL {
        let destinationDirectory: URL
        if let destinationDirectoryURL {
            destinationDirectory = destinationDirectoryURL
        } else {
            destinationDirectory = try uploadedFilesDirectory()
        }
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

    private static let filenameTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter
    }()
}

private func uploadedFilesDirectory() throws -> URL {
    let fileManager = FileManager.default
    let supportDirectory = try fileManager.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )

    let baseDirectory = supportDirectory
        .appendingPathComponent("Anything Reader", isDirectory: true)
        .appendingPathComponent("Uploaded Files", isDirectory: true)

    try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    return baseDirectory
}

private func sanitizedFileName(_ name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "Document" }

    let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
    let components = trimmed.components(separatedBy: invalidCharacters)
    let cleaned = components.joined(separator: "-")
    return cleaned.isEmpty ? "Document" : cleaned
}
