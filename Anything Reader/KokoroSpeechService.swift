//
//  KokoroSpeechService.swift
//  Anything Reader
//
//  Kokoro voice catalog plus an offline-first speech service.
//

import AVFoundation
import Foundation

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
        .init(voiceName: "af_alloy", displayName: "Alloy", languageLabel: "American English · Female", sampleText: sampleText(for: "Alloy")),
        .init(voiceName: "af_aoede", displayName: "Aoede", languageLabel: "American English · Female", sampleText: sampleText(for: "Aoede")),
        .init(voiceName: "af_bella", displayName: "Bella", languageLabel: "American English · Female", sampleText: sampleText(for: "Bella")),
        .init(voiceName: "af_heart", displayName: "Heart", languageLabel: "American English · Female", sampleText: sampleText(for: "Heart")),
        .init(voiceName: "af_jessica", displayName: "Jessica", languageLabel: "American English · Female", sampleText: sampleText(for: "Jessica")),
        .init(voiceName: "af_kore", displayName: "Kore", languageLabel: "American English · Female", sampleText: sampleText(for: "Kore")),
        .init(voiceName: "af_nicole", displayName: "Nicole", languageLabel: "American English · Female", sampleText: sampleText(for: "Nicole")),
        .init(voiceName: "af_nova", displayName: "Nova", languageLabel: "American English · Female", sampleText: sampleText(for: "Nova")),
        .init(voiceName: "af_river", displayName: "River", languageLabel: "American English · Female", sampleText: sampleText(for: "River")),
        .init(voiceName: "af_sarah", displayName: "Sarah", languageLabel: "American English · Female", sampleText: sampleText(for: "Sarah")),
        .init(voiceName: "af_sky", displayName: "Sky", languageLabel: "American English · Female", sampleText: sampleText(for: "Sky")),

        .init(voiceName: "am_adam", displayName: "Adam", languageLabel: "American English · Male", sampleText: sampleText(for: "Adam")),
        .init(voiceName: "am_echo", displayName: "Echo", languageLabel: "American English · Male", sampleText: sampleText(for: "Echo")),
        .init(voiceName: "am_eric", displayName: "Eric", languageLabel: "American English · Male", sampleText: sampleText(for: "Eric")),
        .init(voiceName: "am_fenrir", displayName: "Fenrir", languageLabel: "American English · Male", sampleText: sampleText(for: "Fenrir")),
        .init(voiceName: "am_liam", displayName: "Liam", languageLabel: "American English · Male", sampleText: sampleText(for: "Liam")),
        .init(voiceName: "am_michael", displayName: "Michael", languageLabel: "American English · Male", sampleText: sampleText(for: "Michael")),
        .init(voiceName: "am_onyx", displayName: "Onyx", languageLabel: "American English · Male", sampleText: sampleText(for: "Onyx")),
        .init(voiceName: "am_puck", displayName: "Puck", languageLabel: "American English · Male", sampleText: sampleText(for: "Puck")),

        .init(voiceName: "bf_alice", displayName: "Alice", languageLabel: "British English · Female", sampleText: sampleText(for: "Alice")),
        .init(voiceName: "bf_emma", displayName: "Emma", languageLabel: "British English · Female", sampleText: sampleText(for: "Emma")),
        .init(voiceName: "bf_isabella", displayName: "Isabella", languageLabel: "British English · Female", sampleText: sampleText(for: "Isabella")),
        .init(voiceName: "bf_lily", displayName: "Lily", languageLabel: "British English · Female", sampleText: sampleText(for: "Lily")),

        .init(voiceName: "bm_daniel", displayName: "Daniel", languageLabel: "British English · Male", sampleText: sampleText(for: "Daniel")),
        .init(voiceName: "bm_fable", displayName: "Fable", languageLabel: "British English · Male", sampleText: sampleText(for: "Fable")),
        .init(voiceName: "bm_george", displayName: "George", languageLabel: "British English · Male", sampleText: sampleText(for: "George")),
        .init(voiceName: "bm_lewis", displayName: "Lewis", languageLabel: "British English · Male", sampleText: sampleText(for: "Lewis")),

        .init(voiceName: "ef_dora", displayName: "Dora", languageLabel: "Spanish · Female", sampleText: sampleText(for: "Dora")),
        .init(voiceName: "ff_siwis", displayName: "Siwis", languageLabel: "French · Female", sampleText: sampleText(for: "Siwis")),
        .init(voiceName: "if_sara", displayName: "Sara", languageLabel: "Italian · Female", sampleText: sampleText(for: "Sara")),
        .init(voiceName: "im_nicola", displayName: "Nicola", languageLabel: "Italian · Male", sampleText: sampleText(for: "Nicola")),

        .init(voiceName: "jf_alpha", displayName: "Alpha", languageLabel: "Japanese · Female", sampleText: sampleText(for: "Alpha")),
        .init(voiceName: "jf_gongitsune", displayName: "Gongitsune", languageLabel: "Japanese · Female", sampleText: sampleText(for: "Gongitsune")),
        .init(voiceName: "jf_nezumi", displayName: "Nezumi", languageLabel: "Japanese · Female", sampleText: sampleText(for: "Nezumi")),
        .init(voiceName: "jf_tebukuro", displayName: "Tebukuro", languageLabel: "Japanese · Female", sampleText: sampleText(for: "Tebukuro")),
        .init(voiceName: "jm_kumo", displayName: "Kumo", languageLabel: "Japanese · Male", sampleText: sampleText(for: "Kumo")),

        .init(voiceName: "pf_dora", displayName: "Dora", languageLabel: "Portuguese · Female", sampleText: sampleText(for: "Dora")),
        .init(voiceName: "zf_xiaobei", displayName: "Xiaobei", languageLabel: "Chinese · Female", sampleText: sampleText(for: "Xiaobei")),
        .init(voiceName: "zf_xiaoni", displayName: "Xiaoni", languageLabel: "Chinese · Female", sampleText: sampleText(for: "Xiaoni")),
        .init(voiceName: "zf_xiaoxiao", displayName: "Xiaoxiao", languageLabel: "Chinese · Female", sampleText: sampleText(for: "Xiaoxiao")),
        .init(voiceName: "zf_xiaoyi", displayName: "Xiaoyi", languageLabel: "Chinese · Female", sampleText: sampleText(for: "Xiaoyi")),
        .init(voiceName: "zm_yunjian", displayName: "Yunjian", languageLabel: "Chinese · Male", sampleText: sampleText(for: "Yunjian")),
        .init(voiceName: "zm_yunxi", displayName: "Yunxi", languageLabel: "Chinese · Male", sampleText: sampleText(for: "Yunxi")),
        .init(voiceName: "zm_yunxia", displayName: "Yunxia", languageLabel: "Chinese · Male", sampleText: sampleText(for: "Yunxia")),
        .init(voiceName: "zm_yunyang", displayName: "Yunyang", languageLabel: "Chinese · Male", sampleText: sampleText(for: "Yunyang"))
    ]

    static func voice(named name: String) -> KokoroVoiceOption {
        allVoices.first(where: { $0.voiceName == name }) ?? allVoices[0]
    }

    private static func sampleText(for voiceDisplayName: String) -> String {
        "Hello. This is the \(voiceDisplayName) voice preview for Anything Reader."
    }
}

