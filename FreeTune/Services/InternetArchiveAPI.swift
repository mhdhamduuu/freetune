import Foundation

enum ArchiveError: LocalizedError {
    case http(Int)
    case unreachable

    var errorDescription: String? {
        switch self {
        case .http(let code):
            return "Internet Archive server error (\(code)). Try again."
        case .unreachable:
            return "Couldn't load Internet Archive files. Check your connection."
        }
    }
}

/// Client for the Internet Archive (archive.org) audio catalogs.
/// Everything exposed here is free-to-share music:
///   - "netlabels"   — the Netlabels community (Creative Commons releases)
///   - "musopen"     — Musopen's public-domain classical recordings
///   - "georgeblood" — the Great 78 Project (preserved vintage 78 rpm records)
/// Items are plain MP3s, so the streaming URL doubles as the download URL.
final class InternetArchiveAPI {
    static let shared = InternetArchiveAPI()

    private let searchURL = URL(string: "https://archive.org/advancedsearch.php")!
    private let metadataBase = URL(string: "https://archive.org/metadata")!

    // MARK: - Catalog browsing (paginated)

    func fetchCollectionTracks(
        collection: String,
        extraQuery: String? = nil,
        limit: Int,
        offset: Int
    ) async throws -> [Track] {
        var query = "collection:(\(collection)) AND mediatype:(audio) AND format:(MP3)"
        if let extraQuery, !extraQuery.isEmpty {
            query += " AND \(extraQuery)"
        }
        let identifiers = try await searchIdentifiers(query: query, limit: limit, offset: offset)
        let tracks = await resolveTracks(identifiers: identifiers)
        if identifiers.isEmpty == false, tracks.isEmpty {
            throw ArchiveError.unreachable
        }
        return tracks
    }

    // MARK: - Keyword search (bonus catalog, explicitly CC-licensed items only)

    func fetchCCTracks(search: String, limit: Int) async throws -> [Track] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        let query = "(\(term)) AND mediatype:(audio) AND format:(MP3) AND licenseurl:*creativecommons*"
        let identifiers = try await searchIdentifiers(query: query, limit: limit, offset: 0)
        return await resolveTracks(identifiers: identifiers)
    }

    // MARK: - Search endpoint

    private func searchIdentifiers(query: String, limit: Int, offset: Int) async throws -> [String] {
        var components = URLComponents(url: searchURL, resolvingAgainstBaseURL: false)!
        let page = offset / max(limit, 1) + 1
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fl[]", value: "identifier"),
            URLQueryItem(name: "fl[]", value: "title"),
            URLQueryItem(name: "fl[]", value: "creator"),
            URLQueryItem(name: "rows", value: String(max(1, limit))),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "sort[]", value: "downloads desc"),
            URLQueryItem(name: "output", value: "json")
        ]

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ArchiveError.http(http.statusCode)
        }
        let pageData = try JSONDecoder().decode(ArchiveSearchPage.self, from: data)
        return pageData.response.docs.map { $0.identifier }
    }

    // MARK: - Item resolution (search docs list items; each item names its files)

    private func resolveTracks(identifiers: [String]) async -> [Track] {
        var resolved: [Int: Track?] = [:]
        await withTaskGroup(of: (Int, Track?).self) { group in
            for (index, identifier) in identifiers.enumerated() {
                group.addTask { [self] in
                    (index, (try? await itemTrack(identifier: identifier)) ?? nil)
                }
            }
            for await result in group {
                resolved[result.0] = result.1
            }
        }
        return resolved
            .sorted { $0.key < $1.key }
            .compactMap { $0.value }
    }

    private func itemTrack(identifier: String) async throws -> Track? {
        var request = URLRequest(url: metadataBase.appendingPathComponent(identifier))
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ArchiveError.http(http.statusCode)
        }
        let metadata = try JSONDecoder().decode(ArchiveItemMetadata.self, from: data)

        // Prefer the VBR MP3 derivative, fall back to the first MP3 present.
        let mp3 = metadata.files
            .filter { $0.name.lowercased().hasSuffix(".mp3") }
            .first { $0.format?.lowercased().contains("vbr") == true }
            ?? metadata.files.first { $0.name.lowercased().hasSuffix(".mp3") }
        guard let mp3 else { return nil }

        let encodedName = mp3.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? mp3.name
        guard let audioURL = URL(string: "https://archive.org/download/\(identifier)/\(encodedName)") else {
            return nil
        }

        let duration = ArchiveDurationParser.seconds(mp3.length)
            ?? ArchiveDurationParser.seconds(metadata.metadata?.length)
        let title = mp3.title?.isEmpty == false
            ? mp3.title!
            : (metadata.metadata?.title ?? identifier)
        let creator = metadata.metadata?.creator.flatMap { creatorValue -> String? in
            switch creatorValue {
            case .text(let text): return text
            case .list(let values): return values.first
            }
        }

        return Track.archive(
            identifier: identifier,
            title: title,
            creator: creator,
            duration: duration,
            audioURL: audioURL
        )
    }
}

// MARK: - Wire formats

struct ArchiveSearchPage: Decodable {
    struct ResponseBlock: Decodable {
        let docs: [ArchiveSearchDoc]
        let numFound: Int?
    }
    let response: ResponseBlock
}

struct ArchiveSearchDoc: Decodable {
    let identifier: String
    let title: String?
    let creator: ArchiveTextList?
}

/// Archive fields are sometimes a single string, sometimes a list.
enum ArchiveTextList: Decodable, Hashable {
    case text(String)
    case list([String])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let single = try? container.decode(String.self) {
            self = .text(single)
        } else if let multiple = try? container.decode([String].self) {
            self = .list(multiple)
        } else {
            self = .text("")
        }
    }
}

struct ArchiveItemMetadata: Decodable {
    struct ItemMetadata: Decodable {
        let title: String?
        let creator: ArchiveTextList?
        let length: String?
    }
    struct ItemFile: Decodable {
        let name: String
        let format: String?
        let title: String?
        let length: String?
    }
    let metadata: ItemMetadata?
    let files: [ItemFile]
}

// MARK: - Duration parsing ("203.55" or "3:23" or "1:02:03")

enum ArchiveDurationParser {
    static func seconds(_ raw: String?) -> Int? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }

        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":").compactMap { Double($0) }
            guard !parts.isEmpty, parts.allSatisfy({ $0.isFinite }) else { return nil }
            var total = 0.0
            for part in parts { total = total * 60 + part }
            return total.isFinite && total >= 0 ? Int(total.rounded()) : nil
        }

        guard let value = Double(trimmed), value.isFinite, value >= 0 else { return nil }
        return Int(value.rounded())
    }
}
