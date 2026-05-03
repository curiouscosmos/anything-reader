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
        categoryFilter: FreeBookCategoryFilter,
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

    private static func likeClause(aliases: [String], columns: [String]) -> (clause: String?, bindValues: [String]) {
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
