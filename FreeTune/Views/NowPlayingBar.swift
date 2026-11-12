import SwiftUI

struct NowPlayingBar: View {
    @Binding var showFull: Bool

    @ObservedObject private var player = PlayerManager.shared

    var body: some View {
        Group {
            if let track = player.currentTrack {
                HStack(spacing: 12) {
                    TrackArtwork(track: track, size: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.name)
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        Text(track.artistName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Button {
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    Button {
                        player.next()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.body)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 4)
                .onTapGesture {
                    showFull = true
                }
            }
        }
    }
}
