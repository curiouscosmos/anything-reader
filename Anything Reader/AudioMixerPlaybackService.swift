//
//  AudioMixerPlaybackService.swift
//  Anything Reader
//
//  Plays a selected background music track in parallel with the main reader
//  player. The service keeps playback, looping, and reader-sync state isolated
//  from the narration engines.
//

import AVFoundation
import Foundation
import Combine

enum AudioMixerReaderPlaybackState: Equatable {
    case playing
    case paused
    case stopped
}

@MainActor
final class AudioMixerPlaybackService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = AudioMixerPlaybackService()

    @Published private(set) var isPlaying = false
    @Published private(set) var isPaused = false
    @Published private(set) var selectedTrackID: String?
    @Published private(set) var selectedTrackTitle = ""
    @Published var alertMessage: String?
    @Published var volume: Double
    @Published var isLooping: Bool
    @Published var followsReaderPlayback: Bool

    private var player: AVAudioPlayer?
    private var pendingReaderStopTask: Task<Void, Never>?
    private var isReaderTransitioning = false

    private static let volumeStorageKey = "audioMixerVolume"
    private static let loopingStorageKey = "audioMixerLooping"
    private static let followsReaderPlaybackStorageKey = "audioMixerFollowsReaderPlayback"
    private static let selectedTrackIDStorageKey = "audioMixerSelectedTrackID"

    private override init() {
        let storedVolume = UserDefaults.standard.object(forKey: Self.volumeStorageKey) as? Double
        let storedLooping = UserDefaults.standard.object(forKey: Self.loopingStorageKey) as? Bool
        let storedFollowsReaderPlayback = UserDefaults.standard.object(forKey: Self.followsReaderPlaybackStorageKey) as? Bool
        let storedTrackID = UserDefaults.standard.string(forKey: Self.selectedTrackIDStorageKey)

        volume = storedVolume ?? 0.28
        isLooping = storedLooping ?? true
        followsReaderPlayback = storedFollowsReaderPlayback ?? false
        selectedTrackID = storedTrackID
        super.init()
    }

    var hasSelection: Bool {
        selectedTrackID != nil
    }

    func setVolume(_ newValue: Double) {
        let clamped = min(max(newValue, 0), 1)
        volume = clamped
        player?.volume = Float(clamped)
        UserDefaults.standard.set(clamped, forKey: Self.volumeStorageKey)
    }

    func setLooping(_ newValue: Bool) {
        isLooping = newValue
        player?.numberOfLoops = newValue ? -1 : 0
        UserDefaults.standard.set(newValue, forKey: Self.loopingStorageKey)
    }

    func setFollowsReaderPlayback(_ newValue: Bool) {
        followsReaderPlayback = newValue
        UserDefaults.standard.set(newValue, forKey: Self.followsReaderPlaybackStorageKey)
    }

    func isSelected(_ track: AudioMixerTrack) -> Bool {
        selectedTrackID == track.id
    }

    func isPlayingTrack(_ track: AudioMixerTrack) -> Bool {
        isSelected(track) && isPlaying
    }

    func isPausedTrack(_ track: AudioMixerTrack) -> Bool {
        isSelected(track) && isPaused
    }

    func togglePlayback(for track: AudioMixerTrack) {
        if isPlayingTrack(track) {
            pause()
            return
        }

        if isPausedTrack(track) {
            resume()
            return
        }

        play(track: track)
    }

    func play(track: AudioMixerTrack) {
        selectedTrackID = track.id
        selectedTrackTitle = track.title
        UserDefaults.standard.set(track.id, forKey: Self.selectedTrackIDStorageKey)

        guard FileManager.default.fileExists(atPath: track.fileURL.path) else {
            alertMessage = AudioMixerLibraryError.trackMissing.localizedDescription
            stopPlayback(resetSelection: true)
            return
        }

        if hasLoadedAudio(for: track.fileURL), let player {
            player.numberOfLoops = isLooping ? -1 : 0
            player.volume = Float(volume)
            if player.isPlaying {
                isPlaying = true
                isPaused = false
                return
            }

            player.play()
            isPlaying = true
            isPaused = false
            AudioMixerLibraryService.shared.markPlayed(trackID: track.id)
            return
        }

        stopPlayback(resetSelection: false)

        do {
            let player = try AVAudioPlayer(contentsOf: track.fileURL)
            player.delegate = self
            player.numberOfLoops = isLooping ? -1 : 0
            player.volume = Float(volume)
            player.prepareToPlay()
            self.player = player
            player.play()
            isPlaying = true
            isPaused = false
            AudioMixerLibraryService.shared.markPlayed(trackID: track.id)
        } catch {
            alertMessage = AudioMixerLibraryError.invalidAudioFile.localizedDescription
            stopPlayback(resetSelection: true)
        }
    }

    func pause() {
        cancelPendingReaderStop()
        guard let player, player.isPlaying else { return }
        player.pause()
        isPlaying = false
        isPaused = true
    }

    func resume() {
        cancelPendingReaderStop()
        guard let player, isPaused else { return }
        player.numberOfLoops = isLooping ? -1 : 0
        player.volume = Float(volume)
        player.play()
        isPlaying = true
        isPaused = false
        if let selectedTrackID {
            AudioMixerLibraryService.shared.markPlayed(trackID: selectedTrackID)
        }
    }

    func stopPlayback(resetSelection: Bool) {
        cancelPendingReaderStop()
        player?.stop()
        player = nil
        isPlaying = false
        isPaused = false

        if resetSelection {
            selectedTrackID = nil
            selectedTrackTitle = ""
            UserDefaults.standard.removeObject(forKey: Self.selectedTrackIDStorageKey)
        }
    }

    func clearSelectionIfNeeded(for track: AudioMixerTrack) {
        guard selectedTrackID == track.id else { return }
        stopPlayback(resetSelection: true)
    }

    func syncReaderPlaybackState(_ state: AudioMixerReaderPlaybackState) {
        guard followsReaderPlayback else { return }
        guard let selectedTrackID,
              let track = AudioMixerLibraryService.shared.track(for: selectedTrackID) else {
            return
        }

        switch state {
        case .playing:
            endReaderPlaybackTransition()
            cancelPendingReaderStop()
            if isPaused {
                resume()
            } else if !isPlaying {
                play(track: track)
            }
        case .paused:
            endReaderPlaybackTransition()
            cancelPendingReaderStop()
            if isPlaying {
                pause()
            }
        case .stopped:
            guard !isReaderTransitioning else { return }
            guard isPlaying || isPaused else {
                return
            }
            scheduleReaderStop()
        }
    }

    func stopIfTrackRemoved(_ track: AudioMixerTrack) {
        guard selectedTrackID == track.id else { return }
        stopPlayback(resetSelection: true)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if flag {
            isPlaying = false
            isPaused = false
            self.player = nil
        } else {
            alertMessage = "The audio track ended unexpectedly."
            stopPlayback(resetSelection: false)
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        if let error {
            alertMessage = error.localizedDescription
        } else {
            alertMessage = AudioMixerLibraryError.invalidAudioFile.localizedDescription
        }
        stopPlayback(resetSelection: true)
    }

    private func hasLoadedAudio(for fileURL: URL) -> Bool {
        guard let player else { return false }
        return player.url?.standardizedFileURL.path == fileURL.standardizedFileURL.path
    }

    private func scheduleReaderStop() {
        cancelPendingReaderStop()
        pendingReaderStopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, followsReaderPlayback else { return }
            stopPlayback(resetSelection: false)
        }
    }

    private func cancelPendingReaderStop() {
        pendingReaderStopTask?.cancel()
        pendingReaderStopTask = nil
    }

    func beginReaderPlaybackTransition() {
        isReaderTransitioning = true
        cancelPendingReaderStop()
    }

    func endReaderPlaybackTransition() {
        isReaderTransitioning = false
        cancelPendingReaderStop()
    }
}
