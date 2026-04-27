//
//  TextNormalizationService.swift
//  Anything Reader
//
//  Cleans raw text before chunking and synthesis.
//

import Foundation

// Normalizes imported and pasted text into a stable, TTS-friendly form.
enum TextNormalizationService {
    static let normalizationVersion = 1

    nonisolated static func normalize(_ text: String) -> String {
        let canonical = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{200C}", with: "")
            .replacingOccurrences(of: "\u{200D}", with: "")
            .replacingOccurrences(of: "\u{FEFF}", with: "")

        let lines = canonical.split(separator: "\n", omittingEmptySubsequences: false).map { rawLine in
            normalizeLine(String(rawLine))
        }

        let collapsed = lines.joined(separator: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)

        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func normalizeLine(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        var normalized = trimmed

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

        return normalized
    }
}
