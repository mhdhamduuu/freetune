import Foundation
import Combine

enum RadioDownloadState: Equatable {
    case idle
    case downloading
    case paused
}

/// Downloads radio programme audio files into the app sandbox with live
/// progress, pause and resume support.
///
/// Permission rules baked into this manager:
///  - It never records or captures live radio streams. It downloads only
///    static audio files published for download by the app's authorized
///    catalog (Internet Archive public-archive programme collections).
///  - Every download URL is validated against the authorized archive hosts
///    and the track's source before a task may start.
///
/// Pause/resume uses URLSession's resume-data mechanism; pending resume
/// data is persisted in the sandbox so paused downloads survive relaunches.
final class RadioDownloadManager: NSObject, ObservableObject {
    static let shared = RadioDownloadManager()

    @Published private(set) var progress: [String: Double] = [:]
    @Published private(set) var states: [String: RadioDownloadState] = [:]
    @Published var lastErrorMessage: String?

    private var pendingTracks: [String: Track] = [:]
    private var resumeData: [String: Data] = [:]

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60 * 60
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private override init() {
        super.init()
        try? FileManager.default.createDirectory(
            at: OfflineRadioStorage.pendingDirectory,
            withIntermediateDirectories: true
        )
        loadPersistedPending()
    }

    // MARK: - Authorization gate

    private func isAuthorized(_ track: Track) -> Bool {
        guard track.source == .archive,
              let host = track.audioDownload?.host?.lowercased() else { return false }
        return host == "archive.org" || host.hasSuffix(".archive.org")
    }

    // MARK: - Actions

    func startDownload(_ track: Track) {
        guard isAuthorized(track) else {
            lastErrorMessage = "This programme is not from an authorized downloadable catalog."
            return
        }
        guard let url = track.audioDownload else {
            lastErrorMessage = "No downloadable file is available for this programme."
            return
        }
        guard OfflineRadioStorage.shared.episode(for: track.id) == nil,
              states[track.id] == nil else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        let task = session.downloadTask(with: request)
        task.taskDescription = track.id
        task.resume()

        pendingTracks[track.id] = track
        states[track.id] = .downloading
        progress[track.id] = 0
    }

    func pauseDownload(_ trackID: String) {
        session.getAllTasks { tasks in
            let task = tasks.first(where: { $0.taskDescription == trackID }) as? URLSessionDownloadTask
            DispatchQueue.main.async {
                guard let task else {
                    if self.resumeData[trackID] != nil { self.states[trackID] = .paused }
                    return
                }
                task.cancel { data in
                    DispatchQueue.main.async {
                        if let data, !data.isEmpty {
                            self.resumeData[trackID] = data
                            self.persistPending(trackID: trackID, resumeData: data)
                            self.states[trackID] = .paused
                        } else {
                            self.states[trackID] = nil
                            self.progress[trackID] = nil
                            self.pendingTracks[trackID] = nil
                        }
                    }
                }
            }
        }
    }

    func resumeDownload(_ trackID: String) {
        guard states[trackID] == .paused else { return }
        let data = resumeData[trackID]
        guard let data else {
            // Resume data was lost (e.g. the source file changed) — restart.
            if let track = pendingTracks[trackID] {
                states[trackID] = nil
                removePending(trackID: trackID)
                startDownload(track)
            } else {
                states[trackID] = nil
                removePending(trackID: trackID)
                lastErrorMessage = "Couldn't resume this download. Please start it again from the catalog."
            }
            return
        }

        let task = session.downloadTask(withResumeData: data)
        task.taskDescription = trackID
        task.resume()
        states[trackID] = .downloading
    }

    func cancelDownload(_ trackID: String) {
        session.getAllTasks { tasks in
            if let task = tasks.first(where: { $0.taskDescription == trackID }) {
                task.cancel()
            }
        }
        DispatchQueue.main.async {
            self.resumeData[trackID] = nil
            self.progress[trackID] = nil
            self.states[trackID] = nil
            self.pendingTracks[trackID] = nil
            self.removePending(trackID: trackID)
        }
    }

    // MARK: - Pending persistence (paused downloads survive relaunch)

    private struct PendingDownload: Codable {
        let track: Track
        let resumeData: Data
    }

    private func persistPending(trackID: String, resumeData data: Data) {
        guard let track = pendingTracks[trackID] else { return }
        let pending = PendingDownload(track: track, resumeData: data)
        if let encoded = try? JSONEncoder().encode(pending) {
            let url = OfflineRadioStorage.pendingDirectory.appendingPathComponent("\(trackID).resume")
            try? encoded.write(to: url)
        }
    }

    private func removePending(trackID: String) {
        let url = OfflineRadioStorage.pendingDirectory.appendingPathComponent("\(trackID).resume")
        try? FileManager.default.removeItem(at: url)
    }

    private func loadPersistedPending() {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: OfflineRadioStorage.pendingDirectory,
            includingPropertiesForKeys: nil
        ) else { return }

        for file in files where file.pathExtension == "resume" {
            let trackID = file.deletingPathExtension().lastPathComponent
            if let data = try? Data(contentsOf: file),
               let pending = try? JSONDecoder().decode(PendingDownload.self, from: data) {
                resumeData[trackID] = pending.resumeData
                pendingTracks[trackID] = pending.track
                states[trackID] = .paused
            }
        }
    }
}

// MARK: - URLSessionDownloadDelegate

extension RadioDownloadManager: URLSessionDownloadDelegate {
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
            self.progress[trackID] = fraction
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let trackID = downloadTask.taskDescription,
              let track = pendingTracks[trackID] else { return }
        DispatchQueue.main.async {
            self.finishDownload(trackID: trackID, track: track, location: location)
        }
    }

    private func finishDownload(trackID: String, track: Track, location: URL) {
        let destination = OfflineRadioStorage.downloadsDirectory.appendingPathComponent("\(trackID).mp3")
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }

        do {
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            lastErrorMessage = "Couldn't save the programme. Try again."
            states[trackID] = nil
            progress[trackID] = nil
            pendingTracks[trackID] = nil
            return
        }

        var fileSize: Int64 = 0
        if let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path) {
            fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        }

        OfflineRadioStorage.shared.addEpisode(track: track, fileSize: fileSize, duration: track.durationSeconds)

        states[trackID] = nil
        progress[trackID] = nil
        pendingTracks[trackID] = nil
        resumeData[trackID] = nil
        removePending(trackID: trackID)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        guard let trackID = task.taskDescription else { return }
        let cancelled = (error as NSError).code == NSURLErrorCancelled

        DispatchQueue.main.async {
            if cancelled {
                // Pause handles its own state; just don't leave a stuck spinner.
                if self.states[trackID] == .downloading {
                    self.states[trackID] = nil
                    self.progress[trackID] = nil
                }
            } else {
                self.states[trackID] = nil
                self.progress[trackID] = nil
                self.pendingTracks[trackID] = nil
                self.lastErrorMessage = "Download failed. Check your connection and try again."
            }
        }
    }
}
