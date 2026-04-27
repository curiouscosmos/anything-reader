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

    func removeCache(for entry: LibraryEntry) async {
        let key = cacheKey(for: entry)
        inMemoryCache.removeValue(forKey: key)

        try? fileManager().removeItem(at: cacheFileURL(for: key))
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
