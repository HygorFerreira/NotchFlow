import Foundation
import CryptoKit

/// Uses only the public key embedded in the distributable app. Besides checking
/// the real generated assets, verifies that a changed archive/feed is rejected.
@main
struct UpdateArchiveTests {
    static func main() throws {
        let args = CommandLine.arguments
        precondition(args.count == 4, "Usage: archive-tests App.app appcast.xml update.zip")
        let app = URL(fileURLWithPath: args[1])
        let plist = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        let info = try PropertyListSerialization.propertyList(from: plist, format: nil) as! [String: Any]
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: info["SUPublicEDKey"] as! String)!)
        let feed = try Data(contentsOf: URL(fileURLWithPath: args[2]))
        let text = String(decoding: feed, as: UTF8.self)
        func capture(_ pattern: String) throws -> String {
            let regex = try NSRegularExpression(pattern: pattern)
            guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else {
                throw NSError(domain: "ArchiveTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing signature metadata"])
            }
            return String(text[range])
        }
        let archiveSignature = Data(base64Encoded: try capture("sparkle:edSignature=\"([^\"]+)\""))!
        let archive = try Data(contentsOf: URL(fileURLWithPath: args[3]))
        precondition(publicKey.isValidSignature(archiveSignature, for: archive), "Archive signature is invalid")
        var changedArchive = archive
        changedArchive[changedArchive.count / 2] ^= 1
        precondition(!publicKey.isValidSignature(archiveSignature, for: changedArchive), "Changed archive was accepted")
        let feedSignature = Data(base64Encoded: try capture("<!-- sparkle-signatures:\\s*edSignature: ([A-Za-z0-9+/=]+)"))!
        let signedLength = Int(try capture("<!-- sparkle-signatures:[\\s\\S]*?length: ([0-9]+)"))!
        let marker = feed.range(of: Data("<!-- sparkle-signatures:".utf8))!
        precondition(signedLength == marker.lowerBound, "Signed feed length mismatch")
        let signedFeed = Data(feed.prefix(signedLength))
        precondition(publicKey.isValidSignature(feedSignature, for: signedFeed), "Feed signature is invalid")
        var changedFeed = signedFeed
        changedFeed[changedFeed.count / 2] ^= 1
        precondition(!publicKey.isValidSignature(feedSignature, for: changedFeed), "Changed feed was accepted")
        print("Public-key verification passed; changed archive and feed were rejected")
    }
}
