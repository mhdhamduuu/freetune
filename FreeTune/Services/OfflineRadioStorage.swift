import Foundation
import Combine

/// One saved (downloaded) radio programme in the offline library.
struct SavedRadioEpisode: Identifiable, Codable, Hashable {
    let track: Track
    let fileName: String
    let downloadedAt: Date
    let fileSize: Int64
    var lastPlayedAt: Date?
    var resumePosition: Double?
    var durationSeconds: Double?

    var id: String { track.id }
}

/// Sandbox storage for the offline radio library:
///  - index of downloaded programmes (persisted),
///  - recently-played tracking + resume positions,
///  - disk-space queries.
///
/// Files are stored in the app sandbox under Documents/Downloads as
/// "<track id>.mp3" — the same folder the music downloader uses — so the
/// existing PlayerManager treats saved programmes as plain local files and
/// plays them with zero special cases (AVPlayer, lock screen, mini player,
/// background audio all keep working).
final class OfflineRadioStorage: ObservableObject {
    static let shared = OfflineRadioStorage()

    @Published private(set) var episodes: [SavedRadioEpisode] = []

    private let libraryKey = "freetune.radio.library"

    private init() {
        loadLibrary()
    }

    // MARK: - Folders (all inside the app sandbox)

    static var downloadsDirectory: URL { DownloadManager.downloadsDirectory }

    /// Where in-flight download resume data is kept between sessions.
    static var pendingDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("RadioPending", isDirectory: true)
    }

    // MARK: - Library persistence

    private func loadLibrary() {
        guard let data = UserDefaults.standard.data(forKey: libraryKey),
              let decoded = try? JSONDecoder().decode([SavedRadioEpisode].self, from: data) else { return }
        let fileManager = FileManager.default
        episodes = decoded.filter {
            fileManager.fileExists(atPath: Self.downloadsDirectory.appendingPathComponent($0.fileName).path)
        }
    }

    private func saveLibrary() {
        if let data = try? JSONEncoder().encode(episodes) {
            UserDefaults.standard.set(data, forKey: libraryKey)
        }
    }

    // MARK: - Queries

    func episode(for trackID: String) -> SavedRadioEpisode? {
        episodes.first { $0.id == trackID }
    }

    func localFileURL(for trackID: String) -> URL? {
        let url = Self.downloadsDirectory.appendingPathComponent("\(trackID).mp3")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var recentlyPlayed: [SavedRadioEpisode] {
        episodes
            .filter { $0.lastPlayedAt != nil }
            .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
    }

    var librarySizeBytes: Int64 {
        episodes.reduce(0) { $0 + $1.fileSize }
    }

    /// Free space on the volume that hosts the app sandbox.
    static func freeDiskSpaceBytes() -> Int64 {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let values = try? documents.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return Int64(values?.volumeAvailableCapacityForImportantUsage ?? 0)
    }

    // MARK: - Library changes

    func addEpisode(track: Track, fileSize: Int64, duration: Double?) {
        let fileManager = FileManager.default
        let fileName = "\(track.id).mp3"
        guard fileManager.fileExists(atPath: Self.downloadsDirectory.appendingPathComponent(fileName).path) else { return }
        guard !episodes.contains(where: { $0.id == track.id }) else { return }

        let record = SavedRadioEpisode(
            track: track,
            fileName: fileName,
            downloadedAt: Date(),
            fileSize: fileSize,
            lastPlayedAt: nil,
            resumePosition: nil,
            durationSeconds: duration
        )
        episodes.insert(record, at: 0)
        saveLibrary()
    }

    func removeEpisode(_ record: SavedRadioEpisode) {
        try? FileManager.default.removeItem(at: Self.downloadsDirectory.appendingPathComponent(record.fileName))
        episodes.removeAll { $0.id == record.id }
        saveLibrary()
    }

    // MARK: - Play tracking (recently played + resume position)

    func markPlayed(trackID: String) {
        guard let index = episodes.firstIndex(where: { $0.id == trackID }) else { return }
        episodes[index].lastPlayedAt = Date()
        saveLibrary()
    }

    func savePosition(trackID: String, position: Double, duration: Double?) {
        guard let index = episodes.firstIndex(where: { $0.id == trackID }) else { return }
        episodes[index].resumePosition = position
        if let duration, duration > 0 {
            episodes[index].durationSeconds = duration
        }
        saveLibrary()
    }

    func clearPosition(trackID: String) {
        guard let index = episodes.firstIndex(where: { $0.id == trackID }) else { return }
        episodes[index].resumePosition = nil
        saveLibrary()
    }
}
