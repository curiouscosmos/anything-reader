//
//  DocumentIngestService.swift
//  Anything Reader
//
//  Handles PDF, TXT, and ePub extraction plus normalization.
//

import AppKit
import Foundation
import PDFKit
import Vision
import ZIPFoundation

struct IngestedDocument {
    let title: String?
    let normalizedText: String
    let normalizedTextFileURL: URL
    let sourceKind: ReaderSourceKind
    let fileSizeBytes: Int64
    let textLanguage: TextLanguage
    let pdfExtractionMode: PDFExtractionMode?
    let readingStructureKind: ReadingStructureKind?
    let pageCount: Int
    let chapterCount: Int
    let sectionCount: Int
    let readingJumpTargets: [ReaderJumpTarget]
}

struct IngestedDocumentDraft {
    let title: String?
    let rawText: String
    let sourceKind: ReaderSourceKind
    let fileSizeBytes: Int64
    let detectedLanguage: TextLanguage
    let pdfExtractionMode: PDFExtractionMode?
    let readingStructureKind: ReadingStructureKind?
    let pageCount: Int
    let chapterCount: Int
    let sectionCount: Int
    let readingJumpTargets: [ReaderJumpTarget]
}

enum DocumentIngestError: LocalizedError {
    case invalidFile
    case unsupportedFileType
    case unreadableDocument
    case extractionFailed
    case normalizationFailed
    case archiveAccessFailed

    var errorDescription: String? {
        switch self {
        case .invalidFile:
            return "The selected file is missing, empty, or unreadable."
        case .unsupportedFileType:
            return "Please choose a PDF, TXT, or ePub file."
        case .unreadableDocument:
            return "The document could not be read."
        case .extractionFailed:
            return "The text could not be extracted from the file."
        case .normalizationFailed:
            return "The extracted text could not be normalized."
        case .archiveAccessFailed:
            return "The ePub archive could not be opened."
        }
    }
}

