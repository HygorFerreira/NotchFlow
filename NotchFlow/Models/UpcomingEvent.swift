import Foundation

struct UpcomingEvent: Equatable {
    let title: String
    let start: Date
    let end: Date
    let meetingURL: URL?

    static func meetingLink(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap(\.url).first { url in
            guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(), url.user == nil else { return false }
            return ["meet.google.com", "zoom.us", "zoom.com", "teams.microsoft.com", "teams.live.com", "teams.cloud.microsoft", "webex.com"]
                .contains { host == $0 || host.hasSuffix("." + $0) }
        }
    }
}
