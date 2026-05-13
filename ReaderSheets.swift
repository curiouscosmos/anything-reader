//
//  ReaderSheets.swift
//  Anything Reader
//
//  Shared modal sheets used by the reader shell.
//

import SwiftUI

// Settings sheet for theme and Kokoro voice controls.
struct ReaderSettingsSheet: View {
    @Binding var appearanceModeRawValue: String
    @Binding var selectedVoiceName: String
    let voiceOptions: [KokoroVoiceOption]
    let isPlaying: Bool
    let onPlaySample: (KokoroVoiceOption) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Light mode not fully ready yet
//                        settingSection(title: "Appearance") {
//                            Picker("Theme", selection: $appearanceModeRawValue) {
//                                ForEach(AppearanceMode.allCases) { mode in
//                                    Text(mode.title).tag(mode.rawValue)
//                                }
//                            }
//                        }

                        settingSection(title: "Kokoro Voice") {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(alignment: .center, spacing: 12) {
                                    Picker("Default Voice", selection: $selectedVoiceName) {
                                        ForEach(voiceOptions, id: \KokoroVoiceOption.voiceName) { voice in
                                            Text("\(voice.genderSymbol) \(voice.dropdownLabel)")
                                                .tag(voice.voiceName)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .readerPointerCursor()

                                    Button {
                                        onPlaySample(currentVoice)
                                    } label: {
                                        Label(isPlaying ? "Playing..." : "Play", systemImage: "play.circle.fill")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .readerPointerCursor()
                                    .disabled(isPlaying)
                                }

                                Text("Kokoro voice selection is local and will use the offline runtime when the model directory is available.")
                                    .foregroundStyle(.secondary)

                                Text(currentVoice.sampleText)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }

                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                footerButtons
            }
            .accessibilityIdentifier("settings-sheet")
            .navigationTitle("Settings")
        }
    }

    @Environment(\.dismiss) private var dismiss

    private var currentVoice: KokoroVoiceOption {
        voiceOptions.first(where: { $0.voiceName == selectedVoiceName }) ?? voiceOptions[0]
    }

    private var footerButtons: some View {
        HStack {
            Spacer()
            Button("Done") { dismiss() }
                .accessibilityIdentifier("settings-sheet-done-button")
                .readerPointerCursor()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.thinMaterial)
    }

