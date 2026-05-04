//
//  FreeBookHTMLViewerView.swift
//  Anything Reader
//
//  Presents the book's HTML page in a dedicated in-app screen.
//

import SwiftUI

struct FreeBookHTMLViewerView: View {
    let book: FreeBook
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    @State private var loadErrorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if let url = book.inAppHTMLURL {
                ZStack {
                    FreeBookWebView(url: url, isLoading: $isLoading, errorMessage: $loadErrorMessage)

                    if isLoading {
                        ProgressView("Loading book...")
                            .padding(16)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            } else {
                missingHTMLView
            }
        }
        .navigationTitle(book.displayTitle)
        .onAppear {
            if book.inAppHTMLURL != nil {
                isLoading = true
                loadErrorMessage = nil
            }
        }
    }

    private var missingHTMLView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.orange)

            Text("HTML preview not available")
                .font(.headline)

            Text("This book does not have a valid HTML link in the catalog.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
