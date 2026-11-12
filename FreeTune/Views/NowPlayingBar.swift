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
                        MarqueeText(text: track.name, font: .footnote.weight(.semibold), color: .primary, speed: 22)
                            .frame(height: 15)
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
                .overlay(alignment: .bottom) {
                    GeometryReader { geo in
                        Capsule()
                            .fill(GlassPalette.accentGradient)
                            .frame(width: geo.size.width * progressFraction, height: 2.5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 2.5)
                }
                .onTapGesture {
                    showFull = true
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: player.currentTrack?.id)
    }

    private var progressFraction: CGFloat {
        guard player.duration > 0 else { return 0 }
        return CGFloat(min(max(player.currentTime / player.duration, 0), 1))
    }
}
