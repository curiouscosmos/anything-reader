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
    @AppStorage("supertonicVoiceName") private var supertonicVoiceName: String = SupertonicVoiceCatalog.defaultVoiceName

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
    @State private var isShowingRSSPushNotificationsPermissionSheet = false
    @AppStorage("didPromptForRSSPushNotificationsOnFirstLaunch") private var didPromptForRSSPushNotificationsOnFirstLaunch = false
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
    @State private var pendingImportTask: Task<Void, Never>?
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
    @StateObject private var supertonicModelStore = SupertonicModelStore.shared
    @StateObject private var kokoroSpeechService = KokoroSpeechService.shared
    @StateObject private var moonshineSpeechService = MoonshineSpeechService.shared
    @StateObject private var supertonicSpeechService = SupertonicSpeechService.shared
    @StateObject private var ttsCoordinator = ReaderTTSCoordinator.shared
    @StateObject private var readerPlaybackService = ReaderPlaybackService.shared
    @StateObject private var generatedAudioPlaybackService = GeneratedAudioPlaybackService.shared
    @StateObject private var audioMixerPlaybackService = AudioMixerPlaybackService.shared
    @StateObject private var audioMixerLibraryService = AudioMixerLibraryService.shared
    @StateObject private var rssFeedRefreshService = RSSFeedRefreshService.shared
    @StateObject private var appUpdateChecker = AppUpdateChecker.shared
    @State private var translationCoordinator = DocumentTranslationCoordinator()

    private var categoryDeletionDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingCategoryDeletionName != nil },
            set: { isPresented in
                if !isPresented {
                    pendingCategoryDeletionName = nil
                }
            }
        )
    }

    private var documentTranslationOverlay: some View {
        DocumentTranslationHostView(coordinator: translationCoordinator)
    }

    private func performStartupTasks() async {
        cleanupGeneratedDemoContentIfNeeded()
        backfillMissingCoverArtIfNeeded()
        backfillCategoryIconsIfNeeded()
        await backfillGeneratedAudioMetadataIfNeeded()
        audioMixerLibraryService.loadIfNeeded(using: modelContext)
        audioMixerLibraryService.repairLibraryIfNeeded(using: modelContext)
        validateSelectedTTSConfiguration()
        ttsCoordinator.refreshInstallationStatus()
        promptForTTSDownloadIfNeeded()
    }

    private func performBrowserStartupTasks() async {
        do {
            try await BrowserNativeMessagingService.shared.installHostIfNeeded()
        } catch {
            browserHostInstallAlertMessage = "Chrome manifest install failed: \(error.localizedDescription)"
        }
        await monitorBrowserInbox()
    }

    private func confirmCategoryDeletion() {
        if let categoryName = pendingCategoryDeletionName {
            deleteCategory(named: categoryName)
        }
        pendingCategoryDeletionName = nil
    }

    private func cancelCategoryDeletion() {
        pendingCategoryDeletionName = nil
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

    private static let categoryIconPalette = [
        "folder.fill",
        "bookmark.fill",
        "tag.fill",
        "books.vertical.fill",
        "doc.text.fill",
        "sparkles",
        "star.fill",
        "tray.full.fill",
        "note.text",
        "rectangle.stack.fill",
        "paperclip",
        "folder.badge.plus"
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
        let shouldSummarize: Bool
        let importCategoryName: String?
        var createdFileURLs: [URL]
    }

    private struct SummaryGenerationSuccess: Identifiable {
        let id = UUID()
        let title: String
    }

    var body: some View {
        ZStack {
            ReaderBackgroundView(preferredMode: preferredMode)

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
        .buttonStyle(ReaderPointerCursorButtonStyle())
        .task {
            await promptForRSSPushNotificationsIfNeededOnLaunch()
        }
        .task {
            await observeRSSFeedNavigationRequests()
        }
        .task {
            await handlePendingSidebarSelection()
        }
        .task {
            // Prime the mixer library at launch so reader playback can follow the
            // selected track before the Audio Mixer screen has been visited.
            audioMixerLibraryService.loadIfNeeded(using: modelContext)
            audioMixerLibraryService.repairLibraryIfNeeded(using: modelContext)
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
                    canRewind: summaryPlaybackActive ? false : ReaderPlaybackSupport.canNavigateReadingTarget(.backward, in: activeEntry, currentProgress: playbackState.progress),
                    canFastForward: summaryPlaybackActive ? false : ReaderPlaybackSupport.canNavigateReadingTarget(.forward, in: activeEntry, currentProgress: playbackState.progress),
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
                supertonicVoiceName: $supertonicVoiceName,
                ttsCoordinator: ttsCoordinator,
                isKokoroPlaying: kokoroSpeechService.isPlaying,
                isMoonshinePlaying: moonshineSpeechService.isPlaying,
                isSupertonicPlaying: supertonicSpeechService.isPlaying,
                onPlaySample: playTTSVoiceSample
            )
        }
        .sheet(isPresented: $isShowingKokoroDownloadModal) {
            ReaderTTSDownloadSheet(
                kokoroModelStore: kokoroModelStore,
                moonshineModelStore: moonshineModelStore,
                supertonicModelStore: supertonicModelStore,
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
        .sheet(isPresented: $isShowingRSSPushNotificationsPermissionSheet) {
            RSSPushNotificationsPermissionSheet(
                preferredMode: preferredMode,
                onClose: {
                    isShowingRSSPushNotificationsPermissionSheet = false
                }
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
                providerID: pendingAudioProviderID,
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
            if isProcessingImport, pendingImportContext?.shouldSummarize == true {
                ReaderImportLoadingOverlayView(
                    message: "Summarizing file...",
                    subtitle: "This can take a few minutes.",
                    onCancel: discardPendingImport
                )
            } else if readerPlaybackService.isBufferingFirstChunk {
                ReaderPlaybackLoadingOverlayView(message: "Preparing first chunk", subtitle: "This only takes a few seconds")
            }
        }
        .overlay(alignment: .top) {
            if let successToastMessage {
                ReaderToastView(message: successToastMessage)
                    .padding(.top, 16)
            }
        }
        .overlay(documentTranslationOverlay)
        .categoryDeletionConfirmationDialog(
            isPresented: categoryDeletionDialogBinding,
            onDelete: confirmCategoryDeletion,
            onCancel: cancelCategoryDeletion
        )
        .task {
            await performStartupTasks()
        }
        .task {
            await performBrowserStartupTasks()
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
        .onChange(of: supertonicModelStore.status) { _, _ in
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
        .onChange(of: supertonicVoiceName) { _, newValue in
            ttsCoordinator.setSelectedVoiceName(newValue, for: .supertonic)
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

    private func validateSelectedTTSConfiguration() {
        let kokoroNames = Set(KokoroVoiceCatalog.allVoices.map(\.voiceName))
        if !kokoroNames.contains(kokoroVoiceName) {
            kokoroVoiceName = KokoroVoiceCatalog.defaultVoiceName
        }

        let moonshineNames = Set(MoonshineVoiceCatalog.allVoices.map(\.voiceName))
        if !moonshineNames.contains(moonshineVoiceName) {
            moonshineVoiceName = MoonshineVoiceCatalog.defaultVoiceName
        }

        let supertonicNames = Set(SupertonicVoiceCatalog.allVoices.map(\.voiceName))
        if !supertonicNames.contains(supertonicVoiceName) {
            supertonicVoiceName = SupertonicVoiceCatalog.defaultVoiceName
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

        if !kokoroModelStore.isInstalled && !moonshineModelStore.isInstalled && !supertonicModelStore.isInstalled {
            isShowingKokoroDownloadModal = true
        }
    }

    private func openKokoroDownloadModal() {
        isShowingKokoroDownloadModal = true
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
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
                        let sortedByDateAdded = sortedLibraryEntries(for: .home, keyPath: \.createdAt)
                        homeContent(
                            featured: sortedByDateAdded.first,
                            sortedByDateAdded: sortedByDateAdded
                        )

                    case .recent:
                        let sortedByRecentlyPlayed = sortedLibraryEntries(for: .recent, keyPath: \.lastOpened)
                        ReaderLibrarySectionView(
                            title: "Recently Played",
                            subtitle: "Your most recent played items",
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
                            },
                            onRequestPushNotificationsPermission: {
                                isShowingRSSPushNotificationsPermissionSheet = true
                            }
                            )

                    case .category(let categoryName):
                        let sortedByDateAdded = sortedLibraryEntries(for: selection, keyPath: \.createdAt)
                        ReaderLibrarySectionView(
                            title: categoryName,
                            subtitle: "",
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

    private func sortedLibraryEntries(
        for selection: SidebarSelection,
        keyPath: KeyPath<LibraryEntry, Date>
    ) -> [LibraryEntry] {
        filteredEntries(for: selection).sorted {
            $0[keyPath: keyPath] > $1[keyPath: keyPath]
        }
    }

    private func filteredEntries(for selection: SidebarSelection) -> [LibraryEntry] {
        guard selectionSupportsLibraryFiltering(selection) else { return [] }

        let query = activeSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return libraryEntries.filter { entry in
            matchesSelection(entry, selection: selection) && matchesSearch(entry, query: query)
        }
    }

    private func selectionSupportsLibraryFiltering(_ selection: SidebarSelection) -> Bool {
        switch selection {
        case .home, .recent, .category:
            return true
        case .freeBooks, .audioMixer, .rssFeeds:
            return false
        }
    }

    private func matchesSelection(_ entry: LibraryEntry, selection: SidebarSelection) -> Bool {
        switch selection {
        case .home, .recent:
            return true
        case .freeBooks:
            return true
        case .audioMixer, .rssFeeds:
            return false
        case .category(let categoryName):
            return entry.categoryName == categoryName
        }
    }

    private func matchesSearch(_ entry: LibraryEntry, query: String) -> Bool {
        guard !query.isEmpty else { return true }

        if entry.title.lowercased().contains(query) {
            return true
        }

        if entry.subtitle.lowercased().contains(query) {
            return true
        }

        if entry.fileExtension.lowercased().contains(query) {
            return true
        }

        if let categoryName = entry.categoryName?.lowercased(),
           categoryName.contains(query) {
            return true
        }

        guard let snippet = normalizedTextSnippet(for: entry)?.lowercased() else {
            return false
        }

        return snippet.contains(query)
    }

    @ViewBuilder
    private func homeContent(
        featured: LibraryEntry?,
        sortedByDateAdded: [LibraryEntry]
    ) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            if let notice = appUpdateChecker.notice {
                ReaderUpdateBannerView(
                    notice: notice,
                    onDownload: { appUpdateChecker.openAppStore() }
                )
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

            if !rssFeedRefreshService.feedItems.isEmpty {
                RSSHomeTickerView(
                    feedItems: rssFeedRefreshService.feedItems,
                    preferredMode: preferredMode,
                    onOpenArticle: { item in
                        guard let url = item.linkURL ?? URL(string: item.linkURLString) else { return }
                        NSWorkspace.shared.open(url)
                    },
                    onReadAloud: { item in
                        do {
                            try await prepareRSSArticleReadAloudImport(from: item)
                        } catch {
                            await MainActor.run {
                                browserImportAlertMessage = error.localizedDescription
                            }
                        }
                    }
                )
            }

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
                ReaderHomeDropOverlayView()
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 110)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isHomeDropTargeted, perform: handleDroppedFiles)
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
            accentName: Self.accentPalette.randomElement() ?? "emerald",
            iconName: Self.categoryIconPalette.randomElement() ?? "folder.fill"
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
            if existingCategory.iconName.isEmpty {
                existingCategory.iconName = Self.categoryIconPalette.randomElement() ?? "folder.fill"
                try? modelContext.save()
            }
            return existingCategory
        }

        let category = ReaderCategory(
            name: categoryName,
            accentName: Self.accentPalette.randomElement() ?? "emerald",
            iconName: Self.categoryIconPalette.randomElement() ?? "folder.fill"
        )
        modelContext.insert(category)
        try? modelContext.save()
        return category
    }

    @MainActor
    private func backfillCategoryIconsIfNeeded() {
        var didUpdateCategories = false

        for category in categories where category.iconName.isEmpty {
            category.iconName = Self.categoryIconPalette.randomElement() ?? "folder.fill"
            didUpdateCategories = true
        }

        if didUpdateCategories {
            try? modelContext.save()
        }
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

        return try? ReaderImportSupport.uploadedFilesDirectory()
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
            fileName: ReaderImportSupport.sanitizedStorageFileName(for: resolvedTitle),
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

        let resolvedTitle = ReaderImportSupport.browserTitle(for: message, existingEntries: libraryEntries)

        Task { @MainActor in
            do {
                let tempURL = try ReaderImportSupport.createTemporaryBrowserTextFile(
                    title: resolvedTitle,
                    text: trimmedText
                )
                defer {
                    try? FileManager.default.removeItem(at: tempURL)
                }

                await preparePendingImport(
                    from: tempURL,
                    shouldAutoPlay: true,
                    shouldSummarize: message.summarize == true,
                    showImportLanguageSheet: false,
                    importCategoryName: ReaderImportSupport.browserCategoryName(for: message)
                )
            } catch {
                browserImportAlertMessage = error.localizedDescription
            }
        }
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
        shouldSummarize: Bool = false,
        showImportLanguageSheet: Bool = true,
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
                sourceKind: ReaderImportSupport.readerSourceKind(for: fileExtension),
                shouldAutoPlay: shouldAutoPlay,
                shouldSummarize: shouldSummarize,
                importCategoryName: importCategoryName,
                createdFileURLs: [stagedURL]
            )
            isTranslateDocument = false
            translateToLanguage = .english
            if showImportLanguageSheet {
                isProcessingImport = true
                processingImportMessage = "Preparing import options…"
                isProcessingImport = false
                isShowingImportLanguageSheet = true
            } else {
                isShowingImportLanguageSheet = false
                isProcessingImport = true
                processingImportMessage = shouldSummarize ? "Summarizing file..." : "Preparing import..."
                beginIdleSleepAssertion(for: shouldSummarize ? .summarizing : .importing)
                createPendingImportEntry()

                let selectedLanguage = pendingDocumentLanguage
                pendingImportTask = Task { @MainActor in
                    await processPendingImport(documentLanguage: selectedLanguage)
                }
            }
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
            let tempURL = try ReaderImportSupport.createTemporaryRSSArticleFile(from: draft)
            defer {
                try? FileManager.default.removeItem(at: tempURL)
            }

            await preparePendingImport(from: tempURL, shouldAutoPlay: true, importCategoryName: "RSS Feed")
        } catch {
            audioMixerPlaybackService.endReaderPlaybackTransition()
            throw error
        }
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
        guard ReaderImportSupport.isSupportedUploadFileExtension(fileExtension) else {
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
        pendingImportTask = Task { @MainActor in
            await processPendingImport(documentLanguage: selectedLanguage)
        }
    }

    @MainActor
    private func processPendingImport(documentLanguage: TextLanguage) async {
        guard let context = pendingImportContext else { return }
        guard let placeholderEntry = pendingImportEntry else { return }
        defer {
            pendingImportTask = nil
            endIdleSleepAssertion(for: context.shouldSummarize ? .summarizing : .importing)
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

            if context.shouldSummarize {
                await MainActor.run {
                    processingImportMessage = "Summarizing file..."
                }

                let sourceLanguage = draft.detectedLanguage
                let summarizedText = try await FileSummarizationService.shared.summarize(
                    text: draft.rawText,
                    language: sourceLanguage
                )
                try Task.checkCancellation()
                finalText = summarizedText
                normalizedLanguage = sourceLanguage
            } else if shouldTranslate {
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

            placeholderEntry.title = ingest.title ?? ReaderImportSupport.sanitizedTitle(from: context.sourceURL.deletingPathExtension().lastPathComponent)
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
            placeholderEntry.avatarSymbolName = ReaderImportSupport.avatarSymbol(for: ingest.sourceKind)
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
                    pendingImportTask = nil
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
                pendingImportTask = nil
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
        pendingImportTask = Task { @MainActor in
            await processPendingImport(documentLanguage: pendingDocumentLanguage)
        }
    }

    @MainActor
    private func discardPendingImport() {
        pendingImportTask?.cancel()
        pendingImportTask = nil
        cleanupPendingImportArtifacts()
        audioMixerPlaybackService.endReaderPlaybackTransition()
        clearPendingImportState(showing: nil)
    }

    @MainActor
    private func cleanupPendingImportArtifacts() {
        guard let context = pendingImportContext else { return }
        let fileManager = FileManager.default
        let shouldSummarize = context.shouldSummarize
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
        pendingImportTask = nil
        detectedDocumentLanguage = .english
        pendingDocumentLanguage = .english
        isShowingImportLanguageSheet = false
        isProcessingImport = false
        processingImportMessage = ""
        endIdleSleepAssertion(for: shouldSummarize ? .summarizing : .importing)
    }

    @MainActor
    private func clearPendingImportState(showing message: String?) {
        let shouldSummarize = pendingImportContext?.shouldSummarize ?? false
        isProcessingImport = false
        processingImportMessage = ""
        pendingImportContext = nil
        pendingImportEntry = nil
        pendingImportTask = nil
        translationCoordinator.cancel()
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

        endIdleSleepAssertion(for: shouldSummarize ? .summarizing : .importing)
    }

    private var isImportInFlight: Bool {
        isProcessingImport || pendingImportContext != nil
    }

    @MainActor
    private func createPendingImportEntry() {
        guard let context = pendingImportContext, pendingImportEntry == nil else { return }

        let placeholder = LibraryEntry(
            title: ReaderImportSupport.sanitizedTitle(from: context.sourceURL.deletingPathExtension().lastPathComponent),
            subtitle: "Importing…",
            sourceKind: context.sourceKind,
            fileExtension: context.fileExtension,
            originalFileName: context.fileName,
            storedFilePath: context.stagedURL.path,
            normalizedTextFilePath: nil,
            coverImageFilePath: nil,
            fileSizeBytes: 0,
            categoryName: nil,
            avatarSymbolName: ReaderImportSupport.avatarSymbol(for: context.sourceKind),
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
        guard ReaderImportSupport.isSupportedUploadFileExtension(extensionName) else {
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

        let directoryURL = try ReaderImportSupport.makeUploadDirectory(for: sourceURL)
        let baseName = ReaderImportSupport.sanitizedImportedFileBaseName(from: sourceURL)
        let destinationURL = directoryURL.appendingPathComponent("\(baseName).\(extensionName)")

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return (destinationURL, directoryURL)
    }

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
        let directoryURL = try ReaderImportSupport.uploadedFilesDirectory()
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
            resolvedDirectoryURL = try ReaderImportSupport.uploadedFilesDirectory()
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
        let rootDirectory = try ReaderImportSupport.uploadedFilesDirectory()
        let timestamp = ReaderImportSupport.importTimestampString()
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
        persistProgress: Bool = true,
        startingChunkIndexOverride: Int? = nil
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
        let duration = ReaderPlaybackSupport.estimatedPlaybackDuration(for: normalizedText)
        let isSummaryPlayback = textFileURL?.path == entry.summarizedTextFileURL?.path
        let resumeProgress = persistProgress
            ? ReaderPlaybackSupport.playbackResumeProgress(for: entry, textFileURL: textFileURL, duration: duration)
            : 0
        let resumeTargetIndex = persistProgress && !isSummaryPlayback
            ? (entry.currentReadingPositionIndex ?? ReaderPlaybackSupport.readingPositionIndex(for: entry, progress: resumeProgress))
            : nil
        let chunks = ReaderPlaybackChunkService.chunks(for: entry, textFileURL: textFileURL)
        let startingChunkIndex = startingChunkIndexOverride
            ?? resumeTargetIndex.flatMap { ReaderPlaybackChunkService.chunkIndex(for: $0, in: entry) }
            ?? ReaderPlaybackChunkService.chunkIndex(for: resumeProgress, chunkCount: chunks.count)
        
//        if resumeTargetIndex != nil {
//            print("Anything Reader resumeTargetIndex -> '\(resumeTargetIndex)': \(startingChunkIndex)")
//        }

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
            readingPositionText: displayTitle ?? entry.currentReadingPositionDisplayText ?? ReaderPlaybackSupport.readingPositionText(for: entry, progress: resumeProgress),
            readingPositionOverrideText: nil,
            readingPositionIndexOverride: persistProgress && !isSummaryPlayback ? (entry.currentReadingPositionIndex ?? ReaderPlaybackSupport.readingPositionIndex(for: entry, progress: resumeProgress)) : nil,
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
        print("Playing file now ->")
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

        let newProgress = ReaderPlaybackSupport.readingProgress(for: target, in: entry)
        let explicitReadingPositionText = ReaderPlaybackSupport.readingPositionText(for: entry, targetIndex: target.index)
        let startingChunkIndex = ReaderPlaybackChunkService.chunkIndex(for: target.index, in: entry)
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
        startPlayback(
            for: entry,
            startingChunkIndexOverride: startingChunkIndex
        )
    }

    @MainActor
    private func scheduleReadingTargetNavigation(_ direction: PlaybackNavigationDirection) {
        guard let entry = activeEntry, ReaderPlaybackSupport.canNavigateReadingTarget(direction, in: entry, currentProgress: playbackState.progress) else { return }

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
            guard let target = ReaderPlaybackSupport.adjacentReadingTarget(for: direction, in: currentEntry, currentProgress: playbackState.progress) else { return }

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
            let targetIndex = ReaderPlaybackSupport.readingPositionIndex(for: entry, chunkIndex: update.chunkIndex)
                ?? ReaderPlaybackSupport.readingPositionIndex(for: entry, progress: update.progress)
            playbackState.readingPositionIndexOverride = targetIndex
            playbackState.readingPositionTotalCount = entry.readingJumpTargets.isEmpty ? nil : entry.readingJumpTargets.count
            playbackState.readingPositionText = targetIndex.flatMap {
                ReaderPlaybackSupport.readingPositionText(for: entry, targetIndex: $0)
            } ?? ReaderPlaybackSupport.readingPositionText(for: entry, progress: update.progress)
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

        let selectedProviderID = ReaderTTSProviderID(rawValue: activeTTSProviderIDRawValue) ?? ttsCoordinator.activeProviderID
        pendingAudioGenerationEntry = entry
        pendingAudioProviderID = selectedProviderID
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
                language: entry.textLanguage,
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

    private func syncReadingPositionState(for entry: LibraryEntry?, progress: Double, chunkIndex: Int? = nil) {
        guard let entry else { return }

        let totalCount = entry.readingJumpTargets.isEmpty ? nil : entry.readingJumpTargets.count
        let index = chunkIndex.flatMap { ReaderPlaybackSupport.readingPositionIndex(for: entry, chunkIndex: $0) }
            ?? playbackState.readingPositionIndexOverride
            ?? entry.currentReadingPositionIndex
            ?? ReaderPlaybackSupport.readingPositionIndex(for: entry, progress: progress)

        entry.currentReadingPositionIndex = index
        entry.currentReadingPositionTotalCount = totalCount
        playbackState.readingPositionIndexOverride = index
        playbackState.readingPositionTotalCount = totalCount
        playbackState.readingPositionText = entry.currentReadingPositionDisplayText ?? ReaderPlaybackSupport.readingPositionText(for: entry, progress: progress)
        playbackState.readingPositionOverrideText = nil
    }

    private func cancelReadingNavigationTask() {
        readingNavigationTask?.cancel()
        readingNavigationTask = nil
    }

    @MainActor
    private func promptForRSSPushNotificationsIfNeededOnLaunch() async {
        guard !didPromptForRSSPushNotificationsOnFirstLaunch else { return }
        didPromptForRSSPushNotificationsOnFirstLaunch = true

        let allowed = await RSSPushNotificationService.shared.canSendNotifications()
        guard !allowed else { return }

        isShowingRSSPushNotificationsPermissionSheet = true
    }

    @MainActor
    private func handlePendingSidebarSelection() async {
        let userDefaults = UserDefaults.standard
        guard let rawValue = userDefaults.string(forKey: "pendingSidebarSelection") else { return }
        userDefaults.removeObject(forKey: "pendingSidebarSelection")

        guard let selection = sidebarSelection(from: rawValue) else { return }
        self.selection = selection
    }

    private func sidebarSelection(from rawValue: String) -> SidebarSelection? {
        switch rawValue {
        case "home":
            return .home
        case "recent":
            return .recent
        case "freeBooks":
            return .freeBooks
        case "audioMixer":
            return .audioMixer
        case "rssFeeds":
            return .rssFeeds
        default:
            if rawValue.hasPrefix("category:") {
                return .category(String(rawValue.dropFirst("category:".count)))
            }
            return nil
        }
    }

    @MainActor
    private func observeRSSFeedNavigationRequests() async {
        for await _ in NotificationCenter.default.notifications(named: .navigateToRSSFeeds) {
            selection = .rssFeeds
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [LibraryEntry.self, ReaderCategory.self], inMemory: true)
}


private extension View {
    func categoryDeletionConfirmationDialog(
        isPresented: Binding<Bool>,
        onDelete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        confirmationDialog(
            "Delete Category?",
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Category", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel, action: onCancel)
        } message: {
            Text("This will remove the category from all library items that use it.")
        }
    }
}
