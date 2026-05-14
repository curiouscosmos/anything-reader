//
//  ReaderPlaybackService.swift
//  Anything Reader
//
//  Narration player
//  Queued TTS playback controller for library entries.
//  It synthesizes chunked audio ahead of time and schedules it on a single
//  AVAudioPlayerNode so the handoff between chunks stays gap-free.
//

import AVFoundation
import Combine
import Foundation
import SwiftData

// Lightweight progress payload for the narration player UI.
// The UI uses this snapshot to refresh time, progress, and the current chunk
// without reaching into the audio engine directly.
struct ReaderPlaybackUpdate {
    let elapsedSeconds: Int
    let durationSeconds: Int
    let progress: Double
    let chunkIndex: Int
    let isPlaying: Bool
}

// Drives one library entry at a time through provider-backed chunked playback.
// This service stays focused on live narration so generated-audio playback can
// remain in its own isolated player service.
@MainActor
final class ReaderPlaybackService: NSObject, ObservableObject {
    // Shared singleton because the narration queue is global to the active reader session.
    static let shared = ReaderPlaybackService()

    // Published playback state that the reader UI observes directly.
    @Published private(set) var isPlaying = false
    @Published private(set) var isPaused = false
    @Published private(set) var isBufferingFirstChunk = false
    @Published private(set) var activePlaybackIdentity: String?
    @Published private(set) var volume: Double

    // The audio engine and player node are rebuilt after stop so each session
    // starts from a clean, known-good graph.
    private var engine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    // Identifies the current playback target so stale callbacks can be ignored.
    private struct PlaybackSession {
        let id: UUID
        let identity: String
    }

    // Background tasks used for synthesis and progress polling.
    private var playbackTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?
    // Cancellation and cache state for the current narration session.
    private var stopRequested = false
    private var didConfigureEngine = false
    private var synthesizedAudioURLs: [Int: URL] = [:]
    private var synthesisTasks: [Int: Task<URL, Error>] = [:]
    private var playbackSessionID = UUID()
    private var playbackSession: PlaybackSession?
    private var activeChunkIndex = 0
    // Tracks the last chunk that actually reached audible playback. This must
    // only move forward when a chunk completes, not when it is merely queued.
    private(set) var currentAudibleChunkIndex = 0

    // UserDefaults key for preserving the player volume between launches.
    private static let volumeStorageKey = "readerPlaybackVolume"

    private override init() {
        // Restore the last saved volume, falling back to a comfortable default.
        let storedVolume = UserDefaults.standard.object(forKey: Self.volumeStorageKey) as? Double
        self.volume = storedVolume ?? 0.9
        super.init()
        playerNode.volume = Float(volume)
    }

    // Stops playback, cancels synthesis, and clears all session-specific caches.
    func stop() {
        // Mark the current session as cancelled before tearing down any state.
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

        // Detach references to the existing engine objects so they can be
        // stopped and reset before a fresh engine is created.
        let oldEngine = engine
        let oldPlayerNode = playerNode

        // Stop the active node and engine if they are still running.
        if oldPlayerNode.isPlaying {
            oldPlayerNode.stop()
        }
        oldPlayerNode.reset()
        if oldEngine.isRunning {
            oldEngine.stop()
        }

        // Rebuild the audio graph so the next playback starts cleanly.
        engine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        playerNode.volume = Float(volume)
        didConfigureEngine = false

        // Reset observable state so the UI immediately reflects the stop.
        isPlaying = false
        isPaused = false
        isBufferingFirstChunk = false
        activePlaybackIdentity = nil
        activeChunkIndex = 0
        currentAudibleChunkIndex = 0

        // Tell the rest of the app that reader playback has ended.
        ReaderPlaybackEventCenter.post(
            ReaderPlaybackEvent(kind: .didStop, source: .reader)
        )
    }

    // Persists the player volume and updates the active audio node immediately.
    func setVolume(_ newValue: Double) {
        // Clamp the input so the stored value always stays within range.
        let clampedVolume = min(max(newValue, 0), 1)
        volume = clampedVolume
        playerNode.volume = Float(clampedVolume)
        UserDefaults.standard.set(clampedVolume, forKey: Self.volumeStorageKey)
    }

