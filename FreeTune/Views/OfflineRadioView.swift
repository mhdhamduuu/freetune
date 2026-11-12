import SwiftUI

/// Offline Radio — save authorized downloadable radio programmes, listen
/// with full offline support (library, recently played, resume positions,
/// storage display, and automatic handover to saved content when the
/// internet drops).
struct OfflineRadioView: View {
    @ObservedObject private var radio = OfflineRadioManager.shared
    @ObservedObject private var storage = OfflineRadioStorage.shared
    @ObservedObject private var downloads = RadioDownloadManager.shared
    @ObservedObject private var player = PlayerManager.shared

    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedCategory = RadioCategory.all.first!
    @State private var catalogTracks: [Track] = []
    @State private var catalogLoading = false
    @State private var catalogError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    statusHeader
                    if let banner = radio.banner {
                        bannerView(banner)
                    }
                    if !storage.recentlyPlayed.isEmpty {
                        continueSection
                    }
                    if !storage.episodes.isEmpty {
                        librarySection
                    }
                    browseSection
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .navigationTitle("Offline Radio")
            .task(id: selectedCategory) {
                loadCatalog()
            }
            .onChange(of: scenePhase) { _ in
                radio.flushPosition()
            }
            .alert(
                "Radio Download Error",
                isPresented: Binding(
                    get: { downloads.lastErrorMessage != nil },
                    set: { if !$0 { downloads.lastErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(downloads.lastErrorMessage ?? "")
            }
        }
    }

    // MARK: - Status header (online state + storage + auto-switch)

    private var statusHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(radio.isOnline ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(radio.isOnline ? "Online" : "Offline")
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: "internaldrive")
                    .foregroundColor(.secondary)
                Text(storageText)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            Toggle(isOn: $radio.autoSwitchEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Switch to saved programmes offline")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("When the internet drops mid-song, FreeTune continues with your saved radio.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .tint(Color.accentColor)
        }
        .padding(14)
        .glassCard(cornerRadius: 16)
        .padding(.horizontal)
    }

