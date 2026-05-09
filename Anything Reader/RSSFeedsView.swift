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
    let onRequestPushNotificationsPermission: () -> Void

    @AppStorage("rssFeedDisplayStyle") private var rssFeedDisplayStyleRawValue: String = RSSFeedDisplayStyle.list.rawValue
    @AppStorage("rssFeedSourceFilter") private var rssFeedSourceFilterRawValue: String = RSSFeedSourceFilter.all.rawValue
    @State private var feedURLString = ""
    @State private var isSavingFeed = false
    @State private var isShowingAddFeedSheet = false
    @State private var alertMessage: String?
    @State private var readAloudItemID: String?
    @State private var visibleFeedItemCount = 50
    @State private var isLoadingMoreFeedItems = false
    @State private var didResetLargeUnreadBatch = false
    @State private var newFeedPushNotificationsEnabled = false

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
        .onChange(of: rssFeedSourceFilter) { _, _ in
            visibleFeedItemCount = 50
            isLoadingMoreFeedItems = false
        }
        .onChange(of: refreshService.unreadFeedItemCount) { _, newValue in
            if newValue <= 300 {
                didResetLargeUnreadBatch = false
            }
        }
        .sheet(isPresented: $isShowingAddFeedSheet) {
            RSSAddFeedSheet(
                refreshService: refreshService,
                feedURLString: $feedURLString,
                isSavingFeed: $isSavingFeed,
                pushNotificationsEnabled: $newFeedPushNotificationsEnabled,
                preferredMode: preferredMode,
                onSave: saveFeed,
                onRequestPushNotificationsPermission: {
                    onRequestPushNotificationsPermission()
                },
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
                    newFeedPushNotificationsEnabled = false
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
            }

            feedSourceFilterSection

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
                                hasSeen: card.hasSeen,
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
                                hasSeen: card.hasSeen,
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
        .task(id: visibleFeedItemIdentityKey) {
            await markVisibleFeedItemsSeen(after: 1.5, ids: cards.map(\.id))
        }
        .task(id: refreshService.unreadFeedItemCount) {
            await resetUnreadFeedItemsIfNeeded()
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
        let sourceFilter = rssFeedSourceFilter

        return refreshService.feedItems.filter { item in
            let matchesSearch: Bool
            if query.isEmpty {
                matchesSearch = true
            } else {
                matchesSearch = item.title.lowercased().contains(query)
                    || item.summary.lowercased().contains(query)
                    || item.feedTitle.lowercased().contains(query)
                    || item.linkURLString.lowercased().contains(query)
            }

            let matchesSourceFilter: Bool
            switch sourceFilter {
            case .all:
                matchesSourceFilter = true
            case .unread:
                matchesSourceFilter = !item.hasSeen
            case .feedTitle(let feedTitle):
                matchesSourceFilter = item.feedTitle == feedTitle
            }

            return matchesSearch && matchesSourceFilter
        }
    }

    private var visibleCards: [RSSFeedItemRecord] {
        Array(filteredCards.prefix(visibleFeedItemCount))
    }

    private var visibleFeedItemIdentityKey: String {
        visibleCards.map(\.id).joined(separator: "|")
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

    private var rssFeedSourceFilter: RSSFeedSourceFilter {
        get {
            RSSFeedSourceFilter(rawValue: rssFeedSourceFilterRawValue) ?? .all
        }
        nonmutating set {
            rssFeedSourceFilterRawValue = newValue.rawValue
        }
    }

    private var rssFeedSourceFilterBinding: Binding<RSSFeedSourceFilter> {
        Binding(
            get: { rssFeedSourceFilter },
            set: { rssFeedSourceFilter = $0 }
        )
    }

    private var availableFeedTitleFilters: [String] {
        let titles = Set(refreshService.feedItems.map(\.feedTitle))
        return titles.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var feedSourceFilterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Feed Filters")
                .font(.headline.weight(.semibold))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    filterButton(
                        title: "Unread Feeds",
                        isSelected: rssFeedSourceFilter == .unread
                    ) {
                        rssFeedSourceFilter = .unread
                    }

                    filterButton(
                        title: "All Feeds",
                        isSelected: rssFeedSourceFilter == .all
                    ) {
                        rssFeedSourceFilter = .all
                    }

                    ForEach(availableFeedTitleFilters, id: \.self) { title in
                        filterButton(
                            title: title,
                            isSelected: rssFeedSourceFilter == .feedTitle(title)
                        ) {
                            rssFeedSourceFilter = .feedTitle(title)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor
    private func markVisibleFeedItemsSeen(after delay: TimeInterval, ids: [String]) async {
        guard !ids.isEmpty else { return }

        do {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            try refreshService.markFeedItemsSeen(ids: ids)
        } catch {
            if !(error is CancellationError) {
                NSLog("RSS seen-state update failed: %@", error.localizedDescription)
            }
        }
    }

    private func filterButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.white : .primary)
        .background(
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(
                    isSelected
                    ? ReaderStyle.accentColor(named: "emerald")
                    : Color.secondary.opacity(preferredMode == .light ? 0.12 : 0.18)
                )
        )
    }

    @MainActor
    private func resetUnreadFeedItemsIfNeeded() async {
        guard refreshService.unreadFeedItemCount > 300 else { return }
        guard !didResetLargeUnreadBatch else { return }

        didResetLargeUnreadBatch = true

        do {
            try await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            guard refreshService.unreadFeedItemCount > 300 else { return }
            try refreshService.markAllFeedItemsSeen()
        } catch {
            if !(error is CancellationError) {
                NSLog("RSS bulk seen reset failed: %@", error.localizedDescription)
            }
        }
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
            try refreshService.saveFeed(
                urlString: trimmed,
                pushNotificationsEnabled: newFeedPushNotificationsEnabled
            )
            feedURLString = ""
            newFeedPushNotificationsEnabled = false
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
    let hasSeen: Bool
    let isReadAloudLoading: Bool
    let onOpenArticle: () -> Void
    let onReadAloud: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(card.title)
                        .font(.title)
                        .lineLimit(3)

                    if !hasSeen {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Unread")
                    }
                }

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
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(hasSeen ? Color.clear : Color.orange.opacity(0.55), lineWidth: 1.5)
        )
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

    private var cardBackground: AnyShapeStyle {
        if hasSeen {
            return AnyShapeStyle(.thinMaterial)
        }

        return preferredMode == .light
            ? AnyShapeStyle(Color.orange.opacity(0.08))
            : AnyShapeStyle(Color.orange.opacity(0.14))
    }
}

struct RSSFeedItemListRowView: View {
    let card: RSSFeedItemRecord
    let preferredMode: AppearanceMode
    let hasSeen: Bool
    let isReadAloudLoading: Bool
    let onOpenArticle: () -> Void
    let onReadAloud: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            placeholderImage
                .frame(width: 110, height: 110)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(card.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)

                    if !hasSeen {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Unread")
                    }
                }

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
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(hasSeen ? Color.clear : Color.orange.opacity(0.55), lineWidth: 1.5)
        )
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

    private var rowBackground: AnyShapeStyle {
        if hasSeen {
            return AnyShapeStyle(.thinMaterial)
        }

        return preferredMode == .light
            ? AnyShapeStyle(Color.orange.opacity(0.08))
            : AnyShapeStyle(Color.orange.opacity(0.14))
    }
}

