//
//  Item.swift
//  Anything Reader
//
//  Created by Daman Mehta on 2026-04-24.
//

import Foundation
import SwiftData

enum ReaderSourceKind: String, CaseIterable, Identifiable {
    case pdf
    case epub
    case text
    case pastedText
    case image

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pdf:
            return "PDF"
        case .epub:
            return "ePub"
        case .text:
            return "Text"
        case .pastedText:
            return "Paste"
        case .image:
            return "Image"
        }
    }

    var systemImage: String {
        switch self {
        case .pdf:
            return "doc.richtext.fill"
        case .epub:
            return "book.fill"
        case .text:
            return "doc.text.fill"
        case .pastedText:
            return "doc.on.clipboard.fill"
        case .image:
            return "doc.text.image"
        }
    }
}

enum ReadingStructureKind: String, Codable, CaseIterable, Identifiable {
    case page
    case chapter
    case section

    var id: String { rawValue }
}

enum LibraryEntryImportState: String, Codable, CaseIterable, Identifiable {
    case importing
    case ready
    case failed

    var id: String { rawValue }
}

enum PDFExtractionMode: String, Codable, CaseIterable, Identifiable {
    case directText
    case ocr
    case hybrid
    case unknown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .directText:
            return "Direct Text"
        case .ocr:
            return "OCR"
        case .hybrid:
            return "Hybrid"
        case .unknown:
            return "Unknown"
        }
    }
}

enum TextLanguage: String, Codable, CaseIterable, Identifiable {
    case english = "en"
    case french = "fr"
    case spanish = "es"
    case german = "de"
    case italian = "it"
    case portuguese = "pt"
    case dutch = "nl"
    case swedish = "sv"
    case turkish = "tr"
    case polish = "pl"
    case romanian = "ro"
    case russian = "ru"
    case ukrainian = "uk"
    case greek = "el"
    case arabic = "ar"
    case hebrew = "he"
    case persian = "fa"
    case urdu = "ur"
    case hindi = "hi"
    case marathi = "mr"
    case bengali = "bn"
    case punjabi = "pa"
    case tamil = "ta"
    case telugu = "te"
    case vietnamese = "vi"
    case thai = "th"
    case indonesian = "id"
    case malay = "ms"
    case korean = "ko"
    case japanese = "ja"
    case mandarin = "zh-Hans"
    case unknown = "und"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english:
            return "English"
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
            return "Unknown"
        }
    }

    var isConservativeNormalizationLanguage: Bool {
        switch self {
        case .mandarin, .japanese, .korean, .arabic, .hebrew, .persian, .urdu, .hindi, .marathi, .bengali, .punjabi, .tamil, .telugu, .thai, .unknown:
            return true
        case .english, .french, .spanish, .german, .italian, .portuguese, .dutch, .swedish, .turkish, .polish, .romanian, .russian, .ukrainian, .greek, .vietnamese, .indonesian, .malay:
            return false
        }
    }

    init?(naturalLanguageIdentifier identifier: String) {
        switch identifier.lowercased() {
        case "en":
            self = .english
        case "fr":
            self = .french
        case "es":
            self = .spanish
        case "de":
            self = .german
        case "it":
            self = .italian
        case "pt":
            self = .portuguese
        case "nl":
            self = .dutch
        case "sv":
            self = .swedish
        case "tr":
            self = .turkish
        case "pl":
            self = .polish
        case "ro":
            self = .romanian
        case "ru":
            self = .russian
        case "uk":
            self = .ukrainian
        case "el":
            self = .greek
        case "ar":
            self = .arabic
        case "he":
            self = .hebrew
        case "fa":
            self = .persian
        case "ur":
            self = .urdu
        case "ja":
            self = .japanese
        case "hi":
            self = .hindi
        case "mr":
            self = .marathi
        case "bn":
            self = .bengali
        case "pa":
            self = .punjabi
        case "ta":
            self = .tamil
        case "te":
            self = .telugu
        case "vi":
            self = .vietnamese
        case "th":
            self = .thai
        case "id":
            self = .indonesian
        case "ms":
            self = .malay
        case "ko":
            self = .korean
        case "zh", "zh-hans", "zh-hant":
            self = .mandarin
        case "und":
            self = .unknown
        default:
            return nil
        }
    }
}

struct ReaderJumpTarget: Codable, Identifiable, Hashable {
    let index: Int
    let title: String

    var id: Int { index }
}

