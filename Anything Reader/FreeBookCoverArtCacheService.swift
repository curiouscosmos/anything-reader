//
//  FreeBookCoverArtCacheService.swift
//  Anything Reader
//
//  Downloads remote free-book cover art once and stores it locally so the
//  catalog can reuse the same image file on future renders.
//

import CryptoKit
import Foundation

actor FreeBookCoverArtCacheService {
    static let shared = FreeBookCoverArtCacheService()

    private let fileManager = FileManager.default
    private var inFlightRequests: [URL: Task<URL?, Never>] = [:]

    func cachedCoverURL(for sourceURL: URL?) async -> URL? {
        guard let sourceURL else { return nil }

        if sourceURL.isFileURL {
            return fileManager.fileExists(atPath: sourceURL.path) ? sourceURL : nil
        }

        let destinationURL = localCacheURL(for: sourceURL)
        if fileManager.fileExists(atPath: destinationURL.path) {
            return destinationURL
        }

        if let inFlight = inFlightRequests[sourceURL] {
            return await inFlight.value
        }

        let requestTask = Task<URL?, Never> { [sourceURL, destinationURL] in
            return await self.downloadCoverArt(from: sourceURL, to: destinationURL)
        }

        inFlightRequests[sourceURL] = requestTask
        let resolvedURL = await requestTask.value
        inFlightRequests[sourceURL] = nil
        return resolvedURL
    }

    private func downloadCoverArt(from sourceURL: URL, to destinationURL: URL) async -> URL? {
        do {
            let (temporaryURL, response) = try await URLSession.shared.download(from: sourceURL)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return nil
            }

            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }

            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            return destinationURL
        } catch {
            return nil
        }
    }

    private func localCacheURL(for remoteURL: URL) -> URL {
        let keyData = Data(remoteURL.absoluteString.utf8)
        let digest = SHA256.hash(data: keyData).map { String(format: "%02x", $0) }.joined()
        let fileExtension = remoteURL.pathExtension.isEmpty ? "img" : remoteURL.pathExtension.lowercased()

        return cacheDirectory()
            .appendingPathComponent(digest)
            .appendingPathExtension(fileExtension)
    }

    private func cacheDirectory() -> URL {
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        return supportDirectory
            .appendingPathComponent("Anything Reader", isDirectory: true)
            .appendingPathComponent("Free Books", isDirectory: true)
            .appendingPathComponent("Cover Art", isDirectory: true)
    }
}