private enum RSSFeedDisplayStyle: String, CaseIterable, Identifiable {
    case list
    case card

    var id: String { rawValue }
}

private enum RSSFeedSourceFilter: Hashable {
    case all
    case unread
    case feedTitle(String)

    static let allRawValue = "all"
    static let unreadRawValue = "unread"

    var rawValue: String {
        switch self {
        case .all:
            return Self.allRawValue
        case .unread:
            return Self.unreadRawValue
        case .feedTitle(let title):
            return title
        }
    }

    init?(rawValue: String) {
        guard rawValue != Self.allRawValue else {
            self = .all
            return
        }

        guard rawValue != Self.unreadRawValue else {
            self = .unread
            return
        }

        guard !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        self = .feedTitle(rawValue)
    }
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
    @ObservedObject var refreshService: RSSFeedRefreshService
    @Binding var feedURLString: String
    @Binding var isSavingFeed: Bool
    @Binding var pushNotificationsEnabled: Bool
    let preferredMode: AppearanceMode
    let onSave: () -> Void
    let onRequestPushNotificationsPermission: () -> Void
    let onClose: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var feedPendingDeletion: RSSFeedSubscription?

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

                    Toggle(isOn: $pushNotificationsEnabled) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Push Notifications")
                                .font(.subheadline.weight(.semibold))
                            Text("Notify me when this feed publishes new items.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .onChange(of: pushNotificationsEnabled) { _, newValue in
                        guard newValue else { return }

                        Task {
                            let allowed = await RSSPushNotificationService.shared.requestNotificationAuthorizationIfNeeded()
                            guard allowed else {
                                await MainActor.run {
                                    pushNotificationsEnabled = false
                                    requestPushNotificationsPermissionAfterDismissal()
                                }
                                return
                            }
                        }
                    }

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

