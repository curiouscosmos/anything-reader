//
//  FreeBookWebView.swift
//  Anything Reader
//
//  macOS wrapper around WKWebView for in-app HTML viewing.
//

import SwiftUI
import WebKit

struct FreeBookWebView: NSViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = false
        print("Free book HTML opening URL: \(url.absoluteString)")
        context.coordinator.load(url: url, in: webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        guard nsView.url != url else { return }
        print("Free book HTML reloading URL: \(url.absoluteString)")
        context.coordinator.load(url: url, in: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading, errorMessage: $errorMessage)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var isLoading: Bool
        @Binding var errorMessage: String?
        private var loadTask: Task<Void, Never>?

        init(isLoading: Binding<Bool>, errorMessage: Binding<String?>) {
            _isLoading = isLoading
            _errorMessage = errorMessage
        }

        deinit {
            loadTask?.cancel()
        }

        func load(url: URL, in webView: WKWebView) {
            loadTask?.cancel()
            isLoading = true
            errorMessage = nil

            loadTask = Task { @MainActor in
                do {
                    let finalURL = Self.preferredRemoteURL(for: url)
                    let (data, response) = try await URLSession.shared.data(from: finalURL)

                    guard let httpResponse = response as? HTTPURLResponse,
                          (200...299).contains(httpResponse.statusCode) else {
                        throw NSError(domain: "FreeBookWebView", code: -1, userInfo: [
                            NSLocalizedDescriptionKey: "The HTML page could not be loaded."
                        ])
                    }

                    guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                        throw NSError(domain: "FreeBookWebView", code: -2, userInfo: [
                            NSLocalizedDescriptionKey: "The HTML response could not be decoded."
                        ])
                    }

                    let responsiveHTML = Self.makeResponsive(html)
                    webView.loadHTMLString(responsiveHTML, baseURL: response.url ?? finalURL.deletingLastPathComponent())
                } catch {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = nil
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            DispatchQueue.main.async {
                self.isLoading = false
                print("Free book HTML web view failed after navigation: \(error.localizedDescription)")
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            DispatchQueue.main.async {
                self.isLoading = false
                print("Free book HTML web view failed during provisional navigation: \(error.localizedDescription)")
            }
        }

        private static func preferredRemoteURL(for url: URL) -> URL {
            guard url.host?.contains("gutenberg.org") == true else {
                return url
            }

            let path = url.path.lowercased()
            guard path.contains("/ebooks/") else {
                return (url.scheme == "http" ? httpsURL(from: url) : url) ?? url
            }

            let lastComponent = url.lastPathComponent
            let parts = lastComponent.split(separator: ".").map(String.init)
            guard let identifier = parts.first, let bookID = Int(identifier) else {
                return (url.scheme == "http" ? httpsURL(from: url) : url) ?? url
            }

            let variant = parts.contains("images") ? "images" : "noimages"
            return URL(string: "https://www.gutenberg.org/cache/epub/\(bookID)/pg\(bookID)-\(variant).html")
                ?? (url.scheme == "http" ? httpsURL(from: url) : url) ?? url
        }

        private static func httpsURL(from url: URL) -> URL? {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return nil
            }
            components.scheme = "https"
            return components.url
        }

        private static func makeResponsive(_ html: String) -> String {
            let responsiveHeader = """
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                html, body {
                    max-width: 100% !important;
                    overflow-x: hidden !important;
                    word-wrap: break-word !important;
                    overflow-wrap: break-word !important;
                    -webkit-text-size-adjust: 100%;
                }
                body {
                    box-sizing: border-box !important;
                    padding-left: 16px !important;
                    padding-right: 16px !important;
                }
                img, table, pre, blockquote, iframe {
                    max-width: 100% !important;
                    height: auto !important;
                }
            </style>
            """

            if let headRange = html.range(of: "<head>", options: [.caseInsensitive]) {
                return html.replacingCharacters(in: headRange.upperBound..<headRange.upperBound, with: responsiveHeader)
            }

            return responsiveHeader + html
        }
    }
}
