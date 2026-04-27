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
            NormalizedTextDocumentView(text: normalizedText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(documentBackground)
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
}

struct NormalizedTextDocumentView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = STTextView.scrollableTextView()
        configure(scrollView)
        updateText(in: scrollView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        updateText(in: nsView)
    }

    private func configure(_ scrollView: NSScrollView) {
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = .clear

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

    private func updateText(in scrollView: NSScrollView) {
        guard let textView = scrollView.documentView as? STTextView else { return }
        if textView.text != text {
            textView.text = text
        }
    }
}
