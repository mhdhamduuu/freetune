import SwiftUI

struct NowPlayingView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var player = PlayerManager.shared
    @ObservedObject private var favorites = FavoritesManager.shared

    @State private var scrubbing = false
    @State private var scrubPosition: Double = 0
    @State private var showQueue = false
    @State private var showSound = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ImmersiveBackdrop(track: player.currentTrack ?? .placeholder)
                VStack(spacing: 0) {
                    header
                    Spacer(minLength: 4)
                    artworkStack(width: geo.size.width, height: geo.size.height)
                    Spacer(minLength: 4)
                    titleBlock
                    Spacer(minLength: 2)
                    scrubber
                    controls
                    Spacer(minLength: 4)
                    visualizerSection
                    bottomBar
                }
                .padding(.top, 8)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showQueue) { QueueView() }
        .sheet(isPresented: $showSound) { SoundView() }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.85))
            }
            Spacer()
            Text("NOW PLAYING")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.6))
                .kerning(1.5)
            Spacer()
            Button {
                showQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 22)
    }

    private func artworkStack(width: CGFloat, height: CGFloat) -> some View {
        let side = max(140, min(320, width - 56, height * 0.36))
        return TrackArtwork(track: player.currentTrack ?? .placeholder, size: side)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 14)
    }

    private var titleBlock: some View {
        let track = player.currentTrack ?? .placeholder
        return VStack(spacing: 5) {
            Text(track.name)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(track.artistName)
                .font(.body)
                .foregroundColor(.white.opacity(0.65))
                .lineLimit(1)
        }
        .padding(.horizontal, 30)
    }

    private var scrubber: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: {
                        scrubbing
                            ? scrubPosition
                            : min(player.currentTime, max(player.duration, 0.001))
                    },
                    set: { newValue in
                        scrubbing = true
                        scrubPosition = newValue
                    }
                ),
                in: 0...max(player.duration, 0.001),
                onEditingChanged: { editing in
                    if !editing {
                        player.seek(to: scrubPosition)
                        scrubbing = false
                    }
                }
            )
            .tint(.white)
            .padding(.horizontal, 28)
            HStack {
                Text(player.currentTime.asTimeString)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.55))
                Spacer()
                Text(player.duration.asTimeString)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.55))
            }
            .padding(.horizontal, 30)
        }
    }

    private var controls: some View {
        HStack(spacing: 30) {
            Button {
                player.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.body)
                    .foregroundColor(
                        player.isShuffleOn
                            ? Color(red: 0.85, green: 0.55, blue: 1.0)
                            : Color.white.opacity(0.7)
                    )
            }
            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
                    .foregroundColor(.white)
            }
            Button {
                Haptics.impact()
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 66))
                    .foregroundColor(.white)
            }
            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
                    .foregroundColor(.white)
            }
            Button {
                player.toggleRepeat()
            } label: {
                Image(systemName: "repeat")
                    .font(.body)
                    .foregroundColor(
                        player.isRepeatOn
                            ? Color(red: 0.85, green: 0.55, blue: 1.0)
                            : Color.white.opacity(0.7)
                    )
            }
        }
        .padding(.top, 6)
    }

    private var visualizerSection: some View {
        Visualizer(seed: seedValue, active: player.isPlaying)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 30)
    }

    private var seedValue: Double {
        Double(abs(player.currentTrack?.id.hashValue ?? 7) % 1000)
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            FavoriteButton(track: player.currentTrack ?? .placeholder)
            Spacer()
            DownloadButton(track: player.currentTrack ?? .placeholder)
            Spacer()
            Button {
                showSound = true
            } label: {
                Image(systemName: "waveform")
                    .foregroundColor(.white.opacity(0.85))
            }
            .buttonStyle(.plain)
            Spacer()
            ShareLink(item: shareText) {
                Image(systemName: "square.and.arrow.up")
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 34)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var shareText: String {
        let track = player.currentTrack
        let name = track?.name ?? "FreeTune"
        let artist = track?.artistName ?? ""
        let url = track?.audio?.absoluteString ?? "https://www.jamendo.com"
        return "\(name) — \(artist) on FreeTune: \(url)"
    }
}

