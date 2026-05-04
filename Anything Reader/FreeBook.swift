//
//  FreeBook.swift
//  Anything Reader
//
//  Lightweight view model for rows loaded from the free books SQLite catalog.
//

import Foundation

struct FreeBook: Identifiable, Hashable {
    let id: Int64
    let title: String
    let authors: String?
    let languages: String?
    let subjects: String?
    let bookshelves: String?
    let epub: String?
    let pdf: String?
    let txt: String?
    let html: String?
    let cover: String?

    var availableFormats: [String] {
        var formats: [String] = []

        if isUsableLink(epub) { formats.append("epub") }
        if isUsableLink(pdf) { formats.append("pdf") }
        if isUsableLink(txt) { formats.append("txt") }
        if isUsableLink(html) { formats.append("html") }

        return formats
    }

    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var displayAuthors: String {
        formattedList(
            from: authors,
            fallback: "Unknown author",
            transform: Self.displayAuthorName
        )
    }

    var displayLanguages: String {
        formattedList(
            from: languages,
            fallback: "Unknown language",
            transform: Self.displayLanguageName
        )
    }

    var displaySubjects: String {
        formattedList(from: subjects, fallback: "No subject")
    }

    var displayBookshelves: String {
        formattedList(from: bookshelves, fallback: "No bookshelf")
    }

    var displayFormat: String {
        availableFormats.first?.uppercased() ?? "Unknown"
    }

    var coverURL: URL? {
        guard let cover else { return nil }

        let trimmed = cover.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }

        return URL(fileURLWithPath: trimmed)
    }

    var htmlURL: URL? {
        guard let html else { return nil }

        for candidate in Self.listValues(from: html) + [html] {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if let url = Self.makeURL(from: trimmed) {
                return url
            }
        }

        return nil
    }

    var inAppHTMLURL: URL? {
        guard let htmlURL else { return nil }
        return Self.preferredWebViewURL(for: htmlURL)
    }

    var txtURL: URL? {
        guard let txt else { return nil }

        for candidate in Self.listValues(from: txt) + [txt] {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if let url = Self.makeURL(from: trimmed) {
                return url
            }
        }

        return nil
    }

    var preferredTXTDownloadURL: URL? {
        guard let txtURL else { return nil }
        return Self.preferredTXTDownloadURL(for: txtURL)
    }

    var primaryLanguage: TextLanguage? {
        Self.listValues(from: languages)
            .compactMap { Self.catalogTextLanguage(from: $0) }
            .first
    }

    private func formattedList(
        from value: String?,
        fallback: String,
        transform: ((String) -> String)? = nil
    ) -> String {
        let items = Self.listValues(from: value).map { transform?($0) ?? $0 }
        guard !items.isEmpty else { return fallback }
        if items.count == 1 { return items[0] }
        return items.prefix(3).joined(separator: " · ")
    }

    nonisolated static func listValues(from value: String?) -> [String] {
        guard let value else { return [] }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimCollectionWrappers(trimmed)

        return normalized
            .components(separatedBy: CharacterSet(charactersIn: "\n;|"))
            .flatMap { $0.components(separatedBy: " / ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { trimCollectionWrappers($0) }
            .filter { !$0.isEmpty }
            .map { stripSurroundingQuotes($0) }
            .reduce(into: [String]()) { result, item in
                if !result.contains(item) {
                    result.append(item)
                }
            }
    }

    nonisolated static func displayAuthorName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        if trimmed.contains(",") {
            let components = trimmed.split(separator: ",", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if components.count >= 2 {
                return ([components[1]] + components.dropFirst(2)).joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return trimmed
    }

    nonisolated static func displayLanguageName(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return value }

        if let languageName = languageCodeName(for: normalized) {
            return languageName
        }

        return value
    }

    nonisolated private static func languageCodeName(for code: String) -> String? {
        switch code {
        case "en", "eng", "en-us", "en-gb":
            return "English"
        case "fr", "fre", "fra":
            return "French"
        case "es", "spa":
            return "Spanish"
        case "de", "ger", "deu":
            return "German"
        case "it", "ita":
            return "Italian"
        case "pt", "por":
            return "Portuguese"
        case "nl", "dut", "nld":
            return "Dutch"
        case "sv", "swe":
            return "Swedish"
        case "tr", "tur":
            return "Turkish"
        case "pl", "pol":
            return "Polish"
        case "ro", "rum", "ron":
            return "Romanian"
        case "ru", "rus":
            return "Russian"
        case "uk", "ukr":
            return "Ukrainian"
        case "el", "ell":
            return "Greek"
        case "ar", "ara":
            return "Arabic"
        case "he", "heb":
            return "Hebrew"
        case "fa", "fas", "per":
            return "Persian"
        case "ur", "urd":
            return "Urdu"
        case "hi", "hin":
            return "Hindi"
        case "mr", "mar":
            return "Marathi"
        case "bn", "ben":
            return "Bengali"
        case "pa", "pan":
            return "Punjabi"
        case "ta", "tam":
            return "Tamil"
        case "te", "tel":
            return "Telugu"
        case "vi", "vie":
            return "Vietnamese"
        case "th", "tha":
            return "Thai"
        case "id", "ind":
            return "Indonesian"
        case "msa", "may", "ms":
            return "Malay"
        case "ko", "kor":
            return "Korean"
        case "ja", "jpn":
            return "Japanese"
        case "zho", "zh-hans", "zh":
            return "Mandarin"
        default:
            return nil
        }
    }

    nonisolated private static func trimCollectionWrappers(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("[") && result.hasSuffix("]") {
            result.removeFirst()
            result.removeLast()
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func stripSurroundingQuotes(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("\"") && result.hasSuffix("\"") && result.count >= 2 {
            result.removeFirst()
            result.removeLast()
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func makeURL(from value: String) -> URL? {
        if let url = URL(string: value), url.scheme != nil {
            return httpsIfNeeded(url)
        }

        if value.hasPrefix("//"), let url = URL(string: "https:\(value)") {
            return url
        }

        if value.hasPrefix("www."), let url = URL(string: "https://\(value)") {
            return url
        }

        if value.hasPrefix("/ebooks/") || value.hasPrefix("/files/") {
            return URL(string: "https://www.gutenberg.org\(value)")
        }

        if value.contains("gutenberg.org"), let url = URL(string: "https://\(value)") {
            return url
        }

        return nil
    }

    nonisolated private static func httpsIfNeeded(_ url: URL) -> URL {
        guard url.scheme == "http", url.host?.contains("gutenberg.org") == true else {
            return url
        }

        let httpsString = url.absoluteString.replacingOccurrences(
            of: "http://",
            with: "https://",
            options: [.anchored]
        )
        return URL(string: httpsString) ?? url
    }

    nonisolated private static func catalogTextLanguage(from value: String) -> TextLanguage? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }

        switch normalized {
        case "en", "eng", "english":
            return .english
        case "fr", "fre", "fra", "french":
            return .french
        case "es", "spa", "spanish":
            return .spanish
        case "de", "ger", "deu", "german":
            return .german
        case "it", "ita", "italian":
            return .italian
        case "pt", "por", "portuguese":
            return .portuguese
        case "nl", "dut", "nld", "dutch":
            return .dutch
        case "sv", "swe", "swedish":
            return .swedish
        case "tr", "tur", "turkish":
            return .turkish
        case "pl", "pol", "polish":
            return .polish
        case "ro", "rum", "ron", "romanian":
            return .romanian
        case "ru", "rus", "russian":
            return .russian
        case "uk", "ukr", "ukrainian":
            return .ukrainian
        case "el", "ell", "greek":
            return .greek
        case "ar", "ara", "arabic":
            return .arabic
        case "he", "heb", "hebrew":
            return .hebrew
        case "fa", "fas", "per", "persian":
            return .persian
        case "ur", "urd", "urdu":
            return .urdu
        case "hi", "hin", "hindi":
            return .hindi
        case "mr", "mar", "marathi":
            return .marathi
        case "bn", "ben", "bengali":
            return .bengali
        case "pa", "pan", "punjabi":
            return .punjabi
        case "ta", "tam", "tamil":
            return .tamil
        case "te", "tel", "telugu":
            return .telugu
        case "vi", "vie", "vietnamese":
            return .vietnamese
        case "th", "tha", "thai":
            return .thai
        case "id", "ind", "indonesian":
            return .indonesian
        case "ms", "msa", "may", "malay":
            return .malay
        case "ko", "kor", "korean":
            return .korean
        case "ja", "jpn", "japanese":
            return .japanese
        case "zh", "zho", "zh-hans", "zh-hant", "mandarin", "chinese":
            return .mandarin
        default:
            return nil
        }
    }

    nonisolated private static func preferredWebViewURL(for url: URL) -> URL? {
        guard url.host?.contains("gutenberg.org") == true else {
            return url
        }

        let path = url.path.lowercased()
        guard path.contains("/ebooks/") else {
            return url.scheme == "http" ? httpsURL(from: url) : url
        }

        let lastComponent = url.lastPathComponent
        let components = lastComponent.split(separator: ".").map(String.init)
        guard let identifier = components.first, let bookID = Int(identifier) else {
            return url.scheme == "http" ? httpsURL(from: url) : url
        }

        let variant: String
        if components.contains("images") {
            variant = "images"
        } else if components.contains("noimages") {
            variant = "noimages"
        } else {
            variant = "noimages"
        }

        return URL(string: "https://www.gutenberg.org/cache/epub/\(bookID)/pg\(bookID)-\(variant).html")
            ?? (url.scheme == "http" ? httpsURL(from: url) : url)
    }

    nonisolated private static func preferredTXTDownloadURL(for url: URL) -> URL {
//        guard url.host?.contains("gutenberg.org") == true else {
//            return url
//        }
//
//        if let bookID = gutenbergBookID(from: url) {
//            let canonical = "https://www.gutenberg.org/ebooks/\(bookID).txt.utf-8"
//            return URL(string: canonical) ?? httpsIfNeeded(url)
//        }

        return httpsIfNeeded(url)
    }

    nonisolated private static func gutenbergBookID(from url: URL) -> Int? {
        let pathComponents = url.pathComponents.compactMap { component -> Int? in
            let digits = component.filter(\.isNumber)
            return Int(digits)
        }

        return pathComponents.first
    }

    nonisolated private static func httpsURL(from url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = "https"
        return components.url
    }

    private func isUsableLink(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum FreeBookLanguageFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case english
    case french
    case spanish
    case german
    case italian
    case portuguese
    case dutch
    case swedish
    case turkish
    case polish
    case romanian
    case russian
    case ukrainian
    case greek
    case arabic
    case hebrew
    case persian
    case urdu
    case hindi
    case marathi
    case bengali
    case punjabi
    case tamil
    case telugu
    case vietnamese
    case thai
    case indonesian
    case malay
    case korean
    case japanese
    case mandarin

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all:
            return "All Languages"
        case .english:
            return TextLanguage.english.displayName
        case .french:
            return TextLanguage.french.displayName
        case .spanish:
            return TextLanguage.spanish.displayName
        case .german:
            return TextLanguage.german.displayName
        case .italian:
            return TextLanguage.italian.displayName
        case .portuguese:
            return TextLanguage.portuguese.displayName
        case .dutch:
            return TextLanguage.dutch.displayName
        case .swedish:
            return TextLanguage.swedish.displayName
        case .turkish:
            return TextLanguage.turkish.displayName
        case .polish:
            return TextLanguage.polish.displayName
        case .romanian:
            return TextLanguage.romanian.displayName
        case .russian:
            return TextLanguage.russian.displayName
        case .ukrainian:
            return TextLanguage.ukrainian.displayName
        case .greek:
            return TextLanguage.greek.displayName
        case .arabic:
            return TextLanguage.arabic.displayName
        case .hebrew:
            return TextLanguage.hebrew.displayName
        case .persian:
            return TextLanguage.persian.displayName
        case .urdu:
            return TextLanguage.urdu.displayName
        case .hindi:
            return TextLanguage.hindi.displayName
        case .marathi:
            return TextLanguage.marathi.displayName
        case .bengali:
            return TextLanguage.bengali.displayName
        case .punjabi:
            return TextLanguage.punjabi.displayName
        case .tamil:
            return TextLanguage.tamil.displayName
        case .telugu:
            return TextLanguage.telugu.displayName
        case .vietnamese:
            return TextLanguage.vietnamese.displayName
        case .thai:
            return TextLanguage.thai.displayName
        case .indonesian:
            return TextLanguage.indonesian.displayName
        case .malay:
            return TextLanguage.malay.displayName
        case .korean:
            return TextLanguage.korean.displayName
        case .japanese:
            return TextLanguage.japanese.displayName
        case .mandarin:
            return TextLanguage.mandarin.displayName
        }
    }

    var queryAliases: [String] {
        switch self {
        case .all:
            return []
        case .english:
            return ["en", "eng", "english"]
        case .french:
            return ["fr", "fra", "fre", "french"]
        case .spanish:
            return ["es", "spa", "spanish"]
        case .german:
            return ["de", "deu", "ger", "german"]
        case .italian:
            return ["it", "ita", "italian"]
        case .portuguese:
            return ["pt", "por", "portuguese"]
        case .dutch:
            return ["nl", "nld", "dut", "dutch"]
        case .swedish:
            return ["sv", "swe", "swedish"]
        case .turkish:
            return ["tr", "tur", "turkish"]
        case .polish:
            return ["pl", "pol", "polish"]
        case .romanian:
            return ["ro", "ron", "rum", "romanian"]
        case .russian:
            return ["ru", "rus", "russian"]
        case .ukrainian:
            return ["uk", "ukr", "ukrainian"]
        case .greek:
            return ["el", "ell", "greek"]
        case .arabic:
            return ["ar", "ara", "arabic"]
        case .hebrew:
            return ["he", "heb", "hebrew"]
        case .persian:
            return ["fa", "fas", "per", "persian"]
        case .urdu:
            return ["ur", "urd", "urdu"]
        case .hindi:
            return ["hi", "hin", "hindi"]
        case .marathi:
            return ["mr", "mar", "marathi"]
        case .bengali:
            return ["bn", "ben", "bengali"]
        case .punjabi:
            return ["pa", "pan", "punjabi"]
        case .tamil:
            return ["ta", "tam", "tamil"]
        case .telugu:
            return ["te", "tel", "telugu"]
        case .vietnamese:
            return ["vi", "vie", "vietnamese"]
        case .thai:
            return ["th", "tha", "thai"]
        case .indonesian:
            return ["id", "ind", "indonesian"]
        case .malay:
            return ["ms", "msa", "may", "malay"]
        case .korean:
            return ["ko", "kor", "korean"]
        case .japanese:
            return ["ja", "jpn", "japanese"]
        case .mandarin:
            return ["zh", "zh-hans", "zh-hant", "chi", "zho", "mandarin", "chinese"]
        }
    }

    var isAll: Bool {
        self == .all
    }
}
