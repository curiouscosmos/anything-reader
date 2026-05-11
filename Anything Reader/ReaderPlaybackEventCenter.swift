//
//  ReaderPlaybackEventCenter.swift
//  Anything Reader
//
//  Shared playback events for the narration player, generated-audio player,
//  and background music mixer. This lets the mixer react to explicit lifecycle
//  events instead of inferring state from UI callbacks.
//

import Foundation

// Enumerates the sources that can emit playback lifecycle events.
enum ReaderPlaybackSource: String {
    case reader
    case generatedAudio
    case importFlow
}

// Captures the lifecycle transition that happened for a playback source.
enum ReaderPlaybackEventKind: String {
    case willTransition
    case didStart
    case didPause
    case didStop
    case didFinish
}

// Lightweight value type posted through NotificationCenter for playback changes.
struct ReaderPlaybackEvent: Sendable {
    let kind: ReaderPlaybackEventKind
    let source: ReaderPlaybackSource
}

// Notification names used by the reader shell and RSS navigation bridge.
extension Notification.Name {
    static let readerPlaybackEvent = Notification.Name("ReaderPlaybackEvent")
    static let navigateToRSSFeeds = Notification.Name("NavigateToRSSFeeds")
}

// Small helper that serializes playback events into NotificationCenter payloads.
enum ReaderPlaybackEventCenter {
    // Posts a lifecycle event using a stable userInfo payload format.
    static func post(_ event: ReaderPlaybackEvent) {
        NotificationCenter.default.post(
            name: .readerPlaybackEvent,
            object: nil,
            userInfo: [
                "kind": event.kind.rawValue,
                "source": event.source.rawValue
            ]
        )
    }

    // Decodes the notification payload back into a strongly typed event.
    static func decode(_ notification: Notification) -> ReaderPlaybackEvent? {
        guard let kindRaw = notification.userInfo?["kind"] as? String,
              let sourceRaw = notification.userInfo?["source"] as? String,
              let kind = ReaderPlaybackEventKind(rawValue: kindRaw),
              let source = ReaderPlaybackSource(rawValue: sourceRaw) else {
            return nil
        }

        return ReaderPlaybackEvent(kind: kind, source: source)
    }
}