actor DocumentIngestService {
    static let shared = DocumentIngestService()

    private init() {}

    func process(
        stagedFileURL: URL,
        fileExtension: String,
        originalFileName: String,
        documentLanguage: TextLanguage
    ) throws -> IngestedDocument {
        let draft = try extractDraft(
            stagedFileURL: stagedFileURL,
            fileExtension: fileExtension,
            documentLanguage: documentLanguage
        )

        return try finalize(
            draft: draft,
            sourceText: draft.rawText,
            normalizedLanguage: draft.detectedLanguage,
            originalFileName: originalFileName,
            sourceURL: stagedFileURL
        )
    }

    func extractDraft(
        stagedFileURL: URL,
        fileExtension: String,
        documentLanguage: TextLanguage
    ) throws -> IngestedDocumentDraft {
        let normalizedFileExtension = fileExtension.lowercased()
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: stagedFileURL.path) else {
            throw DocumentIngestError.invalidFile
        }

        let fileData = try Data(contentsOf: stagedFileURL)
        guard !fileData.isEmpty else {
            throw DocumentIngestError.invalidFile
        }

        let sourceKind = readerSourceKind(for: normalizedFileExtension)
        let detectedLanguage = Self.detectLanguage(
            for: stagedFileURL,
            fileExtension: normalizedFileExtension
        )
        let resolvedLanguage = documentLanguage == .unknown ? detectedLanguage : documentLanguage
        let rawText: String
        let extractedTitle: String?
        let pdfExtractionMode: PDFExtractionMode?
        let readingMetadata: ReadingMetadata

        switch sourceKind {
        case .pdf:
            let pdfExtraction = try PDFTextExtractionService.extractText(
                from: stagedFileURL,
                preferredLanguage: resolvedLanguage
            )
            rawText = pdfExtraction.text
            extractedTitle = bestTitleCandidate(from: rawText)
            pdfExtractionMode = pdfExtraction.mode
            readingMetadata = PDFTextExtractionService.readingMetadata(from: stagedFileURL)
        case .epub:
            let epubTextExtraction = try EPUBTextExtractionService.extractText(from: stagedFileURL)
            rawText = epubTextExtraction.text
            extractedTitle = bestTitleCandidate(from: rawText)
            pdfExtractionMode = nil
            readingMetadata = epubTextExtraction.readingMetadata
        case .text, .pastedText:
            guard let text = String(data: fileData, encoding: .utf8) else {
                throw DocumentIngestError.unreadableDocument
            }
            rawText = TXTReadingMetadataService.sectionedText(from: text)
            extractedTitle = bestTitleCandidate(from: text)
            pdfExtractionMode = nil
            readingMetadata = TXTReadingMetadataService.readingMetadata(from: rawText)
        }

        let resolvedReadingMetadata: ReadingMetadata
        resolvedReadingMetadata = readingMetadata

        return IngestedDocumentDraft(
            title: extractedTitle,
            rawText: rawText,
            sourceKind: sourceKind,
            fileSizeBytes: Int64(fileData.count),
            detectedLanguage: resolvedLanguage,
            pdfExtractionMode: pdfExtractionMode,
            readingStructureKind: resolvedReadingMetadata.readingStructureKind,
            pageCount: resolvedReadingMetadata.pageCount,
            chapterCount: resolvedReadingMetadata.chapterCount,
            sectionCount: resolvedReadingMetadata.sectionCount,
            readingJumpTargets: resolvedReadingMetadata.readingJumpTargets
        )
    }

    func finalize(
        draft: IngestedDocumentDraft,
        sourceText: String,
        normalizedLanguage: TextLanguage,
        originalFileName: String,
        sourceURL: URL
    ) throws -> IngestedDocument {
        let normalizedText = TextNormalizationService.normalize(sourceText, language: normalizedLanguage)
        guard !normalizedText.isEmpty else {
            throw DocumentIngestError.normalizationFailed
        }

        let normalizedURL = try saveNormalizedText(
            normalizedText,
            originalFileName: originalFileName,
            sourceURL: sourceURL
        )

        return IngestedDocument(
            title: draft.title,
            normalizedText: normalizedText,
            normalizedTextFileURL: normalizedURL,
            sourceKind: draft.sourceKind,
            fileSizeBytes: draft.fileSizeBytes,
            textLanguage: normalizedLanguage,
            pdfExtractionMode: draft.pdfExtractionMode,
            readingStructureKind: draft.readingStructureKind,
            pageCount: draft.pageCount,
            chapterCount: draft.chapterCount,
            sectionCount: draft.sectionCount,
            readingJumpTargets: draft.readingJumpTargets
        )
    }

    private func saveNormalizedText(
        _ text: String,
        originalFileName: String,
        sourceURL: URL
    ) throws -> URL {
        let fileManager = FileManager.default
        let directoryURL = try uploadedFilesDirectory()
        let baseName = sourceURL.lastPathComponent
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let destinationURL = directoryURL.appendingPathComponent("\(baseName).txt")

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        guard fileManager.createFile(
            atPath: destinationURL.path,
            contents: Data(text.utf8),
            attributes: nil
        ) else {
            throw DocumentIngestError.normalizationFailed
        }

        return destinationURL
    }

    private func uploadedFilesDirectory() throws -> URL {
        let fileManager = FileManager.default
        let supportDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let appDirectory = supportDirectory.appendingPathComponent("Anything Reader", isDirectory: true)
        let uploadsDirectory = appDirectory.appendingPathComponent("Uploaded Files", isDirectory: true)

        if !fileManager.fileExists(atPath: uploadsDirectory.path) {
            try fileManager.createDirectory(at: uploadsDirectory, withIntermediateDirectories: true)
        }

        return uploadsDirectory
    }

    nonisolated static func detectLanguage(
        for stagedFileURL: URL,
        fileExtension: String
    ) -> TextLanguage {
        switch fileExtension.lowercased() {
        case "pdf":
            return PDFTextExtractionService.previewLanguage(from: stagedFileURL)
        case "epub":
            guard let text = try? EPUBTextExtractionService.extractText(from: stagedFileURL).text else {
                return .english
            }
            let detected = TextNormalizationService.detectLanguage(for: text)
            return detected == .unknown ? .english : detected
        case "txt":
            guard let data = try? Data(contentsOf: stagedFileURL),
                  let text = String(data: data, encoding: .utf8) else {
                return .english
            }
            let detected = TextNormalizationService.detectLanguage(for: text)
            return detected == .unknown ? .english : detected
        default:
            return .english
        }
    }

    private func readerSourceKind(for fileExtension: String) -> ReaderSourceKind {
        switch fileExtension.lowercased() {
        case "pdf":
            return .pdf
        case "epub":
            return .epub
        case "txt":
            return .text
        default:
            return .text
        }
    }
}

private struct ReadingMetadata {
    let readingStructureKind: ReadingStructureKind?
    let pageCount: Int
    let chapterCount: Int
    let sectionCount: Int
    let readingJumpTargets: [ReaderJumpTarget]
}

nonisolated private func bestTitleCandidate(from text: String) -> String? {
    let candidates = text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    guard let firstLine = candidates.first else { return nil }

    let cleaned = firstLine.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
    guard cleaned.count <= 120 else { return nil }
    guard cleaned.contains(where: { $0.isLetter }) else { return nil }
    return cleaned
}

