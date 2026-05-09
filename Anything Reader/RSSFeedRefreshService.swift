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

struct RSSFeedParsedItem: Sendable {
    let itemIdentifier: String
    let title: String
    let summary: String
    let linkURLString: String
    let imageURLString: String?
    let publishedAt: Date?
}

struct RSSFeedParsedFeed: Sendable {
    let feedTitle: String
    let feedLinkURLString: String?
    let feedImageURLString: String?
    let items: [RSSFeedParsedItem]
}

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
    static let shared = RSSFeedRefreshService()

    private static let seededDefaultsKey = "rssFeedDefaultSubscriptionsSeeded"
    private static let retentionThreshold = 5_000
    private static let retentionKeepCount = 1_000
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

    @Published private(set) var subscriptions: [RSSFeedSubscription] = []
    @Published private(set) var feedItems: [RSSFeedItemRecord] = []
    @Published private(set) var lastRefreshAt: Date?
    @Published private(set) var isRefreshing = false

    private var refreshLoopTask: Task<Void, Never>?
    private var didStart = false

    private init() {}

    func startIfNeeded() {
        guard !didStart else { return }
        didStart = true

        refreshLoopTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshLoop()
        }
    }

    func stop() {
        refreshLoopTask?.cancel()
        refreshLoopTask = nil
        didStart = false
    }

    func saveFeed(urlString: String) throws {
        _ = try RSSFeedSQLiteStore.shared.saveSubscription(from: urlString)
        reloadCachedData()
    }

    func deleteFeed(_ subscription: RSSFeedSubscription) throws {
        try RSSFeedSQLiteStore.shared.deleteSubscription(id: subscription.id)
        reloadCachedData()
    }

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

    var unreadFeedItemCount: Int {
        feedItems.reduce(into: 0) { result, item in
            if !item.hasSeen {
                result += 1
            }
        }
    }

    func refreshNow() async {
        await refreshFeeds()
    }

    private func refreshLoop() async {
        seedDefaultSubscriptionsIfNeeded()
        reloadCachedData()
        await refreshFeeds()

        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: 1_800_000_000_000)
            } catch {
                break
            }

            if Task.isCancelled {
                break
            }

            await refreshFeeds()
        }
    }

    private func seedDefaultSubscriptionsIfNeeded() {
        let userDefaults = UserDefaults.standard
        guard !userDefaults.bool(forKey: Self.seededDefaultsKey) else { return }

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

    private func reloadCachedData() {
        do {
            subscriptions = try RSSFeedSQLiteStore.shared.loadSubscriptions()
            feedItems = try RSSFeedSQLiteStore.shared.loadItems()
        } catch {
            NSLog("RSS cache load failed: %@", error.localizedDescription)
        }
    }

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

    private func refresh(_ subscription: RSSFeedSubscription) async {
        guard let url = subscription.url else { return }

        do {
            let parsed = try await RSSFeedParserService.shared.fetchFeed(from: url)
            let fetchedAt = Date()
            let records = parsed.items.map { item in
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

            try RSSFeedSQLiteStore.shared.replaceItems(for: subscription, feedTitle: parsed.feedTitle, items: records)
            try RSSFeedSQLiteStore.shared.updateLastFetchedAt(for: subscription.id, at: fetchedAt)
        } catch {
            NSLog("RSS feed refresh failed for %@: %@", subscription.urlString, error.localizedDescription)
        }
    }
}

final class RSSFeedParserService {
    static let shared = RSSFeedParserService()

    private init() {}

    func fetchFeed(from url: URL) async throws -> RSSFeedParsedFeed {
        let rssFeed = try await RSSFeed(url: url)
        return parse(rssFeed: rssFeed, fallbackURL: url)
    }

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

    private func stableItemIdentifier(linkURLString: String, title: String, publishedAt: Date?) -> String {
        let dateComponent = publishedAt.map { ISO8601DateFormatter().string(from: $0) } ?? ""
        return "\(linkURLString)|\(title)|\(dateComponent)"
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
