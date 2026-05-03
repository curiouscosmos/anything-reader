//
//  FreeBooksCatalogStore.swift
//  Anything Reader
//
//  Handles download and local reading of the free books SQLite catalog.
//

import Combine
import Foundation
import SQLite3

@MainActor
final class FreeBooksCatalogStore: ObservableObject {
    static let shared = FreeBooksCatalogStore()

    @Published private(set) var books: [FreeBook] = []
    @Published private(set) var totalBooksCount = 0
    @Published var selectedLanguageFilter: FreeBookLanguageFilter = .all
    @Published private(set) var isLoadingBooks = false
    @Published private(set) var isLoadingMoreBooks = false
    @Published private(set) var isDownloadingDatabase = false
    @Published private(set) var errorMessage: String?

    private let fileManager = FileManager.default
    private let catalogURL = URL(string: "https://sandalbar.s3.us-west-2.amazonaws.com/books/books.sqlite")!
    private let pageSize = 12
    private var didAttemptInitialLoad = false

    var isDatabaseDownloaded: Bool {
        fileManager.fileExists(atPath: localDatabaseURL.path)
    }

    var localDatabaseURL: URL {
        appSupportDirectory().appendingPathComponent("Free Books", isDirectory: true)
            .appendingPathComponent("books.sqlite")
    }

    func loadCatalogIfNeeded() async {
        guard !didAttemptInitialLoad else { return }
        didAttemptInitialLoad = true
        await refreshCatalog()
    }

    func setLanguageFilter(_ filter: FreeBookLanguageFilter) async {
        guard selectedLanguageFilter != filter else { return }
        selectedLanguageFilter = filter
        await refreshCatalog()
    }

    func refreshCatalog() async {
        guard isDatabaseDownloaded else {
            books = []
            totalBooksCount = 0
            return
        }

        isLoadingBooks = true
        errorMessage = nil
        defer { isLoadingBooks = false }

        do {
            let result = try await Self.loadBooks(
                from: localDatabaseURL,
                limit: pageSize,
                offset: 0,
                languageFilter: selectedLanguageFilter
            )
            books = result.books
            totalBooksCount = result.totalCount
        } catch {
            books = []
            totalBooksCount = 0
            errorMessage = "Could not read the free books catalog: \(error.localizedDescription)"
        }
    }

    func loadNextPage() async {
        guard isDatabaseDownloaded else { return }
        guard !isLoadingBooks else { return }
        guard !isLoadingMoreBooks else { return }
        guard books.count < totalBooksCount || totalBooksCount == 0 else { return }

        isLoadingMoreBooks = true
        errorMessage = nil
        defer { isLoadingMoreBooks = false }

        do {
            if totalBooksCount == 0 {
                totalBooksCount = try Self.countBooks(in: localDatabaseURL, languageFilter: selectedLanguageFilter)
            }

            let result = try await Self.loadBooks(
                from: localDatabaseURL,
                limit: pageSize,
                offset: books.count,
                languageFilter: selectedLanguageFilter
            )
            books.append(contentsOf: result.books)
            totalBooksCount = result.totalCount
        } catch {
            errorMessage = "Could not load more free books: \(error.localizedDescription)"
        }
    }

