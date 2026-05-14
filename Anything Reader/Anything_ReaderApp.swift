//
//  Anything_ReaderApp.swift
//  Anything Reader
//
//  Created by Daman Mehta on 2026-04-24.
//

import SwiftUI
import SwiftData

// Application entry point that wires the persistent store, startup services, and root content view.
@main
struct Anything_ReaderApp: App {
    // Shared model container backed by the app's on-disk SwiftData store.
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            LibraryEntry.self,
            ReaderCategory.self,
            AudioMixerTrackRecord.self,
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

    // Performs one-time startup wiring before the first window appears.
    init() {
        StartupLaunchService.shared.registerAtLoginOnFirstInstallIfNeeded()
        _ = RSSPushNotificationService.shared
    }

    // Root scene for the whole app.
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }

    // Returns the persistent SwiftData configuration, falling back to in-memory storage if needed.
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
        let storeURL = appDirectory.appendingPathComponent("AnythingReader-v7.sqlite")
        return ModelConfiguration(schema: schema, url: storeURL, allowsSave: true)
    }
}