@Model
final class LibraryEntry {
    var title: String
    var subtitle: String
    var sourceKindRawValue: String
    var fileExtension: String
    var originalFileName: String?
    var storedFilePath: String?
    var normalizedTextFilePath: String?
    var coverImageFilePath: String?
    var fileSizeBytes: Int64
    var categoryName: String?
    var avatarSymbolName: String
    var accentName: String
    var phonemeText: String?
    var phonemeUpdatedAt: Date?
    var textLanguageRawValue: String?
    var pdfExtractionModeRawValue: String?
    var readingStructureKindRawValue: String?
    var pageCount: Int
    var chapterCount: Int
    var sectionCount: Int?
    var importStateRawValue: String?
    var generatedAudioFilePath: String?
    var generatedAudioFileName: String?
    var generatedAudioVoiceName: String?
    var generatedAudioUpdatedAt: Date?
    var generatedAudioDurationSeconds: Int?
    var generatedAudioPlaybackPositionSeconds: Int?
    var readingJumpTargetsData: Data?
    var currentReadingPositionIndex: Int?
    var currentReadingPositionTotalCount: Int?
    var progress: Double
    var lastOpened: Date
    var createdAt: Date

    init(
        title: String,
        subtitle: String,
        sourceKind: ReaderSourceKind,
        fileExtension: String,
        originalFileName: String? = nil,
        storedFilePath: String? = nil,
        normalizedTextFilePath: String? = nil,
        coverImageFilePath: String? = nil,
        fileSizeBytes: Int64 = 0,
        categoryName: String? = nil,
        avatarSymbolName: String,
        accentName: String,
        phonemeText: String? = nil,
        phonemeUpdatedAt: Date? = nil,
        textLanguage: TextLanguage? = nil,
        pdfExtractionMode: PDFExtractionMode? = nil,
        readingStructureKind: ReadingStructureKind? = nil,
        pageCount: Int = 0,
        chapterCount: Int = 0,
        sectionCount: Int = 0,
        importState: LibraryEntryImportState? = nil,
        generatedAudioFilePath: String? = nil,
        generatedAudioFileName: String? = nil,
        generatedAudioVoiceName: String? = nil,
        generatedAudioUpdatedAt: Date? = nil,
        generatedAudioDurationSeconds: Int? = nil,
        generatedAudioPlaybackPositionSeconds: Int? = nil,
        readingJumpTargets: [ReaderJumpTarget] = [],
        currentReadingPositionIndex: Int? = nil,
        currentReadingPositionTotalCount: Int? = nil,
        progress: Double = 0.0,
        lastOpened: Date = .now,
        createdAt: Date = .now
    ) {
        self.title = title
        self.subtitle = subtitle
        self.sourceKindRawValue = sourceKind.rawValue
        self.fileExtension = fileExtension
        self.originalFileName = originalFileName
        self.storedFilePath = storedFilePath
        self.normalizedTextFilePath = normalizedTextFilePath
        self.coverImageFilePath = coverImageFilePath
        self.fileSizeBytes = fileSizeBytes
        self.categoryName = categoryName
        self.avatarSymbolName = avatarSymbolName
        self.accentName = accentName
        self.phonemeText = phonemeText
        self.phonemeUpdatedAt = phonemeUpdatedAt
        self.textLanguageRawValue = textLanguage?.rawValue
        self.pdfExtractionModeRawValue = pdfExtractionMode?.rawValue
        self.readingStructureKindRawValue = readingStructureKind?.rawValue
        self.pageCount = pageCount
        self.chapterCount = chapterCount
        self.sectionCount = sectionCount > 0 ? sectionCount : nil
        self.importStateRawValue = importState?.rawValue
        self.generatedAudioFilePath = generatedAudioFilePath
        self.generatedAudioFileName = generatedAudioFileName
        self.generatedAudioVoiceName = generatedAudioVoiceName
        self.generatedAudioUpdatedAt = generatedAudioUpdatedAt
        self.generatedAudioDurationSeconds = generatedAudioDurationSeconds
        self.generatedAudioPlaybackPositionSeconds = generatedAudioPlaybackPositionSeconds
        self.readingJumpTargetsData = Self.encodeJumpTargets(readingJumpTargets)
        self.currentReadingPositionIndex = currentReadingPositionIndex
        self.currentReadingPositionTotalCount = currentReadingPositionTotalCount
        self.progress = progress
        self.lastOpened = lastOpened
        self.createdAt = createdAt
    }

    var sourceKind: ReaderSourceKind {
        ReaderSourceKind(rawValue: sourceKindRawValue) ?? .text
    }

    var cacheIdentity: String {
        [
            sourceKindRawValue,
            title,
            originalFileName ?? "",
            String(createdAt.timeIntervalSince1970)
        ]
        .joined(separator: "|")
    }

    var readingStructureKind: ReadingStructureKind? {
        get {
            guard let readingStructureKindRawValue else { return nil }
            return ReadingStructureKind(rawValue: readingStructureKindRawValue)
        }
        set {
            readingStructureKindRawValue = newValue?.rawValue
        }
    }

