//
//  SupertonicModelStore.swift
//  Anything Reader
//
//  Tracks the downloaded Supertonic model bundle and installs the zip payload
//  into Application Support so the local ONNX runtime can load it.
//

import Combine
import Foundation
import ZIPFoundation

struct SupertonicDownloadOption: Identifiable, Hashable, Equatable {
    let localFileName: String
    let displayName: String
    let qualityLabel: String
    let downloadURL: URL
    let isRecommended: Bool

    var id: String { localFileName }

    var subtitle: String {
        isRecommended ? "\(qualityLabel) · Recommended" : qualityLabel
    }
}

enum SupertonicDownloadCatalog {
    static let allOptions: [SupertonicDownloadOption] = [
        .init(
            localFileName: "supertonic-3",
            displayName: "Supertonic",
            qualityLabel: "66M fastest & lightest, 31-languages, 6-voices",
            downloadURL: URL(string: "https://sandalbar.s3.us-west-2.amazonaws.com/TTS/superstonic.zip")!,
            isRecommended: true
        )
    ]

    static let defaultOption = allOptions[0]
}

@MainActor
final class SupertonicModelStore: ObservableObject {
    enum Status: Equatable {
        case checking
        case notInstalled
        case downloading(SupertonicDownloadOption)
        case installed(SupertonicDownloadOption)
        case failed(String)
    }

    static let shared = SupertonicModelStore()

    @Published private(set) var status: Status = .checking
    @Published private(set) var activeModelFileName: String?

    private let selectedModelStorageKey = "supertonicSelectedModelFileName"
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

    var installedOptions: [SupertonicDownloadOption] {
        runtimeRootURL() != nil ? [SupertonicDownloadCatalog.defaultOption] : []
    }

    var selectedOption: SupertonicDownloadOption? {
        runtimeRootURL() != nil ? SupertonicDownloadCatalog.defaultOption : nil
    }

    func refreshInstallationStatus() {
        if let installed = selectedOption, isOptionDownloaded(installed) {
            activeModelFileName = installed.localFileName
            storeSelectedOption(installed)
            status = .installed(installed)
            return
        }

        if case .downloading = status {
            return
        }

        activeModelFileName = nil
        UserDefaults.standard.removeObject(forKey: selectedModelStorageKey)
        status = .notInstalled
    }

    func ensureInstalled() async throws {
        if runtimeRootURL() != nil {
            return
        }

        if let downloadTask {
            await downloadTask.value
            if runtimeRootURL() != nil {
                return
            }
        }

        try await downloadAndInstallModel(option: SupertonicDownloadCatalog.defaultOption)
        await MainActor.run {
            if let installed = self.selectedOption, self.isOptionDownloaded(installed) {
                self.activeModelFileName = installed.localFileName
                self.storeSelectedOption(installed)
                self.status = .installed(installed)
            } else {
                self.status = .failed("Downloaded Supertonic bundle could not be verified.")
            }
        }
    }

    func activateDownloadedModel(_ option: SupertonicDownloadOption) {
        guard isOptionDownloaded(option) else { return }
        activeModelFileName = option.localFileName
        storeSelectedOption(option)
        status = .installed(option)
    }

    func deactivateDownloadedModel(_ option: SupertonicDownloadOption) {
        guard selectedOption?.localFileName == option.localFileName else { return }

        activeModelFileName = nil
        UserDefaults.standard.removeObject(forKey: selectedModelStorageKey)
        status = isOptionDownloaded(option) ? .installed(option) : .notInstalled
    }

    func deleteDownloadedModel(_ option: SupertonicDownloadOption) {
        let directory = modelDirectory()
        guard fileManager().fileExists(atPath: directory.path) else { return }

        try? fileManager().removeItem(at: directory)
        activeModelFileName = nil
        UserDefaults.standard.removeObject(forKey: selectedModelStorageKey)
        refreshInstallationStatus()
    }

    func downloadModel(option: SupertonicDownloadOption) {
        guard downloadTask == nil else { return }

        if isOptionDownloaded(option) {
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
                try await downloadAndInstallModel(option: option)
                await MainActor.run {
                    if let installed = self.selectedOption, self.isOptionDownloaded(installed) {
                        self.activeModelFileName = installed.localFileName
                        self.storeSelectedOption(installed)
                        self.status = .installed(installed)
                    } else {
                        self.status = .failed("Downloaded Supertonic bundle could not be verified.")
                    }
                }
            } catch {
                await MainActor.run {
                    self.status = .failed(error.localizedDescription)
                }
            }
        }
    }

    func modelURL() -> URL? {
        runtimeRootURL()
    }

    func assetRootURL() -> URL? {
        runtimeRootURL()
    }

    func isOptionDownloaded(_ option: SupertonicDownloadOption) -> Bool {
        runtimeRootURL() != nil
    }

    private func downloadAndInstallModel(option: SupertonicDownloadOption) async throws {
        let (temporaryURL, response) = try await URLSession.shared.download(from: option.downloadURL)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw CocoaError(.fileReadUnknown)
        }

        let destination = modelDirectory()
        try fileManager().createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager().fileExists(atPath: destination.path) {
            try fileManager().removeItem(at: destination)
        }

        try fileManager().createDirectory(at: destination, withIntermediateDirectories: true)
        try fileManager().unzipItem(at: temporaryURL, to: destination)
        try? fileManager().removeItem(at: temporaryURL)

        guard runtimeRootURL() != nil else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    private func runtimeRootURL() -> URL? {
        let root = modelDirectory()
        if isRuntimeBundle(at: root) {
            return root
        }

        guard fileManager().fileExists(atPath: root.path) else {
            return nil
        }

        let enumerator = fileManager().enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        while let candidate = enumerator?.nextObject() as? URL {
            if candidate.hasDirectoryPath, isRuntimeBundle(at: candidate) {
                return candidate
            }
        }

        return nil
    }

    private func isRuntimeBundle(at url: URL) -> Bool {
        let configExists = fileExists(at: url.appendingPathComponent("config.json"))
            || fileExists(at: url.appendingPathComponent("tts.json"))
            || fileExists(at: url.appendingPathComponent("onnx", isDirectory: true).appendingPathComponent("tts.json"))
        let onnxExists = fileManager().fileExists(atPath: url.appendingPathComponent("onnx", isDirectory: true).path)
        let voiceStylesExists = fileManager().fileExists(atPath: url.appendingPathComponent("voice_styles", isDirectory: true).path)
        return configExists && onnxExists && voiceStylesExists
    }

    private func fileExists(at url: URL) -> Bool {
        fileManager().fileExists(atPath: url.path)
    }

    private func modelDirectory() -> URL {
        let supportDirectory = fileManager().urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        return supportDirectory
            .appendingPathComponent("Anything Reader", isDirectory: true)
            .appendingPathComponent("SupertonicModel", isDirectory: true)
    }

    private func storeSelectedOption(_ option: SupertonicDownloadOption) {
        UserDefaults.standard.set(option.localFileName, forKey: selectedModelStorageKey)
    }

    private func fileManager() -> FileManager {
        .default
    }
}
