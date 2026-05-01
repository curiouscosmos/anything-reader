//
//  Anything_ReaderTests.swift
//  Anything ReaderTests
//

import AppKit
import AVFoundation
import Foundation
import Testing
@testable import Anything_Reader

struct Anything_ReaderTests {

    @Test func readerEnumsExposeExpectedPresentationValues() {
        #expect(ReaderSourceKind.image.displayName == "Image")
        #expect(ReaderSourceKind.image.systemImage == "doc.text.image")
        #expect(PDFExtractionMode.ocr.displayName == "OCR")
        #expect(TextLanguage.english.displayName == "English")
        #expect(TextLanguage.mandarin.displayName == "Mandarin")
        #expect(TextLanguage.init(naturalLanguageIdentifier: "zh-Hant") == .mandarin)
        #expect(TextLanguage.init(naturalLanguageIdentifier: "und") == .unknown)
    }

    @Test func libraryEntryDerivedValuesRoundTripJumpTargets() {
        let entry = LibraryEntry(
            title: "Chaptered Book",
            subtitle: "",
            sourceKind: .image,
            fileExtension: "png",
            originalFileName: "scan.png",
            storedFilePath: "/tmp/scan.png",
            normalizedTextFilePath: "/tmp/scan.txt",
            coverImageFilePath: "/tmp/scan.png",
            fileSizeBytes: 1_024,
            avatarSymbolName: "doc.text.image",
            accentName: "emerald",
            textLanguage: .english,
            pdfExtractionMode: .ocr,
            readingStructureKind: .chapter,
            pageCount: 0,
            chapterCount: 3,
            sectionCount: 0,
            readingJumpTargets: [
                ReaderJumpTarget(index: 0, title: "Intro"),
                ReaderJumpTarget(index: 1, title: "Middle"),
                ReaderJumpTarget(index: 2, title: "End")
            ],
            currentReadingPositionIndex: 1,
            currentReadingPositionTotalCount: 3,
            progress: 0.5,
            lastOpened: .now,
            createdAt: .now
        )

        #expect(entry.sourceKind == .image)
        #expect(entry.pdfExtractionMode == .ocr)
        #expect(entry.currentReadingProgressFraction == 2.0 / 3.0)
        #expect(entry.currentReadingPositionDisplayText == "Chapter 2/3 · Middle")
        #expect(entry.readingJumpTargets.count == 3)
        #expect(entry.readingJumpTargets[1].title == "Middle")
    }

    @Test func textNormalizationCollapsesWhitespaceAndPunctuation() {
        let normalized = TextNormalizationService.normalize(
            "Hello  ,  world\n\n“Quoted” — text…",
            language: .english
        )

        #expect(normalized == "Hello, world\n\n\"Quoted\" - text...")
    }

    @Test func detectLanguageRecognizesCommonScripts() {
        #expect(TextNormalizationService.detectLanguage(for: "こんにちは世界") == .japanese)
        #expect(TextNormalizationService.detectLanguage(for: "你好，世界") == .mandarin)
        #expect(TextNormalizationService.detectLanguage(for: "Hello, world.") == .english)
    }

    @Test func playbackChunkServiceTreatsImageEntriesLikeText() throws {
        let directory = try makeTemporaryDirectory(prefix: "chunks")
        defer { try? FileManager.default.removeItem(at: directory) }

        let normalizedFileURL = directory.appendingPathComponent("book.txt")
        try "One\n\n[[TXT_SECTION_BREAK]]\n\nTwo\n\n[[TXT_SECTION_BREAK]]\n\nThree".write(
            to: normalizedFileURL,
            atomically: true,
            encoding: .utf8
        )

        let entry = LibraryEntry(
            title: "OCR Book",
            subtitle: "",
            sourceKind: .image,
            fileExtension: "png",
            storedFilePath: directory.appendingPathComponent("book.png").path,
            normalizedTextFilePath: normalizedFileURL.path,
            fileSizeBytes: 123,
            avatarSymbolName: "doc.text.image",
            accentName: "teal",
            textLanguage: .english,
            pdfExtractionMode: .ocr,
            readingStructureKind: .section,
            pageCount: 0,
            chapterCount: 0,
            sectionCount: 3,
            readingJumpTargets: [
                ReaderJumpTarget(index: 0, title: "First"),
                ReaderJumpTarget(index: 1, title: "Second"),
                ReaderJumpTarget(index: 2, title: "Third")
            ]
        )

        let chunks = ReaderPlaybackChunkService.chunks(for: entry)
        #expect(chunks == ["One", "Two", "Three"])
        #expect(ReaderPlaybackChunkService.pageChunks(for: entry) == ["One", "Two", "Three"])
        #expect(ReaderPlaybackChunkService.chunkIndex(for: 1, in: entry) == 1)
        #expect(ReaderPlaybackChunkService.readingTargetIndex(forChunkIndex: 1, in: entry) == 1)
    }

