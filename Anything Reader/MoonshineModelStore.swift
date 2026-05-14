//
//  MoonshineModelStore.swift
//  Anything Reader
//
//  Tracks the Moonshine TTS asset tree and downloads the missing files into
//  Application Support so the runtime can boot from a real directory layout.
//

import Combine
import Foundation
import MoonshineVoice

struct MoonshineDownloadOption: Identifiable, Hashable, Equatable {
    let localFileName: String
    let displayName: String
    let qualityLabel: String
    let downloadURL: URL
    let isRecommended: Bool

    var id: String { localFileName }

    var subtitle: String {
        isRecommended ? "\(qualityLabel)" : qualityLabel
    }
}

enum MoonshineDownloadCatalog {
    static let allOptions: [MoonshineDownloadOption] = [
        .init(
            localFileName: "moonshine.safetensors",
            displayName: "Moonshine",
            qualityLabel: "250M good quality, 8-languages, 45-voices",
            downloadURL: URL(string: "https://sandalbar.s3.us-west-2.amazonaws.com/TTS/moonshine.safetensors")!,
            isRecommended: false
        )
    ]

    static let defaultOption = allOptions[0]
}

@MainActor
final class MoonshineModelStore: ObservableObject {
    enum Status: Equatable {
        case checking
        case notInstalled
        case downloading(MoonshineDownloadOption)
        case installed(MoonshineDownloadOption)
        case failed(String)
    }

    static let shared = MoonshineModelStore()

    @Published private(set) var status: Status = .checking
    @Published private(set) var activeModelFileName: String?

    private let selectedModelStorageKey = "moonshineSelectedModelFileName"
    private var downloadTask: Task<Void, Never>?

    private init() {
        activeModelFileName = UserDefaults.standard.string(forKey: selectedModelStorageKey)
        refreshInstallationStatus()
    }

    var isInstalled: Bool {
        if case .installed = status {
            return true
        }
        return false
    }

    var installedOptions: [MoonshineDownloadOption] {
        assetTreeIsInstalled() ? MoonshineDownloadCatalog.allOptions : []
    }

    var selectedOption: MoonshineDownloadOption? {
        assetTreeIsInstalled() ? MoonshineDownloadCatalog.defaultOption : nil
    }

    func refreshInstallationStatus() {
        if assetTreeIsInstalled() {
            let option = MoonshineDownloadCatalog.defaultOption
            activeModelFileName = option.localFileName
            storeSelectedOption(option)
            status = .installed(option)
        } else if case .downloading = status {
            return
        } else {
            activeModelFileName = nil
            UserDefaults.standard.removeObject(forKey: selectedModelStorageKey)
            status = .notInstalled
        }
    }

    func activateDownloadedModel(_ option: MoonshineDownloadOption) {
        guard assetTreeIsInstalled() else { return }
        activeModelFileName = option.localFileName
        storeSelectedOption(option)
        status = .installed(option)
    }

    func deactivateDownloadedModel(_ option: MoonshineDownloadOption) {
        guard selectedOption?.localFileName == option.localFileName else { return }

        let remainingOptions = installedOptions.filter { $0.localFileName != option.localFileName }
        if let nextOption = remainingOptions.first {
            activeModelFileName = nextOption.localFileName
            storeSelectedOption(nextOption)
            status = .installed(nextOption)
        } else {
            activeModelFileName = nil
            UserDefaults.standard.removeObject(forKey: selectedModelStorageKey)
            status = .notInstalled
        }
    }

    func deleteDownloadedModel(_ option: MoonshineDownloadOption) {
        let directory = modelDirectory()
        guard fileManager().fileExists(atPath: directory.path) else { return }

        try? fileManager().removeItem(at: directory)
        activeModelFileName = nil
        UserDefaults.standard.removeObject(forKey: selectedModelStorageKey)
        refreshInstallationStatus()
    }

    func downloadModel(option: MoonshineDownloadOption) {
        guard downloadTask == nil else { return }

        if assetTreeIsInstalled() {
            activateDownloadedModel(option)
            return
        }

        status = .downloading(option)

        downloadTask = Task {
            defer {
                Task { @MainActor in
                    self.downloadTask = nil
                }
            }

            do {
                try await downloadAndInstallDefaultAssets()
                await MainActor.run {
                    let installedOption = MoonshineDownloadCatalog.defaultOption
                    self.activeModelFileName = installedOption.localFileName
                    self.storeSelectedOption(installedOption)
                    self.status = .installed(installedOption)
                }
            } catch {
                await MainActor.run {
                    self.status = .failed(error.localizedDescription)
                }
            }
        }
    }

    func ensureInstalled(for voice: ReaderTTSVoiceSelection) async throws {
        if assetTreeIsInstalled(for: voice) {
            return
        }

        if let downloadTask {
            await downloadTask.value
            if assetTreeIsInstalled(for: voice) {
                return
            }
        }

        try await downloadDependencies(for: voice)
        await MainActor.run {
            let installedOption = MoonshineDownloadCatalog.defaultOption
            self.activeModelFileName = installedOption.localFileName
            self.storeSelectedOption(installedOption)
            self.status = .installed(installedOption)
        }
    }

    func modelURL() -> URL? {
        assetTreeIsInstalled() ? modelDirectory() : nil
    }

    func assetRootURL() -> URL {
        modelDirectory()
    }