private enum PDFTextExtractionService {
    nonisolated static func extractText(
        from url: URL,
        preferredLanguage: TextLanguage? = nil
    ) throws -> PDFTextExtractionResult {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else {
            throw DocumentIngestError.unreadableDocument
        }

        let pageCount = document.pageCount
        let extractionMode = classifyExtractionMode(for: document)
        let boilerplateThreshold = max(2, Int(ceil(Double(pageCount) * 0.35)))
        var candidateCounts: [String: Int] = [:]

        for index in 0..<pageCount {
            guard let page = document.page(at: index) else { continue }
            let pageBounds = page.bounds(for: .mediaBox)
            let headerRect = CGRect(
                x: pageBounds.minX,
                y: pageBounds.maxY - (pageBounds.height * 0.18),
                width: pageBounds.width,
                height: pageBounds.height * 0.18
            )
            let footerRect = CGRect(
                x: pageBounds.minX,
                y: pageBounds.minY,
                width: pageBounds.width,
                height: pageBounds.height * 0.18
            )

            let headerLines = lines(from: page.selection(for: headerRect)?.string)
            let footerLines = lines(from: page.selection(for: footerRect)?.string)

            for line in Set(headerLines + footerLines) {
                candidateCounts[line, default: 0] += 1
            }
        }

        let boilerplateLines: Set<String> = Set(candidateCounts.compactMap { (line, count) -> String? in
            guard count >= boilerplateThreshold, !line.isEmpty else { return nil }
            return line
        })

        var cleanedPages: [String] = []

        for index in 0..<pageCount {
            guard let page = document.page(at: index) else { continue }
            let directText = directPageText(from: page)
            let pagePreferredLanguage = preferredLanguage ?? detectLanguageHint(from: directText)
            let shouldUseOCRForPage = shouldUseOCRForPage(
                directText: directText,
                extractionMode: extractionMode
            )
            let extractedPageText = shouldUseOCRForPage
                ? (ocrText(from: page, preferredLanguage: pagePreferredLanguage)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? directText)
                : bestPageText(from: page, preferredLanguage: pagePreferredLanguage)
            let pageLines = lines(from: extractedPageText)
            let filteredLines = pageLines.filter { line in
                !boilerplateLines.contains(line)
                    && !isPageNumberLine(line)
                    && (shouldUseOCRForPage || !isLikelyBoilerplate(line))
            }

            let pageText = filteredLines.isEmpty && shouldUseOCRForPage
                ? extractedPageText
                : filteredLines.joined(separator: "\n")
            if !pageText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                cleanedPages.append(pageText)
            }
        }

        let extracted = cleanedPages.joined(separator: "\n\n[[PDF_PAGE_BREAK]]\n\n")
        if extractedWordCount(extracted) < max(40, pageCount * 12),
           extractionMode != .ocr {
            let forcedOCRPages = (0..<pageCount).compactMap { index -> String? in
                guard let page = document.page(at: index) else { return nil }
                let pagePreferredLanguage = preferredLanguage ?? detectLanguageHint(from: page.string)
                return bestPageText(from: page, preferredLanguage: pagePreferredLanguage, forceOCR: true)
            }

            let forcedExtracted = forcedOCRPages
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n[[PDF_PAGE_BREAK]]\n\n")

            guard !forcedExtracted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DocumentIngestError.extractionFailed
            }