                VStack(alignment: .leading, spacing: 12) {
                    Text("Saved Feeds")
                        .font(.headline.weight(.semibold))

                    if refreshService.subscriptions.isEmpty {
                        ContentUnavailableView(
                            "No saved feeds",
                            systemImage: "dot.radiowaves.left.and.right",
                            description: Text("Save an RSS feed URL to see it listed here.")
                        )
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 10) {
                                ForEach(refreshService.subscriptions) { subscription in
                                    RSSSavedFeedRowView(
                                        subscription: subscription,
                                        preferredMode: preferredMode,
                                        onDelete: {
                                            feedPendingDeletion = subscription
                                        },
                                        onRequestPushNotificationsPermission: {
                                            requestPushNotificationsPermissionAfterDismissal()
                                        },
                                        onTogglePushNotificationsEnabled: { newValue in
                                            try refreshService.updatePushNotificationsEnabled(
                                                for: subscription,
                                                enabled: newValue
                                            )
                                        }
                                    )
                                    .id(subscription.id)
                                }
                            }
                        }
                        .frame(maxHeight: .infinity)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 4)
            .frame(minWidth: 560, minHeight: 300)
            .background(
                ReaderStyle.accentColor(named: "emerald").opacity(preferredMode == .light ? 0.08 : 0.12)
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") {
                        onClose()
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "Delete Saved Feed",
                isPresented: Binding(
                    get: { feedPendingDeletion != nil },
                    set: { if !$0 { feedPendingDeletion = nil } }
                ),
                presenting: feedPendingDeletion
            ) { subscription in
                Button("Delete Feed", role: .destructive) {
                    do {
                        try refreshService.deleteFeed(subscription)
                    } catch {
                        // Keep the sheet open; the save sheet already exposes the remaining feeds.
                    }
                }

                Button("Cancel", role: .cancel) {
                    feedPendingDeletion = nil
                }
            } message: { subscription in
                Text("Delete \(subscription.url?.host ?? subscription.urlString)? This removes the saved feed link from the database.")
            }
        }
    }

    @MainActor
    private func requestPushNotificationsPermissionAfterDismissal() {
        onClose()
        dismiss()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            onRequestPushNotificationsPermission()
        }
    }
}
private struct RSSSavedFeedRowView: View {
    let subscription: RSSFeedSubscription
    let preferredMode: AppearanceMode
    let onDelete: () -> Void
    let onRequestPushNotificationsPermission: () -> Void
    let onTogglePushNotificationsEnabled: (Bool) throws -> Void

    @State private var isPushNotificationsEnabled: Bool
    @State private var isUpdatingPushNotifications = false

    init(
        subscription: RSSFeedSubscription,
        preferredMode: AppearanceMode,
        onDelete: @escaping () -> Void,
        onRequestPushNotificationsPermission: @escaping () -> Void,
        onTogglePushNotificationsEnabled: @escaping (Bool) throws -> Void
    ) {
        self.subscription = subscription
        self.preferredMode = preferredMode
        self.onDelete = onDelete
        self.onRequestPushNotificationsPermission = onRequestPushNotificationsPermission
        self.onTogglePushNotificationsEnabled = onTogglePushNotificationsEnabled
        _isPushNotificationsEnabled = State(initialValue: subscription.pushNotificationsEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
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
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.borderless)
            }

            Toggle(isOn: $isPushNotificationsEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Push Notifications")
                        .font(.subheadline.weight(.semibold))
                    Text("Notify me when this feed publishes new items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .disabled(isUpdatingPushNotifications)
            .onChange(of: isPushNotificationsEnabled) { _, newValue in
                handleToggleChange(newValue)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.secondary.opacity(preferredMode == .light ? 0.08 : 0.14))
        )
        .onChange(of: subscription.pushNotificationsEnabled) { _, newValue in
            guard newValue != isPushNotificationsEnabled else { return }
            isPushNotificationsEnabled = newValue
        }
    }

    @MainActor
    private func handleToggleChange(_ newValue: Bool) {
        guard !isUpdatingPushNotifications else { return }

        isUpdatingPushNotifications = true
        Task {
            defer {
                Task { @MainActor in
                    isUpdatingPushNotifications = false
                }
            }

            if newValue {
                let allowed = await RSSPushNotificationService.shared.requestNotificationAuthorizationIfNeeded()
                guard allowed else {
                    await MainActor.run {
                        isPushNotificationsEnabled = false
                        onRequestPushNotificationsPermission()
                    }
                    return
                }
            }

            do {
                try onTogglePushNotificationsEnabled(newValue)
            } catch {
                NSLog("RSS push notification toggle failed: %@", error.localizedDescription)
                await MainActor.run {
                    isPushNotificationsEnabled = subscription.pushNotificationsEnabled
                }
            }
        }
    }
}

struct RSSPushNotificationsPermissionSheet: View {
    let preferredMode: AppearanceMode
    let onClose: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Enable Push Notifications")
                    .font(.system(size: 30, weight: .bold, design: .rounded))

                Text("Anything Reader needs notification access in System Settings before it can notify you about new RSS items.")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text("Open System Settings, choose Notifications, and enable Anything Reader.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Link(destination: URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!) {
                    Label("Open Notification Settings", systemImage: "gearshape")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 4)
            .frame(minWidth: 520, minHeight: 220)
            .background(
                ReaderStyle.accentColor(named: "emerald").opacity(preferredMode == .light ? 0.08 : 0.12)
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") {
                        onClose()
                        dismiss()
                    }
                }
            }
        }
    }
}