    @ViewBuilder
    private func settingSection<Content: View>(
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

// Import language sheet shown before the file is normalized.
struct ReaderImportLanguageSheet: View {
    @Binding var documentLanguage: TextLanguage
    @Binding var isTranslateDocument: Bool
    @Binding var translateToLanguage: TextLanguage

    let detectedLanguage: TextLanguage?
    let onImport: () -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection

                        formSection(title: "Document Language") {
                            Picker("Document Language", selection: $documentLanguage) {
                                ForEach(languageOptions) { language in
                                    Text(language.displayName)
                                        .tag(language)
                                }
                            }
                            .pickerStyle(.menu)
                            .readerPointerCursor()

                            if let detectedLanguage {
                                Text("Auto-detected as \(detectedLanguage.displayName). You can change this before import for better OCR text extraction.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Anything Reader will use this language for normalization and OCR.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        formSection(title: "Translation") {
                            Toggle("Translate document", isOn: $isTranslateDocument)
                                .readerPointerCursor()

                            if isTranslateDocument {
                                Picker("Translate to Language", selection: $translateToLanguage) {
                                    ForEach(languageOptions) { language in
                                        Text(language.displayName)
                                            .tag(language)
                                    }
                                }
                                .pickerStyle(.menu)
                                .readerPointerCursor()
                            } else {
                                Text("Document will be translated to your selected language.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                footerButtons
            }
            .accessibilityIdentifier("import-language-sheet")
            .navigationTitle("Import Options")
        }
        .interactiveDismissDisabled(true)
    }

    private var languageOptions: [TextLanguage] {
        TextLanguage.allCases
    }

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose import options")
                .font(.title2.weight(.bold))

            Text("Select the document language before normalization starts. The same language is used for OCR if the file needs text extraction from images.")
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

    private var footerButtons: some View {
        HStack {
            Button("Cancel") {
                onCancel()
                dismiss()
            }
            .accessibilityIdentifier("import-language-sheet-cancel-button")
            .readerPointerCursor()

            Spacer()

            Button("Import") {
                onImport()
                dismiss()
            }
            .accessibilityIdentifier("import-language-sheet-import-button")
            .readerPointerCursor()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.thinMaterial)
    }
}

// Audio export sheet shown before the full normalized file is rendered to a local audio file.
struct ReaderGenerateAudioSheet: View {
    @Binding var voiceName: String

    let voiceOptions: [ReaderTTSVoiceSelection]
    let onGenerate: () -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection

                        formSection(title: "Voice") {
                            Picker("Default Voice", selection: $voiceName) {
                                ForEach(voiceOptions, id: \.voiceName) { voice in
                                    Text("\(voice.genderSymbol) \(voice.dropdownLabel)")
                                        .tag(voice.voiceName)
                                }
                            }
                            .pickerStyle(.menu)
                            .readerPointerCursor()

                            Text("The selected voice will be used to synthesize the complete normalized document into a local audio export.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                footerButtons
            }
            .accessibilityIdentifier("generate-audio-sheet")
            .navigationTitle("Generate Audio file")
        }
        .interactiveDismissDisabled(true)
    }

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Export the whole file")
                .font(.title2.weight(.bold))

            Text("Anything Reader will synthesize the complete normalized document in the background and save the audio locally for later use.")
                .foregroundStyle(.secondary)
            
            Text("Note: Depending on your system, this can take several miutes or hours.")
                .font(.body.weight(.bold))
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

    private var footerButtons: some View {
        HStack {
            Button("Cancel") {
                onCancel()
                dismiss()
            }
            .accessibilityIdentifier("generate-audio-sheet-cancel-button")
            .readerPointerCursor()

            Spacer()

            Button("Generate Audio file") {
                onGenerate()
                dismiss()
            }
            .accessibilityIdentifier("generate-audio-sheet-generate-button")
            .readerPointerCursor()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.thinMaterial)
    }
}

// Small success modal shown after a file summary is generated and saved locally.
struct ReaderSummarySuccessSheet: View {
    let title: String
    let onPlay: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.green)

            VStack(spacing: 6) {
                Text("Summary complete")
                    .font(.title3.weight(.bold))

                Text("The summary for \(title) was saved locally.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                Button("Done", action: onDone)
                    .buttonStyle(.bordered)
                    .readerPointerCursor()

                Button("Play Summary", action: onPlay)
                    .buttonStyle(.borderedProminent)
                    .readerPointerCursor()
            }
        }
        .frame(minWidth: 320)
        .padding(28)
    }
}

// Modal for Kokoro model downloads.
struct ReaderKokoroDownloadSheet: View {
    @ObservedObject var modelStore: KokoroModelStore
    let preferredMode: AppearanceMode
    let onDownload: (KokoroDownloadOption) -> Void
    let onClose: () -> Void