            return PDFTextExtractionResult(text: forcedExtracted, mode: .ocr)
        }

        guard !extracted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DocumentIngestError.extractionFailed
        }

        return PDFTextExtractionResult(text: extracted, mode: extractionMode)
    }

    nonisolated static func previewLanguage(from url: URL) -> TextLanguage {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else {
            return .english
        }

        let samplePages = min(document.pageCount, 3)
        let sampleText = (0..<samplePages)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")

        let detected = TextNormalizationService.detectLanguage(for: sampleText)
        return detected == .unknown ? .english : detected
    }

    nonisolated static func readingMetadata(from url: URL) -> ReadingMetadata {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else {
            return ReadingMetadata(
                readingStructureKind: nil,
                pageCount: 0,
                chapterCount: 0,
                sectionCount: 0,
                readingJumpTargets: []
            )
        }

        let pageCount = document.pageCount
        let jumpTargets = (0..<pageCount).map { index in
            ReaderJumpTarget(index: index, title: "Page \(index + 1)")
        }

        return ReadingMetadata(
            readingStructureKind: .page,
            pageCount: pageCount,
            chapterCount: 0,
            sectionCount: 0,
            readingJumpTargets: jumpTargets
        )
    }

    struct PDFTextExtractionResult {
        let text: String
        let mode: PDFExtractionMode
    }

    nonisolated static func extractTitle(from url: URL) -> String? {
        guard let document = PDFDocument(url: url), let page = document.page(at: 0) else { return nil }
        let pageText = pageText(from: page, preferredLanguage: detectLanguageHint(from: page.string))
        return bestTitleCandidate(from: pageText)
    }

    nonisolated private static func lines(from text: String?) -> [String] {
        guard let text else { return [] }
        return text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map(Self.normalizedLine)
    }

    nonisolated private static func normalizedLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func pageText(
        from page: PDFPage,
        preferredLanguage: TextLanguage?
    ) -> String {
        bestPageText(from: page, preferredLanguage: preferredLanguage)
    }

    nonisolated private static func directPageText(from page: PDFPage) -> String {
        (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func bestPageText(
        from page: PDFPage,
        preferredLanguage: TextLanguage?,
        forceOCR: Bool = false
    ) -> String {
        let directText = directPageText(from: page)
        let directScore = textQualityScore(for: directText)

        if forceOCR || shouldUseOCR(for: directText) {
            if let ocrText = ocrText(from: page, preferredLanguage: preferredLanguage)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !ocrText.isEmpty {
                return ocrText
            }
            return directText
        }

        guard let ocrText = ocrText(from: page, preferredLanguage: preferredLanguage)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !ocrText.isEmpty else {
            return directText
        }

        let ocrScore = textQualityScore(for: ocrText)
        return ocrScore > directScore + 2 ? ocrText : directText
    }

    nonisolated private static func shouldUseOCR(for text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        // If the page string looks like unreadable character soup, treat it as a
        // signal that the PDF text layer is broken and OCR should be attempted on
        // a rendered page image instead.
        if looksLikeGibberish(trimmed) {
            return true
        }

        let asciiLetterCount = trimmed.unicodeScalars.filter { scalar in
            scalar.isASCII && CharacterSet.letters.contains(scalar)
        }.count
        guard asciiLetterCount > 0 else { return false }

        let vowelCount = trimmed.lowercased().filter { "aeiouyáéíóúàèìòùäëïöüâêîôûãõåøæœ".contains($0) }.count
        let ratio = Double(vowelCount) / Double(max(asciiLetterCount, 1))

        if ratio < 0.20 && trimmed.count >= 20 {
            return true
        }

        let wordCount = trimmed.split(whereSeparator: { $0.isWhitespace }).count
        return wordCount <= 2 && trimmed.count >= 48
    }

    nonisolated private static func shouldUseOCRForPage(
        directText: String,
        extractionMode: PDFExtractionMode
    ) -> Bool {
        let trimmed = directText.trimmingCharacters(in: .whitespacesAndNewlines)

        if extractionMode == .ocr {
            return true
        }

        if shouldUseOCR(for: trimmed) {
            return true
        }

        if isSparseEmbeddedText(trimmed) {
            return true
        }

        return false
    }

    nonisolated private static func looksLikeGibberish(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return true }

        let asciiLetters = letters.filter { $0.isASCII }
        let nonAsciiLetters = letters.count - asciiLetters.count
        let punctuationCount = text.unicodeScalars.filter { CharacterSet.punctuationCharacters.contains($0) }.count
        let digitCount = text.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.count
        let wordCount = text.split(whereSeparator: { $0.isWhitespace }).count

        if wordCount <= 3 && text.count >= 24 && punctuationCount >= 3 {
            return true
        }

        if asciiLetters.count >= 6 && nonAsciiLetters == 0 {
            let consonantHeavy = text.lowercased().filter { "bcdfghjklmnpqrstvwxyz".contains($0) }.count
            let vowelCount = text.lowercased().filter { "aeiou".contains($0) }.count
            if consonantHeavy > vowelCount * 3 && text.count >= 12 {
                return true
            }
        }

        if digitCount > 0 && letters.count <= digitCount + 2 && text.count >= 10 {
            return true
        }

        return false
    }

    nonisolated private static func textQualityScore(for text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        let letters = trimmed.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        let words = trimmed.split(whereSeparator: { $0.isWhitespace }).count
        let digits = trimmed.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.count
        let punctuation = trimmed.unicodeScalars.filter { CharacterSet.punctuationCharacters.contains($0) }.count
        let repeatedNoisePenalty = looksLikeGibberish(trimmed) ? 6 : 0

        return (letters * 2) + (words * 3) - digits - punctuation - repeatedNoisePenalty
    }

    nonisolated private static func isSparseEmbeddedText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        let wordCount = trimmed.split(whereSeparator: { $0.isWhitespace }).count
        let letterCount = trimmed.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        let lineCount = trimmed.split(separator: "\n", omittingEmptySubsequences: true).count

        // OCR-only PDFs sometimes expose only a title or a few fragments in the
        // embedded text layer. Those files should still be routed through OCR.
        return (wordCount <= 20 && letterCount <= 140) || lineCount <= 6 || trimmed.count <= 240
    }

    nonisolated private static func extractedWordCount(_ text: String) -> Int {
        text
            .split(whereSeparator: { $0.isWhitespace })
            .count
    }

    nonisolated private static func ocrText(
        from page: PDFPage,
        preferredLanguage: TextLanguage?
    ) -> String? {
        let renderSize = renderSize(for: page)
        guard let cgImage = renderPDFPage(page, size: renderSize) else {
            return nil
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = false
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ocrLanguageHints(preferredLanguage: preferredLanguage)

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observations = request.results, !observations.isEmpty else {
            return nil
        }

        let orderedObservations = observations.sorted { lhs, rhs in
            if lhs.boundingBox.midY == rhs.boundingBox.midY {
                return lhs.boundingBox.minX < rhs.boundingBox.minX
            }
            return lhs.boundingBox.midY > rhs.boundingBox.midY
        }

        let recognizedLines = orderedObservations.compactMap { observation in
            observation.topCandidates(1).first?.string
        }

        let merged = recognizedLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return merged.isEmpty ? nil : merged
    }

    nonisolated private static func renderSize(for page: PDFPage) -> CGSize {
        let bounds = page.bounds(for: .mediaBox)
        let maxDimension: CGFloat = 2800

        guard bounds.width > 0, bounds.height > 0 else {
            return CGSize(width: maxDimension, height: maxDimension)
        }

        let scale = maxDimension / max(bounds.width, bounds.height)
        return CGSize(
            width: max(bounds.width * scale, 1),
            height: max(bounds.height * scale, 1)
        )
    }

    nonisolated private static func renderPDFPage(_ page: PDFPage, size: CGSize) -> CGImage? {
        let targetSize = CGSize(width: max(size.width, 1), height: max(size.height, 1))
        let imageRect = CGRect(origin: .zero, size: targetSize)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(targetSize.width.rounded()),
            pixelsHigh: Int(targetSize.height.rounded()),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        bitmap.size = targetSize

        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.setFillColor(NSColor.white.cgColor)
        context.cgContext.fill(imageRect)
        context.cgContext.saveGState()

        let pdfBounds = page.bounds(for: .mediaBox)
        let scaleX = targetSize.width / max(pdfBounds.width, 1)
        let scaleY = targetSize.height / max(pdfBounds.height, 1)
        context.cgContext.scaleBy(x: scaleX, y: scaleY)
        page.draw(with: .mediaBox, to: context.cgContext)
        context.cgContext.restoreGState()
        NSGraphicsContext.restoreGraphicsState()

        return bitmap.cgImage
    }

    nonisolated private static func classifyExtractionMode(for document: PDFDocument) -> PDFExtractionMode {
        let pageCount = document.pageCount
        guard pageCount > 0 else { return .unknown }

        let sampleIndices = samplePageIndices(for: pageCount)
        var directScore = 0
        var ocrScore = 0

        for index in sampleIndices {
            guard let page = document.page(at: index) else { continue }
            let extractedText = directPageText(from: page)
            if shouldUseOCR(for: extractedText) || isSparseEmbeddedText(extractedText) {
                ocrScore += 1
            } else {
                directScore += 1
            }
        }

        if ocrScore == 0 {
            return .directText
        }

        if directScore == 0 {
            return .ocr
        }

        return .hybrid
    }

    nonisolated private static func samplePageIndices(for pageCount: Int) -> [Int] {
        guard pageCount > 0 else { return [] }

        if pageCount <= 5 {
            return Array(0..<pageCount)
        }

        let rawIndices = [
            0,
            pageCount / 4,
            pageCount / 2,
            (pageCount * 3) / 4,
            pageCount - 1
        ]

        return Array(Set(rawIndices.map { min(max($0, 0), pageCount - 1) })).sorted()
    }

    nonisolated private static func ocrLanguageHints(preferredLanguage: TextLanguage?) -> [String] {
        var identifiers: [String] = [
            "en-US",
            "fr-FR",
            "es-ES",
            "de-DE",
            "it-IT",
            "pt-PT",
            "nl-NL",
            "sv-SE",
            "tr-TR",
            "pl-PL",
            "ro-RO",
            "ru-RU",
            "uk-UA",
            "el-GR",
            "ar-SA",
            "he-IL",
            "fa-IR",
            "ur-PK",
            "hi-IN",
            "mr-IN",
            "bn-BD",
            "pa-IN",
            "ta-IN",
            "te-IN",
            "vi-VN",
            "th-TH",
            "id-ID",
            "ms-MY",
            "ko-KR",
            "ja-JP",
            "zh-Hans"
        ]

        if let preferredLanguage {
            let preferredIdentifier: String?
            switch preferredLanguage {
            case .english:
                preferredIdentifier = "en-US"
            case .french:
                preferredIdentifier = "fr-FR"
            case .spanish:
                preferredIdentifier = "es-ES"
            case .german:
                preferredIdentifier = "de-DE"
            case .mandarin:
                preferredIdentifier = "zh-Hans"
            case .italian:
                preferredIdentifier = "it-IT"
            case .portuguese:
                preferredIdentifier = "pt-PT"
            case .dutch:
                preferredIdentifier = "nl-NL"
            case .swedish:
                preferredIdentifier = "sv-SE"
            case .turkish:
                preferredIdentifier = "tr-TR"
            case .polish:
                preferredIdentifier = "pl-PL"
            case .romanian:
                preferredIdentifier = "ro-RO"
            case .russian:
                preferredIdentifier = "ru-RU"
            case .ukrainian:
                preferredIdentifier = "uk-UA"
            case .greek:
                preferredIdentifier = "el-GR"
            case .arabic:
                preferredIdentifier = "ar-SA"
            case .hebrew:
                preferredIdentifier = "he-IL"
            case .persian:
                preferredIdentifier = "fa-IR"
            case .urdu:
                preferredIdentifier = "ur-PK"
            case .japanese:
                preferredIdentifier = "ja-JP"
            case .hindi:
                preferredIdentifier = "hi-IN"
            case .marathi:
                preferredIdentifier = "mr-IN"
            case .bengali:
                preferredIdentifier = "bn-BD"
            case .punjabi:
                preferredIdentifier = "pa-IN"
            case .tamil:
                preferredIdentifier = "ta-IN"
            case .telugu:
                preferredIdentifier = "te-IN"
            case .vietnamese:
                preferredIdentifier = "vi-VN"
            case .thai:
                preferredIdentifier = "th-TH"
            case .indonesian:
                preferredIdentifier = "id-ID"
            case .malay:
                preferredIdentifier = "ms-MY"
            case .korean:
                preferredIdentifier = "ko-KR"
            case .unknown:
                preferredIdentifier = nil
            }

            if let preferredIdentifier {
                identifiers.removeAll(where: { $0 == preferredIdentifier })
                identifiers.insert(preferredIdentifier, at: 0)
            }
        }

        return identifiers
    }

    nonisolated private static func detectLanguageHint(from text: String?) -> TextLanguage? {
        guard let text else { return nil }
        let detected = TextNormalizationService.detectLanguage(for: text)
        return detected == .unknown ? nil : detected
    }

    nonisolated private static func isPageNumberLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: #"^\d+$"#, options: .regularExpression) != nil {
            return true
        }
        if trimmed.range(of: #"^page\s*\d+$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        return false
    }

    nonisolated private static func isLikelyBoilerplate(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 4 else { return false }
        return trimmed.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) || CharacterSet.punctuationCharacters.contains($0) }
    }
}

