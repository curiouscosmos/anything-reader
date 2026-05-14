<wizard-report>
# PostHog post-wizard report

The wizard has completed a deep integration of PostHog analytics into **Anything Reader**, a macOS SwiftUI text-to-speech app. Here is a summary of all changes made:

- **`Anything Reader.xcodeproj/project.pbxproj`** — Added the local `posthog-ios` Swift package (already present in `Packages/posthog-ios`) as a linked framework: `XCLocalSwiftPackageReference`, `XCSwiftPackageProductDependency`, and `PBXBuildFile` entries wired into the main target's Frameworks build phase and `packageProductDependencies`.
- **`Anything Reader.xcodeproj/xcshareddata/xcschemes/Anything Reader.xcscheme`** — Created a shared Xcode scheme with `POSTHOG_PROJECT_TOKEN` and `POSTHOG_HOST` environment variable slots in the Run action. Fill in `POSTHOG_PROJECT_TOKEN` with your actual token in Xcode (Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables).
- **`Anything Reader/Anything_ReaderApp.swift`** — Added `import PostHog`, a `PostHogEnv` enum that reads keys safely from `ProcessInfo`, and PostHog SDK initialization (with `captureApplicationLifecycleEvents = true`) in the app's `init()`.
- **`Anything Reader/ContentView.swift`** — Added `import PostHog` and 10 `PostHogSDK.shared.capture()` calls across the key user-action paths.

## Events instrumented

| Event | Description | File |
|-------|-------------|------|
| `document_imported` | User successfully imports a PDF, ePub, TXT, or image via file picker or drag-and-drop | `ContentView.swift` |
| `paste_text_imported` | User pastes text directly and submits it for playback | `ContentView.swift` |
| `browser_extension_imported` | A web page is sent from the browser extension | `ContentView.swift` |
| `free_book_downloaded` | User downloads a book from the Project Gutenberg free catalog | `ContentView.swift` |
| `rss_article_imported` | An RSS article is scraped and queued for read-aloud | `ContentView.swift` |
| `document_played` | TTS narration playback starts on a library entry | `ContentView.swift` |
| `generated_audio_played` | A pre-exported AAC audio file starts playing | `ContentView.swift` |
| `document_summarized` | Apple Intelligence summarization completes successfully | `ContentView.swift` |
| `audio_file_generated` | A full-document AAC audio export completes successfully | `ContentView.swift` |
| `tts_model_downloaded` | A TTS model (Kokoro, Moonshine, or Supertonic) finishes downloading | `ContentView.swift` |

## Next steps

We've built some insights and a dashboard for you to keep an eye on user behavior, based on the events we just instrumented:

- [Analytics basics dashboard](/dashboard/1582846)
- [Documents Imported Over Time](/insights/HkYWw3LV) — all import sources by day
- [Playback Starts Over Time](/insights/i2we61cz) — TTS narration vs generated audio
- [Import to Playback Conversion Funnel](/insights/yWvViX8l) — what fraction of importers go on to play
- [AI Feature Usage](/insights/3Y5DKWL4) — summaries and audio exports per day
- [TTS Model Download Rate](/insights/cQytHua2) — onboarding completion, broken down by provider

### One manual step required

Open the shared scheme in Xcode (Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables) and set `POSTHOG_PROJECT_TOKEN` to your PostHog project token. The host (`https://us.i.posthog.com`) is already filled in.

### Agent skill

We've left an agent skill folder in your project at `.claude/skills/integration-swift/`. You can use this context for further agent development when using Claude Code. This will help ensure the model provides the most up-to-date approaches for integrating PostHog.

</wizard-report>
