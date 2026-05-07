//
//  MoonshineSpeechService.swift
//  Anything Reader
//
//  Moonshine-backed speech service for offline synthesis.
//

import AVFoundation
import Foundation
import MoonshineVoice
import Combine

@MainActor
final class MoonshineSpeechService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = MoonshineSpeechService()

    private let runtime = MoonshineSpeechRenderer()
    private var audioPlayer: AVAudioPlayer?
    @Published private(set) var isPlaying = false

    override private init() {}

    func prepareForPlayback() {
        isPlaying = true
    }

    func playSample(for voice: ReaderTTSVoiceSelection) {
        guard voice.providerID == .moonshine else { return }

        Task {
            do {
                let outputURL = try await runtime.synthesize(text: voice.sampleText, voice: voice)
                try await MainActor.run {
                    try playAudioFile(at: outputURL)
                }
            } catch {
                await MainActor.run {
                    self.isPlaying = false
                }
                NSLog("Moonshine sample playback failed: %@", error.localizedDescription)
            }
        }
    }

    func synthesize(text: String, voice: ReaderTTSVoiceSelection) async throws -> URL {
        guard voice.providerID == .moonshine else {
            throw CocoaError(.fileNoSuchFile)
        }

        try await MoonshineModelStore.shared.ensureInstalled(for: voice)
        return try await runtime.synthesize(text: text, voice: voice)
    }

    private func playAudioFile(at url: URL) throws {
        audioPlayer?.stop()
        audioPlayer = try AVAudioPlayer(contentsOf: url)
        audioPlayer?.delegate = self
        audioPlayer?.prepareToPlay()
        isPlaying = true
        audioPlayer?.play()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        isPlaying = false
    }
}

actor MoonshineSpeechRenderer {
    private var engineCache: [URL: TextToSpeech] = [:]

    func synthesize(text: String, voice: ReaderTTSVoiceSelection) async throws -> URL {
        let modelDirectory = try await modelDirectoryURL()
        let engine = try engine(for: modelDirectory, voice: voice)
        let result = try engine.synthesize(text: text)
        return try writeWaveFile(samples: result.samples, sampleRate: Double(result.sampleRateHz))
    }

    private func engine(for modelDirectory: URL, voice: ReaderTTSVoiceSelection) throws -> TextToSpeech {
        let cacheKey = modelDirectory.appendingPathComponent(voice.voiceName)
        if let cached = engineCache[cacheKey] {
            return cached
        }

        let language = moonshineLanguageCode(for: voice)
        let runtime = try TextToSpeech(
            language: language,
            g2pRoot: modelDirectory.path,
            voice: voice.voiceName,
            options: [
                TranscriberOption(name: "tts_root", value: modelDirectory.path),
                TranscriberOption(name: "model_root", value: modelDirectory.path)
            ]
        )
        engineCache[cacheKey] = runtime
        return runtime
    }

    private func modelDirectoryURL() async throws -> URL {
        guard let modelURL = await MainActor.run(body: { MoonshineModelStore.shared.modelURL() }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return modelURL
    }

    private func writeWaveFile(samples: [Float], sampleRate: Double) throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
        let tempURL = tempDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
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

        let audioFile = try AVAudioFile(forWriting: tempURL, settings: format.settings)
        try audioFile.write(from: buffer)
        return tempURL
    }

    private func moonshineLanguageCode(for voice: ReaderTTSVoiceSelection) -> String {
        switch voice.languageLabel.lowercased() {
        case let label where label.contains("british"):
            return "en_gb"
        case let label where label.contains("spanish"):
            return "es"
        case let label where label.contains("french"):
            return "fr"
        case let label where label.contains("italian"):
            return "it"
        case let label where label.contains("japanese"):
            return "ja"
        case let label where label.contains("portuguese"):
            return "pt"
        case let label where label.contains("chinese"):
            return "zh"
        default:
            return "en_us"
        }
    }
}