private enum EPUBTextExtractionService {
    nonisolated static func extractText(from url: URL) throws -> EPUBTextExtractionResult {
        let archive = try Archive(url: url, accessMode: .read)

        guard let containerData = try extractArchiveData(archive, entryPath: "META-INF/container.xml"),
              let opfPath = try opfPath(from: containerData),
              let opfData = try extractArchiveData(archive, entryPath: opfPath) else {
            throw DocumentIngestError.archiveAccessFailed
        }

        let document = try XMLDocument(data: opfData, options: [])
        let chapters = try chapterSections(from: document, archive: archive, opfPath: opfPath)

        let orderedSections = chapters.map(\.text).filter { !$0.isEmpty }
        let extracted = orderedSections.joined(separator: "\n\n[[EPUB_CHAPTER_BREAK]]\n\n")
        guard !extracted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DocumentIngestError.extractionFailed
        }

        let readingMetadata = ReadingMetadata(
            readingStructureKind: .chapter,
            pageCount: chapters.count,
            chapterCount: chapters.count,
            sectionCount: 0,
            readingJumpTargets: chapters.enumerated().map { index, chapter in
                ReaderJumpTarget(index: index, title: chapter.title)
            }
        )

        return EPUBTextExtractionResult(text: extracted, readingMetadata: readingMetadata)
    }

    nonisolated static func extractTitle(from url: URL) -> String? {
        do {
            let archive = try Archive(url: url, accessMode: .read)
            guard let containerData = try extractArchiveData(archive, entryPath: "META-INF/container.xml"),
                  let opfPath = try opfPath(from: containerData),
                  let opfData = try extractArchiveData(archive, entryPath: opfPath) else {
                return nil
            }

            guard let document = try? XMLDocument(data: opfData, options: []) else {
                return nil
            }

            let titleNodes = try? document.nodes(forXPath: "//*[local-name()='metadata']/*[local-name()='title']")
            if let value = titleNodes?.compactMap({ ($0 as? XMLElement)?.stringValue }).first?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }

            if let metaNodes = try? document.nodes(forXPath: "//*[local-name()='metadata']/*[local-name()='meta']") {
                for node in metaNodes {
                    guard let element = node as? XMLElement,
                          let name = element.attribute(forName: "name")?.stringValue?.lowercased(),
                          name == "title",
                          let content = element.attribute(forName: "content")?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !content.isEmpty else { continue }
                    return content
                }
            }

            return nil
        } catch {
            return nil
        }
    }

    nonisolated private static func opfPath(from containerData: Data) throws -> String? {
        let document = try XMLDocument(data: containerData, options: [])
        guard
            let rootfile = try document.nodes(forXPath: "//container/rootfiles/rootfile").first as? XMLElement,
            let fullPath = rootfile.attribute(forName: "full-path")?.stringValue
        else {
            return nil
        }

        return fullPath
    }

    nonisolated private static func chapterSections(
        from document: XMLDocument,
        archive: Archive,
        opfPath: String
    ) throws -> [EPUBChapterSection] {
        let basePath = (opfPath as NSString).deletingLastPathComponent
        let manifestItems = try manifestItems(from: document)
        let spineItemIDs = try document.nodes(forXPath: "//*[local-name()='spine']/*[local-name()='itemref']")
            .compactMap { node -> String? in
                guard let element = node as? XMLElement else { return nil }
                return element.attribute(forName: "idref")?.stringValue
            }

        let navigationTitles = try navigationTitles(from: document, archive: archive, manifestItems: manifestItems, basePath: basePath)
        var sections: [EPUBChapterSection] = []

        for id in spineItemIDs {
            guard let item = manifestItems[id] else { continue }
            guard item.href.hasSuffix(".xhtml") || item.href.hasSuffix(".html") || item.href.hasSuffix(".htm") else { continue }

            let entryPath = normalizedArchivePath(basePath: basePath, href: item.href)
            guard let htmlData = try extractArchiveData(archive, entryPath: entryPath),
                  let plainText = htmlToPlainText(htmlData) else {
                continue
            }

            let cleanedText = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedText.isEmpty else { continue }

            let title = navigationTitles[normalizedNavigationKey(item.href)]
                ?? bestTitleCandidate(from: cleanedText)
                ?? fallbackTitle(for: item)
            sections.append(EPUBChapterSection(title: title, text: cleanedText))
        }

        if sections.isEmpty {
            let fallbackItems = manifestItems.values
                .filter { $0.href.hasSuffix(".xhtml") || $0.href.hasSuffix(".html") || $0.href.hasSuffix(".htm") }
                .sorted { $0.href < $1.href }

            for item in fallbackItems {
                let entryPath = normalizedArchivePath(basePath: basePath, href: item.href)
                guard let htmlData = try extractArchiveData(archive, entryPath: entryPath),
                      let plainText = htmlToPlainText(htmlData) else {
                    continue
                }

                let cleanedText = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleanedText.isEmpty else { continue }

                let title = bestTitleCandidate(from: cleanedText) ?? fallbackTitle(for: item)
                sections.append(EPUBChapterSection(title: title, text: cleanedText))
            }
        }

        return sections
    }

    nonisolated private static func manifestItems(from document: XMLDocument) throws -> [String: EPUBManifestItem] {
        let manifestNodes = try document.nodes(forXPath: "//*[local-name()='manifest']/*[local-name()='item']")
        var manifest: [String: EPUBManifestItem] = [:]

        for node in manifestNodes {
            guard let element = node as? XMLElement,
                  let id = element.attribute(forName: "id")?.stringValue,
                  let href = element.attribute(forName: "href")?.stringValue else {
                continue
            }

            let properties = element.attribute(forName: "properties")?.stringValue ?? ""
            let mediaType = element.attribute(forName: "media-type")?.stringValue ?? ""
            manifest[id] = EPUBManifestItem(
                id: id,
                href: href,
                properties: properties,
                mediaType: mediaType
            )
        }

        return manifest
    }

    nonisolated private static func navigationTitles(
        from document: XMLDocument,
        archive: Archive,
        manifestItems: [String: EPUBManifestItem],
        basePath: String
    ) throws -> [String: String] {
        var titles: [String: String] = [:]

        if let navItem = manifestItems.values.first(where: { $0.properties.lowercased().contains("nav") }) {
            let navPath = normalizedArchivePath(basePath: basePath, href: navItem.href)
            if let navData = try extractArchiveData(archive, entryPath: navPath),
               let navDocument = try? XMLDocument(data: navData, options: []) {
                let navNodes = try navDocument.nodes(forXPath: "//*[local-name()='nav']//*[local-name()='a']")
                for node in navNodes {
                    guard let element = node as? XMLElement,
                          let href = element.attribute(forName: "href")?.stringValue else {
                        continue
                    }

                    let title = element.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let title, !title.isEmpty else { continue }
                    titles[normalizedNavigationKey(href)] = title
                }
            }
        }

        guard titles.isEmpty else {
            return titles
        }

        guard let ncxItem = manifestItems.values.first(where: { item in
            item.mediaType.lowercased().contains("ncx") || item.href.lowercased().hasSuffix(".ncx")
        }) else {
            return titles
        }

        let ncxPath = normalizedArchivePath(basePath: basePath, href: ncxItem.href)
        guard let ncxData = try extractArchiveData(archive, entryPath: ncxPath),
              let ncxDocument = try? XMLDocument(data: ncxData, options: []) else {
            return titles
        }

        let navPoints = try ncxDocument.nodes(forXPath: "//*[local-name()='navMap']//*[local-name()='navPoint']")
        for node in navPoints {
            guard let navPoint = node as? XMLElement else { continue }

            let titleNode = navPoint.elements(forName: "navLabel").first?.elements(forName: "text").first
            let title = titleNode?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let title, !title.isEmpty else { continue }

            guard
                let contentElement = navPoint.elements(forName: "content").first,
                let src = contentElement.attribute(forName: "src")?.stringValue
            else {
                continue
            }

            titles[normalizedNavigationKey(src)] = title
        }

        return titles
    }

    nonisolated private static func normalizedNavigationKey(_ href: String) -> String {
        let fragmentless = href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? href
        return fragmentless.removingPercentEncoding ?? fragmentless
    }

    nonisolated private static func normalizedArchivePath(basePath: String, href: String) -> String {
        let combined = (basePath as NSString).appendingPathComponent(href)
        return combined.removingPercentEncoding ?? combined
    }

    nonisolated private static func fallbackTitle(for item: EPUBManifestItem) -> String {
        let fileName = (item.href as NSString).lastPathComponent
        let title = (fileName as NSString).deletingPathExtension
        return title.isEmpty ? item.id : title
    }

    nonisolated private static func extractArchiveData(_ archive: Archive, entryPath: String) throws -> Data? {
        guard let entry = archive[entryPath] else { return nil }

        var extractedData = Data()
        _ = try archive.extract(entry) { chunk in
            extractedData.append(chunk)
        }

        return extractedData.isEmpty ? nil : extractedData
    }

    nonisolated private static func htmlToPlainText(_ data: Data) -> String? {
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]

        guard let attributedString = try? NSAttributedString(data: data, options: options, documentAttributes: nil) else {
            return String(data: data, encoding: .utf8)
        }

        return attributedString.string
    }
}

