//
//  ReaderPlaybackChunkService.swift
//  Anything Reader
//
//  Breaks normalized text into TTS-friendly chunks and resolves the current
//  playback position from persisted progress.
//

import Foundation
import SwiftData

// Breaks normalized text into TTS-friendly chunks and resolves playback positions from structured content.
struct ReaderPlaybackChunkService {
    // Chunking defaults tuned to keep synthesis responsive without making chunks too small.
    static let initialChunkLength = 80
    static let preferredChunkLength = 240
    static let prefetchChunkCount = 3
    static let pdfPageBreakMarker = "[[PDF_PAGE_BREAK]]"
    static let epubChapterBreakMarker = "[[EPUB_CHAPTER_BREAK]]"
    static let txtSectionBreakMarker = "[[TXT_SECTION_BREAK]]"

    // Loads normalized text from disk and trims it into a reusable in-memory string.
    static func normalizedText(for entry: LibraryEntry) -> String? {
        normalizedText(for: entry.normalizedTextFileURL)
    }

    // Same as above, but accepts an explicit file URL when the caller has one.
    static func normalizedText(for textFileURL: URL?) -> String? {
        guard let textFileURL else { return nil }

        if let fileText = try? String(contentsOf: textFileURL, encoding: .utf8) {
            let trimmed = fileText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return nil
    }

    // Returns the chunk sidecar URL next to a normalized text file.
    private static func chunkCacheURL(for normalizedTextFileURL: URL) -> URL {
        normalizedTextFileURL
            .deletingPathExtension()
            .appendingPathExtension("chunks")
            .appendingPathExtension("json")
    }

    // Returns the jump-target sidecar URL next to a normalized text file.
    private static func jumpMapCacheURL(for normalizedTextFileURL: URL) -> URL {
        normalizedTextFileURL
            .deletingPathExtension()
            .appendingPathExtension("jumpMap")
            .appendingPathExtension("json")
    }

    // Loads the cached chunk strings when the sidecar already exists.
    static func cachedChunks(for textFileURL: URL?) -> [String]? {
        guard let textFileURL else { return nil }
        let cacheURL = chunkCacheURL(for: textFileURL)
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode([String].self, from: data)
    }

    // Loads the cached jump-map indices when the sidecar already exists.
    static func cachedJumpMap(for textFileURL: URL?) -> [Int]? {
        guard let textFileURL else { return nil }
        let cacheURL = jumpMapCacheURL(for: textFileURL)
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode([Int].self, from: data)
    }

    // Removes both playback sidecars so a re-import can rewrite them cleanly.
    static func removeCachedChunkArtifacts(for textFileURL: URL?) {
        guard let textFileURL else { return }
        let fileManager = FileManager.default

        [chunkCacheURL(for: textFileURL), jumpMapCacheURL(for: textFileURL)].forEach { cacheURL in
            if fileManager.fileExists(atPath: cacheURL.path) {
                try? fileManager.removeItem(at: cacheURL)
            }
        }
    }

    // Writes the cached chunk strings and jump targets beside the normalized text file.
    static func storeChunkCache(
        normalizedText: String,
        normalizedTextFileURL: URL,
        sourceKind: ReaderSourceKind,
        language: TextLanguage?,
        readingJumpTargets: [ReaderJumpTarget]
    ) throws {
        let resolvedLanguage = language ?? TextNormalizationService.detectLanguage(for: normalizedText)
        let chunks = chunkList(
            fromNormalizedText: normalizedText,
            sourceKind: sourceKind,
            language: resolvedLanguage
        )
        let jumpMap = jumpMap(
            forNormalizedText: normalizedText,
            sourceKind: sourceKind,
            language: resolvedLanguage,
            readingJumpTargets: readingJumpTargets,
            chunkCount: chunks.count
        )

        let encoder = JSONEncoder()
        let chunkData = try encoder.encode(chunks)
        let jumpMapData = try encoder.encode(jumpMap)

        try chunkData.write(to: chunkCacheURL(for: normalizedTextFileURL), options: [.atomic])
        try jumpMapData.write(to: jumpMapCacheURL(for: normalizedTextFileURL), options: [.atomic])
    }

    // Builds chunk arrays from a library entry using source-specific structure when available.
    static func chunks(for entry: LibraryEntry, textFileURL: URL? = nil) -> [String] {
        guard let resolvedTextFileURL = textFileURL ?? entry.normalizedTextFileURL else { return [] }

        if let cachedChunks = cachedChunks(for: resolvedTextFileURL) {
            return cachedChunks
        }

        guard let text = normalizedText(for: resolvedTextFileURL) else { return [] }
        let language = entry.textLanguage ?? TextNormalizationService.detectLanguage(for: text)
        let chunks = chunkList(fromNormalizedText: text, sourceKind: entry.sourceKind, language: language)

        // Legacy entries may not yet have sidecars. Regenerate them only for the
        // main normalized file, not for ad-hoc summary playback sources.
        if resolvedTextFileURL == entry.normalizedTextFileURL {
            try? storeChunkCache(
                normalizedText: text,
                normalizedTextFileURL: resolvedTextFileURL,
                sourceKind: entry.sourceKind,
                language: language,
                readingJumpTargets: entry.readingJumpTargets
            )
        }

        return chunks
    }

    // Splits already-normalized text into sentence-safe chunks.
    static func chunks(from text: String, language: TextLanguage? = nil) -> [String] {
        let resolvedLanguage = language ?? TextNormalizationService.detectLanguage(for: text)
        let cleaned = TextNormalizationService.normalize(text, language: resolvedLanguage)
        guard !cleaned.isEmpty else { return [] }

        if cleaned.contains(pdfPageBreakMarker) {
            return cleaned
                .components(separatedBy: pdfPageBreakMarker)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }

        var firstChunkPending = true
        return chunks(
            fromCleanedText: cleaned,
            language: resolvedLanguage,
            firstChunkPending: &firstChunkPending
        )
    }

    // Returns page/chapter/section chunks when the source file already contains structure markers.
    static func pageChunks(for entry: LibraryEntry, textFileURL: URL? = nil) -> [String] {
        guard let text = normalizedText(for: textFileURL ?? entry.normalizedTextFileURL) else { return [] }
        let language = entry.textLanguage ?? TextNormalizationService.detectLanguage(for: text)

        if entry.sourceKind == .pdf,
           text.contains(pdfPageBreakMarker) {
            return text
                .components(separatedBy: pdfPageBreakMarker)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }

        if entry.sourceKind == .epub,
           text.contains(epubChapterBreakMarker) {
            return text
                .components(separatedBy: epubChapterBreakMarker)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }

        if (entry.sourceKind == .text || entry.sourceKind == .html || entry.sourceKind == .pastedText || entry.sourceKind == .image),
           text.contains(txtSectionBreakMarker) {
            return text
                .components(separatedBy: txtSectionBreakMarker)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }

        let cleaned = TextNormalizationService.normalize(text, language: language)
        guard !cleaned.isEmpty else { return [] }

        return chunks(from: cleaned, language: language)
    }

    // Resolves a chunk index from a structured reading target.
    static func chunkIndex(for readingTargetIndex: Int, in entry: LibraryEntry) -> Int? {
        let targetIndex = min(max(readingTargetIndex, 0), entry.readingJumpTargets.count - 1)

        if let cachedJumpMap = cachedJumpMap(for: entry.normalizedTextFileURL),
           cachedJumpMap.count == entry.readingJumpTargets.count,
           cachedJumpMap.indices.contains(targetIndex) {
            return cachedJumpMap[targetIndex]
        }

        guard let text = normalizedText(for: entry), !entry.readingJumpTargets.isEmpty else { return nil }
        let language = entry.textLanguage ?? TextNormalizationService.detectLanguage(for: text)

        if let startIndices = structuredChunkStartIndices(from: text, marker: marker(for: entry.sourceKind), language: language),
           startIndices.indices.contains(targetIndex) {
            return startIndices[targetIndex]
        }

        return chunkIndex(
            for: Double(targetIndex) / Double(max(entry.readingJumpTargets.count, 1)),
            chunkCount: chunks(for: entry).count
        )
    }

    // Resolves a structured reading target from a chunk index.
    static func readingTargetIndex(forChunkIndex chunkIndex: Int, in entry: LibraryEntry) -> Int? {
        if let cachedJumpMap = cachedJumpMap(for: entry.normalizedTextFileURL),
           cachedJumpMap.count == entry.readingJumpTargets.count,
           !cachedJumpMap.isEmpty {
            let boundedChunkIndex = max(chunkIndex, 0)
            var currentTargetIndex = 0

            for (index, startIndex) in cachedJumpMap.enumerated() {
                if boundedChunkIndex >= startIndex {
                    currentTargetIndex = index
                } else {
                    break
                }
            }

            return currentTargetIndex
        }

        guard let text = normalizedText(for: entry), !entry.readingJumpTargets.isEmpty else { return nil }

        let language = entry.textLanguage ?? TextNormalizationService.detectLanguage(for: text)

        if let startIndices = structuredChunkStartIndices(from: text, marker: marker(for: entry.sourceKind), language: language),
           !startIndices.isEmpty {
            let boundedChunkIndex = max(chunkIndex, 0)
            var currentTargetIndex = 0

            for (index, startIndex) in startIndices.enumerated() {
                if boundedChunkIndex >= startIndex {
                    currentTargetIndex = index
                } else {
                    break
                }
            }

            return currentTargetIndex
        }

        return Self.chunkIndex(for: Double(chunkIndex), chunkCount: entry.readingJumpTargets.count)
    }

    // Maps a playback progress fraction to the chunk index to synthesize or resume from.
    static func chunkIndex(for progress: Double, chunkCount: Int) -> Int {
        guard chunkCount > 0 else { return 0 }
        let clampedProgress = min(max(progress, 0), 0.999_999)
        let index = Int((clampedProgress * Double(chunkCount)).rounded(.down))
        return min(max(index, 0), chunkCount - 1)
    }

    // Converts a chunk index back into a progress fraction centered in that chunk's bucket.
    static func progress(for chunkIndex: Int, chunkCount: Int) -> Double {
        guard chunkCount > 0 else { return 0 }
        let boundedIndex = min(max(chunkIndex, 0), chunkCount - 1)
        // Anchor the value inside the target bucket so a later chunkIndex(for:)
        // call resolves back to the same page/chapter instead of the previous one.
        let centeredIndex = Double(boundedIndex) + 0.5
        return min(centeredIndex / Double(chunkCount), 0.999_999)
    }

    private static func splitIntoSentenceSegments(_ text: String, language: TextLanguage?) -> [String] {
        let pattern = sentenceBoundaryPattern(for: language)
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [text]
        }

        let range = NSRange(text.startIndex..., in: text)
        var segments: [String] = []
        var previousUpperBound = text.startIndex

        regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match, let splitRange = Range(match.range, in: text) else { return }
            let segment = String(text[previousUpperBound..<splitRange.lowerBound])
            if !segment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(segment)
            }
            previousUpperBound = splitRange.upperBound
        }

        let remainder = String(text[previousUpperBound...])
        if !remainder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append(remainder)
        }

        return segments.isEmpty ? [text] : segments
    }

    private static func sentenceBoundaryPattern(for language: TextLanguage?) -> String {
        switch language {
        case .mandarin, .japanese:
            return #"(?<=[。！？!?；;…])\s*"#
        case .hindi, .punjabi:
            return #"(?<=[।॥!?؛;…])\s*"#
        default:
            return #"(?<=[.!?])\s+"#
        }
    }

    // Resolves the marker used for structured reading sources.
    private static func marker(for sourceKind: ReaderSourceKind) -> String? {
        switch sourceKind {
        case .pdf:
            return pdfPageBreakMarker
        case .epub:
            return epubChapterBreakMarker
        case .text, .html, .pastedText, .image:
            return txtSectionBreakMarker
        }
    }

    // Builds the chunk list from already-normalized text while honoring any
    // source-specific page/chapter/section markers.
    private static func chunkList(
        fromNormalizedText normalizedText: String,
        sourceKind: ReaderSourceKind,
        language: TextLanguage
    ) -> [String] {
        let cleaned = TextNormalizationService.normalize(normalizedText, language: language)
        guard !cleaned.isEmpty else { return [] }

        if let marker = marker(for: sourceKind) {
            return structuredChunks(
                from: cleaned,
                marker: marker,
                language: language
            ) ?? chunks(from: cleaned, language: language)
        }

        return chunks(from: cleaned, language: language)
    }

    // Rebuilds the jump-map cache from the chunk layout so page/chapter/section
    // jumps can start from the correct chunk after a later app launch.
    private static func jumpMap(
        forNormalizedText normalizedText: String,
        sourceKind: ReaderSourceKind,
        language: TextLanguage,
        readingJumpTargets: [ReaderJumpTarget],
        chunkCount: Int
    ) -> [Int] {
        guard !readingJumpTargets.isEmpty, chunkCount > 0 else { return [] }

        if let marker = marker(for: sourceKind),
           let startIndices = structuredChunkStartIndices(from: normalizedText, marker: marker, language: language),
           startIndices.count == readingJumpTargets.count {
            return startIndices
        }

        return readingJumpTargets.indices.map { targetIndex in
            chunkIndex(
                for: Double(targetIndex) / Double(max(readingJumpTargets.count, 1)),
                chunkCount: chunkCount
            )
        }
    }

    private static func splitLongSegment(_ text: String) -> [String] {
        var firstChunkPending = true
        return splitLongSegment(text, firstChunkPending: &firstChunkPending)
    }

    private static func splitLongSegment(_ text: String, firstChunkPending: inout Bool) -> [String] {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return [text] }

        var chunks: [String] = []
        var buffer = ""

        for word in words {
            let chunkLength = firstChunkPending ? initialChunkLength : preferredChunkLength

            if word.count > chunkLength {
                if !buffer.isEmpty {
                    chunks.append(buffer)
                    buffer = ""
                    firstChunkPending = false
                }
                chunks.append(contentsOf: breakLongWord(word, firstChunkPending: &firstChunkPending))
                continue
            }

            if buffer.isEmpty {
                buffer = word
            } else if buffer.count + 1 + word.count <= chunkLength {
                buffer += " "
                buffer += word
            } else {
                chunks.append(buffer)
                buffer = word
                firstChunkPending = false
            }
        }

        if !buffer.isEmpty {
            chunks.append(buffer)
            firstChunkPending = false
        }

        return chunks
    }

    private static func structuredChunks(
        from text: String,
        marker: String,
        language: TextLanguage
    ) -> [String]? {
        guard text.contains(marker) else { return nil }

        let sections = text
            .components(separatedBy: marker)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        var firstChunkPending = true
        var flattenedChunks: [String] = []
        flattenedChunks.reserveCapacity(sections.count)

        for section in sections {
            flattenedChunks.append(
                contentsOf: chunks(
                    fromCleanedText: section,
                    language: language,
                    firstChunkPending: &firstChunkPending
                )
            )
        }

        return flattenedChunks.isEmpty ? nil : flattenedChunks
    }

    private static func structuredChunkStartIndices(
        from text: String,
        marker: String?,
        language: TextLanguage
    ) -> [Int]? {
        guard let marker, text.contains(marker) else { return nil }

        let sections = text
            .components(separatedBy: marker)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        var startIndices: [Int] = []
        var runningIndex = 0
        var firstChunkPending = true

        for section in sections {
            startIndices.append(runningIndex)
            runningIndex += chunks(
                fromCleanedText: section,
                language: language,
                firstChunkPending: &firstChunkPending
            ).count
        }

        return startIndices
    }

    private static func breakLongWord(_ word: String) -> [String] {
        var firstChunkPending = true
        return breakLongWord(word, firstChunkPending: &firstChunkPending)
    }

    private static func breakLongWord(_ word: String, firstChunkPending: inout Bool) -> [String] {
        let chunkLength = firstChunkPending ? initialChunkLength : preferredChunkLength
        guard word.count > chunkLength else { return [word] }

        var result: [String] = []
        var startIndex = word.startIndex

        while startIndex < word.endIndex {
            let currentChunkLength = firstChunkPending ? initialChunkLength : preferredChunkLength
            let endIndex = word.index(startIndex, offsetBy: currentChunkLength, limitedBy: word.endIndex) ?? word.endIndex
            result.append(String(word[startIndex..<endIndex]))
            startIndex = endIndex
            firstChunkPending = false
        }

        return result
    }

    private static func chunks(
        fromCleanedText cleanedText: String,
        language: TextLanguage,
        firstChunkPending: inout Bool
    ) -> [String] {
        let paragraphs = cleanedText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n\n")

        var chunks: [String] = []

        for paragraph in paragraphs {
            let paragraphText = paragraph
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !paragraphText.isEmpty else { continue }

            let segments = splitIntoSentenceSegments(paragraphText, language: language)
            if segments.isEmpty {
                appendChunk(paragraphText, to: &chunks, firstChunkPending: &firstChunkPending)
                continue
            }

            var buffer = ""
            for segment in segments {
                let trimmedSegment = segment.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedSegment.isEmpty else { continue }

                let chunkLength = firstChunkPending ? initialChunkLength : preferredChunkLength

                if trimmedSegment.count > chunkLength {
                    if !buffer.isEmpty {
                        chunks.append(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
                        buffer = ""
                        firstChunkPending = false
                    }

                    chunks.append(contentsOf: splitLongSegment(trimmedSegment, firstChunkPending: &firstChunkPending))
                    continue
                }

                if buffer.isEmpty {
                    buffer = trimmedSegment
                } else if buffer.count + 1 + trimmedSegment.count <= chunkLength {
                    buffer += " "
                    buffer += trimmedSegment
                } else {
                    chunks.append(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
                    buffer = trimmedSegment
                    firstChunkPending = false
                }
            }

            if !buffer.isEmpty {
                chunks.append(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
                firstChunkPending = false
            }
        }

        return chunks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func appendChunk(
        _ chunk: String,
        to chunks: inout [String],
        firstChunkPending: inout Bool
    ) {
        let trimmedChunk = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedChunk.isEmpty else { return }

        let chunkLength = firstChunkPending ? initialChunkLength : preferredChunkLength
        if trimmedChunk.count <= chunkLength {
            chunks.append(trimmedChunk)
            firstChunkPending = false
            return
        }

        chunks.append(contentsOf: splitLongSegment(trimmedChunk, firstChunkPending: &firstChunkPending))
    }
}
