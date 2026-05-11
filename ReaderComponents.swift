//
//  ReaderComponents.swift
//  Anything Reader
//
//  Reusable SwiftUI building blocks for the main reader experience.
//

import AppKit
import SwiftData
import SwiftUI

// MARK: - Pointer Cursor
// Keeps the macOS pointer consistent across custom SwiftUI controls.
private struct ReaderPointerCursorModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.onHover { isHovering in
            if isHovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

struct ReaderPointerCursorButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.readerPointerCursor()
    }
}

extension View {
    @ViewBuilder
    func readerPointerCursor() -> some View {
        #if os(macOS)
        modifier(ReaderPointerCursorModifier())
        #else
        self
        #endif
    }
}

// MARK: - Sidebar
// Primary navigation for the app shell, including user-created categories.
struct ReaderSidebarView: View {
    let categories: [ReaderCategory]
    @Binding var selection: SidebarSelection
    let rssUnreadCount: Int
    let onAddCategory: () -> Void

    var body: some View {
        List(selection: $selection) {
            // Core navigation shortcuts.
            Section {
                Label("Home", systemImage: "house.fill")
                    .readerPointerCursor()
                    .tag(SidebarSelection.home)

                Label("Recently Played", systemImage: "clock.arrow.circlepath")
                    .readerPointerCursor()
                    .tag(SidebarSelection.recent)

                Label("Free Books", systemImage: "books.vertical.fill")
                    .readerPointerCursor()
                    .tag(SidebarSelection.freeBooks)

                Label("Audio Mixer", systemImage: "music.note.list")
                    .readerPointerCursor()
                    .tag(SidebarSelection.audioMixer)

                if rssUnreadCount > 0 {
                    Label("RSS Feed", systemImage: "dot.radiowaves.left.and.right")
                        .badge(rssUnreadCount)
                        .readerPointerCursor()
                        .tag(SidebarSelection.rssFeeds)
                } else {
                    Label("RSS Feed", systemImage: "dot.radiowaves.left.and.right")
                        .readerPointerCursor()
                        .tag(SidebarSelection.rssFeeds)
                }
            }

            // User-generated categories.
            if !categories.isEmpty {
                Section("Categories") {
                    ForEach(categories) { category in
                        Label(category.name, systemImage: category.iconName.isEmpty ? "folder.fill" : category.iconName)
                            .readerPointerCursor()
                            .tag(SidebarSelection.category(category.name))
                    }
                }
                .padding(.vertical, 8)
                .font(.system(size: 16))
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .navigationTitle("Anything Reader - Offline & Private Text to Speech")
        .toolbar {
            ToolbarItem {
                Button(action: onAddCategory) {
                    Label("New Category", systemImage: "plus")
                }
            }
        }
    }
}

// MARK: - Top Bar
// Global actions and search entry point shown above the library content.
struct ReaderTopBarView: View {
    @Binding var searchText: String
    let searchPlaceholder: String
    let onHome: () -> Void
    let onPasteText: () -> Void
    let onUploadFile: () -> Void
    let onSettings: () -> Void
    let tint: Color
    let preferredMode: AppearanceMode
    let isUploadDisabled: Bool

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onHome) {
                Label("Home", systemImage: "house.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.headline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .foregroundStyle(primaryTextColor)
                    .background(elevatedBackground, in: Capsule())
            }
            .buttonStyle(ReaderPointerCursorButtonStyle())
            .accessibilityIdentifier("topbar-home-button")

            searchField

            Button(action: onPasteText) {
                Label("Paste Text", systemImage: "doc.on.clipboard.fill")
                    .font(.headline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .foregroundStyle(primaryTextColor)
                    .background(tint.opacity(preferredMode == .light ? 0.14 : 0.20), in: Capsule())
            }
            .buttonStyle(ReaderPointerCursorButtonStyle())
            .accessibilityIdentifier("topbar-paste-text-button")

            Button(action: onUploadFile) {
                Label("Upload", systemImage: "arrow.up.doc.fill")
                    .font(.headline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .foregroundStyle(primaryTextColor)
                    .background(tint.opacity(preferredMode == .light ? 0.14 : 0.20), in: Capsule())
            }
            .buttonStyle(ReaderPointerCursorButtonStyle())
            .disabled(isUploadDisabled)
            .opacity(isUploadDisabled ? 0.45 : 1)
            .accessibilityIdentifier("topbar-upload-button")

            Button(action: onSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.headline)
                    .padding(12)
                    .foregroundStyle(primaryTextColor)
                    .background(elevatedBackground, in: Circle())
            }
            .buttonStyle(ReaderPointerCursorButtonStyle())
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("topbar-settings-button")
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(searchPlaceholder, text: $searchText)
                .textFieldStyle(.plain)
                .disableAutocorrection(true)
        }
        .padding(.horizontal, 14)
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(elevatedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var elevatedBackground: Color {
        switch preferredMode {
        case .light:
            return Color.black.opacity(0.05)
        case .dark, .system:
            return Color.white.opacity(0.08)
        }
    }

    private var primaryTextColor: Color {
        switch preferredMode {
        case .light:
            return .black
        case .dark, .system:
            return .white
        }
    }
}

// MARK: - Hero
// High-visibility home section that promotes the currently featured item.
struct ReaderHeroView: View {
    let featured: LibraryEntry?
    let preferredMode: AppearanceMode
    let kokoroModelStatus: KokoroModelStore.Status
    let onPasteText: () -> Void
    let onUploadFile: () -> Void
    let onOpenLibrary: () -> Void
    let onDownloadKokoro: () -> Void
    let isUploadDisabled: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            heroBackgroundImage

            VStack(alignment: .leading, spacing: 14) {
                Text("Listen to anything")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(heroPrimaryTextColor)

                Text("TTS, Translate, Summarize, & OCR - all on your Mac")
                    .font(.headline)
                    .foregroundStyle(heroSecondaryTextColor)
                    .frame(maxWidth: 800, alignment: .leading)

                HStack(spacing: 12) {
                    Button(action: onPasteText) {
                        Label("Paste Text", systemImage: "doc.on.clipboard")
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .foregroundStyle(heroPrimaryTextColor)
                            .background(heroButtonBackground, in: Capsule())
                    }
                    .buttonStyle(ReaderPointerCursorButtonStyle())
                    .accessibilityIdentifier("hero-paste-text-button")

                    Button(action: onUploadFile) {
                        Label("Upload", systemImage: "arrow.up.doc.fill")
                            .font(.headline)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .foregroundStyle(heroPrimaryTextColor)
                            .background(heroButtonBackground, in: Capsule())
                    }
                    .buttonStyle(ReaderPointerCursorButtonStyle())
                    .disabled(isUploadDisabled)
                    .opacity(isUploadDisabled ? 0.45 : 1)
                    .accessibilityIdentifier("hero-upload-button")
                    
                    Button(action: onDownloadKokoro) {
                        Label(kokoroButtonTitle, systemImage: kokoroButtonIcon)
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .foregroundStyle(heroPrimaryTextColor)
                            .background(kokoroButtonBackground, in: Capsule())
                    }
                    .buttonStyle(ReaderPointerCursorButtonStyle())
                    .disabled(kokoroButtonDisabled)
                    .accessibilityIdentifier("hero-download-tts-button")
                }

                Text(kokoroStatusMessage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(heroSecondaryTextColor)
            }
            .padding(28)

        }
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(heroBorderColor, lineWidth: 1)
        )
    }

    private var heroBackgroundImage: some View {
        ZStack(alignment: .trailing) {
            // Background fallback
            LinearGradient(
                colors: [
                        Color.black,
                        Color.black.opacity(0.8)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let image = bundledHeroImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 800) // control how much image shows
                    .frame(maxHeight: .infinity)
                    .clipped()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(heroTintOverlay)
    }

    private var heroTintOverlay: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(preferredMode == .light ? 0.01 : 0.01),
                Color.black.opacity(preferredMode == .light ? 0.01 : 0.01)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .blendMode(.multiply)
    }

    private var heroGradientColors: [Color] {
        switch preferredMode {
        case .light:
            return [
                Color(red: 0.90, green: 0.98, blue: 0.92),
                Color(red: 0.82, green: 0.95, blue: 0.87),
                Color(red: 0.76, green: 0.91, blue: 0.84)
            ]
        case .dark, .system:
            return [
                Color(red: 0.10, green: 0.42, blue: 0.24),
                Color(red: 0.06, green: 0.19, blue: 0.12),
                Color(red: 0.04, green: 0.18, blue: 0.25)
            ]
        }
    }

    private var bundledHeroImage: NSImage? {
        guard let url = Bundle.main.url(forResource: "hero_image", withExtension: "png") else {
            return nil
        }

        return NSImage(contentsOf: url)
    }

    private var heroPrimaryTextColor: Color {
        preferredMode == .light ? .black : .white
    }

    private var heroSecondaryTextColor: Color {
        preferredMode == .light ? Color.black.opacity(0.72) : Color.white.opacity(0.82)
    }

    private var heroButtonBackground: Color {
        Color.green.opacity(preferredMode == .light ? 0.4 : 0.5)
    }

    private var kokoroButtonBackground: Color {
        switch kokoroModelStatus {
        case .installed:
            return Color.green.opacity(preferredMode == .light ? 0.22 : 0.30)
        case .downloading:
            return Color.orange.opacity(preferredMode == .light ? 0.22 : 0.30)
        case .failed:
            return Color.red.opacity(preferredMode == .light ? 0.20 : 0.28)
        case .checking, .notInstalled:
            return heroButtonBackground
        }
    }

    private var kokoroButtonTitle: String {
        switch kokoroModelStatus {
        case .checking:
            return "Loading TTS..."
        case .notInstalled:
            return "Download TTS Modal"
        case .downloading:
            return "Downloading..."
        case .installed:
            return "TTS Ready"
        case .failed:
            return "Retry Download"
        }
    }

    private var kokoroButtonIcon: String {
        switch kokoroModelStatus {
        case .checking:
            return "clock"
        case .notInstalled:
            return "arrow.down.circle.fill"
        case .downloading:
            return "arrow.down.circle"
        case .installed:
            return "checkmark.seal.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    private var kokoroButtonDisabled: Bool {
        if case .checking = kokoroModelStatus { return true }
        if case .downloading = kokoroModelStatus { return true }
        return false
    }

    private var kokoroStatusMessage: String {
        switch kokoroModelStatus {
        case .checking:
            return "Checking whether a TTS model is already downloaded."
        case .notInstalled:
            return "Download one TTS model to unlock offline voice playback."
        case .downloading:
            return "The selected TTS model is downloading in the background."
        case .installed:
            return "A TTS model is ready for offline voice playback."
        case .failed(let message):
            return "TTS model download failed: \(message)"
        }
    }

    private var kokoroActiveModelMessage: String {
        switch kokoroModelStatus {
        case .checking:
            return "Active model: checking..."
        case .notInstalled:
            return "Active model: none installed"
        case .downloading(let option):
            return "Active model: downloading \(option.displayName)"
        case .installed(let option):
            return "Active model: \(option.displayName)"
        case .failed:
            return "Active model: unavailable"
        }
    }

    private var heroBorderColor: Color {
        preferredMode == .light ? Color.black.opacity(0.10) : Color.white.opacity(0.12)
    }
}

// Generic TTS hero that works across Kokoro and Moonshine.
struct ReaderTTSHeroView: View {
    let featured: LibraryEntry?
    let preferredMode: AppearanceMode
    let ttsStatus: ReaderTTSModelAvailability
    let activeProviderID: ReaderTTSProviderID
    let onPasteText: () -> Void
    let onUploadFile: () -> Void
    let onOpenLibrary: () -> Void
    let onDownloadTTS: () -> Void
    let isUploadDisabled: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            heroBackgroundImage

            VStack(alignment: .leading, spacing: 14) {
                if let image = bundledLogoImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 140, height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityHidden(true)
                }

                Text("Listen to anything")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(heroPrimaryTextColor)

                Text("TTS, Translate, Summarize, & OCR - all on your Mac")
                    .font(.headline)
                    .foregroundStyle(heroSecondaryTextColor)
                    .frame(maxWidth: 800, alignment: .leading)

                HStack(spacing: 12) {
                    Button(action: onPasteText) {
                        Label("Paste Text", systemImage: "doc.on.clipboard")
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .foregroundStyle(heroPrimaryTextColor)
                            .background(heroButtonBackground, in: Capsule())
                    }
                    .buttonStyle(ReaderPointerCursorButtonStyle())
                    .accessibilityIdentifier("hero-paste-text-button")

                    Button(action: onUploadFile) {
                        Label("Upload", systemImage: "arrow.up.doc.fill")
                            .font(.headline)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .foregroundStyle(heroPrimaryTextColor)
                            .background(heroButtonBackground, in: Capsule())
                    }
                    .buttonStyle(ReaderPointerCursorButtonStyle())
                    .disabled(isUploadDisabled)
                    .opacity(isUploadDisabled ? 0.45 : 1)
                    .accessibilityIdentifier("hero-upload-button")

                    Button(action: onDownloadTTS) {
                        Label(ttsButtonTitle, systemImage: ttsButtonIcon)
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .foregroundStyle(heroPrimaryTextColor)
                            .background(ttsButtonBackground, in: Capsule())
                    }
                    .buttonStyle(ReaderPointerCursorButtonStyle())
                    .disabled(ttsButtonDisabled)
                    .accessibilityIdentifier("hero-download-tts-button")
                }

                Text(ttsStatusMessage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(heroSecondaryTextColor)
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(heroBorderColor, lineWidth: 1)
        )
    }

    private var heroBackgroundImage: some View {
        ZStack(alignment: .trailing) {
            LinearGradient(
                colors: [
                    Color.black,
                    Color.black.opacity(0.8)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let image = bundledHeroImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 800)
                    .frame(maxHeight: .infinity)
                    .clipped()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(heroTintOverlay)
    }

    private var heroTintOverlay: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(preferredMode == .light ? 0.01 : 0.01),
                Color.black.opacity(preferredMode == .light ? 0.01 : 0.01)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .blendMode(.multiply)
    }

    private var bundledHeroImage: NSImage? {
        guard let url = Bundle.main.url(forResource: "hero_image", withExtension: "png") else {
            return nil
        }

        return NSImage(contentsOf: url)
    }

    private var bundledLogoImage: NSImage? {
        guard let url = Bundle.main.url(forResource: "logo", withExtension: "png") else {
            return nil
        }

        return NSImage(contentsOf: url)
    }

    private var heroPrimaryTextColor: Color {
        preferredMode == .light ? .black : .white
    }

    private var heroSecondaryTextColor: Color {
        preferredMode == .light ? Color.black.opacity(0.72) : Color.white.opacity(0.82)
    }

    private var heroButtonBackground: Color {
        Color.green.opacity(preferredMode == .light ? 0.4 : 0.5)
    }

    private var ttsButtonBackground: Color {
        switch ttsStatus {
        case .installed:
            return Color.green.opacity(preferredMode == .light ? 0.22 : 0.30)
        case .downloading:
            return Color.orange.opacity(preferredMode == .light ? 0.22 : 0.30)
        case .failed:
            return Color.red.opacity(preferredMode == .light ? 0.20 : 0.28)
        case .checking, .notInstalled:
            return heroButtonBackground
        }
    }

    private var ttsButtonTitle: String {
        switch ttsStatus {
        case .checking:
            return "Loading TTS..."
        case .notInstalled:
            return "Download TTS"
        case .downloading(let providerID):
            return "Downloading \(providerID.title)..."
        case .installed(let providerID):
            return "\(providerID.title) Ready"
        case .failed:
            return "Retry Download"
        }
    }

    private var ttsButtonIcon: String {
        switch ttsStatus {
        case .checking:
            return "clock"
        case .notInstalled:
            return "arrow.down.circle.fill"
        case .downloading:
            return "arrow.down.circle"
        case .installed:
            return "checkmark.seal.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    private var ttsButtonDisabled: Bool {
        if case .checking = ttsStatus { return true }
        if case .downloading = ttsStatus { return true }
        return false
    }

    private var ttsStatusMessage: String {
        switch ttsStatus {
        case .checking:
            return "Checking whether a TTS model is already downloaded."
        case .notInstalled:
            return "Download a TTS model to unlock offline voice playback."
        case .downloading(let providerID):
            return "\(providerID.title) is downloading in the background."
        case .installed(let providerID):
            return "\(providerID.title) is ready for offline voice playback."
        case .failed(let message):
            return "TTS model download failed: \(message)"
        }
    }

    private var activeModelMessage: String {
        switch ttsStatus {
        case .checking:
            return "Active model: checking..."
        case .notInstalled:
            return "Active model: none installed"
        case .downloading(let providerID):
            return "Active model: downloading \(providerID.title)"
        case .installed(let providerID):
            return "Active model: \(providerID.title)"
        case .failed:
            return "Active model: unavailable"
        }
    }

    private var heroBorderColor: Color {
        preferredMode == .light ? Color.black.opacity(0.10) : Color.white.opacity(0.12)
    }
}

// MARK: - Library Section
// Shared wrapper that renders a titled section and adaptive grid of cards.
struct ReaderLibrarySectionView: View {
    let title: String
    let subtitle: String
    let entries: [LibraryEntry]
    let visibleEntryCount: Int
    let isLoadingMore: Bool
    let onLoadMore: () async -> Void
    let categories: [ReaderCategory]
    let coverArtGenerationKeys: Set<String>
    let preferredMode: AppearanceMode
    let onDeleteCategory: (() -> Void)?
    let isEntryPlaying: (LibraryEntry) -> Bool
    let isEntryGeneratingAudio: (LibraryEntry) -> Bool
    let isEntrySummarizing: (LibraryEntry) -> Bool
    let isSummaryPlaying: (LibraryEntry) -> Bool
    let audioGenerationProgressFraction: (LibraryEntry) -> Double?
    let generatedAudioProgressFraction: (LibraryEntry) -> Double?
    let readingProgressFraction: (LibraryEntry) -> Double?
    let onPrimaryAction: (LibraryEntry) -> Void
    let onPlay: (LibraryEntry) -> Void
    let onPlaySummary: (LibraryEntry) -> Void
    let onSummarize: (LibraryEntry) -> Void
    let onCancelSummarization: (LibraryEntry) -> Void
    let onOpenOriginalFile: (LibraryEntry) -> Void
    let onViewTextFile: (LibraryEntry) -> Void
    let onRevealLocation: (LibraryEntry) -> Void
    let onGenerateAudio: (LibraryEntry) -> Void
    let onStopAudioGeneration: (LibraryEntry) -> Void
    let onDeleteAudio: (LibraryEntry) -> Void
    let onClearCategory: (LibraryEntry) -> Void
    let onAssignCategory: (LibraryEntry, String) -> Void
    let onDelete: (LibraryEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2.weight(.bold))
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if let onDeleteCategory {
                    Button(role: .destructive, action: onDeleteCategory) {
                        Label("Delete Category", systemImage: "trash")
                            .font(.headline)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }

            if entries.isEmpty {
                emptyStateCard
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 16)], spacing: 16) {
                    ForEach(visibleEntries) { entry in
                        ReaderLibraryCardView(
                            entry: entry,
                            categories: categories,
                            isCoverArtLoading: coverArtGenerationKeys.contains(entry.cacheIdentity),
                            preferredMode: preferredMode,
                            isPlaying: isEntryPlaying(entry),
                            isImporting: entry.isImporting,
                            isGeneratingAudio: isEntryGeneratingAudio(entry),
                            isLoading: entry.isImporting || isEntryGeneratingAudio(entry) || isEntrySummarizing(entry),
                            audioGenerationProgressFraction: audioGenerationProgressFraction(entry),
                            generatedAudioProgressFraction: generatedAudioProgressFraction(entry),
                            readingProgressFraction: readingProgressFraction(entry),
                            hasGeneratedAudio: entry.generatedAudioFileURL != nil,
                            hasSummarizedText: entry.hasSummarizedText,
                            isSummaryPlaying: isSummaryPlaying(entry),
                            isSummarizing: isEntrySummarizing(entry),
                            onPrimaryAction: { onPrimaryAction(entry) },
                            onPlay: { onPlay(entry) },
                            onPlaySummary: { onPlaySummary(entry) },
                            onSummarize: { onSummarize(entry) },
                            onCancelSummarization: { onCancelSummarization(entry) },
                            onOpenOriginalFile: { onOpenOriginalFile(entry) },
                            onViewTextFile: { onViewTextFile(entry) },
                            onRevealLocation: { onRevealLocation(entry) },
                            onGenerateAudio: { onGenerateAudio(entry) },
                            onStopAudioGeneration: { onStopAudioGeneration(entry) },
                            onDeleteAudio: { onDeleteAudio(entry) },
                            onClearCategory: { onClearCategory(entry) },
                            onAssignCategory: { categoryName in
                                onAssignCategory(entry, categoryName)
                            },
                            onDelete: { onDelete(entry) }
                        )
                    }
                }

                if entries.count > visibleEntries.count {
                    HStack {
                        Spacer()

                        Button {
                            Task {
                                await onLoadMore()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if isLoadingMore {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Loading...")
                                } else {
                                    Text("Load More")
                                }
                            }
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .frame(maxWidth: 120)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .disabled(isLoadingMore)

                        Spacer()
                    }
                    .padding(.top, 8)
                }
            }
        } // Add space at the bottom
        .padding(.bottom, 40)
    }

    private var visibleEntries: [LibraryEntry] {
        Array(entries.prefix(visibleEntryCount))
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No items yet")
                .font(.headline)
            Text("Use Paste Text, import a document, or create a category to start building your listening library.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(panelBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var panelBackground: Color {
        switch preferredMode {
        case .light:
            return Color(red: 0.985, green: 0.986, blue: 0.982)
        case .dark, .system:
            return Color(red: 0.08, green: 0.09, blue: 0.08)
        }
    }
}

// MARK: - Library Card
// Full-bleed card used for each book, file, or pasted note in the grid.
struct ReaderLibraryCardView: View {
    let entry: LibraryEntry
    let categories: [ReaderCategory]
    let isCoverArtLoading: Bool
    let preferredMode: AppearanceMode
    let isPlaying: Bool
    let isImporting: Bool
    let isGeneratingAudio: Bool
    let isLoading: Bool
    let audioGenerationProgressFraction: Double?
    let generatedAudioProgressFraction: Double?
    let readingProgressFraction: Double?
    let hasGeneratedAudio: Bool
    let hasSummarizedText: Bool
    let isSummaryPlaying: Bool
    let isSummarizing: Bool
    let onPrimaryAction: () -> Void
    let onPlay: () -> Void
    let onPlaySummary: () -> Void
    let onSummarize: () -> Void
    let onCancelSummarization: () -> Void
    let onOpenOriginalFile: () -> Void
    let onViewTextFile: () -> Void
    let onRevealLocation: () -> Void
    let onGenerateAudio: () -> Void
    let onStopAudioGeneration: () -> Void
    let onDeleteAudio: () -> Void
    let onClearCategory: () -> Void
    let onAssignCategory: (String) -> Void
    let onDelete: () -> Void

    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingCardMenu = false
    @State private var isShowingMoveCategorySheet = false
    @State private var selectedMoveCategoryName: String?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            cardArtworkLayer
            if !isLoading {
                cardFooterLayer
            }
            if hasSummarizedText {
                summaryPlayButton
            }
            if isImporting {
                importOverlay(text: "Preparing file...")
                    .zIndex(1)
            }
            if isGeneratingAudio {
                importOverlay(text: "Generating audio...", progress: audioGenerationProgressFraction)
                    .zIndex(1)
            }
            if isLoading && !isImporting && !isGeneratingAudio {
                importOverlay(text: "Summarizing file...")
                    .zIndex(1)
            }
            cardMenuButton
        }
        .frame(maxWidth: .infinity, minHeight: 400, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(preferredMode == .light ? 0.24 : 0.40), lineWidth: 1)
        )
        .shadow(color: .black.opacity(preferredMode == .light ? 0.10 : 0.22), radius: 16, y: 8)
        .background(panelBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .confirmationDialog(
            "Delete \"\(entry.title)\"?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDelete()
            }

            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently remove the book/text from the local database.")
        }
        .sheet(isPresented: $isShowingMoveCategorySheet) {
            categoryPickerSheet
        }
    }

    private var categoryPickerSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Select Category")
                    .font(.title2.weight(.bold))

                Text("Choose a category to move this item into.")
                    .foregroundStyle(.secondary)

                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(categories) { category in
                            Button {
                                selectedMoveCategoryName = category.name
                            } label: {
                                HStack {
                                    Label(category.name, systemImage: "folder.fill")
                                        .font(.body.weight(.medium))
                                    Spacer()
                                    if selectedMoveCategoryName == category.name {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(sheetRowBackground(isSelected: selectedMoveCategoryName == category.name), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(ReaderPointerCursorButtonStyle())
                        }
                    }
                }

                HStack {
                    Button("Cancel", role: .cancel) {
                        isShowingMoveCategorySheet = false
                    }

                    Spacer()

                    Button("Move") {
                        if let selectedMoveCategoryName {
                            onAssignCategory(selectedMoveCategoryName)
                        }
                        isShowingMoveCategorySheet = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedMoveCategoryName == nil)
                }
            }
            .padding(20)
            .frame(minWidth: 360, minHeight: 420)
            .navigationTitle("Move to Category")
        }
    }

    private func sheetRowBackground(isSelected: Bool) -> Color {
        if isSelected {
            return preferredMode == .light ? Color.green.opacity(0.14) : Color.green.opacity(0.22)
        }

        return preferredMode == .light ? Color.black.opacity(0.04) : Color.white.opacity(0.06)
    }

    private var summaryPlayButton: some View {
        HStack {
            Button(action: onPlaySummary) {
                Label("Summary", systemImage: isSummaryPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.yellow, in: Capsule())
            }
            .buttonStyle(ReaderPointerCursorButtonStyle())
            .disabled(isSummaryPlaying)
            .opacity(isSummaryPlaying ? 0.8 : 1)
            Spacer()
        }
        .padding(12)
        .accessibilityLabel("Play summary")
    }

    @ViewBuilder
    private var cardArtworkLayer: some View {
        ReaderCardArtworkView(
            coverImagePath: entry.coverImageFilePath,
            symbolName: entry.avatarSymbolName,
            accentName: entry.accentName,
            preferredMode: preferredMode,
            isLoading: isCoverArtLoading
        )
        .frame(maxWidth: .infinity, minHeight: 340)
        .clipped()

        LinearGradient(
            colors: [
                Color.clear,
                Color.black.opacity(preferredMode == .light ? 0.22 : 0.30),
                Color.black.opacity(preferredMode == .light ? 0.72 : 0.82)
            ],
            startPoint: .center,
            endPoint: .bottom
        )
    }

    private var cardFooterLayer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.title)
                        .font(.headline.weight(.bold))
                        .lineLimit(1)
                        .foregroundStyle(.white)
                }

                HStack(spacing: 8) {
                    if let textLanguage = entry.textLanguage {
                        Text(textLanguage.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.16), in: Capsule())
                    }

                    Text(sourceKindBadgeText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(sourceKindBadgeBackground, in: Capsule())

                    if let extractionMode = extractionBadgeMode {
                        Text(extractionMode.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(pdfExtractionBadgeBackground(for: extractionMode), in: Capsule())
                    }

                    if hasGeneratedAudio {
                        Image(systemName: "person.wave.2.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.yellow, in: Capsule())
                            .accessibilityLabel("Audio generated")
                    }

                    Spacer()
                }

                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: readingProgressFraction ?? generatedAudioProgressFraction ?? entry.currentReadingProgressFraction)
                        .tint(.white)

                    if let currentReadingProgress = entry.currentReadingProgressSummaryText ?? entry.currentReadingPositionDisplayText {
                        Text(currentReadingProgress)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                    }
                }

                HStack {
                    Button(action: onPrimaryAction) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 44, height: 44)
                            .background(hasGeneratedAudio ? Color.yellow : .white, in: Circle())
                    }
                    .buttonStyle(ReaderPointerCursorButtonStyle())
                    .disabled(isImporting)
                    .opacity(isImporting ? 0.45 : 1)

                    Button(action: onOpenOriginalFile) {
                        Text("View")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.16), in: Circle())
                    }
                    .buttonStyle(ReaderPointerCursorButtonStyle())
                    .disabled(isImporting)
                    .opacity(isImporting ? 0.45 : 1)

                    Spacer()

                    Text(entry.createdAt, format: .dateTime.day().month(.abbreviated).year())
                        .font(.caption2)
                        .italic()
                        .foregroundStyle(.white.opacity(0.68))
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TopRoundedRectangle(radius: 0).fill(metaBackground))
        }
        .padding(.vertical, 2)
    }

    // Covers the card while an item is importing or generating audio so users
    // get an immediate visual indication that the file is still being processed.
    private func importOverlay(text: String, progress: Double? = nil) -> some View {
        VStack {
            if let progress {
                ProgressView(value: progress)
                    .tint(.white)
                    .frame(maxWidth: 180)
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.top, 4)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }
            Text(text)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.top, 10)
                .padding(.bottom, 24)
        }
        .padding(EdgeInsets(top: 24, leading: 44, bottom: 8, trailing: 44))
        .background(Color.black.opacity(0.42))
        .cornerRadius(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cardMenuButton: some View {
        Button {
            isShowingCardMenu.toggle()
        } label: {
            Image(systemName: "ellipsis")
                .font(.headline)
                .padding(8)
                .foregroundStyle(.white)
                .background(Color.black.opacity(0.82), in: Circle())
                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
        }
        .padding(12)
        // .disabled(isImporting || isGeneratingAudio)
        // .opacity((isImporting || isGeneratingAudio) ? 0.45 : 1)
        .popover(isPresented: $isShowingCardMenu, arrowEdge: .top) {
            ReaderCardMenuPopoverView(
                categories: categories,
                preferredMode: preferredMode,
                onPlay: onPlay,
                onPlaySummary: onPlaySummary,
                onSummarize: {
                    isShowingCardMenu = false
                    onSummarize()
                },
                onCancelSummarization: {
                    isShowingCardMenu = false
                    onCancelSummarization()
                },
                onViewTextFile: {
                    isShowingCardMenu = false
                    onViewTextFile()
                },
                onRevealLocation: onRevealLocation,
                onGenerateAudio: onGenerateAudio,
                onStopAudioGeneration: onStopAudioGeneration,
                onDeleteAudio: onDeleteAudio,
                hasGeneratedAudio: hasGeneratedAudio,
                hasSummarizedText: hasSummarizedText,
                isSummaryPlaying: isSummaryPlaying,
                isSummarizing: isSummarizing,
                isGeneratingAudio: isGeneratingAudio,
                onClearCategory: onClearCategory,
                onSelectCategory: {
                    selectedMoveCategoryName = entry.categoryName ?? categories.first?.name
                    isShowingMoveCategorySheet = true
                },
                onDelete: {
                    isShowingDeleteConfirmation = true
                },
                isLoading: isLoading
            )
            .frame(width: 260)
            .padding(12)
        }
    }
    
    struct TopRoundedRectangle: Shape {
        var radius: CGFloat = 16

        // Builds a top-rounded rectangle so the card footer can sit flush
        // against the artwork while only the upper corners stay rounded.
        func path(in rect: CGRect) -> Path {
            var path = Path()

            let r = min(radius, rect.width / 2, rect.height / 2)

            path.move(to: CGPoint(x: rect.minX, y: rect.maxY)) // bottom-left
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))

            // top-left curve
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + r, y: rect.minY),
                control: CGPoint(x: rect.minX, y: rect.minY)
            )

            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))

            // top-right curve
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + r),
                control: CGPoint(x: rect.maxX, y: rect.minY)
            )

            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)) // bottom-right
            path.closeSubpath()

            return path
        }
    }

    // Base surface color behind the entire card chrome.
    private var panelBackground: Color {
        preferredMode == .light ? Color.white.opacity(0.82) : Color.white.opacity(0.12)
    }

    // Secondary elevated tint used for subtle UI containers and chips.
    private var elevatedBackground: Color {
        preferredMode == .light ? Color.black.opacity(0.05) : Color.white.opacity(0.08)
    }

    // Full-width footer tint behind the metadata block.
    private var metaBackground: Color {
        switch preferredMode {
        case .light:
            return Color.white.opacity(0.34)
        case .dark, .system:
            return Color.black.opacity(0.70)
        }
    }

    private var secondaryTextColor: Color {
        preferredMode == .light ? Color.black.opacity(0.60) : Color.white.opacity(0.72)
    }

    private var primaryTextColor: Color {
        preferredMode == .light ? .black : .white
    }

    private var sourceKindBadgeText: String {
        return entry.sourceKind.displayName
    }

    private var sourceKindBadgeBackground: Color {
        return Color.white.opacity(0.18)
    }

    private var extractionBadgeMode: PDFExtractionMode? {
        if entry.sourceKind == .image {
            return .ocr
        }

        if entry.sourceKind == .pdf {
            return entry.pdfExtractionMode
        }

        return nil
    }

    // Chooses a badge tint that makes the PDF extraction mode readable while
    // still fitting the card's existing color language.
    private func pdfExtractionBadgeBackground(for mode: PDFExtractionMode) -> Color {
        switch mode {
        case .directText:
            return Color.green.opacity(0.20)
        case .ocr:
            return Color.orange.opacity(0.22)
        case .hybrid:
            return Color.blue.opacity(0.22)
        case .unknown:
            return Color.white.opacity(0.12)
        }
    }
}

