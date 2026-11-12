import AVFoundation
import Combine
import Foundation
import MediaPlayer
import UIKit

enum PlaybackBackend {
    case avPlayer
    case soundEngine
}

/// The playback brain. Two backends:
///  - AVPlayer for remote streams (MP3 / FLAC) and plain local playback
///  - AVAudioEngine DSP chain for downloaded songs when sound FX are on
/// Handles queue, shuffle/repeat, lock-screen remote commands, artwork,
/// interruptions (phone calls) and Hi-Res quality fallback.
final class PlayerManager: NSObject, ObservableObject {
    static let shared = PlayerManager()

    // MARK: - Published state

    @Published private(set) var queue: [Track] = []
    @Published private(set) var originalQueue: [Track] = []
    @Published private(set) var currentIndex = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isShuffleOn = false
    @Published var isRepeatOn = false
    @Published var playbackErrorMessage: String?

    // MARK: - Backends & internals

    private let avPlayer = AVPlayer()
    private let soundEngine = SoundEngine()
    private var backend: PlaybackBackend = .avPlayer

    private var timeObserver: Any?
    private var statusObservation: AnyCancellable?
    private var soundSettingsObserver: AnyCancellable?
    private var engineTimer: Timer?
    private var engineSegmentStart: Double = 0
    private var engineGeneration = 0
    private var lastFXEnabled = false
    private var usedHiFiFallback = false

    private var artworkCache: [String: UIImage] = [:]
    private var currentArtwork: UIImage?

    var currentTrack: Track? {
        queue.indices.contains(currentIndex) ? queue[currentIndex] : nil
    }

    var stateDescription: String {
        switch backend {
        case .soundEngine:
            return "EQ + Immersive active"
        case .avPlayer:
            return SoundSettings.shared.fxEnabled ? "Ready — download songs to enable FX" : "Standard"
        }
    }

    private override init() {
        super.init()
        configureAudioSession()
        addPeriodicTimeObserver()
        observeTrackEnd()
        observeInterruptions()
        setupRemoteCommands()
        observeSoundSettings()
    }

