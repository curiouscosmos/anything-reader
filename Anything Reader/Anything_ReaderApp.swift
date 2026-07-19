//
//  Anything_ReaderApp.swift
//  Anything Reader
//
//  Created by Daman Mehta on 2026-04-24.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif
import SwiftData
import PostHog
import Sentry

// PostHog configuration is read from the Xcode scheme first, then from the bundled .env file.
enum PostHogEnv: String {
    case projectToken = "POSTHOG_PROJECT_TOKEN"
    case host = "POSTHOG_HOST"

    var value: String? {
        if let value = ProcessInfo.processInfo.environment[rawValue], !value.isEmpty {
            return value
        }
        return Self.bundleValue(for: rawValue)
    }

    private static func bundleValue(for key: String) -> String? {
        guard let url = Bundle.main.url(forResource: ".env", withExtension: nil),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        for line in contents.split(whereSeparator: \.isNewline) {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty, !trimmedLine.hasPrefix("#") else {
                continue
            }

            let candidateLine = trimmedLine.hasPrefix("export ") ? String(trimmedLine.dropFirst(7)) : trimmedLine
            guard let equalsIndex = candidateLine.firstIndex(of: "=") else {
                continue
            }

            let entryKey = candidateLine[..<equalsIndex].trimmingCharacters(in: .whitespaces)
            guard entryKey == key else {
                continue
            }

            let entryValue = String(candidateLine[candidateLine.index(after: equalsIndex)...]
                .trimmingCharacters(in: .whitespaces))
            return unquote(entryValue)
        }

        return nil
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2,
              let first = value.first,
              let last = value.last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'") else {
            return value
        }

        return String(value.dropFirst().dropLast())
    }
}

// Sentry uses the same scheme-first, bundled-.env fallback as the analytics configuration.
enum SentryEnv: String {
    case dsn = "SENTRY_DSN"
    case environment = "SENTRY_ENVIRONMENT"
    case release = "SENTRY_RELEASE"

    var value: String? {
        if let value = ProcessInfo.processInfo.environment[rawValue], !value.isEmpty {
            return value
        }
        return bundleValue(for: rawValue)
    }

    private func bundleValue(for key: String) -> String? {
        guard let url = Bundle.main.url(forResource: ".env", withExtension: nil),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        for line in contents.split(whereSeparator: \.isNewline) {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty, !trimmedLine.hasPrefix("#") else {
                continue
            }

            let candidateLine = trimmedLine.hasPrefix("export ") ? String(trimmedLine.dropFirst(7)) : trimmedLine
            guard let equalsIndex = candidateLine.firstIndex(of: "=") else {
                continue
            }

            let entryKey = candidateLine[..<equalsIndex].trimmingCharacters(in: .whitespaces)
            guard entryKey == key else {
                continue
            }

            let entryValue = String(candidateLine[candidateLine.index(after: equalsIndex)...]
                .trimmingCharacters(in: .whitespaces))
            return unquote(entryValue)
        }

        return nil
    }

    private func unquote(_ value: String) -> String {
        guard value.count >= 2,
              let first = value.first,
              let last = value.last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'") else {
            return value
        }

        return String(value.dropFirst().dropLast())
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
#if os(macOS)
        // Force dark Aqua so AppKit-backed windows, sheets, and dialogs stay dark
        // even if the user switches the system appearance to light.
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
#endif

        if let sentryDSN = SentryEnv.dsn.value {
            SentrySDK.start { options in
                options.dsn = sentryDSN
                if let environment = SentryEnv.environment.value {
                    options.environment = environment
                }
                options.releaseName = SentryEnv.release.value
                    ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                options.enableCrashHandler = true
                options.tracesSampleRate = 1.0
                options.configureProfiling = {
                    $0.sessionSampleRate = 1.0
                    $0.lifecycle = .trace
                }
            }
        } else {
            print("Sentry is disabled because SENTRY_DSN is not set.")
        }

        // PostHog: Initialize analytics SDK
        if let projectToken = PostHogEnv.projectToken.value,
           let host = PostHogEnv.host.value {
            let config = PostHogConfig(projectToken: projectToken, host: host)
            config.captureApplicationLifecycleEvents = true
            PostHogSDK.shared.setup(config)
        } else {
            print("PostHog is disabled because POSTHOG_PROJECT_TOKEN or POSTHOG_HOST is not set.")
        }

        StartupLaunchService.shared.registerAtLoginOnFirstInstallIfNeeded()
        _ = RSSPushNotificationService.shared
    }

    // Root scene for the whole app.
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
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