private struct EPUBTextExtractionResult {
    let text: String
    let readingMetadata: ReadingMetadata
}

private struct EPUBChapterSection {
    let title: String
    let text: String
}

private struct EPUBManifestItem {
    let id: String
    let href: String
    let properties: String
    let mediaType: String
}

private enum TXTReadingMetadataService {
    nonisolated static func readingMetadata(from text: String) -> ReadingMetadata {
        let sections = splitIntoSections(from: text)
        return ReadingMetadata(
            readingStructureKind: sections.isEmpty ? nil : .section,
            pageCount: 0,
            chapterCount: 0,
            sectionCount: sections.count,
            readingJumpTargets: sections.enumerated().map { index, section in
                ReaderJumpTarget(index: index, title: section.title)
            }
        )
    }

    nonisolated static func sectionedText(from text: String) -> String {
        if text.contains("[[TXT_SECTION_BREAK]]") {
            return text
        }

        let sections = splitIntoSections(from: text)
        return sections.map(\.text).joined(separator: "\n\n[[TXT_SECTION_BREAK]]\n\n")
    }

    nonisolated private static func splitIntoSections(from text: String) -> [TXTSection] {
        let cleaned = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return [] }

        if cleaned.contains("[[TXT_SECTION_BREAK]]") {
            return cleaned
                .components(separatedBy: "[[TXT_SECTION_BREAK]]")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { TXTSection(text: $0, title: "") }
        }

