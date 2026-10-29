import AppKit
import Carbon

@main
struct MusicTests {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let playing = MusicPlayback(id: "track", title: "Song", artist: "Artist", duration: 120,
                                    position: 30, isPlaying: true, sampledAt: now)
        precondition(playing.elapsed(at: now.addingTimeInterval(15)) == 45)
        precondition(playing.elapsed(at: now.addingTimeInterval(200)) == 120)
        precondition(playing.elapsed(at: now.addingTimeInterval(-10)) == 30)
        let paused = MusicPlayback(id: "track", title: "Song", artist: "Artist", duration: 120,
                                   position: 30, isPlaying: false, sampledAt: now)
        precondition(paused.elapsed(at: now.addingTimeInterval(100)) == 30)
        precondition(MusicPlayback.timeLabel(.infinity) == "0:00")
        precondition(MusicPlayback.timeLabel(-10) == "0:00")
        precondition(MusicPlayback.timeLabel(245) == "4:05")

        func fixture(_ key: String, _ container: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
            switch key {
            case "pPlS": return NSAppleEventDescriptor(enumCode: MusicAutomation.code("kPSP"))
            case "pnam": return NSAppleEventDescriptor(string: "Song\nwith unicode ♫")
            case "pArt": return NSAppleEventDescriptor(string: "Artist")
            case "pDur": return NSAppleEventDescriptor(double: 245000)
            case "pPos": return NSAppleEventDescriptor(double: 32.5)
            case "ID  ", "pPID": return NSAppleEventDescriptor(string: "test-id")
            case "aUrl": return NSAppleEventDescriptor(string: "https://example.com/cover.jpg")
            default: throw MusicAutomation.Failure(code: -1728)
            }
        }
        let spotify = try MusicAutomation.read(pid: 0, player: .spotify, previous: nil, fetch: fixture)!
        precondition(spotify.duration == 245 && spotify.position == 32.5)
        precondition(spotify.title == "Song\nwith unicode ♫" && spotify.isPlaying)
        precondition(spotify.artworkURL?.scheme == "https")
        let music = try MusicAutomation.read(pid: 0, player: .appleMusic, previous: nil) { key, container in
            if key == "pDur" { return NSAppleEventDescriptor(double: 245) }
            return try fixture(key, container)
        }!
        precondition(music.duration == 245 && music.artworkData == nil)
        let stopped = try MusicAutomation.read(pid: 0, player: .spotify, previous: spotify) { key, _ in
            precondition(key == "pPlS", "Stopped players must not read a stale track")
            return NSAppleEventDescriptor(enumCode: MusicAutomation.code("kPSS"))
        }
        precondition(stopped == nil)
        let unsafeArtwork = try MusicAutomation.read(pid: 0, player: .spotify, previous: nil) { key, container in
            if key == "aUrl" { return NSAppleEventDescriptor(string: "file:///private/test.jpg") }
            return try fixture(key, container)
        }
        precondition(unsafeArtwork?.artworkURL == nil)
        do {
            _ = try MusicAutomation.read(pid: 0, player: .spotify, previous: spotify) { _, _ in
                throw MusicAutomation.Failure(code: -1743)
            }
            preconditionFailure("Permission errors must propagate instead of keeping stale playback")
        } catch let error as MusicAutomation.Failure { precondition(error.code == -1743) }
        let lyrics = SyncedLyrics.parse("[00:20.250]Second\n[00:05.00][00:10.00]Repeated\n[99:99.00]Invalid\n[ar:Artist]")
        precondition(lyrics.count == 3 && lyrics.map(\.time) == [5, 10, 20.25])
        precondition(SyncedLyrics.activeLine(in: lyrics, at: 4) == nil)
        precondition(SyncedLyrics.activeLine(in: lyrics, at: 10) == lyrics[1].id)
        precondition(SyncedLyrics.activeLine(in: lyrics, at: .infinity) == nil)
        print("Music and synchronized lyrics tests passed")
    }
}
