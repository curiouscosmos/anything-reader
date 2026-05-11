//
//  AppUpdateChecker.swift
//  Anything Reader
//
//  Checks the remote version payload and surfaces update availability in the UI.
//

import AppKit
import Combine
import Foundation

struct AppUpdateNotice: Equatable {
    // These values are compared against the local bundle version to decide whether to show a banner.
    let currentVersion: String
    let minimumSupportedVersion: String
    let unstableVersions: [String]
    let forceUpdate: Bool
    let appStoreURL: URL

    var shouldShowBanner: Bool {
        isCurrentVersionLowerThanMinimum || isCurrentVersionUnstable
    }

    var isForceUpdateRequired: Bool {
        forceUpdate || isCurrentVersionLowerThanMinimum
    }

    var subtitle: String {
        "A new version of the app is available on app store. Please download to continue using the app."
    }

    var title: String {
        "Update Anything Reader"
    }

    private var isCurrentVersionLowerThanMinimum: Bool {
        SemanticVersion.isLower(currentVersion, than: minimumSupportedVersion)
    }

    private var isCurrentVersionUnstable: Bool {
        unstableVersions.contains(currentVersion.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

@MainActor
final class AppUpdateChecker: ObservableObject {
    // App-wide singleton because update state is shared by the shell and multiple views.
    static let shared = AppUpdateChecker()

    @Published private(set) var notice: AppUpdateNotice?
    @Published private(set) var isChecking = false

    private let remoteConfigurationURL = URL(string: "https://sandalbar.s3.us-west-2.amazonaws.com/assets/version_check.json")!
    private let pollingIntervalNanoseconds: UInt64 = 86_400_000_000_000
    private var monitoringTask: Task<Void, Never>?

    private init() {}

    // Launches the background polling loop once per app session.
    func startMonitoring() {
        guard monitoringTask == nil else { return }

        monitoringTask = Task { [weak self] in
            guard let self else { return }

            await self.checkNow()

            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: pollingIntervalNanoseconds)
                } catch {
                    break
                }

                guard !Task.isCancelled else { break }
                await self.checkNow()
            }
        }
    }

    // Opens the App Store listing associated with the current build.
    func openAppStore() {
        guard let url = notice?.appStoreURL else { return }
        NSWorkspace.shared.open(url)
    }

    // Fetches the remote version JSON and computes the current update state.
    func checkNow() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        do {
            let (data, response) = try await URLSession.shared.data(from: remoteConfigurationURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return
            }

            let payload = try JSONDecoder().decode(RemoteVersionPayload.self, from: data)
            let currentVersion = Self.currentAppVersion
            let minimumSupportedVersion = payload.mac.minSupportedVersion.trimmingCharacters(in: .whitespacesAndNewlines)
            let unstableVersions = payload.mac.unstableVersions.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

            let computedNotice = AppUpdateNotice(
                currentVersion: currentVersion,
                minimumSupportedVersion: minimumSupportedVersion,
                unstableVersions: unstableVersions,
                forceUpdate: payload.mac.forceUpdate,
                appStoreURL: Self.appStoreURL
            )

            notice = computedNotice.shouldShowBanner ? computedNotice : nil
        } catch {
            // Keep the last known update state if the network check fails.
        }
    }

    // Compares semantic versions so we can do a stable minimum-version check.
    private static var currentAppVersion: String {
        let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return bundleVersion?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? bundleVersion!.trimmingCharacters(in: .whitespacesAndNewlines)
            : "0.0.0"
    }

    private static var appStoreURL: URL {
        if let configuredURLString = Bundle.main.object(forInfoDictionaryKey: "AppStoreURL") as? String,
           let configuredURL = URL(string: configuredURLString) {
            return configuredURL
        }

        return URL(string: "https://apps.apple.com/ca/app/anything-reader-offline-text-to-speach/id1628040777")!
    }
}

// Decoded configuration payload returned by the remote version-check endpoint.
private struct RemoteVersionPayload: Decodable {
    struct PlatformPayload: Decodable {
        let minSupportedVersion: String
        let unstableVersions: [String]
        let forceUpdate: Bool
    }

    let mac: PlatformPayload
    let windows: PlatformPayload
}

// Lightweight semantic version helper that avoids depending on a full versioning library.
private struct SemanticVersion: Comparable {
    private let components: [Int]

    init?(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parsedComponents = trimmed.split(separator: ".").compactMap { segment -> Int? in
            let numericPrefix = segment.prefix { $0.isNumber }
            return Int(numericPrefix)
        }

        guard !parsedComponents.isEmpty else { return nil }
        components = parsedComponents
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }

    static func isLower(_ current: String, than minimum: String) -> Bool {
        guard let currentVersion = SemanticVersion(current),
              let minimumVersion = SemanticVersion(minimum) else {
            return false
        }

        return currentVersion < minimumVersion
    }
}