    // Starts chunked narration playback for the given entry and voice selection.
    func play(
        entry: LibraryEntry,
        voice: ReaderTTSVoiceSelection,
        startingProgress: Double,
        startingChunkIndex: Int? = nil,
        textFileURL: URL? = nil,
        onProgress: @escaping (ReaderPlaybackUpdate) -> Void,
        onFinished: @escaping () -> Void,
        onFailure: @escaping (String) -> Void
    ) {
        // Starting a new narration session resets any previously scheduled
        // chunk queue so the player can resume from the selected reading target.
        ReaderPlaybackEventCenter.post(
            ReaderPlaybackEvent(kind: .willTransition, source: .reader)
        )
        // Stop any in-flight playback before starting the new session.
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
        currentAudibleChunkIndex = activeChunkIndex
        playerNode.volume = Float(volume)

        // Run the long-lived playback workflow off the main thread while state
        // changes still funnel back through MainActor when needed.
        playbackTask = Task { [weak self] in
            guard let self else { return }

            // Split the document into narration chunks before any synthesis work begins.
            let chunks = ReaderPlaybackChunkService.chunks(for: entry, textFileURL: textFileURL)
            guard !chunks.isEmpty else {
                // Fail fast when the source file has no readable text at all.
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
            // Estimate total duration and current elapsed time from chunk lengths
            // so the UI has useful progress information before audio is rendered.
            let estimatedTotalDuration = Self.estimatedDuration(for: chunks)
            let initialElapsed = Self.elapsedEstimate(for: chunks, upTo: startIndex)

            // Publish the initial progress snapshot before audio starts to flow.
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

            // Configure the audio engine exactly once for this service instance.
            await MainActor.run {
                guard self.playbackSessionID == sessionID else { return }
                self.configureEngineIfNeeded()
                self.playerNode.reset()
            }

            // Start the audio engine before any file scheduling occurs.
            do {
                try engine.start()
            } catch {
                // Surface engine startup failures as user-facing playback errors.
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

            // Begin polling the player node so progress stays in sync with playback.
            startProgressMonitor(
                chunkCount: chunks.count,
                totalDuration: estimatedTotalDuration,
                initialElapsed: initialElapsed,
                onProgress: onProgress,
                onFinished: onFinished,
                onFailure: onFailure
            )

            // Broadcast the active reader playback session to any observers.
            ReaderPlaybackEventCenter.post(
                ReaderPlaybackEvent(kind: .didStart, source: .reader)
            )

            // Walk the chunk list in order, synthesizing and scheduling audio as needed.
            var scheduledChunkCount = 0

            for chunkIndex in startIndex..<chunks.count {
                // Exit immediately if the session was cancelled or replaced.
                if stopRequested || Task.isCancelled {
                    break
                }
                let isStaleSession = await MainActor.run { self.playbackSessionID != sessionID }
                if isStaleSession {
                    break
                }

                // Skip chunks that are empty after whitespace normalization.
                let chunkText = chunks[chunkIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !chunkText.isEmpty else { continue }
                await MainActor.run {
                    self.activeChunkIndex = chunkIndex
                }

                // The first chunk prefers an existing cached audio file so playback
                // can start quickly without waiting on fresh synthesis.
                let isFirstSessionChunk = chunkIndex == startIndex
                if isFirstSessionChunk,
                   let cachedAudioURL = await ReaderPlaybackAudioCacheService.shared.cachedAudioURL(
                    for: entry,
                    providerID: voice.providerID,
                    voiceName: voice.voiceName,
                    chunkText: chunkText,
                    languageCode: cacheLanguageCode(for: entry, providerID: voice.providerID)
                   ) {
                    await MainActor.run {
                        guard self.playbackSessionID == sessionID else { return }
                        self.scheduleAudioFile(
                            cachedAudioURL,
                            isFinalChunk: chunkIndex == chunks.count - 1,
                            chunkIndex: chunkIndex,
                            chunkCount: chunks.count,
                            sessionID: sessionID,
                            onFinished: onFinished
                        )
                        if !self.playerNode.isPlaying && !self.isPaused {
                            self.playerNode.play()
                        }
                    }

                    scheduledChunkCount += 1

                    // Clear the initial buffering flag as soon as the first chunk is queued.
                    if scheduledChunkCount == 1 {
                        await MainActor.run {
                            guard self.playbackSessionID == sessionID else { return }
                            self.isBufferingFirstChunk = false
                        }
                    }

                    // Warm the next few chunks in the background while the first chunk plays.
                    await primeAudioPrefetch(for: entry, chunks: chunks, voice: voice, startingAt: chunkIndex + 1, sessionID: sessionID)
                    continue
                }

                // Precompute phonemes so future synthesis passes can reuse them.
                if await PhonemeCacheService.shared.cachedPhonemes(for: entry, chunkIndex: chunkIndex, providerID: voice.providerID) == nil {
                    let phonemes = await phonemes(for: chunkText, providerID: voice.providerID)
                    if !phonemes.isEmpty {
                        await PhonemeCacheService.shared.store(phonemes, for: entry, chunkIndex: chunkIndex, providerID: voice.providerID)
                    }
                }

                // Synthesize the chunk, or reuse a prefetched result if one exists.
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

                // Schedule the synthesized file onto the player node and start it if
                // playback has not already begun.
                await MainActor.run {
                    guard self.playbackSessionID == sessionID else { return }
                    self.scheduleAudioFile(
                        audioURL,
                        isFinalChunk: chunkIndex == chunks.count - 1,
                        chunkIndex: chunkIndex,
                        chunkCount: chunks.count,
                        sessionID: sessionID,
                        onFinished: onFinished
                    )
                    if !self.playerNode.isPlaying && !self.isPaused {
                        self.playerNode.play()
                    }
                }

                scheduledChunkCount += 1

                // Clear the initial buffering flag as soon as the first chunk is queued.
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

            // If nothing could be scheduled, treat that as a synthesis failure.
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

            // Wait until playback naturally drains or the session is cancelled.
            while !stopRequested && !Task.isCancelled {
                let isNodePlaying = await MainActor.run { self.playerNode.isPlaying }
                if !isNodePlaying {
                    break
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }

            // If the wait loop exited because playback stopped by itself, leave the
            // UI in a finished state instead of a paused/stopped intermediate state.
            if stopRequested || Task.isCancelled {
                return
            }
        }
    }

    func pause() {
        // Pause only if the node is actually playing.
        guard playerNode.isPlaying else { return }

        playerNode.pause()
        isPlaying = false
        isPaused = true

        ReaderPlaybackEventCenter.post(
            ReaderPlaybackEvent(kind: .didPause, source: .reader)
        )
    }

    func resume() {
        // Resume only from the paused state so the audio graph stays consistent.
        guard isPaused else { return }

        playerNode.play()
        isPlaying = true
        isPaused = false

        ReaderPlaybackEventCenter.post(
            ReaderPlaybackEvent(kind: .didStart, source: .reader)
        )
    }

    func isActivePlayback(for entry: LibraryEntry, textFileURL: URL? = nil) -> Bool {
        // Compare the caller's identity with the current session identity.
        guard let playbackSession else { return false }
        return playbackSession.identity == playbackIdentity(for: entry, textFileURL: textFileURL)
    }

    func isPausedPlayback(for entry: LibraryEntry, textFileURL: URL? = nil) -> Bool {
        // A paused playback is only meaningful if it matches the active entry.
        guard isPaused else { return false }
        return isActivePlayback(for: entry, textFileURL: textFileURL)
    }

    private func configureEngineIfNeeded() {
        // Build the audio graph once and reuse it until the session is reset.
        guard !didConfigureEngine else { return }

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: nil)
        engine.prepare()
        didConfigureEngine = true
    }

    private func playbackIdentity(for entry: LibraryEntry, textFileURL: URL?) -> String {
        // Combine persistent model identity and any alternate text file path so
        // multiple playback sources for the same record do not collide.
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
        chunkIndex: Int,
        chunkCount: Int,
        sessionID: UUID,
        onFinished: @escaping () -> Void
    ) {
        // Translate the synthesized file into an AVAudioFile that can be queued.
        guard let audioFile = try? AVAudioFile(forReading: url) else { return }
        // Invoke the completion handler only when the final chunk finishes and
        // the callback still belongs to the active playback session.
        playerNode.scheduleFile(audioFile, at: nil) { [weak self] in
            guard let self else { return }

            Task { @MainActor in
                guard self.playbackSessionID == sessionID else { return }
                // Advance the audible chunk only after the current chunk has
                // fully finished. Prefetched or scheduled chunks never touch
                // this value, which keeps resume state tied to what the user
                // actually heard.
                self.currentAudibleChunkIndex = min(chunkIndex + 1, max(chunkCount - 1, 0))
                guard isFinalChunk else { return }
                self.finishPlayback(onFinished: onFinished)
            }
        }
    }

    private func finishPlayback(onFinished: @escaping () -> Void) {
        // Mark the session as completed before tearing down runtime audio state.
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

        // Notify other parts of the app and then hand control back to the caller.
        ReaderPlaybackEventCenter.post(
            ReaderPlaybackEvent(kind: .didFinish, source: .reader)
        )
        onFinished()
    }

    private func primeAudioPrefetch(
        for entry: LibraryEntry,
        chunks: [String],
        voice: ReaderTTSVoiceSelection,
        startingAt index: Int,
        sessionID: UUID
    ) async {
        // Prefetch only for the current, non-empty session.
        guard !chunks.isEmpty else { return }
        let isCurrentSession = await MainActor.run { self.playbackSessionID == sessionID }
        guard isCurrentSession else { return }

        // Clamp the prefetch window to the chunk array so the loop stays safe.
        let startIndex = min(max(index, 0), chunks.count - 1)
        let upperBound = min(chunks.count - 1, startIndex + ReaderPlaybackChunkService.prefetchChunkCount)

        // Kick off synthesis work for a small window of upcoming chunks.
        for chunkIndex in startIndex...upperBound {
            guard chunkIndex < chunks.count else { continue }
            guard synthesizedAudioURLs[chunkIndex] == nil else { continue }
            guard synthesisTasks[chunkIndex] == nil else { continue }
            let stillCurrentSession = await MainActor.run { self.playbackSessionID == sessionID }
            guard stillCurrentSession else { return }

            let chunkText = chunks[chunkIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !chunkText.isEmpty else { continue }

            // Make sure phoneme caching is populated before the synthesis task runs.
            if await awaitCachedPhonemesMissing(for: entry, chunkIndex: chunkIndex, text: chunkText, providerID: voice.providerID) {
                let phonemes = await phonemes(for: chunkText, providerID: voice.providerID)
                if !phonemes.isEmpty {
                    Task { await PhonemeCacheService.shared.store(phonemes, for: entry, chunkIndex: chunkIndex, providerID: voice.providerID) }
                }
            }

            // Retain the synthesis task so later playback can await the same work.
            let task = Task<URL, Error> {
                try await ReaderTTSCoordinator.shared.synthesize(
                    text: chunkText,
                    voice: voice,
                    language: playbackLanguage(for: entry, providerID: voice.providerID)
                )
            }
            synthesisTasks[chunkIndex] = task

            // Record the result back into the session cache when synthesis completes.
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

    private func awaitCachedPhonemesMissing(for entry: LibraryEntry, chunkIndex: Int, text: String, providerID: ReaderTTSProviderID) async -> Bool {
        // Only synthesize phonemes when the cache has no entry and the text is real.
        if await PhonemeCacheService.shared.cachedPhonemes(for: entry, chunkIndex: chunkIndex, providerID: providerID) != nil {
            return false
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return true
    }

    private func synthesizedAudioURL(
        for chunkIndex: Int,
        entry: LibraryEntry,
        voice: ReaderTTSVoiceSelection,
        text: String,
        isPrimaryChunk: Bool,
        sessionID: UUID
    ) async throws -> URL {
        // Reject work from stale sessions so new playback starts cleanly.
        let isActiveSession = await MainActor.run { self.playbackSessionID == sessionID }
        guard isActiveSession else {
            throw CancellationError()
        }

        // Reuse any already-available synthesized file for this chunk.
        if let cached = synthesizedAudioURLs[chunkIndex] {
            return cached
        }

        // The first chunk can reuse the persistent audio cache before we synthesize.
        if isPrimaryChunk,
           let cachedAudioURL = await ReaderPlaybackAudioCacheService.shared.cachedAudioURL(
            for: entry,
            providerID: voice.providerID,
            voiceName: voice.voiceName,
            chunkText: text,
            languageCode: cacheLanguageCode(for: entry, providerID: voice.providerID)
           ) {
            synthesizedAudioURLs[chunkIndex] = cachedAudioURL
            return cachedAudioURL
        }

        // If prefetch already started this chunk, wait for that task instead of
        // launching duplicate synthesis work.
        if let task = synthesisTasks[chunkIndex] {
            let url = try await task.value
            synthesizedAudioURLs[chunkIndex] = url
            synthesisTasks.removeValue(forKey: chunkIndex)
            return url
        }

        // Otherwise create a new synthesis task and store its result locally.
        let task = Task<URL, Error> {
            try await ReaderTTSCoordinator.shared.synthesize(
                text: text,
                voice: voice,
                language: playbackLanguage(for: entry, providerID: voice.providerID)
            )
        }

        synthesisTasks[chunkIndex] = task

        do {
            let url = try await task.value
            let cachedURL: URL
            if isPrimaryChunk,
               let storedURL = await ReaderPlaybackAudioCacheService.shared.storeAudio(
                at: url,
                for: entry,
                providerID: voice.providerID,
                voiceName: voice.voiceName,
                chunkText: text,
                languageCode: cacheLanguageCode(for: entry, providerID: voice.providerID)
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
            // Clean up task bookkeeping even when synthesis fails so retries work.
            let isStillActive = await MainActor.run { self.playbackSessionID == sessionID }
            if isStillActive {
                synthesisTasks.removeValue(forKey: chunkIndex)
            }
            throw error
        }
    }

    private func phonemes(for text: String, providerID: ReaderTTSProviderID) async -> String {
        // Use provider-specific preprocessing so the phoneme cache matches the
        // synthesis engine that will consume it.
        switch providerID {
        case .kokoro:
            return await KokoroG2PService.shared.phonemize(text)
        case .moonshine:
            return TextNormalizationService.normalize(text)
        case .supertonic:
            return TextNormalizationService.normalize(text)
        }
    }

    private func playbackLanguage(for entry: LibraryEntry, providerID: ReaderTTSProviderID) -> TextLanguage? {
        providerID == .supertonic ? entry.textLanguage : nil
    }

    private func cacheLanguageCode(for entry: LibraryEntry, providerID: ReaderTTSProviderID) -> String? {
        guard providerID == .supertonic else { return nil }
        return SupertonicLanguageCatalog.languageCode(for: entry.textLanguage)
    }

    private func startProgressMonitor(
        chunkCount: Int,
        totalDuration: Int,
        initialElapsed: Int,
        onProgress: @escaping (ReaderPlaybackUpdate) -> Void,
        onFinished: @escaping () -> Void,
        onFailure: @escaping (String) -> Void
    ) {
        // Replace any previous progress poller with the new session's monitor.
        progressTask?.cancel()

        // Poll the player node on a fixed cadence so the UI stays responsive
        // without requiring continuous main-thread work.
        progressTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled && !self.stopRequested {
                // Derive absolute elapsed and progress by offsetting the player node's
                // sample-based time (which resets to 0 on each play call) by the
                // estimated duration of the chunks that precede the start index.
                // This ensures jumps to mid-document positions report the correct
                // progress and chapter instead of the synthesis-ahead chunk index.
                let snapshot = await MainActor.run { () -> (Bool, Int, Double) in
                    guard self.playerNode.isPlaying,
                          let nodeTime = self.playerNode.lastRenderTime,
                          let playerTime = self.playerNode.playerTime(forNodeTime: nodeTime) else {
                        return (self.playerNode.isPlaying, initialElapsed, totalDuration > 0 ? min(1, Double(initialElapsed) / Double(totalDuration)) : 0)
                    }

                    let sampleRate = playerTime.sampleRate
                    let rawElapsed = sampleRate > 0
                        ? Int((Double(playerTime.sampleTime) / sampleRate).rounded(.down))
                        : 0
                    let absoluteElapsed = initialElapsed + rawElapsed
                    let progress = totalDuration > 0
                        ? min(1, Double(absoluteElapsed) / Double(totalDuration))
                        : 0
                    return (self.playerNode.isPlaying, absoluteElapsed, progress)
                }

                // Only publish progress when the player node is actively running.
                if snapshot.0 {
                    let chunkIndex = ReaderPlaybackChunkService.chunkIndex(
                        for: snapshot.2,
                        chunkCount: chunkCount
                    )
                    await MainActor.run {
                        onProgress(
                            ReaderPlaybackUpdate(
                                elapsedSeconds: snapshot.1,
                                durationSeconds: totalDuration,
                                progress: snapshot.2,
                                chunkIndex: chunkIndex,
                                isPlaying: true
                            )
                        )
                    }
                }

                // Sleeping briefly keeps the monitor lightweight while still
                // updating the UI frequently enough for a smooth progress bar.
                try? await Task.sleep(nanoseconds: 250_000_000)
            }

            // If the node is idle and we did not request a stop, treat the run
            // as a natural completion and notify the caller.
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
        // Convert chunk length to a coarse duration estimate with sane minimums
        // and maximums so the UI does not jump around wildly for short or long text.
        let estimated = chunks.reduce(into: 0) { partialResult, chunk in
            partialResult += max(4, min(120, chunk.count / 12))
        }
        return max(estimated, 30)
    }

    private static func elapsedEstimate(for chunks: [String], upTo chunkIndex: Int) -> Int {
        // Sum the estimated duration of the chunks that precede the starting index.
        guard !chunks.isEmpty else { return 0 }
        let cappedIndex = min(max(chunkIndex, 0), chunks.count - 1)
        let completed = chunks.prefix(cappedIndex).reduce(into: 0) { partialResult, chunk in
            partialResult += max(4, min(120, chunk.count / 12))
        }
        return completed
    }
}