    @Test func playbackChunkMathStaysCentered() {
        let chunkCount = 8
        let index = ReaderPlaybackChunkService.chunkIndex(for: 0.5, chunkCount: chunkCount)
        #expect(index == 4)
        #expect(ReaderPlaybackChunkService.progress(for: index, chunkCount: chunkCount) > 0.5)
        #expect(ReaderPlaybackChunkService.progress(for: index, chunkCount: chunkCount) < 0.7)
    }

    @Test func documentIngestServiceWritesNormalizedTextNextToSourceFile() async throws {
        let directory = try makeTemporaryDirectory(prefix: "ingest-text")
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("notes.txt")
        try "Hello   world\nLine 2".write(
            to: sourceURL,
            atomically: true,
            encoding: .utf8
        )

        let result = try await DocumentIngestService.shared.process(
            stagedFileURL: sourceURL,
            fileExtension: "txt",
            originalFileName: "notes.txt",
            documentLanguage: .english
        )
        let expectedNormalizedText = TextNormalizationService.normalize(
            "Hello   world Line 2",
            language: .english
        )

        #expect(result.sourceKind == .text)
        #expect(result.pdfExtractionMode == nil)
        #expect(result.normalizedText == expectedNormalizedText)
        #expect(result.normalizedTextFileURL.deletingLastPathComponent().path == directory.path)

        let storedText = try await String(contentsOf: result.normalizedTextFileURL, encoding: .utf8)
        #expect(storedText == expectedNormalizedText)
        #expect(result.normalizedTextFileURL.lastPathComponent == "notes.txt.txt")
    }

    @Test func coverArtGenerationWritesIntoTheSameUploadFolder() async throws {
        let directory = try makeTemporaryDirectory(prefix: "cover-art")
        defer { try? FileManager.default.removeItem(at: directory) }

        let pdfURL = try writeSimplePDF(to: directory.appendingPathComponent("sample.pdf"))
        let generatedURL = await CoverArtService.shared.generateCoverImageURL(
            sourceURL: pdfURL,
            fileExtension: "pdf",
            originalFileName: "sample.pdf"
        )

        #expect(generatedURL != nil)

        guard let generatedURL else { return }

        #expect(generatedURL.deletingLastPathComponent() == directory)
        #expect(FileManager.default.fileExists(atPath: generatedURL.path))
        let data = try Data(contentsOf: generatedURL)
        #expect(data.count > 8)
        #expect(Array(data.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
    }

    @Test @MainActor func generatedAudioPlaybackCanPlayAndPause() throws {
        let directory = try makeTemporaryDirectory(prefix: "audio")
        defer { try? FileManager.default.removeItem(at: directory) }

        let audioURL = try writeSilentWav(
            to: directory.appendingPathComponent("silence.wav"),
            durationSeconds: 2
        )

        let service = GeneratedAudioPlaybackService.shared
        service.stop()

        var finished = false
        var failures: [String] = []

        service.play(
            fileURL: audioURL,
            title: "Silence",
            onProgress: { _, _ in },
            onFinished: {
                finished = true
            },
            onFailure: { message in
                failures.append(message)
            }
        )

        #expect(failures.isEmpty)
        #expect(service.isPlaying)
        #expect(service.currentTitle == "Silence")
        #expect(service.currentDurationSeconds >= 1)

        service.togglePlayback()
        #expect(service.isPlaying == false)
        #expect(service.hasLoadedAudio(for: audioURL))

        service.stop()
        #expect(service.isPlaying == false)
        #expect(service.hasLoadedAudio == false)
        #expect(finished == false)
    }

    @Test func kokoroVoiceCatalogProvidesStableLookups() {
        let voice = KokoroVoiceCatalog.voice(named: "af_bella")
        #expect(voice.voiceName == "af_bella")
        #expect(voice.displayName == "Bella")
        #expect(voice.dropdownLabel.contains("Bella"))
        #expect(KokoroVoiceCatalog.voice(named: "missing").voiceName == KokoroVoiceCatalog.allVoices[0].voiceName)
    }
}

private func makeTemporaryDirectory(prefix: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func writeSimplePDF(to url: URL) throws -> URL {
    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }

    context.beginPDFPage(nil)
    context.setFillColor(NSColor.white.cgColor)
    context.fill(mediaBox)
    context.setFillColor(NSColor.black.cgColor)
    context.fill(CGRect(x: 72, y: 600, width: 180, height: 80))
    context.endPDFPage()
    context.closePDF()
    return url
}

private func writeSilentWav(to url: URL, durationSeconds: Double) throws -> URL {
    let sampleRate: Double = 24_000
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let frameCount = AVAudioFrameCount(sampleRate * durationSeconds)

    let file = try AVAudioFile(
        forWriting: url,
        settings: format.settings,
        commonFormat: .pcmFormatFloat32,
        interleaved: false
    )

    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
        throw CocoaError(.fileWriteUnknown)
    }

    buffer.frameLength = frameCount
    if let channelData = buffer.floatChannelData?[0] {
        channelData.initialize(repeating: 0, count: Int(frameCount))
    }

    try file.write(from: buffer)
    return url
}
