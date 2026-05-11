//
//  DocumentTranslationService.swift
//  Anything Reader
//
//  Handles Apple Translation framework integration for imported documents.
//

import Foundation
import Observation
import SwiftUI
import Translation

// Translation failures are surfaced as user-facing errors so the import flow can recover gracefully.
enum DocumentTranslationError: LocalizedError {
    case unsupported(source: TextLanguage, target: TextLanguage)
    case missingLanguage

    var errorDescription: String? {
        switch self {
        case .unsupported(let source, let target):
            return "System doesn't support Translation from \(source.displayName) to \(target.displayName)"
        case .missingLanguage:
            return "Select both the document language and the translation language."
        }
    }
}

// Request payload passed into the system translation session.
struct DocumentTranslationRequest: Identifiable {
    let id = UUID()
    let sourceText: String
    let sourceLanguage: TextLanguage
    let targetLanguage: TextLanguage

    var sourceLocaleLanguage: Locale.Language? {
        sourceLanguage.localeLanguage
    }

    var targetLocaleLanguage: Locale.Language? {
        targetLanguage.localeLanguage
    }
}

// Coordinates the asynchronous Translation framework request lifecycle.
@MainActor
@Observable
final class DocumentTranslationCoordinator {
    fileprivate var activeRequest: DocumentTranslationRequest?

    private var continuation: CheckedContinuation<String, Error>?

    // Starts a translation request and suspends until the system session returns a result.
    func translate(
        sourceText: String,
        sourceLanguage: TextLanguage,
        targetLanguage: TextLanguage
    ) async throws -> String {
        guard sourceLanguage != .unknown, targetLanguage != .unknown else {
            throw DocumentTranslationError.missingLanguage
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.activeRequest = DocumentTranslationRequest(
                sourceText: sourceText,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage
            )
        }
    }

    // Returns the active request so the hidden host view can reconfigure its session.
    func currentRequest() -> DocumentTranslationRequest? {
        activeRequest
    }

    // Resumes the pending continuation with translated text.
    func finish(with translatedText: String) {
        continuation?.resume(returning: translatedText)
        continuation = nil
        activeRequest = nil
    }

    // Resumes the pending continuation with an error and clears the active request.
    func fail(with error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
        activeRequest = nil
    }

    // Cancels the current translation request using a cancellation error.
    func cancel() {
        fail(with: CancellationError())
    }
}

// Invisible SwiftUI host that owns the system translation session.
struct DocumentTranslationHostView: View {
    let coordinator: DocumentTranslationCoordinator
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .onAppear {
                syncConfiguration()
            }
            .onChange(of: coordinator.activeRequest?.id) { _, newValue in
                _ = newValue
                syncConfiguration()
            }
            .translationTask(configuration) { session in
                await performTranslation(using: session)
            }
    }

    // Rebuilds the translation configuration whenever a new request becomes active.
    @MainActor
    private func syncConfiguration() {
        guard let request = coordinator.currentRequest(),
              let sourceLanguage = request.sourceLocaleLanguage,
              let targetLanguage = request.targetLocaleLanguage else {
            configuration = nil
            return
        }

        configuration = TranslationSession.Configuration(
            source: sourceLanguage,
            target: targetLanguage,
            preferredStrategy: .lowLatency
        )
    }

    // Sends the active source text through the system Translation session.
    @MainActor
    private func performTranslation(using session: TranslationSession) async {
        guard let request = coordinator.currentRequest() else { return }

        do {
            try await session.prepareTranslation()
            let response = try await session.translate(request.sourceText)
            coordinator.finish(with: response.targetText)
        } catch {
            coordinator.fail(with: error)
        }
    }
}

// Maps the app's text-language enum to Locale.Language for the Translation framework.
extension TextLanguage {
    var localeLanguage: Locale.Language? {
        guard self != .unknown else { return nil }
        return Locale.Language(identifier: rawValue)
    }
}
