import SwiftUI

struct LibraryView: View {
    @ObservedObject private var downloads = DownloadManager.shared
    @ObservedObject private var favorites = FavoritesManager.shared

    var body: some View {
        NavigationStack {
            List {
                Section("Downloads — play offline") {
                    if downloads.downloads.isEmpty {
                        Text("Songs you download appear here and play without internet.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(Array(downloads.downloads.enumerated()), id: \.element.id) { index, record in
                            TrackRow(
                                track: record.track,
                                queue: downloads.downloads.map(\.track),
                                index: index,
                                subtitleOverride: subtitle(for: record)
                            )
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    downloads.deleteDownload(record)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                Section("Favorites") {
                    if favorites.favorites.isEmpty {
                        Text("Tap the heart on any song to save it here.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(Array(favorites.favorites.enumerated()), id: \.element.id) { index, track in
                            TrackRow(track: track, queue: favorites.favorites, index: index)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        favorites.toggle(track)
                                    } label: {
                                        Label("Remove", systemImage: "heart.slash")
                                    }
                                }
                        }
                    }
                }
            }
            .navigationTitle("Library")
        }
    }

    private func subtitle(for record: DownloadedTrack) -> String {
        let size = ByteCountFormatter.string(fromByteCount: record.fileSize, countStyle: .file)
        let quality = record.isHiRes ? "FLAC Hi-Res" : "MP3"
        return "\(record.track.artistName) • \(quality) • \(size)"
    }
}
