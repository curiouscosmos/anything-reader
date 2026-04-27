//
//  KokoroSpeechService.swift
//  Anything Reader
//
//  Kokoro-backed speech service that loads the selected model and voice style
//  from the local app sandbox and plays the synthesized result.
//

import AVFoundation
import Foundation
import KokoroSwift
import MLX
import ZIPFoundation
import Combine

// Describes a single Kokoro voice available in the UI.
struct KokoroVoiceOption: Identifiable, Hashable {
    let voiceName: String
    let displayName: String
    let languageLabel: String
    let sampleText: String

    var id: String { voiceName }

    var previewLanguageCode: String {
        switch String(voiceName.prefix(2)) {
        case "bf", "bm":
            return "en-GB"
        default:
            return "en-US"
        }
    }
}

// Centralized catalog so the Settings sheet stays declarative.
enum KokoroVoiceCatalog {
    static let defaultVoiceName = "af_bella"

    static let allVoices: [KokoroVoiceOption] = [
        .init(voiceName: "af_alloy", displayName: "Alloy", languageLabel: "American English · Female", sampleText: sampleText(for: "af_alloy", displayName: "Alloy")),
        .init(voiceName: "af_aoede", displayName: "Aoede", languageLabel: "American English · Female", sampleText: sampleText(for: "af_aoede", displayName: "Aoede")),
        .init(voiceName: "af_bella", displayName: "Bella", languageLabel: "American English · Female", sampleText: sampleText(for: "af_bella", displayName: "Bella")),
        .init(voiceName: "af_heart", displayName: "Heart", languageLabel: "American English · Female", sampleText: sampleText(for: "af_heart", displayName: "Heart")),
        .init(voiceName: "af_jessica", displayName: "Jessica", languageLabel: "American English · Female", sampleText: sampleText(for: "af_jessica", displayName: "Jessica")),
        .init(voiceName: "af_kore", displayName: "Kore", languageLabel: "American English · Female", sampleText: sampleText(for: "af_kore", displayName: "Kore")),
        .init(voiceName: "af_nicole", displayName: "Nicole", languageLabel: "American English · Female", sampleText: sampleText(for: "af_nicole", displayName: "Nicole")),
        .init(voiceName: "af_nova", displayName: "Nova", languageLabel: "American English · Female", sampleText: sampleText(for: "af_nova", displayName: "Nova")),
        .init(voiceName: "af_river", displayName: "River", languageLabel: "American English · Female", sampleText: sampleText(for: "af_river", displayName: "River")),
        .init(voiceName: "af_sarah", displayName: "Sarah", languageLabel: "American English · Female", sampleText: sampleText(for: "af_sarah", displayName: "Sarah")),
        .init(voiceName: "af_sky", displayName: "Sky", languageLabel: "American English · Female", sampleText: sampleText(for: "af_sky", displayName: "Sky")),

        .init(voiceName: "am_adam", displayName: "Adam", languageLabel: "American English · Male", sampleText: sampleText(for: "am_adam", displayName: "Adam")),
        .init(voiceName: "am_echo", displayName: "Echo", languageLabel: "American English · Male", sampleText: sampleText(for: "am_echo", displayName: "Echo")),
        .init(voiceName: "am_eric", displayName: "Eric", languageLabel: "American English · Male", sampleText: sampleText(for: "am_eric", displayName: "Eric")),
        .init(voiceName: "am_fenrir", displayName: "Fenrir", languageLabel: "American English · Male", sampleText: sampleText(for: "am_fenrir", displayName: "Fenrir")),
        .init(voiceName: "am_liam", displayName: "Liam", languageLabel: "American English · Male", sampleText: sampleText(for: "am_liam", displayName: "Liam")),
        .init(voiceName: "am_michael", displayName: "Michael", languageLabel: "American English · Male", sampleText: sampleText(for: "am_michael", displayName: "Michael")),
        .init(voiceName: "am_onyx", displayName: "Onyx", languageLabel: "American English · Male", sampleText: sampleText(for: "am_onyx", displayName: "Onyx")),
        .init(voiceName: "am_puck", displayName: "Puck", languageLabel: "American English · Male", sampleText: sampleText(for: "am_puck", displayName: "Puck")),

        .init(voiceName: "bf_alice", displayName: "Alice", languageLabel: "British English · Female", sampleText: sampleText(for: "bf_alice", displayName: "Alice")),
        .init(voiceName: "bf_emma", displayName: "Emma", languageLabel: "British English · Female", sampleText: sampleText(for: "bf_emma", displayName: "Emma")),
        .init(voiceName: "bf_isabella", displayName: "Isabella", languageLabel: "British English · Female", sampleText: sampleText(for: "bf_isabella", displayName: "Isabella")),
        .init(voiceName: "bf_lily", displayName: "Lily", languageLabel: "British English · Female", sampleText: sampleText(for: "bf_lily", displayName: "Lily")),

        .init(voiceName: "bm_daniel", displayName: "Daniel", languageLabel: "British English · Male", sampleText: sampleText(for: "bm_daniel", displayName: "Daniel")),
        .init(voiceName: "bm_fable", displayName: "Fable", languageLabel: "British English · Male", sampleText: sampleText(for: "bm_fable", displayName: "Fable")),
        .init(voiceName: "bm_george", displayName: "George", languageLabel: "British English · Male", sampleText: sampleText(for: "bm_george", displayName: "George")),
        .init(voiceName: "bm_lewis", displayName: "Lewis", languageLabel: "British English · Male", sampleText: sampleText(for: "bm_lewis", displayName: "Lewis")),

        .init(voiceName: "ef_dora", displayName: "Dora", languageLabel: "Spanish · Female", sampleText: sampleText(for: "ef_dora", displayName: "Dora")),
        .init(voiceName: "ff_siwis", displayName: "Siwis", languageLabel: "French · Female", sampleText: sampleText(for: "ff_siwis", displayName: "Siwis")),
        .init(voiceName: "if_sara", displayName: "Sara", languageLabel: "Italian · Female", sampleText: sampleText(for: "if_sara", displayName: "Sara")),
        .init(voiceName: "im_nicola", displayName: "Nicola", languageLabel: "Italian · Male", sampleText: sampleText(for: "im_nicola", displayName: "Nicola")),

        .init(voiceName: "jf_alpha", displayName: "Alpha", languageLabel: "Japanese · Female", sampleText: sampleText(for: "jf_alpha", displayName: "Alpha")),
        .init(voiceName: "jf_gongitsune", displayName: "Gongitsune", languageLabel: "Japanese · Female", sampleText: sampleText(for: "jf_gongitsune", displayName: "Gongitsune")),
        .init(voiceName: "jf_nezumi", displayName: "Nezumi", languageLabel: "Japanese · Female", sampleText: sampleText(for: "jf_nezumi", displayName: "Nezumi")),
        .init(voiceName: "jf_tebukuro", displayName: "Tebukuro", languageLabel: "Japanese · Female", sampleText: sampleText(for: "jf_tebukuro", displayName: "Tebukuro")),
        .init(voiceName: "jm_kumo", displayName: "Kumo", languageLabel: "Japanese · Male", sampleText: sampleText(for: "jm_kumo", displayName: "Kumo")),

        .init(voiceName: "pf_dora", displayName: "Dora", languageLabel: "Portuguese · Female", sampleText: sampleText(for: "pf_dora", displayName: "Dora")),
        .init(voiceName: "zf_xiaobei", displayName: "Xiaobei", languageLabel: "Chinese · Female", sampleText: sampleText(for: "zf_xiaobei", displayName: "Xiaobei")),
        .init(voiceName: "zf_xiaoni", displayName: "Xiaoni", languageLabel: "Chinese · Female", sampleText: sampleText(for: "zf_xiaoni", displayName: "Xiaoni")),
        .init(voiceName: "zf_xiaoxiao", displayName: "Xiaoxiao", languageLabel: "Chinese · Female", sampleText: sampleText(for: "zf_xiaoxiao", displayName: "Xiaoxiao")),
        .init(voiceName: "zf_xiaoyi", displayName: "Xiaoyi", languageLabel: "Chinese · Female", sampleText: sampleText(for: "zf_xiaoyi", displayName: "Xiaoyi")),
        .init(voiceName: "zm_yunjian", displayName: "Yunjian", languageLabel: "Chinese · Male", sampleText: sampleText(for: "zm_yunjian", displayName: "Yunjian")),
        .init(voiceName: "zm_yunxi", displayName: "Yunxi", languageLabel: "Chinese · Male", sampleText: sampleText(for: "zm_yunxi", displayName: "Yunxi")),
        .init(voiceName: "zm_yunxia", displayName: "Yunxia", languageLabel: "Chinese · Male", sampleText: sampleText(for: "zm_yunxia", displayName: "Yunxia")),
        .init(voiceName: "zm_yunyang", displayName: "Yunyang", languageLabel: "Chinese · Male", sampleText: sampleText(for: "zm_yunyang", displayName: "Yunyang"))
    ]