#if canImport(KokoroSwift) && canImport(ZIPFoundation) && canImport(MLX)
import KokoroSwift
import MLX
import ZIPFoundation

// Real Kokoro runtime when the package and model assets are available.
final class KokoroSpeechService {
    static let shared = KokoroSpeechService()

    private let fallbackSynthesizer = AVSpeechSynthesizer()
    private var runtimeEngine: KokoroTTS?
    private var voiceCache: [String: MLXArray] = [:]
    private var audioPlayer: AVAudioPlayer?

    private init() {}

    func playSample(for voice: KokoroVoiceOption) {
        Task {
            await playSampleAsync(for: voice)
        }
    }

    private func playSampleAsync(for voice: KokoroVoiceOption) async {
        do {
            let samples = try await synthesizeSamples(for: voice)
            let wavData = try Self.makeWavData(samples: samples, sampleRate: Double(KokoroTTS.Constants.samplingRate))

            await MainActor.run {
                do {
                    self.audioPlayer = try AVAudioPlayer(data: wavData)
                    self.audioPlayer?.prepareToPlay()
                    self.audioPlayer?.play()
                } catch {
                    self.playFallbackSample(for: voice)
                }
            }
        } catch {
            await MainActor.run {
                self.playFallbackSample(for: voice)
            }
        }
    }