// MARK: - Card Menu
// Custom popover that replaces the default menu so the action surface can be styled.
struct ReaderCardMenuPopoverView: View {
    let categories: [ReaderCategory]
    let preferredMode: AppearanceMode
    let onPlay: () -> Void
    let onPlaySummary: () -> Void
    let onSummarize: () -> Void
    let onCancelSummarization: () -> Void
    let onViewTextFile: () -> Void
    let onRevealLocation: () -> Void
    let onGenerateAudio: () -> Void
    let onStopAudioGeneration: () -> Void
    let onDeleteAudio: () -> Void
    let hasGeneratedAudio: Bool
    let hasSummarizedText: Bool
    let isSummaryPlaying: Bool
    let isSummarizing: Bool
    let isGeneratingAudio: Bool
    let onClearCategory: () -> Void
    let onSelectCategory: () -> Void
    let onDelete: () -> Void
    let isLoading: Bool

    var body: some View {
        // Keep the menu actions grouped and visually balanced.
        VStack(alignment: .leading, spacing: 10) {
            if isGeneratingAudio {
                menuButton(title: "Stop Audio generation", systemImage: "stop.fill", role: .destructive, action: onStopAudioGeneration)
                Divider()
            } else if isSummarizing {
                menuButton(title: "Cancel summarization", systemImage: "xmark.circle.fill", role: .destructive, action: onCancelSummarization)
                Divider()
            } else if !isLoading {
                if hasSummarizedText {
                    menuButton(title: "Play summarized file", systemImage: "quote.bubble.fill", action: onPlaySummary)
                } else {
                    menuButton(title: "Summarize File", systemImage: "text.bubble.fill", action: onSummarize)
                }
                menuButton(title: "View text file", systemImage: "doc.text.magnifyingglass", action: onViewTextFile)
                menuButton(title: "Open file location", systemImage: "folder", action: onRevealLocation)
                if hasGeneratedAudio {
                    menuButton(title: "Delete audio file", systemImage: "trash", role: .destructive, action: onDeleteAudio)
                } else {
                    menuButton(title: "Generate Audio file", systemImage: "waveform.circle.fill", action: onGenerateAudio)
                }

                Divider()
            }

            menuButton(title: "Clear category", systemImage: "tag.slash", action: onClearCategory)
            menuButton(title: "Delete", systemImage: "trash", role: .destructive, action: onDelete)

            if !categories.isEmpty {
                Divider()
                menuButton(title: "Select Category", systemImage: "folder.fill", action: onSelectCategory)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(menuBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(menuBorderColor, lineWidth: 1)
        )
        .shadow(color: .black.opacity(preferredMode == .light ? 0.14 : 0.26), radius: 16, y: 8)
    }

    // Reusable row button used for every menu action.
    @ViewBuilder
    // Wraps a single menu action in the shared card popover styling.
    private func menuButton(
        title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 18)

                Text(title)
                    .font(.body.weight(.medium))

                Spacer()
            }
            .frame(maxWidth: 260, alignment: .leading)
            .foregroundStyle(role == .destructive ? .red : primaryTextColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(menuButtonBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // Menu surface tint that adapts to the selected appearance mode.
    private var menuBackground: Color {
        preferredMode == .light ? Color.white.opacity(0.72) : Color.black.opacity(0.72)
    }

    // Button row background inside the popover.
    private var menuButtonBackground: Color {
        preferredMode == .light ? Color.black.opacity(0.04) : Color.white.opacity(0.06)
    }

    // Thin border to separate the menu from the background artwork.
    private var menuBorderColor: Color {
        preferredMode == .light ? Color.black.opacity(0.08) : Color.white.opacity(0.10)
    }

    private var primaryTextColor: Color {
        preferredMode == .light ? .black : .white
    }
}

// MARK: - Card Artwork
// Artwork loader that prefers saved cover art and falls back to a generated badge.
struct ReaderCardArtworkView: View {
    let coverImagePath: String?
    let symbolName: String
    let accentName: String
    let preferredMode: AppearanceMode
    let isLoading: Bool

    var body: some View {
        if let coverImagePath, let image = NSImage(contentsOf: URL(fileURLWithPath: coverImagePath)) {
            coverImage(image)
        } else {
            placeholderCover
        }
    }

    // Real cover art rendering path.
    @ViewBuilder
    // Renders the resolved cover art using the same crop and emphasis settings
    // that the rest of the card uses for its artwork surface.
    private func coverImage(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit() // preserve full cover
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.gray.opacity(preferredMode == .light ? 0.08 : 0.2))
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(preferredMode == .light ? 0.28 : 0.14), lineWidth: 1)
            )
            .shadow(color: .black.opacity(preferredMode == .light ? 0.12 : 0.24), radius: 10, y: 5)

    }

