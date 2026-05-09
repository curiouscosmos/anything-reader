//
//  StartupLaunchService.swift
//  Anything Reader
//
//  Registers the app to launch at login once on first install.
//

import Foundation
import ServiceManagement

@MainActor
final class StartupLaunchService {
    static let shared = StartupLaunchService()

    private let didAttemptRegistrationKey = "didAttemptStartupLaunchRegistration"

    private init() {}

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
