//
//  FileSummarizationService.swift
//  Anything Reader
//
//  Uses Apple Intelligence to summarize long-form source text and writes the
//  normalized result back to disk for later playback.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

// Summarization failures are returned as localized errors so the import flow can tell the user what happened.
enum FileSummarizationError: LocalizedError {
    case unavailable
    case emptyInput
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Apple Intelligence summarization is not available on this Mac."
        case .emptyInput:
            return "There was no readable text to summarize."
        case .generationFailed(let message):
            return message
        }
    }
}

// Wraps Apple Intelligence summarization into a file-oriented service that can run hierarchically.
actor FileSummarizationService {
    // Shared singleton because summarization is used from import and reread flows.
    static let shared = FileSummarizationService()

    private let sectionCharacterLimit = 1_500
    private let finalSummaryCharacterLimit = 4_500
    private static let maximumResponseTokens = 256
    private static let maximumHierarchyDepth = 12

    private init() {}

    // Produces a concise summary for the provided text and language.
    func summarize(text: String, language: TextLanguage) async throws -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw FileSummarizationError.emptyInput
        }

        let resolvedLanguage = Self.resolvedLanguage(for: language)
        let normalizedSummary = try await summarizeHierarchically(
            trimmedText,
            language: resolvedLanguage,
            maximumCharacters: sectionCharacterLimit
        )

        if normalizedSummary.count <= finalSummaryCharacterLimit {
            return normalizedSummary
        }

        let finalSummary = try await summarizeHierarchically(
            normalizedSummary,
            language: resolvedLanguage,
            maximumCharacters: sectionCharacterLimit
        )

        guard !finalSummary.isEmpty else {
            throw FileSummarizationError.emptyInput
        }

        return finalSummary
    }

    // Summarizes each section independently so long inputs can be processed in chunks.
    private func summarizeSections(_ sections: [String], language: TextLanguage) async throws -> [String] {
        var summaries: [String] = []
        summaries.reserveCapacity(sections.count)

        for section in sections {
            try Task.checkCancellation()
            let summary = try await summarizeSingleSection(section, language: language)
            summaries.append(summary)
        }

        return summaries
    }

    // Recursively summarizes text until the result fits within the requested budget.
    private func summarizeHierarchically(
        _ text: String,
        language: TextLanguage,
        maximumCharacters: Int,
        depth: Int = 0
    ) async throws -> String {
        let sections = Self.splitForSummarization(text, maximumCharacters: maximumCharacters)

        guard !sections.isEmpty else {
            throw FileSummarizationError.emptyInput
        }

        if sections.count == 1 {
            return try await summarizeSectionHierarchically(
                sections[0],
                language: language,
                maximumCharacters: maximumCharacters,
                depth: depth
            )
        }

        var sectionSummaries: [String] = []
        sectionSummaries.reserveCapacity(sections.count)

        for section in sections {
            try Task.checkCancellation()
            let summary = try await summarizeSectionHierarchically(
                section,
                language: language,
                maximumCharacters: maximumCharacters,
                depth: depth + 1
            )
            sectionSummaries.append(summary)
        }

        guard !sectionSummaries.isEmpty else {
            throw FileSummarizationError.emptyInput
        }

        let combinedSummary = Self.normalizedSummary(from: sectionSummaries, language: language)

        if combinedSummary.count <= maximumCharacters || depth >= Self.maximumHierarchyDepth {
            return combinedSummary
        }

        return try await summarizeHierarchically(
            combinedSummary,
            language: language,
            maximumCharacters: Self.nextSmallerCharacterLimit(
                for: combinedSummary,
                currentLimit: maximumCharacters
            ),
            depth: depth + 1
        )
    }

    // Handles one section of text and recurses only when the section still exceeds the limit.
    private func summarizeSectionHierarchically(
        _ text: String,
        language: TextLanguage,
        maximumCharacters: Int,
        depth: Int
    ) async throws -> String {
        let sections = Self.splitForSummarization(text, maximumCharacters: maximumCharacters)

        guard !sections.isEmpty else {
            throw FileSummarizationError.emptyInput
        }

        if sections.count > 1 {
            var childSummaries: [String] = []
            childSummaries.reserveCapacity(sections.count)

            for section in sections {
                try Task.checkCancellation()
                let summary = try await summarizeSectionHierarchically(
                    section,
                    language: language,
                    maximumCharacters: Self.nextSmallerCharacterLimit(for: section, currentLimit: maximumCharacters),
                    depth: depth + 1
                )
                childSummaries.append(summary)
            }

            guard !childSummaries.isEmpty else {
                throw FileSummarizationError.emptyInput
            }

            let combinedChildSummary = Self.normalizedSummary(from: childSummaries, language: language)
            if combinedChildSummary.count <= maximumCharacters || depth >= Self.maximumHierarchyDepth {
                return combinedChildSummary
            }

            return try await summarizeSectionHierarchically(
                combinedChildSummary,
                language: language,
                maximumCharacters: Self.nextSmallerCharacterLimit(
                    for: combinedChildSummary,
                    currentLimit: maximumCharacters
                ),
                depth: depth + 1
        )
    }

        do {
            return try await summarizeSingleSection(sections[0], language: language)
        } catch let error as LanguageModelSession.GenerationError {
            guard Self.shouldSplitFurther(error: error), maximumCharacters > 1 else {
                throw Self.generationFailed(error: error, language: language)
            }

            return try await summarizeSectionHierarchically(
                sections[0],
                language: language,
                maximumCharacters: Self.nextSmallerCharacterLimit(
                    for: sections[0],
                    currentLimit: maximumCharacters
                ),
                depth: depth + 1
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw FileSummarizationError.generationFailed(error.localizedDescription)
        }
    }

    private func summarizeSingleSection(_ section: String, language: TextLanguage) async throws -> String {
        #if canImport(FoundationModels)
        guard #available(macOS 15.0, *) else {
            throw FileSummarizationError.unavailable
        }

        let model = SystemLanguageModel.default
        guard model.availability == .available else {
            throw FileSummarizationError.unavailable
        }

        let instructions = """
        You are a careful document summarizer.
        Summarize the provided text in \(Self.summaryLanguageName(for: language)).
        Write in plain prose only.
        Do not use bullets, numbering, headings, or markdown.
        Keep names, numbers, and important facts accurate.
        Keep the response concise enough to be read aloud naturally.
        """

        let prompt = """
        Summarize this section of a longer document:

        \(section)
        """

        do {
            let session = LanguageModelSession(model: model, tools: [], instructions: instructions)
            var options = GenerationOptions()
            options.maximumResponseTokens = Self.maximumResponseTokens
            return try await session.respond(to: prompt, options: options).content
        } catch let error as LanguageModelSession.GenerationError {
            if case .unsupportedLanguageOrLocale = error {
                if language != .english {
                    return try await summarizeSingleSection(section, language: .english)
                }
                throw FileSummarizationError.generationFailed(
                    "Apple Intelligence could not summarize this file in the detected language."
                )
            }

            if case .guardrailViolation = error {
                return Self.extractiveFallbackSummary(from: section, language: language)
            }

            throw Self.generationFailed(error: error, language: language)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw FileSummarizationError.generationFailed(error.localizedDescription)
        }
        #else
        throw FileSummarizationError.unavailable
        #endif
    }

    nonisolated static func resolvedLanguage(for language: TextLanguage) -> TextLanguage {
        language == .unknown ? .english : language
    }

    nonisolated static func normalizedSummary(from sectionSummaries: [String], language: TextLanguage) -> String {
        let combinedSummary = sectionSummaries.joined(separator: "\n\n")
        return TextNormalizationService.normalize(combinedSummary, language: language)
    }

    nonisolated static func shouldSplitFurther(error: LanguageModelSession.GenerationError) -> Bool {
        if case .exceededContextWindowSize = error {
            return true
        }

        return false
    }

    nonisolated static func generationFailed(error: LanguageModelSession.GenerationError, language: TextLanguage) -> FileSummarizationError {
        if case .unsupportedLanguageOrLocale = error {
            if language != .english {
                return .generationFailed("Apple Intelligence could not summarize this file in the detected language.")
            }
        }

        if case .exceededContextWindowSize = error {
            return .generationFailed("The summary request was too large for the model context window.")
        }

        return .generationFailed(error.localizedDescription)
    }

    nonisolated static func nextSmallerCharacterLimit(for text: String, currentLimit: Int) -> Int {
        let halvedLimit = max(1, currentLimit / 2)
        let textBasedLimit = max(1, text.count / 2)
        return min(halvedLimit, textBasedLimit)
    }

    nonisolated static func extractiveFallbackSummary(from text: String, language: TextLanguage) -> String {
        let normalizedText = TextNormalizationService.normalize(text, language: language)
        let paragraphs = normalizedText
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var excerpts: [String] = []
        var totalCharacterCount = 0
        let maximumCharacterCount = 900

        for paragraph in paragraphs.prefix(4) {
            let sentences = splitIntoSentences(paragraph, language: language)
            let candidate = sentences.prefix(2).joined(separator: " ")
            let excerpt = candidate.isEmpty ? paragraph : candidate
            guard !excerpt.isEmpty else { continue }

            let remainingBudget = maximumCharacterCount - totalCharacterCount
            guard remainingBudget > 0 else { break }

            if excerpt.count <= remainingBudget {
                excerpts.append(excerpt)
                totalCharacterCount += excerpt.count
            } else {
                let truncated = String(excerpt.prefix(remainingBudget)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !truncated.isEmpty {
                    excerpts.append(truncated)
                }
                break
            }
        }

        if excerpts.isEmpty {
            let fallbackText = String(normalizedText.prefix(maximumCharacterCount)).trimmingCharacters(in: .whitespacesAndNewlines)
            return fallbackText.isEmpty ? "No readable text was available for summarization." : fallbackText
        }

        let joined = excerpts.joined(separator: " ")
        return joined.count < normalizedText.count ? "\(joined)..." : joined
    }

    nonisolated static func splitIntoSentences(_ text: String, language: TextLanguage) -> [String] {
        let pattern: String
        switch language {
        case .mandarin, .japanese:
            pattern = #"(?<=[。！？!?；;…])\s*"#
        case .hindi, .punjabi:
            pattern = #"(?<=[।॥!?؛;…])\s*"#
        default:
            pattern = #"(?<=[.!?])\s+"#
        }

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [text]
        }

        let range = NSRange(text.startIndex..., in: text)
        var sentences: [String] = []
        var previousUpperBound = text.startIndex

        regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match, let splitRange = Range(match.range, in: text) else { return }
            let segment = String(text[previousUpperBound..<splitRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !segment.isEmpty {
                sentences.append(segment)
            }
            previousUpperBound = splitRange.upperBound
        }

        let remainder = String(text[previousUpperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !remainder.isEmpty {
            sentences.append(remainder)
        }

        return sentences.isEmpty ? [text] : sentences
    }

    nonisolated static func splitForSummarization(_ text: String, maximumCharacters: Int) -> [String] {
        let canonical = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let paragraphs = canonical.components(separatedBy: "\n\n")
        var sections: [String] = []
        var buffer = ""

        for paragraph in paragraphs {
            let trimmedParagraph = paragraph
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmedParagraph.isEmpty else { continue }

            if trimmedParagraph.count > maximumCharacters {
                if !buffer.isEmpty {
                    sections.append(buffer)
                    buffer = ""
                }

                sections.append(contentsOf: splitOversizedParagraph(trimmedParagraph, maximumCharacters: maximumCharacters))
                continue
            }

            if buffer.isEmpty {
                buffer = trimmedParagraph
                continue
            }

            if buffer.count + 2 + trimmedParagraph.count <= maximumCharacters {
                buffer += "\n\n"
                buffer += trimmedParagraph
            } else {
                sections.append(buffer)
                buffer = trimmedParagraph
            }
        }

        if !buffer.isEmpty {
            sections.append(buffer)
        }

        return sections
    }

    nonisolated static func splitOversizedParagraph(_ paragraph: String, maximumCharacters: Int) -> [String] {
        let words = paragraph.split(whereSeparator: { $0.isWhitespace })
        guard !words.isEmpty else { return [paragraph] }

        if words.count == 1, paragraph.count > maximumCharacters {
            return splitByCharacterCount(paragraph, maximumCharacters: maximumCharacters)
        }

        var sections: [String] = []
        var buffer = ""

        for word in words {
            if word.count > maximumCharacters {
                if !buffer.isEmpty {
                    sections.append(buffer)
                    buffer = ""
                }

                sections.append(contentsOf: splitByCharacterCount(String(word), maximumCharacters: maximumCharacters))
                continue
            }

            let candidate = buffer.isEmpty ? String(word) : "\(buffer) \(word)"
            if candidate.count <= maximumCharacters {
                buffer = candidate
            } else {
                if !buffer.isEmpty {
                    sections.append(buffer)
                }
                buffer = String(word)
            }
        }

        if !buffer.isEmpty {
            sections.append(buffer)
        }

        return sections
    }

    nonisolated static func splitByCharacterCount(_ text: String, maximumCharacters: Int) -> [String] {
        guard maximumCharacters > 0 else { return [text] }

        var sections: [String] = []
        var startIndex = text.startIndex

        while startIndex < text.endIndex {
            let endIndex = text.index(startIndex, offsetBy: maximumCharacters, limitedBy: text.endIndex) ?? text.endIndex
            sections.append(String(text[startIndex..<endIndex]))
            startIndex = endIndex
        }

        return sections
    }

    nonisolated static func summaryLanguageName(for language: TextLanguage) -> String {
        switch language {
        case .english:
            return "U.S. English"
        case .french:
            return "French"
        case .spanish:
            return "Spanish"
        case .german:
            return "German"
        case .italian:
            return "Italian"
        case .portuguese:
            return "Portuguese"
        case .dutch:
            return "Dutch"
        case .swedish:
            return "Swedish"
        case .turkish:
            return "Turkish"
        case .polish:
            return "Polish"
        case .romanian:
            return "Romanian"
        case .russian:
            return "Russian"
        case .ukrainian:
            return "Ukrainian"
        case .greek:
            return "Greek"
        case .arabic:
            return "Arabic"
        case .hebrew:
            return "Hebrew"
        case .persian:
            return "Persian"
        case .urdu:
            return "Urdu"
        case .hindi:
            return "Hindi"
        case .marathi:
            return "Marathi"
        case .bengali:
            return "Bengali"
        case .punjabi:
            return "Punjabi"
        case .tamil:
            return "Tamil"
        case .telugu:
            return "Telugu"
        case .vietnamese:
            return "Vietnamese"
        case .thai:
            return "Thai"
        case .indonesian:
            return "Indonesian"
        case .malay:
            return "Malay"
        case .korean:
            return "Korean"
        case .japanese:
            return "Japanese"
        case .mandarin:
            return "Mandarin"
        case .unknown:
            return "U.S. English"
        }
    }
}
