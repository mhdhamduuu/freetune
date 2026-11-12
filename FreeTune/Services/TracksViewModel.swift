import Foundation
import Combine

enum CatalogSource: Equatable {
    case jamendoTrending
    case jamendoGenre(String)
    case audiusTrending
    case audiusGenre(String)
    case audiusFresh(String)   // trending window: week / month / year
    case archiveCollection(String)  // Internet Archive free-music collection
    case archiveIndia78s            // vintage Indian-language 78 rpm records
    case searchAll(String)

    var isSearch: Bool {
        if case .searchAll = self { return true }
        return false
    }
}

/// Paginated list loader for all three catalogs. Search queries Jamendo,
/// Audius and the Internet Archive in parallel and merges the results.
@MainActor
final class TracksViewModel: ObservableObject {
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private var source: CatalogSource
    private var offset = 0
    private var canLoadMore = true
    private var loadTask: Task<Void, Never>?
    private let pageSize = 30

    init(source: CatalogSource) {
        self.source = source
        if source.isSearch {
            canLoadMore = false
        }
    }

    var isSearch: Bool { source.isSearch }

    /// True when the current listing comes from the key-protected Jamendo catalog.
    var needsJamendoKey: Bool {
        switch source {
        case .jamendoTrending, .jamendoGenre:
            return true
        default:
            return false
        }
    }

    func updateSource(_ newSource: CatalogSource, force: Bool = false) {
        if source == newSource && !force { return }
        source = newSource
        reload()
    }

    func reload() {
        loadTask?.cancel()
        offset = 0
        canLoadMore = true
        tracks = []
        errorMessage = nil
        loadTask = Task { await load(reset: true) }
    }

    func reloadNow() async {
        loadTask?.cancel()
        offset = 0
        canLoadMore = true
        errorMessage = nil
        await load(reset: true)
    }

    func showEmpty() {
        loadTask?.cancel()
        tracks = []
        errorMessage = nil
        canLoadMore = false
    }

    func loadMoreIfNeeded(current track: Track) {
        guard canLoadMore, !isLoading, track.id == tracks.last?.id else { return }
        loadTask = Task { await load(reset: false) }
    }

    private func load(reset: Bool) async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let results = try await performFetch(offset: offset, limit: pageSize)
            if Task.isCancelled { return }
            tracks = reset ? results : tracks + results
            offset += results.count
            canLoadMore = source.isSearch ? false : results.count >= pageSize
        } catch {
            if Task.isCancelled { return }
            if let jamendoError = error as? JamendoError {
                errorMessage = jamendoError.localizedDescription
            } else if let audiusError = error as? AudiusError {
                errorMessage = audiusError.localizedDescription
            } else if (error as NSError).code != NSURLErrorCancelled {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func performFetch(offset: Int, limit: Int) async throws -> [Track] {
        let audioformat = SoundSettings.shared.hifi ? "flac" : nil
        switch source {
        case .jamendoTrending:
            return try await JamendoAPI.shared.fetchTracks(
                order: "popularity_week",
                limit: limit,
                offset: offset,
                audioformat: audioformat
            )
        case .jamendoGenre(let tag):
            return try await JamendoAPI.shared.fetchTracks(
                tags: tag,
                order: "popularity_total",
                limit: limit,
                offset: offset,
                audioformat: audioformat
            )
        case .audiusTrending:
            return try await AudiusAPI.shared.fetchTracks(limit: limit, offset: offset)
        case .audiusGenre(let genre):
            return try await AudiusAPI.shared.fetchTracks(
                genre: genre,
                limit: limit,
                offset: offset
            )
        case .audiusFresh(let range):
            return try await AudiusAPI.shared.fetchTracks(
                timeRange: range,
                limit: limit,
                offset: offset
            )
        case .archiveCollection(let collection):
            return try await InternetArchiveAPI.shared.fetchCollectionTracks(
                collection: collection,
                limit: limit,
                offset: offset
            )
        case .archiveIndia78s:
            return try await InternetArchiveAPI.shared.fetchCollectionTracks(
                collection: "georgeblood",
                extraQuery: "(malayalam OR hindi OR tamil OR telugu)",
                limit: limit,
                offset: offset
            )
        case .searchAll(let query):
            // Deeper page for keyword channels/search: 100 per catalog.
            return try await searchBoth(query: query, limit: 100)
        }
    }

    /// Jamendo + Audius + Internet Archive in parallel. If one catalog fails
    /// (e.g. no key yet), results from the other catalogs are still returned.
    private func searchBoth(query: String, limit: Int) async throws -> [Track] {
        let jamendoTask = Task { () -> [Track] in
            let audioformat = SoundSettings.shared.hifi ? "flac" : nil
            return try await JamendoAPI.shared.fetchTracks(
                search: query,
                limit: limit,
                audioformat: audioformat
            )
        }
        let audiusTask = Task { () -> [Track] in
            try await AudiusAPI.shared.fetchTracks(search: query, limit: limit)
        }
        let archiveTask = Task { () -> [Track] in
            try await InternetArchiveAPI.shared.fetchCCTracks(search: query, limit: 30)
        }

        var results: [Track] = []
        var firstError: Error?
        do {
            results += try await jamendoTask.value
        } catch {
            firstError = firstError ?? error
        }
        do {
            results += try await audiusTask.value
        } catch {
            firstError = firstError ?? error
        }
        do {
            results += try await archiveTask.value
        } catch {
            // Archive is a bonus catalog — never block search results on it.
        }

        if results.isEmpty, let error = firstError {
            throw error
        }
        return results
    }
}
