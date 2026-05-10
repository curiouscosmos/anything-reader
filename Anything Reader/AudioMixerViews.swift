//
//  AudioMixerViews.swift
//  Anything Reader
//
//  Sidebar destination and card UI for the background music library.
//

import AppKit
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct AudioMixerView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var libraryService: AudioMixerLibraryService
    @ObservedObject var playbackService: AudioMixerPlaybackService
    @Binding var searchText: String
    let preferredMode: AppearanceMode

    @State private var isShowingImporter = false
    @State private var importAlertMessage: String?
    @State private var importSuccessMessage: String?
    @State private var toastDismissTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            headerSection
            settingsSection
            trackGrid
        }
        .overlay(alignment: .top) {
            if let importSuccessMessage {
                Text(importSuccessMessage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.84), in: Capsule())
                    .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
                    .padding(.top, 14)
            }
        }
        .task {
            libraryService.loadIfNeeded(using: modelContext)
            libraryService.repairLibraryIfNeeded(using: modelContext)
        }
        .fileImporter(
            isPresented: $isShowingImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let sourceURL = urls.first else { return }
                do {
                    let importedTrack = try libraryService.importAudioFile(from: sourceURL)
                    showUploadSuccess(message: "\(importedTrack.title) added to Audio Mixer")
                } catch {
                    importAlertMessage = error.localizedDescription
                }
            case .failure(let error):
                importAlertMessage = error.localizedDescription
            }
        }
        .alert(
            "Audio Import Failed",
            isPresented: Binding(
                get: { importAlertMessage != nil },
                set: { if !$0 { importAlertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                importAlertMessage = nil
            }
        } message: {
            Text(importAlertMessage ?? "The audio file could not be imported.")
        }
        .onChange(of: importSuccessMessage) { _, newValue in
            toastDismissTask?.cancel()
            guard let newValue else { return }

            toastDismissTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                if importSuccessMessage == newValue {
                    importSuccessMessage = nil
                }
            }
        }
        .alert(
            "Audio Playback Failed",
            isPresented: Binding(
                get: { playbackService.alertMessage != nil },
                set: { if !$0 { playbackService.alertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                playbackService.alertMessage = nil
            }
        } message: {
            Text(playbackService.alertMessage ?? "The selected audio file could not be played.")
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Audio Mixer")
                .font(.system(size: 34, weight: .bold, design: .rounded))

            Text("Upload your own music or use the bundled audio beds. Background audio can follow the reader, loop continuously, and stay low in the mix.")
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 860, alignment: .leading)

            if let selectedTrack = libraryService.track(for: playbackService.selectedTrackID ?? "") {
                Text("Selected track: \(selectedTrack.title)")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Playback Settings")
                .font(.title2.weight(.bold))

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Background Music Volume")
                        .font(.headline)
                    Spacer(minLength: 2)
                    ReaderVolumeControlView(
                        volume: Binding(
                            get: { playbackService.volume },
                            set: { playbackService.setVolume($0) }
                        ),
                        preferredMode: preferredMode
                    )
                }
                
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Toggle("Play with Reader", isOn: Binding(
                        get: { playbackService.followsReaderPlayback },
                        set: { playbackService.setFollowsReaderPlayback($0) }
                    ))
                    .toggleStyle(.switch)
                    .readerPointerCursor()

                    Toggle("Loop Track", isOn: Binding(
                        get: { playbackService.isLooping },
                        set: { playbackService.setLooping($0) }
                    ))
                    .toggleStyle(.switch)
                    .readerPointerCursor()
                }
            }
            .frame(maxWidth: 500)
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var uploadSection: some View {
        Button {
            isShowingImporter = true
        } label: {
            Label("Upload Audio", systemImage: "square.and.arrow.up.fill")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    ReaderStyle.accentColor(named: "green")
                )
                .foregroundStyle(.white)
                .clipShape(
                    RoundedRectangle(cornerRadius: 16)
                )
        }
        .buttonStyle(ReaderPointerCursorButtonStyle())
    }

    @ViewBuilder
    private var trackGrid: some View {
        let visibleTracks = filteredTracks

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Library")
                        .font(.title2.weight(.bold))
                }
                Spacer()
                uploadSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if visibleTracks.isEmpty {
                emptyStateCard
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 16)], spacing: 16) {
                    ForEach(visibleTracks) { track in
                        AudioMixerTrackCardView(
                            track: track,
                            preferredMode: preferredMode,
                            isSelected: playbackService.isSelected(track),
                            isPlaying: playbackService.isPlayingTrack(track),
                            canDelete: !track.isBundled,
                            onPlayPause: {
                                playbackService.togglePlayback(for: track)
                            },
                            onDelete: {
                                do {
                                    playbackService.stopIfTrackRemoved(track)
                                    try libraryService.delete(track)
                                } catch {
                                    importAlertMessage = error.localizedDescription
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    private var filteredTracks: [AudioMixerTrack] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            return libraryService.tracks
        }

        return libraryService.tracks.filter { track in
            track.title.lowercased().contains(query)
        }
    }

    private var emptyStateText: String {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Use Upload Audio to add your own music, or play one of the bundled tracks."
        } else {
            return "No tracks matched your search."
        }
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No audio tracks yet")
                .font(.headline)
            Text("Upload an audio file to add it to the mixer library.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(panelBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var panelBackground: Color {
        preferredMode == .light ? Color.black.opacity(0.04) : Color.white.opacity(0.06)
    }

    private func showUploadSuccess(message: String) {
        importSuccessMessage = message
        playUploadTone()
    }

    private func playUploadTone() {
        if let sound = NSSound(named: NSSound.Name("Glass")) {
            sound.play()
        } else {
            NSSound.beep()
        }
    }
}

struct AudioMixerTrackCardView: View {
    let track: AudioMixerTrack
    let preferredMode: AppearanceMode
    let isSelected: Bool
    let isPlaying: Bool
    let canDelete: Bool
    let onPlayPause: () -> Void
    let onDelete: () -> Void

    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            backgroundLayer
            contentLayer
            deleteButton
        }
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: .black.opacity(preferredMode == .light ? 0.10 : 0.24), radius: 16, y: 8)
        .confirmationDialog(
            "Delete \"\(track.title)\"?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDelete()
            }

            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove the uploaded audio file from the local mixer library.")
        }
    }

    private var backgroundLayer: some View {
        LinearGradient(
            colors: gradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var contentLayer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))

                Spacer()

                if track.isBundled {
                    Label("Bundled", systemImage: "lock.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.14), in: Capsule())
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 0) {
                Text(track.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(isPlaying ? "Playing now" : (isSelected ? "Ready to play" : "Tap play to preview"))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
            }
            
            playButton
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var playButton: some View {
        VStack {
            Spacer()
            HStack {
                Button(action: onPlayPause) {
                    Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color.white, in: Capsule())
                }
                .buttonStyle(ReaderPointerCursorButtonStyle())

                Spacer()
            }
        }
    }

    private var deleteButton: some View {
        HStack {
            Spacer()
            Button {
                if canDelete {
                    isShowingDeleteConfirmation = true
                }
            } label: {
                Image(systemName: canDelete ? "trash.fill" : "lock.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(canDelete ? 0.14 : 0.08), in: Circle())
            }
            .buttonStyle(ReaderPointerCursorButtonStyle())
            .disabled(!canDelete)
            .opacity(canDelete ? 1 : 0)
        }
        .padding(14)
    }

    private var gradientColors: [Color] {
        if isPlaying {
            return [Color(red: 0.12, green: 0.55, blue: 0.36), Color(red: 0.08, green: 0.27, blue: 0.22)]
        }

        if isSelected {
            return [Color(red: 0.13, green: 0.33, blue: 0.47), Color(red: 0.11, green: 0.19, blue: 0.28)]
        }

        if track.isBundled {
            return [Color(red: 0.28, green: 0.18, blue: 0.42), Color(red: 0.12, green: 0.10, blue: 0.18)]
        }

        return [Color(red: 0.11, green: 0.21, blue: 0.33), Color(red: 0.08, green: 0.13, blue: 0.22)]
    }

    private var borderColor: Color {
        if isPlaying {
            return Color.green.opacity(0.95)
        }

        if isSelected {
            return Color.white.opacity(0.80)
        }

        return Color.white.opacity(preferredMode == .light ? 0.24 : 0.34)
    }
}
