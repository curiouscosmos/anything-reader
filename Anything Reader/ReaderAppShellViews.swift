//
//  ReaderAppShellViews.swift
//  Anything Reader
//
//  Small shell-level views extracted from ContentView for clarity.
//

import SwiftUI

struct ReaderBackgroundView: View {
    let preferredMode: AppearanceMode

    var body: some View {
        Group {
            switch preferredMode {
            case .light:
                LinearGradient(
                    colors: [
                        Color(red: 0.97, green: 0.98, blue: 0.97),
                        Color(red: 0.93, green: 0.95, blue: 0.94),
                        Color(red: 0.88, green: 0.91, blue: 0.89)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .dark, .system:
                LinearGradient(
                    colors: [
                        Color(red: 26 / 255, green: 35 / 255, blue: 30 / 255)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .ignoresSafeArea()
    }
}

struct ReaderUpdateBannerView: View {
    let notice: AppUpdateNotice
    let onDownload: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(notice.title)
                    .font(.headline.weight(.bold))
                Text(notice.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button {
                onDownload()
            } label: {
                Label("Download", systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.green.opacity(0.35), lineWidth: 1)
        )
    }
}

struct ReaderHomeDropOverlayView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color.green.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(
                        Color.green.opacity(0.72),
                        style: StrokeStyle(lineWidth: 2, dash: [10, 8])
                    )
            )
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 28, weight: .semibold))
                    Text("Drop PDF, ePub, TXT, or image files here")
                        .font(.headline)
                    Text("The file will open in the upload flow after it is validated and staged locally.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .padding(24)
            )
    }
}
