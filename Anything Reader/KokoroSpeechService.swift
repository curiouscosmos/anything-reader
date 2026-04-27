//
//  KokoroSpeechService.swift
//  Anything Reader
//
//  Lightweight fallback voice service used when the Kokoro runtime is not
//  active in the app bundle.
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

// Fallback preview so the Settings surface still works without the Kokoro runtime.
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
