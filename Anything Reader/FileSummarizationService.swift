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

actor FileSummarizationService {
    static let shared = FileSummarizationService()

    private let sectionCharacterLimit = 6_000
    private let finalSummaryCharacterLimit = 8_000

    private init() {}

    func summarize(text: String, language: TextLanguage) async throws -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw FileSummarizationError.emptyInput
        }

        let resolvedLanguage = language == .unknown ? .english : language
        let sections = splitForSummarization(trimmedText, maximumCharacters: sectionCharacterLimit)

        guard !sections.isEmpty else {
            throw FileSummarizationError.emptyInput
        }

        let sectionSummaries = try await summarizeSections(sections, language: resolvedLanguage)
        let combinedSummary = sectionSummaries.joined(separator: "\n\n")
        let normalizedSummary = TextNormalizationService.normalize(combinedSummary, language: resolvedLanguage)

        if normalizedSummary.count <= finalSummaryCharacterLimit {
            return normalizedSummary
        }

        let condensedSections = splitForSummarization(normalizedSummary, maximumCharacters: sectionCharacterLimit)
        let condensedSummaries = try await summarizeSections(condensedSections, language: resolvedLanguage)
        let condensedSummary = condensedSummaries.joined(separator: "\n\n")
        let finalSummary = TextNormalizationService.normalize(condensedSummary, language: resolvedLanguage)

        guard !finalSummary.isEmpty else {
            throw FileSummarizationError.emptyInput
        }

        return finalSummary
    }

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
        Summarize the provided text in \(summaryLanguageName(for: language)).
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
            return try await session.respond(to: prompt).content
        } catch let error as LanguageModelSession.GenerationError {
            if case .unsupportedLanguageOrLocale = error {
                if language != .english {
                    return try await summarizeSingleSection(section, language: .english)
                }
                throw FileSummarizationError.generationFailed(
                    "Apple Intelligence could not summarize this file in the detected language."
                )
            }

            throw FileSummarizationError.generationFailed(error.localizedDescription)
        } catch {
            throw FileSummarizationError.generationFailed(error.localizedDescription)
        }
        #else
        throw FileSummarizationError.unavailable
        #endif
    }

    private func splitForSummarization(_ text: String, maximumCharacters: Int) -> [String] {
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

    private func splitOversizedParagraph(_ paragraph: String, maximumCharacters: Int) -> [String] {
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

    private func splitByCharacterCount(_ text: String, maximumCharacters: Int) -> [String] {
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

    private func summaryLanguageName(for language: TextLanguage) -> String {
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
