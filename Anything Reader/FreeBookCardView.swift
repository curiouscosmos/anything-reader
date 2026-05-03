//
//  FreeBookCardView.swift
//  Anything Reader
//
//  Card used to present free books from the downloaded catalog.
//

import SwiftUI

struct FreeBookCardView: View {
    let book: FreeBook
    var onView: (() -> Void)? = nil
    var onDownload: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                coverImage

                LinearGradient(
                    colors: [
                        .clear,
                        .black.opacity(0.05),
                        .black.opacity(0.70)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                bookMetaOverlay
                    .padding(16)
            }
            .frame(height: 350)
            // .clipped()

            actionButtons
                .padding(14)
                .background(cardFooterBackground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 10)
    }

    private var coverImage: some View {
        ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.primary.opacity(0.08),
                            Color.primary.opacity(0.03)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let coverURL = book.coverURL {
                AsyncImage(url: coverURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .controlSize(.small)

                    case .success(let image):
                        image
                            .resizable()

                    case .failure:
                        placeholderCover

                    @unknown default:
                        placeholderCover
                    }
                }
            } else {
                placeholderCover
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var bookMetaOverlay: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(book.displayTitle)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(2)

            Text(book.displayAuthors)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)

            HStack(spacing: 8) {
                metaPill(book.displayLanguages)
                metaPill(book.displayFormat)
            }
        }
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
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BookCardSecondaryButtonStyle())
            .disabled(book.htmlURL == nil)

            Button {
                onDownload?()
            } label: {
                Label("Download", systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BookCardPrimaryButtonStyle())
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
            .padding(.vertical, 11)
            .background(
                LinearGradient(
                    colors: [
                        Color.green,
                        Color.green
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
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
            .background(
                Color.primary.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

#Preview {
    // Preview Free Books screen for development
    FreeBooksView(searchText: .constant("Lincoln"))
}
