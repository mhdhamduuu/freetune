import SwiftUI

struct HomeView: View {
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var viewModel = TracksViewModel(source: .audiusTrending)
    @State private var selectedGenre: String? = nil
    @State private var activeSpecial: String? = nil
    @State private var provider: MusicProvider = .audius

    /// Instant channels at the top of the chip row.
    enum QuickChannel {
        case fresh(String)      // Audius live trending window
        case search(String)     // keyword search across both catalogs
    }

    private let quickChannels: [(title: String, channel: QuickChannel)] = [
        ("New This Week", .fresh("week")),
        ("New This Month", .fresh("month")),
        ("New This Year", .fresh("year")),
        ("Malayalam", .search("malayalam")),
        ("Malayalam Rap", .search("malayalam rap")),
        ("Mollywood Covers", .search("malayalam cover")),
        ("Kerala", .search("kerala")),
        ("Devotional", .search("devotional")),
        ("Tamil", .search("tamil"))
    ]

    enum MusicProvider: String, CaseIterable, Identifiable {
        case audius = "Audius"
        case jamendo = "Jamendo"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    providerPicker
                    if let top = viewModel.tracks.first {
                        HeroCard(track: top, tracks: viewModel.tracks)
                    }
                    genreChips
                    TracksList(viewModel: viewModel)
                }
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .refreshable {
                await viewModel.reloadNow()
            }
            .navigationTitle("Listen Now")
            .task(id: settings.keyVersion) {
                applySelection(force: true)
            }
        }
    }

    private func applySelection(force: Bool) {
        let target: CatalogSource
        if provider == .jamendo {
            target = selectedGenre.map { CatalogSource.jamendoGenre($0) } ?? .jamendoTrending
        } else {
            target = selectedGenre.map { CatalogSource.audiusGenre($0) } ?? .audiusTrending
        }
        viewModel.updateSource(target, force: force)
    }

    private var providerPicker: some View {
        Picker("Catalog", selection: $provider) {
            ForEach(MusicProvider.allCases) { item in
                Text(item.rawValue).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .onChange(of: provider) { _ in
            selectedGenre = nil
            activeSpecial = nil
            applySelection(force: true)
        }
    }

    private var genreChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(quickChannels, id: \.title) { entry in
                    chip(title: entry.title, active: activeSpecial == entry.title) {
                        activeSpecial = entry.title
                        selectedGenre = nil
                        switch entry.channel {
                        case .fresh(let range):
                            viewModel.updateSource(.audiusFresh(range), force: true)
                        case .search(let term):
                            viewModel.updateSource(.searchAll(term), force: true)
                        }
                    }
                }
                chip(title: "Trending", active: activeSpecial == nil && selectedGenre == nil) {
                    activeSpecial = nil
                    selectedGenre = nil
                    applySelection(force: true)
                }
                ForEach(provider == .jamendo ? GenrePalette.genres : AudiusAPI.genres, id: \.self) { genre in
                    chip(title: genre.capitalized, active: activeSpecial == nil && selectedGenre == genre) {
                        activeSpecial = nil
                        selectedGenre = genre
                        applySelection(force: true)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func chip(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(active ? .bold : .regular)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(active ? Color.accentColor : Color(.secondarySystemBackground))
                .foregroundColor(active ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Featured hero card (Apple Music "Listen Now" style)

struct HeroCard: View {
    let track: Track
    let tracks: [Track]

    var body: some View {
        Button {
            Haptics.impact()
            PlayerManager.shared.play(tracks, startIndex: 0)
        } label: {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: track.bestArtwork) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        LinearGradient(
                            colors: GenrePalette.colors(for: "pop"),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
                .frame(height: 210)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.78)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text("FEATURED")
                        .font(.caption2)
                        .bold()
                        .foregroundColor(.white.opacity(0.7))
                        .kerning(1.2)
                    Text(track.name)
                        .font(.title3)
                        .bold()
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(track.artistName)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                }
                .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
    }
}
