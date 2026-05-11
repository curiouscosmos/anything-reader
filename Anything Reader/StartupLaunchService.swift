//
//  StartupLaunchService.swift
//  Anything Reader
//
//  Registers the app to launch at login once on first install.
//

import Foundation
import ServiceManagement

// Registers the app to launch at login only once so first-install setup is automatic.
@MainActor
final class StartupLaunchService {
    // Shared singleton because launch-at-login registration is a one-time app concern.
    static let shared = StartupLaunchService()

    private let didAttemptRegistrationKey = "didAttemptStartupLaunchRegistration"

    private init() {}

    // Attempts registration only on first run so repeated launches do not keep asking ServiceManagement.
    func registerAtLoginOnFirstInstallIfNeeded() {
        let userDefaults = UserDefaults.standard
        guard !userDefaults.bool(forKey: didAttemptRegistrationKey) else { return }

        defer {
            userDefaults.set(true, forKey: didAttemptRegistrationKey)
        }

        guard #available(macOS 13.0, *) else {
            NSLog("Startup launch registration skipped: requires macOS 13 or later.")
            return
        }

        let service = SMAppService.mainApp
        if service.status == .enabled {
            return
        }

        do {
            try service.register()
        } catch {
            NSLog("Startup launch registration failed: %@", error.localizedDescription)
        }
    }
}
