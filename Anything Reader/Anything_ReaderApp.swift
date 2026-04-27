//
//  Anything_ReaderApp.swift
//  Anything Reader
//
//  Created by Daman Mehta on 2026-04-24.
//

import SwiftUI
import SwiftData

@main
struct Anything_ReaderApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            LibraryEntry.self,
            ReaderCategory.self,
        ])

        do {
            let modelConfiguration = try Self.persistentModelConfiguration(for: schema)
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Keep the app launchable even if the on-disk store is incompatible.
            let fallbackConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [fallbackConfiguration])
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }

    private static func persistentModelConfiguration(for schema: Schema) throws -> ModelConfiguration {
        let fileManager = FileManager.default
        let applicationSupportDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let appDirectory = applicationSupportDirectory.appendingPathComponent("Anything Reader", isDirectory: true)
        if !fileManager.fileExists(atPath: appDirectory.path) {
            try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        }

        // Version the store URL so schema changes do not crash launch against an older SQLite file.
        let storeURL = appDirectory.appendingPathComponent("AnythingReader-v2.sqlite")
        return ModelConfiguration(schema: schema, url: storeURL, allowsSave: true)
    }
}
