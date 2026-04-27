//
//  KokoroG2PService.swift
//  Anything Reader
//
//  Local phoneme-prep helper used while the Kokoro runtime is being wired up.
//  This avoids a hard dependency on external G2P packages so the app can build cleanly.
//

import Foundation

actor KokoroG2PService {
    static let shared = KokoroG2PService()

    private init() {}

    func phonemize(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return "" }

        return normalized
            .components(separatedBy: .newlines)
            .map { phonemizeLine($0) }
            .joined(separator: " ")
    }

    private func phonemizeLine(_ line: String) -> String {
        let words = line
            .split(whereSeparator: { $0.isWhitespace })
            .map { word -> String in
                let token = word
                    .trimmingCharacters(in: .punctuationCharacters)
                    .lowercased()

                guard !token.isEmpty else { return "" }
                return "[\(token)]"
            }
            .filter { !$0.isEmpty }

        return words.joined(separator: " ")
    }
}
