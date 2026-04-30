//
//  GeneratedAudioPlaybackService.swift
//  Anything Reader
//
//  Plays exported library audio files without touching the Kokoro playback
//  pipeline. This keeps generated-audio playback isolated from live TTS.
//

import AVFoundation
import Combine
import Foundation

@MainActor
final class GeneratedAudioPlaybackService: NSObject, ObservableObject, AVAudioPlayerDelegate {
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
    private var onProgress: ((Int, Int) -> Void)?
    private var onFinished: (() -> Void)?
    private var onFailure: ((String) -> Void)?

    private static let volumeStorageKey = "generatedAudioPlaybackVolume"
    private static let playbackSpeedStorageKey = "generatedAudioPlaybackSpeed"

    private override init() {
        let storedVolume = UserDefaults.standard.object(forKey: Self.volumeStorageKey) as? Double
        let storedSpeed = UserDefaults.standard.object(forKey: Self.playbackSpeedStorageKey) as? Double
        volume = storedVolume ?? 0.9
        playbackSpeed = Self.clampPlaybackSpeed(storedSpeed ?? 1.0)
        super.init()
    }

    var hasLoadedAudio: Bool {
        currentFileURL != nil
    }

    func isPlayingAudio(for fileURL: URL) -> Bool {
        guard let currentFileURL else { return false }
        return currentFileURL.standardizedFileURL.path == fileURL.standardizedFileURL.path && isPlaying
    }

    func hasLoadedAudio(for fileURL: URL) -> Bool {
        guard let currentFileURL else { return false }
        return currentFileURL.standardizedFileURL.path == fileURL.standardizedFileURL.path
    }

    func setVolume(_ newValue: Double) {
        let clamped = min(max(newValue, 0), 1)
        volume = clamped
        player?.volume = Float(clamped)
        UserDefaults.standard.set(clamped, forKey: Self.volumeStorageKey)
    }

    func setPlaybackSpeed(_ newValue: Double) {
        let clamped = Self.clampPlaybackSpeed(newValue)
        playbackSpeed = clamped
        player?.enableRate = true
        player?.rate = Float(clamped)
        UserDefaults.standard.set(clamped, forKey: Self.playbackSpeedStorageKey)
    }

    func play(
        fileURL: URL,
        title: String,
        startingTime: TimeInterval = 0,
        onProgress: @escaping (Int, Int) -> Void = { _, _ in },
        onFinished: @escaping () -> Void,
        onFailure: @escaping (String) -> Void
    ) {
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
            onProgress(currentElapsedSeconds, currentDurationSeconds)
        } catch {
            stop()
            onFailure(error.localizedDescription)
        }
    }

    func togglePlayback() {
        guard let player, currentFileURL != nil else { return }

        if player.isPlaying {
            updateProgress()
            player.pause()
            isPlaying = false
            stopProgressTimer()
        } else {
            player.enableRate = true
            player.rate = Float(playbackSpeed)
            player.play()
            isPlaying = true
            startProgressTimer()
        }
    }

    func stop() {
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
            finishedHandler?()
        } else {
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

    private static func clampPlaybackSpeed(_ value: Double) -> Double {
        let clamped = min(max(value, 0.5), 2.0)
        return (clamped * 10).rounded() / 10
    }
}
