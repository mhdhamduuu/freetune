import Foundation
import Combine

/// Downloads songs (MP3 / FLAC) to a local folder for offline playback,
/// reports live progress, and keeps a persisted index of downloaded tracks.
final class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var downloads: [DownloadedTrack] = []
    @Published private(set) var activeProgress: [String: Double] = [:]
    @Published var lastErrorMessage: String?

    private var pendingTracks: [String: Track] = [:]
    private let indexKey = "freetune.downloads.index"

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 30 * 60
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    static var downloadsDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("Downloads", isDirectory: true)
    }

    private override init() {
        super.init()
        loadIndex()
    }

    // MARK: - Queries

    func localFileURL(for track: Track) -> URL? {
        let folder = Self.downloadsDirectory
        for candidate in ["\(track.id).flac", "\(track.id).mp3", "\(track.id).m4a"] {
            let url = folder.appendingPathComponent(candidate)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    func isDownloaded(_ track: Track) -> Bool {
        downloads.contains { $0.id == track.id }
    }

    func progress(for track: Track) -> Double? {
        activeProgress[track.id]
    }

    func download(for trackID: String) -> DownloadedTrack? {
        downloads.first { $0.id == trackID }
    }

    // MARK: - Actions

    func startDownload(_ track: Track) {
        guard track.downloadAllowed, !isDownloaded(track) else { return }
        guard activeProgress[track.id] == nil else { return }
        guard let url = track.audioDownload else {
            lastErrorMessage = "No download file is available for this track."
            return
        }
        try? FileManager.default.createDirectory(at: Self.downloadsDirectory, withIntermediateDirectories: true)

        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        let task = session.downloadTask(with: request)
        task.taskDescription = track.id
        task.resume()

        pendingTracks[track.id] = track
        activeProgress[track.id] = 0
    }

    func cancelDownload(_ trackID: String) {
        session.getAllTasks { tasks in
            if let task = tasks.first(where: { $0.taskDescription == trackID }) {
                task.cancel()
            }
        }
    }

    func deleteDownload(_ record: DownloadedTrack) {
        let url = Self.downloadsDirectory.appendingPathComponent(record.fileName)
        try? FileManager.default.removeItem(at: url)
        DispatchQueue.main.async {
            self.downloads.removeAll { $0.id == record.id }
            self.saveIndex()
        }
    }

    // MARK: - Persistence

    private func loadIndex() {
        try? FileManager.default.createDirectory(at: Self.downloadsDirectory, withIntermediateDirectories: true)
        guard let data = UserDefaults.standard.data(forKey: indexKey) else { return }
        if let decoded = try? JSONDecoder().decode([DownloadedTrack].self, from: data) {
            let fileManager = FileManager.default
            downloads = decoded.filter {
                fileManager.fileExists(atPath: Self.downloadsDirectory.appendingPathComponent($0.fileName).path)
            }
        }
    }

    private func saveIndex() {
        if let data = try? JSONEncoder().encode(downloads) {
            UserDefaults.standard.set(data, forKey: indexKey)
        }
    }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let trackID = downloadTask.taskDescription else { return }
        let fraction = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0
        DispatchQueue.main.async {
            self.activeProgress[trackID] = fraction
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let trackID = downloadTask.taskDescription,
              let track = pendingTracks[trackID] else { return }

        try? FileManager.default.createDirectory(at: Self.downloadsDirectory, withIntermediateDirectories: true)

        let extensionFromURL = track.audioDownload?.pathExtension ?? ""
        let fileExtension = extensionFromURL.isEmpty ? "mp3" : extensionFromURL
        let destination = Self.downloadsDirectory.appendingPathComponent("\(trackID).\(fileExtension)")

        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }

        do {
            try FileManager.default.moveItem(at: location, to: destination)
            var fileSize: Int64 = 0
            if let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path) {
                fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            }
            let record = DownloadedTrack(
                track: track,
                fileName: destination.lastPathComponent,
                downloadedAt: Date(),
                fileSize: fileSize
            )
            DispatchQueue.main.async {
                self.pendingTracks.removeValue(forKey: trackID)
                self.activeProgress.removeValue(forKey: trackID)
                self.downloads.removeAll { $0.id == trackID }
                self.downloads.insert(record, at: 0)
                self.saveIndex()
                Haptics.success()
            }
        } catch {
            DispatchQueue.main.async {
                self.pendingTracks.removeValue(forKey: trackID)
                self.activeProgress.removeValue(forKey: trackID)
                self.lastErrorMessage = "Could not save download: \(error.localizedDescription)"
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        guard let trackID = task.taskDescription else { return }
        let cancelled = (error as NSError).code == NSURLErrorCancelled
        DispatchQueue.main.async {
            self.pendingTracks.removeValue(forKey: trackID)
            self.activeProgress.removeValue(forKey: trackID)
            if !cancelled {
                self.lastErrorMessage = "Download failed: \(error.localizedDescription)"
            }
        }
    }
}
