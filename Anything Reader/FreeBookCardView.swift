//
//  FreeBookCardView.swift
//  Anything Reader
//
//  Card used to present free books from the downloaded catalog.
//

import AppKit
import SwiftUI

struct FreeBookCardView: View {
    let book: FreeBook
    var onView: (() -> Void)? = nil
    var onDownload: (() -> Void)? = nil
    var isDownloadDisabled: Bool = false

    @State private var cachedCoverPath: String?
    @State private var isResolvingCoverArt = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                coverImage

                LinearGradient(
                    colors: [
                        .clear,
                        .black.opacity(0.12),
                        .black.opacity(0.78)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                bookMetaOverlay
                    .padding(16)
            }
            .frame(width: 260, height: 320)
            .clipped()

            actionButtons
                .padding(14)
                .frame(height: 64)
                .background(cardFooterBackground)
        }
        .frame(width: 260, height: 390)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 22, x: 0, y: 12)
        .task(id: coverCacheTaskID) {
            await resolveCachedCoverArtIfNeeded()
        }
    }

    private var coverImage: some View {
        ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.primary.opacity(0.10),
                            Color.primary.opacity(0.03)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let cachedImage = cachedCoverImage {
                Image(nsImage: cachedImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 260, height: 320, alignment: .top)
                    .clipped()
            } else if isResolvingCoverArt {
                ProgressView()
                    .controlSize(.small)
            } else {
                placeholderCover
            }
        }
    }

    private var bookMetaOverlay: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(book.displayTitle)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .shadow(radius: 4)

            Text(book.displayAuthors)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.84))
                .lineLimit(1)

            HStack(spacing: 8) {
                metaPill(book.displayLanguages)
                metaPill(book.displayFormat)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metaPill(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.white.opacity(0.16), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            )
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button {
                onView?()
            } label: {
                Label("View", systemImage: "eye.fill")
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BookCardSecondaryButtonStyle())
            .readerPointerCursor()
            .disabled(book.htmlURL == nil)

            Button {
                onDownload?()
            } label: {
                Label("Download", systemImage: "arrow.down.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BookCardPrimaryButtonStyle())
            .readerPointerCursor()
            .disabled(isDownloadDisabled)
            .opacity(isDownloadDisabled ? 0.55 : 1)
        }
    }

    private var placeholderCover: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 34, weight: .semibold))

            Text("No cover")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.secondary)
    }

    private var cachedCoverImage: NSImage? {
        guard let cachedCoverPath else { return nil }
        return NSImage(contentsOf: URL(fileURLWithPath: cachedCoverPath))
    }

    private var coverCacheTaskID: String {
        book.coverURL?.absoluteString ?? "book-\(book.id)"
    }

    @MainActor
    private func resolveCachedCoverArtIfNeeded() async {
        guard cachedCoverPath == nil else { return }
        guard book.coverURL != nil else { return }

        isResolvingCoverArt = true
        defer { isResolvingCoverArt = false }

        if let localURL = await FreeBookCoverArtCacheService.shared.cachedCoverURL(for: book.coverURL) {
            cachedCoverPath = localURL.path
        }
    }

    private var cardBackground: some ShapeStyle {
        Color(nsColor: .controlBackgroundColor)
    }

    private var cardFooterBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                Color.primary.opacity(0.035),
                Color.primary.opacity(0.015)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct BookCardPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 11)
            .background(
                ReaderStyle.accentColor(named: "green"),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct BookCardSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.bold))
            .foregroundStyle(.primary)
            .padding(.vertical, 11)
            .readerPointerCursor()
            .background(
                Color.primary.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

#Preview {
    // Preview Free Books screen for development
    FreeBooksView(
        searchText: .constant("Lincoln"),
        isDownloadingBook: .constant(false),
        downloadMessage: .constant(""),
        onDownloadBook: { _ in }
    )
}
