//
//  ReaderPlaybackService.swift
//  Anything Reader
//
//  Narration player
//  Queued Kokoro playback controller for library entries.
//  It synthesizes chunked audio ahead of time and schedules it on a single
//  AVAudioPlayerNode so the handoff between chunks stays gap-free.
//

import AVFoundation
import Combine
import Foundation
import SwiftData

// Lightweight progress payload for the narration player UI.
struct ReaderPlaybackUpdate {
    let elapsedSeconds: Int
    let durationSeconds: Int
    let progress: Double
    let chunkIndex: Int
    let isPlaying: Bool
}

// Drives one library entry at a time through Kokoro-backed chunked playback.
// This service stays focused on live narration so generated-audio playback can
// remain in its own isolated player service.
@MainActor
final class ReaderPlaybackService: NSObject, ObservableObject {
    static let shared = ReaderPlaybackService()

    @Published private(set) var isPlaying = false
    @Published private(set) var isPaused = false
    @Published private(set) var isBufferingFirstChunk = false
    @Published private(set) var activePlaybackIdentity: String?
    @Published private(set) var volume: Double

    private var engine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private struct PlaybackSession {
        let id: UUID
        let identity: String
    }

    private var playbackTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?
    private var stopRequested = false
    private var didConfigureEngine = false
    private var synthesizedAudioURLs: [Int: URL] = [:]
    private var synthesisTasks: [Int: Task<URL, Error>] = [:]
    private var playbackSessionID = UUID()
    private var playbackSession: PlaybackSession?
    private var activeChunkIndex = 0

    private static let volumeStorageKey = "readerPlaybackVolume"

    private override init() {
        let storedVolume = UserDefaults.standard.object(forKey: Self.volumeStorageKey) as? Double
        self.volume = storedVolume ?? 0.9
        super.init()
        playerNode.volume = Float(volume)
    }

    func stop() {
        stopRequested = true
        playbackSessionID = UUID()
        playbackSession = nil
        playbackTask?.cancel()
        progressTask?.cancel()
        playbackTask = nil
        progressTask = nil

        synthesisTasks.values.forEach { $0.cancel() }
        synthesisTasks.removeAll()
        synthesizedAudioURLs.removeAll()

        let oldEngine = engine
        let oldPlayerNode = playerNode

        if oldPlayerNode.isPlaying {
            oldPlayerNode.stop()
        }
        oldPlayerNode.reset()
        if oldEngine.isRunning {
            oldEngine.stop()
        }

        engine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        playerNode.volume = Float(volume)
        didConfigureEngine = false

        isPlaying = false
        isPaused = false
        isBufferingFirstChunk = false
        activePlaybackIdentity = nil
        activeChunkIndex = 0
    }

    func setVolume(_ newValue: Double) {
        let clampedVolume = min(max(newValue, 0), 1)
        volume = clampedVolume
        playerNode.volume = Float(clampedVolume)
        UserDefaults.standard.set(clampedVolume, forKey: Self.volumeStorageKey)
    }

