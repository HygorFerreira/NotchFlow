import Foundation

enum MusicPlayer: String, CaseIterable, Identifiable {
    case spotify, appleMusic
    var id: String { rawValue }
    var name: String { self == .spotify ? "Spotify" : "Apple Music" }
    var bundleID: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
    var eventSuite: String { self == .spotify ? "spfy" : "hook" }
}

struct MusicPlayback: Equatable {
    let id: String
    let title: String
    let artist: String
    let duration: Double
    let position: Double
    let isPlaying: Bool
    let sampledAt: Date
    var artworkURL: URL?
    var artworkData: Data?
    var album: String?

    func elapsed(at date: Date) -> Double {
        let value = position + (isPlaying ? max(0, date.timeIntervalSince(sampledAt)) : 0)
        return min(max(0, duration), max(0, value.isFinite ? value : 0))
    }

    static func timeLabel(_ seconds: Double) -> String {
        let value = Int(min(86400 * 365, max(0, seconds.isFinite ? seconds : 0)))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