    static func voice(named name: String) -> KokoroVoiceOption {
        allVoices.first(where: { $0.voiceName == name }) ?? allVoices[0]
    }

    private static func sampleText(for voiceName: String, displayName: String) -> String {
        switch String(voiceName.prefix(2)) {
        case "ef":
            return "Hola. Esta es la vista previa de la voz \(displayName) para Anything Reader."
        case "ff":
            return "Bonjour. Ceci est l'aperçu de la voix \(displayName) pour Anything Reader."
        case "if", "im":
            return "Ciao. Questa è l'anteprima della voce \(displayName) per Anything Reader."
        case "jf", "jm":
            return "こんにちは。これは Anything Reader の \(displayName) 音声プレビューです。"
        case "pf":
            return "Olá. Esta é a prévia da voz \(displayName) para Anything Reader."
        case "zf", "zm":
            return "你好，这是 Anything Reader 的 \(displayName) 语音预览。"
        default:
            return "Hello. This is the \(displayName) voice preview for Anything Reader."
        }
    }
}

// Kokoro speech service that generates and plays local model output.
final class KokoroSpeechService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = KokoroSpeechService()

    private let runtime = RuntimeBackend()
    private var audioPlayer: AVAudioPlayer?
    @Published private(set) var isPlaying = false

    override private init() {}

    func prepareForPlayback() {
        isPlaying = true
    }

    func playSample(for voice: KokoroVoiceOption) {
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
                NSLog("Kokoro sample playback failed: %@", error.localizedDescription)
            }
        }
    }

    func synthesize(text: String, voice: KokoroVoiceOption) async throws -> URL {
        try await runtime.synthesize(text: text, voice: voice)
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

// MARK: - Runtime backend

private actor RuntimeBackend {
    private var engineCache: [URL: KokoroTTS] = [:]
    private var voiceCache: [String: MLXArray] = [:]
    private let sampleRate: Double = 24_000

    func synthesize(text: String, voice: KokoroVoiceOption) async throws -> URL {
        guard let modelURL = await MainActor.run(body: { KokoroModelStore.shared.modelURL() }) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let engine = try engine(for: modelURL)
        let voiceEmbedding = try await voiceEmbedding(for: voice.voiceName)
        let language = language(for: voice)
        let (audioSamples, _) = try engine.generateAudio(
            voice: voiceEmbedding,
            language: language,
            text: text,
            speed: 1.0
        )

        return try writeWaveFile(samples: audioSamples)
    }

    private func engine(for modelURL: URL) throws -> KokoroTTS {
        if let cached = engineCache[modelURL] {
            return cached
        }

        let engine = KokoroTTS(modelPath: modelURL, g2p: .misaki)
        engineCache[modelURL] = engine
        return engine
    }

    private func voiceEmbedding(for voiceName: String) async throws -> MLXArray {
        if let cached = voiceCache[voiceName] {
            return cached
        }

        let archiveURL = try voiceArchiveURL()
        let extractedURL = try extractVoiceFile(named: "\(voiceName).npy", from: archiveURL)
        let voiceArray = try loadVoiceArray(from: extractedURL)
        voiceCache[voiceName] = voiceArray
        return voiceArray
    }

    private func voiceArchiveURL() throws -> URL {
        if let bundleURL = Bundle.main.url(forResource: "voices-v1.0", withExtension: "bin") {
            return bundleURL
        }

        if let bundleURL = Bundle.main.url(forResource: "voices-v1.0", withExtension: nil) {
            return bundleURL
        }

        throw CocoaError(.fileNoSuchFile)
    }

    private func extractVoiceFile(named entryName: String, from archiveURL: URL) throws -> URL {
        let destinationDirectory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Anything Reader", isDirectory: true)
            .appendingPathComponent("Kokoro Voices", isDirectory: true)

        guard let destinationDirectory else {
            throw CocoaError(.fileWriteUnknown)
        }

        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let destinationURL = destinationDirectory.appendingPathComponent(entryName)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            return destinationURL
        }

        let archive = try Archive(url: archiveURL, accessMode: .read)

        guard let entry = archive[entryName] else {
            throw CocoaError(.fileNoSuchFile)
        }

        _ = try archive.extract(entry, to: destinationURL)
        return destinationURL
    }

    private func loadVoiceArray(from url: URL) throws -> MLXArray {
        try loadArray(url: url)
    }

    private func language(for voice: KokoroVoiceOption) -> Language {
        switch String(voice.voiceName.prefix(2)) {
        case "bf", "bm":
            return .enGB
        default:
            return .enUS
        }
    }

    private func writeWaveFile(samples: [Float]) throws -> URL {
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
}
