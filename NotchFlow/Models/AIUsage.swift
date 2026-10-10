import Foundation
import CoreFoundation

enum AIProvider: String, CaseIterable, Codable, Identifiable {
    case codex, claude
    var id: String { rawValue }
    var name: String { self == .codex ? "Codex" : "Claude Code" }
    var usageURL: URL {
        URL(string: self == .codex ? "https://chatgpt.com/codex/settings/usage" : "https://claude.ai/settings/usage")!
    }
}

struct AIUsageWindow: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let usedPercent: Double
    let resetsAt: Date?
    var fraction: Double { min(1, max(0, usedPercent / 100)) }
    var remainingPercent: Double { max(0, 100 - usedPercent) }
}

struct AIUsageReading: Codable, Equatable {
    let windows: [AIUsageWindow]
    let fetchedAt: Date
    func isStale(at date: Date) -> Bool {
        date.timeIntervalSince(fetchedAt) > 300 || windows.contains { ($0.resetsAt ?? .distantFuture) <= date }
    }
}

enum AIUsageError: Error {
    case credentials, expired, access, response, noLimits, rateLimited(TimeInterval)
}

/// Decode each window independently: an absent/invalid percentage is unavailable, never zero.
enum AIUsageParser {
    static func parse(_ data: Data, provider: AIProvider, now: Date = Date()) throws -> AIUsageReading {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIUsageError.response
        }
        var windows: [AIUsageWindow] = []
        func append(_ value: Any?, id: String, title: String, percentKey: String) {
            guard let object = value as? [String: Any],
                  let number = object[percentKey] as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
                  number.doubleValue >= 0 else { return }
            var reset: Date?
            if let timestamp = object["reset_at"] as? Double, timestamp.isFinite {
                reset = Date(timeIntervalSince1970: timestamp)
            } else if let seconds = object["reset_after_seconds"] as? Double, seconds.isFinite {
                reset = now.addingTimeInterval(max(0, seconds))
            } else if let text = object["resets_at"] as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                reset = formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
            }
            guard !windows.contains(where: { $0.id == id }) else { return }
            windows.append(AIUsageWindow(id: id, title: title, usedPercent: number.doubleValue, resetsAt: reset))
        }
        switch provider {
        case .codex:
            let limits = root["rate_limit"] as? [String: Any]
            for key in ["primary_window", "secondary_window"] {
                let object = limits?[key] as? [String: Any]
                let seconds = object?["limit_window_seconds"] as? Double ?? 0
                let title: String
                if seconds == 604800 { title = "Weekly limit" }
                else if seconds == 18000 { title = "5-hour limit" }
                else if seconds.isFinite, seconds >= 3600, seconds / 3600 < Double(Int.max) {
                    title = "\(Int(seconds / 3600)) h"
                }
                else { title = key == "primary_window" ? "Current session" : "Longer window" }
                append(object, id: key, title: title, percentKey: "used_percent")
            }
        case .claude:
            // New responses use a list; older responses expose named windows.
            for (index, limit) in ((root["limits"] as? [[String: Any]]) ?? []).enumerated() {
                guard let kind = limit["kind"] as? String else { continue }
                let scope = limit["scope"] as? [String: Any]
                let model = scope?["model"] as? [String: Any]
                let id = kind == "weekly_scoped" ? "\(kind)-\(index)" : kind
                let title = model?["display_name"] as? String
                    ?? (kind == "session" ? "Current session" : kind == "weekly_all" ? "Weekly limit" : kind)
                append(limit, id: id, title: title, percentKey: "percent")
            }
            append(root["five_hour"], id: "session", title: "Current session", percentKey: "utilization")
            append(root["seven_day"], id: "weekly_all", title: "Weekly limit", percentKey: "utilization")
            for key in ["seven_day_sonnet", "seven_day_opus"] {
                append(root[key], id: key, title: key == "seven_day_sonnet" ? "Sonnet" : "Opus", percentKey: "utilization")
            }
            windows.sort { rank($0.id) < rank($1.id) }
        }
        guard !windows.isEmpty else { throw AIUsageError.noLimits }
        return AIUsageReading(windows: windows, fetchedAt: now)
    }

    private static func rank(_ id: String) -> Int { id == "session" ? 0 : id == "weekly_all" ? 1 : 2 }
}