    // Placeholder art shown while cover extraction is still running.
    private var placeholderCover: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: placeholderGradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(preferredMode == .light ? 0.30 : 0.14), lineWidth: 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            ZStack {
                Circle()
                    .fill(Color.white.opacity(preferredMode == .light ? 0.20 : 0.12))
                    .frame(width: 46, height: 46)

                Image(systemName: symbolName)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(primarySymbolColor)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if isLoading {
                Text("Preparing")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(primarySymbolColor.opacity(0.85))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(preferredMode == .light ? 0.08 : 0.18), in: Capsule())
                    .padding(8)
            }
        }
        .shadow(color: .black.opacity(preferredMode == .light ? 0.11 : 0.22), radius: 10, y: 5)
    }

    private var placeholderGradientColors: [Color] {
        let accent = ReaderStyle.accentColor(named: accentName)
        switch preferredMode {
        case .light:
            return [
                accent.opacity(0.95),
                accent.opacity(0.65),
                Color.white.opacity(0.86)
            ]
        case .dark, .system:
            return [
                accent.opacity(0.98),
                accent.opacity(0.55),
                Color.black.opacity(0.26)
            ]
        }
    }

    private var primarySymbolColor: Color {
        preferredMode == .light ? .black : .white
    }
}

// MARK: - Avatar Badge
// Shared badge view used across cards, player chrome, and hero surfaces.
struct ReaderAvatarView: View {
    let symbolName: String
    let accentName: String
    let preferredMode: AppearanceMode

