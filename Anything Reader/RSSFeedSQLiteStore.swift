//
//  RSSFeedSQLiteStore.swift
//  Anything Reader
//
//  Persists RSS feed subscriptions in the app's existing SQLite store.
//

import Foundation
import SQLite3

struct RSSFeedSubscription: Identifiable, Hashable, Sendable {
    let id: String
    let urlString: String
    let createdAt: Date
    let lastFetchedAt: Date?

    var url: URL? {
        URL(string: urlString)
    }
}

struct RSSFeedItemRecord: Identifiable, Hashable, Sendable {
    let id: String
    let subscriptionID: String
    let subscriptionURLString: String
    let feedTitle: String
    let itemIdentifier: String
    let title: String
    let summary: String
    let linkURLString: String
    let imageURLString: String?
    let publishedAt: Date?
    let fetchedAt: Date

    var linkURL: URL? {
        URL(string: linkURLString)
    }

    var imageURL: URL? {
        guard let imageURLString else { return nil }
        return URL(string: imageURLString)
    }
}

enum RSSFeedSQLiteStoreError: LocalizedError {
    case databaseOpenFailed
    case statementPreparationFailed
    case statementStepFailed
    case invalidFeedURL

    var errorDescription: String? {
        switch self {
        case .databaseOpenFailed:
            return "The RSS feed database could not be opened."
        case .statementPreparationFailed:
            return "The RSS feed database query could not be prepared."
        case .statementStepFailed:
            return "The RSS feed database query could not be completed."
        case .invalidFeedURL:
            return "Please enter a valid RSS feed URL."
        }
    }
}

enum RSSFeedSaveOutcome {
    case inserted(RSSFeedSubscription)
    case alreadyExists(RSSFeedSubscription)
}

final class RSSFeedSQLiteStore {
    static let shared = RSSFeedSQLiteStore()

    private let appSupportDirectoryName = "Anything Reader"
    private let databaseFileName = "AnythingReader-v7.sqlite"
    private let tableName = "rss_feed_subscriptions"
    private let itemsTableName = "rss_feed_items"
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private init() {}

    func loadSubscriptions() throws -> [RSSFeedSubscription] {
        let database = try openDatabase()
        defer { sqlite3_close(database) }

        try ensureSchema(in: database)
        return try fetchSubscriptions(in: database)
    }

    func saveSubscription(from rawURLString: String) throws -> RSSFeedSaveOutcome {
        let normalizedURLString = try canonicalFeedURLString(from: rawURLString)
        let database = try openDatabase()
        defer { sqlite3_close(database) }

        try ensureSchema(in: database)

        if let existing = try fetchSubscription(for: normalizedURLString, in: database) {
            return .alreadyExists(existing)
        }

        let now = Date.now
        let subscription = RSSFeedSubscription(
            id: UUID().uuidString,
            urlString: normalizedURLString,
            createdAt: now,
            lastFetchedAt: nil
        )

        try insert(subscription, in: database)
        return .inserted(subscription)
    }

    func deleteSubscription(id: String) throws {
        let database = try openDatabase()
        defer { sqlite3_close(database) }

        try ensureSchema(in: database)
        try execute(sql: "DELETE FROM \(itemsTableName) WHERE subscription_id = ?;", bind: { statement in
            bindText(id, to: statement, index: 1)
        }, in: database)
        try execute(sql: "DELETE FROM \(tableName) WHERE id = ?;", bind: { statement in
            bindText(id, to: statement, index: 1)
        }, in: database)
    }

    func loadItems() throws -> [RSSFeedItemRecord] {
        let database = try openDatabase()
        defer { sqlite3_close(database) }

        try ensureSchema(in: database)
        return try fetchItems(in: database)
    }

    func replaceItems(
        for subscription: RSSFeedSubscription,
        feedTitle: String,
        items: [RSSFeedItemRecord]
    ) throws {
        let database = try openDatabase()
        defer { sqlite3_close(database) }

        try ensureSchema(in: database)
        try execute(sql: "DELETE FROM \(itemsTableName) WHERE subscription_id = ?;", bind: { statement in
            bindText(subscription.id, to: statement, index: 1)
        }, in: database)

        for item in items {
            try insert(item, in: database, feedTitle: feedTitle, subscription: subscription)
        }

        try execute(sql: "UPDATE \(tableName) SET last_fetched_at = ? WHERE id = ?;", bind: { statement in
            bindText(dateFormatter.string(from: .now), to: statement, index: 1)
            bindText(subscription.id, to: statement, index: 2)
        }, in: database)
    }

