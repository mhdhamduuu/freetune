import Foundation

enum JamendoError: LocalizedError {
    case missingKey
    case http(Int)
    case api(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "Add your free Jamendo API key in Settings to browse Jamendo music. (Audius works without any key!)"
        case .http(let code):
            return "Jamendo server error (\(code)). Try again."
        case .api(let code, let message):
            return "Jamendo API error \(code): \(message)"
        }
    }
}

/// Client for the Jamendo public music API (https://dev.jamendo.com).
/// Jamendo hosts 600,000+ Creative Commons tracks and legally allows downloads.
final class JamendoAPI {
    static let shared = JamendoAPI()

    /// OPTIONAL: hardcode your own client ID here before building so Jamendo
    /// works out of the box. Get one free at https://dev.jamendo.com
    static let bundledClientID = ""

    private let baseURL = URL(string: "https://api.jamendo.com/v3.0")!

    var clientID: String {
        let saved = UserDefaults.standard.string(forKey: "freetune.jamendo.clientid") ?? ""
        if !saved.isEmpty { return saved }
        return Self.bundledClientID
    }

    func fetchTracks(
        ids: [String]? = nil,
        search: String? = nil,
        tags: String? = nil,
        order: String? = nil,
        limit: Int = 30,
        offset: Int = 0,
        audioformat: String? = nil
    ) async throws -> [Track] {
        let key = clientID
        guard !key.isEmpty else { throw JamendoError.missingKey }

        var components = URLComponents(
            url: baseURL.appendingPathComponent("tracks"),
            resolvingAgainstBaseURL: false
        )!

        var items: [URLQueryItem] = [
            URLQueryItem(name: "client_id", value: key),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "limit", value: String(max(1, limit))),
            URLQueryItem(name: "offset", value: String(max(0, offset)))
        ]
        if let ids, !ids.isEmpty {
            items.append(URLQueryItem(name: "id", value: ids.joined(separator: ",")))
        }
        if let search {
            let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                items.append(URLQueryItem(name: "search", value: trimmed))
            }
        }
        if let tags { items.append(URLQueryItem(name: "tags", value: tags)) }
        if let order { items.append(URLQueryItem(name: "order", value: order)) }
        if let audioformat { items.append(URLQueryItem(name: "audioformat", value: audioformat)) }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw JamendoError.http(http.statusCode)
        }

        let page = try JSONDecoder().decode(JamendoPage.self, from: data)
        if let headers = page.headers, let code = headers.code, code != 0 {
            throw JamendoError.api(code, headers.status ?? "API error")
        }
        return (page.results ?? []).map { Track.jamendo($0) }
    }
}
