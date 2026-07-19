//
//  AudioMixerLibraryService.swift
//  Anything Reader
//
//  Owns the audio mixer library state and persists it in the app's existing
//  SwiftData store.
//

import AVFoundation
import Combine
import Foundation
import SwiftData
import UniformTypeIdentifiers

struct AudioMixerTrack: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var title: String
    var filePath: String
    var isBundled: Bool
    var sortOrder: Int
    var createdAt: Date
    var lastPlayedAt: Date?

    var fileURL: URL {
        URL(fileURLWithPath: filePath)
    }

    var locationDescription: String {
        fileURL.standardizedFileURL.path
    }
}

enum AudioMixerLibraryError: LocalizedError {
    case unsupportedAudioFile
    case invalidAudioFile
    case bundledAudioMissing(String)
    case cannotDeleteBundledTrack
    case trackMissing
    case databaseUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedAudioFile:
            return "The selected file does not appear to be a supported audio file."
        case .invalidAudioFile:
            return "The selected audio file could not be played by AVFoundation."
        case .bundledAudioMissing(let fileName):
            return "The bundled audio file \(fileName) is missing from the app resources."
        case .cannotDeleteBundledTrack:
            return "Bundled audio tracks cannot be deleted."
        case .trackMissing:
            return "The selected audio file could not be found on disk."
        case .databaseUnavailable:
            return "The audio mixer library is not available yet."
        }
    }
}

@MainActor
final class AudioMixerLibraryService: ObservableObject {
    static let shared = AudioMixerLibraryService()

    @Published private(set) var tracks: [AudioMixerTrack] = []

    private let appSupportDirectoryName = "Anything Reader"
    private let mixerDirectoryName = "Audio Mixer"
    private let tracksDirectoryName = "Tracks"
    private let bundledAudioDirectoryName = "audio"

    private let bundledAudioFileNames = [
        "A-very-happy-christmas.mp3",
        "Beautiful-dream.mp3",
        "Forest-treasure.mp3",
        "meditation.mp3",
        "Silent-descent.mp3",
        "Staring-at-the-night-sky.mp3",
        "Wedding.mp3"
    ]

    private var didLoad = false
    private var modelContext: ModelContext?

    private init() {}

    func loadIfNeeded(using modelContext: ModelContext) {
        self.modelContext = modelContext
        guard !didLoad else { return }
        didLoad = true

        do {
            tracks = try fetchTracks(from: modelContext)
            try seedBundledTracksIfNeeded()
            try syncDirectoryTracksIntoLibrary()
            try repairMissingTracks()
            try persistTracks(using: modelContext)
            publishSortedTracks()
        } catch {
            NSLog("Audio mixer library load failed: %@", error.localizedDescription)
            publishSortedTracks()
        }
    }

    func loadIfNeeded() {
        guard let modelContext else { return }
        loadIfNeeded(using: modelContext)
    }

    func refresh(using modelContext: ModelContext) {
        self.modelContext = modelContext
        didLoad = false
        loadIfNeeded(using: modelContext)
    }

    func refresh() {
        guard let modelContext else { return }
        refresh(using: modelContext)
    }

    func track(for id: String) -> AudioMixerTrack? {
        tracks.first { $0.id == id }
    }

    func importAudioFile(from sourceURL: URL) throws -> AudioMixerTrack {
        guard let modelContext else {
            throw AudioMixerLibraryError.databaseUnavailable
        }
        guard sourceURL.isFileURL else {
            throw AudioMixerLibraryError.trackMissing
        }

        let didAccessSecurityScope = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScope {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw AudioMixerLibraryError.trackMissing
        }

        let destinationDirectory = try tracksDirectoryURL()
        let destinationURL = try uniqueDestinationURL(for: sourceURL, in: destinationDirectory)
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

        guard isPlayableAudioFile(at: destinationURL) else {
            try? FileManager.default.removeItem(at: destinationURL)
            throw AudioMixerLibraryError.invalidAudioFile
        }

        let nextOrder = (tracks.map(\.sortOrder).max() ?? -1) + 1
        let newTrack = AudioMixerTrack(
            id: UUID().uuidString,
            title: destinationURL.lastPathComponent,
            filePath: destinationURL.path,
            isBundled: false,
            sortOrder: nextOrder,
            createdAt: .now,
            lastPlayedAt: nil
        )

        tracks.append(newTrack)
        try persistTracks(using: modelContext)
        publishSortedTracks()
        return newTrack
    }

