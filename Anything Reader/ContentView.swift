//
//  ContentView.swift
//  Anything Reader
//
//  Main orchestration view for the reader shell.
//

import Foundation
import AppKit
import SwiftData
import SwiftUI
import Translation
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\LibraryEntry.lastOpened, order: .reverse)])
    private var libraryEntries: [LibraryEntry]

    @Query(sort: [SortDescriptor(\ReaderCategory.createdAt, order: .forward)])
    private var categories: [ReaderCategory]

    @AppStorage("appearanceMode") private var appearanceModeRawValue: String = AppearanceMode.system.rawValue
    @AppStorage("kokoroVoiceName") private var kokoroVoiceName: String = KokoroVoiceCatalog.defaultVoiceName

    @State private var selection: SidebarSelection = .home
    @State private var searchText = ""
    @State private var isShowingPasteSheet = false
    @State private var isShowingSettings = false
    @State private var isShowingKokoroDownloadModal = false
    @State private var isShowingCategorySheet = false
    @State private var isShowingFileImporter = false
    @State private var isShowingImportLanguageSheet = false
    @State private var audioGenerationSheetEntry: LibraryEntry?
    @State private var pendingAudioDeletionEntry: LibraryEntry?
    @State private var newCategoryName = ""
    @State private var pastedTitle = ""
    @State private var pastedText = ""
    @State private var uploadAlertMessage: String?
    @State private var importFailureMessage: String?
    @State private var processingImportMessage = ""
    @State private var successToastMessage: String?
    @State private var isProcessingImport = false
    @State private var pendingImportContext: PendingImportContext?
    @State private var pendingImportEntry: LibraryEntry?
    @State private var pendingAudioGenerationEntry: LibraryEntry?
    @State private var detectedDocumentLanguage: TextLanguage = .english
    @State private var pendingDocumentLanguage: TextLanguage = .english
    @State private var pendingAudioVoiceName: String = KokoroVoiceCatalog.defaultVoiceName
    @State private var audioGenerationProgressValue: Double?
    @State private var isTranslateDocument = false
    @State private var translateToLanguage: TextLanguage = .english
    @State private var importAwakeAssertion: NSObjectProtocol?
    @State private var audioGenerationAwakeAssertion: NSObjectProtocol?
    @State private var playbackState = PlaybackState()
    @State private var activeEntry: LibraryEntry?
    @State private var viewerEntry: LibraryEntry?
    @State private var viewerAlertMessage: String?
    @State private var playbackTask: Task<Void, Never>?
    @State private var playbackWarmupTask: Task<Void, Never>?
    @State private var readingNavigationTask: Task<Void, Never>?
    @State private var audioGenerationTask: Task<Void, Never>?
    @State private var audioGenerationPrewarmTask: Task<Void, Never>?
    @State private var playbackChunks: [String] = []
    @State private var playbackChunkIndex: Int = 0
    @State private var playbackSessionToken = UUID()
    @State private var toastDismissTask: Task<Void, Never>?
    @State private var didCleanupGeneratedContent = false
    @State private var coverArtGenerationKeys: Set<String> = []
    @State private var didBackfillMissingCoverArt = false
    @State private var didPresentKokoroDownloadGate = false
    @State private var audioGenerationAlertMessage: String?
    @StateObject private var kokoroModelStore = KokoroModelStore.shared
    @StateObject private var kokoroSpeechService = KokoroSpeechService.shared
    @StateObject private var readerPlaybackService = ReaderPlaybackService.shared
    @State private var translationCoordinator = DocumentTranslationCoordinator()

    private enum ReadingNavigationDirection {
        case backward
        case forward
    }

    private enum IdleSleepAssertionKind {
        case importing
        case audio
    }

    private static let fallbackAvatars = [
        "waveform",
        "headphones",
        "books.vertical.fill",
        "music.note.list",
        "sparkles",
        "doc.text.image"
    ]

    private static let accentPalette = [
        "emerald",
        "teal",
        "gold",
        "violet",
        "rose",
        "sky"
    ]

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter
    }()

    private static let yearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter
    }()

    private var uploadAllowedContentTypes: [UTType] {
        [UTType.pdf, UTType.plainText, UTType.epub]
    }

    private struct PendingImportContext {
        let sourceURL: URL
        let stagedURL: URL
        let fileName: String
        let fileExtension: String
        let sourceKind: ReaderSourceKind
        var createdFileURLs: [URL]
    }

    var body: some View {
        ZStack {
            backgroundLayer

            NavigationSplitView {
                ReaderSidebarView(
                    categories: categories,
                    selection: $selection,
                    onAddCategory: { isShowingCategorySheet = true }
                )
            } detail: {
                detailContent
            }
            .navigationSplitViewStyle(.balanced)
        }
        .safeAreaInset(edge: .bottom) {
            if shouldShowPlayerBar {
                ReaderPlayerBarView(
                    playbackState: $playbackState,
                    volume: Binding(
                        get: { readerPlaybackService.volume },
                        set: { readerPlaybackService.setVolume($0) }
                    ),
                    preferredMode: preferredMode,
                    isLoadingFirstChunk: readerPlaybackService.isBufferingFirstChunk,
                    readingStructureKind: activeEntry?.readingStructureKind,
                    jumpTargets: activeEntry?.readingJumpTargets ?? [],
                    canRewind: canNavigateReadingTarget(.backward, in: activeEntry),
                    canFastForward: canNavigateReadingTarget(.forward, in: activeEntry),
                    onRewind: rewindPlayback,
                    onTogglePlayPause: togglePlayback,
                    onFastForward: fastForwardPlayback,
                    onJumpToTarget: jumpToReadingTarget
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .sheet(isPresented: $isShowingPasteSheet) {
            ReaderPasteTextSheet(
                title: $pastedTitle,
                text: $pastedText,
                onPlay: playPastedText
            )
        }
        .sheet(isPresented: $isShowingSettings) {
            ReaderSettingsSheet(
                appearanceModeRawValue: $appearanceModeRawValue,
                selectedVoiceName: $kokoroVoiceName,
                voiceOptions: KokoroVoiceCatalog.allVoices,
                isPlaying: kokoroSpeechService.isPlaying,
                onPlaySample: playKokoroVoiceSample
            )
        }
        .sheet(isPresented: $isShowingKokoroDownloadModal) {
            ReaderKokoroDownloadSheet(
                modelStore: kokoroModelStore,
                preferredMode: preferredMode,
                onDownload: downloadKokoroModel(option:),
                onClose: {
                    isShowingKokoroDownloadModal = false
                }
            )
        }
        .sheet(isPresented: $isShowingCategorySheet) {
            ReaderNewCategorySheet(
                categoryName: $newCategoryName,
                onCreate: createCategory
            )
        }
        .sheet(isPresented: $isShowingImportLanguageSheet) {
            ReaderImportLanguageSheet(
                documentLanguage: $pendingDocumentLanguage,
                isTranslateDocument: $isTranslateDocument,
                translateToLanguage: $translateToLanguage,
                detectedLanguage: detectedDocumentLanguage,
                onImport: confirmPendingImport,
                onCancel: discardPendingImport
            )
        }
        .sheet(item: $audioGenerationSheetEntry) { entry in
            ReaderGenerateAudioSheet(
                voiceName: $pendingAudioVoiceName,
                voiceOptions: KokoroVoiceCatalog.allVoices,
                onGenerate: {
                    confirmPendingAudioGeneration(for: entry)
                },
                onCancel: discardPendingAudioGeneration
            )
        }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: uploadAllowedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            handleImportedFileSelection(result)
        }
        .alert(
            "Upload Failed",
            isPresented: Binding(
                get: { uploadAlertMessage != nil },
                set: { if !$0 { uploadAlertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                uploadAlertMessage = nil
            }
        } message: {
            Text(uploadAlertMessage ?? "The selected file could not be imported.")
        }
        .alert(
            "Normalization Failed",
            isPresented: Binding(
                get: { importFailureMessage != nil },
                set: { if !$0 { importFailureMessage = nil } }
            )
        ) {
            Button("Retry") {
                retryPendingImport()
            }

            Button("Remove File", role: .destructive) {
                discardPendingImport()
            }
        } message: {
            Text(importFailureMessage ?? "The file could not be normalized.")
        }
        .alert(
            "Viewer Unavailable",
            isPresented: Binding(
                get: { viewerAlertMessage != nil },
                set: { if !$0 { viewerAlertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                viewerAlertMessage = nil
            }
        } message: {
            Text(viewerAlertMessage ?? "The normalized TXT file could not be opened.")
        }
        .confirmationDialog(
            "Delete audio file?",
            isPresented: Binding(
                get: { pendingAudioDeletionEntry != nil },
                set: { if !$0 { pendingAudioDeletionEntry = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete audio file", role: .destructive) {
                confirmAudioDeletion()
            }

            Button("Cancel", role: .cancel) {
                pendingAudioDeletionEntry = nil
            }
        } message: {
            Text("This will remove the generated audio export from the local library and delete the file from disk.")
        }
        .alert(
            "Audio Generation Failed",
            isPresented: Binding(
                get: { audioGenerationAlertMessage != nil },
                set: { if !$0 { audioGenerationAlertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                audioGenerationAlertMessage = nil
            }
        } message: {
            Text(audioGenerationAlertMessage ?? "The audio file could not be generated.")
        }
        .preferredColorScheme(preferredMode.colorScheme)
        .tint(.green)
        .overlay {
            if readerPlaybackService.isBufferingFirstChunk {
                ReaderPlaybackLoadingOverlayView(message: "Preparing first chunk")
            }
        }
        .overlay(alignment: .top) {
            if let successToastMessage {
                ReaderToastView(message: successToastMessage)
                    .padding(.top, 16)
            }
        }
        .overlay {
            DocumentTranslationHostView(coordinator: translationCoordinator)
        }
        .task {
            cleanupGeneratedDemoContentIfNeeded()
            backfillMissingCoverArtIfNeeded()
            validateSelectedKokoroVoice()
            kokoroModelStore.refreshInstallationStatus()
            promptForKokoroDownloadIfNeeded()
        }
        .onChange(of: kokoroModelStore.status) { _, newStatus in
            switch newStatus {
            case .installed:
                successToastMessage = "TTS model downloaded and ready"
                isShowingKokoroDownloadModal = false
            case .failed(let message):
                successToastMessage = "TTS model download failed: \(message)"
                isShowingKokoroDownloadModal = true
            default:
                break
            }
        }
        .onChange(of: kokoroVoiceName) { _, _ in
            restartPlaybackForSelectedVoiceIfNeeded()
        }
        .onChange(of: successToastMessage) { _, newMessage in
            toastDismissTask?.cancel()

            guard let newMessage else { return }

            let message = newMessage
            toastDismissTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if successToastMessage == message {
                    successToastMessage = nil
                }
            }
        }
    }

    // MARK: - Theme

    private var preferredMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRawValue) ?? .system
    }

    private var backgroundLayer: some View {
        Group {
            switch preferredMode {
            case .light:
                LinearGradient(
                    colors: [
                        Color(red: 0.97, green: 0.98, blue: 0.97),
                        Color(red: 0.93, green: 0.95, blue: 0.94),
                        Color(red: 0.88, green: 0.91, blue: 0.89)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .dark, .system:
                LinearGradient(
                    colors: [
                        Color(red: 0.07, green: 0.09, blue: 0.08),
                        Color(red: 0.05, green: 0.05, blue: 0.06),
                        Color.black
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .ignoresSafeArea()
    }

    private func validateSelectedKokoroVoice() {
        let availableNames = Set(KokoroVoiceCatalog.allVoices.map(\.voiceName))
        if !availableNames.contains(kokoroVoiceName) {
            kokoroVoiceName = KokoroVoiceCatalog.defaultVoiceName
        }
    }

    private var shouldShowPlayerBar: Bool {
        activeEntry != nil && !readerPlaybackService.isBufferingFirstChunk
    }

    private func playKokoroVoiceSample(_ voice: KokoroVoiceOption) {
        kokoroSpeechService.prepareForPlayback()
        kokoroSpeechService.playSample(for: voice)
        successToastMessage = "Playing \(voice.displayName) sample"
    }

    @MainActor
    private func restartPlaybackForSelectedVoiceIfNeeded() {
        guard let entry = activeEntry else { return }
        guard playbackState.isPlaying || readerPlaybackService.isPlaying || readerPlaybackService.isBufferingFirstChunk else { return }

        readerPlaybackService.stop()
        stopPlaybackTask()
        stopPlaybackWarmupTask()
        cancelReadingNavigationTask()
        playbackState.isPlaying = true
        startPlayback(for: entry)
    }

    private func promptForKokoroDownloadIfNeeded() {
        guard !didPresentKokoroDownloadGate else { return }
        didPresentKokoroDownloadGate = true

        if !kokoroModelStore.isInstalled {
            isShowingKokoroDownloadModal = true
        }
    }

    private func openKokoroDownloadModal() {
        isShowingKokoroDownloadModal = true
    }

    private func downloadKokoroModel(option: KokoroDownloadOption) {
        switch kokoroModelStore.status {
        case .checking, .downloading:
            return
        case .installed:
            if !kokoroModelStore.isOptionDownloaded(option) {
                kokoroModelStore.downloadModel(option: option)
                successToastMessage = "Downloading \(option.displayName)"
            }
        case .notInstalled, .failed:
            kokoroModelStore.downloadModel(option: option)
            successToastMessage = "Downloading \(option.displayName)"
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        let entries = filteredEntries
        let sortedByDateAdded = entries.sorted { $0.createdAt > $1.createdAt }
        let sortedByRecentlyPlayed = entries.sorted { $0.lastOpened > $1.lastOpened }
        let isPresentingViewer = Binding(
            get: { viewerEntry != nil },
            set: { newValue in
                if !newValue {
                    viewerEntry = nil
                }
            }
        )

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ReaderTopBarView(
                        searchText: $searchText,
                        onHome: { selection = .home },
                        onPasteText: { isShowingPasteSheet = true },
                        onUploadFile: { isShowingFileImporter = true },
                        onSettings: { isShowingSettings = true },
                        tint: ReaderStyle.accentColor(named: "emerald"),
                        preferredMode: preferredMode,
                        isUploadDisabled: isImportInFlight
                    )

                    switch selection {
                    case .home:
                        ReaderHeroView(
                            featured: sortedByDateAdded.first,
                            preferredMode: preferredMode,
                            kokoroModelStatus: kokoroModelStore.status,
                            onPasteText: { isShowingPasteSheet = true },
                            onUploadFile: { isShowingFileImporter = true },
                            onOpenLibrary: { selection = .recent },
                            onDownloadKokoro: openKokoroDownloadModal,
                            isUploadDisabled: isImportInFlight
                        )

                        ReaderLibrarySectionView(
                            title: "Library",
                            subtitle: "Everything you have imported or pasted",
                            entries: sortedByDateAdded,
                            categories: categories,
                            coverArtGenerationKeys: coverArtGenerationKeys,
                            preferredMode: preferredMode,
                            isEntryPlaying: isEntryPlaying(_:),
                            isEntryGeneratingAudio: isEntryGeneratingAudio(_:),
                            audioGenerationProgressFraction: audioGenerationProgressFraction(for:),
                            onPrimaryAction: handlePrimaryCardAction(for:),
                            onPlay: { entry in startPlayback(for: entry) },
                            onView: openNormalizedTextViewer,
                            onRevealLocation: revealLibraryEntryLocation,
                            onGenerateAudio: openAudioGenerationSheet(for:),
                            onStopAudioGeneration: stopAudioGeneration(for:),
                            onDeleteAudio: openAudioDeletionConfirmation(for:),
                            onClearCategory: { assign($0, to: nil) },
                            onAssignCategory: { assign($0, to: $1) },
                            onDelete: deleteEntry
                        )

                    case .recent:
                        ReaderLibrarySectionView(
                            title: "Recently Played",
                            subtitle: "Your last opened books and pasted text",
                            entries: sortedByRecentlyPlayed,
                            categories: categories,
                            coverArtGenerationKeys: coverArtGenerationKeys,
                            preferredMode: preferredMode,
                            isEntryPlaying: isEntryPlaying(_:),
                            isEntryGeneratingAudio: isEntryGeneratingAudio(_:),
                            audioGenerationProgressFraction: audioGenerationProgressFraction(for:),
                            onPrimaryAction: handlePrimaryCardAction(for:),
                            onPlay: { entry in startPlayback(for: entry) },
                            onView: openNormalizedTextViewer,
                            onRevealLocation: revealLibraryEntryLocation,
                            onGenerateAudio: openAudioGenerationSheet(for:),
                            onStopAudioGeneration: stopAudioGeneration(for:),
                            onDeleteAudio: openAudioDeletionConfirmation(for:),
                            onClearCategory: { assign($0, to: nil) },
                            onAssignCategory: { assign($0, to: $1) },
                            onDelete: deleteEntry
                        )

                    case .category(let categoryName):
                        ReaderLibrarySectionView(
                            title: categoryName,
                            subtitle: "All books filed into this category",
                            entries: sortedByDateAdded,
                            categories: categories,
                            coverArtGenerationKeys: coverArtGenerationKeys,
                            preferredMode: preferredMode,
                            isEntryPlaying: isEntryPlaying(_:),
                            isEntryGeneratingAudio: isEntryGeneratingAudio(_:),
                            audioGenerationProgressFraction: audioGenerationProgressFraction(for:),
                            onPrimaryAction: handlePrimaryCardAction(for:),
                            onPlay: { entry in startPlayback(for: entry) },
                            onView: openNormalizedTextViewer,
                            onRevealLocation: revealLibraryEntryLocation,
                            onGenerateAudio: openAudioGenerationSheet(for:),
                            onStopAudioGeneration: stopAudioGeneration(for:),
                            onDeleteAudio: openAudioDeletionConfirmation(for:),
                            onClearCategory: { assign($0, to: nil) },
                            onAssignCategory: { assign($0, to: $1) },
                            onDelete: deleteEntry
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 110)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Anything Reader - Offline Text to Speech PDF")
            .navigationDestination(isPresented: isPresentingViewer) {
                if let viewerEntry {
                    NormalizedTextViewerScreen(
                        entry: viewerEntry,
                        preferredMode: preferredMode,
                        onRevealLocation: revealLibraryEntryLocation
                    )
                }
            }
        }
    }

    private var filteredEntries: [LibraryEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return libraryEntries.filter { entry in
            let matchesQuery: Bool
            if query.isEmpty {
                matchesQuery = true
            } else {
                matchesQuery = entry.title.lowercased().contains(query)
                    || entry.subtitle.lowercased().contains(query)
                    || (normalizedTextSnippet(for: entry)?.lowercased().contains(query) ?? false)
                    || entry.fileExtension.lowercased().contains(query)
                    || (entry.categoryName?.lowercased().contains(query) ?? false)
            }

            let matchesSelection: Bool
            switch selection {
            case .home, .recent:
                matchesSelection = true
            case .category(let categoryName):
                matchesSelection = entry.categoryName == categoryName
            }

            return matchesQuery && matchesSelection
        }
    }

    // MARK: - Cleanup

    private func cleanupGeneratedDemoContentIfNeeded() {
        guard !didCleanupGeneratedContent else { return }
        didCleanupGeneratedContent = true

        // Remove the placeholder content that was previously seeded into the library.
        let generatedCategoryNames: Set<String> = ["Focus", "Commute", "Research"]
        let generatedTitles: Set<String> = [
            "Designing Audio Products",
            "Morning Brief",
            "Paste Text Draft"
        ]
        let generatedSubtitles: Set<String> = [
            "A short PDF ready for replay.",
            "An imported ePub document.",
            "Saved text record for later playback."
        ]

        let entriesToDelete = libraryEntries.filter { entry in
            generatedTitles.contains(entry.title)
                || generatedSubtitles.contains(entry.subtitle)
                || generatedCategoryNames.contains(entry.categoryName ?? "")
        }

        let categoriesToDelete = categories.filter { generatedCategoryNames.contains($0.name) }

        entriesToDelete.forEach { modelContext.delete($0) }
        categoriesToDelete.forEach { modelContext.delete($0) }

        if !entriesToDelete.isEmpty || !categoriesToDelete.isEmpty {
            try? modelContext.save()
        }
    }

    // MARK: - Category Management

    @MainActor
    private func createCategory() {
        let trimmedName = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let category = ReaderCategory(
            name: trimmedName,
            accentName: Self.accentPalette.randomElement() ?? "emerald"
        )
        modelContext.insert(category)
        try? modelContext.save()

        selection = .category(trimmedName)
        newCategoryName = ""
        isShowingCategorySheet = false
    }

    @MainActor
    private func assign(_ entry: LibraryEntry, to categoryName: String?) {
        entry.categoryName = categoryName
        entry.lastOpened = .now
        try? modelContext.save()
    }

    // MARK: - Deletion

    @MainActor
    private func deleteEntry(_ entry: LibraryEntry) {
        if activeEntry?.persistentModelID == entry.persistentModelID {
            readerPlaybackService.stop()
            activeEntry = nil
            playbackState = PlaybackState()
            playbackChunks = []
            playbackChunkIndex = 0
        }

        if viewerEntry?.persistentModelID == entry.persistentModelID {
            viewerEntry = nil
        }

        removeAssociatedFiles(for: entry)

        Task {
            await PhonemeCacheService.shared.removeCache(for: entry)
        }

        modelContext.delete(entry)
        try? modelContext.save()
    }

    // MARK: - File Viewing

    private func openNormalizedTextViewer(_ entry: LibraryEntry) {
        guard let storedPath = entry.normalizedTextFilePath else {
            viewerAlertMessage = "This item does not have a normalized TXT file."
            return
        }

        let fileURL = URL(fileURLWithPath: storedPath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            viewerAlertMessage = "The normalized TXT file could not be found on disk."
            return
        }

        entry.lastOpened = .now
        try? modelContext.save()
        viewerEntry = entry
    }

    private func normalizedTextSnippet(for entry: LibraryEntry) -> String? {
        ReaderPlaybackChunkService.normalizedText(for: entry)
    }

    private func revealLibraryEntryLocation(_ entry: LibraryEntry) {
        guard let storedPath = entry.storedFilePath else {
            uploadAlertMessage = "This item does not have a saved file location."
            return
        }

        let fileURL = URL(fileURLWithPath: storedPath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            uploadAlertMessage = "The saved file could not be found on disk."
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    private func removeAssociatedFiles(for entry: LibraryEntry) {
        let fileManager = FileManager.default
        [entry.storedFilePath, entry.normalizedTextFilePath, entry.coverImageFilePath].compactMap { $0 }.forEach { path in
            let fileURL = URL(fileURLWithPath: path)
            if fileManager.fileExists(atPath: fileURL.path) {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }

    // MARK: - Paste Text

    @MainActor
    private func playPastedText() {
        let trimmedText = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        let trimmedTitle = pastedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = trimmedTitle.isEmpty ? generatedPastedTitle() : trimmedTitle
        let fileName = resolvedTitle.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")

        let detectedLanguage = TextNormalizationService.detectLanguage(for: trimmedText)
        let normalizedText = TextNormalizationService.normalize(trimmedText, language: detectedLanguage)
        guard !normalizedText.isEmpty else {
            uploadAlertMessage = "The pasted text could not be normalized."
            return
        }

        let textData = Data(normalizedText.utf8)
        guard let storedURL = try? storeTextFile(contents: textData, fileName: fileName) else {
            uploadAlertMessage = "The pasted text could not be saved to disk."
            return
        }
        let pastedEntry = LibraryEntry(
            title: resolvedTitle,
            subtitle: "Pasted text saved locally for later.",
            sourceKind: .pastedText,
            fileExtension: "txt",
            originalFileName: "\(fileName).txt",
            storedFilePath: storedURL.path,
            normalizedTextFilePath: storedURL.path,
            coverImageFilePath: nil,
            fileSizeBytes: Int64(textData.count),
            categoryName: nil,
            avatarSymbolName: Self.fallbackAvatars.randomElement() ?? "waveform",
            accentName: Self.accentPalette.randomElement() ?? "emerald",
            phonemeText: nil,
            phonemeUpdatedAt: nil,
            textLanguage: detectedLanguage,
            progress: 0.04,
            lastOpened: .now
        )

        modelContext.insert(pastedEntry)
        try? modelContext.save()

        pastedTitle = ""
        pastedText = ""
        isShowingPasteSheet = false
        startPlayback(for: pastedEntry)
    }

    private func generatedPastedTitle() -> String {
        let now = Date()
        let calendar = Calendar.current
        let noteNumber = libraryEntries.filter { entry in
            entry.sourceKind == .pastedText && calendar.isDate(entry.createdAt, inSameDayAs: now)
        }.count + 1

        return "Note: #\(noteNumber)"
    }

    // MARK: - File Uploads

    @MainActor
    private func handleImportedFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let sourceURLs):
            guard let sourceURL = sourceURLs.first else {
                uploadAlertMessage = "No file was selected."
                return
            }
            Task { await preparePendingImport(from: sourceURL) }
        case .failure(let error):
            uploadAlertMessage = error.localizedDescription
        }
    }

    @MainActor
    private func preparePendingImport(from sourceURL: URL) async {
        do {
            let stagedURL = try stageImportedFile(from: sourceURL)
            let fileExtension = stagedURL.pathExtension.lowercased()
            let detectedLanguage = DocumentIngestService.detectLanguage(
                for: stagedURL,
                fileExtension: fileExtension
            )

            detectedDocumentLanguage = detectedLanguage
            pendingDocumentLanguage = detectedLanguage
            pendingImportContext = PendingImportContext(
                sourceURL: sourceURL,
                stagedURL: stagedURL,
                fileName: sourceURL.lastPathComponent,
                fileExtension: fileExtension,
                sourceKind: readerSourceKind(for: fileExtension),
                createdFileURLs: [stagedURL]
            )
            isTranslateDocument = false
            translateToLanguage = .english
            isProcessingImport = true
            processingImportMessage = "Preparing import options…"
            isProcessingImport = false
            isShowingImportLanguageSheet = true
        } catch {
            uploadAlertMessage = error.localizedDescription
            cleanupPendingImportArtifacts()
        }
    }

    @MainActor
    private func confirmPendingImport() {
        guard pendingImportContext != nil else { return }
        isShowingImportLanguageSheet = false
        isProcessingImport = true
        processingImportMessage = "Normalizing \(pendingImportContext?.fileName ?? "file")…"
        beginIdleSleepAssertion(for: .importing)
        createPendingImportEntry()

        let selectedLanguage = pendingDocumentLanguage
        Task {
            await processPendingImport(documentLanguage: selectedLanguage)
        }
    }

    @MainActor
    private func processPendingImport(documentLanguage: TextLanguage) async {
        guard let context = pendingImportContext else { return }
        guard let placeholderEntry = pendingImportEntry else { return }
        defer {
            endIdleSleepAssertion(for: .importing)
        }

        do {
            let draft = try await DocumentIngestService.shared.extractDraft(
                stagedFileURL: context.stagedURL,
                fileExtension: context.fileExtension,
                documentLanguage: documentLanguage
            )

            await MainActor.run {
                processingImportMessage = isTranslateDocument
                    ? "Checking translation support…"
                    : "Normalizing \(context.fileName)…"
            }

            let shouldTranslate = await MainActor.run(body: { isTranslateDocument })
            let finalText: String
            let normalizedLanguage: TextLanguage

            if shouldTranslate {
                let targetLanguage = await MainActor.run(body: { translateToLanguage })
                guard let translationSourceLanguage = draft.detectedLanguage.localeLanguage,
                      let translationTargetLanguage = targetLanguage.localeLanguage else {
                    throw DocumentTranslationError.missingLanguage
                }

                let availability = LanguageAvailability(preferredStrategy: .lowLatency)
                let status = await availability.status(
                    from: translationSourceLanguage,
                    to: translationTargetLanguage
                )

                switch status {
                case .installed, .supported:
                    await MainActor.run {
                        processingImportMessage = "Translating \(context.fileName)…"
                    }
                case .unsupported:
                    throw DocumentTranslationError.unsupported(
                        source: draft.detectedLanguage,
                        target: targetLanguage
                    )
                @unknown default:
                    throw DocumentTranslationError.unsupported(
                        source: draft.detectedLanguage,
                        target: targetLanguage
                    )
                }

                finalText = try await translationCoordinator.translate(
                    sourceText: draft.rawText,
                    sourceLanguage: draft.detectedLanguage,
                    targetLanguage: targetLanguage
                )
                normalizedLanguage = targetLanguage
            } else {
                finalText = draft.rawText
                normalizedLanguage = draft.detectedLanguage
            }

            let ingest = try await DocumentIngestService.shared.finalize(
                draft: draft,
                sourceText: finalText,
                normalizedLanguage: normalizedLanguage,
                originalFileName: context.fileName,
                sourceURL: context.stagedURL
            )

            await MainActor.run {
                pendingImportContext?.createdFileURLs.append(ingest.normalizedTextFileURL)
                processingImportMessage = "Saving \(context.fileName)…"
            }

            placeholderEntry.title = ingest.title ?? sanitizedTitle(from: context.sourceURL.deletingPathExtension().lastPathComponent)
            placeholderEntry.subtitle = ""
            placeholderEntry.sourceKindRawValue = ingest.sourceKind.rawValue
            placeholderEntry.fileExtension = context.fileExtension
            placeholderEntry.originalFileName = context.fileName
            placeholderEntry.storedFilePath = context.stagedURL.path
            placeholderEntry.normalizedTextFilePath = ingest.normalizedTextFileURL.path
            placeholderEntry.coverImageFilePath = nil
            placeholderEntry.fileSizeBytes = ingest.fileSizeBytes
            placeholderEntry.categoryName = nil
            placeholderEntry.avatarSymbolName = avatarSymbol(for: ingest.sourceKind)
            placeholderEntry.accentName = placeholderEntry.accentName.isEmpty ? (Self.accentPalette.randomElement() ?? "emerald") : placeholderEntry.accentName
            placeholderEntry.phonemeText = nil
            placeholderEntry.phonemeUpdatedAt = nil
            placeholderEntry.textLanguage = ingest.textLanguage
            placeholderEntry.pdfExtractionMode = ingest.pdfExtractionMode
            placeholderEntry.readingStructureKind = ingest.readingStructureKind
            placeholderEntry.pageCount = ingest.pageCount
            placeholderEntry.chapterCount = ingest.chapterCount
            placeholderEntry.sectionCount = ingest.sectionCount > 0 ? ingest.sectionCount : nil
            placeholderEntry.readingJumpTargets = ingest.readingJumpTargets
            placeholderEntry.progress = 0
            placeholderEntry.lastOpened = .now
            placeholderEntry.importState = .ready
            try modelContext.save()

            await MainActor.run {
                clearPendingImportState(showing: "\(placeholderEntry.title) is ready to play.")
                queueCoverArtGenerationIfNeeded(for: placeholderEntry)
            }
        } catch {
            if error is CancellationError {
                await MainActor.run {
                    if let pendingImportEntry {
                        modelContext.delete(pendingImportEntry)
                        try? modelContext.save()
                    }
                    isProcessingImport = false
                    pendingImportEntry = nil
                }
                return
            }

            await MainActor.run {
                isProcessingImport = false
                if let pendingImportEntry {
                    modelContext.delete(pendingImportEntry)
                    try? modelContext.save()
                }
                importFailureMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func retryPendingImport() {
        guard pendingImportContext != nil else { return }
        importFailureMessage = nil
        isProcessingImport = true
        processingImportMessage = "Retrying normalization…"
        beginIdleSleepAssertion(for: .importing)
        createPendingImportEntry()
        Task { await processPendingImport(documentLanguage: pendingDocumentLanguage) }
    }

    @MainActor
    private func discardPendingImport() {
        cleanupPendingImportArtifacts()
        clearPendingImportState(showing: nil)
    }

    @MainActor
    private func cleanupPendingImportArtifacts() {
        guard let context = pendingImportContext else { return }
        let fileManager = FileManager.default
        context.createdFileURLs.forEach { url in
            if fileManager.fileExists(atPath: url.path) {
                try? fileManager.removeItem(at: url)
            }
        }
        translationCoordinator.cancel()
        if let pendingImportEntry {
            modelContext.delete(pendingImportEntry)
            try? modelContext.save()
        }
        pendingImportEntry = nil
        pendingImportContext = nil
        detectedDocumentLanguage = .english
        pendingDocumentLanguage = .english
        isShowingImportLanguageSheet = false
        isProcessingImport = false
        processingImportMessage = ""
    }

    @MainActor
    private func clearPendingImportState(showing message: String?) {
        isProcessingImport = false
        processingImportMessage = ""
        pendingImportContext = nil
        pendingImportEntry = nil
        translationCoordinator.cancel()
        endIdleSleepAssertion(for: .importing)
        detectedDocumentLanguage = .english
        pendingDocumentLanguage = .english
        isShowingImportLanguageSheet = false
        isTranslateDocument = false
        translateToLanguage = .english

        if let message {
            successToastMessage = message
            playSuccessTone()
        } else {
            successToastMessage = nil
        }
    }

    private var isImportInFlight: Bool {
        isProcessingImport || pendingImportContext != nil
    }

    @MainActor
    private func createPendingImportEntry() {
        guard let context = pendingImportContext, pendingImportEntry == nil else { return }

        let placeholder = LibraryEntry(
            title: sanitizedTitle(from: context.sourceURL.deletingPathExtension().lastPathComponent),
            subtitle: "Importing…",
            sourceKind: context.sourceKind,
            fileExtension: context.fileExtension,
            originalFileName: context.fileName,
            storedFilePath: context.stagedURL.path,
            normalizedTextFilePath: nil,
            coverImageFilePath: nil,
            fileSizeBytes: 0,
            categoryName: nil,
            avatarSymbolName: avatarSymbol(for: context.sourceKind),
            accentName: Self.accentPalette.randomElement() ?? "emerald",
            phonemeText: nil,
            phonemeUpdatedAt: nil,
            textLanguage: pendingDocumentLanguage,
            pdfExtractionMode: nil,
            readingStructureKind: nil,
            pageCount: 0,
            chapterCount: 0,
            sectionCount: 0,
            importState: .importing,
            readingJumpTargets: [],
            progress: 0,
            lastOpened: .now
        )

        modelContext.insert(placeholder)
        try? modelContext.save()
        pendingImportEntry = placeholder
    }

    private func stageImportedFile(from sourceURL: URL) throws -> URL {
        guard sourceURL.isFileURL else {
            throw UploadError.invalidFile
        }

        let extensionName = sourceURL.pathExtension.lowercased()
        guard ["pdf", "txt", "epub"].contains(extensionName) else {
            throw UploadError.unsupportedFileType
        }

        let fileManager = FileManager.default
        let didAccessSecurityScope = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScope {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw UploadError.invalidFile
        }

        let directoryURL = try uploadedFilesDirectory()
        let baseName = sanitizedImportedFileBaseName(from: sourceURL)
        let destinationURL = directoryURL.appendingPathComponent("\(baseName).\(extensionName)")

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    private func sanitizedImportedFileBaseName(from sourceURL: URL) -> String {
        let fileStem = sourceURL.deletingPathExtension().lastPathComponent
        let sanitizedStem = fileStem
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let timestamp = Self.importTimestampFormatter.string(from: .now)
        return "\(sanitizedStem)_\(timestamp)"
    }

    private static let importTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd_HHmmssSSS"
        return formatter
    }()

    @MainActor
    private func applyPhonemeCache(_ phonemeText: String, to entry: LibraryEntry) {
        entry.phonemeText = phonemeText
        entry.phonemeUpdatedAt = .now
        try? modelContext.save()
    }

    @MainActor
    private func queueCoverArtGenerationIfNeeded(for entry: LibraryEntry) {
        guard entry.coverImageFilePath == nil else { return }
        guard entry.sourceKind == .pdf || entry.sourceKind == .epub else { return }

        let cacheKey = entry.cacheIdentity
        guard !coverArtGenerationKeys.contains(cacheKey) else { return }

        coverArtGenerationKeys.insert(cacheKey)

        Task(priority: .utility) {
            guard let storedPath = entry.storedFilePath else {
                _ = await MainActor.run {
                    self.coverArtGenerationKeys.remove(cacheKey)
                }
                return
            }

            let sourceURL = URL(fileURLWithPath: storedPath)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                _ = await MainActor.run {
                    self.coverArtGenerationKeys.remove(cacheKey)
                }
                return
            }

            let imageURL = await CoverArtService.shared.generateCoverImageURL(
                sourceURL: sourceURL,
                fileExtension: entry.fileExtension,
                originalFileName: entry.originalFileName ?? entry.title
            )

            guard let imageURL else {
                _ = await MainActor.run {
                    self.coverArtGenerationKeys.remove(cacheKey)
                }
                return
            }

            _ = await MainActor.run {
                entry.coverImageFilePath = imageURL.path
                try? modelContext.save()
                self.coverArtGenerationKeys.remove(cacheKey)
            }
        }
    }

    @MainActor
    private func backfillMissingCoverArtIfNeeded() {
        guard !didBackfillMissingCoverArt else { return }
        didBackfillMissingCoverArt = true

        for entry in libraryEntries where entry.coverImageFilePath == nil {
            queueCoverArtGenerationIfNeeded(for: entry)
        }
    }

    private func storeUploadedFile(sourceURL: URL, fileExtension: String, fileData: Data) throws -> URL {
        let fileManager = FileManager.default
        let directoryURL = try uploadedFilesDirectory()
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let destinationURL = directoryURL.appendingPathComponent("\(UUID().uuidString)-\(baseName).\(fileExtension)")

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        _ = fileManager.createFile(atPath: destinationURL.path, contents: fileData)
        return destinationURL
    }

    private func storeTextFile(contents: Data, fileName: String) throws -> URL {
        let fileManager = FileManager.default
        let directoryURL = try uploadedFilesDirectory()
        let destinationURL = directoryURL.appendingPathComponent("\(UUID().uuidString)-\(fileName).txt")

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        _ = fileManager.createFile(atPath: destinationURL.path, contents: contents)
        return destinationURL
    }

    private func uploadedFilesDirectory() throws -> URL {
        let fileManager = FileManager.default
        let supportDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let appDirectory = supportDirectory.appendingPathComponent("Anything Reader", isDirectory: true)
        let uploadsDirectory = appDirectory.appendingPathComponent("Uploaded Files", isDirectory: true)

        if !fileManager.fileExists(atPath: uploadsDirectory.path) {
            try fileManager.createDirectory(at: uploadsDirectory, withIntermediateDirectories: true)
        }

        return uploadsDirectory
    }

    private func readerSourceKind(for fileExtension: String) -> ReaderSourceKind {
        switch fileExtension.lowercased() {
        case "pdf":
            return .pdf
        case "epub":
            return .epub
        default:
            return .text
        }
    }

    private func avatarSymbol(for sourceKind: ReaderSourceKind) -> String {
        switch sourceKind {
        case .pdf:
            return "doc.richtext.fill"
        case .epub:
            return "book.fill"
        case .text, .pastedText:
            return "doc.text.fill"
        }
    }

    private func sanitizedTitle(from fileName: String) -> String {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Upload" : trimmed
    }

    private enum UploadError: LocalizedError {
        case invalidFile
        case unsupportedFileType

        var errorDescription: String? {
            switch self {
            case .invalidFile:
                return "The selected file is missing, empty, or unreadable."
            case .unsupportedFileType:
                return "Please choose a PDF, TXT, or ePub file."
            }
        }
    }

    // MARK: - Playback

    @MainActor
    private func startPlayback(for entry: LibraryEntry, readingPositionOverrideText: String? = nil) {
        playbackSessionToken = UUID()
        let sessionToken = playbackSessionToken
        let resumeProgress = playbackResumeProgress(for: entry)
        let resumeTargetIndex = entry.currentReadingPositionIndex ?? readingPositionIndex(for: entry, progress: resumeProgress)
        let startingChunkIndex = resumeTargetIndex.flatMap { ReaderPlaybackChunkService.chunkIndex(for: $0, in: entry) } ?? ReaderPlaybackChunkService.chunkIndex(for: resumeProgress, chunkCount: ReaderPlaybackChunkService.chunks(for: entry).count)

        readerPlaybackService.stop()
        stopPlaybackTask()
        stopPlaybackWarmupTask()

        // Store the active record so progress updates persist to SwiftData.
        activeEntry = entry
        entry.lastOpened = .now

        playbackChunks = ReaderPlaybackChunkService.chunks(for: entry)
        playbackChunkIndex = startingChunkIndex

        let normalizedText = normalizedTextSnippet(for: entry) ?? ""
        let duration = max(600, min(10800, normalizedText.isEmpty ? 1800 : max(600, normalizedText.count / 12)))
        let elapsedSeconds = Int((Double(duration) * resumeProgress).rounded())

        playbackState = PlaybackState(
            title: entry.title,
            subtitle: entry.subtitle,
            readingPositionText: entry.currentReadingPositionDisplayText ?? readingPositionText(for: entry, progress: resumeProgress),
            readingPositionOverrideText: nil,
            readingPositionIndexOverride: entry.currentReadingPositionIndex ?? readingPositionIndex(for: entry, progress: resumeProgress),
            readingPositionTotalCount: entry.currentReadingPositionTotalCount ?? (entry.readingJumpTargets.isEmpty ? nil : entry.readingJumpTargets.count),
            avatarSymbol: entry.avatarSymbolName,
            accentName: entry.accentName,
            progress: resumeProgress,
            durationSeconds: duration,
            elapsedSeconds: elapsedSeconds,
            isPlaying: true
        )

        entry.progress = resumeProgress

        try? modelContext.save()

        let voice = KokoroVoiceCatalog.voice(named: kokoroVoiceName)
        readerPlaybackService.play(
            entry: entry,
            voice: voice,
            startingProgress: resumeProgress,
            startingChunkIndex: startingChunkIndex,
            onProgress: { update in
                guard self.playbackSessionToken == sessionToken else { return }
                self.applyPlaybackUpdate(update, to: entry)
            },
            onFinished: {
                guard self.playbackSessionToken == sessionToken else { return }
                self.playbackState.progress = 0
                self.playbackState.elapsedSeconds = 0
                self.playbackState.isPlaying = false
                entry.progress = 0
                try? self.modelContext.save()
                self.persistPlayerProgress()
            },
            onFailure: { message in
                guard self.playbackSessionToken == sessionToken else { return }
                self.playbackState.isPlaying = false
                self.uploadAlertMessage = message
            }
        )
    }

    @MainActor
    private func togglePlayback() {
        if playbackState.isPlaying {
            playbackState.isPlaying = false
            readerPlaybackService.stop()
            stopPlaybackTask()
            stopPlaybackWarmupTask()
            cancelReadingNavigationTask()
        } else {
            if let entry = activeEntry {
                startPlayback(for: entry)
            } else {
                playbackState.isPlaying = false
            }
        }

        persistPlayerProgress()
    }

    @MainActor
    private func rewindPlayback() {
        scheduleReadingTargetNavigation(.backward)
    }

    @MainActor
    private func fastForwardPlayback() {
        scheduleReadingTargetNavigation(.forward)
    }

    @MainActor
    private func jumpToReadingTarget(_ target: ReaderJumpTarget) {
        guard let entry = activeEntry else { return }

        let newProgress = readingProgress(for: target, in: entry)
        let explicitReadingPositionText = readingPositionText(for: entry, targetIndex: target.index)
        entry.progress = newProgress
        entry.currentReadingPositionIndex = target.index
        entry.currentReadingPositionTotalCount = entry.readingJumpTargets.isEmpty ? nil : entry.readingJumpTargets.count
        playbackState.progress = newProgress
        playbackState.elapsedSeconds = Int((Double(playbackState.durationSeconds) * newProgress).rounded())
        playbackState.readingPositionText = explicitReadingPositionText
        playbackState.readingPositionOverrideText = nil
        playbackState.readingPositionIndexOverride = target.index
        playbackState.readingPositionTotalCount = entry.readingJumpTargets.isEmpty ? nil : entry.readingJumpTargets.count
        entry.lastOpened = .now
        try? modelContext.save()
        startPlayback(for: entry)
    }

    @MainActor
    private func scheduleReadingTargetNavigation(_ direction: ReadingNavigationDirection) {
        guard let entry = activeEntry, canNavigateReadingTarget(direction, in: entry) else { return }

        cancelReadingNavigationTask()

        let entryID = entry.persistentModelID
        readingNavigationTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            guard let currentEntry = activeEntry, currentEntry.persistentModelID == entryID else { return }
            guard let target = adjacentReadingTarget(for: direction, in: currentEntry) else { return }

            jumpToReadingTarget(target)
        }
    }

    @MainActor
    private func persistPlayerProgress() {
        activeEntry?.progress = playbackState.progress
        if let activeEntry {
            syncReadingPositionState(for: activeEntry, progress: playbackState.progress)
        }
        activeEntry?.lastOpened = .now
        try? modelContext.save()
    }

    @MainActor
    private func stopPlaybackTask() {
        playbackTask?.cancel()
        playbackTask = nil
    }

    @MainActor
    private func stopPlaybackWarmupTask() {
        playbackWarmupTask?.cancel()
        playbackWarmupTask = nil
    }

    @MainActor
    private func applyPlaybackUpdate(_ update: ReaderPlaybackUpdate, to entry: LibraryEntry) {
        guard playbackState.isPlaying else { return }
        playbackState.elapsedSeconds = update.elapsedSeconds
        playbackState.durationSeconds = update.durationSeconds
        playbackState.progress = update.progress
        syncReadingPositionState(for: entry, progress: update.progress, chunkIndex: update.chunkIndex)
        playbackState.isPlaying = update.isPlaying
        entry.progress = update.progress
        entry.lastOpened = .now
        try? modelContext.save()
    }

    @MainActor
    private func isEntryPlaying(_ entry: LibraryEntry) -> Bool {
        guard let activeEntry else { return false }
        return activeEntry.persistentModelID == entry.persistentModelID
            && playbackState.isPlaying
    }

    @MainActor
    private func isEntryGeneratingAudio(_ entry: LibraryEntry) -> Bool {
        guard audioGenerationTask != nil else { return false }
        guard let pendingAudioGenerationEntry else { return false }
        return pendingAudioGenerationEntry.persistentModelID == entry.persistentModelID
    }

    @MainActor
    private func audioGenerationProgressFraction(for entry: LibraryEntry) -> Double? {
        guard isEntryGeneratingAudio(entry) else { return nil }
        return audioGenerationProgressValue
    }

    @MainActor
    private func openAudioGenerationSheet(for entry: LibraryEntry) {
        guard audioGenerationTask == nil else {
            audioGenerationAlertMessage = "Finish the current audio export before starting another one."
            return
        }

        guard normalizedTextFileURL(for: entry) != nil else {
            audioGenerationAlertMessage = "This item does not have a normalized file to export."
            return
        }

        pendingAudioGenerationEntry = entry
        pendingAudioVoiceName = kokoroVoiceName
        audioGenerationSheetEntry = entry
        audioGenerationProgressValue = nil
        audioGenerationPrewarmTask?.cancel()
        let voice = KokoroVoiceCatalog.voice(named: pendingAudioVoiceName)
        audioGenerationPrewarmTask = Task {
            await LibraryAudioGenerationService.shared.prewarm(voice: voice)
        }
    }

    @MainActor
    private func stopAudioGeneration(for entry: LibraryEntry) {
        cancelAudioGenerationIfNeeded(for: entry)
        pendingAudioDeletionEntry = nil
    }

    @MainActor
    private func confirmPendingAudioGeneration(for entry: LibraryEntry) {
        guard audioGenerationTask == nil else { return }

        pendingAudioGenerationEntry = entry
        audioGenerationSheetEntry = nil
        audioGenerationProgressValue = 0
        beginIdleSleepAssertion(for: .audio)

        let voiceName = pendingAudioVoiceName
        audioGenerationTask = Task {
            await processPendingAudioGeneration(for: entry, voiceName: voiceName)
        }
    }

    @MainActor
    private func discardPendingAudioGeneration() {
        audioGenerationTask?.cancel()
        audioGenerationTask = nil
        audioGenerationPrewarmTask?.cancel()
        audioGenerationPrewarmTask = nil
        pendingAudioGenerationEntry = nil
        audioGenerationSheetEntry = nil
        pendingAudioVoiceName = KokoroVoiceCatalog.defaultVoiceName
        audioGenerationProgressValue = nil
    }

    @MainActor
    private func processPendingAudioGeneration(for entry: LibraryEntry, voiceName: String) async {
        defer {
            audioGenerationTask = nil
            audioGenerationProgressValue = nil
            endIdleSleepAssertion(for: .audio)
        }

        guard let normalizedTextFileURL = normalizedTextFileURL(for: entry) else {
            pendingAudioGenerationEntry = nil
            audioGenerationAlertMessage = "This item does not have a normalized file to export."
            return
        }

        guard let voice = KokoroVoiceCatalog.allVoices.first(where: { $0.voiceName == voiceName }) else {
            pendingAudioGenerationEntry = nil
            audioGenerationAlertMessage = "The selected voice could not be found."
            return
        }

        do {
            let audioFileURL = try await LibraryAudioGenerationService.shared.generateAudioFile(
                from: normalizedTextFileURL,
                entryTitle: entry.title,
                voice: voice,
                progressHandler: { fraction in
                    await MainActor.run {
                        audioGenerationProgressValue = fraction
                    }
                }
            )

            entry.generatedAudioFilePath = audioFileURL.path
            entry.generatedAudioFileName = audioFileURL.lastPathComponent
            entry.generatedAudioVoiceName = voice.voiceName
            entry.generatedAudioUpdatedAt = .now
            try? modelContext.save()

            pendingAudioGenerationEntry = nil
            pendingAudioVoiceName = KokoroVoiceCatalog.defaultVoiceName
            successToastMessage = "\(entry.title) audio file is ready."
            playSuccessTone()
        } catch is CancellationError {
            pendingAudioGenerationEntry = nil
            pendingAudioVoiceName = KokoroVoiceCatalog.defaultVoiceName
            audioGenerationProgressValue = nil
        } catch {
            pendingAudioGenerationEntry = nil
            pendingAudioVoiceName = KokoroVoiceCatalog.defaultVoiceName
            audioGenerationProgressValue = nil
            audioGenerationAlertMessage = error.localizedDescription
        }
    }

    private func normalizedTextFileURL(for entry: LibraryEntry) -> URL? {
        guard let normalizedTextFilePath = entry.normalizedTextFilePath else { return nil }
        return URL(fileURLWithPath: normalizedTextFilePath)
    }

    @MainActor
    private func openAudioDeletionConfirmation(for entry: LibraryEntry) {
        guard entry.generatedAudioFileURL != nil else {
            audioGenerationAlertMessage = "This item does not have a generated audio file to delete."
            return
        }

        cancelAudioGenerationIfNeeded(for: entry)
        pendingAudioDeletionEntry = entry
    }

    @MainActor
    private func confirmAudioDeletion() {
        guard let entry = pendingAudioDeletionEntry else { return }
        pendingAudioDeletionEntry = nil
        cancelAudioGenerationIfNeeded(for: entry)

        if let audioURL = entry.generatedAudioFileURL {
            try? FileManager.default.removeItem(at: audioURL)
        }

        entry.generatedAudioFilePath = nil
        entry.generatedAudioFileName = nil
        entry.generatedAudioVoiceName = nil
        entry.generatedAudioUpdatedAt = nil
        try? modelContext.save()

        successToastMessage = "Deleted generated audio for \(entry.title)."
    }

    @MainActor
    private func cancelAudioGenerationIfNeeded(for entry: LibraryEntry) {
        guard isEntryGeneratingAudio(entry) else { return }

        audioGenerationTask?.cancel()
        audioGenerationTask = nil
        audioGenerationPrewarmTask?.cancel()
        audioGenerationPrewarmTask = nil
        pendingAudioGenerationEntry = nil
        audioGenerationSheetEntry = nil
        pendingAudioVoiceName = KokoroVoiceCatalog.defaultVoiceName
        audioGenerationProgressValue = nil
        endIdleSleepAssertion(for: .audio)
    }

    @MainActor
    private func beginIdleSleepAssertion(for kind: IdleSleepAssertionKind) {
        let activity: NSObjectProtocol

        switch kind {
        case .importing:
            if importAwakeAssertion != nil { return }
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled],
                reason: "Normalizing file"
            )
            importAwakeAssertion = activity
        case .audio:
            if audioGenerationAwakeAssertion != nil { return }
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled],
                reason: "Generating audio"
            )
            audioGenerationAwakeAssertion = activity
        }
    }

    @MainActor
    private func endIdleSleepAssertion(for kind: IdleSleepAssertionKind) {
        switch kind {
        case .importing:
            guard let activity = importAwakeAssertion else { return }
            ProcessInfo.processInfo.endActivity(activity)
            importAwakeAssertion = nil
        case .audio:
            guard let activity = audioGenerationAwakeAssertion else { return }
            ProcessInfo.processInfo.endActivity(activity)
            audioGenerationAwakeAssertion = nil
        }
    }

    private func playSuccessTone() {
        if let sound = NSSound(named: NSSound.Name("Glass")) {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    @MainActor
    private func handlePrimaryCardAction(for entry: LibraryEntry) {
        if isEntryPlaying(entry) {
            togglePlayback()
        } else {
            startPlayback(for: entry)
        }
    }

    private func readingPositionText(for entry: LibraryEntry, progress: Double) -> String {
        guard let structureKind = entry.readingStructureKind else { return "" }

        let targets = entry.readingJumpTargets
        guard !targets.isEmpty else { return "" }

        let index = ReaderPlaybackChunkService.chunkIndex(for: progress, chunkCount: targets.count)
        let target = targets[min(index, targets.count - 1)]
        let title = target.title.trimmingCharacters(in: .whitespacesAndNewlines)

        switch structureKind {
        case .page:
            if title.isEmpty {
                return "Page \(index + 1) of \(targets.count)"
            }
            return "Page \(index + 1) of \(targets.count) · \(title)"
        case .chapter:
            if title.isEmpty {
                return "Chapter \(index + 1) of \(targets.count)"
            }
            return "Chapter \(index + 1) of \(targets.count) · \(title)"
        case .section:
            if title.isEmpty {
                return "Section \(index + 1) of \(targets.count)"
            }
            return "Section \(index + 1) of \(targets.count) · \(title)"
        }
    }

    private func readingPositionText(for entry: LibraryEntry, targetIndex: Int) -> String {
        guard let structureKind = entry.readingStructureKind else { return "" }

        let targets = entry.readingJumpTargets
        guard !targets.isEmpty else { return "" }

        let index = min(max(targetIndex, 0), targets.count - 1)
        let target = targets[index]
        let title = target.title.trimmingCharacters(in: .whitespacesAndNewlines)

        switch structureKind {
        case .page:
            if title.isEmpty {
                return "Page \(index + 1) of \(targets.count)"
            }
            return "Page \(index + 1) of \(targets.count) · \(title)"
        case .chapter:
            if title.isEmpty {
                return "Chapter \(index + 1) of \(targets.count)"
            }
            return "Chapter \(index + 1) of \(targets.count) · \(title)"
        case .section:
            if title.isEmpty {
                return "Section \(index + 1) of \(targets.count)"
            }
            return "Section \(index + 1) of \(targets.count) · \(title)"
        }
    }

    private func readingPositionIndex(for entry: LibraryEntry, progress: Double) -> Int? {
        let targets = entry.readingJumpTargets
        guard !targets.isEmpty else { return nil }
        return ReaderPlaybackChunkService.chunkIndex(for: progress, chunkCount: targets.count)
    }

    private func readingPositionIndex(for entry: LibraryEntry, chunkIndex: Int) -> Int? {
        let targets = entry.readingJumpTargets
        guard !targets.isEmpty else { return nil }
        return ReaderPlaybackChunkService.readingTargetIndex(forChunkIndex: chunkIndex, in: entry)
    }

    private func syncReadingPositionState(for entry: LibraryEntry?, progress: Double, chunkIndex: Int? = nil) {
        guard let entry else { return }

        let totalCount = entry.readingJumpTargets.isEmpty ? nil : entry.readingJumpTargets.count
        let index = chunkIndex.flatMap { readingPositionIndex(for: entry, chunkIndex: $0) }
            ?? playbackState.readingPositionIndexOverride
            ?? entry.currentReadingPositionIndex
            ?? readingPositionIndex(for: entry, progress: progress)

        entry.currentReadingPositionIndex = index
        entry.currentReadingPositionTotalCount = totalCount
        playbackState.readingPositionIndexOverride = index
        playbackState.readingPositionTotalCount = totalCount
        playbackState.readingPositionText = entry.currentReadingPositionDisplayText ?? readingPositionText(for: entry, progress: progress)
        playbackState.readingPositionOverrideText = nil
    }

    private func readingProgress(for target: ReaderJumpTarget, in entry: LibraryEntry) -> Double {
        let targets = entry.readingJumpTargets
        guard !targets.isEmpty else { return 0 }
        return ReaderPlaybackChunkService.progress(for: target.index, chunkCount: targets.count)
    }

    private func playbackResumeProgress(for entry: LibraryEntry) -> Double {
        if let currentIndex = entry.currentReadingPositionIndex,
           let totalCount = entry.currentReadingPositionTotalCount,
           totalCount > 0 {
            return ReaderPlaybackChunkService.progress(for: currentIndex, chunkCount: totalCount)
        }

        return entry.progress
    }

    private func adjacentReadingTarget(for direction: ReadingNavigationDirection, in entry: LibraryEntry) -> ReaderJumpTarget? {
        let targets = entry.readingJumpTargets
        guard !targets.isEmpty else { return nil }

        let currentIndex = readingTargetIndex(for: entry) ?? 0
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

    private func canNavigateReadingTarget(_ direction: ReadingNavigationDirection, in entry: LibraryEntry?) -> Bool {
        guard let entry else { return false }
        let targets = entry.readingJumpTargets
        guard !targets.isEmpty else { return false }

        let currentIndex = readingTargetIndex(for: entry) ?? 0

        switch direction {
        case .backward:
            return currentIndex > 0
        case .forward:
            return currentIndex < targets.count - 1
        }
    }

    private func readingTargetIndex(for entry: LibraryEntry) -> Int? {
        entry.currentReadingPositionIndex ?? readingPositionIndex(for: entry, progress: playbackState.progress)
    }

    private func cancelReadingNavigationTask() {
        readingNavigationTask?.cancel()
        readingNavigationTask = nil
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [LibraryEntry.self, ReaderCategory.self], inMemory: true)
}
