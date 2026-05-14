//
//  FreeBooksSQLiteHelpers.swift
//  Anything Reader
//
//  Pure SQLite helpers for the free books catalog queries.
//

import Foundation
import SQLite3

enum FreeBooksSQLiteHelpers {
    nonisolated private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    nonisolated static func bindText(_ value: String, to statement: OpaquePointer, index: Int32) {
        value.utf8CString.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            sqlite3_bind_text(statement, index, baseAddress, -1, sqliteTransient)
        }
    }

    nonisolated static func filteredBooksQuery(
        baseSQL: String,
        languageFilter: FreeBookLanguageFilter,
        categoryFilter: FreeBookCategoryFilter,
        searchText: String,
        includePagination: Bool
    ) -> (sql: String, bindValues: [String]) {
        var clauses: [String] = []
        var bindValues: [String] = []

        if !languageFilter.isAll {
            let languageClause = likeClause(
                aliases: languageFilter.queryAliases,
                columns: ["languages"]
            )
            if let clause = languageClause.clause {
                clauses.append(clause)
                bindValues.append(contentsOf: languageClause.bindValues)
            }
        }

        if !categoryFilter.isAll {
            let categoryClause = likeClause(
                aliases: categoryFilter.aliases,
                columns: ["bookshelves", "subjects"]
            )
            if let clause = categoryClause.clause {
                clauses.append(clause)
                bindValues.append(contentsOf: categoryClause.bindValues)
            }
        }

        let searchClause = searchQueryClause(searchText: searchText)
        if let clause = searchClause.clause {
            clauses.append(clause)
            bindValues.append(contentsOf: searchClause.bindValues)
        }

        let whereClause: String
        if clauses.isEmpty {
            whereClause = ""
        } else {
            whereClause = "WHERE " + clauses.joined(separator: " AND ")
        }

        if includePagination {
            return (
                sql: """
                \(baseSQL)
                \(whereClause)
                ORDER BY title COLLATE NOCASE ASC
                LIMIT ? OFFSET ?;
                """,
                bindValues: bindValues
            )
        }

        return (
            sql: """
            \(baseSQL)
            \(whereClause);
            """,
            bindValues: bindValues
        )
    }

    nonisolated private static func searchQueryClause(searchText: String) -> (clause: String?, bindValues: [String]) {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return (nil, [])
        }

        let tokens = query
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else {
            return (nil, [])
        }

        let columns = ["title", "authors", "subjects", "bookshelves", "languages"]
        var tokenClauses: [String] = []
        var bindValues: [String] = []
        tokenClauses.reserveCapacity(tokens.count)
        bindValues.reserveCapacity(tokens.count * columns.count)

        for token in tokens {
            let perTokenClauses = columns.map { "LOWER(COALESCE(\($0), '')) LIKE ?" }
            tokenClauses.append("(\(perTokenClauses.joined(separator: " OR ")))")
            for _ in columns {
                bindValues.append("%\(token)%")
            }
        }

        return ("(\(tokenClauses.joined(separator: " AND ")))", bindValues)
    }

    nonisolated private static func likeClause(aliases: [String], columns: [String]) -> (clause: String?, bindValues: [String]) {
        let terms = aliases
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        guard !terms.isEmpty else {
            return (nil, [])
        }

        var predicateParts: [String] = []
        var bindValues: [String] = []
        predicateParts.reserveCapacity(terms.count * columns.count)
        bindValues.reserveCapacity(terms.count * columns.count)

        for term in terms {
            for column in columns {
                predicateParts.append("LOWER(COALESCE(\(column), '')) LIKE ?")
                bindValues.append("%\(term)%")
            }
        }

        return ("(\(predicateParts.joined(separator: " OR ")))", bindValues)
    }
}