    func delete(_ track: AudioMixerTrack) throws {
        guard !track.isBundled else {
            throw AudioMixerLibraryError.cannotDeleteBundledTrack
        }
        guard let modelContext else {
            throw AudioMixerLibraryError.databaseUnavailable
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: track.fileURL.path) {
            try fileManager.removeItem(at: track.fileURL)
        }

        tracks.removeAll { $0.id == track.id }
        try persistTracks(using: modelContext)
        publishSortedTracks()
    }

    func markPlayed(trackID: String) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        tracks[index].lastPlayedAt = .now
        if let modelContext {
            try? persistTracks(using: modelContext)
        }
        publishSortedTracks()
    }

    func repairLibraryIfNeeded(using modelContext: ModelContext) {
        self.modelContext = modelContext
        guard didLoad else { return }

        do {
            try syncDirectoryTracksIntoLibrary()
            try repairMissingTracks()
            try persistTracks(using: modelContext)
            publishSortedTracks()
        } catch {
            NSLog("Audio mixer library repair failed: %@", error.localizedDescription)
        }
    }

    func repairLibraryIfNeeded() {
        guard let modelContext else { return }
        repairLibraryIfNeeded(using: modelContext)
    }

    private func fetchTracks(from modelContext: ModelContext) throws -> [AudioMixerTrack] {
        let descriptor = FetchDescriptor<AudioMixerTrackRecord>()
        return try modelContext.fetch(descriptor).map { record in
            AudioMixerTrack(
                id: record.id,
                title: record.title,
                filePath: record.filePath,
                isBundled: record.isBundled,
                sortOrder: record.sortOrder,
                createdAt: record.createdAt,
                lastPlayedAt: record.lastPlayedAt
            )
        }
    }

    private func persistTracks(using modelContext: ModelContext) throws {
        let descriptor = FetchDescriptor<AudioMixerTrackRecord>()
        let existingRecords = try modelContext.fetch(descriptor)
        existingRecords.forEach { modelContext.delete($0) }

        for track in tracks {
            modelContext.insert(
                AudioMixerTrackRecord(
                    id: track.id,
                    title: track.title,
                    filePath: track.filePath,
                    isBundled: track.isBundled,
                    sortOrder: track.sortOrder,
                    createdAt: track.createdAt,
                    lastPlayedAt: track.lastPlayedAt
                )
            )
        }

        try modelContext.save()
    }

    private func seedBundledTracksIfNeeded() throws {
        let currentTitles = Set(tracks.filter { $0.isBundled }.map(\.title))
        var didModify = false
        var nextSortIndex = tracks.map(\.sortOrder).max().map { $0 + 1 } ?? 0
        let fileManager = FileManager.default
        let destinationDirectory = try tracksDirectoryURL()
        var knownTitles = Set(tracks.map(\.title))

        for fileName in bundledAudioFileNames {
            if currentTitles.contains(fileName) {
                continue
            }

            guard let bundleURL = bundledAudioURL(for: fileName) else {
                NSLog("Bundled audio file missing from resources: %@", fileName)
                continue
            }

            let destinationURL = destinationDirectory.appendingPathComponent(fileName)
            if !fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.copyItem(at: bundleURL, to: destinationURL)
            }

            let title = uniqueTitle(for: fileName, among: knownTitles)
            tracks.append(
                AudioMixerTrack(
                    id: UUID().uuidString,
                    title: title,
                    filePath: destinationURL.path,
                    isBundled: true,
                    sortOrder: nextSortIndex,
                    createdAt: .now,
                    lastPlayedAt: nil
                )
            )
            knownTitles.insert(title)
            nextSortIndex += 1
            didModify = true
        }

        if didModify {
            publishSortedTracks()
        }
    }

    private func syncDirectoryTracksIntoLibrary() throws {
        let directory = try tracksDirectoryURL()
        let fileManager = FileManager.default
        let existingPaths = Set(tracks.map(\.filePath))
        var knownTitles = Set(tracks.map(\.title))
        let directoryContents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var didModify = false
        var nextSortIndex = (tracks.map(\.sortOrder).max() ?? -1) + 1

        for fileURL in directoryContents.sorted(by: { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }) {
            let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues?.isRegularFile == true else { continue }
            guard isPlayableAudioFile(at: fileURL) else { continue }

            let path = fileURL.standardizedFileURL.path
            guard !existingPaths.contains(path) else { continue }

            let title = uniqueTitle(for: fileURL.lastPathComponent, among: knownTitles)
            tracks.append(
                AudioMixerTrack(
                    id: UUID().uuidString,
                    title: title,
                    filePath: path,
                    isBundled: bundledAudioFileNames.contains(fileURL.lastPathComponent),
                    sortOrder: nextSortIndex,
                    createdAt: .now,
                    lastPlayedAt: nil
                )
            )
            knownTitles.insert(title)
            nextSortIndex += 1
            didModify = true
        }

        if didModify {
            publishSortedTracks()
        }
    }

    private func repairMissingTracks() throws {
        var nextTracks: [AudioMixerTrack] = []
        let fileManager = FileManager.default
        let destinationDirectory = try tracksDirectoryURL()

        for track in tracks {
            if fileManager.fileExists(atPath: track.fileURL.path) {
                nextTracks.append(track)
                continue
            }

            if track.isBundled, let bundleURL = bundledAudioURL(for: track.title) {
                let destinationURL = destinationDirectory.appendingPathComponent(track.title)
                if !fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.copyItem(at: bundleURL, to: destinationURL)
                }

                var repairedTrack = track
                repairedTrack.filePath = destinationURL.path
                nextTracks.append(repairedTrack)
            }
        }

        tracks = nextTracks
    }

    private func publishSortedTracks() {
        tracks = tracks.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder > rhs.sortOrder
            }
            if lhs.isBundled != rhs.isBundled {
                return lhs.isBundled && !rhs.isBundled
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func isPlayableAudioFile(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            return true
        } catch {
            return false
        }
    }

    private func uniqueDestinationURL(for sourceURL: URL, in directoryURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let originalFileName = sanitizedFileName(sourceURL.lastPathComponent)
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let fileExtension = sourceURL.pathExtension

        var candidateURL = directoryURL.appendingPathComponent(originalFileName)
        if !fileManager.fileExists(atPath: candidateURL.path) {
            return candidateURL
        }

        var counter = 2
        while true {
            let suffix = "-\(counter)"
            let proposedBaseName = sanitizedFileName("\(baseName)\(suffix)")
            if fileExtension.isEmpty {
                candidateURL = directoryURL.appendingPathComponent(proposedBaseName)
            } else {
                candidateURL = directoryURL.appendingPathComponent(proposedBaseName).appendingPathExtension(fileExtension)
            }

            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            counter += 1
        }
    }

    private func tracksDirectoryURL() throws -> URL {
        let directory = try baseDirectoryURL().appendingPathComponent(tracksDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func baseDirectoryURL() throws -> URL {
        let fileManager = FileManager.default
        let supportDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let appDirectory = supportDirectory.appendingPathComponent(appSupportDirectoryName, isDirectory: true)
        let mixerDirectory = appDirectory.appendingPathComponent(mixerDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: mixerDirectory, withIntermediateDirectories: true)
        return mixerDirectory
    }

    private func bundledAudioURL(for fileName: String) -> URL? {
        let fileNameWithoutExtension = (fileName as NSString).deletingPathExtension
        let fileExtension = (fileName as NSString).pathExtension
        return Bundle.main.url(
            forResource: fileNameWithoutExtension,
            withExtension: fileExtension,
            subdirectory: bundledAudioDirectoryName
        ) ?? Bundle.main.url(
            forResource: fileNameWithoutExtension,
            withExtension: fileExtension
        )
    }

    private func uniqueTitle(for title: String, among existingTitles: Set<String>) -> String {
        guard existingTitles.contains(title) else {
            return title
        }

        let baseTitle = (title as NSString).deletingPathExtension
        let fileExtension = (title as NSString).pathExtension
        var counter = 2

        while true {
            let suffix = " \(counter)"
            let proposed = fileExtension.isEmpty ? "\(baseTitle)\(suffix)" : "\(baseTitle)\(suffix).\(fileExtension)"
            if !existingTitles.contains(proposed) {
                return proposed
            }
            counter += 1
        }
    }

    private func sanitizedFileName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\")
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitized = trimmed
            .components(separatedBy: invalidCharacters)
            .joined(separator: "_")
        return sanitized.isEmpty ? "audio-file" : sanitized
    }
}
