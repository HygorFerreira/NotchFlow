import Foundation

struct LyricLine: Identifiable, Equatable {
    let id: Int
    let time: Double
    let text: String
}

enum SyncedLyrics {
    static func parse(_ lrc: String) -> [LyricLine] {
        guard lrc.utf8.count <= 1_000_000,
              let regex = try? NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{2})(?:\.(\d{1,3}))?\]"#) else { return [] }
        var result: [LyricLine] = []
        for raw in lrc.components(separatedBy: .newlines) {
            let ns = raw as NSString
            let matches = regex.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue }
            let text = ns.substring(from: last.range.location + last.range.length).trimmingCharacters(in: .whitespaces)
            for match in matches {
                guard let minutes = Double(ns.substring(with: match.range(at: 1))),
                      let seconds = Double(ns.substring(with: match.range(at: 2))), seconds < 60 else { continue }
                let fraction = match.range(at: 3)
                let decimal = fraction.location == NSNotFound ? 0 : (Double(ns.substring(with: fraction)) ?? 0) / pow(10, Double(fraction.length))
                result.append(LyricLine(id: result.count, time: minutes * 60 + seconds + decimal, text: text))
                if result.count >= 5000 { break }
            }
            if result.count >= 5000 { break }
        }
        return result.sorted { $0.time == $1.time ? $0.id < $1.id : $0.time < $1.time }
    }

    static func activeLine(in lines: [LyricLine], at seconds: Double) -> Int? {
        guard seconds.isFinite else { return nil }
        var low = 0, high = lines.count
        while low < high {
            let middle = (low + high) / 2
            if lines[middle].time <= seconds { low = middle + 1 } else { high = middle }
        }
        return low > 0 ? lines[low - 1].id : nil
    }
}
