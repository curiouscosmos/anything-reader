//
//  KokoroModelStore.swift
//  Anything Reader
//
//  Tracks the available Kokoro model downloads and installs them locally so
//  the reader can enforce an initial model download before TTS playback.
//

import Combine
import Foundation

struct KokoroDownloadOption: Identifiable, Hashable, Equatable {
    let localFileName: String
    let displayName: String
    let qualityLabel: String
    let downloadURL: URL
    let isRecommended: Bool
    let isRuntimeCompatible: Bool
    let qualityRank: Int

    var id: String { localFileName }

    var subtitle: String {
        isRecommended ? "\(qualityLabel) · Recommended" : qualityLabel
    }
}

enum KokoroDownloadCatalog {
    static let allOptions: [KokoroDownloadOption] = [
        .init(
            localFileName: "kokoro_q8f16.safetensors",
            displayName: "Q8 F16",
            qualityLabel: "Highest quality",
            downloadURL: URL(string: "https://huggingface.co/mlx-community/Kokoro-82M-bf16/resolve/main/kokoro-v1_0.safetensors?download=true")!,
            isRecommended: true,
            isRuntimeCompatible: true,
            qualityRank: 0
        ),
        .init(
            localFileName: "kokoro_fp16.safetensors",
            displayName: "FP16",
            qualityLabel: "Better quality",
            downloadURL: URL(string: "https://huggingface.co/mlx-community/Kokoro-82M-8bit/resolve/main/kokoro-v1_0.safetensors?download=true")!,
            isRecommended: false,
            isRuntimeCompatible: false,
            qualityRank: 1
        ),
        .init(
            localFileName: "kokoro_quantized.safetensors",
            displayName: "Quantized",
            qualityLabel: "Smaller, faster CPU",
            downloadURL: URL(string: "https://huggingface.co/mlx-community/Kokoro-82M-6bit/resolve/main/kokoro-v1_0.safetensors?download=true")!,
            isRecommended: false,
            isRuntimeCompatible: false,
            qualityRank: 2
        ),
        .init(
            localFileName: "kokoro_q4f16.safetensors",
            displayName: "Q4 F16",
            qualityLabel: "Smallest, experimental",
            downloadURL: URL(string: "https://huggingface.co/mlx-community/Kokoro-82M-4bit/resolve/main/kokoro-v1_0.safetensors?download=true")!,
            isRecommended: false,
            isRuntimeCompatible: false,
            qualityRank: 3
        )
    ]

    static let defaultOption = allOptions.first!
}

@MainActor
final class KokoroModelStore: ObservableObject {
    enum Status: Equatable {
        case checking
        case notInstalled
        case downloading(KokoroDownloadOption)
        case installed(KokoroDownloadOption)
        case failed(String)
    }

    static let shared = KokoroModelStore()

    @Published private(set) var status: Status = .checking

    private let selectedModelStorageKey = "kokoroSelectedModelFileName"
    private var downloadTask: Task<Void, Never>?

    private init() {
        refreshInstallationStatus()
    }

    var isInstalled: Bool {
        if case .installed = status {
            return true
        }
        return false
    }

    var installedOptions: [KokoroDownloadOption] {
        KokoroDownloadCatalog.allOptions.filter { isOptionDownloaded($0) }
    }

    var selectedOption: KokoroDownloadOption? {
        if let storedName = UserDefaults.standard.string(forKey: selectedModelStorageKey) {
            return KokoroDownloadCatalog.allOptions.first(where: { $0.localFileName == storedName }) ?? installedOptions.first
        }

        switch status {
        case .installed(let option), .downloading(let option):
            return option
        default:
            return installedOptions.first
        }
    }

    func refreshInstallationStatus() {
        purgeInvalidRuntimeCompatibleModels()

        if let active = selectedOption, isOptionDownloaded(active) {
            storeSelectedOption(active)
            status = .installed(active)
            return
        }

        if let firstInstalled = installedOptions.first {
            storeSelectedOption(firstInstalled)
            status = .installed(firstInstalled)
        } else {
            status = .notInstalled
        }
    }

    func activateDownloadedModel(_ option: KokoroDownloadOption) {
        guard isOptionDownloaded(option) else { return }
        storeSelectedOption(option)
        status = .installed(option)
    }

    func deactivateDownloadedModel(_ option: KokoroDownloadOption) {
        guard selectedOption?.localFileName == option.localFileName else { return }

        let remainingOptions = installedOptions.filter { $0.localFileName != option.localFileName }
        if let nextOption = remainingOptions.first {
            storeSelectedOption(nextOption)
            status = .installed(nextOption)
        } else {
            UserDefaults.standard.removeObject(forKey: selectedModelStorageKey)
            status = .notInstalled
        }
    }

    func deleteDownloadedModel(_ option: KokoroDownloadOption) {
        let fileURL = localModelURL(for: option)
        guard fileManager().fileExists(atPath: fileURL.path) else { return }

        try? fileManager().removeItem(at: fileURL)

        if selectedOption?.localFileName == option.localFileName {
            UserDefaults.standard.removeObject(forKey: selectedModelStorageKey)

            if let fallback = installedOptions.first {
                storeSelectedOption(fallback)
                status = .installed(fallback)
            } else {
                status = installedOptions.isEmpty ? .notInstalled : .failed("No runtime-compatible Kokoro model is installed. Download the recommended model to continue.")
            }
        } else {
            refreshInstallationStatus()
        }
    }

