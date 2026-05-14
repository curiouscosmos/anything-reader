//
//  Anything_ReaderApp.swift
//  Anything Reader
//
//  Created by Daman Mehta on 2026-04-24.
//

import SwiftUI
import SwiftData
import PostHog

// Reads PostHog configuration from Xcode scheme environment variables at launch.
enum PostHogEnv: String {
    case projectToken = "POSTHOG_PROJECT_TOKEN"
    case host = "POSTHOG_HOST"

    var value: String {
        guard let value = ProcessInfo.processInfo.environment[rawValue] else {
            fatalError("Set \(rawValue) in the Xcode scheme Run environment variables.")
        }
        return value
    }
}

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
        // PostHog: Initialize analytics SDK
        let config = PostHogConfig(apiKey: PostHogEnv.projectToken.value, host: PostHogEnv.host.value)
        config.captureApplicationLifecycleEvents = true
        PostHogSDK.shared.setup(config)

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
