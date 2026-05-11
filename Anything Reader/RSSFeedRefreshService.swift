//
//  RSSFeedRefreshService.swift
//  Anything Reader
//
//  Keeps the RSS feed cache warm while the app is running.
//

import Foundation
import Combine
import AppKit
import FeedKit

// Parsed RSS item payload used to move data out of FeedKit and into our store layer
// without keeping the parser dependency around in the rest of the app.
struct RSSFeedParsedItem: Sendable {
    let itemIdentifier: String
    let title: String
    let summary: String
    let linkURLString: String
    let imageURLString: String?
    let publishedAt: Date?
}

// Parsed RSS feed payload used after normalization so the refresh service can
// write records and trigger notifications without depending on FeedKit objects directly.
struct RSSFeedParsedFeed: Sendable {
    let feedTitle: String
    let feedLinkURLString: String?
    let feedImageURLString: String?
    let items: [RSSFeedParsedItem]
}

// Errors surfaced when we cannot turn a feed URL into a parseable RSS feed.
enum RSSFeedRefreshError: LocalizedError {
    case invalidFeedURL
    case feedParsingFailed

    var errorDescription: String? {
        switch self {
        case .invalidFeedURL:
            return "The feed URL is not valid."
        case .feedParsingFailed:
            return "The feed could not be parsed."
        }
    }
}

@MainActor
final class RSSFeedRefreshService: ObservableObject {
    // Shared singleton because the app treats RSS refresh as one global service
    // that owns the refresh loop and the cached feed state.
    static let shared = RSSFeedRefreshService()

    // Prevents seeding the default subscriptions more than once.
    private static let seededDefaultsKey = "rssFeedDefaultSubscriptionsSeeded"
    // If the cache grows beyond this many items, older rows are pruned.
    private static let retentionThreshold = 5_000
    // Number of newest items we keep when retention cleanup runs.
    private static let retentionKeepCount = 1_000
    // Built-in feeds the app adds the first time RSS is used.
    private static let defaultSubscriptionURLs = [
        "https://techcrunch.com/rss",
        "https://openai.com/blog/rss.xml",
        "https://huggingface.co/blog/feed.xml",
        "https://deepmind.google/blog/rss.xml",
        "https://www.theverge.com/rss/index.xml",
        "https://feeds.npr.org/1001/rss.xml",
        "https://feeds.npr.org/1001/rss.xml",
        "https://feeds.bbci.co.uk/news/rss.xml"
    ]

    // In-memory mirror of the SQLite-backed RSS subscriptions table.
    @Published private(set) var subscriptions: [RSSFeedSubscription] = []
    // In-memory mirror of the SQLite-backed RSS items table.
    @Published private(set) var feedItems: [RSSFeedItemRecord] = []
    // Timestamp of the most recent successful refresh.
    @Published private(set) var lastRefreshAt: Date?
    // Prevents overlapping refresh work.
    @Published private(set) var isRefreshing = false

    // The background loop task that keeps the RSS cache current.
    private var refreshLoopTask: Task<Void, Never>?
    // Guards the one-time start path so we do not launch duplicate loops.
    private var didStart = false

    private init() {}

