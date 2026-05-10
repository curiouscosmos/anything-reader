//
//  ReaderImportSupport.swift
//  Anything Reader
//
//  Pure helpers used by the import and browser-ingest flows.
//

import Foundation
import Translation
import UniformTypeIdentifiers

enum ReaderImportSupport {
    static func uploadedFilesDirectory() throws -> URL {
        let fileManager = FileManager.default
        let supportDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let appDirectory = supportDirectory.appendingPathComponent("Anything Reader", isDirectory: true)
        let uploadsDirectory = appDirectory.appendingPathComponent("Uploaded Files", isDirectory: true)

        if !fileManager.fileExists(atPath: uploadsDirectory.path) {
            try fileManager.createDirectory(at: uploadsDirectory, withIntermediateDirectories: true)
        }

        return uploadsDirectory
    }

    static func makeUploadDirectory(for sourceURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let rootDirectory = try uploadedFilesDirectory()
        let directoryName = sanitizedUploadedFileDirectoryName(from: sourceURL)
        let destinationDirectory = rootDirectory.appendingPathComponent(directoryName, isDirectory: true)

        if !fileManager.fileExists(atPath: destinationDirectory.path) {
            try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        }

        return destinationDirectory
    }

    static func sanitizedUploadedFileDirectoryName(from sourceURL: URL) -> String {
        let timestamp = importTimestampString()
        let stem = sourceURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let sanitizedStem = stem.isEmpty ? "upload" : stem
        return "\(timestamp)-\(sanitizedStem)"
    }

    static func readerSourceKind(for fileExtension: String) -> ReaderSourceKind {
        if UTType(filenameExtension: fileExtension)?.conforms(to: .image) == true {
            return .image
        }

        switch fileExtension.lowercased() {
        case "pdf":
            return .pdf
        case "epub":
            return .epub
        case "txt":
            return .text
        case "html", "htm":
            return .html
        default:
            return .text
        }
    }

    static func isSupportedUploadFileExtension(_ fileExtension: String) -> Bool {
        guard !fileExtension.isEmpty else { return false }

        if ["pdf", "txt", "epub"].contains(fileExtension) {
            return true
        }

        return UTType(filenameExtension: fileExtension)?.conforms(to: .image) == true
    }

    static func avatarSymbol(for sourceKind: ReaderSourceKind) -> String {
        switch sourceKind {
        case .pdf:
            return "doc.richtext.fill"
        case .epub:
            return "book.fill"
        case .image:
            return "doc.text.image"
        case .text, .html, .pastedText:
            return "doc.text.fill"
        }
    }

    static func sanitizedTitle(from fileName: String) -> String {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Upload" : trimmed
    }

    static func sanitizedImportedFileBaseName(from sourceURL: URL) -> String {
        let fileStem = sourceURL.deletingPathExtension().lastPathComponent
        let sanitizedStem = fileStem
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let timestamp = importTimestampString()
        return "\(sanitizedStem)_\(timestamp)"
    }

    static func sanitizedStorageFileName(for title: String) -> String {
        title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }

    static func createTemporaryBrowserTextFile(title: String, text: String) throws -> URL {
        let fileManager = FileManager.default
        let directoryURL = fileManager.temporaryDirectory.appendingPathComponent("Browser Text Imports", isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let fileName = sanitizedStorageFileName(for: title.isEmpty ? "Browser Page" : title)
        let fileURL = directoryURL.appendingPathComponent(fileName).appendingPathExtension("txt")
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    static func browserTitle(for message: BrowserNativeMessage, existingEntries: [LibraryEntry]) -> String {
        let trimmedTitle = message.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }

        let now = Date()
        let calendar = Calendar.current
        let browserCount = existingEntries.filter { entry in
            entry.sourceKind == .pastedText && calendar.isDate(entry.createdAt, inSameDayAs: now)
        }.count + 1

        if let pageURL = message.pageURL,
           let host = URL(string: pageURL)?.host,
           !host.isEmpty {
            return "Web Clip from \(host) #\(browserCount)"
        }

        return "Web Clip #\(browserCount)"
    }

    static func browserSubtitle(for message: BrowserNativeMessage) -> String {
        if let pageURL = message.pageURL,
           let host = URL(string: pageURL)?.host,
           !host.isEmpty {
            return "Saved from \(host)."
        }

        return "Saved from browser extension."
    }

    static func browserCategoryName(for message: BrowserNativeMessage) -> String {
        let trimmedSite = message.site?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedSite.isEmpty ? "Web" : trimmedSite
    }

    static func createTemporaryRSSArticleFile(from draft: RSSArticleDraft) throws -> URL {
        let fileManager = FileManager.default
        let directoryURL = fileManager.temporaryDirectory.appendingPathComponent("RSS Article Imports", isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let fileName = sanitizedStorageFileName(for: draft.title.isEmpty ? "RSS Article" : draft.title)
        let fileURL = directoryURL.appendingPathComponent(fileName).appendingPathExtension("txt")
        let body = [draft.title, "", draft.body].joined(separator: "\n")

        try body.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private static let importTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd_HHmmssSSS"
        return formatter
    }()

    static func importTimestampString() -> String {
        importTimestampFormatter.string(from: .now)
    }
}
