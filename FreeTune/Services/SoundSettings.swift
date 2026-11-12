import Foundation
import Combine

/// Global sound preferences: EQ, bass boost, immersive (spatial) mode and
/// Hi-Res FLAC streaming. Persisted to UserDefaults and applied live to the
/// AVAudioEngine processing chain.
final class SoundSettings: ObservableObject {
    static let shared = SoundSettings()

    private static let eqKey = "freetune.sound.eq"
    private static let bassKey = "freetune.sound.bass"
    private static let spatialKey = "freetune.sound.spatial"
    private static let hifiKey = "freetune.sound.hifi"

    @Published var eqGains: [Double] {
        didSet {
            if let data = try? JSONEncoder().encode(eqGains) {
                UserDefaults.standard.set(data, forKey: Self.eqKey)
            }
        }
    }
    @Published var bassBoost: Double {
        didSet { UserDefaults.standard.set(bassBoost, forKey: Self.bassKey) }
    }
    @Published var spatialEnabled: Bool {
        didSet { UserDefaults.standard.set(spatialEnabled, forKey: Self.spatialKey) }
    }
    @Published var hifi: Bool {
        didSet { UserDefaults.standard.set(hifi, forKey: Self.hifiKey) }
    }

    static let presets: [(name: String, gains: [Double])] = [
        ("Flat", [0, 0, 0, 0, 0]),
        ("Bass Boost", [7.5, 3, -1, -1, 0]),
        ("Vocal", [-2, 1, 5, 4, 1]),
        ("Bright", [0, -2, 1, 4, 6]),
        ("Warm", [5, 2, -1, -2, -3])
    ]

    static let bandLabels = ["60", "230", "910", "3.6k", "14k"]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.eqKey),
           let gains = try? JSONDecoder().decode([Double].self, from: data),
           gains.count == 5 {
            eqGains = gains
        } else {
            eqGains = [0, 0, 0, 0, 0]
        }
        bassBoost = UserDefaults.standard.double(forKey: Self.bassKey)
        spatialEnabled = UserDefaults.standard.bool(forKey: Self.spatialKey)
        hifi = UserDefaults.standard.bool(forKey: Self.hifiKey)
    }

    func applyPreset(_ gains: [Double]) {
        eqGains = gains
    }

    /// True when any effect is configured — only then is the DSP engine used.
    var fxEnabled: Bool {
        spatialEnabled || bassBoost > 0.01 || eqGains.contains { abs($0) > 0.01 }
    }
}
