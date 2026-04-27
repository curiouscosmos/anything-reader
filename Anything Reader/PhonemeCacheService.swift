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

    func cachedPhonemes(for entry: LibraryEntry) async -> String? {
        let key = cacheKey(for: entry)

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

    func cachedPhonemes(for entry: LibraryEntry, chunkIndex: Int) async -> String? {
        let key = chunkCacheKey(for: entry, chunkIndex: chunkIndex)

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

    func store(_ phonemes: String, for entry: LibraryEntry) async {
        let normalized = phonemes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        let key = cacheKey(for: entry)
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

    func store(_ phonemes: String, for entry: LibraryEntry, chunkIndex: Int) async {
        let normalized = phonemes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        let key = chunkCacheKey(for: entry, chunkIndex: chunkIndex)
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

    func removeCache(for entry: LibraryEntry) async {
        let keyPrefix = cacheKey(for: entry)
        inMemoryCache.keys.filter { $0 == keyPrefix || $0.hasPrefix("\(keyPrefix)-chunk-") }.forEach {
            inMemoryCache.removeValue(forKey: $0)
        }

        let directory = cacheDirectory()
        guard let contents = try? fileManager().contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }

        for fileURL in contents where fileURL.lastPathComponent.hasPrefix(keyPrefix) {
            try? fileManager().removeItem(at: fileURL)
        }
    }

    func primeChunks(for entry: LibraryEntry, chunks: [String], startingAt chunkIndex: Int, prefetchCount: Int = 2) async {
        guard !chunks.isEmpty else { return }
        let boundedStartIndex = min(max(chunkIndex, 0), chunks.count - 1)
        let upperBound = min(chunks.count - 1, boundedStartIndex + prefetchCount)

        for index in boundedStartIndex...upperBound {
            if await cachedPhonemes(for: entry, chunkIndex: index) != nil {
                continue
            }

            let chunkText = chunks[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !chunkText.isEmpty else { continue }

            let phonemes = await KokoroG2PService.shared.phonemize(chunkText)
            guard !phonemes.isEmpty else { continue }

            await store(phonemes, for: entry, chunkIndex: index)
        }
    }

    func primeCache(for entry: LibraryEntry) async -> String? {
        if let cached = await cachedPhonemes(for: entry) {
            return cached
        }

        guard let sourceText = nonEmptySourceText(for: entry) else {
            return nil
        }

        let phonemes = await KokoroG2PService.shared.phonemize(sourceText)
        guard !phonemes.isEmpty else { return nil }

        await store(phonemes, for: entry)
        return phonemes
    }

    private func cacheKey(for entry: LibraryEntry) -> String {
        let source = entry.storedFilePath ?? entry.cacheIdentity
        return hashedKey(from: source)
    }

    private func chunkCacheKey(for entry: LibraryEntry, chunkIndex: Int) -> String {
        "\(cacheKey(for: entry))-chunk-\(String(format: "%03d", chunkIndex))"
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

    private func nonEmptySourceText(for entry: LibraryEntry) -> String? {
        let text = entry.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
