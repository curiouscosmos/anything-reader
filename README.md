# Anything Reader

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

## Notes For Agents

- Consult `AI.md` first for the app map and runtime flow.
- Keep storage and metadata changes aligned with `Anything_ReaderApp.swift`, `DocumentIngestService.swift`, and `Item.swift`.
