//
//  TextNormalizationService.swift
//  Anything Reader
//
//  Cleans raw text before chunking and synthesis.
//

import Foundation
import NaturalLanguage

// Normalizes imported and pasted text into a stable, TTS-friendly form.
enum TextNormalizationService {
    // Version bump when the normalization rules change in a way that should invalidate older output.
    static let normalizationVersion = 2

    // Uses script heuristics first, then falls back to language detection when needed.
    nonisolated static func detectLanguage(for text: String) -> TextLanguage {
        let sampleText = sampleTextForDetection(from: text)

        guard !sampleText.isEmpty else {
            return .unknown
        }

        if containsCharacters(in: sampleText, ranges: [
            0x3040...0x309F, // Hiragana
            0x30A0...0x30FF, // Katakana
            0x31F0...0x31FF, // Katakana phonetic extensions
            0xFF66...0xFF9D  // Halfwidth katakana
        ]) {
            return .japanese
        }

        if containsCharacters(in: sampleText, ranges: [
            0x0A00...0x0A7F // Gurmukhi
        ]) {
            return .punjabi
        }

        if containsCharacters(in: sampleText, ranges: [
            0x0900...0x097F // Devanagari
        ]) {
            return .hindi
        }

        if containsCharacters(in: sampleText, ranges: [
            0x0980...0x09FF // Bengali
        ]) {
            return .bengali
        }

        if containsCharacters(in: sampleText, ranges: [
            0x0B80...0x0BFF // Tamil
        ]) {
            return .tamil
        }

        if containsCharacters(in: sampleText, ranges: [
            0x0C00...0x0C7F // Telugu
        ]) {
            return .telugu
        }

        if containsCharacters(in: sampleText, ranges: [
            0x0590...0x05FF // Hebrew
        ]) {
            return .hebrew
        }

        if containsCharacters(in: sampleText, ranges: [
            0x0600...0x06FF, // Arabic
            0x0750...0x077F, // Arabic Supplement
            0x08A0...0x08FF  // Arabic Extended-A
        ]) {
            return .arabic
        }

        if containsCharacters(in: sampleText, ranges: [
            0x0370...0x03FF // Greek and Coptic
        ]) {
            return .greek
        }

        if containsCharacters(in: sampleText, ranges: [
            0x0400...0x04FF, // Cyrillic
            0x0500...0x052F  // Cyrillic Supplement
        ]) {
            return .russian
        }

        if containsCharacters(in: sampleText, ranges: [
            0xAC00...0xD7AF // Hangul Syllables
        ]) {
            return .korean
        }

        if containsCharacters(in: sampleText, ranges: [
            0x4E00...0x9FFF, // CJK Unified Ideographs
            0x3400...0x4DBF, // CJK Extension A
            0xF900...0xFAFF  // CJK Compatibility Ideographs
        ]) {
            return .mandarin
        }

        let recognizerLanguage = NLLanguageRecognizer.dominantLanguage(for: sampleText)
        guard let recognizerLanguage else {
            return .english
        }

        return textLanguage(for: recognizerLanguage.rawValue)
    }

    // Converts raw imported text into a canonical form with normalized spacing and punctuation.
    nonisolated static func normalize(_ text: String, language: TextLanguage? = nil) -> String {
        let resolvedLanguage = language ?? detectLanguage(for: text)
        let canonical = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{200C}", with: "")
            .replacingOccurrences(of: "\u{200D}", with: "")
            .replacingOccurrences(of: "\u{FEFF}", with: "")

        let lines = canonical.split(separator: "\n", omittingEmptySubsequences: false).map { rawLine in
            normalizeLine(String(rawLine), language: resolvedLanguage)
        }

        let collapsed = lines.joined(separator: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)

        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Applies language-specific spacing and punctuation cleanup to a single line.
    nonisolated private static func normalizeLine(_ line: String, language: TextLanguage) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        var normalized = trimmed

        switch language {
        case .mandarin, .japanese, .korean, .arabic, .hebrew, .persian, .urdu, .hindi, .marathi, .bengali, .punjabi, .tamil, .telugu, .thai, .unknown:
            normalized = normalized.replacingOccurrences(of: "\t", with: " ")
            normalized = normalized.replacingOccurrences(
                of: "\\s{2,}",
                with: " ",
                options: .regularExpression
            )
        case .english, .french, .spanish, .german, .italian, .portuguese, .dutch, .swedish, .turkish, .polish, .romanian, .russian, .ukrainian, .greek, .vietnamese, .indonesian, .malay:
            let substitutions: [(String, String)] = [
                ("“", "\""),
                ("”", "\""),
                ("„", "\""),
                ("‟", "\""),
                ("‘", "'"),
                ("’", "'"),
                ("‚", "'"),
                ("‛", "'"),
                ("—", " - "),
                ("–", " - "),
                ("−", "-"),
                ("•", "- "),
                ("·", "- "),
                ("…", "..."),
                ("‹", "<"),
                ("›", ">"),
                ("\t", " ")
            ]

            for (source, replacement) in substitutions {
                normalized = normalized.replacingOccurrences(of: source, with: replacement)
            }

            normalized = normalized.replacingOccurrences(
                of: "\\s{2,}",
                with: " ",
                options: .regularExpression
            )

            normalized = normalized.replacingOccurrences(
                of: "\\s+([,.;:!?])",
                with: "$1",
                options: .regularExpression
            )
        }

        return normalized
    }

    nonisolated private static func sampleTextForDetection(from text: String) -> String {
        let compact = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !compact.isEmpty else { return "" }
        return String(compact.prefix(4_000))
    }

    nonisolated private static func containsCharacters(in text: String, ranges: [ClosedRange<UInt32>]) -> Bool {
        text.unicodeScalars.contains { scalar in
            ranges.contains { $0.contains(scalar.value) }
        }
    }

    nonisolated private static func textLanguage(for identifier: String) -> TextLanguage {
        switch identifier.lowercased() {
        case "en":
            return .english
        case "fr":
            return .french
        case "es":
            return .spanish
        case "de":
            return .german
        case "it":
            return .italian
        case "pt":
            return .portuguese
        case "nl":
            return .dutch
        case "sv":
            return .swedish
        case "tr":
            return .turkish
        case "pl":
            return .polish
        case "ro":
            return .romanian
        case "ru":
            return .russian
        case "uk":
            return .ukrainian
        case "el":
            return .greek
        case "ar":
            return .arabic
        case "he":
            return .hebrew
        case "fa":
            return .persian
        case "ur":
            return .urdu
        case "ja":
            return .japanese
        case "hi":
            return .hindi
        case "mr":
            return .marathi
        case "bn":
            return .bengali
        case "pa":
            return .punjabi
        case "ta":
            return .tamil
        case "te":
            return .telugu
        case "vi":
            return .vietnamese
        case "th":
            return .thai
        case "id":
            return .indonesian
        case "ms":
            return .malay
        case "ko":
            return .korean
        case "zh", "zh-hans", "zh-hant":
            return .mandarin
        default:
            return .english
        }
    }
}