    var importState: LibraryEntryImportState? {
        get {
            guard let importStateRawValue else { return nil }
            return LibraryEntryImportState(rawValue: importStateRawValue)
        }
        set {
            importStateRawValue = newValue?.rawValue
        }
    }

    var isImporting: Bool {
        importState == .importing
    }

    var generatedAudioFileURL: URL? {
        guard let generatedAudioFilePath else { return nil }
        return URL(fileURLWithPath: generatedAudioFilePath)
    }

    var generatedAudioPlaybackPosition: TimeInterval {
        TimeInterval(generatedAudioPlaybackPositionSeconds ?? 0)
    }

    var generatedAudioDuration: TimeInterval {
        TimeInterval(generatedAudioDurationSeconds ?? 0)
    }

    var generatedAudioProgressFraction: Double {
        guard let duration = generatedAudioDurationSeconds, duration > 0 else { return 0 }
        return min(max(Double(generatedAudioPlaybackPositionSeconds ?? 0) / Double(duration), 0), 1)
    }

    var textLanguage: TextLanguage? {
        get {
            guard let textLanguageRawValue else { return nil }
            return TextLanguage(rawValue: textLanguageRawValue)
        }
        set {
            textLanguageRawValue = newValue?.rawValue
        }
    }

    var pdfExtractionMode: PDFExtractionMode? {
        get {
            guard let pdfExtractionModeRawValue else { return nil }
            return PDFExtractionMode(rawValue: pdfExtractionModeRawValue)
        }
        set {
            pdfExtractionModeRawValue = newValue?.rawValue
        }
    }

    var readingJumpTargets: [ReaderJumpTarget] {
        get {
            guard let readingJumpTargetsData else { return [] }

            do {
                return try JSONDecoder().decode([ReaderJumpTarget].self, from: readingJumpTargetsData)
            } catch {
                return []
            }
        }
        set {
            readingJumpTargetsData = Self.encodeJumpTargets(newValue)
        }
    }

    var currentReadingProgressFraction: Double {
        guard
            let currentReadingPositionIndex,
            let currentReadingPositionTotalCount,
            currentReadingPositionTotalCount > 0
        else {
            return progress
        }

        let boundedIndex = min(max(currentReadingPositionIndex, 0), currentReadingPositionTotalCount - 1)
        return Double(boundedIndex + 1) / Double(currentReadingPositionTotalCount)
    }

    var currentReadingPositionDisplayText: String? {
        guard
            let currentReadingPositionIndex,
            let currentReadingPositionTotalCount,
            currentReadingPositionTotalCount > 0,
            !readingJumpTargets.isEmpty
        else {
            return nil
        }

        let boundedIndex = min(max(currentReadingPositionIndex, 0), readingJumpTargets.count - 1)
        let target = readingJumpTargets[boundedIndex]
        let label = target.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let total = currentReadingPositionTotalCount
        let position = boundedIndex + 1

        switch readingStructureKind {
        case .page:
            if label.isEmpty {
                return "Page \(position)/\(total)"
            }
            return "Page \(position)/\(total) · \(label)"
        case .chapter:
            if label.isEmpty {
                return "Chapter \(position)/\(total)"
            }
            return "Chapter \(position)/\(total) · \(label)"
        case .section:
            if label.isEmpty {
                return "Section \(position)/\(total)"
            }
            return "Section \(position)/\(total) · \(label)"
        case .none:
            return label.isEmpty ? "Item \(position)/\(total)" : "\(label)"
        }
    }

    var currentReadingProgressSummaryText: String? {
        guard
            let currentReadingPositionIndex,
            let currentReadingPositionTotalCount,
            currentReadingPositionTotalCount > 0,
            !readingJumpTargets.isEmpty
        else {
            return nil
        }

        let boundedIndex = min(max(currentReadingPositionIndex, 0), readingJumpTargets.count - 1)
        let target = readingJumpTargets[boundedIndex]
        let label = target.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let position = boundedIndex + 1
        let total = currentReadingPositionTotalCount

        let unitLabel: String
        switch readingStructureKind {
        case .page:
            unitLabel = "Pages"
        case .chapter:
            unitLabel = "Chapters"
        case .section:
            unitLabel = "Sections"
        case .none:
            unitLabel = "Items"
        }

        var summary = "Progress \(position)/\(total) \(unitLabel)"
        if !label.isEmpty {
            summary += " · \(label)"
        }
        return summary
    }

    private static func encodeJumpTargets(_ targets: [ReaderJumpTarget]) -> Data? {
        guard !targets.isEmpty else { return nil }
        return try? JSONEncoder().encode(targets)
    }
}

@Model
final class ReaderCategory {
    var name: String
    var accentName: String
    var createdAt: Date

    init(name: String, accentName: String, createdAt: Date = .now) {
        self.name = name
        self.accentName = accentName
        self.createdAt = createdAt
    }
}
