//
//  FreeBookCardView.swift
//  Anything Reader
//
//  Card used to present free books from the downloaded catalog.
//

import SwiftUI

struct FreeBookCardView: View {
    let book: FreeBook

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            coverImage

            VStack(alignment: .leading, spacing: 8) {
                Text(book.displayTitle)
                    .font(.headline.weight(.bold))
                    .lineLimit(2)

                Text(book.displayAuthors)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                metadataRow(title: "Language", value: book.displayLanguages)
                metadataRow(title: "Format", value: book.displayFormat)
                metadataRow(title: "Subject", value: book.displaySubjects)
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var coverImage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.08))

            if let coverURL = book.coverURL {
                AsyncImage(url: coverURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
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
        .frame(height: 220)
        .clipped()
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var placeholderCover: some View {
        VStack(spacing: 10) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("No cover")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func metadataRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.medium))
                .lineLimit(1)
        }
    }

    private var background: some ShapeStyle {
        LinearGradient(
            colors: [
                Color(red: 0.98, green: 0.98, blue: 0.97),
                Color(red: 0.94, green: 0.95, blue: 0.93)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