    private func synthesizeSamples(for voice: KokoroVoiceOption) async throws -> [Float] {
        guard let modelURL = Self.locateModelDirectory() else {
            throw KokoroRuntimeError.modelDirectoryMissing
        }

        let engine = try await runtimeEngine(for: modelURL)
        let voiceEmbedding = try await voiceEmbedding(named: voice.voiceName)
        let (samples, _) = try engine.generateAudio(
            voice: voiceEmbedding,
            language: .enUS,
            text: voice.sampleText,
            speed: 0.95
        )
        return samples
    }

    private func runtimeEngine(for modelURL: URL) async throws -> KokoroTTS {
        if let runtimeEngine {
            return runtimeEngine
        }

        let engine = KokoroTTS(modelPath: modelURL, g2p: .misaki)
        runtimeEngine = engine
        return engine
    }

    private func voiceEmbedding(named voiceName: String) async throws -> MLXArray {
        if let cached = voiceCache[voiceName] {
            return cached
        }

        guard let archiveURL = Self.locateVoiceArchive() else {
            throw KokoroRuntimeError.voiceArchiveMissing
        }

        let archive = try Archive(url: archiveURL, accessMode: .read)
        let entryName = "\(voiceName).npy"
        guard let entry = archive[entryName] else {
            throw KokoroRuntimeError.voiceNotFound(voiceName)
        }

        var payload = Data()
        _ = try archive.extract(entry, consumer: { data in
            payload.append(data)
        })

        let voiceEmbedding = try Self.decodeNPY(payload)
        voiceCache[voiceName] = voiceEmbedding
        return voiceEmbedding
    }

    private func playFallbackSample(for voice: KokoroVoiceOption) {
        let utterance = AVSpeechUtterance(string: voice.sampleText)
        utterance.voice = AVSpeechSynthesisVoice(language: voice.previewLanguageCode)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        utterance.pitchMultiplier = 1.0
        utterance.preUtteranceDelay = 0.05
        utterance.postUtteranceDelay = 0.05

        fallbackSynthesizer.stopSpeaking(at: .immediate)
        fallbackSynthesizer.speak(utterance)
    }

    private static func locateModelDirectory() -> URL? {
        let fileManager = FileManager.default
        let candidates: [URL] = [
            Bundle.main.resourceURL?.appendingPathComponent("KokoroModel"),
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("KokoroModel")
        ].compactMap { $0 }

        return candidates.first(where: { fileManager.fileExists(atPath: $0.path) })
    }

    private static func locateVoiceArchive() -> URL? {
        let fileManager = FileManager.default
        let candidates: [URL] = [
            Bundle.main.url(forResource: "voices-v1.0", withExtension: "bin"),
            Bundle.main.resourceURL?.appendingPathComponent("voices-v1.0.bin"),
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("voices-v1.0.bin")
        ].compactMap { $0 }

        return candidates.first(where: { fileManager.fileExists(atPath: $0.path) })
    }

