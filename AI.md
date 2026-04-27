# Anything Reader AI Guide

This file is for agents and contributors who need fast context on how the app is organized and how playback works.

## Project Layout

Top-level files:
- `AGENTS.md` - repo-wide agent instructions
- `AI.md` - project map and runtime guide
- `Anything Reader.xcodeproj` - Xcode project
- `ReaderTypes.swift` - shared enums, playback state, and style helpers
- `ReaderComponents.swift` - reusable SwiftUI building blocks
- `ReaderSheets.swift` - modal sheets used by the app
- `KokoroG2PService.swift` - phoneme conversion helper used by the TTS pipeline

App source folder:
- `Anything Reader/Anything_ReaderApp.swift` - app entry point and SwiftData container setup
- `Anything Reader/ContentView.swift` - main orchestration view and app state coordination
- `Anything Reader/Item.swift` - SwiftData models for library entries and categories
- `Anything Reader/DocumentIngestService.swift` - PDF, TXT, and ePub ingestion plus normalization
- `Anything Reader/CoverArtService.swift` - background cover image extraction and file writing
- `Anything Reader/KokoroModelStore.swift` - local TTS model download, activation, and deletion state
- `Anything Reader/KokoroSpeechService.swift` - Kokoro runtime bridge, model loading, and sample playback
- `Anything Reader/PhonemeCacheService.swift` - file-backed phoneme cache for playback chunks
- `Anything Reader/ReaderPlaybackChunkService.swift` - normalized text chunking and playback positioning
- `Anything Reader/ReaderPlaybackService.swift` - queued player engine that plays chunked audio
- `Anything Reader/ReaderVolumeControlView.swift` - standalone player volume control UI
- `Anything Reader/TextNormalizationService.swift` - raw text cleanup before chunking and synthesis

Assets and data:
- `Assets/voices-v1.0.bin` - bundled Kokoro voice archive
- `Anything Reader.entitlements` - sandbox and runtime permissions for the macOS app

Tests:
- `Anything ReaderTests/Anything_ReaderTests.swift` - unit tests
- `Anything ReaderUITests/Anything_ReaderUITests.swift` - UI tests
- `Anything ReaderUITests/Anything_ReaderUITestsLaunchTests.swift` - launch flow UI tests

## How The App Works

### 1. App Launch
- `Anything_ReaderApp.swift` creates the SwiftData `ModelContainer`.
- `ContentView` becomes the root app shell.
- `ContentView` also restores persisted UI settings such as theme and selected Kokoro voice.

### 2. Library Shell
- `ContentView` owns the sidebar, top bar, home view, category views, and player shell.
- `ReaderComponents.swift` provides reusable UI pieces:
  - sidebar
  - top bar
  - hero banner
  - library cards
  - player bar
  - toast and loading overlays
- `ReaderSheets.swift` provides the modals:
  - Settings
  - Kokoro model download modal
  - paste text sheet
  - category creation sheet

### 3. Importing Content
- `DocumentIngestService` reads PDF, TXT, and ePub files.
- It extracts text, normalizes it, and saves a normalized `.txt` file next to the staged content in Application Support.
- `CoverArtService` runs cover extraction in the background for supported documents.
- `ContentView` creates or updates the `LibraryEntry` SwiftData record after ingestion.

### 4. Playback Flow
- The user presses play on a card or on the bottom player.
- `ContentView` chooses the active `LibraryEntry`.
- `ReaderPlaybackChunkService` loads the normalized text and splits it into TTS-friendly chunks.
- `PhonemeCacheService` stores phonemes on disk so future replays can reuse them.
- `ReaderPlaybackService` synthesizes chunk audio and queues it on `AVAudioPlayerNode`.
- `ReaderPlaybackService` also keeps track of:
  - play state
  - buffering state
  - active playback identity
  - progress and elapsed time

### 5. Kokoro TTS Flow
- `KokoroModelStore` manages which Kokoro model is installed and active.
- `ReaderSheets.swift` lets the user pick the active voice and download or delete the model.
- `KokoroSpeechService` loads the active model, loads the selected voice embedding, and generates audio.
- `KokoroG2PService` provides phoneme conversion used by the cache and playback pipeline.

### 6. Progress and Resume
- `LibraryEntry.progress` and `LibraryEntry.lastOpened` are persisted in SwiftData.
- Playback resume uses the saved progress value when the same file is opened again.
- The player bar shows time played and total estimated duration.

## Component Responsibilities

### `ContentView.swift`
- Owns the app state machine.
- Connects library actions, playback actions, imports, settings, and toast messages.
- Decides when the player bar is visible.
- Restarts playback when the selected Kokoro voice changes.

### `Item.swift`
- Defines shared data models.
- `LibraryEntry` stores source metadata, normalized file paths, progress, and cover art paths.
- `ReaderCategory` stores custom folders/categories.

### `ReaderTypes.swift`
- Holds common UI enums and playback state structs.
- Houses shared styling helpers.

### `ReaderComponents.swift`
- Contains reusable SwiftUI views only.
- Keep this file focused on presentation, not business logic.

### `ReaderSheets.swift`
- Contains the modal sheets and settings UI.
- Keep destructive actions and complex sheet behavior here instead of inside `ContentView`.

### `DocumentIngestService.swift`
- Responsible for file parsing and text normalization after import.
- Keep file-type specific extraction logic isolated here.

### `CoverArtService.swift`
- Responsible for background art generation and cover file storage.
- Keep image extraction and save logic here.

### `ReaderPlaybackChunkService.swift`
- Converts normalized text into chunks suitable for synthesis and resume.
- Keeps the chunking rules centralized.

### `ReaderPlaybackService.swift`
- Owns the queued audio engine.
- Manages synthesis tasks, prefetching, buffering state, and playback progress.
- This is the place for playback bugs, timing issues, and audio queue fixes.

### `ReaderVolumeControlView.swift`
- Independent player volume control component.
- Kept separate so transport controls stay focused and maintainable.

### `PhonemeCacheService.swift`
- Caches phonemes by entry and chunk index.
- Keeps replay fast by avoiding repeated phoneme generation.

### `KokoroModelStore.swift`
- Manages downloadable TTS model availability and active selection.
- Handles install, delete, activate, and validation state.

### `KokoroSpeechService.swift`
- Bridges the app to Kokoro runtime audio generation.
- Loads model and voice assets, then produces temporary WAV files for playback.

### `KokoroG2PService.swift`
- Handles phoneme conversion used by the TTS pipeline.
- Keep G2P-specific logic out of views and playback control.

## Working Rules For Future Agents

- Keep code clean and easy to scan.
- Split components into separate files when it improves readability or reuse.
- Add comments for non-obvious logic or important flows.
- Handle errors explicitly and provide safe fallbacks.
- Prefer secure defaults and avoid assumptions about file availability or runtime state.
- Keep changes scoped to the requested task.

## Quick Debug Map

- UI and orchestration issue: `ContentView.swift`
- Menu / card layout issue: `ReaderComponents.swift`
- Sheet and settings issue: `ReaderSheets.swift`
- Import / normalization issue: `DocumentIngestService.swift`
- Cover art issue: `CoverArtService.swift`
- Playback timing / gap / resume issue: `ReaderPlaybackService.swift`
- Phoneme cache issue: `PhonemeCacheService.swift`
- Kokoro voice/model issue: `KokoroSpeechService.swift` and `KokoroModelStore.swift`
