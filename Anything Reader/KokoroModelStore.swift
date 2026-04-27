//
//  KokoroModelStore.swift
//  Anything Reader
//
//  Tracks whether the Kokoro MLX weights are present locally and downloads them
//  into Application Support when the user asks for offline Kokoro playback.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class KokoroModelStore: ObservableObject {
    enum Status: Equatable {
        case checking
        case notInstalled
        case downloading
        case installed
        case failed(String)
    }

    static let shared = KokoroModelStore()

    @Published private(set) var status: Status = .checking

    private let modelFileName = "kokoro-v1_0.safetensors"
    private let downloadURLs: [URL] = [
        URL(string: "https://sandalbar.s3.us-west-2.amazonaws.com/kokoro-v1_0.safetensors")!
    ]
    private var downloadTask: Task<Void, Never>?

    private init() {
        refreshInstallationStatus()
    }

    var isInstalled: Bool {
        if case .installed = status {
            return true
        }
        return false
    }

    func refreshInstallationStatus() {
        if localModelURLExists() {
            status = .installed
        } else {
            status = .notInstalled
        }
    }

    func downloadModel() {
        guard !isInstalled else { return }
        guard downloadTask == nil else { return }

        status = .downloading

        downloadTask = Task {
            defer {
                Task { @MainActor in
                    self.downloadTask = nil
                }
            }

            do {
                try await downloadAndInstallModel()
                await MainActor.run {
                    self.status = .installed
                }
            } catch {
                await MainActor.run {
                    self.status = .failed(error.localizedDescription)
                }
            }
        }
    }

    func modelURL() -> URL? {
        localModelURLExists() ? localModelURL() : nil
    }

    private func downloadAndInstallModel() async throws {
        var lastError: Error?

        for downloadURL in downloadURLs {
            do {
                let (temporaryURL, response) = try await URLSession.shared.download(from: downloadURL)

                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode) else {
                    throw CocoaError(.fileReadUnknown)
                }

                let destination = localModelURL()
                try fileManager().createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )

                if fileManager().fileExists(atPath: destination.path) {
                    try fileManager().removeItem(at: destination)
                }

                try fileManager().moveItem(at: temporaryURL, to: destination)
                return
            } catch {
                lastError = error
            }
        }

        if let lastError {
            throw lastError
        }

        throw CocoaError(.fileReadUnknown)
    }

    private func localModelURL() -> URL {
        modelDirectory().appendingPathComponent(modelFileName)
    }

    private func localModelURLExists() -> Bool {
        fileManager().fileExists(atPath: localModelURL().path)
    }

    private func modelDirectory() -> URL {
        let supportDirectory = fileManager().urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        return supportDirectory
            .appendingPathComponent("Anything Reader", isDirectory: true)
            .appendingPathComponent("KokoroModel", isDirectory: true)
    }

    private func fileManager() -> FileManager {
        .default
    }
}
