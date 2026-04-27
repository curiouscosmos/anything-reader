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
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
