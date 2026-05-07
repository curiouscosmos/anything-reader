//
//  PhonemeCacheService.swift
//  Anything Reader
//
//  File-backed cache for Kokoro phonemes and future TTS preprocessing.
//

import Foundation
import CryptoKit

// Persists generated phonemes on disk so the app can reuse them across launches.
actor PhonemeCacheService {
    static let shared = PhonemeCacheService()

    private var inMemoryCache: [String: String] = [:]

    private init() {}

    func cachedPhonemes(for entry: LibraryEntry, providerID: ReaderTTSProviderID = .kokoro) async -> String? {
        let key = cacheKey(for: entry, providerID: providerID)

        if let cached = inMemoryCache[key] {
            return cached
        }

        if let cached = try? String(contentsOf: cacheFileURL(for: key), encoding: .utf8),
           !cached.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            inMemoryCache[key] = cached
            return cached
        }

        if let databaseValue = entry.phonemeText,
           !databaseValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            inMemoryCache[key] = databaseValue
            return databaseValue
        }

        return nil
    }

    func cachedPhonemes(for entry: LibraryEntry, chunkIndex: Int, providerID: ReaderTTSProviderID = .kokoro) async -> String? {
        let key = chunkCacheKey(for: entry, chunkIndex: chunkIndex, providerID: providerID)

        if let cached = inMemoryCache[key] {
            return cached
        }

        if let cached = try? String(contentsOf: cacheFileURL(for: key), encoding: .utf8),
           !cached.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            inMemoryCache[key] = cached
            return cached
        }

        return nil
    }

    func store(_ phonemes: String, for entry: LibraryEntry, providerID: ReaderTTSProviderID = .kokoro) async {
        let normalized = phonemes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        let key = cacheKey(for: entry, providerID: providerID)
        inMemoryCache[key] = normalized

        do {
            try fileManager().createDirectory(
                at: cacheDirectory(),
                withIntermediateDirectories: true
            )
            try normalized.write(to: cacheFileURL(for: key), atomically: true, encoding: .utf8)
        } catch {
            // Cache writes are best-effort; playback can still use the database value.
        }
    }

    func store(_ phonemes: String, for entry: LibraryEntry, chunkIndex: Int, providerID: ReaderTTSProviderID = .kokoro) async {
        let normalized = phonemes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        let key = chunkCacheKey(for: entry, chunkIndex: chunkIndex, providerID: providerID)
        inMemoryCache[key] = normalized

        do {
            try fileManager().createDirectory(
                at: cacheDirectory(),
                withIntermediateDirectories: true
            )
            try normalized.write(to: cacheFileURL(for: key), atomically: true, encoding: .utf8)
        } catch {
            // Chunk cache writes are best-effort; playback can still synthesize on demand.
        }
    }

    func removeCache(for entry: LibraryEntry, providerID: ReaderTTSProviderID? = nil) async {
        let providerIDs = providerID.map { [$0] } ?? ReaderTTSProviderID.allCases

        for provider in providerIDs {
            let keyPrefix = cacheKey(for: entry, providerID: provider)
            inMemoryCache.keys.filter { $0 == keyPrefix || $0.hasPrefix("\(keyPrefix)-chunk-") }.forEach {
                inMemoryCache.removeValue(forKey: $0)
            }

            let directory = cacheDirectory()
            guard let contents = try? fileManager().contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
                continue
            }

            for fileURL in contents where fileURL.lastPathComponent.hasPrefix(keyPrefix) {
                try? fileManager().removeItem(at: fileURL)
            }
        }
    }

    func primeChunks(for entry: LibraryEntry, chunks: [String], startingAt chunkIndex: Int, providerID: ReaderTTSProviderID = .kokoro, prefetchCount: Int = 2) async {
        guard !chunks.isEmpty else { return }
        let boundedStartIndex = min(max(chunkIndex, 0), chunks.count - 1)
        let upperBound = min(chunks.count - 1, boundedStartIndex + prefetchCount)

        for index in boundedStartIndex...upperBound {
            if await cachedPhonemes(for: entry, chunkIndex: index, providerID: providerID) != nil {
                continue
            }

            let chunkText = chunks[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !chunkText.isEmpty else { continue }

            let phonemes = await phonemes(for: chunkText, providerID: providerID)
            guard !phonemes.isEmpty else { continue }

            await store(phonemes, for: entry, chunkIndex: index, providerID: providerID)
        }
    }

    func primeCache(for entry: LibraryEntry, providerID: ReaderTTSProviderID = .kokoro) async -> String? {
        if let cached = await cachedPhonemes(for: entry, providerID: providerID) {
            return cached
        }

        guard let sourceText = await nonEmptySourceText(for: entry) else {
            return nil
        }

        let phonemes = await phonemes(for: sourceText, providerID: providerID)
        guard !phonemes.isEmpty else { return nil }

        await store(phonemes, for: entry, providerID: providerID)
        return phonemes
    }

    private func cacheKey(for entry: LibraryEntry, providerID: ReaderTTSProviderID? = nil) -> String {
        let source = entry.storedFilePath ?? entry.cacheIdentity
        let providerPrefix = providerID?.rawValue ?? "all"
        return hashedKey(from: "\(providerPrefix)|\(source)")
    }

    private func chunkCacheKey(for entry: LibraryEntry, chunkIndex: Int, providerID: ReaderTTSProviderID? = nil) -> String {
        "\(cacheKey(for: entry, providerID: providerID))-chunk-\(String(format: "%03d", chunkIndex))"
    }

    private func cacheFileURL(for key: String) -> URL {
        cacheDirectory().appendingPathComponent("\(key).txt")
    }

    private func cacheDirectory() -> URL {
        let supportDirectory = fileManager().urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return supportDirectory
            .appendingPathComponent("Anything Reader", isDirectory: true)
            .appendingPathComponent("Phoneme Cache", isDirectory: true)
    }

    private func fileManager() -> FileManager {
        .default
    }

    private func hashedKey(from string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func phonemes(for text: String, providerID: ReaderTTSProviderID) async -> String {
        switch providerID {
        case .kokoro:
            return await KokoroG2PService.shared.phonemize(text)
        case .moonshine:
            return TextNormalizationService.normalize(text)
        }
    }

    @MainActor
    private func nonEmptySourceText(for entry: LibraryEntry) -> String? {
        let text = ReaderPlaybackChunkService.normalizedText(for: entry)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }
}
