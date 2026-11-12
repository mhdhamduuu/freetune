import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel = TracksViewModel(source: .searchAll(""))
    @State private var query = ""
    @State private var recentSearches: [String] = []
    @State private var searchDebounce: Task<Void, Never>?

    private let recentsKey = "freetune.recentSearches"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    searchBar
                    if viewModel.tracks.isEmpty && query.isEmpty {
                        recentsSection
                        browseSection
                    } else {
                        TracksList(viewModel: viewModel, showsOnboardingGate: false)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .navigationTitle("Search")
            .onAppear {
                if recentSearches.isEmpty {
                    recentSearches = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
                }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Songs, artists, albums…", text: $query)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { runSearchNow() }
            if !query.isEmpty {
                Button {
                    query = ""
                    viewModel.showEmpty()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .onChange(of: query) { newValue in
            debounceSearch(newValue)
        }
    }

    private var recentsSection: some View {
        Group {
            if !recentSearches.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recent")
                        .font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(recentSearches, id: \.self) { recent in
                                Button {
                                    query = recent
                                    runSearch(query: recent)
                                } label: {
                                    Text(recent)
                                        .font(.footnote)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color(.secondarySystemBackground))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var browseSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Browse — Audius · works instantly")
                    .font(.headline)
                grid(genres: AudiusAPI.genres) { CatalogSource.audiusGenre($0) }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Browse — Jamendo · free downloads")
                    .font(.headline)
                grid(genres: GenrePalette.genres) { CatalogSource.jamendoGenre($0) }
            }
        }
        .padding(.horizontal)
    }

    private func grid(
        genres: [String],
        source: @escaping (String) -> CatalogSource
    ) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())],
            spacing: 10
        ) {
            ForEach(genres, id: \.self) { genre in
                Button {
                    query = ""
                    viewModel.updateSource(source(genre))
                } label: {
                    ZStack(alignment: .bottomLeading) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: GenrePalette.colors(for: genre),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(height: 86)
                        Text(genre)
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(10)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Search actions

    private func debounceSearch(_ newValue: String) {
        searchDebounce?.cancel()
        let trimmed = newValue.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            viewModel.showEmpty()
            return
        }
        searchDebounce = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                runSearch(query: trimmed)
            }
        }
    }

    private func runSearchNow() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        searchDebounce?.cancel()
        runSearch(query: trimmed)
    }

    private func runSearch(query term: String) {
        saveRecent(term)
        viewModel.updateSource(.searchAll(term))
    }

    private func saveRecent(_ term: String) {
        var list = recentSearches.filter { $0 != term }
        list.insert(term, at: 0)
        if list.count > 8 {
            list = Array(list.prefix(8))
        }
        recentSearches = list
        UserDefaults.standard.set(list, forKey: recentsKey)
    }
}
