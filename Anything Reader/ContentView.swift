//
//  ContentView.swift
//  Anything Reader
//
//  Main orchestration view for the reader shell.
//

import Foundation
import AppKit
import AVFoundation
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
    @AppStorage("activeTTSProviderID") private var activeTTSProviderIDRawValue: String = ReaderTTSProviderID.kokoro.rawValue
    @AppStorage("kokoroVoiceName") private var kokoroVoiceName: String = KokoroVoiceCatalog.defaultVoiceName
    @AppStorage("moonshineVoiceName") private var moonshineVoiceName: String = MoonshineVoiceCatalog.defaultVoiceName

    @State private var selection: SidebarSelection = .home
    @State private var homeSearchText = ""
    @State private var recentSearchText = ""
    @State private var freeBooksSearchText = ""
    @State private var audioMixerSearchText = ""
    @State private var rssFeedSearchText = ""
    @State private var categorySearchTexts: [String: String] = [:]
    @State private var visibleHomeEntryCount = 10
    @State private var visibleRecentEntryCount = 10
    @State private var isLoadingMoreHomeEntries = false
    @State private var isLoadingMoreRecentEntries = false
    @State private var freeBookDownloadRequest: FreeBook?
    @State private var freeBookDownloadSuccess: FreeBookDownloadSuccess?
    @State private var isDownloadingFreeBook = false
    @State private var freeBookDownloadMessage = ""
    @State private var isShowingPasteSheet = false
    @State private var isShowingSettings = false
    @State private var isShowingKokoroDownloadModal = false
    @State private var isShowingCategorySheet = false
    @State private var isShowingFileImporter = false
    @State private var isShowingImportLanguageSheet = false
    @State private var audioGenerationSheetEntry: LibraryEntry?
    @State private var pendingAudioDeletionEntry: LibraryEntry?
    @State private var summaryGenerationSuccess: SummaryGenerationSuccess?
    @State private var pendingSummaryEntry: LibraryEntry?
    @State private var summarySuccessEntry: LibraryEntry?
    @State private var newCategoryName = ""
    @State private var pastedTitle = ""
    @State private var pastedText = ""
    @State private var uploadAlertMessage: String?
    @State private var browserImportAlertMessage: String?
    @State private var browserHostInstallAlertMessage: String?
    @State private var importFailureMessage: String?
    @State private var processingImportMessage = ""
    @State private var successToastMessage: String?
    @State private var isProcessingImport = false
    @State private var pendingImportContext: PendingImportContext?
    @State private var pendingImportEntry: LibraryEntry?
    @State private var pendingAudioGenerationEntry: LibraryEntry?
    @State private var pendingAudioProviderID: ReaderTTSProviderID = .kokoro
    @State private var detectedDocumentLanguage: TextLanguage = .english
    @State private var pendingDocumentLanguage: TextLanguage = .english
    @State private var pendingAudioVoiceName: String = KokoroVoiceCatalog.defaultVoiceName
    @State private var audioGenerationProgressValue: Double?
    @State private var isTranslateDocument = false
    @State private var translateToLanguage: TextLanguage = .english
    @State private var pendingCategoryDeletionName: String?
    @State private var importAwakeAssertion: NSObjectProtocol?
    @State private var audioGenerationAwakeAssertion: NSObjectProtocol?
    @State private var summaryGenerationAwakeAssertion: NSObjectProtocol?
    @State private var generatedAudioAlertMessage: String?
    @State private var summaryGenerationAlertMessage: String?
    @State private var playbackState = PlaybackState()
    @State private var activeEntry: LibraryEntry?
    @State private var activePlaybackSummaryFilePath: String?
    @State private var activePlaybackShouldPersistProgress = true
    @State private var summaryPlaybackLastSavedElapsedSeconds: Int = 0
    @State private var activeGeneratedAudioEntry: LibraryEntry?
    @State private var viewerEntry: LibraryEntry?
    @State private var viewerAlertMessage: String?
    @State private var playbackTask: Task<Void, Never>?
    @State private var playbackWarmupTask: Task<Void, Never>?
    @State private var playbackProgressPersistenceTask: Task<Void, Never>?
    @State private var readingNavigationTask: Task<Void, Never>?
    @State private var audioGenerationTask: Task<Void, Never>?
    @State private var audioGenerationPrewarmTask: Task<Void, Never>?
    @State private var summaryGenerationTask: Task<Void, Never>?
    @State private var playbackChunks: [String] = []
    @State private var playbackChunkIndex: Int = 0
    @State private var playbackSessionToken = UUID()
    @State private var playbackProgressLastSavedElapsedSeconds: Int = 0
    @State private var toastDismissTask: Task<Void, Never>?
    @State private var didCleanupGeneratedContent = false
    @State private var coverArtGenerationKeys: Set<String> = []
    @State private var didBackfillMissingCoverArt = false
    @State private var didPresentKokoroDownloadGate = false
    @State private var audioGenerationAlertMessage: String?
    @State private var isHomeDropTargeted = false
    @State private var presentedUpdateVersion: String?
    @State private var updateDialogNotice: AppUpdateNotice?
    @StateObject private var kokoroModelStore = KokoroModelStore.shared
    @StateObject private var moonshineModelStore = MoonshineModelStore.shared
    @StateObject private var kokoroSpeechService = KokoroSpeechService.shared
    @StateObject private var moonshineSpeechService = MoonshineSpeechService.shared
    @StateObject private var ttsCoordinator = ReaderTTSCoordinator.shared
    @StateObject private var readerPlaybackService = ReaderPlaybackService.shared
    @StateObject private var generatedAudioPlaybackService = GeneratedAudioPlaybackService.shared
    @StateObject private var audioMixerPlaybackService = AudioMixerPlaybackService.shared
    @StateObject private var audioMixerLibraryService = AudioMixerLibraryService.shared
    @StateObject private var rssFeedRefreshService = RSSFeedRefreshService.shared
    @StateObject private var appUpdateChecker = AppUpdateChecker.shared
    @State private var translationCoordinator = DocumentTranslationCoordinator()

    private enum ReadingNavigationDirection {
        case backward
        case forward
    }

    private enum IdleSleepAssertionKind {
        case importing
        case audio
        case summarizing
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
        [UTType.pdf, UTType.plainText, UTType.epub, UTType.image]
    }

    private struct PendingImportContext {
        let sourceURL: URL
        let uploadDirectoryURL: URL
        let stagedURL: URL
        let fileName: String
        let fileExtension: String
        let sourceKind: ReaderSourceKind
        let shouldAutoPlay: Bool
        let importCategoryName: String?
        var createdFileURLs: [URL]
    }

    private struct SummaryGenerationSuccess: Identifiable {
        let id = UUID()
        let title: String
    }

    var body: some View {
        ZStack {
            backgroundLayer

            NavigationSplitView {
                ReaderSidebarView(
                    categories: categories,
                    selection: $selection,
                    rssUnreadCount: rssFeedRefreshService.unreadFeedItemCount,
                    onAddCategory: { isShowingCategorySheet = true }
                )
            } detail: {
                detailContent
            }
            .navigationSplitViewStyle(.balanced)
        }
        .safeAreaInset(edge: .bottom) {
            if shouldShowGeneratedAudioPlayerBar, let entry = activeGeneratedAudioEntry {
                GeneratedAudioPlayerBarView(
                    title: entry.title,
                    subtitle: entry.generatedAudioFileName ?? entry.originalFileName ?? entry.fileExtension.uppercased(),
                    avatarSymbol: entry.avatarSymbolName,
                    accentName: entry.accentName,
                    isPlaying: generatedAudioPlaybackService.isPlaying,
                    elapsedSeconds: generatedAudioPlaybackService.currentElapsedSeconds,
                    durationSeconds: generatedAudioPlaybackService.currentDurationSeconds,
                    volume: Binding(
                        get: { generatedAudioPlaybackService.volume },
                        set: { generatedAudioPlaybackService.setVolume($0) }
                    ),
                    playbackSpeed: Binding(
                        get: { generatedAudioPlaybackService.playbackSpeed },
                        set: { generatedAudioPlaybackService.setPlaybackSpeed($0) }
                    ),
                    preferredMode: preferredMode,
                    onTogglePlayPause: toggleGeneratedAudioPlayback,
                    onSeek: { fraction in generatedAudioPlaybackService.seek(to: fraction) },
                    onStop: stopGeneratedAudioPlayback
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            } else if shouldShowPlayerBar {
                let summaryPlaybackActive = isSummaryPlaybackActive
                ReaderPlayerBarView(
                    playbackState: $playbackState,
                    volume: Binding(
                        get: { readerPlaybackService.volume },
                        set: { readerPlaybackService.setVolume($0) }
                    ),
                    preferredMode: preferredMode,
                    isLoadingFirstChunk: readerPlaybackService.isBufferingFirstChunk,
                    readingStructureKind: summaryPlaybackActive ? nil : activeEntry?.readingStructureKind,
                    jumpTargets: summaryPlaybackActive ? [] : (activeEntry?.readingJumpTargets ?? []),
                    canRewind: summaryPlaybackActive ? false : canNavigateReadingTarget(.backward, in: activeEntry),
                    canFastForward: summaryPlaybackActive ? false : canNavigateReadingTarget(.forward, in: activeEntry),
                    onRewind: rewindPlayback,
                    onTogglePlayPause: togglePlayback,
                    onFastForward: fastForwardPlayback,
                    onJumpToTarget: { target in
                        if !summaryPlaybackActive {
                            jumpToReadingTarget(target)
                        }
                    }
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
            ReaderTTSSettingsSheet(
                appearanceModeRawValue: $appearanceModeRawValue,
                activeProviderIDRawValue: $activeTTSProviderIDRawValue,
                kokoroVoiceName: $kokoroVoiceName,
                moonshineVoiceName: $moonshineVoiceName,
                ttsCoordinator: ttsCoordinator,
                isKokoroPlaying: kokoroSpeechService.isPlaying,
                isMoonshinePlaying: moonshineSpeechService.isPlaying,
                onPlaySample: playTTSVoiceSample
            )
        }
        .sheet(isPresented: $isShowingKokoroDownloadModal) {
            ReaderTTSDownloadSheet(
                kokoroModelStore: kokoroModelStore,
                moonshineModelStore: moonshineModelStore,
                ttsCoordinator: ttsCoordinator,
                preferredMode: preferredMode,
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
                voiceOptions: ttsCoordinator.availableVoiceOptions(for: pendingAudioProviderID),
                onGenerate: {
                    confirmPendingAudioGeneration(for: entry)
                },
                onCancel: discardPendingAudioGeneration
            )
        }
        .sheet(item: $freeBookDownloadRequest) { book in
            FreeBookDownloadOptionsSheet(
                book: book,
                onDownload: { translateBook, targetLanguage in
                    freeBookDownloadRequest = nil
                    Task {
                        await importFreeBook(book: book, translateBook: translateBook, targetLanguage: targetLanguage)
                    }
                },
                onCancel: {
                    freeBookDownloadRequest = nil
                }
            )
        }
        .sheet(item: $freeBookDownloadSuccess) { success in
            FreeBookDownloadSuccessSheet(
                title: success.title,
                onView: {
                    selection = .home
                    freeBookDownloadSuccess = nil
                },
                onDone: {
                    freeBookDownloadSuccess = nil
                }
            )
        }
        .sheet(item: $summaryGenerationSuccess) { success in
            ReaderSummarySuccessSheet(
                title: success.title,
                onPlay: {
                    if let summarySuccessEntry {
                        playSummarizedFile(for: summarySuccessEntry)
                    }
                    summaryGenerationSuccess = nil
                    summarySuccessEntry = nil
                },
                onDone: {
                    summaryGenerationSuccess = nil
                    summarySuccessEntry = nil
                }
            )
        }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: uploadAllowedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            handleImportedFileSelection(result)
        }
        .readerNotifications(
            uploadAlertMessage: $uploadAlertMessage,
            browserImportAlertMessage: $browserImportAlertMessage,
            browserHostInstallAlertMessage: $browserHostInstallAlertMessage,
            importFailureMessage: $importFailureMessage,
            viewerAlertMessage: $viewerAlertMessage,
            pendingAudioDeletionEntry: $pendingAudioDeletionEntry,
            audioGenerationAlertMessage: $audioGenerationAlertMessage,
            generatedAudioAlertMessage: $generatedAudioAlertMessage,
            summaryGenerationAlertMessage: $summaryGenerationAlertMessage,
            onRetryPendingImport: retryPendingImport,
            onDiscardPendingImport: discardPendingImport,
            onConfirmAudioDeletion: confirmAudioDeletion
        )
        .preferredColorScheme(preferredMode.colorScheme)
        .tint(.green)
        .overlay {
            if readerPlaybackService.isBufferingFirstChunk {
                ReaderPlaybackLoadingOverlayView(message: "Preparing first chunk", subtitle: "This only takes a few seconds")
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
        .confirmationDialog(
            "Delete Category?",
            isPresented: Binding(
                get: { pendingCategoryDeletionName != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingCategoryDeletionName = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Category", role: .destructive) {
                if let categoryName = pendingCategoryDeletionName {
                    deleteCategory(named: categoryName)
                }
                pendingCategoryDeletionName = nil
            }

            Button("Cancel", role: .cancel) {
                pendingCategoryDeletionName = nil
            }
        } message: {
            Text("This will remove the category from all library items that use it.")
        }
        .task {
            cleanupGeneratedDemoContentIfNeeded()
            backfillMissingCoverArtIfNeeded()
            await backfillGeneratedAudioMetadataIfNeeded()
            audioMixerLibraryService.loadIfNeeded(using: modelContext)
            audioMixerLibraryService.repairLibraryIfNeeded(using: modelContext)
            validateSelectedTTSConfiguration()
            ttsCoordinator.refreshInstallationStatus()
            promptForTTSDownloadIfNeeded()
        }
        .task {
            do {
                try await BrowserNativeMessagingService.shared.installHostIfNeeded()
            } catch {
                browserHostInstallAlertMessage = "Chrome manifest install failed: \(error.localizedDescription)"
            }
            await monitorBrowserInbox()
        }
        .task {
            appUpdateChecker.startMonitoring()
        }
        .task {
            rssFeedRefreshService.startIfNeeded()
        }
        .onChange(of: selection) { _, newValue in
            isHomeDropTargeted = false
            switch newValue {
            case .home:
                visibleHomeEntryCount = 10
            case .recent:
                visibleRecentEntryCount = 10
            case .freeBooks, .audioMixer, .rssFeeds, .category(_):
                break
            }
        }
        .onChange(of: kokoroModelStore.status) { _, _ in
            ttsCoordinator.refreshInstallationStatus()
            if case .installed(let providerID) = ttsCoordinator.availabilityStatus {
                successToastMessage = "\(providerID.title) model downloaded and ready"
            } else if case .failed(let message) = ttsCoordinator.availabilityStatus {
                successToastMessage = "TTS model download failed: \(message)"
                isShowingKokoroDownloadModal = true
            }
        }
        .onChange(of: moonshineModelStore.status) { _, _ in
            ttsCoordinator.refreshInstallationStatus()
            if case .installed(let providerID) = ttsCoordinator.availabilityStatus {
                successToastMessage = "\(providerID.title) model downloaded and ready"
            } else if case .failed(let message) = ttsCoordinator.availabilityStatus {
                successToastMessage = "TTS model download failed: \(message)"
                isShowingKokoroDownloadModal = true
            }
        }
        .onChange(of: appUpdateChecker.notice) { _, newNotice in
            guard let newNotice else { return }
            guard presentedUpdateVersion != newNotice.currentVersion else { return }

            presentedUpdateVersion = newNotice.currentVersion
            updateDialogNotice = newNotice
            presentUpdateDialog(for: newNotice)
        }
        .onChange(of: activeTTSProviderIDRawValue) { _, newValue in
            if let providerID = ReaderTTSProviderID(rawValue: newValue) {
                ttsCoordinator.setActiveProvider(providerID)
                restartPlaybackForSelectedVoiceIfNeeded()
            }
        }
        .onChange(of: kokoroVoiceName) { _, newValue in
            ttsCoordinator.setSelectedVoiceName(newValue, for: .kokoro)
            restartPlaybackForSelectedVoiceIfNeeded()
        }
        .onChange(of: moonshineVoiceName) { _, newValue in
            ttsCoordinator.setSelectedVoiceName(newValue, for: .moonshine)
            restartPlaybackForSelectedVoiceIfNeeded()
        }
        .onChange(of: readerPlaybackService.isPlaying) { _, _ in
        }
        .onChange(of: readerPlaybackService.isPaused) { _, _ in
        }
        .onChange(of: generatedAudioPlaybackService.isPlaying) { _, _ in
        }
        .onChange(of: audioMixerPlaybackService.followsReaderPlayback) { _, _ in
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
                        Color(red: 26/255, green: 35/255, blue: 30/255),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .ignoresSafeArea()
    }

    private func validateSelectedTTSConfiguration() {
        let kokoroNames = Set(KokoroVoiceCatalog.allVoices.map(\.voiceName))
        if !kokoroNames.contains(kokoroVoiceName) {
            kokoroVoiceName = KokoroVoiceCatalog.defaultVoiceName
        }

        let moonshineNames = Set(MoonshineVoiceCatalog.allVoices.map(\.voiceName))
        if !moonshineNames.contains(moonshineVoiceName) {
            moonshineVoiceName = MoonshineVoiceCatalog.defaultVoiceName
        }

        if ReaderTTSProviderID(rawValue: activeTTSProviderIDRawValue) == nil {
            activeTTSProviderIDRawValue = ReaderTTSProviderID.kokoro.rawValue
        }
    }

    @MainActor
    private func monitorBrowserInbox() async {
        while !Task.isCancelled {
            do {
                let pendingMessages = try await BrowserNativeMessagingService.shared.consumePendingMessages()
                if !pendingMessages.isEmpty {
                    for message in pendingMessages {
                        importBrowserMessage(message)
                    }
                }
            } catch {
                // The browser inbox is best-effort. Launch should stay quiet if the folder is not ready yet.
            }

            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
    }

    private var shouldShowPlayerBar: Bool {
        activeEntry != nil && !readerPlaybackService.isBufferingFirstChunk
    }

    private var isSummaryPlaybackActive: Bool {
        activePlaybackSummaryFilePath != nil
    }

    private var shouldShowGeneratedAudioPlayerBar: Bool {
        activeGeneratedAudioEntry != nil && generatedAudioPlaybackService.hasLoadedAudio
    }

    private func playTTSVoiceSample(_ voice: ReaderTTSVoiceSelection) {
        ttsCoordinator.playSample(for: voice)
        successToastMessage = "Playing \(voice.displayName) sample"
    }

    @MainActor
    private func restartPlaybackForSelectedVoiceIfNeeded() {
        guard let entry = activeEntry else { return }
        guard playbackState.isPlaying || readerPlaybackService.isPlaying || readerPlaybackService.isBufferingFirstChunk else { return }

        discardPlaybackAudioCache(for: entry)
        readerPlaybackService.stop()
        stopPlaybackTask()
        stopPlaybackWarmupTask()
        stopPlaybackProgressPersistenceTask()
        cancelReadingNavigationTask()
        playbackState.isPlaying = true
        startPlayback(for: entry)
    }

    private func promptForTTSDownloadIfNeeded() {
        guard !didPresentKokoroDownloadGate else { return }
        didPresentKokoroDownloadGate = true

        if !kokoroModelStore.isInstalled && !moonshineModelStore.isInstalled {
            isShowingKokoroDownloadModal = true
        }
    }

    private func openKokoroDownloadModal() {
        isShowingKokoroDownloadModal = true
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
                        searchText: activeSearchTextBinding,
                        searchPlaceholder: searchPlaceholder,
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
                        homeContent(
                            featured: sortedByDateAdded.first,
                            sortedByDateAdded: sortedByDateAdded
                        )

                    case .recent:
                        ReaderLibrarySectionView(
                            title: "Recently Played",
                            subtitle: "Your last opened books and pasted text",
                            entries: sortedByRecentlyPlayed,
                            visibleEntryCount: visibleRecentEntryCount,
                            isLoadingMore: isLoadingMoreRecentEntries,
                            onLoadMore: loadMoreRecentEntries,
                            categories: categories,
                            coverArtGenerationKeys: coverArtGenerationKeys,
                            preferredMode: preferredMode,
                            onDeleteCategory: nil,
                            isEntryPlaying: isEntryPlaying(_:),
                            isEntryGeneratingAudio: isEntryGeneratingAudio(_:),
                            isEntrySummarizing: isEntrySummarizing(_:),
                            isSummaryPlaying: isSummaryPlaybackPlaying(for:),
                            audioGenerationProgressFraction: audioGenerationProgressFraction(for:),
                            generatedAudioProgressFraction: generatedAudioProgressFraction(for:),
                            readingProgressFraction: readingPlaybackProgressFraction(for:),
                            onPrimaryAction: playLibraryEntry(_:),
                            onPlay: playLibraryEntry(_:),
                            onPlaySummary: playSummarizedLibraryEntry(_:),
                            onSummarize: summarizeLibraryEntry(_:),
                            onCancelSummarization: cancelSummaryGenerationIfNeeded(for:),
                            onOpenOriginalFile: openOriginalUploadedFile,
                            onViewTextFile: openNormalizedTextViewer,
                            onRevealLocation: revealLibraryEntryLocation,
                            onGenerateAudio: openAudioGenerationSheet(for:),
                            onStopAudioGeneration: stopAudioGeneration(for:),
                            onDeleteAudio: openAudioDeletionConfirmation(for:),
                            onClearCategory: { assign($0, to: nil) },
                            onAssignCategory: { assign($0, to: $1) },
                            onDelete: deleteEntry
                        )

                    case .freeBooks:
                        FreeBooksView(
                            searchText: $freeBooksSearchText,
                            isDownloadingBook: $isDownloadingFreeBook,
                            downloadMessage: $freeBookDownloadMessage,
                            onDownloadBook: { book in
                                freeBookDownloadRequest = book
                            }
                        )

                    case .audioMixer:
                        AudioMixerView(
                            libraryService: audioMixerLibraryService,
                            playbackService: audioMixerPlaybackService,
                            searchText: $audioMixerSearchText,
                            preferredMode: preferredMode
                        )

                    case .rssFeeds:
                        RSSFeedsView(
                            refreshService: rssFeedRefreshService,
                            searchText: $rssFeedSearchText,
                            preferredMode: preferredMode,
                            onFeedSaved: {
                                successToastMessage = "RSS feed saved, fetching feed..."
                                playSuccessTone()
                            },
                            onReadAloud: { item in
                                try await prepareRSSArticleReadAloudImport(from: item)
                            }
                        )

                    case .category(let categoryName):
                        ReaderLibrarySectionView(
                            title: categoryName,
                            subtitle: "All books filed into this category",
                            entries: sortedByDateAdded,
                            visibleEntryCount: sortedByDateAdded.count,
                            isLoadingMore: false,
                            onLoadMore: {},
                            categories: categories,
                            coverArtGenerationKeys: coverArtGenerationKeys,
                            preferredMode: preferredMode,
                            onDeleteCategory: { pendingCategoryDeletionName = categoryName },
                            isEntryPlaying: isEntryPlaying(_:),
                            isEntryGeneratingAudio: isEntryGeneratingAudio(_:),
                            isEntrySummarizing: isEntrySummarizing(_:),
                            isSummaryPlaying: isSummaryPlaybackPlaying(for:),
                            audioGenerationProgressFraction: audioGenerationProgressFraction(for:),
                            generatedAudioProgressFraction: generatedAudioProgressFraction(for:),
                            readingProgressFraction: readingPlaybackProgressFraction(for:),
                            onPrimaryAction: playLibraryEntry(_:),
                            onPlay: playLibraryEntry(_:),
                            onPlaySummary: playSummarizedLibraryEntry(_:),
                            onSummarize: summarizeLibraryEntry(_:),
                            onCancelSummarization: cancelSummaryGenerationIfNeeded(for:),
                            onOpenOriginalFile: openOriginalUploadedFile,
                            onViewTextFile: openNormalizedTextViewer,
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
            .navigationTitle("Anything Reader - Offline & Private Text to Speech")
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

    @ViewBuilder
    private func homeContent(
        featured: LibraryEntry?,
        sortedByDateAdded: [LibraryEntry]
    ) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            if let notice = appUpdateChecker.notice {
                updateBannerView(for: notice)
            }

            ReaderTTSHeroView(
                featured: featured,
                preferredMode: preferredMode,
                ttsStatus: ttsCoordinator.availabilityStatus,
                activeProviderID: ttsCoordinator.activeProviderID,
                onPasteText: { isShowingPasteSheet = true },
                onUploadFile: { isShowingFileImporter = true },
                onOpenLibrary: { selection = .recent },
                onDownloadTTS: openKokoroDownloadModal,
                isUploadDisabled: isImportInFlight
            )

            ReaderLibrarySectionView(
                title: "Library",
                subtitle: "Everything you have imported or pasted",
                entries: sortedByDateAdded,
                visibleEntryCount: visibleHomeEntryCount,
                isLoadingMore: isLoadingMoreHomeEntries,
                onLoadMore: loadMoreHomeEntries,
                categories: categories,
                coverArtGenerationKeys: coverArtGenerationKeys,
                preferredMode: preferredMode,
                onDeleteCategory: nil,
                isEntryPlaying: isEntryPlaying(_:),
                isEntryGeneratingAudio: isEntryGeneratingAudio(_:),
                isEntrySummarizing: isEntrySummarizing(_:),
                isSummaryPlaying: isSummaryPlaybackPlaying(for:),
                audioGenerationProgressFraction: audioGenerationProgressFraction(for:),
                generatedAudioProgressFraction: generatedAudioProgressFraction(for:),
                readingProgressFraction: readingPlaybackProgressFraction(for:),
                onPrimaryAction: playLibraryEntry(_:),
                onPlay: playLibraryEntry(_:),
                onPlaySummary: playSummarizedLibraryEntry(_:),
                onSummarize: summarizeLibraryEntry(_:),
                onCancelSummarization: cancelSummaryGenerationIfNeeded(for:),
                onOpenOriginalFile: openOriginalUploadedFile,
                onViewTextFile: openNormalizedTextViewer,
                onRevealLocation: revealLibraryEntryLocation,
                onGenerateAudio: openAudioGenerationSheet(for:),
                onStopAudioGeneration: stopAudioGeneration(for:),
                onDeleteAudio: openAudioDeletionConfirmation(for:),
                onClearCategory: { assign($0, to: nil) },
                onAssignCategory: { assign($0, to: $1) },
                onDelete: deleteEntry
            )
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 110)
        .overlay {
            if isHomeDropTargeted {
                homeDropOverlay
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 110)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isHomeDropTargeted, perform: handleDroppedFiles)
    }

    private var filteredEntries: [LibraryEntry] {
        let query = activeSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

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
            case .freeBooks:
                matchesSelection = true
            case .audioMixer:
                matchesSelection = false
            case .rssFeeds:
                matchesSelection = false
            case .category(let categoryName):
                matchesSelection = entry.categoryName == categoryName
            }

            return matchesQuery && matchesSelection
        }
    }

    @MainActor
    private func loadMoreHomeEntries() async {
        guard !isLoadingMoreHomeEntries else { return }

        isLoadingMoreHomeEntries = true
        defer { isLoadingMoreHomeEntries = false }

        await Task.yield()
        visibleHomeEntryCount += 10
    }

    @MainActor
    private func loadMoreRecentEntries() async {
        guard !isLoadingMoreRecentEntries else { return }

        isLoadingMoreRecentEntries = true
        defer { isLoadingMoreRecentEntries = false }

        await Task.yield()
        visibleRecentEntryCount += 10
    }

    private var activeSearchTextBinding: Binding<String> {
        switch selection {
        case .home:
            return $homeSearchText
        case .recent:
            return $recentSearchText
        case .freeBooks:
            return $freeBooksSearchText
        case .audioMixer:
            return $audioMixerSearchText
        case .rssFeeds:
            return $rssFeedSearchText
        case .category(let categoryName):
            return Binding(
                get: { categorySearchTexts[categoryName] ?? "" },
                set: { categorySearchTexts[categoryName] = $0 }
            )
        }
    }

    private var activeSearchText: String {
        switch selection {
        case .home:
            return homeSearchText
        case .recent:
            return recentSearchText
        case .freeBooks:
            return freeBooksSearchText
        case .audioMixer:
            return audioMixerSearchText
        case .rssFeeds:
            return rssFeedSearchText
        case .category(let categoryName):
            return categorySearchTexts[categoryName] ?? ""
        }
    }

    private var searchPlaceholder: String {
        switch selection {
        case .home, .recent, .category(_):
            return "Search books, text, categories"
        case .freeBooks:
            return "Search free books, authors, categories"
        case .audioMixer:
            return "Search audio tracks"
        case .rssFeeds:
            return "Search RSS feeds"
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
    private func ensureCategory(named categoryName: String) -> ReaderCategory {
        if let existingCategory = categories.first(where: { $0.name == categoryName }) {
            return existingCategory
        }

        let category = ReaderCategory(
            name: categoryName,
            accentName: Self.accentPalette.randomElement() ?? "emerald"
        )
        modelContext.insert(category)
        try? modelContext.save()
        return category
    }

    @MainActor
    private func deleteCategory(named categoryName: String) {
        guard let category = categories.first(where: { $0.name == categoryName }) else { return }

        libraryEntries
            .filter { $0.categoryName == categoryName }
            .forEach { $0.categoryName = nil }

        if case .category(let selectedCategoryName) = selection,
           selectedCategoryName == categoryName {
            selection = .recent
        }

        modelContext.delete(category)
        try? modelContext.save()
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

        if activeGeneratedAudioEntry?.persistentModelID == entry.persistentModelID {
            stopGeneratedAudioPlayback()
        }

        if pendingSummaryEntry?.persistentModelID == entry.persistentModelID {
            cancelSummaryGenerationIfNeeded(for: entry)
        }

        if viewerEntry?.persistentModelID == entry.persistentModelID {
            viewerEntry = nil
        }

        removeAssociatedFiles(for: entry)

        Task {
            await PhonemeCacheService.shared.removeCache(for: entry)
            await ReaderPlaybackAudioCacheService.shared.removeCache(for: entry)
        }

        modelContext.delete(entry)
        try? modelContext.save()
    }

    // MARK: - File Viewing

    private func openOriginalUploadedFile(_ entry: LibraryEntry) {
        guard let storedPath = entry.storedFilePath else {
            viewerAlertMessage = "This item does not have an uploaded file to open."
            return
        }

        let fileURL = URL(fileURLWithPath: storedPath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            viewerAlertMessage = "The uploaded file could not be found on disk."
            return
        }

        entry.lastOpened = .now
        try? modelContext.save()

        if !NSWorkspace.shared.open(fileURL) {
            viewerAlertMessage = "The uploaded file could not be opened in another app."
        }
    }

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

    @MainActor
    private func summarizeLibraryEntry(_ entry: LibraryEntry) {
        guard summaryGenerationTask == nil else {
            summaryGenerationAlertMessage = "Finish the current summary before starting another one."
            return
        }

        guard let normalizedText = ReaderPlaybackChunkService.normalizedText(for: entry) else {
            summaryGenerationAlertMessage = "This item does not have a normalized file to summarize."
            return
        }

        summaryGenerationAlertMessage = nil
        summaryGenerationSuccess = nil
        summarySuccessEntry = nil
        pendingSummaryEntry = entry
        beginIdleSleepAssertion(for: .summarizing)

        summaryGenerationTask = Task { @MainActor in
            defer {
                summaryGenerationTask = nil
                pendingSummaryEntry = nil
                endIdleSleepAssertion(for: .summarizing)
            }

            do {
                let sourceLanguage = entry.textLanguage ?? TextNormalizationService.detectLanguage(for: normalizedText)
                let summarizedText = try await FileSummarizationService.shared.summarize(
                    text: normalizedText,
                    language: sourceLanguage
                )
                try Task.checkCancellation()
                let normalizedSummary = TextNormalizationService.normalize(summarizedText, language: sourceLanguage)

                guard !normalizedSummary.isEmpty else {
                    throw FileSummarizationError.emptyInput
                }

                if let summaryURL = entry.summarizedTextFileURL,
                   FileManager.default.fileExists(atPath: summaryURL.path) {
                    try? FileManager.default.removeItem(at: summaryURL)
                }

                let summaryData = Data(normalizedSummary.utf8)
                let summaryFileName = summaryFileName(for: entry)
                let storedURL = try storeTextFile(
                    contents: summaryData,
                    fileName: summaryFileName,
                    directoryURL: summaryStorageDirectory(for: entry)
                )

                entry.summarizedTextFilePath = storedURL.path
                entry.summarizedTextUpdatedAt = .now
                entry.summarizedTextPlaybackPositionSeconds = 0
                entry.lastOpened = .now
                try modelContext.save()

                summarySuccessEntry = entry
                summaryGenerationSuccess = SummaryGenerationSuccess(title: entry.title)
                playSuccessTone()
            } catch is CancellationError {
                return
            } catch {
                summaryGenerationAlertMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func playSummarizedFile(for entry: LibraryEntry) {
        guard let summaryURL = entry.summarizedTextFileURL else {
            summaryGenerationAlertMessage = "This item does not have a summarized file yet."
            return
        }

        if isSummaryPlaybackTracked(for: entry) {
            togglePlayback()
            return
        }

        startPlayback(
            for: entry,
            textFileURL: summaryURL,
            displayTitle: "Summary: \(entry.title)",
            persistProgress: true
        )
    }

    private func summaryFileName(for entry: LibraryEntry) -> String {
        let baseName = entry.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")

        if baseName.isEmpty {
            return "summary"
        }

        return "\(baseName)-summary"
    }

    private func summaryStorageDirectory(for entry: LibraryEntry) -> URL? {
        if let summaryDirectory = entry.normalizedTextFileURL?.deletingLastPathComponent() {
            return summaryDirectory
        }

        if let summaryDirectory = entry.storedFilePath.map({ URL(fileURLWithPath: $0).deletingLastPathComponent() }) {
            return summaryDirectory
        }

        return try? uploadedFilesDirectory()
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
        let trackedURLs = [
            entry.storedFilePath,
            entry.normalizedTextFilePath,
            entry.summarizedTextFilePath,
            entry.coverImageFilePath,
            entry.generatedAudioFilePath
        ]
        .compactMap { $0 }
        .map { URL(fileURLWithPath: $0) }

        trackedURLs.forEach { fileURL in
            if fileManager.fileExists(atPath: fileURL.path) {
                try? fileManager.removeItem(at: fileURL)
            }
        }

        if let parentDirectory = trackedURLs.first?.deletingLastPathComponent(),
           fileManager.fileExists(atPath: parentDirectory.path) {
            try? fileManager.removeItem(at: parentDirectory)
        }
    }

    private func generatedAudioDurationSeconds(for fileURL: URL) async -> Int {
        let asset = AVURLAsset(url: fileURL)

        let duration: CMTime
        do {
            duration = try await asset.load(.duration)
        } catch {
            return 0
        }

        let durationSeconds = duration.seconds
        guard durationSeconds.isFinite, durationSeconds > 0 else { return 0 }
        return Int(durationSeconds.rounded())
    }

    // MARK: - Paste Text

    @MainActor
    private func playPastedText() {
        let trimmedText = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        let trimmedTitle = pastedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = trimmedTitle.isEmpty ? pastedTextExcerptTitle(from: trimmedText) : trimmedTitle
        guard let pastedEntry = storePlainTextEntry(
            title: resolvedTitle,
            subtitle: "Pasted text saved locally for later.",
            text: trimmedText,
            fileName: sanitizedStorageFileName(for: resolvedTitle),
            categoryName: "Pasted Text"
        ) else {
            uploadAlertMessage = "The pasted text could not be imported."
            return
        }

        pastedTitle = ""
        pastedText = ""
        isShowingPasteSheet = false
        startPlayback(for: pastedEntry)
    }

    private func pastedTextExcerptTitle(from text: String) -> String {
        let condensed = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !condensed.isEmpty else { return "Pasted Text" }

        let excerpt = String(condensed.prefix(28))
        return condensed.count > excerpt.count ? "\(excerpt)..." : excerpt
    }

    @MainActor
    private func importBrowserMessage(_ message: BrowserNativeMessage) {
        let trimmedText = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            browserImportAlertMessage = "The browser page did not contain readable text."
            return
        }

        let resolvedTitle = browserTitle(for: message)
        guard let browserEntry = storePlainTextEntry(
            title: resolvedTitle,
            subtitle: browserSubtitle(for: message),
            text: trimmedText,
            fileName: sanitizedStorageFileName(for: resolvedTitle),
            categoryName: browserCategoryName(for: message)
        ) else {
            browserImportAlertMessage = "The browser page could not be imported."
            return
        }

        successToastMessage = "Imported browser page"
        startPlayback(for: browserEntry)
    }

    private func browserTitle(for message: BrowserNativeMessage) -> String {
        let trimmedTitle = message.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }

        let now = Date()
        let calendar = Calendar.current
        let browserCount = libraryEntries.filter { entry in
            entry.sourceKind == .pastedText && calendar.isDate(entry.createdAt, inSameDayAs: now)
        }.count + 1

        if let pageURL = message.pageURL,
           let host = URL(string: pageURL)?.host,
           !host.isEmpty {
            return "Web Clip from \(host) #\(browserCount)"
        }

        return "Web Clip #\(browserCount)"
    }

    private func browserSubtitle(for message: BrowserNativeMessage) -> String {
        if let pageURL = message.pageURL,
           let host = URL(string: pageURL)?.host,
           !host.isEmpty {
            return "Saved from \(host)."
        }

        return "Saved from browser extension."
    }

    private func browserCategoryName(for message: BrowserNativeMessage) -> String? {
        let trimmedSite = message.site?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedSite.isEmpty ? nil : trimmedSite
    }

    @MainActor
    private func storePlainTextEntry(
        title: String,
        subtitle: String,
        text: String,
        fileName: String,
        categoryName: String? = nil
    ) -> LibraryEntry? {
        let detectedLanguage = TextNormalizationService.detectLanguage(for: text)
        let normalizedText = TextNormalizationService.normalize(text, language: detectedLanguage)
        guard !normalizedText.isEmpty else { return nil }

        let textData = Data(normalizedText.utf8)
        guard let storedURL = try? storeTextFile(contents: textData, fileName: fileName) else {
            return nil
        }

        let storedEntry = LibraryEntry(
            title: title,
            subtitle: subtitle,
            sourceKind: .pastedText,
            fileExtension: "txt",
            originalFileName: "\(fileName).txt",
            storedFilePath: storedURL.path,
            normalizedTextFilePath: storedURL.path,
            coverImageFilePath: nil,
            fileSizeBytes: Int64(textData.count),
            categoryName: categoryName.flatMap { ensureCategory(named: $0).name },
            avatarSymbolName: Self.fallbackAvatars.randomElement() ?? "waveform",
            accentName: Self.accentPalette.randomElement() ?? "emerald",
            phonemeText: nil,
            phonemeUpdatedAt: nil,
            textLanguage: detectedLanguage,
            progress: 0.04,
            lastOpened: .now
        )

        modelContext.insert(storedEntry)
        try? modelContext.save()
        return storedEntry
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
    private func preparePendingImport(
        from sourceURL: URL,
        shouldAutoPlay: Bool = false,
        importCategoryName: String? = nil
    ) async {
        audioMixerPlaybackService.beginReaderPlaybackTransition()
        do {
            let stagedResult = try stageImportedFile(from: sourceURL)
            let stagedURL = stagedResult.stagedURL
            let fileExtension = stagedURL.pathExtension.lowercased()
            let detectedLanguage = DocumentIngestService.detectLanguage(
                for: stagedURL,
                fileExtension: fileExtension
            )

            detectedDocumentLanguage = detectedLanguage
            pendingDocumentLanguage = detectedLanguage
            pendingImportContext = PendingImportContext(
                sourceURL: sourceURL,
                uploadDirectoryURL: stagedResult.uploadDirectoryURL,
                stagedURL: stagedURL,
                fileName: sourceURL.lastPathComponent,
                fileExtension: fileExtension,
                sourceKind: readerSourceKind(for: fileExtension),
                shouldAutoPlay: shouldAutoPlay,
                importCategoryName: importCategoryName,
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
            audioMixerPlaybackService.endReaderPlaybackTransition()
            cleanupPendingImportArtifacts()
        }
    }

    @MainActor
    private func prepareRSSArticleReadAloudImport(from item: RSSFeedItemRecord) async throws {
        audioMixerPlaybackService.beginReaderPlaybackTransition()
        guard let articleURL = item.linkURL ?? URL(string: item.linkURLString) else {
            audioMixerPlaybackService.endReaderPlaybackTransition()
            throw RSSArticleScraperError.invalidArticleURL
        }

        do {
            let draft = try await RSSArticleScraperService.shared.scrapeArticle(from: articleURL)
            let tempURL = try createTemporaryRSSArticleFile(from: draft)
            defer {
                try? FileManager.default.removeItem(at: tempURL)
            }

            await preparePendingImport(from: tempURL, shouldAutoPlay: true, importCategoryName: "RSS Feed")
        } catch {
            audioMixerPlaybackService.endReaderPlaybackTransition()
            throw error
        }
    }

    private func createTemporaryRSSArticleFile(from draft: RSSArticleDraft) throws -> URL {
        let fileManager = FileManager.default
        let directoryURL = fileManager.temporaryDirectory.appendingPathComponent("RSS Article Imports", isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let fileName = sanitizedStorageFileName(for: draft.title.isEmpty ? "RSS Article" : draft.title)
        let fileURL = directoryURL.appendingPathComponent(fileName).appendingPathExtension("txt")
        let body = [draft.title, "", draft.body]
            .joined(separator: "\n")

        try body.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private func handleDroppedFiles(_ providers: [NSItemProvider]) -> Bool {
        guard providers.contains(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }

        Task {
            await handleDroppedFilesAsync(providers)
        }

        return true
    }

    @MainActor
    private func handleDroppedFilesAsync(_ providers: [NSItemProvider]) async {
        guard let sourceURL = await firstDroppedFileURL(from: providers) else {
            uploadAlertMessage = "The dropped file could not be read."
            return
        }

        let fileExtension = sourceURL.pathExtension.lowercased()
        guard isSupportedUploadFileExtension(fileExtension) else {
            uploadAlertMessage = "Please drop a PDF, TXT, ePub, or image file."
            return
        }

        await preparePendingImport(from: sourceURL)
    }

    private func firstDroppedFileURL(from providers: [NSItemProvider]) async -> URL? {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            if let fileURL = await loadDroppedFileURL(from: provider) {
                return fileURL
            }
        }

        return nil
    }

    private func loadDroppedFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                    return
                }

                if let url = item as? NSURL {
                    continuation.resume(returning: url as URL)
                    return
                }

                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                    return
                }

                if let string = item as? String {
                    if let url = URL(string: string) {
                        continuation.resume(returning: url)
                        return
                    }

                    continuation.resume(returning: URL(fileURLWithPath: string))
                    return
                }

                continuation.resume(returning: nil)
            }
        }
    }

    private var homeDropOverlay: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color.green.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(
                        Color.green.opacity(0.72),
                        style: StrokeStyle(lineWidth: 2, dash: [10, 8])
                    )
            )
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 28, weight: .semibold))
                    Text("Drop PDF, ePub, TXT, or image files here")
                        .font(.headline)
                    Text("The file will open in the upload flow after it is validated and staged locally.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .padding(24)
            )
    }

    private func updateBannerView(for notice: AppUpdateNotice) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(notice.title)
                    .font(.headline.weight(.bold))
                Text(notice.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button {
                appUpdateChecker.openAppStore()
            } label: {
                Label("Download", systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.green.opacity(0.35), lineWidth: 1)
        )
    }

    @MainActor
    private func presentUpdateDialog(for notice: AppUpdateNotice) {
        let alert = NSAlert()
        alert.messageText = notice.title
        alert.informativeText = notice.subtitle
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download")

        if !notice.isForceUpdateRequired {
            alert.addButton(withTitle: "Later")
        }

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            appUpdateChecker.openAppStore()
        }

        if response == .alertSecondButtonReturn {
            updateDialogNotice = nil
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
            placeholderEntry.coverImageFilePath = context.sourceKind == .image ? context.stagedURL.path : nil
            placeholderEntry.fileSizeBytes = ingest.fileSizeBytes
            if let importCategoryName = context.importCategoryName {
                let category = ensureCategory(named: importCategoryName)
                placeholderEntry.categoryName = category.name
            } else {
                placeholderEntry.categoryName = nil
            }
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

            let shouldAutoPlay = context.shouldAutoPlay

            await MainActor.run {
                clearPendingImportState(showing: "\(placeholderEntry.title) is ready to play.")
                queueCoverArtGenerationIfNeeded(for: placeholderEntry)
                if shouldAutoPlay {
                    startPlayback(for: placeholderEntry)
                } else {
                    audioMixerPlaybackService.endReaderPlaybackTransition()
                }
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
                    audioMixerPlaybackService.endReaderPlaybackTransition()
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
                audioMixerPlaybackService.endReaderPlaybackTransition()
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
        audioMixerPlaybackService.endReaderPlaybackTransition()
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
        if fileManager.fileExists(atPath: context.uploadDirectoryURL.path) {
            try? fileManager.removeItem(at: context.uploadDirectoryURL)
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

    private func stageImportedFile(from sourceURL: URL) throws -> (stagedURL: URL, uploadDirectoryURL: URL) {
        guard sourceURL.isFileURL else {
            throw UploadError.invalidFile
        }

        let extensionName = sourceURL.pathExtension.lowercased()
        guard isSupportedUploadFileExtension(extensionName) else {
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

        let directoryURL = try makeUploadDirectory(for: sourceURL)
        let baseName = sanitizedImportedFileBaseName(from: sourceURL)
        let destinationURL = directoryURL.appendingPathComponent("\(baseName).\(extensionName)")

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return (destinationURL, directoryURL)
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

    private func sanitizedStorageFileName(for title: String) -> String {
        title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
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
    private func backfillGeneratedAudioMetadataIfNeeded() async {
        for entry in libraryEntries {
            guard let generatedAudioURL = entry.generatedAudioFileURL else { continue }
            guard entry.generatedAudioDurationSeconds == nil else { continue }
            guard FileManager.default.fileExists(atPath: generatedAudioURL.path) else { continue }

            entry.generatedAudioDurationSeconds = await generatedAudioDurationSeconds(for: generatedAudioURL)
        }

        try? modelContext.save()
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

    private func storeTextFile(contents: Data, fileName: String, directoryURL: URL? = nil) throws -> URL {
        let fileManager = FileManager.default
        let resolvedDirectoryURL: URL
        if let directoryURL {
            resolvedDirectoryURL = directoryURL
        } else {
            resolvedDirectoryURL = try uploadedFilesDirectory()
        }
        let destinationFileName: String
        if directoryURL == nil {
            destinationFileName = "\(UUID().uuidString)-\(fileName).txt"
        } else {
            destinationFileName = "\(fileName).txt"
        }
        let destinationURL = resolvedDirectoryURL.appendingPathComponent(destinationFileName)

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        _ = fileManager.createFile(atPath: destinationURL.path, contents: contents)
        return destinationURL
    }

    @MainActor
    private func importFreeBook(
        book: FreeBook,
        translateBook: Bool,
        targetLanguage: TextLanguage
    ) async {
        guard !isProcessingImport else { return }

        isProcessingImport = true
        isDownloadingFreeBook = true
        processingImportMessage = "Downloading \(book.displayTitle)…"
        freeBookDownloadMessage = processingImportMessage
        beginIdleSleepAssertion(for: .importing)

        var stagedFileURLs: [URL] = []

        defer {
            isProcessingImport = false
            processingImportMessage = ""
            isDownloadingFreeBook = false
            freeBookDownloadMessage = ""
            endIdleSleepAssertion(for: .importing)
        }

        do {
            let sourceLanguage = book.primaryLanguage ?? .english
            let downloadDirectory = try makeFreeBookDownloadDirectory(for: book)
            guard let txtURL = book.preferredTXTDownloadURL else {
                throw UploadError.unsupportedFileType
            }
            let stagedURL = try await downloadFreeBookFile(
                from: txtURL,
                into: downloadDirectory,
                fileName: freeBookFileName(for: book),
                fileExtension: "txt"
            )
            stagedFileURLs.append(stagedURL)

            let draft = try await DocumentIngestService.shared.extractDraft(
                stagedFileURL: stagedURL,
                fileExtension: "txt",
                documentLanguage: sourceLanguage
            )

            await MainActor.run {
                processingImportMessage = translateBook
                    ? "Translating \(book.displayTitle)…"
                    : "Normalizing \(book.displayTitle)…"
                freeBookDownloadMessage = processingImportMessage
            }

            let finalText: String
            let normalizedLanguage: TextLanguage

            if translateBook {
                guard let translationSourceLanguage = sourceLanguage.localeLanguage,
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
                    break
                case .unsupported:
                    throw DocumentTranslationError.unsupported(
                        source: sourceLanguage,
                        target: targetLanguage
                    )
                @unknown default:
                    throw DocumentTranslationError.unsupported(
                        source: sourceLanguage,
                        target: targetLanguage
                    )
                }

                finalText = try await translationCoordinator.translate(
                    sourceText: draft.rawText,
                    sourceLanguage: sourceLanguage,
                    targetLanguage: targetLanguage
                )
                normalizedLanguage = targetLanguage
            } else {
                finalText = draft.rawText
                normalizedLanguage = sourceLanguage
            }

            let ingest = try await DocumentIngestService.shared.finalize(
                draft: draft,
                sourceText: finalText,
                normalizedLanguage: normalizedLanguage,
                originalFileName: freeBookFileName(for: book),
                sourceURL: stagedURL
            )

            stagedFileURLs.append(ingest.normalizedTextFileURL)

            let title = ingest.title ?? book.displayTitle
            await MainActor.run {
                processingImportMessage = "Downloading cover art for \(book.displayTitle)…"
                freeBookDownloadMessage = processingImportMessage
            }
            let coverImageFilePath = try await downloadFreeBookCover(
                from: book.coverURL,
                into: downloadDirectory,
                fileName: freeBookFileName(for: book)
            )

            let entry = LibraryEntry(
                title: title,
                subtitle: "Downloaded from Free Books",
                sourceKind: ingest.sourceKind,
                fileExtension: "txt",
                originalFileName: "\(freeBookFileName(for: book)).txt",
                storedFilePath: stagedURL.path,
                normalizedTextFilePath: ingest.normalizedTextFileURL.path,
                coverImageFilePath: coverImageFilePath,
                fileSizeBytes: ingest.fileSizeBytes,
                categoryName: ensureCategory(named: "Books").name,
                avatarSymbolName: ReaderSourceKind.text.systemImage,
                accentName: Self.accentPalette.randomElement() ?? "emerald",
                phonemeText: nil,
                phonemeUpdatedAt: nil,
                textLanguage: ingest.textLanguage,
                pdfExtractionMode: ingest.pdfExtractionMode,
                readingStructureKind: ingest.readingStructureKind,
                pageCount: ingest.pageCount,
                chapterCount: ingest.chapterCount,
                sectionCount: ingest.sectionCount,
                importState: .ready,
                readingJumpTargets: ingest.readingJumpTargets,
                progress: 0,
                lastOpened: .now
            )

            modelContext.insert(entry)
            try modelContext.save()

            freeBookDownloadSuccess = FreeBookDownloadSuccess(title: entry.title)
            playSuccessTone()
        } catch {
            stagedFileURLs.forEach { url in
                if FileManager.default.fileExists(atPath: url.path) {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            uploadAlertMessage = error.localizedDescription
        }
    }

    private func freeBookFileName(for book: FreeBook) -> String {
        let title = book.displayTitle
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\"", with: "")
        let fallback = title.isEmpty ? "free-book-\(book.id)" : title
        return fallback
    }

    private func makeFreeBookDownloadDirectory(for book: FreeBook) throws -> URL {
        let fileManager = FileManager.default
        let rootDirectory = try uploadedFilesDirectory()
        let timestamp = Self.importTimestampFormatter.string(from: .now)
        let folderName = "free-book-\(book.id)-\(timestamp)-\(freeBookFileName(for: book))"
        let sanitizedFolderName = folderName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let directoryURL = rootDirectory.appendingPathComponent(sanitizedFolderName, isDirectory: true)

        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        return directoryURL
    }

    private func downloadFreeBookFile(
        from sourceURL: URL,
        into directoryURL: URL,
        fileName: String,
        fileExtension: String
    ) async throws -> URL {
        let downloadURL = httpsIfNeeded(sourceURL)
        print("Free book TXT download URL: \(downloadURL.absoluteString)")
        let (temporaryURL, response) = try await downloadFileIgnoringInsecureRedirects(from: downloadURL)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw UploadError.invalidFile
        }

        let destinationURL = directoryURL.appendingPathComponent("\(fileName).\(fileExtension)")
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        return destinationURL
    }

    private func downloadFreeBookCover(
        from coverURL: URL?,
        into directoryURL: URL,
        fileName: String
    ) async throws -> String? {
        guard let coverURL else { return nil }

        let downloadURL = httpsIfNeeded(coverURL)
        print("Free book cover download URL: \(downloadURL.absoluteString)")
        let (temporaryURL, response) = try await downloadFileIgnoringInsecureRedirects(from: downloadURL)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            return nil
        }

        let fileManager = FileManager.default
        let responseURL = response.url ?? coverURL
        let extensionName = responseURL.pathExtension.isEmpty ? coverURL.pathExtension : responseURL.pathExtension
        let safeExtension = extensionName.isEmpty ? "png" : extensionName
        let destinationURL = directoryURL.appendingPathComponent("\(fileName)-cover.\(safeExtension)")

        if fileManager.fileExists(atPath: destinationURL.path) {
            try? fileManager.removeItem(at: destinationURL)
        }

        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        return destinationURL.path
    }

    private func downloadFileIgnoringInsecureRedirects(from url: URL) async throws -> (URL, URLResponse) {
        let delegate = FreeBookDownloadSessionDelegate()
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)

        return try await withCheckedThrowingContinuation { continuation in
            let task = session.downloadTask(with: url) { temporaryURL, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let temporaryURL, let response else {
                    continuation.resume(throwing: UploadError.invalidFile)
                    return
                }

                continuation.resume(returning: (temporaryURL, response))
            }

            delegate.task = task
            task.resume()
        }
    }

    private func httpsIfNeeded(_ url: URL) -> URL {
        guard url.scheme == "http", url.host?.contains("gutenberg.org") == true else {
            return url
        }

        let httpsString = url.absoluteString.replacingOccurrences(
            of: "http://",
            with: "https://",
            options: [.anchored]
        )
        return URL(string: httpsString) ?? url
    }

    private final class FreeBookDownloadSessionDelegate: NSObject, URLSessionTaskDelegate {
        var task: URLSessionTask?

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            guard let requestURL = request.url else {
                completionHandler(request)
                return
            }

            let secureURL = secureGutenbergURL(for: requestURL)
            if secureURL != requestURL {
                var secureRequest = request
                secureRequest.url = secureURL
                print("Free book redirect rewritten to: \(secureURL.absoluteString)")
                completionHandler(secureRequest)
                return
            }

            completionHandler(request)
        }

        private func secureGutenbergURL(for url: URL) -> URL {
            guard url.host?.contains("gutenberg.org") == true else {
                return url
            }

            let httpsString = url.absoluteString.replacingOccurrences(
                of: "http://",
                with: "https://",
                options: [.anchored]
            )
            return URL(string: httpsString) ?? url
        }
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

    private func makeUploadDirectory(for sourceURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let rootDirectory = try uploadedFilesDirectory()
        let directoryName = sanitizedUploadedFileDirectoryName(from: sourceURL)
        let destinationDirectory = rootDirectory.appendingPathComponent(directoryName, isDirectory: true)

        if !fileManager.fileExists(atPath: destinationDirectory.path) {
            try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        }

        return destinationDirectory
    }

    private func sanitizedUploadedFileDirectoryName(from sourceURL: URL) -> String {
        let timestamp = Self.importTimestampFormatter.string(from: .now)
        let stem = sourceURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let sanitizedStem = stem.isEmpty ? "upload" : stem
        return "\(timestamp)-\(sanitizedStem)"
    }

    private func readerSourceKind(for fileExtension: String) -> ReaderSourceKind {
        if UTType(filenameExtension: fileExtension)?.conforms(to: .image) == true {
            return .image
        }

        switch fileExtension.lowercased() {
        case "pdf":
            return .pdf
        case "epub":
            return .epub
        case "txt":
            return .text
        case "html", "htm":
            return .html
        default:
            return .text
        }
    }

    private func isSupportedUploadFileExtension(_ fileExtension: String) -> Bool {
        guard !fileExtension.isEmpty else { return false }

        if ["pdf", "txt", "epub"].contains(fileExtension) {
            return true
        }

        return UTType(filenameExtension: fileExtension)?.conforms(to: .image) == true
    }

    private func avatarSymbol(for sourceKind: ReaderSourceKind) -> String {
        switch sourceKind {
        case .pdf:
            return "doc.richtext.fill"
        case .epub:
            return "book.fill"
        case .image:
            return "doc.text.image"
        case .text, .html, .pastedText:
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
                return "Please choose a PDF, TXT, ePub, or image file."
            }
        }
    }

    // MARK: - Playback

    @MainActor
    private func playLibraryEntry(_ entry: LibraryEntry) {
        if let generatedAudioURL = entry.generatedAudioFileURL {
            if generatedAudioPlaybackService.hasLoadedAudio(for: generatedAudioURL) {
                toggleGeneratedAudioPlayback()
            } else {
                startGeneratedAudioPlayback(for: entry, fileURL: generatedAudioURL)
            }
            return
        }

        if let activeEntry,
           activeEntry.persistentModelID == entry.persistentModelID,
           (playbackState.isPlaying || readerPlaybackService.isPaused) {
            togglePlayback()
        } else {
            if let activeEntry,
               activeEntry.persistentModelID != entry.persistentModelID {
                readerPlaybackService.stop()
                discardPlaybackAudioCache(for: activeEntry)
            }
            startPlayback(for: entry)
        }
    }

    @MainActor
    private func playSummarizedLibraryEntry(_ entry: LibraryEntry) {
        guard let summaryURL = entry.summarizedTextFileURL else {
            summaryGenerationAlertMessage = "This item does not have a summarized file yet."
            return
        }

        if let activeEntry,
           activeEntry.persistentModelID == entry.persistentModelID,
           (playbackState.isPlaying || readerPlaybackService.isPaused) {
            togglePlayback()
        } else {
            if let activeEntry,
               activeEntry.persistentModelID != entry.persistentModelID {
                readerPlaybackService.stop()
                discardPlaybackAudioCache(for: activeEntry)
            }
            startPlayback(
                for: entry,
                textFileURL: summaryURL,
                displayTitle: "Summary: \(entry.title)",
                persistProgress: true
            )
        }
    }

    @MainActor
    private func startPlayback(
        for entry: LibraryEntry,
        textFileURL: URL? = nil,
        displayTitle: String? = nil,
        persistProgress: Bool = true
    ) {
        let priorEntry = activeEntry
        audioMixerPlaybackService.beginReaderPlaybackTransition()
        readerPlaybackService.stop()
        stopPlaybackTask()
        stopPlaybackWarmupTask()
        cancelReadingNavigationTask()

        if let priorEntry,
           priorEntry.persistentModelID != entry.persistentModelID
            || activePlaybackSummaryFilePath != textFileURL?.path {
            discardPlaybackAudioCache(for: priorEntry)
        }

        stopGeneratedAudioPlayback()
        playbackSessionToken = UUID()
        let sessionToken = playbackSessionToken
        let normalizedText = ReaderPlaybackChunkService.normalizedText(for: textFileURL ?? entry.normalizedTextFileURL) ?? ""
        let duration = estimatedPlaybackDuration(for: normalizedText)
        let isSummaryPlayback = textFileURL?.path == entry.summarizedTextFileURL?.path
        let resumeProgress = persistProgress
            ? playbackResumeProgress(for: entry, textFileURL: textFileURL, duration: duration)
            : 0
        let resumeTargetIndex = persistProgress && !isSummaryPlayback
            ? (entry.currentReadingPositionIndex ?? readingPositionIndex(for: entry, progress: resumeProgress))
            : nil
        let chunks = ReaderPlaybackChunkService.chunks(for: entry, textFileURL: textFileURL)
        let startingChunkIndex = resumeTargetIndex.flatMap { ReaderPlaybackChunkService.chunkIndex(for: $0, in: entry) } ?? ReaderPlaybackChunkService.chunkIndex(for: resumeProgress, chunkCount: chunks.count)

        // Store the active record so progress updates persist to SwiftData.
        activeEntry = entry
        activePlaybackSummaryFilePath = textFileURL?.path == entry.summarizedTextFileURL?.path ? textFileURL?.path : nil
        activePlaybackShouldPersistProgress = persistProgress
        summaryPlaybackLastSavedElapsedSeconds = activePlaybackSummaryFilePath != nil ? Int((Double(duration) * resumeProgress).rounded()) : 0
        entry.lastOpened = .now

        playbackChunks = chunks
        playbackChunkIndex = startingChunkIndex

        let elapsedSeconds = Int((Double(duration) * resumeProgress).rounded())
        playbackProgressLastSavedElapsedSeconds = elapsedSeconds

        playbackState = PlaybackState(
            title: displayTitle ?? entry.title,
            subtitle: entry.subtitle,
            readingPositionText: displayTitle ?? entry.currentReadingPositionDisplayText ?? readingPositionText(for: entry, progress: resumeProgress),
            readingPositionOverrideText: nil,
            readingPositionIndexOverride: persistProgress && !isSummaryPlayback ? (entry.currentReadingPositionIndex ?? readingPositionIndex(for: entry, progress: resumeProgress)) : nil,
            readingPositionTotalCount: persistProgress && !isSummaryPlayback ? (entry.currentReadingPositionTotalCount ?? (entry.readingJumpTargets.isEmpty ? nil : entry.readingJumpTargets.count)) : nil,
            avatarSymbol: entry.avatarSymbolName,
            accentName: entry.accentName,
            progress: resumeProgress,
            durationSeconds: duration,
            elapsedSeconds: elapsedSeconds,
            isPlaying: true
        )

        if persistProgress {
            entry.progress = resumeProgress
            try? modelContext.save()
        }

        let voice = ttsCoordinator.activeVoiceSelection()
        readerPlaybackService.play(
            entry: entry,
            voice: voice,
            startingProgress: resumeProgress,
            startingChunkIndex: startingChunkIndex,
            textFileURL: textFileURL,
            onProgress: { update in
                guard self.playbackSessionToken == sessionToken else { return }
                self.applyPlaybackUpdate(update, to: entry)
            },
            onFinished: {
                guard self.playbackSessionToken == sessionToken else { return }
                self.stopPlaybackProgressPersistenceTask()
                self.playbackState.progress = 0
                self.playbackState.elapsedSeconds = 0
                self.playbackState.isPlaying = false
                self.audioMixerPlaybackService.endReaderPlaybackTransition()
                if self.activePlaybackSummaryFilePath != nil {
                    entry.summarizedTextPlaybackPositionSeconds = 0
                    self.summaryPlaybackLastSavedElapsedSeconds = 0
                    try? self.modelContext.save()
                } else if self.activePlaybackShouldPersistProgress {
                    entry.progress = 0
                    try? self.modelContext.save()
                }
                self.persistPlayerProgress(force: true)
            },
            onFailure: { message in
                guard self.playbackSessionToken == sessionToken else { return }
                self.stopPlaybackProgressPersistenceTask()
                self.playbackState.isPlaying = false
                self.audioMixerPlaybackService.endReaderPlaybackTransition()
                self.uploadAlertMessage = message
            }
        )

        if persistProgress {
            startPlaybackProgressPersistenceTask(for: sessionToken)
        }
    }

    @MainActor
    private func startGeneratedAudioPlayback(for entry: LibraryEntry, fileURL: URL) {
        audioMixerPlaybackService.beginReaderPlaybackTransition()
        readerPlaybackService.stop()
        stopPlaybackTask()
        stopPlaybackWarmupTask()
        stopPlaybackProgressPersistenceTask()
        cancelReadingNavigationTask()
        playbackState = PlaybackState()
        activeEntry = nil
        activePlaybackSummaryFilePath = nil
        playbackChunks = []
        playbackChunkIndex = 0
        playbackSessionToken = UUID()

        activeGeneratedAudioEntry = entry
        entry.lastOpened = .now
        if entry.generatedAudioDurationSeconds == nil {
            Task { @MainActor in
                guard entry.generatedAudioDurationSeconds == nil else { return }
                entry.generatedAudioDurationSeconds = await generatedAudioDurationSeconds(for: fileURL)
                try? modelContext.save()
            }
        }

        let resumeTime = entry.generatedAudioPlaybackPosition

        generatedAudioPlaybackService.play(
            fileURL: fileURL,
            title: entry.title,
            startingTime: resumeTime,
            onProgress: { elapsedSeconds, _ in
                self.persistGeneratedAudioPlaybackProgress(for: entry, elapsedSeconds: elapsedSeconds)
            },
            onFinished: {
                self.persistGeneratedAudioPlaybackProgress(for: entry, elapsedSeconds: 0)
                self.audioMixerPlaybackService.endReaderPlaybackTransition()
                self.stopGeneratedAudioPlayback()
            },
            onFailure: { message in
                self.stopGeneratedAudioPlayback()
                self.audioMixerPlaybackService.endReaderPlaybackTransition()
                self.generatedAudioAlertMessage = message
            }
        )
    }

    @MainActor
    private func togglePlayback() {
        if playbackState.isPlaying {
            playbackState.isPlaying = false
            readerPlaybackService.pause()
            stopPlaybackProgressPersistenceTask()
            persistPlayerProgress(force: true)
        } else if readerPlaybackService.isPaused, activeEntry != nil {
            readerPlaybackService.resume()
            playbackState.isPlaying = true
            if activePlaybackShouldPersistProgress || activePlaybackSummaryFilePath != nil {
                startPlaybackProgressPersistenceTask(for: playbackSessionToken)
            }
        } else {
            if let entry = activeEntry {
                if let activePlaybackSummaryFilePath,
                   let summaryURL = entry.summarizedTextFileURL,
                   summaryURL.path == activePlaybackSummaryFilePath {
                    startPlayback(
                        for: entry,
                        textFileURL: summaryURL,
                        displayTitle: "Summary: \(entry.title)",
                        persistProgress: true
                    )
                } else {
                    startPlayback(for: entry)
                }
            } else {
                playbackState.isPlaying = false
            }
        }
    }

    @MainActor
    private func toggleGeneratedAudioPlayback() {
        guard activeGeneratedAudioEntry != nil else { return }
        generatedAudioPlaybackService.togglePlayback()
    }

    @MainActor
    private func stopGeneratedAudioPlayback() {
        generatedAudioPlaybackService.stop()
        if let activeGeneratedAudioEntry {
            activeGeneratedAudioEntry.lastOpened = .now
        }
        activeGeneratedAudioEntry = nil
    }

    @MainActor
    private func persistGeneratedAudioPlaybackProgress(for entry: LibraryEntry, elapsedSeconds: Int) {
        entry.generatedAudioPlaybackPositionSeconds = max(0, elapsedSeconds)
        if entry.generatedAudioDurationSeconds == nil, let generatedAudioURL = entry.generatedAudioFileURL {
            Task { @MainActor in
                guard entry.generatedAudioDurationSeconds == nil else { return }
                entry.generatedAudioDurationSeconds = await generatedAudioDurationSeconds(for: generatedAudioURL)
                try? modelContext.save()
            }
        }
        entry.lastOpened = .now
        try? modelContext.save()
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
        discardPlaybackAudioCache(for: entry)
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
    private func persistPlayerProgress(force: Bool = false) {
        guard let activeEntry else { return }

        if activePlaybackSummaryFilePath != nil {
            persistSummaryPlaybackProgress(for: activeEntry, force: force)
            return
        }

        guard activePlaybackShouldPersistProgress else { return }

        let elapsedSeconds = max(0, playbackState.elapsedSeconds)
        guard force || abs(elapsedSeconds - playbackProgressLastSavedElapsedSeconds) >= 5 else {
            return
        }

        playbackProgressLastSavedElapsedSeconds = elapsedSeconds
        activeEntry.progress = playbackState.progress
        syncReadingPositionState(for: activeEntry, progress: playbackState.progress, chunkIndex: playbackChunkIndex)
        activeEntry.lastOpened = .now
        try? modelContext.save()
    }

    @MainActor
    private func startPlaybackProgressPersistenceTask(for sessionToken: UUID) {
        stopPlaybackProgressPersistenceTask()

        guard activePlaybackShouldPersistProgress || activePlaybackSummaryFilePath != nil else { return }

        playbackProgressPersistenceTask = Task { [sessionToken] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch {
                    return
                }

                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.playbackSessionToken == sessionToken else { return }
                    self.persistPlayerProgress()
                }
            }
        }
    }

    @MainActor
    private func stopPlaybackProgressPersistenceTask() {
        playbackProgressPersistenceTask?.cancel()
        playbackProgressPersistenceTask = nil
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
    private func discardPlaybackAudioCache(for entry: LibraryEntry) {
        // The first-chunk cache is session-scoped for a specific entry/position.
        // When the user switches files or jumps to a different chapter, that old
        // cache no longer has a live playback target, so it is cleared explicitly.
        Task {
            await ReaderPlaybackAudioCacheService.shared.removeCache(for: entry)
        }
    }

    @MainActor
    private func applyPlaybackUpdate(_ update: ReaderPlaybackUpdate, to entry: LibraryEntry) {
        guard playbackState.isPlaying else { return }
        playbackState.elapsedSeconds = update.elapsedSeconds
        playbackState.durationSeconds = update.durationSeconds
        playbackState.progress = update.progress
        playbackState.isPlaying = update.isPlaying
        playbackChunkIndex = update.chunkIndex

        if activePlaybackSummaryFilePath == nil, activePlaybackShouldPersistProgress {
            let targetIndex = readingPositionIndex(for: entry, chunkIndex: update.chunkIndex)
                ?? self.readingPositionIndex(for: entry, progress: update.progress)
            playbackState.readingPositionIndexOverride = targetIndex
            playbackState.readingPositionTotalCount = entry.readingJumpTargets.isEmpty ? nil : entry.readingJumpTargets.count
            playbackState.readingPositionText = targetIndex.flatMap {
                readingPositionText(for: entry, targetIndex: $0)
            } ?? readingPositionText(for: entry, progress: update.progress)
            playbackState.readingPositionOverrideText = nil
        }
    }

    @MainActor
    private func persistSummaryPlaybackProgress(for entry: LibraryEntry, force: Bool = false) {
        let elapsedSeconds = max(0, playbackState.elapsedSeconds)
        let shouldPersist = force || abs(elapsedSeconds - summaryPlaybackLastSavedElapsedSeconds) >= 5
        guard shouldPersist else { return }

        summaryPlaybackLastSavedElapsedSeconds = elapsedSeconds
        entry.summarizedTextPlaybackPositionSeconds = elapsedSeconds
        entry.lastOpened = .now
        try? modelContext.save()
    }

    @MainActor
    private func isEntryPlaying(_ entry: LibraryEntry) -> Bool {
        if let generatedAudioURL = entry.generatedAudioFileURL,
           generatedAudioPlaybackService.isPlayingAudio(for: generatedAudioURL) {
            return true
        }

        guard let activeEntry else { return false }
        return activeEntry.persistentModelID == entry.persistentModelID
            && playbackState.isPlaying
    }

    @MainActor
    private func isEntryPaused(_ entry: LibraryEntry) -> Bool {
        return readerPlaybackService.isPausedPlayback(for: entry)
    }

    @MainActor
    private func isEntryGeneratingAudio(_ entry: LibraryEntry) -> Bool {
        guard audioGenerationTask != nil else { return false }
        guard let pendingAudioGenerationEntry else { return false }
        return pendingAudioGenerationEntry.persistentModelID == entry.persistentModelID
    }

    @MainActor
    private func isSummaryPlaybackTracked(for entry: LibraryEntry) -> Bool {
        guard let activePlaybackSummaryFilePath else { return false }
        guard let summaryURL = entry.summarizedTextFileURL else { return false }
        return summaryURL.path == activePlaybackSummaryFilePath
    }

    @MainActor
    private func isSummaryPlaybackPlaying(for entry: LibraryEntry) -> Bool {
        isSummaryPlaybackTracked(for: entry) && playbackState.isPlaying
    }

    @MainActor
    private func isEntrySummarizing(_ entry: LibraryEntry) -> Bool {
        guard summaryGenerationTask != nil else { return false }
        guard let pendingSummaryEntry else { return false }
        return pendingSummaryEntry.persistentModelID == entry.persistentModelID
    }

    @MainActor
    private func audioGenerationProgressFraction(for entry: LibraryEntry) -> Double? {
        guard isEntryGeneratingAudio(entry) else { return nil }
        return audioGenerationProgressValue
    }

    private func generatedAudioProgressFraction(for entry: LibraryEntry) -> Double? {
        guard let generatedAudioURL = entry.generatedAudioFileURL else { return nil }

        if generatedAudioPlaybackService.hasLoadedAudio(for: generatedAudioURL) {
            let duration = generatedAudioPlaybackService.currentDurationSeconds
            guard duration > 0 else { return nil }
            return min(max(Double(generatedAudioPlaybackService.currentElapsedSeconds) / Double(duration), 0), 1)
        }

        let savedFraction = entry.generatedAudioProgressFraction
        return entry.generatedAudioDurationSeconds == nil && savedFraction == 0 ? nil : savedFraction
    }

    private func readingPlaybackProgressFraction(for entry: LibraryEntry) -> Double? {
        guard let activeEntry else { return nil }
        guard activeEntry.persistentModelID == entry.persistentModelID else { return nil }
        return playbackState.displayedProgress
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
        pendingAudioProviderID = ttsCoordinator.activeProviderID
        pendingAudioVoiceName = ttsCoordinator.selectedVoiceName(for: pendingAudioProviderID)
        audioGenerationSheetEntry = entry
        audioGenerationProgressValue = nil
        audioGenerationPrewarmTask?.cancel()
        let voice = ttsCoordinator.voiceSelection(for: pendingAudioProviderID)
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
        let providerID = pendingAudioProviderID
        audioGenerationTask = Task {
            await processPendingAudioGeneration(for: entry, voiceName: voiceName, providerID: providerID)
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
        pendingAudioProviderID = .kokoro
        audioGenerationProgressValue = nil
    }

    @MainActor
    private func processPendingAudioGeneration(for entry: LibraryEntry, voiceName: String, providerID: ReaderTTSProviderID) async {
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

        let voiceOptions = ttsCoordinator.availableVoiceOptions(for: providerID)
        guard let voice = voiceOptions.first(where: { $0.voiceName == voiceName }) else {
            pendingAudioGenerationEntry = nil
            audioGenerationAlertMessage = "The selected voice could not be found."
            return
        }

        do {
            let audioFileURL = try await LibraryAudioGenerationService.shared.generateAudioFile(
                from: normalizedTextFileURL,
                entryTitle: entry.title,
                voice: voice,
                destinationDirectoryURL: normalizedTextFileURL.deletingLastPathComponent(),
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
            entry.generatedAudioDurationSeconds = await generatedAudioDurationSeconds(for: audioFileURL)
            entry.generatedAudioPlaybackPositionSeconds = 0
            try? modelContext.save()

            pendingAudioGenerationEntry = nil
            pendingAudioVoiceName = KokoroVoiceCatalog.defaultVoiceName
            pendingAudioProviderID = .kokoro
            successToastMessage = "\(entry.title) audio file is ready."
            playSuccessTone()
        } catch is CancellationError {
            pendingAudioGenerationEntry = nil
            pendingAudioVoiceName = KokoroVoiceCatalog.defaultVoiceName
            pendingAudioProviderID = .kokoro
            audioGenerationProgressValue = nil
        } catch {
            pendingAudioGenerationEntry = nil
            pendingAudioVoiceName = KokoroVoiceCatalog.defaultVoiceName
            pendingAudioProviderID = .kokoro
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

        if activeGeneratedAudioEntry?.persistentModelID == entry.persistentModelID {
            stopGeneratedAudioPlayback()
        }

        if let audioURL = entry.generatedAudioFileURL {
            try? FileManager.default.removeItem(at: audioURL)
        }

        entry.generatedAudioFilePath = nil
        entry.generatedAudioFileName = nil
        entry.generatedAudioVoiceName = nil
        entry.generatedAudioUpdatedAt = nil
        entry.generatedAudioPlaybackPositionSeconds = nil
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
    private func cancelSummaryGenerationIfNeeded(for entry: LibraryEntry) {
        guard isEntrySummarizing(entry) else { return }

        summaryGenerationTask?.cancel()
        summaryGenerationTask = nil
        pendingSummaryEntry = nil
        summaryGenerationSuccess = nil
        summarySuccessEntry = nil
        summaryGenerationAlertMessage = nil
        endIdleSleepAssertion(for: .summarizing)
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
        case .summarizing:
            if summaryGenerationAwakeAssertion != nil { return }
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled],
                reason: "Summarizing file"
            )
            summaryGenerationAwakeAssertion = activity
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
        case .summarizing:
            guard let activity = summaryGenerationAwakeAssertion else { return }
            ProcessInfo.processInfo.endActivity(activity)
            summaryGenerationAwakeAssertion = nil
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
        playLibraryEntry(entry)
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

    private func playbackResumeProgress(for entry: LibraryEntry, textFileURL: URL? = nil, duration: Int) -> Double {
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

    private func estimatedPlaybackDuration(for normalizedText: String) -> Int {
        max(600, min(10800, normalizedText.isEmpty ? 1800 : max(600, normalizedText.count / 12)))
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
