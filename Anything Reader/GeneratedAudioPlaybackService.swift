//
//  GeneratedAudioPlaybackService.swift
//  Anything Reader
//
//  Audio Player
//  Plays exported library audio files without touching the Kokoro playback
//  pipeline. This keeps generated-audio playback isolated from live TTS and
//  lets the app resume already rendered audio independently from narration.
//

import AVFoundation
import Combine
import Foundation

@MainActor
final class GeneratedAudioPlaybackService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    // Shared singleton because generated audio playback is coordinated from multiple reader screens.
    static let shared = GeneratedAudioPlaybackService()

    @Published private(set) var isPlaying = false
    @Published private(set) var currentFileURL: URL?
    @Published private(set) var currentTitle = ""
    @Published private(set) var currentElapsedSeconds = 0
    @Published private(set) var currentDurationSeconds = 0
    @Published private(set) var volume: Double
    @Published private(set) var playbackSpeed: Double

    private var player: AVAudioPlayer?
    private var progressTimer: Timer?
    private var seekDebounceTask: Task<Void, Never>?
    private var onProgress: ((Int, Int) -> Void)?
    private var onFinished: (() -> Void)?
    private var onFailure: ((String) -> Void)?

    private static let volumeStorageKey = "generatedAudioPlaybackVolume"
    private static let playbackSpeedStorageKey = "generatedAudioPlaybackSpeed"

    // Restores persisted playback preferences so the app remembers volume and speed.
    private override init() {
        let storedVolume = UserDefaults.standard.object(forKey: Self.volumeStorageKey) as? Double
        let storedSpeed = UserDefaults.standard.object(forKey: Self.playbackSpeedStorageKey) as? Double
        volume = storedVolume ?? 0.9
        playbackSpeed = Self.clampPlaybackSpeed(storedSpeed ?? 1.0)
        super.init()
    }

    // True when a file is already loaded, even if playback is currently paused.
    var hasLoadedAudio: Bool {
        currentFileURL != nil
    }

    // Checks whether the requested file is the active file and is currently playing.
    func isPlayingAudio(for fileURL: URL) -> Bool {
        guard let currentFileURL else { return false }
        return currentFileURL.standardizedFileURL.path == fileURL.standardizedFileURL.path && isPlaying
    }

    // Checks whether the requested file is the currently loaded file.
    func hasLoadedAudio(for fileURL: URL) -> Bool {
        guard let currentFileURL else { return false }
        return currentFileURL.standardizedFileURL.path == fileURL.standardizedFileURL.path
    }

    // Updates player volume and persists the user preference.
    func setVolume(_ newValue: Double) {
        let clamped = min(max(newValue, 0), 1)
        volume = clamped
        player?.volume = Float(clamped)
        UserDefaults.standard.set(clamped, forKey: Self.volumeStorageKey)
    }

    // Updates player rate and persists the speed preference.
    func setPlaybackSpeed(_ newValue: Double) {
        let clamped = Self.clampPlaybackSpeed(newValue)
        playbackSpeed = clamped
        // AVAudioPlayer can speed up already rendered audio directly, so the
        // generated-audio player keeps speed control local to this service.
        player?.enableRate = true
        player?.rate = Float(clamped)
        UserDefaults.standard.set(clamped, forKey: Self.playbackSpeedStorageKey)
    }

    // Loads or resumes a rendered file and wires up the progress callbacks for the UI.
    func play(
        fileURL: URL,
        title: String,
        startingTime: TimeInterval = 0,
        onProgress: @escaping (Int, Int) -> Void = { _, _ in },
        onFinished: @escaping () -> Void,
        onFailure: @escaping (String) -> Void
    ) {
        // Reuse an already loaded file when possible so resume, speed, and
        // volume state stay intact across play/pause toggles.
        ReaderPlaybackEventCenter.post(
            ReaderPlaybackEvent(kind: .willTransition, source: .generatedAudio)
        )
        if hasLoadedAudio(for: fileURL), let player {
            self.onProgress = onProgress
            self.onFinished = onFinished
            self.onFailure = onFailure
            currentTitle = title
            let clampedStartingTime = min(max(startingTime, 0), player.duration)
            player.enableRate = true
            player.rate = Float(playbackSpeed)
            player.currentTime = clampedStartingTime
            currentElapsedSeconds = max(0, Int(clampedStartingTime.rounded()))
            currentDurationSeconds = max(0, Int(player.duration.rounded()))

            if player.isPlaying {
                onProgress(currentElapsedSeconds, currentDurationSeconds)
                return
            }

            player.enableRate = true
            player.rate = Float(playbackSpeed)
            player.play()
            isPlaying = true
            startProgressTimer()
            ReaderPlaybackEventCenter.post(
                ReaderPlaybackEvent(kind: .didStart, source: .generatedAudio)
            )
            onProgress(currentElapsedSeconds, currentDurationSeconds)
            return
        }

        stop()

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            onFailure("The generated audio file could not be found on disk.")
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: fileURL)
            player.delegate = self
            player.volume = Float(volume)
            player.prepareToPlay()
            let clampedStartingTime = min(max(startingTime, 0), player.duration)
            player.enableRate = true
            player.rate = Float(playbackSpeed)
            player.currentTime = clampedStartingTime
            self.player = player
            self.currentFileURL = fileURL
            self.currentTitle = title
            self.currentElapsedSeconds = max(0, Int(clampedStartingTime.rounded()))
            self.currentDurationSeconds = max(0, Int(player.duration.rounded()))
            self.onProgress = onProgress
            self.onFinished = onFinished
            self.onFailure = onFailure
            self.isPlaying = true
            player.play()
            startProgressTimer()
            ReaderPlaybackEventCenter.post(
                ReaderPlaybackEvent(kind: .didStart, source: .generatedAudio)
            )
            onProgress(currentElapsedSeconds, currentDurationSeconds)
        } catch {
            stop()
            onFailure(error.localizedDescription)
        }
    }

    // Toggles pause and resume for the loaded generated-audio file.
    func togglePlayback() {
        guard let player, currentFileURL != nil else { return }

        if player.isPlaying {
            // Pause preserves the current file URL and elapsed time so resume
            // uses the same audio file without reloading it.
            updateProgress()
            player.pause()
            isPlaying = false
            stopProgressTimer()
            ReaderPlaybackEventCenter.post(
                ReaderPlaybackEvent(kind: .didPause, source: .generatedAudio)
            )
        } else {
            player.enableRate = true
            player.rate = Float(playbackSpeed)
            player.play()
            isPlaying = true
            startProgressTimer()
            ReaderPlaybackEventCenter.post(
                ReaderPlaybackEvent(kind: .didStart, source: .generatedAudio)
            )
        }
    }

    func seek(to progressFraction: Double) {
        seekDebounceTask?.cancel()

        let clampedFraction = min(max(progressFraction, 0), 1)
        seekDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            self.applySeek(to: clampedFraction)
        }
    }

    func stop() {
        // Stop clears all ephemeral playback state but does not delete the
        // exported audio file on disk.
        seekDebounceTask?.cancel()
        seekDebounceTask = nil
        updateProgress()
        stopProgressTimer()
        player?.stop()
        player = nil
        isPlaying = false
        currentFileURL = nil
        currentTitle = ""
        currentElapsedSeconds = 0
        currentDurationSeconds = 0
        onProgress = nil
        onFinished = nil
        onFailure = nil

        ReaderPlaybackEventCenter.post(
            ReaderPlaybackEvent(kind: .didStop, source: .generatedAudio)
        )
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stopProgressTimer()

        let finishedHandler = onFinished
        let failureHandler = onFailure

        isPlaying = false
        currentFileURL = nil
        currentTitle = ""
        currentElapsedSeconds = 0
        currentDurationSeconds = 0
        self.player = nil
        onProgress = nil
        onFinished = nil
        onFailure = nil

        if flag {
            ReaderPlaybackEventCenter.post(
                ReaderPlaybackEvent(kind: .didFinish, source: .generatedAudio)
            )
            finishedHandler?()
        } else {
            ReaderPlaybackEventCenter.post(
                ReaderPlaybackEvent(kind: .didStop, source: .generatedAudio)
            )
            failureHandler?("Playback ended unexpectedly.")
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        stopProgressTimer()

        let failureHandler = onFailure
        isPlaying = false
        currentFileURL = nil
        currentTitle = ""
        currentElapsedSeconds = 0
        currentDurationSeconds = 0
        self.player = nil
        onProgress = nil
        onFinished = nil
        onFailure = nil

        if let error {
            failureHandler?(error.localizedDescription)
        } else {
            failureHandler?("The generated audio file could not be played.")
        }

        ReaderPlaybackEventCenter.post(
            ReaderPlaybackEvent(kind: .didStop, source: .generatedAudio)
        )
    }

    private func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(
            timeInterval: 0.25,
            target: self,
            selector: #selector(progressTimerFired),
            userInfo: nil,
            repeats: true
        )
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    @objc
    nonisolated
    private func progressTimerFired() {
        Task { @MainActor in
            self.updateProgress()
        }
    }

    private func updateProgress() {
        guard let player else { return }
        currentElapsedSeconds = max(0, Int(player.currentTime.rounded()))
        currentDurationSeconds = max(0, Int(player.duration.rounded()))
        onProgress?(currentElapsedSeconds, currentDurationSeconds)
    }

    private func applySeek(to progressFraction: Double) {
        guard let player else { return }
        guard player.duration > 0 else { return }

        let targetTime = player.duration * progressFraction
        let shouldResumePlaying = player.isPlaying

        player.currentTime = targetTime
        currentElapsedSeconds = max(0, Int(targetTime.rounded()))
        currentDurationSeconds = max(0, Int(player.duration.rounded()))
        onProgress?(currentElapsedSeconds, currentDurationSeconds)

        if shouldResumePlaying {
            player.enableRate = true
            player.rate = Float(playbackSpeed)
            player.play()
            isPlaying = true
            startProgressTimer()
        }
    }

    private static func clampPlaybackSpeed(_ value: Double) -> Double {
        let clamped = min(max(value, 0.5), 2.0)
        return (clamped * 10).rounded() / 10
    }
}
