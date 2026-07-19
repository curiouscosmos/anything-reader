import Foundation

// Message payload written by the browser host into the app inbox directory.
nonisolated struct BrowserNativeMessage: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String?
    let text: String
    let pageURL: String?
    let site: String?
    let summarize: Bool?
    let receivedAt: Date
}

// Manages the browser-native-messaging bridge and the helper host binary.
actor BrowserNativeMessagingService {
    // Shared singleton because browser installation and message consumption are global concerns.
    static let shared = BrowserNativeMessagingService()

    private let hostName = "com.anythingreader.mac"
    private let allowedFirefoxExtensionIdentifier = "anything-reader@local"
    private let chromeExtensionIdentifier = "hfhjoleddnlbcgehaacbgglemiflaboj"
    private let inboxDirectoryName = "Browser Inbox"
    private let hostExecutableFileName = "AnythingReaderHost"
    private let hostSourceFileName = "AnythingReaderHost.swift"
    private let manifestFileName = "com.anythingreader.mac.json"

    // Installs the host binary and manifests if the browser bridge is not yet set up.
    func installHostIfNeeded() throws {
        guard !isAppSandboxed else {
            // Sandboxed builds cannot invoke xcrun to compile the helper at runtime.
            // Treat browser host installation as unavailable instead of surfacing a startup error.
            return
        }

        let hostExecutableURL = try ensureHostExecutable()

        let firefoxManifest = FirefoxNativeHostManifest(
            name: hostName,
            description: "Anything Reader native messaging host",
            path: hostExecutableURL.path,
            type: "stdio",
            allowedExtensions: [allowedFirefoxExtensionIdentifier]
        )

        let firefoxManifestData = try manifestData(for: firefoxManifest)
        let firefoxManifestURL = try firefoxManifestURL()
        try writeIfNeeded(data: firefoxManifestData, to: firefoxManifestURL)

        try syncChromeManifestIfNeeded(hostExecutableURL: hostExecutableURL)
    }

    // Reads all queued browser messages, then deletes them so they are not processed twice.
    func consumePendingMessages() throws -> [BrowserNativeMessage] {
        let fileManager = FileManager.default
        let inboxDirectoryURL = try browserInboxDirectoryURL()
        let pendingFiles = try fileManager.contentsOfDirectory(
            at: inboxDirectoryURL,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "json" }
        .sorted { lhs, rhs in
            let leftDate = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let rightDate = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return leftDate < rightDate
        }

        var messages: [BrowserNativeMessage] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for fileURL in pendingFiles {
            guard let data = try? Data(contentsOf: fileURL) else {
                try? fileManager.removeItem(at: fileURL)
                continue
            }

            if let message = try? decoder.decode(BrowserNativeMessage.self, from: data) {
                messages.append(message)
            }

            try? fileManager.removeItem(at: fileURL)
        }

        return messages
    }

    // Materializes the embedded host source and compiles it into the executable helper.
    private func ensureHostExecutable() throws -> URL {
        let sourceURL = try browserHostSourceURL()
        let executableURL = try browserHostExecutableURL()
        let source = Self.embeddedHostSource
        let fileManager = FileManager.default

        let sourceDirectoryURL = sourceURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: sourceDirectoryURL, withIntermediateDirectories: true)

        try source.write(to: sourceURL, atomically: true, encoding: .utf8)
        try compileHost(from: sourceURL, to: executableURL)

        return executableURL
    }

    // Invokes swiftc to build the host helper and surfaces compiler diagnostics if it fails.
    private func compileHost(from sourceURL: URL, to executableURL: URL) throws {
        let process = Process()
        let standardErrorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [
            "swiftc",
            "-parse-as-library",
            sourceURL.path,
            "-O",
            "-o",
            executableURL.path
        ]
        process.standardError = standardErrorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = standardErrorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(
                domain: hostName,
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: errorMessage ?? "The browser host could not be compiled."]
            )
        }

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )
    }

    private func browserHostSourceURL() throws -> URL {
        try browserSupportDirectoryURL().appendingPathComponent(hostSourceFileName)
    }

    private func browserHostExecutableURL() throws -> URL {
        try browserSupportDirectoryURL().appendingPathComponent(hostExecutableFileName)
    }

    private func firefoxManifestURL() throws -> URL {
        let fileManager = FileManager.default
        let applicationSupportDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let hostDirectory = applicationSupportDirectory
            .appendingPathComponent("Mozilla", isDirectory: true)
            .appendingPathComponent("NativeMessagingHosts", isDirectory: true)

        if !fileManager.fileExists(atPath: hostDirectory.path) {
            try fileManager.createDirectory(at: hostDirectory, withIntermediateDirectories: true)
        }

        return hostDirectory.appendingPathComponent(manifestFileName, isDirectory: false)
    }

    private func chromeManifestURL() throws -> URL {
        let fileManager = FileManager.default
        let applicationSupportDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let hostDirectory = applicationSupportDirectory
            .appendingPathComponent("Google", isDirectory: true)
            .appendingPathComponent("Chrome", isDirectory: true)
            .appendingPathComponent("NativeMessagingHosts", isDirectory: true)

        if !fileManager.fileExists(atPath: hostDirectory.path) {
            try fileManager.createDirectory(at: hostDirectory, withIntermediateDirectories: true)
        }

        return hostDirectory.appendingPathComponent(manifestFileName, isDirectory: false)
    }

    private func browserInboxDirectoryURL() throws -> URL {
        let browserSupportDirectory = try browserSupportDirectoryURL()
        let inboxDirectory = browserSupportDirectory.appendingPathComponent(inboxDirectoryName, isDirectory: true)

        if !FileManager.default.fileExists(atPath: inboxDirectory.path) {
            try FileManager.default.createDirectory(at: inboxDirectory, withIntermediateDirectories: true)
        }

        return inboxDirectory
    }

    private func browserSupportDirectoryURL() throws -> URL {
        let fileManager = FileManager.default
        let applicationSupportDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let appDirectory = applicationSupportDirectory.appendingPathComponent("Anything Reader", isDirectory: true)
        if !fileManager.fileExists(atPath: appDirectory.path) {
            try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        }

        return appDirectory
    }

    private func manifestData<T: Encodable>(for manifest: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(manifest)
    }

    private func syncChromeManifestIfNeeded(hostExecutableURL: URL) throws {
        let chromeManifestURL = try chromeManifestURL()

        let chromeManifest = ChromeNativeHostManifest(
            name: hostName,
            description: "Anything Reader native messaging host",
            path: hostExecutableURL.path,
            type: "stdio",
            allowedOrigins: ["chrome-extension://\(chromeExtensionIdentifier)/"]
        )

        let chromeManifestData = try manifestData(for: chromeManifest)
        try writeIfNeeded(data: chromeManifestData, to: chromeManifestURL)
    }

    private func writeIfNeeded(data: Data, to url: URL) throws {
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: url.path),
           let existingData = fileManager.contents(atPath: url.path),
           existingData == data {
            return
        }

        try data.write(to: url, options: [.atomic])
    }

    private var isAppSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }
}

