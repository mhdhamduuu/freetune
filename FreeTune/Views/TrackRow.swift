import SwiftUI

struct TrackRow: View {
    let track: Track
    let queue: [Track]
    let index: Int
    var subtitleOverride: String? = nil

    @ObservedObject private var player = PlayerManager.shared
    @ObservedObject private var favorites = FavoritesManager.shared

    private var isCurrent: Bool { player.currentTrack?.id == track.id }

    var body: some View {
        HStack(spacing: 12) {
            TrackArtwork(track: track, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(track.name)
                    .font(.subheadline)
                    .fontWeight(isCurrent ? .bold : .semibold)
                    .foregroundColor(isCurrent ? Color.accentColor : .primary)
                    .lineLimit(1)
                Text(subtitleOverride ?? track.artistName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                if isCurrent {
                    EqBars(playing: player.isPlaying)
                }
            }
            Spacer(minLength: 8)
            Text((track.duration ?? 0).asTimeString)
                .font(.caption2)
                .foregroundColor(.secondary)
            FavoriteButton(track: track)
            DownloadButton(track: track)
        }
        .padding(.vertical, 5)
        .padding(.horizontal)
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.impact()
            if isCurrent {
                if !player.isPlaying {
                    player.resume()
                }
            } else {
                player.play(queue, startIndex: index)
            }
        }
    }
}

struct FavoriteButton: View {
    let track: Track

    @ObservedObject private var favorites = FavoritesManager.shared

    var body: some View {
        Button {
            Haptics.impact()
            favorites.toggle(track)
        } label: {
            Image(systemName: favorites.isFavorite(track) ? "heart.fill" : "heart")
                .foregroundColor(
                    favorites.isFavorite(track)
                        ? Color(red: 1.0, green: 0.32, blue: 0.45)
                        : Color.secondary
                )
                .font(.system(size: 17))
        }
        .buttonStyle(.plain)
    }
}

struct DownloadButton: View {
    let track: Track

    @ObservedObject private var downloads = DownloadManager.shared
    @State private var confirmDelete = false

    var body: some View {
        Group {
            if !track.downloadAllowed {
                EmptyView()
            } else if downloads.isDownloaded(track) {
                Button {
                    confirmDelete = true
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 17))
                }
                .buttonStyle(.plain)
            } else if let progress = downloads.progress(for: track) {
                Button {
                    downloads.cancelDownload(track.id)
                } label: {
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.35), lineWidth: 2.5)
                        Circle()
                            .trim(from: 0, to: max(0.04, min(1, progress)))
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 19, height: 19)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    Haptics.impact()
                    downloads.startDownload(track)
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .foregroundColor(.secondary)
                        .font(.system(size: 17))
                }
                .buttonStyle(.plain)
            }
        }
        .alert("Remove Download?", isPresented: $confirmDelete) {
            Button("Remove", role: .destructive) {
                if let record = downloads.download(for: track.id) {
                    downloads.deleteDownload(record)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The song stays available for streaming — this only removes the offline copy.")
        }
    }
}

struct EqBars: View {
    let playing: Bool

    @State private var animated = false

    private let heights: [CGFloat] = [11, 15, 8]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2.5) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.accentColor)
                    .frame(width: 3, height: animated ? heights[index] : 3)
                    .animation(
                        playing
                            ? .easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(Double(index) * 0.18)
                            : nil,
                        value: animated
                    )
            }
        }
        .onAppear { animated = playing }
        .onChange(of: playing) { newValue in animated = newValue }
    }
}