    var body: some View {
        let accent = ReaderStyle.accentColor(named: accentName)

        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.95), accent.opacity(0.45)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 50, height: 50)

            Image(systemName: symbolName)
                .font(.headline)
                .foregroundStyle(preferredMode == .light ? .black : .white)
        }
    }
}

// MARK: - Player Bar
// Persistent transport controls that stay pinned across the app shell.
struct ReaderPlayerBarView: View {
    @Binding var playbackState: PlaybackState
    @Binding var volume: Double
    let preferredMode: AppearanceMode
    let isLoadingFirstChunk: Bool
    let readingStructureKind: ReadingStructureKind?
    let jumpTargets: [ReaderJumpTarget]
    let canRewind: Bool
    let canFastForward: Bool
    let onRewind: () -> Void
    let onTogglePlayPause: () -> Void
    let onFastForward: () -> Void
    let onJumpToTarget: (ReaderJumpTarget) -> Void

    var body: some View {
        ZStack {
            ViewThatFits(in: .horizontal) {
                horizontalLayout
                verticalLayout
            }

            if isLoadingFirstChunk {
                firstChunkLoadingOverlay
            }
        }
        .padding(16)
        .background(panelBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(elevatedBackground, lineWidth: 1)
        )
        .shadow(color: .black.opacity(preferredMode == .light ? 0.12 : 0.35), radius: 20, y: 8)
    }

