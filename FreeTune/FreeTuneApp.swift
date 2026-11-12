import SwiftUI

@main
struct FreeTuneApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

// MARK: - App settings (Jamendo key)

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private static let clientIDKey = "freetune.jamendo.clientid"

    @Published private(set) var clientID: String
    @Published private(set) var keyVersion = 0

    private init() {
        clientID = UserDefaults.standard.string(forKey: Self.clientIDKey) ?? ""
    }

    var effectiveClientID: String {
        clientID.isEmpty ? JamendoAPI.bundledClientID : clientID
    }

    func save(clientID newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        clientID = trimmed
        UserDefaults.standard.set(trimmed, forKey: Self.clientIDKey)
        keyVersion += 1
    }
}

// MARK: - Root (tabs + floating mini player + alerts)

struct RootView: View {
    @ObservedObject private var player = PlayerManager.shared
    @ObservedObject private var downloads = DownloadManager.shared
    @State private var showNowPlaying = false

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            LibraryView()
                .tabItem { Label("Library", systemImage: "square.stack.fill") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .overlay(alignment: .bottom) {
            if player.currentTrack != nil {
                NowPlayingBar(showFull: $showNowPlaying)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 49)
            }
        }
        .fullScreenCover(isPresented: $showNowPlaying) {
            NowPlayingView()
        }
        .alert(
            "Playback Error",
            isPresented: Binding(
                get: { player.playbackErrorMessage != nil },
                set: { if !$0 { player.playbackErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(player.playbackErrorMessage ?? "")
        }
        .alert(
            "Download Error",
            isPresented: Binding(
                get: { downloads.lastErrorMessage != nil },
                set: { if !$0 { downloads.lastErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(downloads.lastErrorMessage ?? "")
        }
    }
}
