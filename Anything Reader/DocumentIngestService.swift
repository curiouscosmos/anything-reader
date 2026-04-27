//
//  DocumentIngestService.swift
//  Anything Reader
//
//  Handles PDF, TXT, and ePub extraction plus normalization.
//

import AppKit
import Foundation
import PDFKit

struct IngestedDocument {
    let title: String?
    let normalizedText: String
    let normalizedTextFileURL: URL
    let sourceKind: ReaderSourceKind
    let fileSizeBytes: Int64
}

enum DocumentIngestError: LocalizedError {
    case invalidFile
    case unsupportedFileType
    case unreadableDocument
    case extractionFailed
    case normalizationFailed
    case archiveAccessFailed

    var errorDescription: String? {
        switch self {
        case .invalidFile:
            return "The selected file is missing, empty, or unreadable."
        case .unsupportedFileType:
            return "Please choose a PDF, TXT, or ePub file."
        case .unreadableDocument:
            return "The document could not be read."
        case .extractionFailed:
            return "The text could not be extracted from the file."
        case .normalizationFailed:
            return "The extracted text could not be normalized."
        case .archiveAccessFailed:
            return "The ePub archive could not be opened."
        }
    }
}

actor DocumentIngestService {
    static let shared = DocumentIngestService()

    private init() {}

    func process(
        stagedFileURL: URL,
        fileExtension: String,
        originalFileName: String
    ) throws -> IngestedDocument {
        let normalizedFileExtension = fileExtension.lowercased()
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: stagedFileURL.path) else {
            throw DocumentIngestError.invalidFile
        }

        let fileData = try Data(contentsOf: stagedFileURL)
        guard !fileData.isEmpty else {
            throw DocumentIngestError.invalidFile
        }

        let sourceKind = readerSourceKind(for: normalizedFileExtension)
        let rawText: String
        let extractedTitle: String?

        switch sourceKind {
        case .pdf:
            rawText = try PDFTextExtractionService.extractText(from: stagedFileURL)
            extractedTitle = bestTitleCandidate(from: rawText)
        case .epub:
            rawText = try EPUBTextExtractionService.extractText(from: stagedFileURL)
            extractedTitle = bestTitleCandidate(from: rawText)
        case .text, .pastedText:
            guard let text = String(data: fileData, encoding: .utf8) else {
                throw DocumentIngestError.unreadableDocument
            }
            rawText = text
            extractedTitle = bestTitleCandidate(from: rawText)
        }

        let normalizedText = TextNormalizationService.normalize(rawText)
        guard !normalizedText.isEmpty else {
            throw DocumentIngestError.normalizationFailed
        }

        let normalizedURL = try saveNormalizedText(
            normalizedText,
            originalFileName: originalFileName,
            sourceURL: stagedFileURL
        )

        return IngestedDocument(
            title: extractedTitle,
            normalizedText: normalizedText,
            normalizedTextFileURL: normalizedURL,
            sourceKind: sourceKind,
            fileSizeBytes: Int64(fileData.count)
        )
    }

    private func saveNormalizedText(
        _ text: String,
        originalFileName: String,
        sourceURL: URL
    ) throws -> URL {
        let fileManager = FileManager.default
        let directoryURL = try uploadedFilesDirectory()
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let safeName = sanitizedFileName(originalFileName)
        let destinationURL = directoryURL.appendingPathComponent("\(baseName)-normalized-\(safeName).txt")

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        guard fileManager.createFile(
            atPath: destinationURL.path,
            contents: Data(text.utf8),
            attributes: nil
        ) else {
            throw DocumentIngestError.normalizationFailed
        }

        return destinationURL
    }

    private func uploadedFilesDirectory() throws -> URL {
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

    private func sanitizedFileName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = "Document"
        let base = trimmed.isEmpty ? fallback : trimmed
        return base
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }

    private func readerSourceKind(for fileExtension: String) -> ReaderSourceKind {
        switch fileExtension.lowercased() {
        case "pdf":
            return .pdf
        case "epub":
            return .epub
        case "txt":
            return .text
        default:
            return .text
        }
    }
}

nonisolated private func bestTitleCandidate(from text: String) -> String? {
    let candidates = text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    guard let firstLine = candidates.first else { return nil }

    let cleaned = firstLine.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
    guard cleaned.count <= 120 else { return nil }
    guard cleaned.contains(where: { $0.isLetter }) else { return nil }
    return cleaned
}