    // Starts the refresh loop once per app lifetime.
    func startIfNeeded() {
        guard !didStart else { return }
        didStart = true

        refreshLoopTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshLoop()
        }
    }

    // Stops the refresh loop and clears the task handle.
    func stop() {
        refreshLoopTask?.cancel()
        refreshLoopTask = nil
        didStart = false
    }

    // Saves a feed subscription and reloads the cached subscriptions/items.
    func saveFeed(urlString: String) throws {
        _ = try RSSFeedSQLiteStore.shared.saveSubscription(from: urlString)
        reloadCachedData()
    }

    // Saves a feed subscription with push notification state and keeps the
    // in-memory cache aligned with the SQLite store.
    func saveFeed(urlString: String, pushNotificationsEnabled: Bool) throws {
        let outcome = try RSSFeedSQLiteStore.shared.saveSubscription(
            from: urlString,
            pushNotificationsEnabled: pushNotificationsEnabled
        )

        let subscription: RSSFeedSubscription
        switch outcome {
        case .inserted(let insertedSubscription):
            subscription = insertedSubscription
        case .alreadyExists(let existingSubscription):
            subscription = existingSubscription
        }

        if pushNotificationsEnabled {
            try RSSFeedSQLiteStore.shared.updatePushNotificationsEnabled(
                for: subscription.id,
                enabled: true
            )
        }

        reloadCachedData()
    }

    // Deletes one subscription from SQLite and refreshes the in-memory cache.
    func deleteFeed(_ subscription: RSSFeedSubscription) throws {
        try RSSFeedSQLiteStore.shared.deleteSubscription(id: subscription.id)
        reloadCachedData()
    }

    // Updates the push-notification flag for a single subscription.
    func updatePushNotificationsEnabled(for subscription: RSSFeedSubscription, enabled: Bool) throws {
        try RSSFeedSQLiteStore.shared.updatePushNotificationsEnabled(for: subscription.id, enabled: enabled)
        subscriptions = subscriptions.map { existing in
            guard existing.id == subscription.id else { return existing }
            return RSSFeedSubscription(
                id: existing.id,
                urlString: existing.urlString,
                createdAt: existing.createdAt,
                lastFetchedAt: existing.lastFetchedAt,
                pushNotificationsEnabled: enabled
            )
        }
    }

    // Marks selected feed items as seen in both SQLite and the local cache.
    func markFeedItemsSeen(ids: [String]) throws {
        try RSSFeedSQLiteStore.shared.markItemsSeen(ids: ids)

        let seenIDs = Set(ids)
        feedItems = feedItems.map { item in
            guard seenIDs.contains(item.id), !item.hasSeen else {
                return item
            }

            return RSSFeedItemRecord(
                id: item.id,
                subscriptionID: item.subscriptionID,
                subscriptionURLString: item.subscriptionURLString,
                feedTitle: item.feedTitle,
                itemIdentifier: item.itemIdentifier,
                title: item.title,
                summary: item.summary,
                linkURLString: item.linkURLString,
                imageURLString: item.imageURLString,
                publishedAt: item.publishedAt,
                fetchedAt: item.fetchedAt,
                hasSeen: true
            )
        }
    }

    // Bulk mark all items as seen and mirror that state in memory.
    func markAllFeedItemsSeen() throws {
        try RSSFeedSQLiteStore.shared.markAllItemsSeen()
        feedItems = feedItems.map { item in
            guard !item.hasSeen else {
                return item
            }

            return RSSFeedItemRecord(
                id: item.id,
                subscriptionID: item.subscriptionID,
                subscriptionURLString: item.subscriptionURLString,
                feedTitle: item.feedTitle,
                itemIdentifier: item.itemIdentifier,
                title: item.title,
                summary: item.summary,
                linkURLString: item.linkURLString,
                imageURLString: item.imageURLString,
                publishedAt: item.publishedAt,
                fetchedAt: item.fetchedAt,
                hasSeen: true
            )
        }
    }

    // Unread count is derived from the cached feed items instead of recomputing
    // it from the database on every UI render.
    var unreadFeedItemCount: Int {
        feedItems.reduce(into: 0) { result, item in
            if !item.hasSeen {
                result += 1
            }
        }
    }

    // Forces an immediate refresh, which is used by the UI's refresh controls.
    func refreshNow() async {
        await refreshFeeds()
    }

    // Main background loop: seed defaults, warm the cache, then refresh every 15 minutes.
    private func refreshLoop() async {
        seedDefaultSubscriptionsIfNeeded()
        reloadCachedData()
        await refreshFeeds()

        while !Task.isCancelled {
            do {
                // Keep the loop quiet between refreshes so we do not spam the network.
                try await Task.sleep(nanoseconds: 900_000_000_000)
            } catch {
                break
            }

            if Task.isCancelled {
                break
            }

            await refreshFeeds()
        }
    }

    // Seeds first-run RSS subscriptions once per install.
    private func seedDefaultSubscriptionsIfNeeded() {
        let userDefaults = UserDefaults.standard
        guard !userDefaults.bool(forKey: Self.seededDefaultsKey) else { return }

        // Deduplicate URLs so the bootstrap list does not create duplicate rows.
        let uniqueURLs = Self.defaultSubscriptionURLs.reduce(into: [String]()) { result, urlString in
            if !result.contains(urlString) {
                result.append(urlString)
            }
        }

        do {
            for urlString in uniqueURLs {
                _ = try RSSFeedSQLiteStore.shared.saveSubscription(from: urlString)
            }
            userDefaults.set(true, forKey: Self.seededDefaultsKey)
        } catch {
            NSLog("RSS default feed seed failed: %@", error.localizedDescription)
        }
    }

    // Reloads subscriptions and items from SQLite into the @Published caches.
    private func reloadCachedData() {
        do {
            subscriptions = try RSSFeedSQLiteStore.shared.loadSubscriptions()
            feedItems = try RSSFeedSQLiteStore.shared.loadItems()
        } catch {
            NSLog("RSS cache load failed: %@", error.localizedDescription)
        }
    }

    // Refreshes each active subscription, updates read state, then applies retention cleanup.
    private func refreshFeeds() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let currentSubscriptions = try RSSFeedSQLiteStore.shared.loadSubscriptions()
            subscriptions = currentSubscriptions

            for subscription in currentSubscriptions {
                await refresh(subscription)
            }

            await maintainFeedReadState()
            feedItems = try RSSFeedSQLiteStore.shared.loadItems()
            lastRefreshAt = .now
            await cleanupFeedItemsIfNeeded()
        } catch {
            NSLog("RSS refresh failed: %@", error.localizedDescription)
        }
    }

    // Keeps the unread state sane by aging out old content and enforcing a cap
    // on unread items when feeds have grown too large.
    private func maintainFeedReadState() async {
        do {
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -2, to: .now) ?? Date().addingTimeInterval(-172_800)
            try RSSFeedSQLiteStore.shared.markItemsSeen(olderThan: cutoffDate)

            let unreadCount = try RSSFeedSQLiteStore.shared.unreadItemCount()
            if unreadCount > 300 {
                try RSSFeedSQLiteStore.shared.markAllItemsSeen()
            }

            feedItems = try RSSFeedSQLiteStore.shared.loadItems()
        } catch {
            NSLog("RSS read-state maintenance failed: %@", error.localizedDescription)
        }
    }

    // Prunes the RSS table only when it exceeds the retention threshold.
    private func cleanupFeedItemsIfNeeded() async {
        do {
            let count = try RSSFeedSQLiteStore.shared.itemCount()
            guard count > Self.retentionThreshold else { return }

            try RSSFeedSQLiteStore.shared.pruneItemsKeepingLatest(Self.retentionKeepCount)
            feedItems = try RSSFeedSQLiteStore.shared.loadItems()
        } catch {
            NSLog("RSS retention cleanup failed: %@", error.localizedDescription)
        }
    }

    // Refreshes one subscription by fetching, parsing, storing, and notifying on new items.
    private func refresh(_ subscription: RSSFeedSubscription) async {
        guard let url = subscription.url else { return }

        do {
            // Capture the previous identifiers first so we can identify newly arrived items.
            let previousItemIdentifiers = try RSSFeedSQLiteStore.shared.loadItemIdentifiers(for: subscription.id)
            let parsed = try await RSSFeedParserService.shared.fetchFeed(from: url)
            let fetchedAt = Date()
            let records = parsed.items.map { item in
                // Use the fetch time as a fallback when the feed item does not carry a publication date.
                let publishedAt = item.publishedAt ?? fetchedAt
                return RSSFeedItemRecord(
                    id: "\(subscription.id)::\(item.itemIdentifier)",
                    subscriptionID: subscription.id,
                    subscriptionURLString: subscription.urlString,
                    feedTitle: parsed.feedTitle,
                    itemIdentifier: item.itemIdentifier,
                    title: item.title,
                    summary: item.summary,
                    linkURLString: item.linkURLString,
                    imageURLString: item.imageURLString ?? parsed.feedImageURLString,
                    publishedAt: publishedAt,
                    fetchedAt: fetchedAt,
                    hasSeen: false
                )
            }

            // Replace the subscription's items in SQLite so the feed stays current.
            try RSSFeedSQLiteStore.shared.replaceItems(for: subscription, feedTitle: parsed.feedTitle, items: records)
            try RSSFeedSQLiteStore.shared.updateLastFetchedAt(for: subscription.id, at: fetchedAt)

            // Only notify after the feed has already been fetched at least once.
            if subscription.pushNotificationsEnabled, subscription.lastFetchedAt != nil {
                let newItems = records.filter { !previousItemIdentifiers.contains($0.itemIdentifier) }
                if !newItems.isEmpty {
                    await RSSPushNotificationService.shared.scheduleNewItemNotifications(
                        feedTitle: parsed.feedTitle,
                        items: newItems
                    )
                }
            }
        } catch {
            NSLog("RSS feed refresh failed for %@: %@", subscription.urlString, error.localizedDescription)
        }
    }
}

