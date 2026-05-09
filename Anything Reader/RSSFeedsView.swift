//
//  RSSFeedsView.swift
//  Anything Reader
//
//  RSS subscription manager and feed card browser.
//

import AppKit
import SwiftUI

struct RSSFeedsView: View {
    @ObservedObject var refreshService: RSSFeedRefreshService
    @Binding var searchText: String
    let preferredMode: AppearanceMode
    let onFeedSaved: () -> Void
    let onReadAloud: (RSSFeedItemRecord) async throws -> Void

    @AppStorage("rssFeedDisplayStyle") private var rssFeedDisplayStyleRawValue: String = RSSFeedDisplayStyle.list.rawValue
    @State private var feedURLString = ""
    @State private var isSavingFeed = false
    @State private var isShowingSavedFeeds = false
    @State private var isShowingAddFeedSheet = false
    @State private var alertMessage: String?
    @State private var readAloudItemID: String?
    @State private var visibleFeedItemCount = 50
    @State private var isLoadingMoreFeedItems = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            headerSection
            feedCardsSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            refreshService.startIfNeeded()
        }
        .onChange(of: searchText) { _, _ in
            visibleFeedItemCount = 50
            isLoadingMoreFeedItems = false
        }
        .sheet(isPresented: $isShowingSavedFeeds) {
            RSSSavedFeedsSheet(
                refreshService: refreshService,
                preferredMode: preferredMode
            )
        }
        .sheet(isPresented: $isShowingAddFeedSheet) {
            RSSAddFeedSheet(
                feedURLString: $feedURLString,
                isSavingFeed: $isSavingFeed,
                preferredMode: preferredMode,
                onSave: saveFeed,
                onClose: {
                    isShowingAddFeedSheet = false
                }
            )
        }
        .alert(
            "RSS Feed",
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                alertMessage = nil
            }
        } message: {
            Text(alertMessage ?? "Unable to save the RSS feed.")
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("RSS Feed")
                    .font(.system(size: 34, weight: .bold, design: .rounded))

                Spacer(minLength: 0)

                Button("Add Feed Link") {
                    isShowingAddFeedSheet = true
                }
                .buttonStyle(.borderedProminent)
                .tint(ReaderStyle.accentColor(named: "emerald"))
            }

            Text("Save RSS feed URLs, refresh them while the app is open, and browse the latest items as cards.")
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 860, alignment: .leading)

            if let lastRefreshAt = refreshService.lastRefreshAt {
                Text("Last refreshed \(lastRefreshAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var feedCardsSection: some View {
        let cards = visibleCards
        let totalCount = filteredCards.count

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Feed Content")
                        .font(.title2.weight(.bold))

                    Text("\(cards.count) of \(totalCount) item\(totalCount == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Picker("View", selection: rssFeedDisplayStyleBinding) {
                    Text("List View")
                        .tag(RSSFeedDisplayStyle.list)
                    Text("Card View")
                        .tag(RSSFeedDisplayStyle.card)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                Button("View Saved Feeds") {
                    isShowingSavedFeeds = true
                }
                .buttonStyle(.bordered)
            }

            if cards.isEmpty {
                emptyStateView
            } else {
                if rssFeedDisplayStyle == .card {
                    LazyVGrid(
                        columns: [
                            GridItem(.adaptive(minimum: 290), spacing: 16, alignment: .top)
                        ],
                        alignment: .leading,
                        spacing: 16
                    ) {
                        ForEach(cards) { card in
                            RSSFeedItemCardView(
                                card: card,
                                preferredMode: preferredMode,
                                isReadAloudLoading: readAloudItemID == card.id,
                                onOpenArticle: { openArticle(card) },
                                onReadAloud: { readAloud(card) }
                            )
                            .onAppear {
                                if card.id == cards.last?.id {
                                    loadMoreFeedItemsIfNeeded()
                                }
                            }
                        }
                    }
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(cards) { card in
                            RSSFeedItemListRowView(
                                card: card,
                                preferredMode: preferredMode,
                                isReadAloudLoading: readAloudItemID == card.id,
                                onOpenArticle: { openArticle(card) },
                                onReadAloud: { readAloud(card) }
                            )
                            .onAppear {
                                if card.id == cards.last?.id {
                                    loadMoreFeedItemsIfNeeded()
                                }
                            }
                        }
                    }
                }

                if canLoadMoreFeedItems || isLoadingMoreFeedItems {
                    HStack {
                        Spacer(minLength: 0)
                        ProgressView()
                            .controlSize(.small)
                            .opacity(isLoadingMoreFeedItems ? 1 : 0.7)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(refreshService.subscriptions.isEmpty ? "No feeds saved yet." : "No feed items yet.")
                .font(.headline)
            Text(refreshService.subscriptions.isEmpty ? "Add an RSS feed URL above to begin syncing items." : "The app will refresh the saved feeds while it is open.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var filteredCards: [RSSFeedItemRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return refreshService.feedItems
        }

        return refreshService.feedItems.filter { item in
            item.title.lowercased().contains(query)
                || item.summary.lowercased().contains(query)
                || item.feedTitle.lowercased().contains(query)
                || item.linkURLString.lowercased().contains(query)
        }
    }

    private var visibleCards: [RSSFeedItemRecord] {
        Array(filteredCards.prefix(visibleFeedItemCount))
    }

    private var canLoadMoreFeedItems: Bool {
        visibleFeedItemCount < filteredCards.count
    }

    private var rssFeedDisplayStyle: RSSFeedDisplayStyle {
        get {
            RSSFeedDisplayStyle(rawValue: rssFeedDisplayStyleRawValue) ?? .list
        }
        nonmutating set {
            rssFeedDisplayStyleRawValue = newValue.rawValue
        }
    }

    private var rssFeedDisplayStyleBinding: Binding<RSSFeedDisplayStyle> {
        Binding(
            get: { rssFeedDisplayStyle },
            set: { rssFeedDisplayStyle = $0 }
        )
    }

    @MainActor
    private func loadMoreFeedItemsIfNeeded() {
        guard !isLoadingMoreFeedItems else { return }
        guard canLoadMoreFeedItems else { return }

        isLoadingMoreFeedItems = true
        visibleFeedItemCount = min(visibleFeedItemCount + 50, filteredCards.count)
        isLoadingMoreFeedItems = false
    }

    @MainActor
    private func saveFeed() {
        let trimmed = feedURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSavingFeed else { return }

        isSavingFeed = true
        defer { isSavingFeed = false }

        do {
            try refreshService.saveFeed(urlString: trimmed)
            feedURLString = ""
            onFeedSaved()
            Task {
                await refreshService.refreshNow()
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func openArticle(_ card: RSSFeedItemRecord) {
        guard let url = card.linkURL ?? URL(string: card.linkURLString) else { return }
        NSWorkspace.shared.open(url)
    }

    @MainActor
    private func readAloud(_ card: RSSFeedItemRecord) {
        guard readAloudItemID == nil else { return }
        readAloudItemID = card.id

        Task {
            defer {
                Task { @MainActor in
                    if readAloudItemID == card.id {
                        readAloudItemID = nil
                    }
                }
            }

            do {
                try await onReadAloud(card)
            } catch {
                await MainActor.run {
                    alertMessage = error.localizedDescription
                }
            }
        }
    }
}

struct RSSFeedItemCardView: View {
    let card: RSSFeedItemRecord
    let preferredMode: AppearanceMode
    let isReadAloudLoading: Bool
    let onOpenArticle: () -> Void
    let onReadAloud: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(card.title)
                    .font(.title)
                    .lineLimit(3)

                Text(card.summary.isEmpty ? "No description provided." : card.summary)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)

                HStack(spacing: 8) {
                    Text(card.feedTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ReaderStyle.accentColor(named: "emerald"))
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if let publishedAt = card.publishedAt {
                        Text(RSSFeedDateDisplayFormatter.string(from: publishedAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        onOpenArticle()
                    } label: {
                        Label("Open Article", systemImage: "safari")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hasOpenableArticleURL || isReadAloudLoading)

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
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ReaderStyle.accentColor(named: "emerald"))
                    .disabled(!hasOpenableArticleURL || isReadAloudLoading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var placeholderImage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(ReaderStyle.accentColor(named: "emerald").opacity(preferredMode == .light ? 0.10 : 0.16))

            Image(systemName: "newspaper.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(ReaderStyle.accentColor(named: "emerald"))
        }
        .frame(height: 180)
    }

    private var hasOpenableArticleURL: Bool {
        card.linkURL != nil || URL(string: card.linkURLString) != nil
    }
}

struct RSSFeedItemListRowView: View {
    let card: RSSFeedItemRecord
    let preferredMode: AppearanceMode
    let isReadAloudLoading: Bool
    let onOpenArticle: () -> Void
    let onReadAloud: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            placeholderImage
                .frame(width: 110, height: 110)

            VStack(alignment: .leading, spacing: 10) {
                Text(card.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)

                Text(card.summary.isEmpty ? "No description provided." : card.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                HStack(spacing: 8) {
                    Text(card.feedTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ReaderStyle.accentColor(named: "emerald"))
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if let publishedAt = card.publishedAt {
                        Text(RSSFeedDateDisplayFormatter.string(from: publishedAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        onOpenArticle()
                    } label: {
                        Label("Open Article", systemImage: "safari")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hasOpenableArticleURL || isReadAloudLoading)

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
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ReaderStyle.accentColor(named: "emerald"))
                    .disabled(!hasOpenableArticleURL || isReadAloudLoading)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var placeholderImage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(ReaderStyle.accentColor(named: "emerald").opacity(preferredMode == .light ? 0.10 : 0.16))

            Image(systemName: "newspaper.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(ReaderStyle.accentColor(named: "emerald"))
        }
    }

    private var hasOpenableArticleURL: Bool {
        card.linkURL != nil || URL(string: card.linkURLString) != nil
    }
}

private enum RSSFeedDisplayStyle: String, CaseIterable, Identifiable {
    case list
    case card

    var id: String { rawValue }
}

private enum RSSFeedDateDisplayFormatter {
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

struct RSSAddFeedSheet: View {
    @Binding var feedURLString: String
    @Binding var isSavingFeed: Bool
    let preferredMode: AppearanceMode
    let onSave: () -> Void
    let onClose: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Add Feed Link")
                    .font(.system(size: 30, weight: .bold, design: .rounded))

                Text("Paste an RSS feed URL below. The app will save it in the database and begin fetching items while the app is open.")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    TextField("https://example.com/feed.xml", text: $feedURLString)
                        .textFieldStyle(.roundedBorder)
                        .disableAutocorrection(true)
                        .onSubmit(onSave)

                    if isSavingFeed {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Saving feed...")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button(action: onSave) {
                        if isSavingFeed {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Saving...")
                            }
                        } else {
                            Text("Save Feed")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ReaderStyle.accentColor(named: "emerald"))
                    .disabled(feedURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSavingFeed)
                }

                Spacer(minLength: 0)

                HStack {
                    Spacer(minLength: 0)
                    Button("Close") {
                        onClose()
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(24)
            .frame(minWidth: 560, minHeight: 300)
            .background(
                ReaderStyle.accentColor(named: "emerald").opacity(preferredMode == .light ? 0.08 : 0.12)
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onClose()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct RSSSavedFeedsSheet: View {
    @ObservedObject var refreshService: RSSFeedRefreshService
    let preferredMode: AppearanceMode

    @Environment(\.dismiss) private var dismiss
    @State private var alertMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    if refreshService.subscriptions.isEmpty {
                        ContentUnavailableView(
                            "No saved feeds",
                            systemImage: "dot.radiowaves.left.and.right",
                            description: Text("Save an RSS feed URL in the main screen to see it here.")
                        )
                    } else {
                        ForEach(refreshService.subscriptions) { subscription in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(subscription.url?.host ?? subscription.urlString)
                                            .font(.headline)

                                        Text(subscription.urlString)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    }

                                    Spacer(minLength: 0)

                                    Button(role: .destructive) {
                                        do {
                                            try refreshService.deleteFeed(subscription)
                                        } catch {
                                            alertMessage = error.localizedDescription
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .navigationTitle("Saved Feeds")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }

                Divider()
                    .padding(.horizontal, 20)
                    .padding(.top, 6)

                HStack {
                    Spacer(minLength: 0)
                    Button("Close") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ReaderStyle.accentColor(named: "emerald"))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .alert(
                "RSS Feed",
                isPresented: Binding(
                    get: { alertMessage != nil },
                    set: { if !$0 { alertMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    alertMessage = nil
                }
            } message: {
                Text(alertMessage ?? "The feed could not be deleted.")
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }
}