    // Wide layout optimized for roomy windows.
    private var horizontalLayout: some View {
        HStack(spacing: 16) {
            mediaInfo
            Spacer()
            VStack(alignment: .trailing, spacing: 14) {
                // controls
                ReaderVolumeControlView(volume: $volume, preferredMode: preferredMode)
                    .frame(width: 240)
            }
        }
    }

    // Compact fallback for narrow windows.
    private var verticalLayout: some View {
        VStack(alignment: .leading, spacing: 14) {
            mediaInfo
            controls
            ReaderVolumeControlView(volume: $volume, preferredMode: preferredMode)
        }
    }

    // Current item title, subtitle, and visual identity.
    private var mediaInfo: some View {
        HStack(spacing: 16) {
//            ReaderAvatarView(symbolName: playbackState.avatarSymbol, accentName: playbackState.accentName, preferredMode: preferredMode)
            roundControlButton(icon: playbackState.isPlaying ? "pause.fill" : "play.fill", isProminent: true) {
                onTogglePlayPause()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(playbackState.title)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(primaryTextColor)

                if !playbackState.displayedReadingPositionText.isEmpty || !jumpTargets.isEmpty {
                    HStack(spacing: 10) {
                        if !playbackState.displayedReadingPositionText.isEmpty {
                            Text(playbackState.displayedReadingPositionText)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(secondaryTextColor)
                                .lineLimit(1)
                        }

                        if !jumpTargets.isEmpty {
                            jumpMenu
                        }
                    }
                    .padding(.top, 2)
                }

                HStack(spacing: 8) {
                seekBar
                        .frame(maxWidth: 520)

                    Text(playbackTimeText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(secondaryTextColor)
                        .frame(minWidth: 84, alignment: .trailing)
                }
            }
        }
    }

    // Playback transport cluster plus seek information.
    private var controls: some View {
        HStack(spacing: 12) {
            roundControlButton(icon: "backward.fill", isDisabled: !canRewind) {
                onRewind()
            }

            roundControlButton(icon: playbackState.isPlaying ? "pause.fill" : "play.fill", isProminent: true) {
                onTogglePlayPause()
            }

            roundControlButton(icon: "forward.fill", isDisabled: !canFastForward) {
                onFastForward()
            }
        }
    }

    private var jumpMenu: some View {
        Menu {
            ForEach(jumpTargets) { target in
                Button {
                    onJumpToTarget(target)
                } label: {
                    if target.index == currentJumpTargetIndex {
                        Label(jumpTargetLabel(for: target), systemImage: "checkmark")
                    } else {
                        Text(jumpTargetLabel(for: target))
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                Text(jumpMenuLabel)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(primaryTextColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(elevatedBackground, in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .readerPointerCursor()
    }

    private var currentJumpTargetIndex: Int? {
        guard !jumpTargets.isEmpty else { return nil }
        if let override = playbackState.readingPositionIndexOverride {
            return min(max(override, 0), jumpTargets.count - 1)
        }
        return ReaderPlaybackChunkService.chunkIndex(
            for: playbackState.progress,
            chunkCount: jumpTargets.count
        )
    }

    // Converts a resolved reading target into the user-facing label shown in
    // the Kokoro narration jump menu.
    private func jumpTargetLabel(for target: ReaderJumpTarget) -> String {
        let title = target.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayIndex = target.index + 1

        switch readingStructureKind {
        case .page:
            if title.isEmpty {
                return "Page \(displayIndex)"
            }
            return "Page \(displayIndex) - \(title)"
        case .chapter:
            if title.isEmpty {
                return "Chapter \(displayIndex)"
            }
            return "Chapter \(displayIndex) - \(title)"
        case .section:
            if title.isEmpty {
                return "Section \(displayIndex)"
            }
            return "Section \(displayIndex) - \(title)"
        case .none:
            return title.isEmpty ? "Item \(displayIndex)" : title
        }
    }

    private var jumpMenuLabel: String {
        switch readingStructureKind {
        case .page:
            return "Jump Page"
        case .chapter:
            return "Jump Chapter"
        case .section:
            return "Jump Section"
        case .none:
            return "Jump"
        }
    }

    // Centered loader shown while the first chunk is still being prepared.
    private var firstChunkLoadingOverlay: some View {
        ZStack {
            Color.black.opacity(preferredMode == .light ? 0.08 : 0.18)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.extraLarge)

                Text("Please wait")
                    .font(.headline)
                    .foregroundStyle(primaryTextColor)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    // Seek bar with elapsed and total time labels.
    private var seekBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(seekTrackColor)
                Capsule()
                    .fill(ReaderStyle.accentColor(named: playbackState.accentName))
                    .frame(width: max(10, geometry.size.width * playbackState.displayedProgress))
            }
            .contentShape(Rectangle())
            .readerPointerCursor()
        }
        .frame(height: 8)
    }

    private var playbackTimeText: String {
        "\(ReaderStyle.formattedTime(playbackState.elapsedSeconds)) / \(ReaderStyle.formattedTime(playbackState.durationSeconds))"
    }

    // Builds the circular transport button used by the narration player bar.
    private func roundControlButton(
        icon: String,
        isActive: Bool = false,
        isProminent: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: isProminent ? 18 : 15, weight: .semibold))
                .foregroundStyle(isActive || isProminent ? Color.white : primaryTextColor)
                .frame(width: isProminent ? 50 : 40, height: isProminent ? 50 : 40)
                .background(
                    Circle()
                        .fill(
                            isProminent
                                ? ReaderStyle.accentColor(named: playbackState.accentName)
                                : elevatedBackground
                        )
                )
                .overlay(
                    Circle()
                        .strokeBorder(isActive ? ReaderStyle.accentColor(named: playbackState.accentName) : Color.clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(ReaderPointerCursorButtonStyle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }

    // Base surface for the player chrome.
    private var panelBackground: Color {
        preferredMode == .light ? Color.white.opacity(0.72) : Color.black.opacity(0.85)
    }

    // Border tint for the player chrome.
    private var elevatedBackground: Color {
        preferredMode == .light ? Color.black.opacity(0.05) : Color.white.opacity(0.08)
    }

    private var seekTrackColor: Color {
        preferredMode == .light ? Color.black.opacity(0.14) : Color.white.opacity(0.18)
    }

    private var secondaryTextColor: Color {
        preferredMode == .light ? Color.black.opacity(0.60) : Color.white.opacity(0.72)
    }

    private var primaryTextColor: Color {
        preferredMode == .light ? .black : .white
    }
}

// MARK: - Generated Audio Player
// Separate playback surface for exported .m4a files so Kokoro playback stays isolated.
struct GeneratedAudioPlayerBarView: View {
    let title: String
    let subtitle: String
    let avatarSymbol: String
    let accentName: String
    let isPlaying: Bool
    let elapsedSeconds: Int
    let durationSeconds: Int
    @Binding var volume: Double
    @Binding var playbackSpeed: Double
    let preferredMode: AppearanceMode
    let onTogglePlayPause: () -> Void
    let onSeek: (Double) -> Void
    let onStop: () -> Void

    var body: some View {
        ZStack {
            ViewThatFits(in: .horizontal) {
                horizontalLayout
                verticalLayout
            }
        }
        .padding(16)
        .background(panelBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(elevatedBackground, lineWidth: 1)
        )
        .shadow(color: .black.opacity(preferredMode == .light ? 0.12 : 0.35), radius: 20, y: 8)
    }

    private var horizontalLayout: some View {
            HStack(spacing: 16) {
            mediaInfo
            Spacer()
            VStack(alignment: .trailing, spacing: 14) {
                VStack(spacing: 10) {
                    ReaderPlaybackSpeedControlView(
                        playbackSpeed: $playbackSpeed,
                        preferredMode: preferredMode
                    )
                    ReaderVolumeControlView(
                        volume: $volume,
                        preferredMode: preferredMode
                    )
                }
                .frame(width: 240)
            }
        }
    }

    private var verticalLayout: some View {
        VStack(alignment: .leading, spacing: 14) {
            mediaInfo
            VStack(spacing: 10) {
                ReaderPlaybackSpeedControlView(
                    playbackSpeed: $playbackSpeed,
                    preferredMode: preferredMode
                )
                ReaderVolumeControlView(
                    volume: $volume,
                    preferredMode: preferredMode
                )
            }
        }
    }

    private var mediaInfo: some View {
        HStack(spacing: 16) {
            controls
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(primaryTextColor)

                Text(subtitle)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(secondaryTextColor)

                    HStack(spacing: 10) {
                    seekBar
                        .frame(maxWidth: 520)

                    Text(playbackTimeText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(secondaryTextColor)
                        .frame(minWidth: 84, alignment: .trailing)
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            roundControlButton(icon: isPlaying ? "pause.fill" : "play.fill", isProminent: true) {
                onTogglePlayPause()
            }
        }
    }

    private var seekBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(seekTrackColor)
                Capsule()
                    .fill(ReaderStyle.accentColor(named: accentName))
                    .frame(width: max(10, geometry.size.width * playbackProgress))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard geometry.size.width > 0 else { return }
                        let fraction = min(max(value.location.x / geometry.size.width, 0), 1)
                        onSeek(fraction)
                    }
            )
        }
        .frame(height: 8)
    }

    private var playbackProgress: Double {
        guard durationSeconds > 0 else { return 0 }
        return min(max(Double(elapsedSeconds) / Double(durationSeconds), 0), 1)
    }

    private var playbackTimeText: String {
        "\(ReaderStyle.formattedTime(elapsedSeconds)) / \(ReaderStyle.formattedTime(durationSeconds))"
    }

    // Builds the circular transport button used by the generated-audio player.
    private func roundControlButton(
        icon: String,
        isProminent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: isProminent ? 18 : 15, weight: .semibold))
                .foregroundStyle(isProminent ? Color.white : primaryTextColor)
                .frame(width: isProminent ? 50 : 40, height: isProminent ? 50 : 40)
                .background(
                    Circle()
                        .fill(
                            isProminent
                                ? ReaderStyle.accentColor(named: accentName)
                                : elevatedBackground
                        )
                )
        }
        .buttonStyle(ReaderPointerCursorButtonStyle())
    }

    private var panelBackground: Color {
        preferredMode == .light ? Color.white.opacity(0.72) : Color.black.opacity(0.85)
    }

    private var elevatedBackground: Color {
        preferredMode == .light ? Color.black.opacity(0.05) : Color.white.opacity(0.08)
    }

    private var seekTrackColor: Color {
        preferredMode == .light ? Color.black.opacity(0.14) : Color.white.opacity(0.18)
    }

    private var secondaryTextColor: Color {
        preferredMode == .light ? Color.black.opacity(0.60) : Color.white.opacity(0.72)
    }

    private var primaryTextColor: Color {
        preferredMode == .light ? .black : .white
    }
}

// MARK: - Processing Overlay
// Full-screen overlay shown while an import is being normalized.
struct ReaderProcessingOverlayView: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.30)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.extraLarge)

                Text(message)
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.24), radius: 16, y: 8)
        }
    }
}

