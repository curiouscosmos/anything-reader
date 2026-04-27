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
                        Picker("Default Voice", selection: $selectedVoiceName) {
                            ForEach(voiceOptions) { voice in
                                Text(voice.displayName).tag(voice.voiceName)
                            }
                        }
                        .pickerStyle(.menu)

                        Text("Kokoro voice selection is local and will use the offline runtime when the model directory is available.")
                            .foregroundStyle(.secondary)
                    }

                    settingSection(title: "Voice Samples") {
                        ForEach(voiceOptions) { voice in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(voice.displayName)
                                            .font(.headline)

                                        Text(voice.languageLabel)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer(minLength: 8)

                                    Button {
                                        onPlaySample(voice)
                                    } label: {
                                        Label("Play Sample", systemImage: "play.circle.fill")
                                    }
                                    .buttonStyle(.borderedProminent)
                                }

                                Text(voice.sampleText)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
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
