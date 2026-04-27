//
//  ReaderPlaybackService.swift
//  Anything Reader
//
//  Sequential Kokoro playback controller for library entries.
//  It reads normalized text, chunks it, synthesizes each chunk, and updates
//  playback progress from the actual audio time.
//

import AVFoundation
import Foundation
import Combine
import SwiftData

// Lightweight progress payload for the player UI.
struct ReaderPlaybackUpdate {
    let elapsedSeconds: Int
    let durationSeconds: Int
    let progress: Double
    let isPlaying: Bool
}

// Drives one library entry at a time through Kokoro-backed chunked playback.
final class ReaderPlaybackService: ObservableObject {
    static let shared = ReaderPlaybackService()

    @Published private(set) var isPlaying = false

    private var playbackTask: Task<Void, Never>?
    private var activeAudioPlayer: AVAudioPlayer?
    private var stopRequested = false

    private init() {}

    func stop() {
        stopRequested = true
        playbackTask?.cancel()
        playbackTask = nil

        activeAudioPlayer?.stop()
        activeAudioPlayer = nil
        isPlaying = false
    }

    func play(
        entry: LibraryEntry,
        voice: KokoroVoiceOption,
        startingProgress: Double,
        onProgress: @escaping (ReaderPlaybackUpdate) -> Void,
        onFinished: @escaping () -> Void,
        onFailure: @escaping (String) -> Void
    ) {
        stop()
        stopRequested = false
        isPlaying = true

        playbackTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            let chunks = ReaderPlaybackChunkService.chunks(for: entry)
            guard !chunks.isEmpty else {
                await MainActor.run {
                    self.isPlaying = false
                    onFailure("No readable text was found in this file.")
                }
                return
            }

            let startIndex = ReaderPlaybackChunkService.chunkIndex(for: startingProgress, chunkCount: chunks.count)
            let estimatedTotalDuration = Self.estimatedDuration(for: chunks)
            var elapsedSoFar = Self.elapsedEstimate(for: chunks, upTo: startIndex)

            await MainActor.run {
                onProgress(
                    ReaderPlaybackUpdate(
                        elapsedSeconds: elapsedSoFar,
                        durationSeconds: estimatedTotalDuration,
                        progress: ReaderPlaybackChunkService.progress(for: startIndex, chunkCount: chunks.count),
                        isPlaying: true
                    )
                )
            }

            await PhonemeCacheService.shared.primeChunks(
                for: entry,
                chunks: chunks,
                startingAt: startIndex,
                prefetchCount: ReaderPlaybackChunkService.prefetchChunkCount
            )

            for chunkIndex in startIndex..<chunks.count {
                if Task.isCancelled || stopRequested {
                    break
                }

                let chunkText = chunks[chunkIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !chunkText.isEmpty else { continue }

                if await PhonemeCacheService.shared.cachedPhonemes(for: entry, chunkIndex: chunkIndex) == nil {
                    let phonemes = await KokoroG2PService.shared.phonemize(chunkText)
                    if !phonemes.isEmpty {
                        await PhonemeCacheService.shared.store(phonemes, for: entry, chunkIndex: chunkIndex)
                    }
                }

                let audioURL: URL
                do {
                    audioURL = try await KokoroSpeechService.shared.synthesize(text: chunkText, voice: voice)
                } catch {
                    await MainActor.run {
                        self.isPlaying = false
                        onFailure(error.localizedDescription)
                    }
                    return
                }

                do {
                    let playedDuration = try await self.playChunk(
                        at: audioURL,
                        baseElapsedSeconds: elapsedSoFar,
                        estimatedTotalDuration: estimatedTotalDuration,
                        chunkIndex: chunkIndex,
                        chunkCount: chunks.count,
                        onProgress: onProgress
                    )
                    elapsedSoFar += Int(playedDuration.rounded())
                } catch {
                    await MainActor.run {
                        self.isPlaying = false
                        onFailure(error.localizedDescription)
                    }
                    return
                }

                let nextChunkIndex = min(chunkIndex + 1, chunks.count - 1)
                await MainActor.run {
                    onProgress(
                        ReaderPlaybackUpdate(
                            elapsedSeconds: elapsedSoFar,
                            durationSeconds: estimatedTotalDuration,
                            progress: ReaderPlaybackChunkService.progress(for: nextChunkIndex, chunkCount: chunks.count),
                            isPlaying: true
                        )
                    )
                }

                await PhonemeCacheService.shared.primeChunks(
                    for: entry,
                    chunks: chunks,
                    startingAt: min(chunkIndex + 1, chunks.count - 1),
                    prefetchCount: ReaderPlaybackChunkService.prefetchChunkCount
                )
            }

            await MainActor.run {
                self.isPlaying = false
                if !self.stopRequested {
                    onFinished()
                }
            }
        }
    }

    private func playChunk(
        at url: URL,
        baseElapsedSeconds: Int,
        estimatedTotalDuration: Int,
        chunkIndex: Int,
        chunkCount: Int,
        onProgress: @escaping (ReaderPlaybackUpdate) -> Void
    ) async throws -> TimeInterval {
        try await MainActor.run {
            activeAudioPlayer?.stop()
            activeAudioPlayer = try AVAudioPlayer(contentsOf: url)
            activeAudioPlayer?.prepareToPlay()
            activeAudioPlayer?.play()
        }

        defer {
            Task { @MainActor in
                self.activeAudioPlayer?.stop()
                self.activeAudioPlayer = nil
            }
        }

        while !Task.isCancelled && !stopRequested {
            let state = await MainActor.run { [weak self] in
                guard let player = self?.activeAudioPlayer else {
                    return (false, 0.0, 0.0)
                }
                return (player.isPlaying, player.currentTime, player.duration)
            }

            guard state.0 else {
                break
            }

            let elapsed = baseElapsedSeconds + Int(state.1.rounded(.down))
            let progress = estimatedTotalDuration > 0
                ? min(1, Double(elapsed) / Double(estimatedTotalDuration))
                : 0

            await MainActor.run {
                onProgress(
                    ReaderPlaybackUpdate(
                        elapsedSeconds: elapsed,
                        durationSeconds: estimatedTotalDuration,
                        progress: progress,
                        isPlaying: true
                    )
                )
            }

            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        let duration = await MainActor.run { [weak self] in
            self?.activeAudioPlayer?.duration ?? 0
        }

        let finalElapsed = baseElapsedSeconds + Int(duration.rounded())
        let finalProgress = estimatedTotalDuration > 0
            ? min(1, Double(finalElapsed) / Double(estimatedTotalDuration))
            : 0

        await MainActor.run {
            onProgress(
                ReaderPlaybackUpdate(
                    elapsedSeconds: finalElapsed,
                    durationSeconds: estimatedTotalDuration,
                    progress: finalProgress,
                    isPlaying: true
                )
            )
        }

        return duration
    }

    private static func estimatedDuration(for chunks: [String]) -> Int {
        let estimated = chunks.reduce(into: 0) { partialResult, chunk in
            partialResult += max(4, min(120, chunk.count / 12))
        }
        return max(estimated, 30)
    }

    private static func elapsedEstimate(for chunks: [String], upTo chunkIndex: Int) -> Int {
        guard !chunks.isEmpty else { return 0 }
        let cappedIndex = min(max(chunkIndex, 0), chunks.count - 1)
        let completed = chunks.prefix(cappedIndex).reduce(into: 0) { partialResult, chunk in
            partialResult += max(4, min(120, chunk.count / 12))
        }
        return completed
    }
}