    func isOptionDownloaded(_ option: MoonshineDownloadOption) -> Bool {
        assetTreeIsInstalled()
    }

    private func downloadAndInstallDefaultAssets() async throws {
        try await downloadDependencies(for: MoonshineVoiceCatalog.voice(named: MoonshineVoiceCatalog.defaultVoiceName))
    }

    private func downloadDependencies(for voice: ReaderTTSVoiceSelection) async throws {
        let root = modelDirectory()
        try fileManager().createDirectory(at: root, withIntermediateDirectories: true)

        let language = MoonshineVoiceCatalog.languageCode(for: voice)
        let dependencyPaths = try dependencyPaths(for: language, voiceName: voice.voiceName, root: root)
        let uniquePaths = Array(Set(dependencyPaths)).sorted()

        for dependencyPath in uniquePaths {
            let destination = localURL(for: dependencyPath)
            if fileManager().fileExists(atPath: destination.path) {
                continue
            }

            try fileManager().createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let remoteURL = try remoteURL(for: dependencyPath)
            let (temporaryURL, response) = try await URLSession.shared.download(from: remoteURL)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw CocoaError(.fileReadUnknown)
            }

            if fileManager().fileExists(atPath: destination.path) {
                try fileManager().removeItem(at: destination)
            }

            try fileManager().moveItem(at: temporaryURL, to: destination)
        }

        do {
            try await downloadFallbackModelIfNeeded()
        } catch {
            NSLog("Moonshine fallback model download failed: %@", error.localizedDescription)
        }
    }

    private func dependencyPaths(for language: String, voiceName: String, root: URL) throws -> [String] {
        let json = try TextToSpeech.getDependencies(
            languages: language,
            options: [
                TranscriberOption(name: "tts_root", value: root.path),
                TranscriberOption(name: "voice", value: voiceName)
            ]
        )

        guard let data = json.data(using: .utf8) else {
            return []
        }

        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return Self.extractDependencyPaths(from: jsonObject)
    }

    private static func extractDependencyPaths(from object: Any) -> [String] {
        if let string = object as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [trimmed]
        }

        if let array = object as? [Any] {
            return array.flatMap { extractDependencyPaths(from: $0) }
        }

        if let dictionary = object as? [String: Any] {
            let directKeys = ["path", "file", "relativePath", "name", "id", "key", "url"]
            let directValues = directKeys.compactMap { key in
                dictionary[key] as? String
            }

            if !directValues.isEmpty {
                return directValues.flatMap { extractDependencyPaths(from: $0) }
            }

            return dictionary.values.flatMap { extractDependencyPaths(from: $0) }
        }

        return []
    }

    private func assetTreeIsInstalled(for voice: ReaderTTSVoiceSelection? = nil) -> Bool {
        let root = modelDirectory()
        guard fileManager().fileExists(atPath: root.path) else { return false }

        let language = MoonshineVoiceCatalog.languageCode(
            for: voice ?? MoonshineVoiceCatalog.voice(named: MoonshineVoiceCatalog.defaultVoiceName)
        )

        guard let dependencyPaths = try? dependencyPaths(
            for: language,
            voiceName: voice?.voiceName ?? MoonshineVoiceCatalog.defaultVoiceName,
            root: root
        ) else {
            return fileManager().fileExists(atPath: root.appendingPathComponent("kokoro").appendingPathComponent("config.json").path)
        }

        guard !dependencyPaths.isEmpty else {
            return fileManager().fileExists(atPath: root.appendingPathComponent("kokoro").appendingPathComponent("config.json").path)
        }

        return dependencyPaths.allSatisfy { dependencyPath in
            fileManager().fileExists(atPath: localURL(for: dependencyPath).path)
        }
    }

    private func downloadFallbackModelIfNeeded() async throws {
        let fallback = MoonshineDownloadCatalog.defaultOption
        let destination = modelDirectory().appendingPathComponent(fallback.localFileName)

        guard !fileManager().fileExists(atPath: destination.path) else {
            return
        }

        let (temporaryURL, response) = try await URLSession.shared.download(from: fallback.downloadURL)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw CocoaError(.fileReadUnknown)
        }

        if fileManager().fileExists(atPath: destination.path) {
            try fileManager().removeItem(at: destination)
        }

        try fileManager().createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager().moveItem(at: temporaryURL, to: destination)
    }

    private func localURL(for relativePath: String) -> URL {
        relativePath
            .split(separator: "/")
            .reduce(modelDirectory()) { partialResult, component in
                partialResult.appendingPathComponent(String(component), isDirectory: false)
            }
    }

    private func remoteURL(for relativePath: String) throws -> URL {
        let encodedPath = relativePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? relativePath
        guard let url = URL(string: "https://download.moonshine.ai/tts/\(encodedPath)") else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        return url
    }

    private func modelDirectory() -> URL {
        let supportDirectory = fileManager().urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        return supportDirectory
            .appendingPathComponent("Anything Reader", isDirectory: true)
            .appendingPathComponent("MoonshineModel", isDirectory: true)
    }

    private func storeSelectedOption(_ option: MoonshineDownloadOption) {
        UserDefaults.standard.set(option.localFileName, forKey: selectedModelStorageKey)
    }

    private func fileManager() -> FileManager {
        .default
    }
}
