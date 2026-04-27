//
//  CoverArtService.swift
//  Anything Reader
//
//  Background cover-art extraction for PDF and ePub imports.
//

import AppKit
import Foundation
import PDFKit

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

}
