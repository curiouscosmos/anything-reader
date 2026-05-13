//
//  ReaderTTSModels.swift
//  Anything Reader
//
//  Shared TTS provider types used to keep Kokoro and Moonshine pluggable.
//

import Foundation
import Combine

enum ReaderTTSProviderID: String, CaseIterable, Identifiable, Codable, Sendable {
    case kokoro
    case moonshine
    case supertonic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .kokoro:
            return "Kokoro"
        case .moonshine:
            return "Moonshine"
        case .supertonic:
            return "Supertonic"
        }
    }
}

@MainActor
final class ReaderTTSCoordinator: ObservableObject {
    static let shared = ReaderTTSCoordinator()

    @Published private(set) var activeProviderID: ReaderTTSProviderID
    @Published private(set) var availabilityStatus: ReaderTTSModelAvailability = .checking

    private let activeProviderStorageKey = "activeTTSProviderID"
    private let kokoroVoiceStorageKey = "kokoroVoiceName"
    private let moonshineVoiceStorageKey = "moonshineVoiceName"
    private let supertonicVoiceStorageKey = "supertonicVoiceName"

    private init() {
        if let storedProvider = UserDefaults.standard.string(forKey: activeProviderStorageKey),
           let providerID = ReaderTTSProviderID(rawValue: storedProvider) {
            activeProviderID = providerID
        } else {
            activeProviderID = .kokoro
        }

        refreshInstallationStatus()
    }

    var kokoroStore: KokoroModelStore {
        .shared
    }

    var moonshineStore: MoonshineModelStore {
        .shared
    }

    var supertonicStore: SupertonicModelStore {
        .shared
    }

    func refreshInstallationStatus() {
        kokoroStore.refreshInstallationStatus()
        moonshineStore.refreshInstallationStatus()
        supertonicStore.refreshInstallationStatus()

        if let installedProvider = preferredInstalledProvider() {
            if activeProviderID != installedProvider {
                activeProviderID = installedProvider
                storeActiveProvider(installedProvider)
            }
            availabilityStatus = .installed(installedProvider)
            return
        }

        if isAnyProviderDownloading {
            availabilityStatus = .downloading(activeProviderID)
        } else {
            availabilityStatus = .notInstalled
        }
    }

    func setActiveProvider(_ providerID: ReaderTTSProviderID) {
        activeProviderID = providerID
        storeActiveProvider(providerID)
        refreshInstallationStatus()
    }

    func selectedVoiceName(for providerID: ReaderTTSProviderID) -> String {
        let storedValue: String?
        switch providerID {
        case .kokoro:
            storedValue = UserDefaults.standard.string(forKey: kokoroVoiceStorageKey)
        case .moonshine:
            storedValue = UserDefaults.standard.string(forKey: moonshineVoiceStorageKey)
        case .supertonic:
            storedValue = UserDefaults.standard.string(forKey: supertonicVoiceStorageKey)
        }

        switch providerID {
        case .kokoro:
            return KokoroVoiceCatalog.allVoices.contains(where: { $0.voiceName == storedValue }) ? storedValue ?? KokoroVoiceCatalog.defaultVoiceName : KokoroVoiceCatalog.defaultVoiceName
        case .moonshine:
            return MoonshineVoiceCatalog.allVoices.contains(where: { $0.voiceName == storedValue }) ? storedValue ?? MoonshineVoiceCatalog.defaultVoiceName : MoonshineVoiceCatalog.defaultVoiceName
        case .supertonic:
            return SupertonicVoiceCatalog.allVoices.contains(where: { $0.voiceName == storedValue }) ? storedValue ?? SupertonicVoiceCatalog.defaultVoiceName : SupertonicVoiceCatalog.defaultVoiceName
        }
    }

    func setSelectedVoiceName(_ voiceName: String, for providerID: ReaderTTSProviderID) {
        switch providerID {
        case .kokoro:
            UserDefaults.standard.set(voiceName, forKey: kokoroVoiceStorageKey)
        case .moonshine:
            UserDefaults.standard.set(voiceName, forKey: moonshineVoiceStorageKey)
        case .supertonic:
            UserDefaults.standard.set(voiceName, forKey: supertonicVoiceStorageKey)
        }
    }

    func activeVoiceSelection() -> ReaderTTSVoiceSelection {
        voiceSelection(for: activeProviderID)
    }

    func voiceSelection(for providerID: ReaderTTSProviderID) -> ReaderTTSVoiceSelection {
        switch providerID {
        case .kokoro:
            return KokoroVoiceCatalog.voice(named: selectedVoiceName(for: .kokoro)).readerTTSVoiceSelection
        case .moonshine:
            return MoonshineVoiceCatalog.voice(named: selectedVoiceName(for: .moonshine))
        case .supertonic:
            return SupertonicVoiceCatalog.voice(named: selectedVoiceName(for: .supertonic))
        }
    }

    func availableVoiceOptions(for providerID: ReaderTTSProviderID) -> [ReaderTTSVoiceSelection] {
        switch providerID {
        case .kokoro:
            return KokoroVoiceCatalog.allVoices.map(\.readerTTSVoiceSelection)
        case .moonshine:
            return MoonshineVoiceCatalog.allVoices
        case .supertonic:
            return SupertonicVoiceCatalog.allVoices
        }
    }

