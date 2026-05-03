//
//  FreeBooksSQLiteHelpers.swift
//  Anything Reader
//
//  Pure SQLite helpers for the free books catalog queries.
//

import Foundation
import SQLite3

enum FreeBooksSQLiteHelpers {
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    static func bindText(_ value: String, to statement: OpaquePointer, index: Int32) {
        value.utf8CString.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            sqlite3_bind_text(statement, index, baseAddress, -1, sqliteTransient)
        }
    }

    static func filteredBooksQuery(
        baseSQL: String,
        languageFilter: FreeBookLanguageFilter,
        includePagination: Bool
    ) -> (sql: String, bindValues: [String]) {
        let aliases = languageFilter.queryAliases
        guard !aliases.isEmpty else {
            if includePagination {
                return (
                    sql: """
                    \(baseSQL)
                    ORDER BY title COLLATE NOCASE ASC
                    LIMIT ? OFFSET ?;
                    """,
                    bindValues: []
                )
            }

            return (sql: "\(baseSQL);", bindValues: [])
        }

        var predicateParts: [String] = []
        predicateParts.reserveCapacity(aliases.count)
        for _ in aliases {
            predicateParts.append("LOWER(COALESCE(languages, '')) LIKE ?")
        }

        let predicate = predicateParts.joined(separator: " OR ")
        let filterClause = "WHERE (\(predicate))"
        let bindValues = aliases.map { "%\($0.lowercased())%" }

        if includePagination {
            return (
                sql: """
                \(baseSQL)
                \(filterClause)
                ORDER BY title COLLATE NOCASE ASC
                LIMIT ? OFFSET ?;
                """,
                bindValues: bindValues
            )
        }

        return (
            sql: """
            \(baseSQL)
            \(filterClause);
            """,
            bindValues: bindValues
        )
    }
}
