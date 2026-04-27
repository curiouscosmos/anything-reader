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
    @State private var newCategoryName = ""
    @State private var pastedTitle = ""
    @State private var pastedText = ""
    @State private var uploadAlertMessage: String?
    @State private var importFailureMessage: String?
    @State private var processingImportMessage = ""
    @State private var successToastMessage: String?
    @State private var isProcessingImport = false
    @State private var pendingImportContext: PendingImportContext?
    @State private var playbackState = PlaybackState()
    @State private var activeEntry: LibraryEntry?
    @State private var playbackTask: Task<Void, Never>?
    @State private var didCleanupGeneratedContent = false
    @State private var coverArtGenerationKeys: Set<String> = []
    @State private var didBackfillMissingCoverArt = false
    @State private var didPresentKokoroDownloadGate = false
    @StateObject private var kokoroModelStore = KokoroModelStore.shared
    @StateObject private var kokoroSpeechService = KokoroSpeechService.shared

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
            ReaderPlayerBarView(
                playbackState: $playbackState,
                preferredMode: preferredMode,
                onToggleRepeat: toggleRepeat,
                onRewind: rewindPlayback,
                onTogglePlayPause: togglePlayback,
                onFastForward: fastForwardPlayback
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
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
        .preferredColorScheme(preferredMode.colorScheme)
        .tint(.green)
        .overlay {
            if isProcessingImport {
                ReaderProcessingOverlayView(message: processingImportMessage)
            }
        }
        .overlay(alignment: .top) {
            if let successToastMessage {
                ReaderToastView(message: successToastMessage)
                    .padding(.top, 16)
            }
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

    private func playKokoroVoiceSample(_ voice: KokoroVoiceOption) {
        kokoroSpeechService.prepareForPlayback()
        kokoroSpeechService.playSample(for: voice)
        successToastMessage = "Playing \(voice.displayName) sample"
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
        let sortedRecent = entries.sorted { $0.lastOpened > $1.lastOpened }

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ReaderTopBarView(
                    searchText: $searchText,
                    onHome: { selection = .home },
                    onPasteText: { isShowingPasteSheet = true },
                    onUploadFile: { isShowingFileImporter = true },
                    onSettings: { isShowingSettings = true },
                    tint: ReaderStyle.accentColor(named: "emerald"),
                    preferredMode: preferredMode
                )

                switch selection {
                case .home:
                    ReaderHeroView(
                        featured: sortedRecent.first,
                        preferredMode: preferredMode,
                        kokoroModelStatus: kokoroModelStore.status,
                        onPasteText: { isShowingPasteSheet = true },
                        onOpenLibrary: { selection = .recent },
                        onDownloadKokoro: openKokoroDownloadModal
                    )

                    ReaderLibrarySectionView(
                        title: "Recently Played",
                        subtitle: "Jump back into what you were listening to",
                        entries: Array(sortedRecent.prefix(8)),
                        categories: categories,
                        coverArtGenerationKeys: coverArtGenerationKeys,
                        preferredMode: preferredMode,
                        onPlay: startPlayback(for:),
                        onView: openLibraryEntry,
                        onRevealLocation: revealLibraryEntryLocation,
                        onClearCategory: { assign($0, to: nil) },
                        onAssignCategory: { assign($0, to: $1) },
                        onDelete: deleteEntry
                    )

                    ReaderLibrarySectionView(
                        title: "Library",
                        subtitle: "Everything you have imported or pasted",
                        entries: sortedRecent,
                        categories: categories,
                        coverArtGenerationKeys: coverArtGenerationKeys,
                        preferredMode: preferredMode,
                        onPlay: startPlayback(for:),
                        onView: openLibraryEntry,
                        onRevealLocation: revealLibraryEntryLocation,
                        onClearCategory: { assign($0, to: nil) },
                        onAssignCategory: { assign($0, to: $1) },
                        onDelete: deleteEntry
                    )

                case .recent:
                    ReaderLibrarySectionView(
                        title: "Recently Played",
                        subtitle: "Your last opened books and pasted text",
                        entries: sortedRecent,
                        categories: categories,
                        coverArtGenerationKeys: coverArtGenerationKeys,
                        preferredMode: preferredMode,
                        onPlay: startPlayback(for:),
                        onView: openLibraryEntry,
                        onRevealLocation: revealLibraryEntryLocation,
                        onClearCategory: { assign($0, to: nil) },
                        onAssignCategory: { assign($0, to: $1) },
                        onDelete: deleteEntry
                    )

                case .category(let categoryName):
                    ReaderLibrarySectionView(
                        title: categoryName,
                        subtitle: "All books filed into this category",
                        entries: sortedRecent,
                        categories: categories,
                        coverArtGenerationKeys: coverArtGenerationKeys,
                        preferredMode: preferredMode,
                        onPlay: startPlayback(for:),
                        onView: openLibraryEntry,
                        onRevealLocation: revealLibraryEntryLocation,
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
                    || entry.sourceText.lowercased().contains(query)
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
        let generatedSourceSnippets: Set<String> = [
            "Demo PDF placeholder content.",
            "Demo ePub placeholder content.",
            "Saved pasted text from the reader."
        ]

        let entriesToDelete = libraryEntries.filter { entry in
            generatedTitles.contains(entry.title)
                || generatedSubtitles.contains(entry.subtitle)
                || generatedCategoryNames.contains(entry.categoryName ?? "")
                || generatedSourceSnippets.contains(entry.sourceText)
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
            stopPlaybackTask()
            activeEntry = nil
            playbackState = PlaybackState()
        }

        removeAssociatedFiles(for: entry)

        Task {
            await PhonemeCacheService.shared.removeCache(for: entry)
        }

        modelContext.delete(entry)
        try? modelContext.save()
    }

    // MARK: - File Viewing

    private func openLibraryEntry(_ entry: LibraryEntry) {
        guard let storedPath = entry.storedFilePath else {
            uploadAlertMessage = "This item does not have a stored file path."
            return
        }

        let fileURL = URL(fileURLWithPath: storedPath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            uploadAlertMessage = "The stored file could not be found on disk."
            return
        }

        if !NSWorkspace.shared.open(fileURL) {
            uploadAlertMessage = "The file could not be opened."
        }
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

        let normalizedText = TextNormalizationService.normalize(trimmedText)
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
            sourceText: normalizedText,
            phonemeText: nil,
            phonemeUpdatedAt: nil,
            progress: 0.04,
            lastOpened: .now
        )

        modelContext.insert(pastedEntry)
        try? modelContext.save()
        cachePhonemesInBackground(for: pastedEntry, text: normalizedText)

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
            Task { await beginImport(from: sourceURL) }
        case .failure(let error):
            uploadAlertMessage = error.localizedDescription
        }
    }

    @MainActor
    private func beginImport(from sourceURL: URL) async {
        do {
            let stagedURL = try stageImportedFile(from: sourceURL)
            pendingImportContext = PendingImportContext(
                sourceURL: sourceURL,
                stagedURL: stagedURL,
                fileName: sourceURL.lastPathComponent,
                fileExtension: stagedURL.pathExtension.lowercased(),
                sourceKind: readerSourceKind(for: stagedURL.pathExtension),
                createdFileURLs: [stagedURL]
            )
            isProcessingImport = true
            processingImportMessage = "Normalizing \(sourceURL.lastPathComponent)…"

            await processPendingImport()
        } catch {
            uploadAlertMessage = error.localizedDescription
            cleanupPendingImportArtifacts()
        }
    }

    private func processPendingImport() async {
        guard let context = await MainActor.run(body: { pendingImportContext }) else { return }

        do {
            let ingest = try await DocumentIngestService.shared.process(
                stagedFileURL: context.stagedURL,
                fileExtension: context.fileExtension,
                originalFileName: context.fileName
            )

            await MainActor.run {
                pendingImportContext?.createdFileURLs.append(ingest.normalizedTextFileURL)
                processingImportMessage = "Saving \(context.fileName)…"
            }

            let entry = LibraryEntry(
                title: ingest.title ?? sanitizedTitle(from: context.sourceURL.deletingPathExtension().lastPathComponent),
                subtitle: "Normalized \(ingest.sourceKind.displayName) file ready to play.",
                sourceKind: ingest.sourceKind,
                fileExtension: context.fileExtension,
                originalFileName: context.fileName,
                storedFilePath: context.stagedURL.path,
                normalizedTextFilePath: ingest.normalizedTextFileURL.path,
                coverImageFilePath: nil,
                fileSizeBytes: ingest.fileSizeBytes,
                categoryName: nil,
                avatarSymbolName: avatarSymbol(for: ingest.sourceKind),
                accentName: Self.accentPalette.randomElement() ?? "emerald",
                sourceText: ingest.normalizedText,
                phonemeText: nil,
                phonemeUpdatedAt: nil,
                progress: 0,
                lastOpened: .now
            )

            modelContext.insert(entry)
            try modelContext.save()

            await MainActor.run {
                clearPendingImportState(showing: "\(entry.title) is ready to play.")
                queueCoverArtGenerationIfNeeded(for: entry)
            }

            cachePhonemesInBackground(for: entry, text: ingest.normalizedText)
        } catch {
            await MainActor.run {
                isProcessingImport = false
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
        Task { await processPendingImport() }
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
        pendingImportContext = nil
    }

    @MainActor
    private func clearPendingImportState(showing message: String?) {
        isProcessingImport = false
        processingImportMessage = ""
        pendingImportContext = nil

        if let message {
            successToastMessage = message
            Task {
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                await MainActor.run {
                    if successToastMessage == message {
                        successToastMessage = nil
                    }
                }
            }
        } else {
            successToastMessage = nil
        }
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
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let destinationURL = directoryURL.appendingPathComponent("\(UUID().uuidString)-\(baseName).\(extensionName)")

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    private func cachePhonemesInBackground(for entry: LibraryEntry, text: String) {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { return }

        Task.detached(priority: .utility) {
            if let cachedPhonemes = await PhonemeCacheService.shared.cachedPhonemes(for: entry),
               !cachedPhonemes.isEmpty {
                await MainActor.run {
                    self.applyPhonemeCache(cachedPhonemes, to: entry)
                }
                return
            }

            let phonemeText = await KokoroG2PService.shared.phonemize(normalizedText)
            guard !Task.isCancelled, !phonemeText.isEmpty else { return }

            await PhonemeCacheService.shared.store(phonemeText, for: entry)

            await MainActor.run {
                self.applyPhonemeCache(phonemeText, to: entry)
            }
        }
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

        Task.detached(priority: .utility) {
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
    private func startPlayback(for entry: LibraryEntry) {
        // Store the active record so progress updates persist to SwiftData.
        activeEntry = entry
        entry.lastOpened = .now

        let duration = max(600, min(10800, entry.sourceText.isEmpty ? 1800 : max(600, entry.sourceText.count / 12)))
        let elapsedSeconds = Int((Double(duration) * entry.progress).rounded())

        playbackState = PlaybackState(
            title: entry.title,
            subtitle: entry.subtitle,
            avatarSymbol: entry.avatarSymbolName,
            accentName: entry.accentName,
            progress: entry.progress,
            durationSeconds: duration,
            elapsedSeconds: elapsedSeconds,
            isPlaying: true
        )

        try? modelContext.save()
        startPlaybackTask()
    }

    @MainActor
    private func togglePlayback() {
        playbackState.isPlaying.toggle()

        if playbackState.isPlaying {
            startPlaybackTask()
        } else {
            stopPlaybackTask()
        }

        persistPlayerProgress()
    }

    @MainActor
    private func toggleRepeat() {
        playbackState.isRepeating.toggle()
    }

    @MainActor
    private func rewindPlayback() {
        playbackState.progress = max(0, playbackState.progress - 0.08)
        playbackState.elapsedSeconds = max(0, Int((Double(playbackState.durationSeconds) * playbackState.progress).rounded()))
        persistPlayerProgress()
    }

    @MainActor
    private func fastForwardPlayback() {
        playbackState.progress = min(1, playbackState.progress + 0.08)
        playbackState.elapsedSeconds = min(playbackState.durationSeconds, Int((Double(playbackState.durationSeconds) * playbackState.progress).rounded()))
        persistPlayerProgress()
    }

    @MainActor
    private func persistPlayerProgress() {
        activeEntry?.progress = playbackState.progress
        activeEntry?.lastOpened = .now
        try? modelContext.save()
    }

    @MainActor
    private func startPlaybackTask() {
        stopPlaybackTask()

        guard playbackState.isPlaying else { return }

        playbackTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)

                await MainActor.run {
                    guard playbackState.isPlaying else { return }

                    if playbackState.elapsedSeconds >= playbackState.durationSeconds {
                        if playbackState.isRepeating {
                            playbackState.elapsedSeconds = 0
                            playbackState.progress = 0
                        } else {
                            playbackState.isPlaying = false
                            stopPlaybackTask()
                            persistPlayerProgress()
                            return
                        }
                    } else {
                        playbackState.elapsedSeconds += 1
                        playbackState.progress = Double(playbackState.elapsedSeconds) / Double(playbackState.durationSeconds)
                    }

                    persistPlayerProgress()
                }
            }
        }
    }

    @MainActor
    private func stopPlaybackTask() {
        playbackTask?.cancel()
        playbackTask = nil
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [LibraryEntry.self, ReaderCategory.self], inMemory: true)
}