// MARK: - Immersive blurred-artwork backdrop

struct ImmersiveBackdrop: View {
    let track: Track

    var body: some View {
        ZStack {
            Color.black
            if let url = track.bestArtwork {
                AsyncImage(url: url, transaction: Transaction(animation: .none)) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Color.black
                    }
                }
                .blur(radius: 46)
                .overlay(Color.black.opacity(0.45))
            } else {
                LinearGradient(
                    colors: [Color(red: 0.28, green: 0.18, blue: 0.45), Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            LinearGradient(
                colors: [Color.black.opacity(0.15), Color.black.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Animated visualizer

struct Visualizer: View {
    let seed: Double
    let active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<24, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.85, green: 0.6, blue: 1.0),
                                    Color(red: 0.45, green: 0.3, blue: 0.9)
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(
                            width: 6,
                            height: barHeight(index: index, time: timeline.date.timeIntervalSinceReferenceDate)
                        )
                }
            }
            .frame(height: 54, alignment: .bottom)
        }
    }

    private func barHeight(index: Int, time: Double) -> CGFloat {
        guard active else { return 5 }
        let x = time * 2.6 + Double(index) * 0.55 + seed
        let wave = sin(x) * 0.5 + sin(x * 1.7 + 1.3) * 0.3 + sin(x * 0.53 + 2.1) * 0.2
        let normalized = 0.5 + wave * 0.45
        return CGFloat(max(0.08, min(1, normalized)) * 50)
    }
}

// MARK: - Queue sheet ("Up Next")

struct QueueView: View {
    @ObservedObject private var player = PlayerManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Playing Next") {
                    if player.queue.isEmpty {
                        Text("Queue is empty.")
                            .foregroundColor(.secondary)
                    }
                    ForEach(Array(player.queue.enumerated()), id: \.element.id) { index, track in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption)
                                .foregroundColor(index == player.currentIndex ? .accentColor : .secondary)
                                .frame(width: 22)
                            TrackArtwork(track: track, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.name)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                    .foregroundColor(index == player.currentIndex ? .accentColor : .primary)
                                Text(track.artistName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if index == player.currentIndex {
                                Image(systemName: "waveform")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            player.jumpTo(index)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Up Next")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Sound studio sheet (EQ / Bass / Immersive / Hi-Res)

struct SoundView: View {
    @ObservedObject private var sound = SoundSettings.shared
    @ObservedObject private var player = PlayerManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Hi-Res Audio (FLAC)", isOn: $sound.hifi)
                } header: {
                    Text("Audio Quality")
                } footer: {
                    Text("Streams and downloads lossless FLAC files when the artist allows it. Applies to the next song you play.")
                }

                Section {
                    Toggle("Immersive Sound", isOn: $sound.spatialEnabled)
                    HStack {
                        Text("Bass")
                        Slider(value: $sound.bassBoost, in: 0...10)
                    }
                    ForEach(SoundSettings.presets, id: \.name) { preset in
                        Button {
                            sound.applyPreset(preset.gains)
                        } label: {
                            HStack {
                                Text(preset.name)
                                Spacer()
                                if sound.eqGains == preset.gains {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("5-Band Equalizer")
                            .font(.subheadline)
                        ForEach(0..<5, id: \.self) { band in
                            HStack {
                                Text(SoundSettings.bandLabels[band])
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 40)
                                Slider(
                                    value: Binding(
                                        get: { sound.eqGains[band] },
                                        set: { newValue in
                                            var gains = sound.eqGains
                                            gains[band] = newValue
                                            sound.eqGains = gains
                                        }
                                    ),
                                    in: -12...12
                                )
                                .tint(.accentColor)
                                Text(String(format: "%+.0f", sound.eqGains[band]))
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.secondary)
                                    .frame(width: 34)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Sound Effects")
                } footer: {
                    Text("Equalizer, Bass and Immersive Sound use a real-time DSP engine and apply to downloaded songs. Download a track to hear them.")
                }

                Section("Engine") {
                    LabeledContent("Processing", value: player.stateDescription)
                }
            }
            .navigationTitle("Sound")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