    func downloadModel(option: KokoroDownloadOption) {
        guard downloadTask == nil else { return }

        if isOptionDownloaded(option) {
            activateDownloadedModel(option)
            return
        }

        status = .downloading(option)

        downloadTask = Task {
            defer {
                Task { @MainActor in
                    self.downloadTask = nil
                }
            }

            do {
                try await downloadAndInstallModel(option: option)
                await MainActor.run {
                    self.storeSelectedOption(option)
                    self.status = .installed(option)
                }
            } catch {
                await MainActor.run {
                    self.status = .failed(error.localizedDescription)
                }
            }
        }
    }

    func modelURL() -> URL? {
        if let selected = selectedOption, isOptionDownloaded(selected) {
            return localModelURL(for: selected)
        }

        return nil
    }

    func isOptionDownloaded(_ option: KokoroDownloadOption) -> Bool {
        fileManager().fileExists(atPath: localModelURL(for: option).path)
    }

    private func downloadAndInstallModel(option: KokoroDownloadOption) async throws {
        let (temporaryURL, response) = try await URLSession.shared.download(from: option.downloadURL)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw CocoaError(.fileReadUnknown)
        }

        let destination = localModelURL(for: option)
        try fileManager().createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager().fileExists(atPath: destination.path) {
            try fileManager().removeItem(at: destination)
        }

        try fileManager().moveItem(at: temporaryURL, to: destination)
    }

    private func localModelURL(for option: KokoroDownloadOption) -> URL {
        modelDirectory().appendingPathComponent(option.localFileName)
    }

    private func modelDirectory() -> URL {
        let supportDirectory = fileManager().urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        return supportDirectory
            .appendingPathComponent("Anything Reader", isDirectory: true)
            .appendingPathComponent("KokoroModel", isDirectory: true)
    }

    private func storeSelectedOption(_ option: KokoroDownloadOption) {
        UserDefaults.standard.set(option.localFileName, forKey: selectedModelStorageKey)
    }

    private func purgeInvalidRuntimeCompatibleModels() {
        // No-op for now; Kokoro model selection is handled by the active row toggle.
    }

    private func isRuntimeCompatibleModel(at url: URL) -> Bool {
        guard fileManager().fileExists(atPath: url.path) else { return false }
        guard let header = Self.parseSafetensorsHeader(at: url) else { return false }

        let requiredKeys: [String] = [
            "bert.embeddings.word_embeddings.weight",
            "bert.embeddings.position_embeddings.weight",
            "bert.embeddings.token_type_embeddings.weight",
            "bert.embeddings.LayerNorm.weight",
            "bert.embeddings.LayerNorm.bias",
            "bert_encoder.weight",
            "bert_encoder.bias",
            "predictor.lstm.weight_ih_l0",
            "predictor.lstm.weight_hh_l0",
            "predictor.lstm.bias_ih_l0",
            "predictor.lstm.bias_hh_l0",
            "predictor.lstm.weight_ih_l0_reverse",
            "predictor.lstm.weight_hh_l0_reverse",
            "predictor.lstm.bias_ih_l0_reverse",
            "predictor.lstm.bias_hh_l0_reverse",
            "predictor.duration_proj.linear_layer.weight",
            "predictor.duration_proj.linear_layer.bias",
            "predictor.F0_proj.weight",
            "predictor.F0_proj.bias",
            "predictor.N_proj.weight",
            "predictor.N_proj.bias",
            "decoder.generator.ups.0.weight_g",
            "decoder.generator.ups.0.weight_v",
            "decoder.generator.conv_post.weight_g",
            "decoder.generator.conv_post.weight_v",
            "decoder.F0_conv.weight_g",
            "decoder.F0_conv.weight_v",
            "decoder.N_conv.weight_g",
            "decoder.N_conv.weight_v"
        ]

        let durationEncoderBlockCount = 6
        let durationEncoderKeys = (0..<durationEncoderBlockCount).flatMap { index in
            if index.isMultiple(of: 2) {
                return [
                    "predictor.text_encoder.lstms.\(index).weight_ih_l0",
                    "predictor.text_encoder.lstms.\(index).weight_hh_l0",
                    "predictor.text_encoder.lstms.\(index).bias_ih_l0",
                    "predictor.text_encoder.lstms.\(index).bias_hh_l0",
                    "predictor.text_encoder.lstms.\(index).weight_ih_l0_reverse",
                    "predictor.text_encoder.lstms.\(index).weight_hh_l0_reverse",
                    "predictor.text_encoder.lstms.\(index).bias_ih_l0_reverse",
                    "predictor.text_encoder.lstms.\(index).bias_hh_l0_reverse"
                ]
            } else {
                return [
                    "predictor.text_encoder.lstms.\(index).fc.weight",
                    "predictor.text_encoder.lstms.\(index).fc.bias"
                ]
            }
        }

        return (requiredKeys + durationEncoderKeys).allSatisfy { header.keys.contains($0) }
    }

    private static func parseSafetensorsHeader(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url), data.count >= 8 else { return nil }

        let headerLength = data.prefix(8).enumerated().reduce(UInt64(0)) { partialResult, element in
            partialResult | (UInt64(element.element) << (UInt64(element.offset) * 8))
        }.clampedInt
        guard headerLength > 0, data.count >= 8 + headerLength else { return nil }

        let headerData = data.subdata(in: 8..<(8 + headerLength))
        guard var headerString = String(data: headerData, encoding: .utf8) else { return nil }
        headerString = headerString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = headerString.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: jsonData),
              let dictionary = object as? [String: Any] else {
            return nil
        }

        return dictionary
    }

    private func fileManager() -> FileManager {
        .default
    }
}

private extension FixedWidthInteger {
    var clampedInt: Int {
        Int(exactly: self) ?? Int.max
    }
}
