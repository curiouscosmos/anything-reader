//
//  NormalizedTextViewerView.swift
//  Anything Reader
//
//  In-app viewer for normalized TXT files using STTextView.
//

import AppKit
import STTextView
import SwiftUI

struct NormalizedTextViewerScreen: View {
    let entry: LibraryEntry
    let preferredMode: AppearanceMode
    let onRevealLocation: (LibraryEntry) -> Void

    @State private var normalizedText = ""
    @State private var viewerText = ""
    @State private var viewerFocusRange: NSRange?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            content
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(viewerBackground.ignoresSafeArea())
        .navigationTitle(entry.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    onRevealLocation(entry)
                } label: {
                    Label("Reveal Location", systemImage: "folder")
                }
            }
        }
        .task(id: normalizedTextFileURL?.path) {
            await loadNormalizedText()
        }
    }

    private var normalizedTextFileURL: URL? {
        guard let path = entry.normalizedTextFilePath else { return nil }
        return URL(fileURLWithPath: path)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            loadingState
        } else if let errorMessage {
            errorState(message: errorMessage)
        } else {
            NormalizedTextDocumentView(text: viewerText, focusRange: viewerFocusRange)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(documentBackground)
                .padding(18)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 1)
                )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(.title2.weight(.bold))

                    Text(entry.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                Text(Self.byteCountFormatter.string(fromByteCount: entry.fileSizeBytes))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(chipBackground, in: Capsule())
            }

            HStack(spacing: 8) {
                Label(entry.sourceKind.displayName, systemImage: entry.sourceKind.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(chipBackground, in: Capsule())

                if let structureSummary = structureSummaryText {
                    Text(structureSummary)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(chipBackground, in: Capsule())
                }

                if let currentReadingPosition = currentReadingPositionText {
                    Text(currentReadingPosition)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(chipBackground, in: Capsule())
                }

                if let normalizedTextFileURL {
                    Text(normalizedTextFileURL.lastPathComponent)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(panelBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
    }

    private var loadingState: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Loading normalized text…")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, minHeight: 320, alignment: .center)
        .background(panelBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
    }

    private func errorState(message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Text unavailable")
                .font(.headline)

            Text(message)
                .foregroundStyle(.secondary)

            Button("Reveal File Location") {
                onRevealLocation(entry)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 320, alignment: .leading)
        .padding(20)
        .background(panelBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
    }

    private var viewerBackground: LinearGradient {
        switch preferredMode {
        case .light:
            return LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.98, blue: 0.97),
                    Color(red: 0.94, green: 0.95, blue: 0.93)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .dark, .system:
            return LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.08, blue: 0.07),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var panelBackground: Color {
        preferredMode == .light ? Color.white.opacity(0.84) : Color.white.opacity(0.08)
    }

    private var documentBackground: Color {
        preferredMode == .light ? Color.white : Color.black.opacity(0.22)
    }

    private var chipBackground: Color {
        preferredMode == .light ? Color.black.opacity(0.05) : Color.white.opacity(0.08)
    }

    private var borderColor: Color {
        preferredMode == .light ? Color.black.opacity(0.10) : Color.white.opacity(0.10)
    }

    private var structureSummaryText: String? {
        switch entry.readingStructureKind {
        case .page:
            guard entry.pageCount > 0 else { return nil }
            return "\(entry.pageCount) pages"
        case .chapter:
            guard entry.chapterCount > 0 else { return nil }
            return "\(entry.chapterCount) chapters"
        case .none:
            return nil
        }
    }

    private var currentReadingPositionText: String? {
        guard let structureKind = entry.readingStructureKind else { return nil }

        let targets = entry.readingJumpTargets
        guard !targets.isEmpty else { return nil }

        let index = ReaderPlaybackChunkService.chunkIndex(for: entry.progress, chunkCount: targets.count)
        let target = targets[min(index, targets.count - 1)]
        let title = target.title.trimmingCharacters(in: .whitespacesAndNewlines)

        switch structureKind {
        case .page:
            if title.isEmpty {
                return "Page \(index + 1) of \(targets.count)"
            }
            return "Page \(index + 1) of \(targets.count) · \(title)"
        case .chapter:
            if title.isEmpty {
                return "Chapter \(index + 1) of \(targets.count)"
            }
            return "Chapter \(index + 1) of \(targets.count) · \(title)"
        }
    }

    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter
    }()

    private func loadNormalizedText() async {
        isLoading = true
        errorMessage = nil
        normalizedText = ""
        viewerText = ""
        viewerFocusRange = nil
        defer { isLoading = false }

        guard let normalizedTextFileURL else {
            errorMessage = "This item does not have a normalized TXT file."
            return
        }

        guard FileManager.default.fileExists(atPath: normalizedTextFileURL.path) else {
            errorMessage = "The normalized TXT file could not be found on disk."
            return
        }

        do {
            let loadedText = try await Task.detached(priority: .utility) {
                let data = try Data(contentsOf: normalizedTextFileURL, options: .mappedIfSafe)
                guard !data.isEmpty else { return "" }
                guard let text = String(data: data, encoding: .utf8) else {
                    throw ViewerError.unreadableText
                }
                return text
            }.value

            normalizedText = loadedText
            let renderResult = Self.viewerText(for: loadedText, entry: entry)
            viewerText = renderResult.text
            viewerFocusRange = renderResult.focusRange
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private enum ViewerError: LocalizedError {
        case unreadableText

        var errorDescription: String? {
            switch self {
            case .unreadableText:
                return "The normalized TXT file could not be decoded as UTF-8 text."
            }
        }
    }

    private static func viewerText(for normalizedText: String, entry: LibraryEntry) -> ViewerRenderResult {
        guard let structureKind = entry.readingStructureKind else {
            return ViewerRenderResult(text: normalizedText, focusRange: nil)
        }

        let targets = entry.readingJumpTargets
        guard !targets.isEmpty else {
            return ViewerRenderResult(text: normalizedText, focusRange: nil)
        }

        switch structureKind {
        case .page:
            return pageText(for: entry, normalizedText: normalizedText, progress: entry.progress)
        case .chapter:
            return chapterText(from: normalizedText, targets: targets, progress: entry.progress)
        }
    }

    private static func pageText(for entry: LibraryEntry, normalizedText: String, progress: Double) -> ViewerRenderResult {
        let chunks = ReaderPlaybackChunkService.pageChunks(for: entry)
        let resolvedChunks = chunks.isEmpty ? ReaderPlaybackChunkService.chunks(from: normalizedText) : chunks
        let chunksToRender = resolvedChunks.isEmpty ? [normalizedText] : resolvedChunks
        guard !chunksToRender.isEmpty else { return ViewerRenderResult(text: normalizedText, focusRange: nil) }
        let total = chunksToRender.count
        let currentIndex = ReaderPlaybackChunkService.chunkIndex(for: progress, chunkCount: total)

        var renderedChunks: [String] = []
        renderedChunks.reserveCapacity(total)
        var focusRange: NSRange?
        var currentLocation = 0

        for (index, chunk) in chunksToRender.enumerated() {
            let segment = ["Page \(index + 1) of \(total)", chunk]
                .joined(separator: "\n\n")

            if index == currentIndex {
                focusRange = NSRange(location: currentLocation, length: 0)
            }

            renderedChunks.append(segment)
            currentLocation += segment.count

            if index < chunksToRender.count - 1 {
                currentLocation += 3
            }
        }

        return ViewerRenderResult(
            text: renderedChunks.joined(separator: "\n\n\n"),
            focusRange: focusRange
        )
    }

    private static func chapterText(from normalizedText: String, targets: [ReaderJumpTarget], progress: Double) -> ViewerRenderResult {
        let sections = normalizedText
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !sections.isEmpty else {
            return ViewerRenderResult(text: normalizedText, focusRange: nil)
        }

        let sectionCount = min(sections.count, targets.count)
        let total = max(sections.count, targets.count)
        let currentIndex = ReaderPlaybackChunkService.chunkIndex(for: progress, chunkCount: targets.count)
        var renderedSections: [String] = []
        renderedSections.reserveCapacity(sections.count)
        var focusRange: NSRange?
        var currentLocation = 0

        for index in 0..<sectionCount {
            let heading = chapterHeadingText(for: targets[index], fallbackIndex: index, total: total)
            let segment = [heading, sections[index]].joined(separator: "\n\n")
            if index == currentIndex {
                focusRange = NSRange(location: currentLocation, length: 0)
            }
            renderedSections.append(segment)
            currentLocation += segment.count
            if index < sectionCount - 1 || sections.count > sectionCount {
                currentLocation += 3
            }
        }

        if sections.count > sectionCount {
            for index in sectionCount..<sections.count {
                let segment = [
                    "Chapter \(index + 1) of \(total)",
                    sections[index]
                ].joined(separator: "\n\n")
                renderedSections.append(segment)
                currentLocation += segment.count
                if index < sections.count - 1 {
                    currentLocation += 3
                }
            }
        }

        return ViewerRenderResult(
            text: renderedSections.joined(separator: "\n\n\n"),
            focusRange: focusRange
        )
    }

    private static func chapterHeadingText(for target: ReaderJumpTarget, fallbackIndex: Int, total: Int) -> String {
        let title = target.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            return "Chapter \(fallbackIndex + 1) of \(total)"
        }
        return "Chapter \(fallbackIndex + 1) of \(total): \(title)"
    }
}

private struct ViewerRenderResult {
    let text: String
    let focusRange: NSRange?
}

struct NormalizedTextDocumentView: NSViewRepresentable {
    let text: String
    let focusRange: NSRange?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = STTextView.scrollableTextView()
        configure(scrollView)
        updateText(in: scrollView, context: context)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        updateText(in: nsView, context: context)
    }

    private func configure(_ scrollView: NSScrollView) {
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = .clear
        scrollView.contentInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)

        guard let textView = scrollView.documentView as? STTextView else { return }

        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 15)
        textView.textColor = .labelColor
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.backgroundColor = .clear
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true
        textView.textContainer.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    }

    private func updateText(in scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? STTextView else { return }
        if textView.text != text {
            textView.text = text
        }

        guard let focusRange else { return }
        guard context.coordinator.lastFocusLocation != focusRange.location else { return }
        context.coordinator.lastFocusLocation = focusRange.location

        DispatchQueue.main.async {
            guard let textView = scrollView.documentView as? STTextView else { return }
            textView.scrollRangeToVisible(focusRange)
        }
    }

    final class Coordinator {
        var lastFocusLocation: Int?
    }
}