private enum PDFTextExtractionService {
    nonisolated static func extractText(from url: URL) throws -> String {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else {
            throw DocumentIngestError.unreadableDocument
        }

        let pageCount = document.pageCount
        let boilerplateThreshold = max(2, Int(ceil(Double(pageCount) * 0.35)))
        var candidateCounts: [String: Int] = [:]

        for index in 0..<pageCount {
            guard let page = document.page(at: index) else { continue }
            let pageBounds = page.bounds(for: .mediaBox)
            let headerRect = CGRect(
                x: pageBounds.minX,
                y: pageBounds.maxY - (pageBounds.height * 0.18),
                width: pageBounds.width,
                height: pageBounds.height * 0.18
            )
            let footerRect = CGRect(
                x: pageBounds.minX,
                y: pageBounds.minY,
                width: pageBounds.width,
                height: pageBounds.height * 0.18
            )

            let headerLines = lines(from: page.selection(for: headerRect)?.string)
            let footerLines = lines(from: page.selection(for: footerRect)?.string)

            for line in Set(headerLines + footerLines) {
                candidateCounts[line, default: 0] += 1
            }
        }

        let boilerplateLines: Set<String> = Set(candidateCounts.compactMap { (line, count) -> String? in
            guard count >= boilerplateThreshold, !line.isEmpty else { return nil }
            return line
        })

        var cleanedPages: [String] = []

        for index in 0..<pageCount {
            guard let page = document.page(at: index) else { continue }
            let pageLines = lines(from: page.string)
            let filteredLines = pageLines.filter { line in
                !boilerplateLines.contains(line)
                    && !isPageNumberLine(line)
                    && !isLikelyBoilerplate(line)
            }

            let pageText = filteredLines.joined(separator: "\n")
            if !pageText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                cleanedPages.append(pageText)
            }
        }

        let extracted = cleanedPages.joined(separator: "\n\n")
        guard !extracted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DocumentIngestError.extractionFailed
        }

        return extracted
    }

    nonisolated static func extractTitle(from url: URL) -> String? {
        guard let document = PDFDocument(url: url), let page = document.page(at: 0) else { return nil }
        let pageText = page.string ?? ""
        return bestTitleCandidate(from: pageText)
    }

    nonisolated private static func lines(from text: String?) -> [String] {
        guard let text else { return [] }
        return text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map(Self.normalizedLine)
    }

    nonisolated private static func normalizedLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func isPageNumberLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: #"^\d+$"#, options: .regularExpression) != nil {
            return true
        }
        if trimmed.range(of: #"^page\s*\d+$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        return false
    }

    nonisolated private static func isLikelyBoilerplate(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 4 else { return false }
        return trimmed.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) || CharacterSet.punctuationCharacters.contains($0) }
    }
}

private enum EPUBTextExtractionService {
    nonisolated static func extractText(from url: URL) throws -> String {
        let zipEntries = try archiveEntries(at: url)
        guard zipEntries.contains("META-INF/container.xml") else {
            throw DocumentIngestError.archiveAccessFailed
        }

        let containerData = try archiveData(at: url, entryPath: "META-INF/container.xml")
        let opfPath = try opfPath(from: containerData)
        let spinePaths = try spineEntryPaths(from: opfPath, archiveEntries: zipEntries, archiveURL: url)

        var orderedSections: [String] = []
        for path in spinePaths {
            guard path.hasSuffix(".xhtml") || path.hasSuffix(".html") || path.hasSuffix(".htm") else { continue }
            guard let htmlData = try? archiveData(at: url, entryPath: path) else { continue }
            if let plainText = htmlToPlainText(htmlData) {
                let cleaned = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    orderedSections.append(cleaned)
                }
            }
        }

        if orderedSections.isEmpty {
            for path in zipEntries.sorted() where path.hasSuffix(".xhtml") || path.hasSuffix(".html") || path.hasSuffix(".htm") {
                guard let htmlData = try? archiveData(at: url, entryPath: path) else { continue }
                if let plainText = htmlToPlainText(htmlData) {
                    let cleaned = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleaned.isEmpty {
                        orderedSections.append(cleaned)
                    }
                }
            }
        }

