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
    var sourceText: String
    var phonemeText: String?
    var phonemeUpdatedAt: Date?
    var readingStructureKindRawValue: String?
    var pageCount: Int
    var chapterCount: Int
    var readingJumpTargetsData: Data?
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
        sourceText: String = "",
        phonemeText: String? = nil,
        phonemeUpdatedAt: Date? = nil,
        readingStructureKind: ReadingStructureKind? = nil,
        pageCount: Int = 0,
        chapterCount: Int = 0,
        readingJumpTargets: [ReaderJumpTarget] = [],
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
        self.sourceText = sourceText
        self.phonemeText = phonemeText
        self.phonemeUpdatedAt = phonemeUpdatedAt
        self.readingStructureKindRawValue = readingStructureKind?.rawValue
        self.pageCount = pageCount
        self.chapterCount = chapterCount
        self.readingJumpTargetsData = Self.encodeJumpTargets(readingJumpTargets)
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