    func play(
        entry: LibraryEntry,
        voice: KokoroVoiceOption,
        startingProgress: Double,
        startingChunkIndex: Int? = nil,
        textFileURL: URL? = nil,
        onProgress: @escaping (ReaderPlaybackUpdate) -> Void,
        onFinished: @escaping () -> Void,
        onFailure: @escaping (String) -> Void
    ) {
        // Starting a new narration session resets any previously scheduled
        // chunk queue so the player can resume from the selected reading target.
        stop()
        stopRequested = false
        playbackSessionID = UUID()
        let sessionID = playbackSessionID
        let sessionIdentity = playbackIdentity(for: entry, textFileURL: textFileURL)
        playbackSession = PlaybackSession(id: sessionID, identity: sessionIdentity)
        isPlaying = true
        isPaused = false
        isBufferingFirstChunk = true
        activePlaybackIdentity = sessionIdentity
        activeChunkIndex = max(startingChunkIndex ?? 0, 0)
        playerNode.volume = Float(volume)

        playbackTask = Task { [weak self] in
            guard let self else { return }

            let chunks = ReaderPlaybackChunkService.chunks(for: entry, textFileURL: textFileURL)
            guard !chunks.isEmpty else {
                await MainActor.run {
                    guard self.playbackSessionID == sessionID else { return }
                    self.isPlaying = false
                    self.isPaused = false
                    self.isBufferingFirstChunk = false
                    self.activePlaybackIdentity = nil
                    self.playbackSession = nil
                    onFailure("No readable text was found in this file.")
                }
                return
            }

            let startIndex = min(
                max(
                    startingChunkIndex ?? ReaderPlaybackChunkService.chunkIndex(for: startingProgress, chunkCount: chunks.count),
                    0
                ),
                max(chunks.count - 1, 0)
            )
            let estimatedTotalDuration = Self.estimatedDuration(for: chunks)
            let initialElapsed = Self.elapsedEstimate(for: chunks, upTo: startIndex)

            await MainActor.run {
                guard self.playbackSessionID == sessionID else { return }
                onProgress(
                    ReaderPlaybackUpdate(
                        elapsedSeconds: initialElapsed,
                        durationSeconds: estimatedTotalDuration,
                        progress: ReaderPlaybackChunkService.progress(for: startIndex, chunkCount: chunks.count),
                        chunkIndex: startIndex,
                        isPlaying: true
                    )
                )
            }

            await MainActor.run {
                guard self.playbackSessionID == sessionID else { return }
                self.configureEngineIfNeeded()
                self.playerNode.reset()
            }

            do {
                try engine.start()
            } catch {
                await MainActor.run {
                    guard self.playbackSessionID == sessionID else { return }
                    self.isPlaying = false
                    self.isPaused = false
                    self.isBufferingFirstChunk = false
                    self.activePlaybackIdentity = nil
                    self.playbackSession = nil
                    self.activeChunkIndex = 0
                    onFailure(error.localizedDescription)
                }
                return
            }

            startProgressMonitor(
                totalDuration: estimatedTotalDuration,
                onProgress: onProgress,
                onFinished: onFinished,
                onFailure: onFailure
            )

            var scheduledChunkCount = 0

            for chunkIndex in startIndex..<chunks.count {
                if stopRequested || Task.isCancelled {
                    break
                }
                let isStaleSession = await MainActor.run { self.playbackSessionID != sessionID }
                if isStaleSession {
                    break
                }

                let chunkText = chunks[chunkIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !chunkText.isEmpty else { continue }
                await MainActor.run {
                    self.activeChunkIndex = chunkIndex
                }

                let isFirstSessionChunk = chunkIndex == startIndex
                if isFirstSessionChunk,
                   let cachedAudioURL = await ReaderPlaybackAudioCacheService.shared.cachedAudioURL(
                    for: entry,
                    voiceName: voice.voiceName,
                    chunkText: chunkText
                   ) {
                    await MainActor.run {
                        guard self.playbackSessionID == sessionID else { return }
                        self.scheduleAudioFile(
                            cachedAudioURL,
                            isFinalChunk: chunkIndex == chunks.count - 1,
                            sessionID: sessionID,
                            onFinished: onFinished
                        )
                        if !self.playerNode.isPlaying && !self.isPaused {
                            self.playerNode.play()
                        }
                    }

                    scheduledChunkCount += 1

                    if scheduledChunkCount == 1 {
                        await MainActor.run {
                            guard self.playbackSessionID == sessionID else { return }
                            self.isBufferingFirstChunk = false
                        }
                    }

                    await primeAudioPrefetch(for: entry, chunks: chunks, voice: voice, startingAt: chunkIndex + 1, sessionID: sessionID)
                    continue
                }

                if await PhonemeCacheService.shared.cachedPhonemes(for: entry, chunkIndex: chunkIndex) == nil {
                    let phonemes = await KokoroG2PService.shared.phonemize(chunkText)
                    if !phonemes.isEmpty {
                        await PhonemeCacheService.shared.store(phonemes, for: entry, chunkIndex: chunkIndex)
                    }
                }

                let audioURL: URL
                do {
                    audioURL = try await synthesizedAudioURL(
                        for: chunkIndex,
                        entry: entry,
                        voice: voice,
                        text: chunkText,
                        isPrimaryChunk: chunkIndex == startIndex,
                        sessionID: sessionID
                    )
                } catch {
                    await MainActor.run {
                        guard self.playbackSessionID == sessionID else { return }
                        self.isPlaying = false
                        self.isPaused = false
                        self.isBufferingFirstChunk = false
                        self.activePlaybackIdentity = nil
                        self.playbackSession = nil
                        self.activeChunkIndex = 0
                        onFailure(error.localizedDescription)
                    }
                    return
                }

                await MainActor.run {
                    guard self.playbackSessionID == sessionID else { return }
                    self.scheduleAudioFile(
                        audioURL,
                        isFinalChunk: chunkIndex == chunks.count - 1,
                        sessionID: sessionID,
                        onFinished: onFinished
                    )
                    if !self.playerNode.isPlaying && !self.isPaused {
                        self.playerNode.play()
                    }
                }

                scheduledChunkCount += 1

                if scheduledChunkCount == 1 {
                    await MainActor.run {
                        guard self.playbackSessionID == sessionID else { return }
                        self.isBufferingFirstChunk = false
                    }
                }

                // Keep a rolling audio queue warm so the next narration chunk is
                // already being synthesized while the current chunk is playing.
                await primeAudioPrefetch(for: entry, chunks: chunks, voice: voice, startingAt: chunkIndex + 1, sessionID: sessionID)
            }

            guard scheduledChunkCount > 0 else {
                await MainActor.run {
                        guard self.playbackSessionID == sessionID else { return }
                        self.isPlaying = false
                        self.isPaused = false
                        self.isBufferingFirstChunk = false
                        self.activePlaybackIdentity = nil
                        self.playbackSession = nil
                        self.activeChunkIndex = 0
                        onFailure("No readable audio could be generated for this file.")
                    }
                    return
            }

            while !stopRequested && !Task.isCancelled {
                let isNodePlaying = await MainActor.run { self.playerNode.isPlaying }
                if !isNodePlaying {
                    break
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }

            if stopRequested || Task.isCancelled {
                return
            }
        }
    }

    func pause() {
        guard playerNode.isPlaying else { return }

        playerNode.pause()
        isPlaying = false
        isPaused = true
    }

    func resume() {
        guard isPaused else { return }

        playerNode.play()
        isPlaying = true
        isPaused = false
    }

    func isActivePlayback(for entry: LibraryEntry, textFileURL: URL? = nil) -> Bool {
        guard let playbackSession else { return false }
        return playbackSession.identity == playbackIdentity(for: entry, textFileURL: textFileURL)
    }

    func isPausedPlayback(for entry: LibraryEntry, textFileURL: URL? = nil) -> Bool {
        guard isPaused else { return false }
        return isActivePlayback(for: entry, textFileURL: textFileURL)
    }

    private func configureEngineIfNeeded() {
        guard !didConfigureEngine else { return }

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: nil)
        engine.prepare()
        didConfigureEngine = true
    }

    private func playbackIdentity(for entry: LibraryEntry, textFileURL: URL?) -> String {
        let modelID = entry.persistentModelID
        return [
            modelID.storeIdentifier ?? "default",
            modelID.entityName,
            String(describing: modelID.id),
            textFileURL?.path ?? ""
        ]
        .joined(separator: "|")
    }

    private func scheduleAudioFile(
        _ url: URL,
        isFinalChunk: Bool,
        sessionID: UUID,
        onFinished: @escaping () -> Void
    ) {
        guard let audioFile = try? AVAudioFile(forReading: url) else { return }
        playerNode.scheduleFile(audioFile, at: nil) { [weak self] in
            guard let self else { return }

            guard isFinalChunk else { return }

            Task { @MainActor in
                guard self.playbackSessionID == sessionID else { return }
                self.finishPlayback(onFinished: onFinished)
            }
        }
    }

    private func finishPlayback(onFinished: @escaping () -> Void) {
        stopRequested = true
        isPlaying = false
        isPaused = false
        isBufferingFirstChunk = false
        activePlaybackIdentity = nil
        playbackSession = nil

        if playerNode.isPlaying {
            playerNode.stop()
        }
        if engine.isRunning {
            engine.stop()
        }

        onFinished()
    }

    private func primeAudioPrefetch(
        for entry: LibraryEntry,
        chunks: [String],
        voice: KokoroVoiceOption,
        startingAt index: Int,
        sessionID: UUID
    ) async {
        guard !chunks.isEmpty else { return }
        let isCurrentSession = await MainActor.run { self.playbackSessionID == sessionID }
        guard isCurrentSession else { return }

        let startIndex = min(max(index, 0), chunks.count - 1)
        let upperBound = min(chunks.count - 1, startIndex + ReaderPlaybackChunkService.prefetchChunkCount)

        for chunkIndex in startIndex...upperBound {
            guard chunkIndex < chunks.count else { continue }
            guard synthesizedAudioURLs[chunkIndex] == nil else { continue }
            guard synthesisTasks[chunkIndex] == nil else { continue }
            let stillCurrentSession = await MainActor.run { self.playbackSessionID == sessionID }
            guard stillCurrentSession else { return }

            let chunkText = chunks[chunkIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !chunkText.isEmpty else { continue }

            if await awaitCachedPhonemesMissing(for: entry, chunkIndex: chunkIndex, text: chunkText) {
                let phonemes = await KokoroG2PService.shared.phonemize(chunkText)
                if !phonemes.isEmpty {
                    Task { await PhonemeCacheService.shared.store(phonemes, for: entry, chunkIndex: chunkIndex) }
                }
            }

            let task = Task<URL, Error> {
                try await KokoroSpeechService.shared.synthesize(text: chunkText, voice: voice)
            }
            synthesisTasks[chunkIndex] = task

            Task {
                do {
                    let url = try await task.value
                    _ = await MainActor.run {
                        guard self.playbackSessionID == sessionID else { return }
                        synthesizedAudioURLs[chunkIndex] = url
                        synthesisTasks.removeValue(forKey: chunkIndex)
                    }
                } catch {
                    _ = await MainActor.run {
                        guard self.playbackSessionID == sessionID else { return }
                        synthesisTasks.removeValue(forKey: chunkIndex)
                    }
                }
            }
        }
    }

    private func awaitCachedPhonemesMissing(for entry: LibraryEntry, chunkIndex: Int, text: String) async -> Bool {
        if await PhonemeCacheService.shared.cachedPhonemes(for: entry, chunkIndex: chunkIndex) != nil {
            return false
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return true
    }

    private func synthesizedAudioURL(
        for chunkIndex: Int,
        entry: LibraryEntry,
        voice: KokoroVoiceOption,
        text: String,
        isPrimaryChunk: Bool,
        sessionID: UUID
    ) async throws -> URL {
        let isActiveSession = await MainActor.run { self.playbackSessionID == sessionID }
        guard isActiveSession else {
            throw CancellationError()
        }

        if let cached = synthesizedAudioURLs[chunkIndex] {
            return cached
        }

        if isPrimaryChunk,
           let cachedAudioURL = await ReaderPlaybackAudioCacheService.shared.cachedAudioURL(
            for: entry,
            voiceName: voice.voiceName,
            chunkText: text
           ) {
            synthesizedAudioURLs[chunkIndex] = cachedAudioURL
            return cachedAudioURL
        }

        if let task = synthesisTasks[chunkIndex] {
            let url = try await task.value
            synthesizedAudioURLs[chunkIndex] = url
            synthesisTasks.removeValue(forKey: chunkIndex)
            return url
        }

        let task = Task<URL, Error> {
            try await KokoroSpeechService.shared.synthesize(text: text, voice: voice)
        }

        synthesisTasks[chunkIndex] = task

        do {
            let url = try await task.value
            let cachedURL: URL
            if isPrimaryChunk,
               let storedURL = await ReaderPlaybackAudioCacheService.shared.storeAudio(
                at: url,
                for: entry,
                voiceName: voice.voiceName,
                chunkText: text
               ) {
                cachedURL = storedURL
            } else {
                cachedURL = url
            }
            let isStillActive = await MainActor.run { self.playbackSessionID == sessionID }
            if isStillActive {
                synthesizedAudioURLs[chunkIndex] = cachedURL
                synthesisTasks.removeValue(forKey: chunkIndex)
            }
            return cachedURL
        } catch {
            let isStillActive = await MainActor.run { self.playbackSessionID == sessionID }
            if isStillActive {
                synthesisTasks.removeValue(forKey: chunkIndex)
            }
            throw error
        }
    }

    private func startProgressMonitor(
        totalDuration: Int,
        onProgress: @escaping (ReaderPlaybackUpdate) -> Void,
        onFinished: @escaping () -> Void,
        onFailure: @escaping (String) -> Void
    ) {
        progressTask?.cancel()

        progressTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled && !self.stopRequested {
                let snapshot = await MainActor.run { () -> (Bool, Int, Double) in
                    guard self.playerNode.isPlaying,
                          let nodeTime = self.playerNode.lastRenderTime,
                          let playerTime = self.playerNode.playerTime(forNodeTime: nodeTime) else {
                        return (self.playerNode.isPlaying, 0, 0)
                    }

                    let sampleRate = playerTime.sampleRate
                    let elapsedSeconds = sampleRate > 0
                        ? Int((Double(playerTime.sampleTime) / sampleRate).rounded(.down))
                        : 0
                    let progress = totalDuration > 0
                        ? min(1, Double(elapsedSeconds) / Double(totalDuration))
                        : 0
                    return (self.playerNode.isPlaying, elapsedSeconds, progress)
                }

                if snapshot.0 {
                    await MainActor.run {
                        onProgress(
                            ReaderPlaybackUpdate(
                                elapsedSeconds: snapshot.1,
                                durationSeconds: totalDuration,
                                progress: snapshot.2,
                                chunkIndex: self.activeChunkIndex,
                                isPlaying: true
                            )
                        )
                    }
                }

                try? await Task.sleep(nanoseconds: 250_000_000)
            }

            let isStoppedNaturally = await MainActor.run { !self.playerNode.isPlaying && !self.stopRequested }
            if isStoppedNaturally {
                await MainActor.run {
                    self.isPlaying = false
                    self.isPaused = false
                    self.playbackSession = nil
                    onFinished()
                }
            }
        }
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