        let extracted = orderedSections.joined(separator: "\n\n")
        guard !extracted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DocumentIngestError.extractionFailed
        }

        return extracted
    }

    nonisolated static func extractTitle(from url: URL) -> String? {
        guard let containerData = try? archiveData(at: url, entryPath: "META-INF/container.xml"),
              let opfPath = try? opfPath(from: containerData),
              let opfData = try? archiveData(at: url, entryPath: opfPath) else {
            return nil
        }

        guard let document = try? XMLDocument(data: opfData, options: []) else {
            return nil
        }

        let titleNodes = try? document.nodes(forXPath: "//*[local-name()='metadata']/*[local-name()='title']")
        if let value = titleNodes?.compactMap({ ($0 as? XMLElement)?.stringValue }).first?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }

        if let metaNodes = try? document.nodes(forXPath: "//*[local-name()='metadata']/*[local-name()='meta']") {
            for node in metaNodes {
                guard let element = node as? XMLElement,
                      let name = element.attribute(forName: "name")?.stringValue?.lowercased(),
                      name == "title",
                      let content = element.attribute(forName: "content")?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !content.isEmpty else { continue }
                return content
            }
        }

        return nil
    }

    nonisolated private static func opfPath(from containerData: Data) throws -> String {
        let document = try XMLDocument(data: containerData, options: [])
        guard
            let rootfile = try document.nodes(forXPath: "//container/rootfiles/rootfile").first as? XMLElement,
            let fullPath = rootfile.attribute(forName: "full-path")?.stringValue
        else {
            throw DocumentIngestError.extractionFailed
        }

        return fullPath
    }

    nonisolated private static func spineEntryPaths(from opfPath: String, archiveEntries: [String], archiveURL: URL) throws -> [String] {
        let opfData = try archiveData(at: archiveURL, entryPath: opfPath)
        let document = try XMLDocument(data: opfData, options: [])

        let manifestNodes = try document.nodes(forXPath: "//*[local-name()='manifest']/*[local-name()='item']")
        var manifest: [String: String] = [:]
        for node in manifestNodes {
            guard let element = node as? XMLElement,
                  let id = element.attribute(forName: "id")?.stringValue,
                  let href = element.attribute(forName: "href")?.stringValue else {
                continue
            }
            manifest[id] = href
        }

        let spineNodes = try document.nodes(forXPath: "//*[local-name()='spine']/*[local-name()='itemref']")
        let basePath = (opfPath as NSString).deletingLastPathComponent
        let orderedPaths = spineNodes.compactMap { node -> String? in
            guard let element = node as? XMLElement,
                  let idref = element.attribute(forName: "idref")?.stringValue,
                  let href = manifest[idref] else {
                return nil
            }
            return normalizedArchivePath(basePath: basePath, href: href)
        }

        if orderedPaths.isEmpty {
            return archiveEntries
        }

        return orderedPaths
    }

    nonisolated private static func normalizedArchivePath(basePath: String, href: String) -> String {
        let combined = (basePath as NSString).appendingPathComponent(href)
        return combined.removingPercentEncoding ?? combined
    }

    nonisolated private static func htmlToPlainText(_ data: Data) -> String? {
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]

        guard let attributedString = try? NSAttributedString(data: data, options: options, documentAttributes: nil) else {
            return String(data: data, encoding: .utf8)
        }

        return attributedString.string
    }
}

nonisolated private func archiveEntries(at url: URL) throws -> [String] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    process.arguments = ["-Z1", url.path]

    let standardOutput = Pipe()
    let standardError = Pipe()
    process.standardOutput = standardOutput
    process.standardError = standardError

    try process.run()
    process.waitUntilExit()

    let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
    guard process.terminationStatus == 0,
          let output = String(data: outputData, encoding: .utf8) else {
        throw DocumentIngestError.archiveAccessFailed
    }

    return output
        .split(separator: "\n")
        .map(String.init)
        .filter { !$0.isEmpty }
}

nonisolated private func archiveData(at url: URL, entryPath: String) throws -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    process.arguments = ["-p", url.path, entryPath]

    let standardOutput = Pipe()
    let standardError = Pipe()
    process.standardOutput = standardOutput
    process.standardError = standardError

    try process.run()
    process.waitUntilExit()

    let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
    guard process.terminationStatus == 0, !outputData.isEmpty else {
        throw DocumentIngestError.archiveAccessFailed
    }

    return outputData
}
