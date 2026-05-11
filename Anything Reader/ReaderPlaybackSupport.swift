//
//  ReaderPlaybackSupport.swift
//  Anything Reader
//
//  Pure helpers for playback calculations and reading-position formatting.
//

import Foundation

// Indicates whether playback navigation should move backward or forward through reading targets.
enum PlaybackNavigationDirection {
    case backward
    case forward
}

// Pure helpers for mapping playback progress to reading-position labels and indices.
enum ReaderPlaybackSupport {
    // Returns the current reading-position label for chunk-based playback progress.
    static func readingPositionText(for entry: LibraryEntry, progress: Double) -> String {
        guard let structureKind = entry.readingStructureKind else { return "" }

        let targets = entry.readingJumpTargets
        guard !targets.isEmpty else { return "" }

        let index = ReaderPlaybackChunkService.chunkIndex(for: progress, chunkCount: targets.count)
        let target = targets[min(index, targets.count - 1)]
        return readingPositionText(
            for: structureKind,
            target: target,
            index: index,
            totalCount: targets.count
        )
    }

    // Returns the reading-position label for an explicit target index.
    static func readingPositionText(for entry: LibraryEntry, targetIndex: Int) -> String {
        guard let structureKind = entry.readingStructureKind else { return "" }

        let targets = entry.readingJumpTargets
        guard !targets.isEmpty else { return "" }

        let index = min(max(targetIndex, 0), targets.count - 1)
        let target = targets[index]
        return readingPositionText(
            for: structureKind,
            target: target,
            index: index,
            totalCount: targets.count
        )
    }

    // Maps playback progress back to a jump-target index when the entry has structured reading data.
    static func readingPositionIndex(for entry: LibraryEntry, progress: Double) -> Int? {
        let targets = entry.readingJumpTargets
        guard !targets.isEmpty else { return nil }
        return ReaderPlaybackChunkService.chunkIndex(for: progress, chunkCount: targets.count)
    }

    // Maps a chunk index back to the corresponding reading target.
    static func readingPositionIndex(for entry: LibraryEntry, chunkIndex: Int) -> Int? {
        let targets = entry.readingJumpTargets
        guard !targets.isEmpty else { return nil }
        return ReaderPlaybackChunkService.readingTargetIndex(forChunkIndex: chunkIndex, in: entry)
    }

    // Returns a normalized progress value for a structured reading target.
    static func readingProgress(for target: ReaderJumpTarget, in entry: LibraryEntry) -> Double {
        let targets = entry.readingJumpTargets
        guard !targets.isEmpty else { return 0 }
        return ReaderPlaybackChunkService.progress(for: target.index, chunkCount: targets.count)
    }

    // Derives the progress used to resume playback after the player stops or restarts.
    static func playbackResumeProgress(for entry: LibraryEntry, textFileURL: URL? = nil, duration: Int) -> Double {
        if let textFileURL,
           let summaryURL = entry.summarizedTextFileURL,
           summaryURL.path == textFileURL.path {
            let elapsedSeconds = entry.summarizedTextPlaybackPositionSeconds ?? 0
            guard duration > 0 else { return 0 }
            return min(max(Double(elapsedSeconds) / Double(duration), 0), 0.999_999)
        }

        if let currentIndex = entry.currentReadingPositionIndex,
           let totalCount = entry.currentReadingPositionTotalCount,
           totalCount > 0 {
            return ReaderPlaybackChunkService.progress(for: currentIndex, chunkCount: totalCount)
        }

        return entry.progress
    }

    // Estimates a duration for narration fallback UI when no real playback time is available.
    static func estimatedPlaybackDuration(for normalizedText: String) -> Int {
        max(600, min(10800, normalizedText.isEmpty ? 1800 : max(600, normalizedText.count / 12)))
    }

    // Finds the next or previous reading target for keyboard and transport controls.
    static func adjacentReadingTarget(
        for direction: PlaybackNavigationDirection,
        in entry: LibraryEntry,
        currentProgress: Double
    ) -> ReaderJumpTarget? {
        let targets = entry.readingJumpTargets
        guard !targets.isEmpty else { return nil }

        let currentIndex = readingTargetIndex(for: entry, currentProgress: currentProgress) ?? 0
        let targetIndex: Int

        switch direction {
        case .backward:
            targetIndex = currentIndex - 1
        case .forward:
            targetIndex = currentIndex + 1
        }

        guard targets.indices.contains(targetIndex) else { return nil }
        return targets[targetIndex]
    }

    // Checks whether a forward/backward jump is possible from the current position.
    static func canNavigateReadingTarget(
        _ direction: PlaybackNavigationDirection,
        in entry: LibraryEntry?,
        currentProgress: Double
    ) -> Bool {
        guard let entry else { return false }
        let targets = entry.readingJumpTargets
        guard !targets.isEmpty else { return false }

        let currentIndex = readingTargetIndex(for: entry, currentProgress: currentProgress) ?? 0

        switch direction {
        case .backward:
            return currentIndex > 0
        case .forward:
            return currentIndex < targets.count - 1
        }
    }

    // Resolves the current reading target index from either persisted state or current progress.
    static func readingTargetIndex(for entry: LibraryEntry, currentProgress: Double) -> Int? {
        entry.currentReadingPositionIndex ?? readingPositionIndex(for: entry, progress: currentProgress)
    }

    private static func readingPositionText(
        for structureKind: ReadingStructureKind,
        target: ReaderJumpTarget,
        index: Int,
        totalCount: Int
    ) -> String {
        let title = target.title.trimmingCharacters(in: .whitespacesAndNewlines)

        switch structureKind {
        case .page:
            if title.isEmpty {
                return "Page \(index + 1) of \(totalCount)"
            }
            return "Page \(index + 1) of \(totalCount) · \(title)"
        case .chapter:
            if title.isEmpty {
                return "Chapter \(index + 1) of \(totalCount)"
            }
            return "Chapter \(index + 1) of \(totalCount) · \(title)"
        case .section:
            if title.isEmpty {
                return "Section \(index + 1) of \(totalCount)"
            }
            return "Section \(index + 1) of \(totalCount) · \(title)"
        }
    }
}
