import Foundation

// MARK: - Sources

enum TrackSource: String, Codable, Hashable {
    case jamendo
    case audius
    case archive
}

// MARK: - Jamendo raw wire format

struct JamendoHeaders: Decodable {
    let status: String?
    let code: Int?
    let resultsCount: Int?
}

struct JamendoRawTrack: Decodable, Hashable {
    let id: String
    let name: String
    let duration: Int?
    let artistName: String
    let artistImage: URL?
    let albumName: String?
    let albumImage: URL?
    let image: URL?
    let audio: URL?
    let audioDownload: URL?
    let audioDownloadAllowed: Bool?
    let licenseURL: String?

    enum CodingKeys: String, CodingKey {
        case id, name, duration, audio, image
        case artistName = "artist_name"
        case artistImage = "artist_image"
        case albumName = "album_name"
        case albumImage = "album_image"
        case audioDownload = "audiodownload"
        case audioDownloadAllowed = "audiodownload_allowed"
        case licenseURL = "license_ccurl"
    }
}

struct JamendoPage: Decodable {
    let headers: JamendoHeaders?
    let results: [JamendoRawTrack]?
}

// MARK: - Universal track (every source maps into this)

struct Track: Identifiable, Codable, Hashable {
    let id: String
    let source: TrackSource
    let name: String
    let artistName: String
    let albumName: String?
    let duration: Int?
    let image: URL?
    let albumImage: URL?
    let audio: URL?
    let audioDownload: URL?
    let audioDownloadAllowed: Bool
    let licenseURL: String?

    var durationSeconds: Double { Double(duration ?? 0) }

    var downloadAllowed: Bool { audioDownloadAllowed && audioDownload != nil }

    var bestArtwork: URL? { albumImage ?? image }

    static func jamendo(_ raw: JamendoRawTrack) -> Track {
        Track(
            id: "jm-\(raw.id)",
            source: .jamendo,
            name: raw.name,
            artistName: raw.artistName,
            albumName: raw.albumName,
            duration: raw.duration,
            image: raw.image,
            albumImage: raw.albumImage,
            audio: raw.audio,
            audioDownload: raw.audioDownload,
            audioDownloadAllowed: raw.audioDownloadAllowed ?? true,
            licenseURL: raw.licenseURL
        )
    }

    /// Internet Archive item — identifier + the item's best MP3 file.
    /// Archive files are free-to-share, so the stream URL is also the download.
    static func archive(
        identifier: String,
        title: String,
        creator: String?,
        duration: Int?,
        audioURL: URL?
    ) -> Track {
        let artwork = URL(string: "https://archive.org/services/img/\(identifier)")
        let artist = creator.flatMap { value in
            value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
        } ?? "Internet Archive"
        return Track(
            id: "ia-\(identifier)",
            source: .archive,
            name: title,
            artistName: artist,
            albumName: title,
            duration: duration,
            image: artwork,
            albumImage: artwork,
            audio: audioURL,
            audioDownload: audioURL,
            audioDownloadAllowed: true,
            licenseURL: nil
        )
    }

    static let placeholder = Track(
        id: "0",
        source: .jamendo,
        name: "Nothing Playing",
        artistName: "FreeTune",
        albumName: nil,
        duration: 0,
        image: nil,
        albumImage: nil,
        audio: nil,
        audioDownload: nil,
        audioDownloadAllowed: false,
        licenseURL: nil
    )
}

// MARK: - Downloaded track (offline library entry)

struct DownloadedTrack: Identifiable, Codable, Hashable {
    let track: Track
    let fileName: String
    let downloadedAt: Date
    let fileSize: Int64

    var id: String { track.id }

    var isHiRes: Bool { fileName.lowercased().hasSuffix(".flac") }
}
