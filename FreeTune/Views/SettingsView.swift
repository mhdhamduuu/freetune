import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var sound = SoundSettings.shared
    @ObservedObject private var downloads = DownloadManager.shared
    @State private var draftKey = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Paste your Jamendo client ID", text: $draftKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save Key") {
                        settings.save(clientID: draftKey)
                        draftKey = ""
                    }
                    .disabled(draftKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    if !settings.effectiveClientID.isEmpty {
                        Label("Key is active — you're all set.", systemImage: "checkmark.seal.fill")
                            .font(.footnote)
                            .foregroundColor(.green)
                    }
                } header: {
                    Text("Jamendo API Key")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Create a free account at dev.jamendo.com, register an app, and paste the client ID here.")
                        Link("Open dev.jamendo.com", destination: URL(string: "https://dev.jamendo.com")!)
                    }
                }

                Section {
                    Toggle("Hi-Res Audio (FLAC)", isOn: $sound.hifi)
                    NavigationLink {
                        SoundView()
                    } label: {
                        Label("Equalizer & Immersive Sound", systemImage: "waveform")
                    }
                } header: {
                    Text("Sound")
                }

                Section("Storage") {
                    LabeledContent(
                        "Downloaded songs",
                        value: "\(downloads.downloads.count)"
                    )
                    LabeledContent(
                        "Space used",
                        value: ByteCountFormatter.string(fromByteCount: totalBytes(), countStyle: .file)
                    )
                    if !downloads.downloads.isEmpty {
                        Button(role: .destructive) {
                            deleteAllDownloads()
                        } label: {
                            Label("Delete All Downloads", systemImage: "trash")
                        }
                    }
                }

                Section("About") {
                    LabeledContent("App", value: "FreeTune 1.0")
                    LabeledContent("Music", value: "Jamendo + Audius")
                    Text("Free and ad-free. Every song is hosted by Jamendo artists and shared under Creative Commons licenses. Downloads appear only where the artist allows them.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                draftKey = settings.clientID
            }
        }
    }

    private func totalBytes() -> Int64 {
        downloads.downloads.reduce(0) { $0 + $1.fileSize }
    }

    private func deleteAllDownloads() {
        for record in downloads.downloads {
            downloads.deleteDownload(record)
        }
    }
}