nonisolated private struct FirefoxNativeHostManifest: Codable, Sendable {
    let name: String
    let description: String
    let path: String
    let type: String
    let allowedExtensions: [String]

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case path
        case type
        case allowedExtensions = "allowed_extensions"
    }
}

nonisolated private struct ChromeNativeHostManifest: Codable, Sendable {
    let name: String
    let description: String
    let path: String
    let type: String
    let allowedOrigins: [String]

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case path
        case type
        case allowedOrigins = "allowed_origins"
    }
}

private extension BrowserNativeMessagingService {
    static let embeddedHostSource = #"""
import Foundation

struct BrowserNativeMessage: Codable {
    let id: String
    let title: String?
    let text: String
    let pageURL: String?
    let site: String?
    let summarize: Bool?
    let receivedAt: Date
}

struct NativeHostResponse: Codable {
    let ok: Bool
    let messageID: String?
    let error: String?
}

@main
enum AnythingReaderHost {
    private static let hostName = "com.anythingreader.mac"

    static func main() {
        autoreleasepool {
            guard let payload = readMessage() else {
                writeResponse(NativeHostResponse(ok: false, messageID: nil, error: "No native message was received."))
                return
            }

            do {
                let message = try decodeMessage(from: payload)
                launchAppIfNeeded()
                try store(message: message)
                writeResponse(NativeHostResponse(ok: true, messageID: message.id, error: nil))
            } catch {
                writeResponse(NativeHostResponse(ok: false, messageID: nil, error: error.localizedDescription))
            }
        }
    }

    private static func launchAppIfNeeded() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-b", "AR.Anything-Reader-temp"]
        try? process.run()
    }