    private var storageText: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let used = formatter.string(fromByteCount: storage.librarySizeBytes)
        let free = formatter.string(fromByteCount: OfflineRadioStorage.freeDiskSpaceBytes())
        return "\(used) saved · \(free) free"
    }

    private func bannerView(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            Text(text)
                .font(.footnote)
                .fontWeight(.medium)
        }
        .foregroundColor(.white)
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.red.opacity(0.85))
        )
        .padding(.horizontal)
    }

    // MARK: - Continue listening (recently played + resume)

    private var continueSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Continue Listening")
                .font(.headline)
                .padding(.horizontal)
            ForEach(Array(storage.recentlyPlayed.prefix(4)), id: \.id) { episode in
                savedEpisodeRow(episode)
            }
        }
    }

    // MARK: - Offline radio library

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Saved Programmes")
                .font(.headline)
                .padding(.horizontal)
            ForEach(Array(storage.episodes.sorted { $0.downloadedAt > $1.downloadedAt }.prefix(20)), id: \.id) { episode in
                savedEpisodeRow(episode)
            }
        }
    }

    private func savedEpisodeRow(_ episode: SavedRadioEpisode) -> some View {
        let isCurrent = player.currentTrack?.id == episode.id
        return HStack(spacing: 12) {
            TrackArtwork(track: episode.track, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(episode.track.name)
                    .font(.subheadline)
                    .fontWeight(isCurrent ? .bold : .semibold)
                    .foregroundColor(isCurrent ? Color.accentColor : .primary)
                    .lineLimit(1)
                Text(subtitle(for: episode))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                if isCurrent {
                    player.togglePlayPause()
                } else {
                    radio.play(episode: episode)
                }
            } label: {
                Image(systemName: isCurrent && player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundColor(Color.accentColor)
            }
            .buttonStyle(SpringPressStyle(scale: 0.9))
            Button {
                storage.removeEpisode(episode)
            } label: {
                Image(systemName: "trash")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(SpringPressStyle(scale: 0.9))
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal)
    }

    private func subtitle(for episode: SavedRadioEpisode) -> String {
        var parts: [String] = [episode.track.artistName]
        if let resume = episode.resumePosition, resume > 3 {
            parts.append("Resume at \(resume.asTimeString)")
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        parts.append(formatter.string(fromByteCount: episode.fileSize))
        return parts.joined(separator: " · ")
    }

    // MARK: - Browse & download (authorized catalog)

    private var browseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Browse Authorized Programmes")
                .font(.headline)
                .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(RadioCategory.all) { category in
                        chip(title: category.title, active: selectedCategory == category) {
                            selectedCategory = category
                        }
                    }
                }
                .padding(.horizontal)
            }
            .entrance(delay: 0.05)

            if catalogLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 24)
            } else if let error = catalogError {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(catalogTracks, id: \.id) { track in
                        catalogRow(track)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func chip(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(active ? .bold : .regular)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background {
                    if active {
                        Capsule().fill(
                            LinearGradient(
                                colors: [GlassPalette.pink, GlassPalette.violet],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    } else {
                        Capsule().fill(.ultraThinMaterial)
                    }
                }
                .foregroundColor(active ? .white : .primary)
        }
        .buttonStyle(SpringPressStyle(scale: 0.92))
    }

    private func catalogRow(_ track: Track) -> some View {
        let isCurrent = player.currentTrack?.id == track.id
        let episode = storage.episode(for: track.id)
        let state = downloads.states[track.id] ?? .idle
        return HStack(spacing: 12) {
            TrackArtwork(track: track, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(track.name)
                    .font(.subheadline)
                    .fontWeight(isCurrent ? .bold : .semibold)
                    .foregroundColor(isCurrent ? Color.accentColor : .primary)
                    .lineLimit(1)
                Text("\(track.artistName) · \(track.durationSeconds.asTimeString)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                if state == .downloading, let progress = downloads.progress[track.id] {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.secondary.opacity(0.25))
                            Capsule()
                                .fill(GlassPalette.accentGradient)
                                .frame(width: geo.size.width * CGFloat(progress))
                        }
                    }
                    .frame(height: 4)
                }
            }
            Spacer(minLength: 8)
            catalogRowActions(track: track, isCurrent: isCurrent, state: state)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func catalogRowActions(track: Track, isCurrent: Bool, state: RadioDownloadState) -> some View {
        if storage.episode(for: track.id) != nil {
            Button {
                if isCurrent {
                    player.togglePlayPause()
                } else {
                    radio.play(track: track)
                }
            } label: {
                Image(systemName: isCurrent && player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title3)
                    .foregroundColor(Color.accentColor)
            }
            .buttonStyle(SpringPressStyle(scale: 0.9))
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        } else {
            switch state {
            case .downloading:
                Button {
                    downloads.pauseDownload(track.id)
                } label: {
                    Image(systemName: "pause.circle.fill")
                        .font(.title3)
                        .foregroundColor(.orange)
                }
                .buttonStyle(SpringPressStyle(scale: 0.9))
            case .paused:
                Button {
                    downloads.resumeDownload(track.id)
                } label: {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.title3)
                        .foregroundColor(.orange)
                }
                .buttonStyle(SpringPressStyle(scale: 0.9))
            case .idle:
                Button {
                    downloads.startDownload(track)
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.title3)
                        .foregroundColor(.primary)
                }
                .buttonStyle(SpringPressStyle(scale: 0.9))
            }
        }
    }

    // MARK: - Catalog loading

    private func loadCatalog() {
        catalogLoading = true
        catalogError = nil
        let category = selectedCategory
        Task {
            do {
                let tracks = try await RadioCategory.fetch(category)
                await MainActor.run {
                    guard selectedCategory == category else { return }
                    catalogTracks = tracks
                    catalogLoading = false
                }
            } catch {
                await MainActor.run {
                    guard selectedCategory == category else { return }
                    catalogTracks = []
                    catalogLoading = false
                    catalogError = error.localizedDescription
                }
            }
        }
    }
}