        let paragraphs = cleaned.components(separatedBy: "\n\n")
        var sections: [TXTSection] = []
        var buffer: [String] = []
        var sectionTitle: String?

        func flushBuffer() {
            let sectionText = buffer
                .joined(separator: "\n\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sectionText.isEmpty else {
                buffer.removeAll(keepingCapacity: true)
                sectionTitle = nil
                return
            }

            let splitChunks = splitOversizedSection(sectionText)
            if splitChunks.count == 1 {
                sections.append(TXTSection(text: sectionText, title: sectionTitle ?? ""))
            } else {
                for (index, chunk) in splitChunks.enumerated() {
                    sections.append(TXTSection(text: chunk, title: index == 0 ? (sectionTitle ?? "") : ""))
                }
            }

            buffer.removeAll(keepingCapacity: true)
            sectionTitle = nil
        }

        for paragraph in paragraphs {
            let paragraphText = paragraph
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !paragraphText.isEmpty else { continue }

            if isHeadingLike(paragraphText), !buffer.isEmpty {
                flushBuffer()
            }

            if buffer.isEmpty {
                sectionTitle = isHeadingLike(paragraphText) ? cleanedHeadingTitle(from: paragraphText) : nil
                buffer.append(paragraphText)
                continue
            }

            let candidateLength = buffer.joined(separator: "\n\n").count + 2 + paragraphText.count
            if candidateLength <= 2_400 {
                buffer.append(paragraphText)
            } else {
                flushBuffer()
                sectionTitle = isHeadingLike(paragraphText) ? cleanedHeadingTitle(from: paragraphText) : nil
                buffer.append(paragraphText)
            }
        }

