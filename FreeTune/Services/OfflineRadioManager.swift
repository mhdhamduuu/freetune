import Foundation
import Combine
import Network

/// A browsable category of authorized downloadable radio programmes.
///
/// Source policy (the IMPORTANT rules from the offline-radio spec):
///  - Every programme is a static, downloadable audio file from the
///    Internet Archive's Old Time Radio preservation collections — a public
///    community archive of classic radio. These are published for download;
///    nothing is recorded or captured from live streams.
///  - Live internet radio is never treated as offline content: streams
///    cannot continue after disconnection, so only saved files count.
struct RadioCategory: Identifiable, Hashable {
    let title: String
    let extraQuery: String?

    var id: String { title }

    static let all: [RadioCategory] = [
        RadioCategory(title: "Top Programmes", extraQuery: nil),
        RadioCategory(title: "Mystery & Suspense", extraQuery: "(suspense OR mystery)"),
        RadioCategory(title: "Comedy Classics", extraQuery: "(comedy OR jack benny OR fibber)"),
        RadioCategory(title: "Sherlock Holmes", extraQuery: "(sherlock holmes)"),
        RadioCategory(title: "Westerns", extraQuery: "(gunsmoke OR lone ranger OR western)"),
        RadioCategory(title: "News & History", extraQuery: "(news OR war OR churchill)")
    ]

    static func fetch(_ category: RadioCategory) async throws -> [Track] {
        try await InternetArchiveAPI.shared.fetchCollectionTracks(
            collection: "oldtimeradio",
            extraQuery: category.extraQuery,
            limit: 40,
            offset: 0
        )
    }
}

/// Orchestrates the offline radio system:
///  - Watches connectivity and — when the internet drops mid-stream —
///    automatically switches to the most recently played saved programme.
///  - Plays saved programmes through the existing PlayerManager (AVPlayer),
///    so background audio, lock screen and the mini player all work.
///  - Tracks recently played programmes and resume positions in storage.
final class OfflineRadioManager: ObservableObject {
    static let shared = OfflineRadioManager()

    @Published private(set) var isOnline = true
    @Published private(set) var banner: String?
    @Published var autoSwitchEnabled: Bool {
        didSet { UserDefaults.standard.set(autoSwitchEnabled, forKey: "freetune.radio.autoswitch") }
    }

    private let monitor = NWPathMonitor()
    private var playerSubscription: AnyCancellable?
    private var positionTimer: Timer?

    private var storage: OfflineRadioStorage { OfflineRadioStorage.shared }
    private var player: PlayerManager { PlayerManager.shared }

    private init() {
        autoSwitchEnabled = UserDefaults.standard.object(forKey: "freetune.radio.autoswitch") as? Bool ?? true
        startMonitor()
        observePlayer()
    }

    // MARK: - Connectivity

    private func startMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.handlePathChange(online: path.status == .satisfied)
            }
        }
        monitor.start(queue: DispatchQueue(label: "freetune.radio.pathmonitor"))
    }

    private func handlePathChange(online: Bool) {
        let wasOnline = isOnline
        isOnline = online
        if online {
            banner = nil
            return
        }
        guard wasOnline else { return }
        handleInternetLoss()
    }

    /// Live streams cannot survive disconnection — so when the network drops
    /// mid-stream, hand playback over to a saved programme.
    private func handleInternetLoss() {
        let currentTrack = player.currentTrack
        let isLocal = currentTrack.flatMap { DownloadManager.shared.localFileURL(for: $0) } != nil

        guard !isLocal else {
            // Local content (saved music or saved radio) is unaffected.
            return
        }

        if player.isPlaying {
            player.pause()
            if let fallback = fallbackEpisode() {
                play(episode: fallback)
                banner = "Internet lost — playing a saved programme."
            } else {
                banner = "Internet lost. Download radio programmes to keep listening offline."
            }
        } else {
            banner = "You're offline. Your saved radio library is ready."
        }
        scheduleBannerDismiss()
    }

    private func fallbackEpisode() -> SavedRadioEpisode? {
        storage.recentlyPlayed.first ?? storage.episodes.first
    }

    private func scheduleBannerDismiss() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in
            self?.banner = nil
        }
    }

    // MARK: - Playback (through the shared PlayerManager / AVPlayer)

    /// Plays a saved programme, resuming from the stored position when there
    /// is one worth resuming (not near the start, not near the end).
    func play(episode: SavedRadioEpisode) {
        storage.markPlayed(trackID: episode.id)
        player.play([episode.track], startIndex: 0)

        if let resume = episode.resumePosition,
           resume > 3,
           let duration = episode.durationSeconds,
           resume < duration - 5 {
            player.seek(to: resume)
        }
    }

    /// Plays a catalog entry — downloaded programmes resume from their
    /// position, un-downloaded ones stream through the same player.
    func play(track: Track) {
        if let episode = storage.episode(for: track.id) {
            play(episode: episode)
            return
        }
        player.play([track], startIndex: 0)
    }

    // MARK: - Resume-position tracking

    private func observePlayer() {
        playerSubscription = player.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playing in
                guard let self else { return }
                if playing {
                    self.startPositionTimer()
                } else {
                    self.stopPositionTimer()
                    self.flushPosition()
                }
            }
    }

    private func startPositionTimer() {
        stopPositionTimer()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.flushPosition()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        positionTimer = timer
    }

    private func stopPositionTimer() {
        positionTimer?.invalidate()
        positionTimer = nil
    }

    /// Saves the current resume position when a saved programme is playing.
    /// Also called from the view when the app moves to the background.
    func flushPosition() {
        guard let track = player.currentTrack,
              storage.episode(for: track.id) != nil,
              player.isPlaying,
              player.currentTime > 1 else { return }

        let duration = player.duration > 0 ? player.duration : nil
        if let duration, player.currentTime >= duration - 3 {
            storage.clearPosition(trackID: track.id)
            return
        }
        storage.savePosition(trackID: track.id, position: player.currentTime, duration: duration)
    }
}
