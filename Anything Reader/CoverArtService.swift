//
//  CoverArtService.swift
//  Anything Reader
//
//  Background cover-art extraction for PDF and ePub imports.
//

import AppKit
import Foundation
import PDFKit
import ZIPFoundation

actor CoverArtService {
    static let shared = CoverArtService()

    private init() {}

    func generateCoverImageURL(
        sourceURL: URL,
        fileExtension: String,
        originalFileName: String
    ) async -> URL? {
        let normalizedExtension = fileExtension.lowercased()

        do {
            let imageData: Data?
            switch normalizedExtension {
            case "pdf":
                imageData = try await extractPDFCoverData(from: sourceURL)
            case "epub":
                imageData = try await extractEPUBCoverData(from: sourceURL)
            default:
                imageData = nil
            }

            guard let imageData, !imageData.isEmpty else {
                return nil
            }

            return try await saveImageData(imageData, sourceURL: sourceURL, originalFileName: originalFileName)
        } catch {
            return nil
        }
    }

    private func extractPDFCoverData(from url: URL) async throws -> Data? {
        guard let document = PDFDocument(url: url), let page = document.page(at: 0) else {
            return nil
        }

        let thumbnail = page.thumbnail(of: NSSize(width: 1024, height: 1536), for: .mediaBox)
        return await pngData(from: thumbnail)
    }

    @MainActor
    private func extractEPUBCoverData(from url: URL) async throws -> Data? {
        let archive = try Archive(url: url, accessMode: .read)
        guard let containerData = try readArchiveEntryData(named: "META-INF/container.xml", from: archive) else {
            return nil
        }

        let containerParser = EPUBContainerParser()
        try parseXML(containerData, delegate: containerParser)

        guard let opfPath = containerParser.rootFilePath,
              let opfData = try readArchiveEntryData(named: opfPath, from: archive) else {
            return nil
        }

        let metadataParser = EPUBMetadataParser()
        try parseXML(opfData, delegate: metadataParser)

        let basePath = (opfPath as NSString).deletingLastPathComponent

        if let coverImageId = metadataParser.coverImageId,
           let coverHref = metadataParser.manifest[coverImageId]?.href {
            let entryPath = normalizedArchivePath(basePath: basePath, href: coverHref)
            return try readArchiveEntryData(named: entryPath, from: archive)
        }

        if let coverEntry = metadataParser.manifest.values.first(where: { $0.properties?.contains("cover-image") == true }) {
            let entryPath = normalizedArchivePath(basePath: basePath, href: coverEntry.href)
            return try readArchiveEntryData(named: entryPath, from: archive)
        }

        return nil
    }

    @MainActor
    private func saveImageData(_ data: Data, sourceURL: URL, originalFileName: String) async throws -> URL {
        let fileManager = FileManager.default
        let directoryURL = try uploadedFilesDirectory()
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let safeName = sanitizedFileName(originalFileName)
        let destinationURL = directoryURL.appendingPathComponent("\(baseName)-cover-\(safeName).png")

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        let outputData: Data
        if let image = NSImage(data: data), let pngData = pngData(from: image) {
            outputData = pngData
        } else {
            outputData = data
        }

        try outputData.write(to: destinationURL, options: .atomic)
        return destinationURL
    }

    nonisolated private func uploadedFilesDirectory() throws -> URL {
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

    @MainActor
    private func pngData(from image: NSImage) -> Data? {
        guard let tiffRepresentation = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }

    nonisolated private func sanitizedFileName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Document" : trimmed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }

    nonisolated private func readArchiveEntryData(named entryPath: String, from archive: Archive) throws -> Data? {
        guard let entry = archive[entryPath] else {
            return nil
        }

        var entryData = Data()
        _ = try archive.extract(entry, consumer: { data in
            entryData.append(data)
        })
        return entryData
    }

    nonisolated private func normalizedArchivePath(basePath: String, href: String) -> String {
        let combined = (basePath as NSString).appendingPathComponent(href)
        return combined.removingPercentEncoding ?? combined
    }

    @MainActor
    private func parseXML<T: NSObject & XMLParserDelegate>(_ data: Data, delegate: T) throws {
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw parser.parserError ?? DocumentIngestError.extractionFailed
        }
    }
}

private final class EPUBContainerParser: NSObject, XMLParserDelegate {
    private(set) var rootFilePath: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard localName(for: elementName) == "rootfile" else { return }
        rootFilePath = attributeDict["full-path"]
    }
}

private final class EPUBMetadataParser: NSObject, XMLParserDelegate {
    private(set) var manifest: [String: EPUBManifestItem] = [:]
    private(set) var coverImageId: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch localName(for: elementName) {
        case "item":
            guard let id = attributeDict["id"],
                  let href = attributeDict["href"] else {
                return
            }

            manifest[id] = EPUBManifestItem(
                href: href,
                properties: attributeDict["properties"]
            )

        case "meta":
            if attributeDict["name"]?.lowercased() == "cover" {
                coverImageId = attributeDict["content"]
            }

        default:
            break
        }
    }
}

private struct EPUBManifestItem {
    let href: String
    let properties: String?
}

private func localName(for elementName: String) -> String {
    elementName.split(separator: ":").last.map(String.init) ?? elementName
}