    private static func decodeNPY(_ data: Data) throws -> MLXArray {
        guard data.count >= 10 else {
            throw KokoroRuntimeError.invalidVoiceArchive
        }

        let magic = Array(data.prefix(6))
        guard magic == [0x93, 0x4E, 0x55, 0x4D, 0x50, 0x59] else {
            throw KokoroRuntimeError.invalidVoiceArchive
        }

        let major = data[6]
        let headerLength: Int
        let headerOffset: Int

        switch major {
        case 1:
            headerLength = Int(UInt16(data[8]) | (UInt16(data[9]) << 8))
            headerOffset = 10
        case 2:
            headerLength = Int(UInt32(data[8]) | (UInt32(data[9]) << 8) | (UInt32(data[10]) << 16) | (UInt32(data[11]) << 24))
            headerOffset = 12
        default:
            throw KokoroRuntimeError.invalidVoiceArchive
        }

        guard data.count >= headerOffset + headerLength else {
            throw KokoroRuntimeError.invalidVoiceArchive
        }

        let headerData = data.subdata(in: headerOffset..<(headerOffset + headerLength))
        let headerString = String(decoding: headerData, as: UTF8.self)

        guard headerString.contains("'descr': '<f4'") || headerString.contains("'descr': '|f4'") else {
            throw KokoroRuntimeError.invalidVoiceArchive
        }

        guard let shape = try parseShape(from: headerString) else {
            throw KokoroRuntimeError.invalidVoiceArchive
        }

        let payloadStart = headerOffset + headerLength
        let payload = data.subdata(in: payloadStart..<data.count)
        let expectedFloatCount = shape.reduce(1, *)
        guard payload.count == expectedFloatCount * MemoryLayout<Float32>.size else {
            throw KokoroRuntimeError.invalidVoiceArchive
        }

        var floats: [Float32] = []
        floats.reserveCapacity(expectedFloatCount)

        var index = payload.startIndex
        while index < payload.endIndex {
            let rawBits = payload[index..<(index + 4)].withUnsafeBytes { rawBytes -> UInt32 in
                rawBytes.load(as: UInt32.self)
            }
            floats.append(Float32(bitPattern: UInt32(littleEndian: rawBits)))
            index += 4
        }

        return MLXArray(floats).reshaped(shape)
    }

    private static func parseShape(from header: String) throws -> [Int]? {
        guard let shapeStart = header.range(of: "'shape': (") else {
            return nil
        }

        let tail = header[shapeStart.upperBound...]
        guard let shapeEnd = tail.firstIndex(of: ")") else {
            return nil
        }

        let shapeText = tail[..<shapeEnd]
        let dimensions = shapeText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap(Int.init)

        return dimensions.isEmpty ? nil : dimensions
    }

    private static func makeWavData(samples: [Float], sampleRate: Double) throws -> Data {
        let bytesPerSample = MemoryLayout<Float32>.size
        let dataChunkSize = samples.count * bytesPerSample
        let riffChunkSize = 36 + dataChunkSize

        var data = Data()
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // RIFF
        data.append(contentsOf: UInt32(riffChunkSize).littleEndianBytes)
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // WAVE
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // fmt 
        data.append(contentsOf: UInt32(16).littleEndianBytes)
        data.append(contentsOf: UInt16(3).littleEndianBytes) // IEEE float
        data.append(contentsOf: UInt16(1).littleEndianBytes) // mono
        data.append(contentsOf: UInt32(sampleRate).littleEndianBytes)
        data.append(contentsOf: UInt32(sampleRate * Double(bytesPerSample)).littleEndianBytes)
        data.append(contentsOf: UInt16(bytesPerSample).littleEndianBytes)
        data.append(contentsOf: UInt16(32).littleEndianBytes)
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // data
        data.append(contentsOf: UInt32(dataChunkSize).littleEndianBytes)

        for sample in samples {
            var littleEndianSample = sample.bitPattern.littleEndian
            withUnsafeBytes(of: &littleEndianSample) { data.append(contentsOf: $0) }
        }

        return data
    }

    enum KokoroRuntimeError: Error {
        case modelDirectoryMissing
        case voiceArchiveMissing
        case voiceNotFound(String)
        case invalidVoiceArchive
    }
}

private extension FixedWidthInteger {
    var littleEndianBytes: [UInt8] {
        withUnsafeBytes(of: self.littleEndian) { Array($0) }
    }
}

#else

// Fallback preview so the Settings surface still works if the Kokoro package is unavailable.
final class KokoroSpeechService {
    static let shared = KokoroSpeechService()

    private let synthesizer = AVSpeechSynthesizer()

    private init() {}

    func playSample(for voice: KokoroVoiceOption) {
        let utterance = AVSpeechUtterance(string: voice.sampleText)
        utterance.voice = AVSpeechSynthesisVoice(language: voice.previewLanguageCode)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        utterance.pitchMultiplier = 1.0
        utterance.preUtteranceDelay = 0.05
        utterance.postUtteranceDelay = 0.05

        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance)
    }
}

#endif
