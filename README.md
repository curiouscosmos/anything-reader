# Anything Reader

Anything Reader is a local-first macOS reading app that turns documents and pasted text into a persistent audio library.

It is designed to feel like a media player for reading:
- import PDF, ePub, or text files
- paste text directly into the app
- keep a searchable local library
- play content with Kokoro text-to-speech
- resume from saved progress
- organize items into custom categories

## How It Works

The app follows a simple pipeline:

1. A file or pasted text is imported into the library.
2. `DocumentIngestService` extracts and normalizes text.
3. The normalized text is saved to disk for later replay.
4. `ReaderPlaybackChunkService` splits the text into TTS-friendly chunks.
5. `PhonemeCacheService` caches phonemes per chunk so replays are faster.
6. `ReaderPlaybackService` synthesizes and queues audio chunk by chunk.
7. `KokoroSpeechService` generates local speech through Kokoro.
8. The player persists progress so playback can resume where it stopped.

The UI shell is built with SwiftUI and keeps playback controls, settings, and library browsing in one place.

## Project Structure

### Root Files
- `AGENTS.md` - instructions for agents
- `AI.md` - project map and component guide
- `README.md` - this overview
- `Anything Reader.xcodeproj` - Xcode project
- `Assets/voices-v1.0.bin` - bundled Kokoro voice archive

### App Sources
- `Anything Reader/Anything_ReaderApp.swift` - app entry point and SwiftData container
- `Anything Reader/ContentView.swift` - main orchestration view for the app shell
- `Anything Reader/Item.swift` - SwiftData models for library entries and categories
- `Anything Reader/DocumentIngestService.swift` - PDF, ePub, and text ingestion
- `Anything Reader/CoverArtService.swift` - background cover extraction
- `Anything Reader/KokoroModelStore.swift` - Kokoro model install and selection state
- `Anything Reader/KokoroSpeechService.swift` - Kokoro runtime bridge and sample playback
- `Anything Reader/PhonemeCacheService.swift` - phoneme cache storage
- `Anything Reader/ReaderPlaybackChunkService.swift` - chunking and resume helpers
- `Anything Reader/ReaderPlaybackService.swift` - queued playback engine
- `Anything Reader/ReaderVolumeControlView.swift` - standalone player volume control
- `Anything Reader/TextNormalizationService.swift` - raw text cleanup

### Shared UI
- `ReaderTypes.swift` - shared enums, playback state, and style helpers
- `ReaderComponents.swift` - reusable SwiftUI building blocks
- `ReaderSheets.swift` - modal sheets and settings UI
- `KokoroG2PService.swift` - phoneme conversion helper

### Tests
- `Anything ReaderTests/Anything_ReaderTests.swift`
- `Anything ReaderUITests/Anything_ReaderUITests.swift`
- `Anything ReaderUITests/Anything_ReaderUITestsLaunchTests.swift`

## Models and Packages Used

### Runtime and Speech
- `KokoroSwift`
- `MLX`
- `ZIPFoundation`

### Apple Frameworks
- `SwiftUI`
- `SwiftData`
- `AVFoundation`
- `AppKit`
- `PDFKit`
- `Foundation`
- `UniformTypeIdentifiers`

### Model and Voice Assets
- `voices-v1.0.bin` is the bundled Kokoro voice archive.
- Kokoro model files are downloaded locally into Application Support when needed.
- The app keeps the selected model and selected voice separate.

## How to Set Up for Development

1. Open `Anything Reader.xcodeproj` in Xcode.
2. Let Swift Package Manager resolve the dependencies.
3. Build the app once so Xcode finishes indexing and package setup.
4. Run the app from Xcode or a debug build.
5. If Kokoro is not installed yet, use the in-app model download flow.

### Helpful Development Notes
- The app stores imported and normalized files in Application Support.
- Playback state and progress are persisted in SwiftData.
- Voice samples and file playback share the same local Kokoro runtime.
- The codebase is split into focused files to keep the app maintainable.

## Data Storage

- SwiftData uses a versioned persistent store at `~/Library/Application Support/Anything Reader/AnythingReader-v2.sqlite`.
- If the persistent store cannot be created, the app falls back to an in-memory SwiftData container so the app can still launch.
- Imported source files are staged under `~/Library/Application Support/Anything Reader/Uploaded Files/`.
- Normalized TXT files are saved alongside the staged content in that uploaded-files directory.
- `LibraryEntry` stores the derived reading metadata needed by the UI:
  - `pageCount`
  - `chapterCount`
  - `readingStructureKind`
  - `readingJumpTargets`

## Supported Languages

Text normalization and chunking are language-aware for:
- English
- French
- Spanish
- German
- Mandarin
- Italian
- Japanese
- Hindi (Pending Kokoro Support)
- Punjabi (Pending Kokoro Support)

Notes:
- Latin-script languages keep the existing normalization behavior.
- Mandarin, Japanese, Hindi, and Punjabi use more conservative normalization to avoid breaking script-specific text.
- Actual speech quality still depends on the selected Kokoro voice/model for the language you want to hear.
- For PDFs, the app first checks whether the extracted text layer looks readable. If it looks like gibberish, the page is rendered to an image and OCR is used instead.

## Minimum Requirements

To run the app locally:
- macOS 15 or later
- Xcode 16 or later
- A Mac with sufficient local storage for imported documents and downloaded Kokoro model files

Recommended:
- A machine with Apple silicon for best Kokoro performance
- At least 8 GB of memory, with more memory preferred for larger models and longer books

## Notes

- The app is intended to work offline after the Kokoro model is installed.
- PDF and ePub handling depends on local file access, so the app should be launched from Xcode with the correct sandbox entitlements during development.
- If you add new major components, keep the structure documented in `AI.md` and update this README when the user-facing flow changes.