// Parser wrapper around FeedKit. This keeps FeedKit details isolated to one place
// and returns simple value types that the rest of the app can consume.
final class RSSFeedParserService {
    static let shared = RSSFeedParserService()

    private init() {}

    // Loads a feed and normalizes it into app-specific value types.
    func fetchFeed(from url: URL) async throws -> RSSFeedParsedFeed {
        let rssFeed = try await RSSFeed(url: url)
        return parse(rssFeed: rssFeed, fallbackURL: url)
    }

    // Converts FeedKit models into lightweight parsed records with fallbacks for missing data.
    private func parse(rssFeed: RSSFeed, fallbackURL: URL) -> RSSFeedParsedFeed {
        guard let channel = rssFeed.channel else {
            return RSSFeedParsedFeed(
                feedTitle: fallbackURL.host ?? fallbackURL.absoluteString,
                feedLinkURLString: fallbackURL.absoluteString,
                feedImageURLString: nil,
                items: []
            )
        }

        let feedTitle = channel.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? fallbackURL.host ?? fallbackURL.absoluteString
        let feedLinkURLString = channel.link?.trimmingCharacters(in: .whitespacesAndNewlines)
        let feedImageURLString = channel.image?.url?.trimmingCharacters(in: .whitespacesAndNewlines)

        // Each feed item is normalized into a stable identifier plus plain text summary.
        let items = (channel.items ?? []).compactMap { item in
            let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Untitled Item"
            let linkURLString = item.link?.trimmingCharacters(in: .whitespacesAndNewlines) ?? feedLinkURLString ?? fallbackURL.absoluteString
            let summary = plainText(from: item.description)
            let itemIdentifier = stableItemIdentifier(linkURLString: linkURLString, title: title, publishedAt: item.pubDate)

            return RSSFeedParsedItem(
                itemIdentifier: itemIdentifier,
                title: title,
                summary: summary,
                linkURLString: linkURLString,
                imageURLString: feedImageURLString,
                publishedAt: item.pubDate
            )
        }

        return RSSFeedParsedFeed(
            feedTitle: feedTitle,
            feedLinkURLString: feedLinkURLString,
            feedImageURLString: feedImageURLString,
            items: items
        )
    }

    // Converts HTML summaries to readable plain text so the list UI and notifications stay compact.
    private func plainText(from html: String?) -> String {
        guard let html, !html.isEmpty else { return "" }

        if let data = html.data(using: .utf8),
           let attributed = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
           ) {
            return attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return html
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Builds a stable item key from the URL, title, and date so the database
    // can detect whether a feed item is new across refresh cycles.
    private func stableItemIdentifier(linkURLString: String, title: String, publishedAt: Date?) -> String {
        let dateComponent = publishedAt.map { ISO8601DateFormatter().string(from: $0) } ?? ""
        return "\(linkURLString)|\(title)|\(dateComponent)"
    }
}

// Small helper for keeping blank strings out of feed titles and summaries.
private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