    private static func decodeMessage(from data: Data) throws -> BrowserNativeMessage {
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])

        let text = preferredTextValue(
            for: ["text", "content", "body", "pageText", "selection"],
            in: jsonObject
        )
        ?? (jsonObject as? String)

        let trimmedText = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedText.isEmpty else {
            throw NSError(
                domain: hostName,
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The browser payload did not include text."]
            )
        }

        let title = firstStringValue(
            for: ["title", "pageTitle", "documentTitle", "name"],
            in: jsonObject
        )
        let pageURL = firstStringValue(
            for: ["pageURL", "pageUrl", "url", "sourceURL", "sourceUrl", "href"],
            in: jsonObject
        )
        let summarize = firstBoolValue(
            for: ["summarize", "shouldSummarize"],
            in: jsonObject
        )

        return BrowserNativeMessage(
            id: UUID().uuidString,
            title: {
                let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
                return (trimmedTitle?.isEmpty == false) ? trimmedTitle : nil
            }(),
            text: trimmedText,
            pageURL: {
                let trimmedURL = pageURL?.trimmingCharacters(in: .whitespacesAndNewlines)
                return (trimmedURL?.isEmpty == false) ? trimmedURL : nil
            }(),
            site: {
                let trimmedSite = firstStringValue(
                    for: ["site", "siteName", "domain", "host"],
                    in: jsonObject
                )?.trimmingCharacters(in: .whitespacesAndNewlines)
                return (trimmedSite?.isEmpty == false) ? trimmedSite : nil
            }(),
            summarize: summarize,
            receivedAt: Date()
        )
    }

    private static func store(message: BrowserNativeMessage) throws {
        let directoryURL = try browserInboxDirectoryURL()
        let fileURL = directoryURL.appendingPathComponent("browser-message-\(message.id).json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(message)
        try data.write(to: fileURL, options: [.atomic])
    }

    private static func browserInboxDirectoryURL() throws -> URL {
        let fileManager = FileManager.default
        let applicationSupportDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let appDirectory = applicationSupportDirectory.appendingPathComponent("Anything Reader", isDirectory: true)
        if !fileManager.fileExists(atPath: appDirectory.path) {
            try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        }

        let inboxDirectory = appDirectory.appendingPathComponent("Browser Inbox", isDirectory: true)
        if !fileManager.fileExists(atPath: inboxDirectory.path) {
            try fileManager.createDirectory(at: inboxDirectory, withIntermediateDirectories: true)
        }

        return inboxDirectory
    }

    private static func readMessage() -> Data? {
        guard let lengthData = readExactly(4) else { return nil }

        let lengthBytes = [UInt8](lengthData)
        guard lengthBytes.count == 4 else { return nil }

        let messageLength = Int(
            UInt32(lengthBytes[0])
            | UInt32(lengthBytes[1]) << 8
            | UInt32(lengthBytes[2]) << 16
            | UInt32(lengthBytes[3]) << 24
        )

        guard messageLength > 0 else { return nil }
        return readExactly(messageLength)
    }

    private static func readExactly(_ byteCount: Int) -> Data? {
        guard byteCount > 0 else { return Data() }

        var data = Data()
        data.reserveCapacity(byteCount)

        while data.count < byteCount {
            let remainingCount = byteCount - data.count
            let chunk = FileHandle.standardInput.readData(ofLength: remainingCount)

            if chunk.isEmpty {
                return nil
            }

            data.append(chunk)
        }

        return data
    }

    private static func writeResponse(_ response: NativeHostResponse) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        guard let data = try? encoder.encode(response) else { return }
        writeMessage(data)
    }

    private static func writeMessage(_ data: Data) {
        var length = UInt32(data.count).littleEndian
        withUnsafeBytes(of: &length) { lengthBytes in
            FileHandle.standardOutput.write(Data(lengthBytes))
        }
        FileHandle.standardOutput.write(data)
    }

    private static func firstStringValue(for keys: [String], in jsonObject: Any) -> String? {
        if let string = jsonObject as? String {
            return string
        }

        if let dictionary = jsonObject as? [String: Any] {
            for key in keys {
                if let value = dictionary[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return value
                }
            }

            for value in dictionary.values {
                if let nested = firstStringValue(for: keys, in: value) {
                    return nested
                }
            }
        }

        if let array = jsonObject as? [Any] {
            for value in array {
                if let nested = firstStringValue(for: keys, in: value) {
                    return nested
                }
            }
        }

        return nil
    }

    private static func preferredTextValue(for keys: [String], in jsonObject: Any) -> String? {
        var candidates: [String] = []
        collectTextCandidates(for: keys, in: jsonObject, into: &candidates)

        return candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !isPlaceholderText($0) }
            .max { lhs, rhs in lhs.count < rhs.count }
    }

    private static func collectTextCandidates(for keys: [String], in jsonObject: Any, into candidates: inout [String]) {
        if let string = jsonObject as? String {
            candidates.append(string)
            return
        }

        if let dictionary = jsonObject as? [String: Any] {
            for key in keys {
                if let value = dictionary[key] {
                    collectTextCandidates(for: keys, in: value, into: &candidates)
                }
            }

            for value in dictionary.values {
                collectTextCandidates(for: keys, in: value, into: &candidates)
            }
            return
        }

        if let array = jsonObject as? [Any] {
            for value in array {
                collectTextCandidates(for: keys, in: value, into: &candidates)
            }
        }
    }

    private static func isPlaceholderText(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "anything-reader:page-text"
    }

    private static func firstBoolValue(for keys: [String], in jsonObject: Any) -> Bool? {
        if let dictionary = jsonObject as? [String: Any] {
            for key in keys {
                if let value = dictionary[key] as? Bool {
                    return value
                }
            }

            for value in dictionary.values {
                if let nested = firstBoolValue(for: keys, in: value) {
                    return nested
                }
            }
        }

        if let array = jsonObject as? [Any] {
            for value in array {
                if let nested = firstBoolValue(for: keys, in: value) {
                    return nested
                }
            }
        }

        return nil
    }
}

private extension Optional where Wrapped == String {
    var nilIfEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        return value
    }
}
"""#
}
