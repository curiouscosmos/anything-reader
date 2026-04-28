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
        }
    }
}

enum ReadingStructureKind: String, Codable, CaseIterable, Identifiable {
    case page
    case chapter

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
    case mandarin = "zh-Hans"
    case italian = "it"
    case japanese = "ja"
    case hindi = "hi"
    case punjabi = "pa"
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
        case .mandarin:
            return "Mandarin"
        case .italian:
            return "Italian"
        case .japanese:
            return "Japanese"
        case .hindi:
            return "Hindi"
        case .punjabi:
            return "Punjabi"
        case .unknown:
            return "Unknown"
        }
    }

    var isConservativeNormalizationLanguage: Bool {
        switch self {
        case .mandarin, .japanese, .hindi, .punjabi, .unknown:
            return true
        case .english, .french, .spanish, .german, .italian:
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
        case "ja":
            self = .japanese
        case "hi":
            self = .hindi
        case "pa":
            self = .punjabi
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
