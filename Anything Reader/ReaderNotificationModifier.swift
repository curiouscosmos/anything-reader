//
//  ReaderNotificationModifier.swift
//  Anything Reader
//
//  Collects the app's transient alerts and confirmation dialog so the main
//  ContentView body stays small enough for the compiler to type-check cleanly.
//

import SwiftUI

struct ReaderNotificationModifier: ViewModifier {
    @Binding var uploadAlertMessage: String?
    @Binding var browserImportAlertMessage: String?
    @Binding var browserHostInstallAlertMessage: String?
    @Binding var importFailureMessage: String?
    @Binding var viewerAlertMessage: String?
    @Binding var pendingAudioDeletionEntry: LibraryEntry?
    @Binding var audioGenerationAlertMessage: String?
    @Binding var generatedAudioAlertMessage: String?
    @Binding var summaryGenerationAlertMessage: String?

    let onRetryPendingImport: () -> Void
    let onDiscardPendingImport: () -> Void
    let onConfirmAudioDeletion: () -> Void

    func body(content: Content) -> some View {
        content
            .alert(
                "Upload Failed",
                isPresented: Binding(
                    get: { uploadAlertMessage != nil },
                    set: { if !$0 { uploadAlertMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    uploadAlertMessage = nil
                }
            } message: {
                Text(uploadAlertMessage ?? "The selected file could not be imported.")
            }
            .alert(
                "Browser Import Failed",
                isPresented: Binding(
                    get: { browserImportAlertMessage != nil },
                    set: { if !$0 { browserImportAlertMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    browserImportAlertMessage = nil
                }
            } message: {
                Text(browserImportAlertMessage ?? "The browser page could not be imported.")
            }
            .alert(
                "Browser Host Install Failed",
                isPresented: Binding(
                    get: { browserHostInstallAlertMessage != nil },
                    set: { if !$0 { browserHostInstallAlertMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    browserHostInstallAlertMessage = nil
                }
            } message: {
                Text(browserHostInstallAlertMessage ?? "The Chrome manifest could not be installed.")
            }
            .alert(
                "Normalization Failed",
                isPresented: Binding(
                    get: { importFailureMessage != nil },
                    set: { if !$0 { importFailureMessage = nil } }
                )
            ) {
                Button("Retry") {
                    onRetryPendingImport()
                }

                Button("Remove File", role: .destructive) {
                    onDiscardPendingImport()
                }
            } message: {
                Text(importFailureMessage ?? "The file could not be normalized.")
            }
            .alert(
                "Viewer Unavailable",
                isPresented: Binding(
                    get: { viewerAlertMessage != nil },
                    set: { if !$0 { viewerAlertMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    viewerAlertMessage = nil
                }
            } message: {
                Text(viewerAlertMessage ?? "The normalized TXT file could not be opened.")
            }
            .confirmationDialog(
                "Delete audio file?",
                isPresented: Binding(
                    get: { pendingAudioDeletionEntry != nil },
                    set: { if !$0 { pendingAudioDeletionEntry = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete audio file", role: .destructive) {
                    onConfirmAudioDeletion()
                }

                Button("Cancel", role: .cancel) {
                    pendingAudioDeletionEntry = nil
                }
            } message: {
                Text("This will remove the generated audio export from the local library and delete the file from disk.")
            }
            .alert(
                "Audio Generation Failed",
                isPresented: Binding(
                    get: { audioGenerationAlertMessage != nil },
                    set: { if !$0 { audioGenerationAlertMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    audioGenerationAlertMessage = nil
                }
            } message: {
                Text(audioGenerationAlertMessage ?? "The audio file could not be generated.")
            }
            .alert(
                "Audio Playback Failed",
                isPresented: Binding(
                    get: { generatedAudioAlertMessage != nil },
                    set: { if !$0 { generatedAudioAlertMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    generatedAudioAlertMessage = nil
                }
            } message: {
                Text(generatedAudioAlertMessage ?? "The generated audio file could not be played.")
            }
            .alert(
                "Summary Failed",
                isPresented: Binding(
                    get: { summaryGenerationAlertMessage != nil },
                    set: { if !$0 { summaryGenerationAlertMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    summaryGenerationAlertMessage = nil
                }
            } message: {
                Text(summaryGenerationAlertMessage ?? "The summary could not be generated.")
            }
    }
}

extension View {
    func readerNotifications(
        uploadAlertMessage: Binding<String?>,
        browserImportAlertMessage: Binding<String?>,
        browserHostInstallAlertMessage: Binding<String?>,
        importFailureMessage: Binding<String?>,
        viewerAlertMessage: Binding<String?>,
        pendingAudioDeletionEntry: Binding<LibraryEntry?>,
        audioGenerationAlertMessage: Binding<String?>,
        generatedAudioAlertMessage: Binding<String?>,
        summaryGenerationAlertMessage: Binding<String?>,
        onRetryPendingImport: @escaping () -> Void,
        onDiscardPendingImport: @escaping () -> Void,
        onConfirmAudioDeletion: @escaping () -> Void
    ) -> some View {
        modifier(
            ReaderNotificationModifier(
                uploadAlertMessage: uploadAlertMessage,
                browserImportAlertMessage: browserImportAlertMessage,
                browserHostInstallAlertMessage: browserHostInstallAlertMessage,
                importFailureMessage: importFailureMessage,
                viewerAlertMessage: viewerAlertMessage,
                pendingAudioDeletionEntry: pendingAudioDeletionEntry,
                audioGenerationAlertMessage: audioGenerationAlertMessage,
                generatedAudioAlertMessage: generatedAudioAlertMessage,
                summaryGenerationAlertMessage: summaryGenerationAlertMessage,
                onRetryPendingImport: onRetryPendingImport,
                onDiscardPendingImport: onDiscardPendingImport,
                onConfirmAudioDeletion: onConfirmAudioDeletion
            )
        )
    }
}
