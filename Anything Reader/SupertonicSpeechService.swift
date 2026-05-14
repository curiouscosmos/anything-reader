//
//  SupertonicSpeechService.swift
//  Anything Reader
//
//  Thin Swift wrapper over the Objective-C++ Supertonic bridge.
//

import AVFoundation
import Foundation
import Combine

enum SupertonicLanguageCatalog {
    static func languageCode(for language: TextLanguage?) -> String {
        switch language ?? .english {
        case .english:
            return "en"
        case .korean:
            return "ko"
        case .japanese:
            return "ja"
        case .arabic:
            return "ar"
        case .german:
            return "de"
        case .greek:
            return "el"
        case .spanish:
            return "es"
        case .french:
            return "fr"
        case .hindi:
            return "hi"
        case .indonesian:
            return "id"
        case .italian:
            return "it"
        case .dutch:
            return "nl"
        case .polish:
            return "pl"
        case .portuguese:
            return "pt"
        case .romanian:
            return "ro"
        case .russian:
            return "ru"
        case .swedish:
            return "sv"
        case .turkish:
            return "tr"
        case .ukrainian:
            return "uk"
        case .vietnamese:
            return "vi"
        case .mandarin, .hebrew, .persian, .urdu, .marathi, .bengali, .punjabi, .tamil, .telugu, .thai, .malay, .unknown:
            return "en"
        }
    }
}

enum SupertonicVoiceCatalog {
    static let defaultVoiceName = "M1"

    static let allVoices: [ReaderTTSVoiceSelection] = [
        makeVoice(name: "M1", gender: "Male", isRecommended: true),
        makeVoice(name: "M2", gender: "Male"),
        makeVoice(name: "M3", gender: "Male"),
        makeVoice(name: "M4", gender: "Male"),
        makeVoice(name: "M5", gender: "Male"),
        makeVoice(name: "F1", gender: "Female"),
        makeVoice(name: "F2", gender: "Female"),
        makeVoice(name: "F3", gender: "Female"),
        makeVoice(name: "F4", gender: "Female"),
        makeVoice(name: "F5", gender: "Female")
    ]

    static func voice(named name: String) -> ReaderTTSVoiceSelection {
        allVoices.first(where: { $0.voiceName == name }) ?? allVoices[0]
    }

    private static func makeVoice(name: String, gender: String, isRecommended: Bool = false) -> ReaderTTSVoiceSelection {
        ReaderTTSVoiceSelection(
            providerID: .supertonic,
            voiceName: name,
            displayName: name,
            languageLabel: "Multilingual",
            sampleText: "Hello. This is the \(name) voice preview for Anything Reader.",
            genderLabel: gender,
            accentLabel: nil,
            isRecommended: isRecommended
        )
    }
}

@MainActor
final class SupertonicSpeechService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = SupertonicSpeechService()

    private let runtime = SupertonicSpeechRenderer()
    private var audioPlayer: AVAudioPlayer?
    @Published private(set) var isPlaying = false

    override private init() {}

    func prepareForPlayback() {
        isPlaying = true
    }

    func playSample(for voice: ReaderTTSVoiceSelection) {
        guard voice.providerID == .supertonic else { return }

        Task {
            do {
                let outputURL = try await synthesize(text: voice.sampleText, voice: voice, language: .english)
                try await MainActor.run {
                    try playAudioFile(at: outputURL)
                }
            } catch {
                await MainActor.run {
                    self.isPlaying = false
                }
                NSLog("Supertonic sample playback failed: %@", error.localizedDescription)
            }
        }
    }

    func synthesize(text: String, voice: ReaderTTSVoiceSelection, language: TextLanguage? = nil) async throws -> URL {
        guard voice.providerID == .supertonic else {
            throw CocoaError(.fileNoSuchFile)
        }

        let languageCode = SupertonicLanguageCatalog.languageCode(for: language)
        return try await runtime.synthesize(text: text, voice: voice, languageCode: languageCode)
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

actor SupertonicSpeechRenderer {
    func synthesize(text: String, voice: ReaderTTSVoiceSelection, languageCode: String) async throws -> URL {
        try await SupertonicModelStore.shared.ensureInstalled()

        guard let modelRootURL = await MainActor.run(body: { SupertonicModelStore.shared.modelURL() }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try supertonicSynthesize(
            text: text,
            voiceName: voice.voiceName,
            languageCode: languageCode,
            modelRootURL: modelRootURL
        )
    }

    private func supertonicSynthesize(
        text: String,
        voiceName: String,
        languageCode: String,
        modelRootURL: URL
    ) throws -> URL {
        guard let bridgeClass = NSClassFromString("SupertonicONNXBridge") else {
            throw CocoaError(.fileNoSuchFile)
        }

        let sharedSelector = NSSelectorFromString("sharedBridge")
        let bridgeClassObject = bridgeClass as AnyObject
        guard let sharedBridgeUnretained = bridgeClassObject.perform(sharedSelector)?.takeUnretainedValue() else {
            throw CocoaError(.fileNoSuchFile)
        }

        let synthesizeSelector = NSSelectorFromString("synthesizeText:voiceName:languageCode:modelRootURL:error:")
        typealias BridgeFunction = @convention(c) (
            AnyObject,
            Selector,
            NSString,
            NSString,
            NSString,
            NSURL,
            AutoreleasingUnsafeMutablePointer<NSError?>
        ) -> NSURL?

        let bridgeFunction = unsafeBitCast(sharedBridgeUnretained.method(for: synthesizeSelector), to: BridgeFunction.self)
        var bridgeError: NSError?
        let outputURL = bridgeFunction(
            sharedBridgeUnretained,
            synthesizeSelector,
            text as NSString,
            voiceName as NSString,
            languageCode as NSString,
            modelRootURL as NSURL,
            &bridgeError
        )

        if let outputURL {
            return outputURL as URL
        }

        throw bridgeError ?? CocoaError(.fileReadUnknown)
    }
}