        flushBuffer()
        return sections
    }

    nonisolated private static func splitOversizedSection(_ text: String) -> [String] {
        guard text.count > 2_400 else { return [text] }

        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return [text] }

        var sections: [String] = []
        var buffer = ""

        for word in words {
            if buffer.isEmpty {
                buffer = word
                continue
            }

            if buffer.count + 1 + word.count <= 2_400 {
                buffer += " "
                buffer += word
            } else {
                sections.append(buffer)
                buffer = word
            }
        }

        if !buffer.isEmpty {
            sections.append(buffer)
        }

        return sections.isEmpty ? [text] : sections
    }

    nonisolated private static func isHeadingLike(_ paragraph: String) -> Bool {
        let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 120 else { return false }

        let wordCount = trimmed.split(whereSeparator: { $0.isWhitespace }).count
        if wordCount == 0 || wordCount > 12 {
            return false
        }

        let lowercased = trimmed.lowercased()
        if lowercased.range(of: #"^(chapter|part|book|section)\s+\d+"#, options: .regularExpression) != nil {
            return true
        }

        if trimmed == trimmed.uppercased() {
            return true
        }

        let hasSentencePunctuation = trimmed.contains(".") || trimmed.contains("!") || trimmed.contains("?")
        return !hasSentencePunctuation && wordCount <= 8
    }

    nonisolated private static func cleanedHeadingTitle(from paragraph: String) -> String {
        paragraph
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct TXTSection {
        let text: String
        let title: String
    }
}
