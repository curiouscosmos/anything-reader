//
//  RSSArticleScraperService.swift
//  Anything Reader
//
//  Extracts the article title and readable body from a web page using
//  Readability-style heuristics.
//

import AppKit
import Foundation

struct RSSArticleDraft: Sendable {
    let title: String
    let body: String
    let sourceURL: URL
    let imageURL: URL?
}

enum RSSArticleScraperError: LocalizedError {
    case invalidArticleURL
    case unreadablePage
    case emptyArticle

    var errorDescription: String? {
        switch self {
        case .invalidArticleURL:
            return "The article URL is invalid."
        case .unreadablePage:
            return "The article page could not be read."
        case .emptyArticle:
            return "The article did not contain readable content."
        }
    }
}

actor RSSArticleScraperService {
    static let shared = RSSArticleScraperService()

    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    private init() {}

    func scrapeArticle(from url: URL) async throws -> RSSArticleDraft {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw RSSArticleScraperError.invalidArticleURL
        }

        let html = try await fetchHTML(from: url)
        let title = extractTitle(from: html, fallbackURL: url)
        let bodyHTML = extractReadableHTML(from: html)
        let body = htmlToPlainText(bodyHTML)

        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RSSArticleScraperError.emptyArticle
        }

        return RSSArticleDraft(
            title: title,
            body: body,
            sourceURL: url,
            imageURL: extractImageURL(from: html, baseURL: url)
        )
    }

    private func fetchHTML(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw RSSArticleScraperError.unreadablePage
        }

        return decodeHTML(from: data, response: response)
    }

    private func decodeHTML(from data: Data, response: URLResponse) -> String {
        if let httpResponse = response as? HTTPURLResponse,
           let charsetName = httpResponse.textEncodingName,
           let encoding = String.Encoding(ianaName: charsetName),
           let html = String(data: data, encoding: encoding) {
            return html
        }

        if let html = String(data: data, encoding: .utf8) {
            return html
        }

        if let html = String(data: data, encoding: .isoLatin1) {
            return html
        }

        return String(decoding: data, as: UTF8.self)
    }

    private func extractTitle(from html: String, fallbackURL: URL) -> String {
        let candidates = [
            metaContent(in: html, names: ["og:title", "twitter:title"]),
            firstHeading(in: html),
            titleTag(in: html)
        ]

        for candidate in candidates.compactMap({ $0 }) {
            let cleaned = sanitizeTitle(candidate)
            if !cleaned.isEmpty {
                return cleaned
            }
        }

        return fallbackURL.host ?? fallbackURL.absoluteString
    }

    private func extractImageURL(from html: String, baseURL: URL) -> URL? {
        let candidates = [
            metaContent(in: html, names: ["og:image", "twitter:image", "twitter:image:src"]),
            linkHref(in: html, rel: "image_src")
        ]

        for candidate in candidates.compactMap({ $0 }) {
            if let absoluteURL = URL(string: candidate, relativeTo: baseURL)?.absoluteURL {
                return absoluteURL
            }
        }

        return nil
    }

    private func extractReadableHTML(from html: String) -> String {
        let candidateFragments = [
            firstMatch(in: html, pattern: #"(?is)<article\b[^>]*>(.*?)</article>"#),
            firstMatch(in: html, pattern: #"(?is)<main\b[^>]*>(.*?)</main>"#),
            firstMatch(in: html, pattern: #"(?is)<div\b[^>]*role=["']main["'][^>]*>(.*?)</div>"#),
            firstMatch(in: html, pattern: #"(?is)<section\b[^>]*itemprop=["']articleBody["'][^>]*>(.*?)</section>"#),
            bodyInnerHTML(from: html)
        ]

        let cleaned = candidateFragments
            .compactMap { $0 }
            .map { sanitizeArticleHTML($0) }
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })

        return cleaned ?? ""
    }

    private func bodyInnerHTML(from html: String) -> String? {
        guard let bodyMatch = firstMatch(in: html, pattern: #"(?is)<body\b[^>]*>(.*?)</body>"#) else {
            return nil
        }
        return bodyMatch
    }

    private func sanitizeArticleHTML(_ html: String) -> String {
        var sanitized = html
        sanitized = sanitized.replacingOccurrences(
            of: #"(?is)<!--.*?-->"#,
            with: " ",
            options: .regularExpression
        )
        sanitized = removeTagBlocks(
            sanitized,
            tags: ["script", "style", "nav", "footer", "header", "aside", "form", "noscript", "iframe", "svg"]
        )
        sanitized = sanitized.replacingOccurrences(
            of: #"(?is)<br\s*/?>"#,
            with: "\n",
            options: .regularExpression
        )
        sanitized = sanitized.replacingOccurrences(
            of: #"(?is)</p\s*>"#,
            with: "\n\n",
            options: .regularExpression
        )
        sanitized = sanitized.replacingOccurrences(
            of: #"(?is)</div\s*>"#,
            with: "\n",
            options: .regularExpression
        )
        sanitized = sanitized.replacingOccurrences(
            of: #"(?is)</li\s*>"#,
            with: "\n",
            options: .regularExpression
        )
        sanitized = sanitized.replacingOccurrences(
            of: #"(?is)</h[1-6]\s*>"#,
            with: "\n\n",
            options: .regularExpression
        )
        sanitized = sanitized.replacingOccurrences(
            of: #"(?is)<li\b[^>]*>"#,
            with: "• ",
            options: .regularExpression
        )
        return sanitized
    }

    private func removeTagBlocks(_ html: String, tags: [String]) -> String {
        tags.reduce(html) { current, tag in
            current.replacingOccurrences(
                of: #"(?is)<\#(tag)\b[^>]*>.*?</\#(tag)>"#,
                with: " ",
                options: .regularExpression
            )
        }
    }

    private func htmlToPlainText(_ html: String) -> String {
        let wrappedHTML = """
        <html>
          <head>
            <meta charset=\"utf-8\">
          </head>
          <body>
            \(html)
          </body>
        </html>
        """

        if let data = wrappedHTML.data(using: .utf8),
           let attributed = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
           ) {
            return normalizePlainText(attributed.string)
        }

        return normalizePlainText(html)
    }

    private func normalizePlainText(_ text: String) -> String {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: #"(?m)^[ \t]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?m)[ \t]+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?m)\n{3,}"#, with: "\n\n", options: .regularExpression)

        return lines.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitizeTitle(_ title: String) -> String {
        title
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func metaContent(in html: String, names: [String]) -> String? {
        for name in names {
            let patterns = [
                #"(?is)<meta\b[^>]*(?:property|name)=["']\#(name)["'][^>]*content=["']([^"']+)["'][^>]*>"#,
                #"(?is)<meta\b[^>]*content=["']([^"']+)["'][^>]*(?:property|name)=["']\#(name)["'][^>]*>"#
            ]

            for pattern in patterns {
                if let match = firstCapturingGroup(in: html, pattern: pattern) {
                    return match
                }
            }
        }
        return nil
    }

    private func linkHref(in html: String, rel: String) -> String? {
        let patterns = [
            #"(?is)<link\b[^>]*rel=["']\#(rel)["'][^>]*href=["']([^"']+)["'][^>]*>"#,
            #"(?is)<link\b[^>]*href=["']([^"']+)["'][^>]*rel=["']\#(rel)["'][^>]*>"#
        ]

        for pattern in patterns {
            if let match = firstCapturingGroup(in: html, pattern: pattern) {
                return match
            }
        }
        return nil
    }

    private func firstHeading(in html: String) -> String? {
        firstCapturingGroup(in: html, pattern: #"(?is)<h1\b[^>]*>(.*?)</h1>"#)
            .map { htmlToPlainText($0) }
    }

    private func titleTag(in html: String) -> String? {
        firstCapturingGroup(in: html, pattern: #"(?is)<title\b[^>]*>(.*?)</title>"#)
            .map { htmlToPlainText($0) }
    }

    private func firstMatch(in html: String, pattern: String) -> String? {
        guard let match = firstCapturingGroup(in: html, pattern: pattern) else { return nil }
        return match
    }

    private func firstCapturingGroup(in html: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[captureRange])
    }
}
