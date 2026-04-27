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
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    settingSection(title: "Appearance") {
                        Picker("Theme", selection: $appearanceModeRawValue) {
                            ForEach(AppearanceMode.allCases) { mode in
                                Text(mode.title).tag(mode.rawValue)
                            }
                        }
                    }

                    settingSection(title: "Kokoro Voice") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .center, spacing: 12) {
                                Picker("Default Voice", selection: $selectedVoiceName) {
                                    ForEach(voiceOptions) { voice in
                                        Text(voice.displayName).tag(voice.voiceName)
                                    }
                                }
                                .pickerStyle(.menu)

                                Button {
                                    onPlaySample(currentVoice)
                                } label: {
                                    Label(isPlaying ? "Playing..." : "Play", systemImage: "play.circle.fill")
                                }
                                .buttonStyle(.borderedProminent)
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
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @Environment(\.dismiss) private var dismiss

    private var currentVoice: KokoroVoiceOption {
        voiceOptions.first(where: { $0.voiceName == selectedVoiceName }) ?? voiceOptions[0]
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
                    Button(modelStore.isInstalled ? "Done" : "Keep Open") {
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
                            Label("Downloading", systemImage: "arrow.down.circle")
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
                    TextField("Chapters, Work, Study, etc.", text: $categoryName)
                }

                Section {
                    Text("Create folders for books and audio sessions so the sidebar stays organized.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New Category")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { onCreate() }
                        .disabled(categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
    let onPlay: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Paste text to listen")
                    .font(.title2.weight(.bold))

                Text("The text will be saved locally with a random title and avatar, then queued into the player.")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Title")
                        .font(.subheadline.weight(.semibold))

                    TextField("Optional title", text: $title)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Text")
                        .font(.subheadline.weight(.semibold))

                TextEditor(text: $text)
                    .frame(minHeight: 180)
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(minWidth: 440, minHeight: 340)
            .navigationTitle("Paste Text")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Play") { onPlay() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
}