// Centered loader shown while the first playback chunk is being prepared.
struct ReaderPlaybackLoadingOverlayView: View {
    let message: String
    let subtitle: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.extraLarge)

                Text(message)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                
                Text(subtitle)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.20), radius: 16, y: 6)
        }
    }
}

// Centered loader shown while an import is being summarized or normalized.
struct ReaderImportLoadingOverlayView: View {
    let message: String
    let subtitle: String
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.extraLarge)

                Text(message)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)

                Button("Cancel", role: .cancel, action: onCancel)
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.20), radius: 16, y: 6)
        }
    }
}

// MARK: - Toast
// Lightweight success banner displayed when a file is ready.
struct ReaderToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)

            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}

// MARK: - RSS Home Ticker
// Rotating home-screen preview for the newest RSS items.
struct RSSHomeTickerView: View {
    let feedItems: [RSSFeedItemRecord]
    let preferredMode: AppearanceMode
    let onOpenArticle: (RSSFeedItemRecord) -> Void
    let onReadAloud: (RSSFeedItemRecord) async -> Void

    private let maximumVisibleItems = 50
    private let displayDuration: TimeInterval = 10
    private let fadeDuration: TimeInterval = 0.7

    @State private var currentIndex = 0
    @State private var isHovered = false
    @State private var isSectionVisible = true
    @State private var isVisible = true
    @State private var isReadAloudLoading = false
    @State private var cycleStartedAt: Date?
    @State private var accumulatedPausedTime: TimeInterval = 0
    @State private var pauseStartedAt: Date?