    @State private var pendingDeleteOption: KokoroDownloadOption?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(KokoroDownloadCatalog.allOptions.sorted(by: { $0.qualityRank < $1.qualityRank })) { option in
                            optionRow(for: option)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Download TTS Model")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(modelStore.isInstalled ? "Done" : "TTS Model Required") {
                        if modelStore.isInstalled {
                            onClose()
                        }
                    }
                    .disabled(!modelStore.isInstalled)
                }
            }
            .confirmationDialog(
                "Delete downloaded model?",
                isPresented: Binding(
                    get: { pendingDeleteOption != nil },
                    set: { if !$0 { pendingDeleteOption = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let pendingDeleteOption {
                        modelStore.deleteDownloadedModel(pendingDeleteOption)
                    }
                    pendingDeleteOption = nil
                }

                Button("Cancel", role: .cancel) {
                    pendingDeleteOption = nil
                }
            } message: {
                Text("This removes the local model file from your device. You can download it again later.")
            }
        }
        .interactiveDismissDisabled(!modelStore.isInstalled)
    }

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Download TTS Model")
                .font(.title2.weight(.bold))

            Text("You must download at least one model before you can use the app. Choose the tier that matches your device and quality preference.")
                .foregroundStyle(.secondary)

            Text("Models are listed from highest quality to lowest quality. The recommended option appears first.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(headerBackground, in: Rectangle())
    }

    private func optionRow(for option: KokoroDownloadOption) -> some View {
        let isInstalled = modelStore.isOptionDownloaded(option)
        let isDownloading = {
            if case .downloading(let activeOption) = modelStore.status {
                return activeOption.localFileName == option.localFileName
            }
            return false
        }()
        let isActive = modelStore.activeModelFileName == option.localFileName && isInstalled
        let isSelectable = option.isRecommended

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(option.displayName)
                            .font(.headline)

                        if option.isRecommended {
                            Text("Recommended")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.18), in: Capsule())
                        }
                    }

                    Text(option.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if isInstalled {
                    HStack(spacing: 12) {
                        Toggle(isOn: Binding(
                            get: { isActive },
                            set: { isOn in
                                if isOn {
                                    modelStore.activateDownloadedModel(option)
                                } else {
                                    modelStore.deactivateDownloadedModel(option)
                                }
                            }
                        )) {
                            Text("Active")
                        }
                        .labelsHidden()
                        .toggleStyle(.switch)
                    .readerPointerCursor()
                        .disabled(!isSelectable)
                        .help("Only one downloaded model can be active at a time.")

                        Button(role: .destructive) {
                            pendingDeleteOption = option
                        } label: {
                            Image(systemName: "trash.fill")
                                .font(.headline)
                        }
                        .buttonStyle(.bordered)
                        .help("Delete this downloaded model from local storage.")
                    }
                } else {
                    Button {
                        onDownload(option)
                    } label: {
                        if isDownloading {
                            downloadingButtonLabel
                        } else {
                            Label("Download", systemImage: "arrow.down.circle.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isDownloading)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(.secondary)
                Text(qualityDescription(for: option))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if isInstalled && !isSelectable {
                    Text("Not selectable in this build")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if isDownloading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(rowBackground, in: Rectangle())
    }

    private func qualityDescription(for option: KokoroDownloadOption) -> String {
        switch option.localFileName {
        case "kokoro_q8f16.safetensors":
            return "Highest quality, recommended for the best output."
        case "kokoro_fp16.safetensors":
            return "High quality with a little less memory pressure."
        case "kokoro_quantized.safetensors":
            return "Smaller and faster on CPU-heavy systems."
        case "kokoro_q4f16.safetensors":
            return "Smallest download, experimental quality tier."
        default:
            return option.qualityLabel
        }
    }

    private var downloadingButtonLabel: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Downloading...")
        }
    }

    private var headerBackground: Color {
        preferredMode == .light ? Color.black.opacity(0.04) : Color.white.opacity(0.06)
    }

    private var rowBackground: Color {
        preferredMode == .light ? Color.black.opacity(0.03) : Color.white.opacity(0.05)
    }
}

struct ReaderTTSSettingsSheet: View {
    @Binding var appearanceModeRawValue: String
    @Binding var activeProviderIDRawValue: String
    @Binding var kokoroVoiceName: String
    @Binding var moonshineVoiceName: String
    @Binding var supertonicVoiceName: String
    @ObservedObject var ttsCoordinator: ReaderTTSCoordinator
    let isKokoroPlaying: Bool
    let isMoonshinePlaying: Bool
    let isSupertonicPlaying: Bool
    let onPlaySample: (ReaderTTSVoiceSelection) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Light mode not ready yet
//                    settingSection(title: "Appearance") {
//                        Picker("Theme", selection: $appearanceModeRawValue) {
//                            ForEach(AppearanceMode.allCases) { mode in
//                                Text(mode.title).tag(mode.rawValue)
//                            }
//                        }
//                    }

                    settingSection(title: "TTS Provider") {
                        Picker("Active Provider", selection: $activeProviderIDRawValue) {
                            ForEach(installedProviderIDs) { provider in
                                Text(provider.title).tag(provider.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .readerPointerCursor()
                        .disabled(installedProviderIDs.isEmpty)

                        Text(providerNote)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    settingSection(title: "Voice") {
                        Picker("Default Voice", selection: selectedVoiceBinding) {
                            ForEach(currentVoiceOptions, id: \.id) { voice in
                                Text("\(voice.genderSymbol) \(voice.dropdownLabel)")
                                    .tag(voice.voiceName)
                            }
                        }
                        .pickerStyle(.menu)
                        .readerPointerCursor()

                        Button {
                            onPlaySample(currentVoice)
                        } label: {
                            Label(isPlaying ? "Playing..." : "Play Sample", systemImage: "play.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .readerPointerCursor()
                        .disabled(isPlaying)

                        Text(currentVoice.sampleText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("settings-sheet")
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("settings-sheet-done-button")
                }
            }
        }
    }

    private var currentProviderID: ReaderTTSProviderID {
        ReaderTTSProviderID(rawValue: activeProviderIDRawValue) ?? .kokoro
    }

    private var installedProviderIDs: [ReaderTTSProviderID] {
        var providers: [ReaderTTSProviderID] = []

        if ttsCoordinator.kokoroStore.isInstalled {
            providers.append(.kokoro)
        }

        if ttsCoordinator.moonshineStore.isInstalled {
            providers.append(.moonshine)
        }

        if ttsCoordinator.supertonicStore.isInstalled {
            providers.append(.supertonic)
        }

        return providers
    }

    private var isPlaying: Bool {
        switch currentProviderID {
        case .kokoro:
            return isKokoroPlaying
        case .moonshine:
            return isMoonshinePlaying
        case .supertonic:
            return isSupertonicPlaying
        }
    }

    private var providerNote: String {
        if installedProviderIDs.isEmpty {
            return "No TTS model is installed yet. Open the download sheet to install Kokoro, Moonshine, or Supertonic."
        }

        switch currentProviderID {
        case .kokoro:
            return "Kokoro offers wide variety of voices and is usually more accurate."
        case .moonshine:
            return "Moonshine uses its own local TTS runtime and is more performant."
        case .supertonic:
            return "Supertonic uses ONNX Runtime and supports more languages with lightweight local models."
        }
    }

    private var currentVoiceOptions: [ReaderTTSVoiceSelection] {
        switch currentProviderID {
        case .kokoro:
            return KokoroVoiceCatalog.allVoices.map(\.readerTTSVoiceSelection)
        case .moonshine:
            return MoonshineVoiceCatalog.allVoices
        case .supertonic:
            return SupertonicVoiceCatalog.allVoices
        }
    }

    private var selectedVoiceBinding: Binding<String> {
        switch currentProviderID {
        case .kokoro:
            return $kokoroVoiceName
        case .moonshine:
            return $moonshineVoiceName
        case .supertonic:
            return $supertonicVoiceName
        }
    }

    private var currentVoice: ReaderTTSVoiceSelection {
        currentVoiceOptions.first(where: { $0.voiceName == selectedVoiceBinding.wrappedValue }) ?? currentVoiceOptions[0]
    }

    @ViewBuilder
    private func settingSection<Content: View>(
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

struct ReaderTTSDownloadSheet: View {
    @ObservedObject var kokoroModelStore: KokoroModelStore
    @ObservedObject var moonshineModelStore: MoonshineModelStore
    @ObservedObject var supertonicModelStore: SupertonicModelStore
    @ObservedObject var ttsCoordinator: ReaderTTSCoordinator
    let preferredMode: AppearanceMode

    @Environment(\.dismiss) private var dismiss
    @State private var pendingDeleteProviderID: ReaderTTSProviderID?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection

                        VStack(alignment: .leading, spacing: 12) {
                            providerRow(
                                providerID: .kokoro,
                                subtitle: KokoroDownloadCatalog.defaultOption.subtitle,
                                isInstalled: kokoroModelStore.isInstalled,
                                isActive: ttsCoordinator.activeProviderID == .kokoro,
                                isDownloading: isKokoroDownloading,
                                onDownload: { kokoroModelStore.downloadModel(option: KokoroDownloadCatalog.defaultOption) },
                                onActivate: { ttsCoordinator.setActiveProvider(.kokoro) },
                                onDelete: { pendingDeleteProviderID = .kokoro }
                            )

                            providerRow(
                                providerID: .moonshine,
                                subtitle: MoonshineDownloadCatalog.defaultOption.subtitle,
                                isInstalled: moonshineModelStore.isInstalled,
                                isActive: ttsCoordinator.activeProviderID == .moonshine,
                                isDownloading: isMoonshineDownloading,
                                onDownload: { moonshineModelStore.downloadModel(option: MoonshineDownloadCatalog.defaultOption) },
                                onActivate: { ttsCoordinator.setActiveProvider(.moonshine) },
                                onDelete: { pendingDeleteProviderID = .moonshine }
                            )

                            providerRow(
                                providerID: .supertonic,
                                subtitle: SupertonicDownloadCatalog.defaultOption.subtitle,
                                isInstalled: supertonicModelStore.isInstalled,
                                isActive: ttsCoordinator.activeProviderID == .supertonic,
                                isDownloading: isSupertonicDownloading,
                                onDownload: { supertonicModelStore.downloadModel(option: SupertonicDownloadCatalog.defaultOption) },
                                onActivate: { ttsCoordinator.setActiveProvider(.supertonic) },
                                onDelete: { pendingDeleteProviderID = .supertonic }
                            )
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                footerButtons
            }
            .navigationTitle("Download TTS Model")
            .confirmationDialog(
                "Delete downloaded model?",
                isPresented: Binding(
                    get: { pendingDeleteProviderID != nil },
                    set: { if !$0 { pendingDeleteProviderID = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let pendingDeleteProviderID {
                        switch pendingDeleteProviderID {
                        case .kokoro:
                            kokoroModelStore.deleteDownloadedModel(KokoroDownloadCatalog.defaultOption)
                        case .moonshine:
                            moonshineModelStore.deleteDownloadedModel(MoonshineDownloadCatalog.defaultOption)
                        case .supertonic:
                            supertonicModelStore.deleteDownloadedModel(SupertonicDownloadCatalog.defaultOption)
                        }
                    }
                    pendingDeleteProviderID = nil
                }

                Button("Cancel", role: .cancel) {
                    pendingDeleteProviderID = nil
                }
            } message: {
                Text("This removes the local model file from your device. You can download it again later.")
            }
        }
        .interactiveDismissDisabled(!isInstalledAny)
    }

    private var isInstalledAny: Bool {
        kokoroModelStore.isInstalled || moonshineModelStore.isInstalled || supertonicModelStore.isInstalled
    }

    private var isKokoroDownloading: Bool {
        if case .downloading = kokoroModelStore.status { return true }
        return false
    }

    private var isMoonshineDownloading: Bool {
        if case .downloading = moonshineModelStore.status { return true }
        return false
    }

    private var isSupertonicDownloading: Bool {
        if case .downloading = supertonicModelStore.status { return true }
        return false
    }

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Download TTS Model")
                .font(.title2.weight(.bold))

        Text("Choose one or both offline TTS providers. The active provider can be switched at anytime without redownloading the other model.")
            .foregroundStyle(.secondary)

            Text("Models are listed independently so Kokoro, Moonshine, and Supertonic can be installed side by side.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(headerBackground, in: Rectangle())
    }

    @ViewBuilder
    private func providerRow(
        providerID: ReaderTTSProviderID,
        subtitle: String,
        isInstalled: Bool,
        isActive: Bool,
        isDownloading: Bool,
        onDownload: @escaping () -> Void,
        onActivate: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(providerID.title)
                            .font(.headline)

                        if isActive {
                            Text("Active")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.18), in: Capsule())
                        }

                        if isInstalled && !isActive {
                            Text("Installed")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.18), in: Capsule())
                        }
                    }

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if isInstalled {
                    HStack(spacing: 12) {
                        Button(isActive ? "Active" : "Use") {
                            onActivate()
                        }
                        .buttonStyle(.borderedProminent)
                        .readerPointerCursor()
                        .disabled(isActive)

                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Image(systemName: "trash.fill")
                                .font(.headline)
                        }
                        .buttonStyle(.bordered)
                        .readerPointerCursor()
                    }
                } else {
                    Button {
                        onDownload()
                    } label: {
                        if isDownloading {
                            downloadingButtonLabel
                        } else {
                            Label("Download", systemImage: "arrow.down.circle.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .readerPointerCursor()
                    .disabled(isDownloading)
                }
            }

            Text(providerDescription(for: providerID))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(rowBackground, in: Rectangle())
    }

    private func providerDescription(for providerID: ReaderTTSProviderID) -> String {
        switch providerID {
        case .kokoro:
            return "Kokoro offers wide variety of voices & better quality than Moonshine but requires more memory."
        case .moonshine:
            return "Moonshine is compact & fast. It works great on low-spec devices."
        case .supertonic:
            return "Supertonic uses ONNX Runtime and covers more languages with a compact local bundle."
        }
    }

    private var downloadingButtonLabel: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Downloading...")
        }
    }

    private var footerButtons: some View {
        HStack {
            Spacer()
            Button(isInstalledAny ? "Done" : "TTS Model Required") {
                if isInstalledAny {
                    dismiss()
                }
            }
            .disabled(!isInstalledAny)
            .readerPointerCursor()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.thinMaterial)
    }

    private var headerBackground: Color {
        preferredMode == .light ? Color.black.opacity(0.04) : Color.white.opacity(0.06)
    }

    private var rowBackground: Color {
        preferredMode == .light ? Color.black.opacity(0.03) : Color.white.opacity(0.05)
    }
}

// Sheet for creating a new category.
struct ReaderNewCategorySheet: View {
    @Binding var categoryName: String
    let onCreate: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Category Name") {
                    TextField("", text: $categoryName)
                        .textFieldStyle(.plain)
                            // .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .frame(height: 40)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                            )
                }

                Section {
                    Text("Create folders for books and audio sessions so the sidebar stays organized.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .accessibilityIdentifier("new-category-sheet")
            .navigationTitle("New Category")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("new-category-sheet-cancel-button")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { onCreate() }
                        .disabled(categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("new-category-sheet-create-button")
                }
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
}

// Modal for pasting text directly into the library.
struct ReaderPasteTextSheet: View {
    @Binding var title: String
    @Binding var text: String
    @FocusState private var isFocused: Bool
    let onPlay: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Title")
                        .font(.body.weight(.semibold))

                    TextField("Optional title", text: $title)
                        .textFieldStyle(.plain)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .frame(height: 40)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                            )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Text")
                        .font(.body.weight(.semibold))

                TextEditor(text: $text)
                        .textFieldStyle(.plain)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .frame(height: 180)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                            )
                            .focused($isFocused)
                            .onAppear {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        isFocused = true
                                    }
                            }
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(minWidth: 440, minHeight: 340)
            .accessibilityIdentifier("paste-text-sheet")
            .navigationTitle("Paste Text")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("paste-text-sheet-cancel-button")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Play") { onPlay() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("paste-text-sheet-play-button")
                }
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
}