    func updateLastFetchedAt(for subscriptionID: String, at date: Date) throws {
        let database = try openDatabase()
        defer { sqlite3_close(database) }

        try ensureSchema(in: database)
        try execute(sql: "UPDATE \(tableName) SET last_fetched_at = ? WHERE id = ?;", bind: { statement in
            bindText(dateFormatter.string(from: date), to: statement, index: 1)
            bindText(subscriptionID, to: statement, index: 2)
        }, in: database)
    }

    private func fetchSubscriptions(in database: OpaquePointer) throws -> [RSSFeedSubscription] {
        let sql = """
        SELECT id, url_string, created_at, last_fetched_at
        FROM \(tableName)
        ORDER BY created_at DESC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw RSSFeedSQLiteStoreError.statementPreparationFailed
        }
        defer { sqlite3_finalize(statement) }

        var subscriptions: [RSSFeedSubscription] = []
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_DONE {
                break
            }
            guard stepResult == SQLITE_ROW else {
                throw RSSFeedSQLiteStoreError.statementStepFailed
            }

            guard
                let id = stringValue(statement, index: 0),
                let urlString = stringValue(statement, index: 1),
                let createdAt = dateValue(statement, index: 2)
            else {
                continue
            }

            subscriptions.append(
                RSSFeedSubscription(
                    id: id,
                    urlString: urlString,
                    createdAt: createdAt,
                    lastFetchedAt: dateValue(statement, index: 3)
                )
            )
        }

        return subscriptions
    }

    private func fetchSubscription(for urlString: String, in database: OpaquePointer) throws -> RSSFeedSubscription? {
        let sql = """
        SELECT id, url_string, created_at, last_fetched_at
        FROM \(tableName)
        WHERE url_string = ?
        LIMIT 1;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw RSSFeedSQLiteStoreError.statementPreparationFailed
        }
        defer { sqlite3_finalize(statement) }

        bindText(urlString, to: statement, index: 1)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        guard
            let id = stringValue(statement, index: 0),
            let fetchedURLString = stringValue(statement, index: 1),
            let createdAt = dateValue(statement, index: 2)
        else {
            return nil
        }

