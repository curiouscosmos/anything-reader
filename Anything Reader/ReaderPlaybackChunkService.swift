//
//  ReaderPlaybackChunkService.swift
//  Anything Reader
//
//  Breaks normalized text into TTS-friendly chunks and resolves the current
//  playback position from persisted progress.
//

import Foundation
import PDFKit
import SwiftData

struct ReaderPlaybackChunkService {
    static let preferredChunkLength = 420
    static let prefetchChunkCount = 3
    static let pdfPageBreakMarker = "[[PDF_PAGE_BREAK]]"

    static func normalizedText(for entry: LibraryEntry) -> String? {
        if let path = entry.normalizedTextFilePath {
            let fileURL = URL(fileURLWithPath: path)
            if let fileText = try? String(contentsOf: fileURL, encoding: .utf8) {
                let trimmed = fileText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }

        let fallback = entry.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? nil : fallback
    }

    static func chunks(for entry: LibraryEntry) -> [String] {
        guard let text = normalizedText(for: entry) else { return [] }
        let language = entry.textLanguage ?? TextNormalizationService.detectLanguage(for: text)

        if entry.sourceKind == .pdf {
            let pdfPages: [String]

            if text.contains(pdfPageBreakMarker) {
                pdfPages = text
                    .components(separatedBy: pdfPageBreakMarker)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            } else if let extractedPages = pdfPageChunks(for: entry), !extractedPages.isEmpty {
                pdfPages = extractedPages
            } else {
                pdfPages = []
            }

            if !pdfPages.isEmpty {
                // Keep page navigation exact, but split each page into smaller
                // TTS-friendly chunks so long PDFs do not trip the model.
                return pdfPages.flatMap { pageText in
                    chunks(from: pageText, language: language)
                }
            }
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

        let paragraphs = cleaned
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n\n")

        var chunks: [String] = []

        for paragraph in paragraphs {
            let paragraphText = paragraph
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !paragraphText.isEmpty else { continue }

            let segments = splitIntoSentenceSegments(paragraphText, language: resolvedLanguage)
            if segments.isEmpty {
                chunks.append(paragraphText)
                continue
            }

            var buffer = ""
            for segment in segments {
                let trimmedSegment = segment.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedSegment.isEmpty else { continue }

                if trimmedSegment.count > preferredChunkLength {
                    if !buffer.isEmpty {
                        chunks.append(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
                        buffer = ""
                    }

                    chunks.append(contentsOf: splitLongSegment(trimmedSegment))
                    continue
                }

                if buffer.isEmpty {
                    buffer = trimmedSegment
                } else if buffer.count + 1 + trimmedSegment.count <= preferredChunkLength {
                    buffer += " "
                    buffer += trimmedSegment
                } else {
                    chunks.append(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
                    buffer = trimmedSegment
                }
            }

            if !buffer.isEmpty {
                chunks.append(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        return chunks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func pageChunks(for entry: LibraryEntry) -> [String] {
        guard let text = normalizedText(for: entry) else { return [] }
        let language = entry.textLanguage ?? TextNormalizationService.detectLanguage(for: text)

        if text.contains(pdfPageBreakMarker) {
            return text
                .components(separatedBy: pdfPageBreakMarker)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }

        if entry.sourceKind == .pdf, let pdfChunks = pdfPageChunks(for: entry), !pdfChunks.isEmpty {
            return pdfChunks
        }

        let cleaned = TextNormalizationService.normalize(text, language: language)
        guard !cleaned.isEmpty else { return [] }

        return chunks(from: cleaned, language: language)
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

    private static func pdfPageChunks(for entry: LibraryEntry) -> [String]? {
        guard let path = entry.storedFilePath else { return nil }
        let fileURL = URL(fileURLWithPath: path)
        guard let document = PDFDocument(url: fileURL), document.pageCount > 0 else { return nil }
        let language = entry.textLanguage ?? .unknown

        return (0..<document.pageCount).map { index in
            guard let page = document.page(at: index) else { return "" }
            let rawText = page.string ?? ""
            return TextNormalizationService.normalize(rawText, language: language)
        }
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
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return [text] }

        var chunks: [String] = []
        var buffer = ""

        for word in words {
            if word.count > preferredChunkLength {
                if !buffer.isEmpty {
                    chunks.append(buffer)
                    buffer = ""
                }
                chunks.append(contentsOf: breakLongWord(word))
                continue
            }

            if buffer.isEmpty {
                buffer = word
            } else if buffer.count + 1 + word.count <= preferredChunkLength {
                buffer += " "
                buffer += word
            } else {
                chunks.append(buffer)
                buffer = word
            }
        }

        if !buffer.isEmpty {
            chunks.append(buffer)
        }

        return chunks
    }

    private static func breakLongWord(_ word: String) -> [String] {
        guard word.count > preferredChunkLength else { return [word] }

        var result: [String] = []
        var startIndex = word.startIndex

        while startIndex < word.endIndex {
            let endIndex = word.index(startIndex, offsetBy: preferredChunkLength, limitedBy: word.endIndex) ?? word.endIndex
            result.append(String(word[startIndex..<endIndex]))
            startIndex = endIndex
        }

        return result
    }
}