    // MARK: - Setup

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("FreeTune: audio session error \(error)")
        }
    }

    private func addPeriodicTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            if time.seconds.isFinite, time.seconds >= 0 {
                self.currentTime = time.seconds
            }
            if let item = self.avPlayer.currentItem {
                let d = item.duration.seconds
                if d.isFinite, d > 0, abs(self.duration - d) > 0.4 {
                    self.duration = d
                }
            }
        }
    }

    private func observeTrackEnd() {
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleTrackEnded()
        }
    }

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if rawType == AVAudioSession.InterruptionType.began.rawValue {
                self.pause()
            } else if rawType == AVAudioSession.InterruptionType.ended.rawValue {
                let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
                let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions ?? 0)
                if options.contains(.shouldResume) {
                    self.resume()
                }
            }
        }
    }

    private func observeSoundSettings() {
        soundSettingsObserver = SoundSettings.shared.objectWillChange
            .debounce(for: .milliseconds(80), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyLiveSoundSettings()
            }
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let target = positionEvent.positionTime
            DispatchQueue.main.async {
                self?.seek(to: target)
            }
            return .success
        }
    }

    // MARK: - Public controls

    func play(_ tracks: [Track], startIndex: Int) {
        guard !tracks.isEmpty else { return }
        originalQueue = tracks
        queue = tracks
        currentIndex = max(0, min(startIndex, tracks.count - 1))
        if isShuffleOn { applyShuffleKeepingCurrent() }
        startPlayback(resumeAt: 0)
    }

    func jumpTo(_ index: Int) {
        guard queue.indices.contains(index) else { return }
        currentIndex = index
        startPlayback(resumeAt: 0)
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { resume() }
    }

    func pause() {
        if backend == .soundEngine {
            soundEngine.pause()
        } else {
            avPlayer.pause()
        }
        isPlaying = false
        stopEngineTimer()
        updateNowPlayingInfo()
    }

    func resume() {
        guard currentTrack != nil else { return }
        if backend == .soundEngine {
            soundEngine.resume()
            startEngineTimer()
        } else {
            avPlayer.play()
        }
        isPlaying = true
        updateNowPlayingInfo()
    }

    func next() {
        if currentIndex < queue.count - 1 {
            currentIndex += 1
            startPlayback(resumeAt: 0)
        } else if isRepeatOn {
            currentIndex = 0
            startPlayback(resumeAt: 0)
        } else {
            pause()
            seek(to: 0)
        }
    }

    func previous() {
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        if currentIndex > 0 {
            currentIndex -= 1
            startPlayback(resumeAt: 0)
        } else {
            seek(to: 0)
        }
    }

    func toggleShuffle() {
        isShuffleOn.toggle()
        if isShuffleOn {
            applyShuffleKeepingCurrent()
        } else {
            restoreOriginalOrder()
        }
        updateNowPlayingInfo()
    }

    func toggleRepeat() {
        isRepeatOn.toggle()
    }

    func seek(to seconds: Double) {
        let clamped = max(0, seconds)
        if backend == .soundEngine {
            guard let track = currentTrack,
                  let local = DownloadManager.shared.localFileURL(for: track) else { return }
            scheduleEngineTrack(track: track, fileURL: local, resumeAt: clamped)
        } else {
            let time = CMTime(seconds: clamped, preferredTimescale: 600)
            avPlayer.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
            currentTime = clamped
        }
        updateNowPlayingInfo()
    }

    func stop() {
        pause()
        avPlayer.replaceCurrentItem(with: nil)
        soundEngine.stopAll()
        queue = []
        originalQueue = []
        currentIndex = 0
        currentTime = 0
        duration = 0
        currentArtwork = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Playback internals

    private func startPlayback(resumeAt: Double) {
        usedHiFiFallback = false
        guard let track = currentTrack else { return }
        playbackErrorMessage = nil
        isLoading = true
        currentTime = resumeAt
        duration = track.durationSeconds

        let localURL = DownloadManager.shared.localFileURL(for: track)
        let effectsOn = SoundSettings.shared.fxEnabled

        if let local = localURL, effectsOn {
            scheduleEngineTrack(track: track, fileURL: local, resumeAt: resumeAt)
        } else if let local = localURL {
            playWithAVPlayer(url: local, resumeAt: resumeAt)
        } else if let streamURL = track.audio {
            playWithAVPlayer(url: streamURL, resumeAt: resumeAt)
        } else {
            isLoading = false
            playbackErrorMessage = "This track has no playable audio."
        }
    }

    private func playWithAVPlayer(url: URL, resumeAt: Double) {
        stopEnginePlayback()
        backend = .avPlayer
        lastFXEnabled = false

        let item = AVPlayerItem(url: url)
        statusObservation?.cancel()
        statusObservation = item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self, self.avPlayer.currentItem === item else { return }
                if status == .failed {
                    self.handleAVPlayerFailure()
                }
            }

        avPlayer.replaceCurrentItem(with: item)
        avPlayer.play()
        if resumeAt > 0.5 {
            avPlayer.seek(
                to: CMTime(seconds: resumeAt, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
        }
        isPlaying = true
        isLoading = false
        updateNowPlayingInfo()
        if let track = currentTrack {
            loadArtwork(for: track)
        }
    }

    private func scheduleEngineTrack(track: Track, fileURL: URL, resumeAt: Double) {
        stopAVPlayerPlayback()
        backend = .soundEngine
        lastFXEnabled = true
        soundEngine.applySettings(SoundSettings.shared)
        engineGeneration += 1
        let generation = engineGeneration
        do {
            let fileDuration = try soundEngine.play(
                fileURL: fileURL,
                resumeAt: resumeAt,
                generation: generation
            ) { [weak self] finishedGeneration in
                DispatchQueue.main.async {
                    guard let self, finishedGeneration == self.engineGeneration else { return }
                    self.handleTrackEnded()
                }
            }
            duration = fileDuration
            engineSegmentStart = resumeAt
            currentTime = resumeAt
            isPlaying = true
            isLoading = false
            startEngineTimer()
            updateNowPlayingInfo()
            loadArtwork(for: track)
        } catch {
            playWithAVPlayer(url: fileURL, resumeAt: resumeAt)
        }
    }

    private func stopAVPlayerPlayback() {
        statusObservation?.cancel()
        statusObservation = nil
        avPlayer.replaceCurrentItem(with: nil)
    }

    private func stopEnginePlayback() {
        engineGeneration += 1
        soundEngine.stopAll()
        stopEngineTimer()
    }

    private func handleTrackEnded() {
        if isRepeatOn && queue.count == 1 {
            startPlayback(resumeAt: 0)
        } else {
            next()
        }
    }

    /// Hi-Res FLAC stream failed -> silently retry with the standard MP3 stream.
    private func handleAVPlayerFailure() {
        guard let track = currentTrack else {
            isLoading = false
            playbackErrorMessage = "This track couldn't be played. Try another."
            return
        }
        if track.source == .jamendo, SoundSettings.shared.hifi, !usedHiFiFallback {
            usedHiFiFallback = true
            isLoading = true
            loadStandardFallback(for: track)
        } else {
            isLoading = false
            playbackErrorMessage = "This track couldn't be played. Try another."
        }
    }

    private func loadStandardFallback(for track: Track) {
        Task {
            do {
                let rawID = track.id.replacingOccurrences(of: "jm-", with: "")
                let results = try await JamendoAPI.shared.fetchTracks(ids: [rawID])
                guard let standard = results.first else {
                    throw JamendoError.api(0, "track unavailable")
                }
                await MainActor.run {
                    if queue.indices.contains(currentIndex) {
                        queue[currentIndex] = standard
                    }
                    let resume = max(currentTime, 0)
                    if let local = DownloadManager.shared.localFileURL(for: standard) {
                        if SoundSettings.shared.fxEnabled {
                            scheduleEngineTrack(track: standard, fileURL: local, resumeAt: resume)
                        } else {
                            playWithAVPlayer(url: local, resumeAt: resume)
                        }
                    } else if let url = standard.audio {
                        playWithAVPlayer(url: url, resumeAt: resume)
                    } else {
                        isLoading = false
                        playbackErrorMessage = "This track couldn't be played."
                    }
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    playbackErrorMessage = "This track couldn't be played."
                }
            }
        }
    }

    /// Re-routes between AVPlayer and the DSP engine when FX settings change,
    /// keeping the current position. Also pushes live EQ updates.
    private func applyLiveSoundSettings() {
        let settings = SoundSettings.shared
        if backend == .soundEngine {
            soundEngine.applySettings(settings)
        }
        guard settings.fxEnabled != lastFXEnabled else { return }
        switch backend {
        case .soundEngine:
            if !settings.fxEnabled, let track = currentTrack,
               let local = DownloadManager.shared.localFileURL(for: track) {
                playWithAVPlayer(url: local, resumeAt: currentTime)
            }
        case .avPlayer:
            if settings.fxEnabled, let track = currentTrack,
               let local = DownloadManager.shared.localFileURL(for: track) {
                scheduleEngineTrack(track: track, fileURL: local, resumeAt: currentTime)
            }
        }
    }

    // MARK: - Shuffle / repeat helpers

    private func applyShuffleKeepingCurrent() {
        guard let current = currentTrack else { return }
        var rest = queue.filter { $0.id != current.id }
        rest.shuffle()
        queue = [current] + rest
        currentIndex = 0
    }

    private func restoreOriginalOrder() {
        guard let current = currentTrack else { return }
        if let index = originalQueue.firstIndex(where: { $0.id == current.id }) {
            queue = originalQueue
            currentIndex = index
        } else {
            queue = [current] + originalQueue
            currentIndex = 0
        }
    }

    // MARK: - Engine clock

    private func startEngineTimer() {
        stopEngineTimer()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.backend == .soundEngine, self.isPlaying else { return }
                if let position = self.soundEngine.currentPosition(segmentStart: self.engineSegmentStart) {
                    self.currentTime = position
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        engineTimer = timer
    }

    private func stopEngineTimer() {
        engineTimer?.invalidate()
        engineTimer = nil
    }

    // MARK: - Now Playing (lock screen)

    private func updateNowPlayingInfo() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.name,
            MPMediaItemPropertyArtist: track.artistName,
            MPMediaItemPropertyAlbumTitle: track.albumName ?? "",
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration: max(duration, track.durationSeconds)
        ]
        if let artwork = currentArtwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(
                boundsSize: artwork.size,
                requestHandler: { _ in artwork }
            )
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtwork(for track: Track) {
        if let cached = artworkCache[track.id] {
            currentArtwork = cached
            updateNowPlayingInfo()
            return
        }
        guard let url = track.bestArtwork else {
            currentArtwork = nil
            updateNowPlayingInfo()
            return
        }
        currentArtwork = nil
        updateNowPlayingInfo()
        Task {
            if let image = try? await ImageLoader.shared.image(from: url) {
                await MainActor.run {
                    self.artworkCache[track.id] = image
                    if self.currentTrack?.id == track.id {
                        self.currentArtwork = image
                        self.updateNowPlayingInfo()
                    }
                }
            }
        }
    }
}