        return RSSFeedSubscription(
            id: id,
            urlString: fetchedURLString,
            createdAt: createdAt,
            lastFetchedAt: dateValue(statement, index: 3)
        )
    }

    private func insert(_ subscription: RSSFeedSubscription, in database: OpaquePointer) throws {
        let sql = """
        INSERT INTO \(tableName) (id, url_string, created_at, last_fetched_at)
        VALUES (?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw RSSFeedSQLiteStoreError.statementPreparationFailed
        }
        defer { sqlite3_finalize(statement) }

        bindText(subscription.id, to: statement, index: 1)
        bindText(subscription.urlString, to: statement, index: 2)
        bindText(dateFormatter.string(from: subscription.createdAt), to: statement, index: 3)
        sqlite3_bind_null(statement, 4)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw RSSFeedSQLiteStoreError.statementStepFailed
        }
    }

    private func ensureSchema(in database: OpaquePointer) throws {
        let subscriptionSQL = """
        CREATE TABLE IF NOT EXISTS \(tableName) (
            id TEXT PRIMARY KEY NOT NULL,
            url_string TEXT NOT NULL UNIQUE,
            created_at TEXT NOT NULL,
            last_fetched_at TEXT
        );
        """

        let itemsSQL = """
        CREATE TABLE IF NOT EXISTS \(itemsTableName) (
            id TEXT PRIMARY KEY NOT NULL,
            subscription_id TEXT NOT NULL,
            subscription_url_string TEXT NOT NULL,
            feed_title TEXT NOT NULL,
            item_identifier TEXT NOT NULL,
            title TEXT NOT NULL,
            summary TEXT NOT NULL,
            link_url_string TEXT NOT NULL,
            image_url_string TEXT,
            published_at TEXT,
            fetched_at TEXT NOT NULL
        );
        """

        try execute(sql: subscriptionSQL, in: database)
        try execute(sql: itemsSQL, in: database)
    }

    private func execute(sql: String, in database: OpaquePointer) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw RSSFeedSQLiteStoreError.statementPreparationFailed
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw RSSFeedSQLiteStoreError.statementStepFailed
        }
    }

    private func execute(sql: String, bind: (OpaquePointer) -> Void, in database: OpaquePointer) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw RSSFeedSQLiteStoreError.statementPreparationFailed
        }
        defer { sqlite3_finalize(statement) }

        bind(statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw RSSFeedSQLiteStoreError.statementStepFailed
        }
    }

    private func openDatabase() throws -> OpaquePointer {
        let databaseURL = try databaseURL()
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              let database else {
            throw RSSFeedSQLiteStoreError.databaseOpenFailed
        }
        return database
    }

    private func databaseURL() throws -> URL {
        let fileManager = FileManager.default
        let supportDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let appDirectory = supportDirectory.appendingPathComponent(appSupportDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        return appDirectory.appendingPathComponent(databaseFileName, isDirectory: false)
    }

    private func canonicalFeedURLString(from rawURLString: String) throws -> String {
        let trimmed = rawURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RSSFeedSQLiteStoreError.invalidFeedURL
        }

        let candidateString: String
        if trimmed.contains("://") {
            candidateString = trimmed
        } else {
            candidateString = "https://\(trimmed)"
        }

        guard var components = URLComponents(string: candidateString) else {
            throw RSSFeedSQLiteStoreError.invalidFeedURL
        }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        guard let url = components.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw RSSFeedSQLiteStoreError.invalidFeedURL
        }

        return url.absoluteString
    }

    private func bindText(_ value: String, to statement: OpaquePointer, index: Int32) {
        value.utf8CString.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            sqlite3_bind_text(statement, index, baseAddress, -1, Self.sqliteTransient)
        }
    }

    private func stringValue(_ statement: OpaquePointer, index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else { return nil }
        let cCharPointer = UnsafeRawPointer(cString).assumingMemoryBound(to: CChar.self)
        return String(cString: cCharPointer)
    }

    private func dateValue(_ statement: OpaquePointer, index: Int32) -> Date? {
        guard let text = stringValue(statement, index: index) else { return nil }
        return dateFormatter.date(from: text)
    }

    private func fetchItems(in database: OpaquePointer) throws -> [RSSFeedItemRecord] {
        let sql = """
        SELECT id, subscription_id, subscription_url_string, feed_title, item_identifier, title, summary, link_url_string, image_url_string, published_at, fetched_at
        FROM \(itemsTableName)
        ORDER BY published_at DESC, fetched_at DESC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw RSSFeedSQLiteStoreError.statementPreparationFailed
        }
        defer { sqlite3_finalize(statement) }

        var records: [RSSFeedItemRecord] = []
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_DONE {
                break
            }
            guard stepResult == SQLITE_ROW else {
                throw RSSFeedSQLiteStoreError.statementStepFailed
            }

            guard
                let id = stringValue(statement, index: 0),
                let subscriptionID = stringValue(statement, index: 1),
                let subscriptionURLString = stringValue(statement, index: 2),
                let feedTitle = stringValue(statement, index: 3),
                let itemIdentifier = stringValue(statement, index: 4),
                let title = stringValue(statement, index: 5),
                let summary = stringValue(statement, index: 6),
                let linkURLString = stringValue(statement, index: 7),
                let fetchedAt = dateValue(statement, index: 10)
            else {
                continue
            }

            records.append(
                RSSFeedItemRecord(
                    id: id,
                    subscriptionID: subscriptionID,
                    subscriptionURLString: subscriptionURLString,
                    feedTitle: feedTitle,
                    itemIdentifier: itemIdentifier,
                    title: title,
                    summary: summary,
                    linkURLString: linkURLString,
                    imageURLString: stringValue(statement, index: 8),
                    publishedAt: dateValue(statement, index: 9),
                    fetchedAt: fetchedAt
                )
            )
        }

        return records
    }

    private func insert(_ item: RSSFeedItemRecord, in database: OpaquePointer, feedTitle: String, subscription: RSSFeedSubscription) throws {
        let sql = """
        INSERT INTO \(itemsTableName) (id, subscription_id, subscription_url_string, feed_title, item_identifier, title, summary, link_url_string, image_url_string, published_at, fetched_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw RSSFeedSQLiteStoreError.statementPreparationFailed
        }
        defer { sqlite3_finalize(statement) }

        let recordID = stableRecordID(subscriptionID: subscription.id, itemIdentifier: item.itemIdentifier)
        bindText(recordID, to: statement, index: 1)
        bindText(subscription.id, to: statement, index: 2)
        bindText(subscription.urlString, to: statement, index: 3)
        bindText(feedTitle, to: statement, index: 4)
        bindText(item.itemIdentifier, to: statement, index: 5)
        bindText(item.title, to: statement, index: 6)
        bindText(item.summary, to: statement, index: 7)
        bindText(item.linkURLString, to: statement, index: 8)
        if let imageURLString = item.imageURLString {
            bindText(imageURLString, to: statement, index: 9)
        } else {
            sqlite3_bind_null(statement, 9)
        }
        if let publishedAt = item.publishedAt {
            bindText(dateFormatter.string(from: publishedAt), to: statement, index: 10)
        } else {
            sqlite3_bind_null(statement, 10)
        }
        bindText(dateFormatter.string(from: item.fetchedAt), to: statement, index: 11)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw RSSFeedSQLiteStoreError.statementStepFailed
        }
    }

    private func stableRecordID(subscriptionID: String, itemIdentifier: String) -> String {
        "\(subscriptionID)::\(itemIdentifier)"
    }
}
