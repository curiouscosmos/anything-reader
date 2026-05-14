<wizard-report>
# PostHog post-wizard report

The wizard has completed a deep integration of PostHog analytics into **Anything Reader**, a macOS SwiftUI document reader with TTS narration, a free books catalog, RSS feeds, audio mixer, and AI summarization.

## What was done

- **SDK added**: `posthog-ios` (v3.58.1) added to the Xcode project via Swift Package Manager (`project.pbxproj`).
- **Xcscheme created**: `Anything Reader.xcodeproj/xcshareddata/xcschemes/Anything Reader.xcscheme` — includes `POSTHOG_PROJECT_TOKEN` and `POSTHOG_HOST` environment variable slots for the Run action. Fill in the token value in Xcode under **Product > Scheme > Edit Scheme > Run > Arguments > Environment Variables**.
- **PostHog initialized**: `PostHogEnv` helper enum and SDK setup added to `Anything_ReaderApp.swift` with `captureApplicationLifecycleEvents = true`.
- **11 events instrumented** across 5 files.

## Events

| Event | Description | File |
|---|---|---|
| `document_imported` | User successfully imported a document (PDF, ePub, image, or text) | `Anything Reader/ContentView.swift` |
| `document_import_failed` | A document import failed during ingest or normalization | `Anything Reader/ContentView.swift` |
| `playback_started` | User started TTS narration for a library entry | `Anything Reader/ReaderPlaybackService.swift` |
| `playback_completed` | TTS narration finished naturally (reached end of document) | `Anything Reader/ReaderPlaybackService.swift` |
| `playback_stopped` | User manually stopped TTS narration before completion | `Anything Reader/ReaderPlaybackService.swift` |
| `playback_failed` | TTS narration failed with an error | `Anything Reader/ReaderPlaybackService.swift` |
| `free_book_downloaded` | User downloaded a free book from the catalog into their library | `Anything Reader/ContentView.swift` |
| `audio_file_generated` | User generated a full M4A audio file from a library document | `Anything Reader/ContentView.swift` |
| `audio_generation_failed` | Audio file generation failed with an error | `Anything Reader/ContentView.swift` |
| `rss_feed_subscribed` | User added a new RSS feed subscription | `Anything Reader/RSSFeedsView.swift` |
| `audio_mixer_track_imported` | User imported a custom audio track into the Audio Mixer | `Anything Reader/AudioMixerViews.swift` |

## Next steps

We've built a dashboard and five insights to monitor user behavior based on the events just instrumented:

- [Analytics basics dashboard](/dashboard/1582589)
- [Documents Imported (Daily)](/insights/iZjQpg6m) — daily import volume, top of the funnel
- [Playback Funnel: Import → Start → Complete](/insights/AXSD0of6) — core engagement conversion funnel
- [Playback Completion Rate](/insights/VCOWaY50) — ratio of completions to starts (weekly)
- [Document Import Failures](/insights/cTTJN5Zi) — error spike detection / churn signal
- [Feature Adoption](/insights/ZO4TFBrd) — weekly usage of free books, audio export, RSS, and audio mixer

### Finish setup in Xcode

In Xcode, open **Product > Scheme > Edit Scheme > Run > Arguments > Environment Variables** and set `POSTHOG_PROJECT_TOKEN` to your PostHog project token. The `POSTHOG_HOST` is already set to `https://us.i.posthog.com`.

### Agent skill

We've left an agent skill folder in your project at `.claude/skills/integration-swift/`. You can use this context for further agent development when using Claude Code. This will help ensure the model provides the most up-to-date approaches for integrating PostHog.

</wizard-report>