    func downloadCatalog() async {
        guard !isDownloadingDatabase else { return }

        isDownloadingDatabase = true
        errorMessage = nil
        defer { isDownloadingDatabase = false }

        do {
            try ensureDatabaseDirectoryExists()

            let (temporaryURL, response) = try await URLSession.shared.download(from: catalogURL)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                throw CatalogDownloadError.invalidResponse
            }

            if fileManager.fileExists(atPath: localDatabaseURL.path) {
                try fileManager.removeItem(at: localDatabaseURL)
            }

            try fileManager.moveItem(at: temporaryURL, to: localDatabaseURL)
            let result = try await Self.loadBooks(
                from: localDatabaseURL,
                limit: pageSize,
                offset: 0,
                languageFilter: selectedLanguageFilter
            )
            books = result.books
            totalBooksCount = result.totalCount
        } catch {
            books = []
            totalBooksCount = 0
            errorMessage = "Could not download the free books catalog: \(error.localizedDescription)"
        }
    }

    private static func loadBooks(
        from databaseURL: URL,
        limit: Int,
        offset: Int,
        languageFilter: FreeBookLanguageFilter
    ) async throws -> (books: [FreeBook], totalCount: Int) {
        try await Task.detached(priority: .utility) {
            let totalCount = try countBooks(in: databaseURL, languageFilter: languageFilter)
            let books = try readBooks(from: databaseURL, limit: limit, offset: offset, languageFilter: languageFilter)
            return (books, totalCount)
        }.value
    }

    nonisolated private static func readBooks(
        from databaseURL: URL,
        limit: Int,
        offset: Int,
        languageFilter: FreeBookLanguageFilter
    ) throws -> [FreeBook] {
        try withDatabase(at: databaseURL) { database in
            try validateCatalogSchema(database)

            let query = FreeBooksSQLiteHelpers.filteredBooksQuery(baseSQL:
                """
                SELECT id, title, authors, languages, subjects, bookshelves, epub, pdf, txt, html, cover
                FROM books
                """
            , languageFilter: languageFilter, includePagination: true)

            let sql = query.sql
            let bindCount = query.bindValues.count

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw CatalogDatabaseError.queryFailed
            }
            defer { sqlite3_finalize(statement) }

            for (index, value) in query.bindValues.enumerated() {
                FreeBooksSQLiteHelpers.bindText(value, to: statement, index: Int32(index + 1))
            }

            sqlite3_bind_int(statement, Int32(bindCount + 1), Int32(max(1, limit)))
            sqlite3_bind_int(statement, Int32(bindCount + 2), Int32(max(0, offset)))

            var loadedBooks: [FreeBook] = []
            loadedBooks.reserveCapacity(min(limit, 256))

            while sqlite3_step(statement) == SQLITE_ROW {
                loadedBooks.append(
                    FreeBook(
                        id: sqlite3_column_int64(statement, 0),
                        title: stringColumn(statement, index: 1) ?? "Untitled",
                        authors: stringColumn(statement, index: 2),
                        languages: stringColumn(statement, index: 3),
                        subjects: stringColumn(statement, index: 4),
                        bookshelves: stringColumn(statement, index: 5),
                        epub: stringColumn(statement, index: 6),
                        pdf: stringColumn(statement, index: 7),
                        txt: stringColumn(statement, index: 8),
                        html: stringColumn(statement, index: 9),
                        cover: stringColumn(statement, index: 10)
                    )
                )
            }

            return loadedBooks
        }
    }

    nonisolated private static func countBooks(
        in databaseURL: URL,
        languageFilter: FreeBookLanguageFilter
    ) throws -> Int {
        try withDatabase(at: databaseURL) { database in
            try validateCatalogSchema(database)

            let query = FreeBooksSQLiteHelpers.filteredBooksQuery(
                baseSQL: "SELECT COUNT(*) FROM books",
                languageFilter: languageFilter,
                includePagination: false
            )

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, query.sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw CatalogDatabaseError.queryFailed
            }
            defer { sqlite3_finalize(statement) }

            for (index, value) in query.bindValues.enumerated() {
                FreeBooksSQLiteHelpers.bindText(value, to: statement, index: Int32(index + 1))
            }

            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw CatalogDatabaseError.queryFailed
            }

            return Int(sqlite3_column_int64(statement, 0))
        }
    }

    nonisolated private static func validateCatalogSchema(_ database: OpaquePointer) throws {
        let requiredColumns: Set<String> = [
            "id",
            "title",
            "authors",
            "languages",
            "subjects",
            "bookshelves",
            "epub",
            "pdf",
            "txt",
            "html",
            "cover"
        ]

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(books);", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw CatalogDatabaseError.schemaLookupFailed
        }
        defer { sqlite3_finalize(statement) }

        var columns: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let columnName = stringColumn(statement, index: 1) {
                columns.insert(columnName)
            }
        }

        guard !columns.isEmpty else {
            throw CatalogDatabaseError.missingBooksTable
        }

        guard requiredColumns.isSubset(of: columns) else {
            throw CatalogDatabaseError.missingRequiredColumns
        }
    }

    nonisolated private static func withDatabase<T>(at url: URL, _ body: (OpaquePointer) throws -> T) throws -> T {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else {
            throw CatalogDatabaseError.openFailed
        }
        defer { sqlite3_close(database) }

        return try body(database)
    }

    nonisolated private static func stringColumn(_ statement: OpaquePointer, index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cString)
    }

    private func ensureDatabaseDirectoryExists() throws {
        let directoryURL = localDatabaseURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    private func appSupportDirectory() -> URL {
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return supportDirectory ?? fileManager.temporaryDirectory
    }

    private enum CatalogDownloadError: LocalizedError {
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "The downloaded file could not be verified."
            }
        }
    }

    private enum CatalogDatabaseError: LocalizedError {
        case openFailed
        case schemaLookupFailed
        case missingBooksTable
        case missingRequiredColumns
        case queryFailed

        var errorDescription: String? {
            switch self {
            case .openFailed:
                return "The SQLite database could not be opened."
            case .schemaLookupFailed:
                return "The SQLite schema could not be inspected."
            case .missingBooksTable:
                return "The SQLite database does not contain a books table."
            case .missingRequiredColumns:
                return "The books table is missing one or more required columns."
            case .queryFailed:
                return "The books table could not be queried."
            }
        }
    }
}
