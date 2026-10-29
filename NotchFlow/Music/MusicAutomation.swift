import AppKit
import Carbon

/// Public Apple Events only. All calls run on the monitor's serial worker,
/// target a running PID (never launch a player), and have bounded timeouts.
enum MusicAutomation {
    struct Failure: Error { let code: Int }

    static func code(_ string: String) -> FourCharCode {
        string.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) }
    }

    static func permission(pid: pid_t, prompt: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(processIdentifier: pid)
        return AEDeterminePermissionToAutomateTarget(target.aeDesc, UInt32(typeWildCard), UInt32(typeWildCard), prompt)
    }

    static func property(_ name: String, of container: NSAppleEventDescriptor = .null()) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: UInt32(typeProperty)), forKeyword: UInt32(keyAEDesiredClass))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: UInt32(formPropertyID)), forKeyword: UInt32(keyAEKeyForm))
        record.setDescriptor(NSAppleEventDescriptor(typeCode: code(name)), forKeyword: UInt32(keyAEKeyData))
        record.setDescriptor(container, forKeyword: UInt32(keyAEContainer))
        return record.coerce(toDescriptorType: UInt32(typeObjectSpecifier))!
    }

    static func send(pid: pid_t, suite: String = "core", command: String,
                     direct: NSAppleEventDescriptor? = nil, value: NSAppleEventDescriptor? = nil) throws -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(eventClass: code(suite), eventID: code(command),
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid),
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        if let direct { event.setParam(direct, forKeyword: UInt32(keyDirectObject)) }
        if let value { event.setParam(value, forKeyword: UInt32(keyAEData)) }
        let reply = try event.sendEvent(options: [.waitForReply, .neverInteract], timeout: 1)
        let error = reply.paramDescriptor(forKeyword: UInt32(keyErrorNumber))?.int32Value ?? 0
        guard error == 0 else { throw Failure(code: Int(error)) }
        return reply.paramDescriptor(forKeyword: UInt32(keyDirectObject)) ?? .null()
    }

    static func read(pid: pid_t, player: MusicPlayer, previous: MusicPlayback?,
                     fetch: ((String, NSAppleEventDescriptor) throws -> NSAppleEventDescriptor)? = nil) throws -> MusicPlayback? {
        func get(_ key: String, in container: NSAppleEventDescriptor = .null()) throws -> NSAppleEventDescriptor {
            if let fetch { return try fetch(key, container) }
            return try send(pid: pid, command: "getd", direct: property(key, of: container))
        }
        let state = try get("pPlS").enumCodeValue
        guard state == code("kPSP") || state == code("kPSp") else { return nil }
        let track = property("pTrk")
        let title = try get("pnam", in: track).stringValue ?? ""
        guard !title.isEmpty else { return nil }
        let artist = try get("pArt", in: track).stringValue ?? ""
        let duration = try get("pDur", in: track).doubleValue / (player == .spotify ? 1000 : 1)
        let position = try get("pPos").doubleValue
        let identifier = try? get(player == .spotify ? "ID  " : "pPID", in: track).stringValue
        let id = identifier.flatMap { $0.isEmpty ? nil : $0 } ?? "\(title)|\(artist)"
        var result = MusicPlayback(id: id, title: title, artist: artist,
            duration: duration.isFinite ? max(0, duration) : 0,
            position: position.isFinite ? max(0, position) : 0,
            isPlaying: state == code("kPSP"), sampledAt: Date())
        result.album = try? get("pAlb", in: track).stringValue
        if previous?.id == id {
            result.artworkURL = previous?.artworkURL
            result.artworkData = previous?.artworkData
        } else if player == .spotify {
            if let address = try? get("aUrl", in: track).stringValue,
               let url = URL(string: address), url.scheme == "https" {
                result.artworkURL = url
            }
        } else {
            let artwork = NSAppleEventDescriptor.record()
            artwork.setDescriptor(NSAppleEventDescriptor(typeCode: code("cArt")), forKeyword: UInt32(keyAEDesiredClass))
            artwork.setDescriptor(NSAppleEventDescriptor(enumCode: UInt32(formAbsolutePosition)), forKeyword: UInt32(keyAEKeyForm))
            artwork.setDescriptor(NSAppleEventDescriptor(int32: 1), forKeyword: UInt32(keyAEKeyData))
            artwork.setDescriptor(track, forKeyword: UInt32(keyAEContainer))
            if let object = artwork.coerce(toDescriptorType: UInt32(typeObjectSpecifier)),
               let data = try? get("pRaw", in: object).data, data.count < 10_000_000 {
                result.artworkData = data
            }
        }
        return result
    }
}
