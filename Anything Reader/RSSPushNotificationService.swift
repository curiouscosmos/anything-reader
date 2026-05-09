//
//  RSSPushNotificationService.swift
//  Anything Reader
//
//  Handles RSS notification permissions and local notification delivery.
//

import AppKit
import Foundation
import UserNotifications

final class RSSPushNotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = RSSPushNotificationService()

    private let notificationSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func notificationAuthorizationStatus() async -> UNAuthorizationStatus {
        await notificationSettings().authorizationStatus
    }

    func canSendNotifications() async -> Bool {
        let status = await notificationAuthorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }

    func requestNotificationAuthorizationIfNeeded() async -> Bool {
        let status = await notificationAuthorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                    if let error {
                        NSLog("RSS notification authorization request failed: %@", error.localizedDescription)
                    }
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    func openNotificationSettings() {
        NSWorkspace.shared.open(notificationSettingsURL)
    }

    func scheduleNewItemNotifications(feedTitle: String, items: [RSSFeedItemRecord]) async {
        guard await canSendNotifications() else { return }

        for item in items {
            let content = UNMutableNotificationContent()
            content.title = feedTitle
            content.subtitle = item.title
            content.body = item.summary.isEmpty
                ? "Open Anything Reader to read the latest RSS item."
                : item.summary
            content.sound = .default
            content.userInfo = [
                "feedTitle": feedTitle,
                "itemTitle": item.title,
                "linkURLString": item.linkURLString
            ]

            let request = UNNotificationRequest(
                identifier: "rss-\(item.id)-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )

            await add(request)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        UserDefaults.standard.set("rssFeeds", forKey: "pendingSidebarSelection")

        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: .navigateToRSSFeeds, object: nil)
            completionHandler()
        }
    }

    private func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    private func add(_ request: UNNotificationRequest) async {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().add(request) { error in
                if let error {
                    NSLog("RSS notification scheduling failed: %@", error.localizedDescription)
                }
                continuation.resume()
            }
        }
    }
}
