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

    @MainActor
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
                imageData = try extractPDFCoverData(from: sourceURL)
            case "epub":
                imageData = try extractEPUBCoverData(from: sourceURL)
            default:
                imageData = nil
            }

            guard let imageData, !imageData.isEmpty else {
                return nil
            }

            return try saveImageData(imageData, sourceURL: sourceURL, originalFileName: originalFileName)
        } catch {
            return nil
        }
    }

    @MainActor
    private func extractPDFCoverData(from url: URL) throws -> Data? {
        guard let document = PDFDocument(url: url), let page = document.page(at: 0) else {
            return nil
        }

        let thumbnail = page.thumbnail(of: NSSize(width: 1024, height: 1536), for: .mediaBox)
        return pngData(from: thumbnail)
    }

    @MainActor
    private func extractEPUBCoverData(from url: URL) throws -> Data? {
        let archive = try Archive(url: url, accessMode: .read)

        guard let containerData = try extractArchiveData(archive, entryPath: "META-INF/container.xml"),
              let opfPath = try opfPath(from: containerData),
              let opfData = try extractArchiveData(archive, entryPath: opfPath),
              let document = try? XMLDocument(data: opfData, options: []) else {
            return nil
        }

        let basePath = (opfPath as NSString).deletingLastPathComponent
        if let coverPath = try coverImagePath(from: document, basePath: basePath),
           let coverData = try extractArchiveData(archive, entryPath: coverPath),
           isLikelyImageData(coverData) {
            return coverData
        }

        for entry in archive where isLikelyImagePath(entry.path) {
            let entryPath = normalizedArchivePath(basePath: basePath, href: entry.path)
            if let imageData = try? extractArchiveData(archive, entryPath: entryPath),
               isLikelyImageData(imageData) {
                return imageData
            }
        }

        return nil
    }

    @MainActor
    private func saveImageData(_ data: Data, sourceURL: URL, originalFileName: String) throws -> URL {
        let fileManager = FileManager.default
        let directoryURL = sourceURL.deletingLastPathComponent()
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

    nonisolated private func extractArchiveData(_ archive: Archive, entryPath: String) throws -> Data? {
        guard let entry = archive[entryPath] else { return nil }

        var output = Data()
        _ = try archive.extract(entry) { chunk in
            output.append(chunk)
        }
        return output.isEmpty ? nil : output
    }

    nonisolated private func opfPath(from containerData: Data) throws -> String? {
        let document = try XMLDocument(data: containerData, options: [])
        guard
            let rootfile = try document.nodes(forXPath: "//container/rootfiles/rootfile").first as? XMLElement,
            let fullPath = rootfile.attribute(forName: "full-path")?.stringValue
        else {
            return nil
        }

        return fullPath
    }

    nonisolated private func coverImagePath(from document: XMLDocument, basePath: String) throws -> String? {
        if let metaNodes = try? document.nodes(forXPath: "//*[local-name()='metadata']/*[local-name()='meta']") {
            for node in metaNodes {
                guard let element = node as? XMLElement else { continue }

                let name = element.attribute(forName: "name")?.stringValue?.lowercased()
                let content = element.attribute(forName: "content")?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)

                if name == "cover", let content, !content.isEmpty,
                   let coverHref = try manifestHref(for: document, itemID: content, basePath: basePath) {
                    return coverHref
                }
            }
        }

        if let manifestNodes = try? document.nodes(forXPath: "//*[local-name()='manifest']/*[local-name()='item']") {
            for node in manifestNodes {
                guard let element = node as? XMLElement,
                      let properties = element.attribute(forName: "properties")?.stringValue?.lowercased(),
                      properties.contains("cover-image"),
                      let href = element.attribute(forName: "href")?.stringValue else {
                    continue
                }
                return normalizedArchivePath(basePath: basePath, href: href)
            }
        }

        return nil
    }

    nonisolated private func manifestHref(for document: XMLDocument, itemID: String, basePath: String) throws -> String? {
        let query = "//*[local-name()='manifest']/*[local-name()='item' and @id='\(itemID)']"
        guard let node = try document.nodes(forXPath: query).first as? XMLElement,
              let href = node.attribute(forName: "href")?.stringValue else {
            return nil
        }

        return normalizedArchivePath(basePath: basePath, href: href)
    }

    nonisolated private func normalizedArchivePath(basePath: String, href: String) -> String {
        let combined = (basePath as NSString).appendingPathComponent(href)
        return combined.removingPercentEncoding ?? combined
    }

    nonisolated private func isLikelyImagePath(_ path: String) -> Bool {
        let extensionName = (path as NSString).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "webp", "heic", "tif", "tiff"].contains(extensionName)
    }

    nonisolated private func isLikelyImageData(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }

        let bytes = [UInt8](data.prefix(12))
        if bytes.count >= 4, bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47 {
            return true
        }
        if bytes.count >= 2, bytes[0] == 0xFF, bytes[1] == 0xD8 {
            return true
        }
        if bytes.count >= 6, bytes[0] == 0x47, bytes[1] == 0x49, bytes[2] == 0x46 {
            return true
        }
        if bytes.count >= 4, bytes[0] == 0x49, bytes[1] == 0x49, bytes[2] == 0x2A, bytes[3] == 0x00 {
            return true
        }
        if bytes.count >= 4, bytes[0] == 0x4D, bytes[1] == 0x4D, bytes[2] == 0x00, bytes[3] == 0x2A {
            return true
        }

        return false
    }

}
