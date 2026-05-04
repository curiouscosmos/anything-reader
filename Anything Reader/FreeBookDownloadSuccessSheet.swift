//
//  FreeBookDownloadSuccessSheet.swift
//  Anything Reader
//
//  Small success modal shown after a free book is imported into the library.
//

import SwiftUI

struct FreeBookDownloadSuccess: Identifiable {
    let id = UUID()
    let title: String
}

struct FreeBookDownloadSuccessSheet: View {
    let title: String
    let onView: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.green)

            VStack(spacing: 6) {
                Text("Download complete")
                    .font(.title3.weight(.bold))

                Text("\(title) was added to your library.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                Button("Done", action: onDone)
                    .buttonStyle(.bordered)

                Button("View", action: onView)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(minWidth: 320)
        .padding(28)
    }
}
