import Foundation
import Combine

@MainActor
final class LyricsMonitor: ObservableObject {
    @Published private(set) var enabled: Bool
    @Published private(set) var lines: [LyricLine] = []
    @Published private(set) var plainLyrics: String?
    @Published private(set) var status: Status = .idle
    enum Status { case idle, loading, ready, instrumental, notFound, failed }
    private let defaults: UserDefaults
    private let session = URLSession(configuration: .ephemeral)
    private var request: _Concurrency.Task<Void, Never>?
    private var key: String?
    private var generation = 0
    private var demo = false
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.bool(forKey: "music.lyrics")
    }

    func setEnabled(_ enabled: Bool, playback: MusicPlayback?) {
        self.enabled = enabled
        defaults.set(enabled, forKey: "music.lyrics")
        update(playback, force: true)
    }

    func update(_ playback: MusicPlayback?, force: Bool = false) {
        guard !demo else { return }
        let nextKey = playback.map { "\($0.id)|\($0.title)|\($0.artist)" }
        guard force || key != nextKey else { return }
        key = nextKey
        generation += 1
        let current = generation
        request?.cancel()
        lines = []; plainLyrics = nil; status = .idle
        guard enabled, let playback, !playback.title.isEmpty, !playback.artist.isEmpty else { return }
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [URLQueryItem(name: "track_name", value: playback.title),
                                URLQueryItem(name: "artist_name", value: playback.artist),
                                URLQueryItem(name: "duration", value: String(Int(min(31536000, max(0, playback.duration.isFinite ? playback.duration : 0)))))]
        if let album = playback.album, !album.isEmpty { components.queryItems?.append(URLQueryItem(name: "album_name", value: album)) }
        guard let url = components.url else { return }
        status = .loading
        let session = session
        request = _Concurrency.Task { [weak self] in
            do {
                var urlRequest = URLRequest(url: url, timeoutInterval: 15)
                urlRequest.setValue("NotchFlow/1.2 (https://github.com/HygorFerreira/NotchFlow)", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await session.data(for: urlRequest)
                guard !_Concurrency.Task.isCancelled, let self, self.generation == current else { return }
                if (response as? HTTPURLResponse)?.statusCode == 404 { self.status = .notFound; return }
                guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 1_000_000 else { self.status = .failed; return }
                let value = try JSONDecoder().decode(Response.self, from: data)
                self.lines = SyncedLyrics.parse(value.syncedLyrics ?? "")
                self.plainLyrics = value.plainLyrics.map { String($0.prefix(100000)) }
                self.status = value.instrumental == true ? .instrumental :
                    (!self.lines.isEmpty || !(value.plainLyrics ?? "").isEmpty ? .ready : .notFound)
            } catch {
                guard !_Concurrency.Task.isCancelled, let self, self.generation == current else { return }
                self.status = .failed
            }
        }
    }
    private struct Response: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
        let instrumental: Bool?
    }
    #if DEBUG
    func setDemo() {
        request?.cancel(); demo = true; enabled = true; status = .ready
        lines = SyncedLyrics.parse("[00:00.00]A quiet moment to begin\n[01:20.00]Let the rhythm guide your focus\n[01:30.00]One small step, then another")
    }
    #endif
}
