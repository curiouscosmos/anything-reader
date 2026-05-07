//
//  ReaderPlaybackAudioCacheService.swift
//  Anything Reader
//
//  File-backed cache for the first synthesized narration chunk so repeat
//  playback can skip the cold Kokoro render path.
//

import CryptoKit
import Foundation
import SwiftData

// Persists rendered WAV files for the first live narration chunk across runs.
actor ReaderPlaybackAudioCacheService {
    static let shared = ReaderPlaybackAudioCacheService()

    private init() {}

    func cachedAudioURL(for entry: LibraryEntry, providerID: ReaderTTSProviderID, voiceName: String, chunkText: String) async -> URL? {
        let cacheURL = cacheFileURL(for: entry, providerID: providerID, voiceName: voiceName, chunkText: chunkText)
        let metadataURL = cacheMetadataURL(for: entry, providerID: providerID, voiceName: voiceName, chunkText: chunkText)
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: cacheURL.path) else { return nil }
        guard let storedEntryID = try? String(contentsOf: metadataURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              storedEntryID == cacheEntryID(for: entry) else {
            try? fileManager.removeItem(at: entryCacheDirectory(for: entry))
            return nil
        }

        return cacheURL
    }

    func storeAudio(
        at sourceURL: URL,
        for entry: LibraryEntry,
        providerID: ReaderTTSProviderID,
        voiceName: String,
        chunkText: String
    ) async -> URL? {
        let cacheURL = cacheFileURL(for: entry, providerID: providerID, voiceName: voiceName, chunkText: chunkText)
        let metadataURL = cacheMetadataURL(for: entry, providerID: providerID, voiceName: voiceName, chunkText: chunkText)
        let fileManager = FileManager.default

        do {
            try fileManager.createDirectory(
                at: entryCacheDirectory(for: entry),
                withIntermediateDirectories: true
            )

            if fileManager.fileExists(atPath: cacheURL.path) {
                if let storedEntryID = try? String(contentsOf: metadataURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
                   storedEntryID == cacheEntryID(for: entry) {
                    return cacheURL
                }

                try? fileManager.removeItem(at: entryCacheDirectory(for: entry))
                try fileManager.createDirectory(
                    at: entryCacheDirectory(for: entry),
                    withIntermediateDirectories: true
                )
            }

            guard let metadataData = cacheEntryID(for: entry).data(using: .utf8) else {
                return nil
            }
            try metadataData.write(to: metadataURL, options: .atomic)

            if fileManager.fileExists(atPath: cacheURL.path) {
                return cacheURL
            }

            let stagingURL = cacheURL.appendingPathExtension("tmp")
            if fileManager.fileExists(atPath: stagingURL.path) {
                try? fileManager.removeItem(at: stagingURL)
            }

            try fileManager.copyItem(at: sourceURL, to: stagingURL)

            if fileManager.fileExists(atPath: cacheURL.path) {
                try? fileManager.removeItem(at: cacheURL)
            }

            try fileManager.moveItem(at: stagingURL, to: cacheURL)
            return cacheURL
        } catch {
            try? fileManager.removeItem(at: cacheURL)
            try? fileManager.removeItem(at: cacheURL.appendingPathExtension("tmp"))
            try? fileManager.removeItem(at: metadataURL)
            return nil
        }
    }

    func removeCache(for entry: LibraryEntry) async {
        try? FileManager.default.removeItem(at: entryCacheDirectory(for: entry))
    }

    private func cacheFileURL(for entry: LibraryEntry, providerID: ReaderTTSProviderID, voiceName: String, chunkText: String) -> URL {
        entryCacheDirectory(for: entry)
            .appendingPathComponent("\(cacheKey(for: entry, providerID: providerID, voiceName: voiceName, chunkText: chunkText)).wav")
    }

    private func cacheMetadataURL(for entry: LibraryEntry, providerID: ReaderTTSProviderID, voiceName: String, chunkText: String) -> URL {
        entryCacheDirectory(for: entry)
            .appendingPathComponent("\(cacheKey(for: entry, providerID: providerID, voiceName: voiceName, chunkText: chunkText)).entryid")
    }

    private func cacheDirectory() -> URL {
        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return supportDirectory
            .appendingPathComponent("Anything Reader", isDirectory: true)
            .appendingPathComponent("First Chunk Audio Cache", isDirectory: true)
    }

    private func entryCacheDirectory(for entry: LibraryEntry) -> URL {
        cacheDirectory().appendingPathComponent(hashedKey(from: cacheEntryID(for: entry)), isDirectory: true)
    }

    private func cacheEntryID(for entry: LibraryEntry) -> String {
        let modelID = entry.persistentModelID
        return [
            modelID.storeIdentifier ?? "default",
            modelID.entityName,
            String(describing: modelID.id)
        ]
        .joined(separator: "|")
    }

    private func cacheKey(for entry: LibraryEntry, providerID: ReaderTTSProviderID, voiceName: String, chunkText: String) -> String {
        hashedKey(from: "\(cacheEntryID(for: entry))|\(providerID.rawValue)|\(voiceName)|\(chunkText)")
    }

    private func hashedKey(from string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