    private var visibleItems: [RSSFeedItemRecord] {
        let sortedItems = feedItems.sorted { lhs, rhs in
            let lhsDate = lhs.publishedAt ?? lhs.fetchedAt
            let rhsDate = rhs.publishedAt ?? rhs.fetchedAt
            if lhsDate == rhsDate {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhsDate > rhsDate
        }

        return Array(sortedItems.prefix(maximumVisibleItems))
    }

    private var feedIdentityKey: String {
        visibleItems.map(\.id).joined(separator: "|")
    }

    private var currentFeedItem: RSSFeedItemRecord? {
        guard !visibleItems.isEmpty else { return nil }
        return visibleItems[min(currentIndex, visibleItems.count - 1)]
    }

    private var isTickerPaused: Bool {
        isHovered || !isSectionVisible
    }

    var body: some View {
        
        if !visibleItems.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Latest RSS")
                            .font(.title2.weight(.bold))
                    }

                    Spacer(minLength: 0)
                    
                    // @todo Add a pause button here to stop the feed play
                }

                VStack(alignment: .leading, spacing: 14) {
                    progressLine

                    if let currentFeedItem {
                        ZStack(alignment: .bottomTrailing) {
                            RSSHomeTickerRowView(
                                item: currentFeedItem,
                                preferredMode: preferredMode,
                                isReadAloudLoading: isReadAloudLoading,
                                onOpenArticle: { onOpenArticle(currentFeedItem) },
                                onReadAloud: {
                                    Task {
                                        await readAloud(currentFeedItem)
                                    }
                                }
                            )
                            .id(currentFeedItem.id)

                            HStack(spacing: 8) {
                                tickerControlButton(
                                    systemImage: "chevron.left",
                                    accessibilityLabel: "Previous feed",
                                    action: { moveFeed(by: -1) }
                                )

                                tickerControlButton(
                                    systemImage: "chevron.right",
                                    accessibilityLabel: "Next feed",
                                    action: { moveFeed(by: 1) }
                                )
                            }
                            .padding(10)
                        }
                        .opacity(isVisible ? 1 : 0)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .onHover { hovering in
                    isHovered = hovering
                    updateTickerPauseState()
                }
                .onScrollVisibilityChange(threshold: 0.1) { isVisibleOnScreen in
                    isSectionVisible = isVisibleOnScreen
                    updateTickerPauseState()
                }
                .task(id: feedIdentityKey) {
                    await runTickerLoop()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var progressLine: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { _ in
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(preferredMode == .light ? 0.10 : 0.16))

                    Capsule()
                        .fill(ReaderStyle.accentColor(named: "emerald"))
                        .frame(width: max(0, proxy.size.width * tickerProgressFraction))
                }
            }
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }

