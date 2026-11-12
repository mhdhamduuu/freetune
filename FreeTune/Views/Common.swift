import SwiftUI
import UIKit

// MARK: - Time formatting

extension Double {
    var asTimeString: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let total = Int(self.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

extension Int {
    var asTimeString: String { Double(self).asTimeString }
}

// MARK: - Haptics

enum Haptics {
    static func impact() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - Image loader (memory cache)

final class ImageLoader {
    static let shared = ImageLoader()

    private let cache = NSCache<NSURL, UIImage>()

    func image(from url: URL) async throws -> UIImage {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let image = UIImage(data: data) else {
            throw URLError(.cannotDecodeContentData)
        }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

// MARK: - Artwork view

struct TrackArtwork: View {
    let track: Track
    var size: CGFloat = 48

    var body: some View {
        AsyncImage(url: track.bestArtwork, transaction: Transaction(animation: .none)) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 0.45, green: 0.3, blue: 0.75),
                            Color(red: 0.2, green: 0.15, blue: 0.4)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.38, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(6, size * 0.16), style: .continuous))
    }
}

// MARK: - Genre palette (Apple Music-style gradient tiles)

enum GenrePalette {
    static let genres = [
        "pop", "rock", "hiphop", "electronic", "dance", "jazz",
        "metal", "classical", "chillout", "folk", "soundtrack", "latin"
    ]

    static func colors(for genre: String) -> [Color] {
        switch genre {
        case "pop":
            return [Color(red: 0.98, green: 0.36, blue: 0.55), Color(red: 0.85, green: 0.2, blue: 0.42)]
        case "rock":
            return [Color(red: 0.95, green: 0.5, blue: 0.2), Color(red: 0.7, green: 0.28, blue: 0.1)]
        case "hiphop":
            return [Color(red: 0.35, green: 0.35, blue: 0.4), Color(red: 0.15, green: 0.15, blue: 0.2)]
        case "electronic":
            return [Color(red: 0.2, green: 0.7, blue: 0.95), Color(red: 0.15, green: 0.3, blue: 0.75)]
        case "dance":
            return [Color(red: 0.9, green: 0.3, blue: 0.9), Color(red: 0.5, green: 0.15, blue: 0.7)]
        case "jazz":
            return [Color(red: 0.95, green: 0.75, blue: 0.3), Color(red: 0.75, green: 0.45, blue: 0.15)]
        case "metal":
            return [Color(red: 0.3, green: 0.3, blue: 0.32), Color(red: 0.1, green: 0.1, blue: 0.12)]
        case "classical":
            return [Color(red: 0.8, green: 0.7, blue: 0.95), Color(red: 0.45, green: 0.3, blue: 0.7)]
        case "chillout":
            return [Color(red: 0.35, green: 0.85, blue: 0.7), Color(red: 0.15, green: 0.5, blue: 0.45)]
        case "folk":
            return [Color(red: 0.65, green: 0.8, blue: 0.35), Color(red: 0.35, green: 0.5, blue: 0.15)]
        case "soundtrack":
            return [Color(red: 0.55, green: 0.6, blue: 0.95), Color(red: 0.25, green: 0.3, blue: 0.6)]
        case "latin":
            return [Color(red: 0.98, green: 0.55, blue: 0.25), Color(red: 0.85, green: 0.3, blue: 0.2)]
        default:
            return [Color(red: 0.55, green: 0.4, blue: 0.85), Color(red: 0.3, green: 0.2, blue: 0.55)]
        }
    }
}

// MARK: - Onboarding card (shown until a Jamendo key is set)

struct OnboardingCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Unlock the full catalogs", systemImage: "key.fill")
                .font(.headline)
            Text("• Audius is already playing — millions of full tracks from artists, no key needed.")
                .font(.footnote)
                .foregroundColor(.secondary)
            Text("• Add a free Jamendo key to unlock the Creative Commons catalog with legal downloads and Hi-Res FLAC. Get a client ID at dev.jamendo.com (2 minutes) and paste it in Settings.")
                .font(.footnote)
                .foregroundColor(.secondary)
            Link("Get a free client ID at dev.jamendo.com", destination: URL(string: "https://dev.jamendo.com")!)
                .font(.footnote)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
    }
}
