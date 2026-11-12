import Foundation

enum AudiusError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Audius network is unreachable right now. Try again."
        }
    }
}

/// Audius — decentralized music platform with millions of full-length tracks
/// uploaded by artists. No API key needed (the app_name parameter identifies
/// the app). Streaming-only: Audius does not offer an official download API.
final class AudiusAPI {
    static let shared = AudiusAPI()

    private var cachedHost: String?
    private let appName = "FreeTune"

    static let genres = [
        "Electronic", "Hip-Hop/Rap", "Pop", "R&B/Soul", "Rock", "Metal",
        "Jazz", "Classical", "Reggae", "Folk", "Latin", "Lo-Fi"
    ]

    /// Audius redirects api.audius.co to a live discovery node.
    func host() async throws -> String {
        if let cachedHost { return cachedHost }
        struct HostList: Decodable { let data: [String]? }
        let (data, _) = try await URLSession.shared.data(
            from: URL(string: "https://api.audius.co")!
        )
        let decoded = try JSONDecoder().decode(HostList.self, from: data)
        guard let first = decoded.data?.first, !first.isEmpty else {
            throw AudiusError.unavailable
        }
        cachedHost = first
        return first
    }

    /// Trending tracks, genre filtering or full-text search.
    func fetchTracks(
        search: String? = nil,
        genre: String? = nil,
        timeRange: String? = nil,
        limit: Int = 30,
        offset: Int = 0
    ) async throws -> [Track] {
        let base = try await host()
        let isSearch = search?.isEmpty == false
        let path = isSearch ? "/v1/tracks/search" : "/v1/tracks/trending"

        var components = URLComponents(string: base + path)!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "app_name", value: appName),
            URLQueryItem(name: "limit", value: String(max(1, limit))),
            URLQueryItem(name: "offset", value: String(max(0, offset)))
        ]
        if let search, isSearch {
            items.append(URLQueryItem(name: "query", value: search))
        }
        if let genre, !genre.isEmpty {
            items.append(URLQueryItem(name: "genre", value: genre))
        }
        if let timeRange, !timeRange.isEmpty, !isSearch {
            items.append(URLQueryItem(name: "time", value: timeRange))
        }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw AudiusError.unavailable
        }

        let page = try JSONDecoder().decode(AudiusPage.self, from: data)
        return (page.data ?? []).compactMap { Self.map($0, host: base) }
    }

    // MARK: - Mapping

    private static func map(_ raw: AudiusRawTrack, host: String) -> Track? {
        guard !raw.id.isEmpty else { return nil }
        let stream = URL(string: "\(host)/v1/tracks/\(raw.id)/stream?app_name=FreeTune")
        let name = raw.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled"
        let artist = raw.user?.name.flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown Artist"
        return Track(
            id: "au-\(raw.id)",
            source: .audius,
            name: name,
            artistName: artist,
            albumName: nil,
            duration: raw.duration,
            image: raw.artwork?.small ?? raw.artwork?.medium,
            albumImage: raw.artwork?.large ?? raw.artwork?.medium,
            audio: stream,
            audioDownload: nil,
            audioDownloadAllowed: false,
            licenseURL: nil
        )
    }
}

// MARK: - Audius wire format

struct AudiusPage: Decodable {
    let data: [AudiusRawTrack]?
}

struct AudiusRawTrack: Decodable {
    let id: String
    let title: String?
    let duration: Int?
    let user: AudiusUser?
    let artwork: AudiusArtwork?

    struct AudiusUser: Decodable {
        let name: String?
    }

    struct AudiusArtwork: Decodable {
        let large: URL?
        let medium: URL?
        let small: URL?

        enum CodingKeys: String, CodingKey {
            case large = "1000x1000"
            case medium = "480x480"
            case small = "150x150"
        }
    }
}
