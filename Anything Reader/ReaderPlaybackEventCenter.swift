//
//  ReaderPlaybackEventCenter.swift
//  Anything Reader
//
//  Shared playback events for the narration player, generated-audio player,
//  and background music mixer. This lets the mixer react to explicit lifecycle
//  events instead of inferring state from UI callbacks.
//

import Foundation

enum ReaderPlaybackSource: String {
    case reader
    case generatedAudio
    case importFlow
}

enum ReaderPlaybackEventKind: String {
    case willTransition
    case didStart
    case didPause
    case didStop
    case didFinish
}

struct ReaderPlaybackEvent: Sendable {
    let kind: ReaderPlaybackEventKind
    let source: ReaderPlaybackSource
}

extension Notification.Name {
    static let readerPlaybackEvent = Notification.Name("ReaderPlaybackEvent")
}

enum ReaderPlaybackEventCenter {
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
