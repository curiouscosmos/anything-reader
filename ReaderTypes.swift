//
//  ReaderTypes.swift
//  Anything Reader
//
//  Shared types and style helpers for the reader shell.
//

import SwiftUI

// Sidebar destinations in the main split view.
enum SidebarSelection: Hashable {
    case home
    case recent
    case freeBooks
    case category(String)
}

// User-selected appearance mode.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

// Playback state for the persistent player bar.
struct PlaybackState {
    var title: String = "Nothing playing"
    var subtitle: String = "Select a PDF, ePub, text file, or paste text"
    var readingPositionText: String = ""
    var readingPositionOverrideText: String?
    var readingPositionIndexOverride: Int?
    var readingPositionTotalCount: Int?
    var avatarSymbol: String = "waveform"
    var accentName: String = "emerald"
    var progress: Double = 0
    var durationSeconds: Int = 1800
    var elapsedSeconds: Int = 0
    var isPlaying: Bool = false

    var displayedReadingPositionText: String {
        readingPositionOverrideText ?? readingPositionText
    }

    var displayedProgress: Double {
        if let readingPositionIndexOverride,
           let readingPositionTotalCount,
           readingPositionTotalCount > 0 {
            let boundedIndex = min(max(readingPositionIndexOverride, 0), readingPositionTotalCount - 1)
            return Double(boundedIndex + 1) / Double(readingPositionTotalCount)
        }

        return progress
    }
}

// Theme and formatting helpers used across multiple views.
enum ReaderStyle {
    static func accentColor(named name: String) -> Color {
        switch name {
        case "teal":
            return Color(red: 0.17, green: 0.76, blue: 0.69)
        case "gold":
            return Color(red: 0.97, green: 0.74, blue: 0.28)
        case "violet":
            return Color(red: 0.74, green: 0.49, blue: 0.98)
        case "rose":
            return Color(red: 0.96, green: 0.37, blue: 0.58)
        case "sky":
            return Color(red: 0.27, green: 0.65, blue: 0.97)
        default:
            return Color(red: 0.15, green: 0.76, blue: 0.44)
        }
    }

    static func formattedTime(_ totalSeconds: Int) -> String {
        let clamped = max(0, totalSeconds)
        let minutes = clamped / 60
        let seconds = clamped % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
