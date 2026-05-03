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
        formattedList(from: authors, fallback: "Unknown author")
    }

    var displayLanguages: String {
        formattedList(from: languages, fallback: "Unknown language")
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

    private func formattedList(from value: String?, fallback: String) -> String {
        let items = Self.listValues(from: value)
        guard !items.isEmpty else { return fallback }
        if items.count == 1 { return items[0] }
        return items.prefix(3).joined(separator: " · ")
    }

    static func listValues(from value: String?) -> [String] {
        guard let value else { return [] }

        return value
            .components(separatedBy: CharacterSet(charactersIn: "\n;|"))
            .flatMap { $0.components(separatedBy: " / ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, item in
                if !result.contains(item) {
                    result.append(item)
                }
            }
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
