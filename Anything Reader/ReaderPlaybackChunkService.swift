//
//  ReaderPlaybackChunkService.swift
//  Anything Reader
//
//  Breaks normalized text into TTS-friendly chunks and resolves the current
//  playback position from persisted progress.
//

import Foundation
import SwiftData

struct ReaderPlaybackChunkService {
    static let initialChunkLength = 40
    static let preferredChunkLength = 120
    static let prefetchChunkCount = 3
    static let pdfPageBreakMarker = "[[PDF_PAGE_BREAK]]"
    static let epubChapterBreakMarker = "[[EPUB_CHAPTER_BREAK]]"
    static let txtSectionBreakMarker = "[[TXT_SECTION_BREAK]]"

    static func normalizedText(for entry: LibraryEntry) -> String? {
        normalizedText(for: entry.normalizedTextFileURL)
    }

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

    static func chunks(for entry: LibraryEntry, textFileURL: URL? = nil) -> [String] {
        guard let text = normalizedText(for: textFileURL ?? entry.normalizedTextFileURL) else { return [] }
        let language = entry.textLanguage ?? TextNormalizationService.detectLanguage(for: text)

        if entry.sourceKind == .pdf {
            return structuredChunks(
                from: text,
                marker: pdfPageBreakMarker,
                language: language
            ) ?? chunks(from: text, language: language)
        }

        if entry.sourceKind == .epub {
            return structuredChunks(
                from: text,
                marker: epubChapterBreakMarker,
                language: language
            ) ?? chunks(from: text, language: language)
        }

        if entry.sourceKind == .text || entry.sourceKind == .html || entry.sourceKind == .pastedText || entry.sourceKind == .image {
            return structuredChunks(
                from: text,
                marker: txtSectionBreakMarker,
                language: language
            ) ?? chunks(from: text, language: language)
        }

        return chunks(from: text, language: language)
    }

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

    static func chunkIndex(for readingTargetIndex: Int, in entry: LibraryEntry) -> Int? {
        guard let text = normalizedText(for: entry), !entry.readingJumpTargets.isEmpty else { return nil }

        let language = entry.textLanguage ?? TextNormalizationService.detectLanguage(for: text)
        let targetIndex = min(max(readingTargetIndex, 0), entry.readingJumpTargets.count - 1)
        let marker: String? = {
            switch entry.sourceKind {
            case .pdf:
                return pdfPageBreakMarker
            case .epub:
                return epubChapterBreakMarker
            case .text, .html, .pastedText, .image:
                return txtSectionBreakMarker
            }
        }()

        if let startIndices = structuredChunkStartIndices(from: text, marker: marker, language: language),
           startIndices.indices.contains(targetIndex) {
            return startIndices[targetIndex]
        }

        return chunkIndex(
            for: Double(targetIndex) / Double(max(entry.readingJumpTargets.count, 1)),
            chunkCount: chunks(for: entry).count
        )
    }

    static func readingTargetIndex(forChunkIndex chunkIndex: Int, in entry: LibraryEntry) -> Int? {
        guard let text = normalizedText(for: entry), !entry.readingJumpTargets.isEmpty else { return nil }

        let language = entry.textLanguage ?? TextNormalizationService.detectLanguage(for: text)
        let marker: String? = {
            switch entry.sourceKind {
            case .pdf:
                return pdfPageBreakMarker
            case .epub:
                return epubChapterBreakMarker
            case .text, .html, .pastedText, .image:
                return txtSectionBreakMarker
            }
        }()

        if let startIndices = structuredChunkStartIndices(from: text, marker: marker, language: language),
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

    static func chunkIndex(for progress: Double, chunkCount: Int) -> Int {
        guard chunkCount > 0 else { return 0 }
        let clampedProgress = min(max(progress, 0), 0.999_999)
        let index = Int((clampedProgress * Double(chunkCount)).rounded(.down))
        return min(max(index, 0), chunkCount - 1)
    }

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
