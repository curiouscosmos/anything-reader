//
//  FreeBookDownloadOptionsSheet.swift
//  Anything Reader
//
//  Confirmation sheet for downloading a free book into the local library.
//

import SwiftUI

struct FreeBookDownloadOptionsSheet: View {
    let book: FreeBook
    let onDownload: (Bool, TextLanguage) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var translateBook = false
    @State private var translateToLanguage: TextLanguage = .english

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection

                    formSection(title: "Download") {
                        Text(book.displayTitle)
                            .font(.headline)

                        Text(book.displayAuthors)
                            .foregroundStyle(.secondary)

                        if let sourceLanguage = book.primaryLanguage {
                            Text("Catalog language: \(sourceLanguage.displayName)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    formSection(title: "Translation") {
                        Toggle("Translate book", isOn: $translateBook)

                        if translateBook {
                            Picker("Translate to Language", selection: $translateToLanguage) {
                                ForEach(TextLanguage.allCases) { language in
                                    Text(language.displayName)
                                        .tag(language)
                                }
                            }
                            .pickerStyle(.menu)

                            Text("The book will be downloaded, translated, and then normalized for TTS.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("The downloaded book will be normalized for TTS without translation.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Download Book")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Download") {
                        dismiss()
                        onDownload(translateBook, translateToLanguage)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .interactiveDismissDisabled(true)
    }

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Download Free Book")
                .font(.title2.weight(.bold))

            Text("Choose whether to translate the book before it is normalized and added to your library.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.thinMaterial, in: Rectangle())
    }

    @ViewBuilder
    private func formSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.thinMaterial, in: Rectangle())
        }
    }
}