    func playSample(for voice: ReaderTTSVoiceSelection) {
        switch voice.providerID {
        case .kokoro:
            let kokoroVoice = KokoroVoiceCatalog.voice(named: voice.voiceName)
            KokoroSpeechService.shared.prepareForPlayback()
            KokoroSpeechService.shared.playSample(for: kokoroVoice)
        case .moonshine:
            MoonshineSpeechService.shared.prepareForPlayback()
            MoonshineSpeechService.shared.playSample(for: voice)
        case .supertonic:
            SupertonicSpeechService.shared.prepareForPlayback()
            SupertonicSpeechService.shared.playSample(for: voice)
        }
    }

    func synthesize(text: String, voice: ReaderTTSVoiceSelection, language: TextLanguage? = nil) async throws -> URL {
        switch voice.providerID {
        case .kokoro:
            let kokoroVoice = KokoroVoiceCatalog.voice(named: voice.voiceName)
            return try await KokoroSpeechService.shared.synthesize(text: text, voice: kokoroVoice)
        case .moonshine:
            return try await MoonshineSpeechService.shared.synthesize(text: text, voice: voice)
        case .supertonic:
            return try await SupertonicSpeechService.shared.synthesize(text: text, voice: voice, language: language)
        }
    }

    private var isAnyProviderDownloading: Bool {
        if case .downloading = kokoroStore.status { return true }
        if case .downloading = moonshineStore.status { return true }
        if case .downloading = supertonicStore.status { return true }
        return false
    }

    private func preferredInstalledProvider() -> ReaderTTSProviderID? {
        if case .installed = status(from: activeProviderID) {
            return activeProviderID
        }

        if case .installed = kokoroStore.status {
            return .kokoro
        }

        if case .installed = moonshineStore.status {
            return .moonshine
        }

        if case .installed = supertonicStore.status {
            return .supertonic
        }

        return nil
    }

    private func status(from providerID: ReaderTTSProviderID) -> ReaderTTSModelAvailability {
        switch providerID {
        case .kokoro:
            switch kokoroStore.status {
            case .checking:
                return .checking
            case .notInstalled:
                return .notInstalled
            case .downloading:
                return .downloading(.kokoro)
            case .installed:
                return .installed(.kokoro)
            case .failed(let message):
                return .failed(message)
            }
        case .moonshine:
            switch moonshineStore.status {
            case .checking:
                return .checking
            case .notInstalled:
                return .notInstalled
            case .downloading:
                return .downloading(.moonshine)
            case .installed:
                return .installed(.moonshine)
            case .failed(let message):
                return .failed(message)
            }
        case .supertonic:
            switch supertonicStore.status {
            case .checking:
                return .checking
            case .notInstalled:
                return .notInstalled
            case .downloading:
                return .downloading(.supertonic)
            case .installed:
                return .installed(.supertonic)
            case .failed(let message):
                return .failed(message)
            }
        }
    }

    private func storeActiveProvider(_ providerID: ReaderTTSProviderID) {
        UserDefaults.standard.set(providerID.rawValue, forKey: activeProviderStorageKey)
    }
}

enum ReaderTTSModelAvailability: Equatable {
    case checking
    case notInstalled
    case downloading(ReaderTTSProviderID)
    case installed(ReaderTTSProviderID)
    case failed(String)
}

struct ReaderTTSVoiceSelection: Identifiable, Hashable, Sendable {
    let providerID: ReaderTTSProviderID
    let voiceName: String
    let displayName: String
    let languageLabel: String
    let sampleText: String
    let genderLabel: String
    let accentLabel: String?
    let isRecommended: Bool

    var id: String {
        "\(providerID.rawValue)-\(voiceName)"
    }

    var dropdownLabel: String {
        if let accentLabel, !accentLabel.isEmpty {
            return "\(displayName) - \(languageLabel) [\(accentLabel)]"
        } else {
            return "\(displayName) - \(languageLabel)"
        }
    }

    var genderSymbol: String {
        genderLabel.lowercased().contains("female") ? "♀" : "♂"
    }
}

extension KokoroVoiceOption {
    var readerTTSVoiceSelection: ReaderTTSVoiceSelection {
        ReaderTTSVoiceSelection(
            providerID: .kokoro,
            voiceName: voiceName,
            displayName: displayName,
            languageLabel: languageLabel,
            sampleText: sampleText,
            genderLabel: genderLabel,
            accentLabel: accentLabel,
            isRecommended: voiceName == KokoroVoiceCatalog.defaultVoiceName
        )
    }
}

enum MoonshineVoiceCatalog {
    static let defaultVoiceName = "kokoro_af_bella"

    static let allVoices: [ReaderTTSVoiceSelection] = KokoroVoiceCatalog.allVoices.map { voice in
        ReaderTTSVoiceSelection(
            providerID: .moonshine,
            voiceName: "kokoro_\(voice.voiceName)",
            displayName: voice.displayName,
            languageLabel: voice.languageLabel,
            sampleText: voice.sampleText,
            genderLabel: voice.genderLabel,
            accentLabel: voice.accentLabel,
            isRecommended: voice.voiceName == KokoroVoiceCatalog.defaultVoiceName
        )
    }

    static func voice(named name: String) -> ReaderTTSVoiceSelection {
        allVoices.first(where: { $0.voiceName == name }) ?? allVoices[0]
    }

    static func languageCode(for voice: ReaderTTSVoiceSelection) -> String {
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