    private var tickerProgressFraction: Double {
        guard let cycleStartedAt else { return 0 }

        let now = Date()
        var elapsed = now.timeIntervalSince(cycleStartedAt) - accumulatedPausedTime
        if let pauseStartedAt {
            elapsed -= now.timeIntervalSince(pauseStartedAt)
        }

        guard elapsed.isFinite else { return 0 }
        return min(max(elapsed / displayDuration, 0), 1)
    }

    private var currentCycleElapsedTime: TimeInterval {
        tickerProgressFraction * displayDuration
    }

    @MainActor
    private func updateTickerPauseState() {
        if isTickerPaused {
            if pauseStartedAt == nil {
                pauseStartedAt = .now
            }
            return
        }

        if let pauseStartedAt {
            accumulatedPausedTime += Date().timeIntervalSince(pauseStartedAt)
            self.pauseStartedAt = nil
        }
    }

    @MainActor
    private func readAloud(_ item: RSSFeedItemRecord) async {
        guard !isReadAloudLoading else { return }
        isReadAloudLoading = true
        defer { isReadAloudLoading = false }

        await onReadAloud(item)
    }

    @MainActor
    private func moveFeed(by offset: Int) {
        guard !visibleItems.isEmpty else { return }

        let count = visibleItems.count
        let normalizedOffset = ((offset % count) + count) % count
        guard normalizedOffset != 0 else { return }

        withAnimation(.easeInOut(duration: fadeDuration)) {
            isVisible = false
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(fadeDuration * 1_000_000_000))
            guard !Task.isCancelled, !visibleItems.isEmpty else { return }

            currentIndex = (currentIndex + normalizedOffset) % count
            cycleStartedAt = .now
            accumulatedPausedTime = 0
            pauseStartedAt = nil

            withAnimation(.easeInOut(duration: fadeDuration)) {
                isVisible = true
            }
        }
    }

    private func tickerControlButton(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .frame(width: 28, height: 28)
                .foregroundStyle(.primary)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        }
        .buttonStyle(ReaderPointerCursorButtonStyle())
        .accessibilityLabel(Text(accessibilityLabel))
    }

    @MainActor
    private func runTickerLoop() async {
        currentIndex = 0
        isVisible = true
        cycleStartedAt = .now
        accumulatedPausedTime = 0
        pauseStartedAt = nil

        guard !visibleItems.isEmpty else { return }

        while !Task.isCancelled {
            guard !isTickerPaused else {
                try? await Task.sleep(nanoseconds: 120_000_000)
                continue
            }

            while currentCycleElapsedTime < displayDuration {
                if Task.isCancelled {
                    return
                }

                if isTickerPaused {
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    continue
                }

                try? await Task.sleep(nanoseconds: 100_000_000)
            }

            if Task.isCancelled || visibleItems.isEmpty {
                return
            }

            withAnimation(.easeInOut(duration: fadeDuration)) {
                isVisible = false
            }

            try? await Task.sleep(nanoseconds: UInt64(fadeDuration * 1_000_000_000))
            if Task.isCancelled || visibleItems.isEmpty {
                return
            }

            currentIndex = (currentIndex + 1) % visibleItems.count
            cycleStartedAt = .now
            accumulatedPausedTime = 0
            pauseStartedAt = nil

            withAnimation(.easeInOut(duration: fadeDuration)) {
                isVisible = true
            }
        }
    }
}

private struct RSSHomeTickerRowView: View {
    let item: RSSFeedItemRecord
    let preferredMode: AppearanceMode
    let isReadAloudLoading: Bool
    let onOpenArticle: () -> Void
    let onReadAloud: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.feedTitle)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(ReaderStyle.accentColor(named: "emerald"))
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text(RSSRelativeTimeFormatter.string(from: item.publishedAt ?? item.fetchedAt))
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                Text(item.title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)

                Text(item.summary.isEmpty ? "No description provided." : item.summary)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                HStack(spacing: 10) {
                    Button {
                        onOpenArticle()
                    } label: {
                        Label("Read Article", systemImage: "safari")
                            .font(.body.weight(.semibold))
                    }
                    .controlSize(.large)
                    .buttonStyle(.bordered)
                    .readerPointerCursor()
                    .disabled(isReadAloudLoading)

                    Button {
                        onReadAloud()
                    } label: {
                        if isReadAloudLoading {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Reading...")
                            }
                            .font(.subheadline.weight(.semibold))
                        } else {
                            Label("Read Aloud", systemImage: "speaker.wave.2.fill")
                                .font(.body.weight(.semibold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .readerPointerCursor()
                    .tint(ReaderStyle.accentColor(named: "emerald"))
                    .disabled(isReadAloudLoading)
                }
                .padding(.top, 16)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var rowBackground: AnyShapeStyle {
        if preferredMode == .light {
            return AnyShapeStyle(Color.orange.opacity(0.06))
        }

        return AnyShapeStyle(Color.orange.opacity(0.12))
    }
}

private enum RSSRelativeTimeFormatter {
    static func string(from date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))

        if seconds < 60 {
            return "\(seconds) sec ago"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes) min\(minutes == 1 ? "" : "s") ago"
        }

        let hours = minutes / 60
        if hours < 24 {
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        }

        let days = hours / 24
        return "\(days) day\(days == 1 ? "" : "s") ago"
    }
}
