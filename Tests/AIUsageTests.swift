import Foundation

@main
struct AIUsageTests {
    @MainActor
    static func main() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func parse(_ json: String, _ provider: AIProvider) throws -> AIUsageReading {
            try AIUsageParser.parse(Data(json.utf8), provider: provider, now: now)
        }
        let codex = try parse("""
        {"rate_limit":{"primary_window":{"used_percent":42,"limit_window_seconds":18000,"reset_after_seconds":3600},
        "secondary_window":{"used_percent":73,"limit_window_seconds":604800,"reset_at":1800600000}}}
        """, .codex)
        precondition(codex.windows.map(\.usedPercent) == [42, 73])
        precondition(codex.windows[0].resetsAt == now.addingTimeInterval(3600))
        precondition(codex.windows[1].title == "Weekly limit")
        precondition(!codex.isStale(at: now.addingTimeInterval(120)))
        precondition(codex.isStale(at: now.addingTimeInterval(301)))
        let partial = try parse("""
        {"rate_limit":{"primary_window":{"used_percent":null},"secondary_window":{"used_percent":0}}}
        """, .codex)
        precondition(partial.windows.count == 1 && partial.windows[0].usedPercent == 0)
        let boolean = try parse("""
        {"rate_limit":{"primary_window":{"used_percent":true},"secondary_window":{"used_percent":20}}}
        """, .codex)
        precondition(boolean.windows.count == 1 && boolean.windows[0].usedPercent == 20)
        let claude = try parse("""
        {"limits":[{"kind":"weekly_all","percent":60,"resets_at":"2027-01-15T10:00:00.123Z"},
        {"kind":"session","percent":15,"resets_at":"2027-01-15T10:00:00Z"}],
        "five_hour":{"utilization":15},"seven_day":{"utilization":60}}
        """, .claude)
        precondition(claude.windows.count == 2 && claude.windows[0].id == "session")
        precondition(claude.windows.allSatisfy { $0.resetsAt != nil })
        let legacy = try parse("""
        {"five_hour":{"utilization":100,"resets_at":"2027-01-01T00:00:00Z"},
        "seven_day":{"utilization":12},"seven_day_sonnet":{"utilization":8}}
        """, .claude)
        precondition(legacy.windows.count == 3 && legacy.windows[0].fraction == 1)
        precondition(legacy.isStale(at: now)) // A reset already passed.
        let overflow = try parse("""
        {"rate_limit":{"primary_window":{"used_percent":110}}}
        """, .codex)
        precondition(overflow.windows[0].fraction == 1 && overflow.windows[0].remainingPercent == 0)
        let hugeWindow = try parse("""
        {"rate_limit":{"primary_window":{"used_percent":10,"limit_window_seconds":1e100}}}
        """, .codex)
        precondition(hugeWindow.windows[0].title == "Current session")
        for provider in AIProvider.allCases {
            do {
                _ = try parse("{}", provider)
                preconditionFailure("Missing readings must not become zero usage")
            } catch AIUsageError.noLimits {}
        }
        precondition(codex.weeklyWindow?.usedPercent == 73)
        precondition(codex.primaryWindow(weekly: false)?.usedPercent == 42)
        precondition(codex.primaryWindow(weekly: true)?.usedPercent == 73)
        var preferences = AIUsagePreferences()
        preferences.monthlyPrice = 100
        let cost = preferences.weeklyCost(for: codex, at: now)!
        precondition(abs(cost - 100 / 4.35 * 0.73) < 0.00001)
        precondition(preferences.weeklyCost(for: codex, at: now.addingTimeInterval(301)) == nil)
        precondition(preferences.weeklyCost(for: partial, at: now) == nil)
        preferences.monthlyPrice = .nan
        precondition(preferences.weeklyCost(for: codex, at: now) == nil)
        preferences.sessionAlerts = true
        preferences.weeklyAlerts = true
        preferences.resetAlerts = true
        func reading(_ percent: Double, reset: Date, fetched: Date = now) -> AIUsageReading {
            AIUsageReading(windows: [AIUsageWindow(id: "session", title: "Current session",
                                                   usedPercent: percent, resetsAt: reset)], fetchedAt: fetched)
        }
        var alertState = AIUsageAlertState()
        let reset = now.addingTimeInterval(3600)
        precondition(alertState.consume(reading(79, reset: reset), provider: .codex, preferences: preferences, now: now).isEmpty)
        precondition(alertState.consume(reading(80, reset: reset), provider: .codex, preferences: preferences, now: now).map(\.kind) == [.threshold(80)])
        precondition(alertState.consume(reading(79, reset: reset), provider: .codex, preferences: preferences, now: now).isEmpty)
        precondition(alertState.consume(reading(81, reset: reset), provider: .codex, preferences: preferences, now: now).isEmpty)
        // Restart preserves the high-water mark.
        alertState = try JSONDecoder().decode(AIUsageAlertState.self, from: JSONEncoder().encode(alertState))
        precondition(alertState.consume(reading(90, reset: reset), provider: .codex, preferences: preferences, now: now).isEmpty)
        precondition(alertState.consume(reading(100, reset: reset), provider: .codex, preferences: preferences, now: now).map(\.kind) == [.threshold(100)])
        precondition(alertState.consume(reading(110, reset: reset), provider: .codex, preferences: preferences, now: now).isEmpty)
        let next = reset.addingTimeInterval(10)
        let newReset = next.addingTimeInterval(3600)
        precondition(alertState.consume(reading(5, reset: newReset, fetched: next), provider: .codex, preferences: preferences, now: next).map(\.kind) == [.reset])
        precondition(alertState.consume(reading(80, reset: newReset, fetched: next), provider: .codex, preferences: preferences, now: next).map(\.kind) == [.threshold(80)])
        var staleState = AIUsageAlertState()
        precondition(staleState.consume(reading(100, reset: reset, fetched: now.addingTimeInterval(-600)), provider: .codex, preferences: preferences, now: now).isEmpty)
        precondition(staleState.windows.isEmpty)
        // Session and weekly limits alert independently; an exhausted first reading alerts once.
        var bothState = AIUsageAlertState()
        let both = AIUsageReading(windows: [
            AIUsageWindow(id: "session", title: "Current session", usedPercent: 100, resetsAt: reset),
            AIUsageWindow(id: "weekly", title: "Weekly limit", usedPercent: 85, resetsAt: reset)
        ], fetchedAt: now)
        precondition(bothState.consume(both, provider: .claude, preferences: preferences, now: now).map(\.kind) == [.threshold(100), .threshold(80)])
        precondition(bothState.consume(both, provider: .claude, preferences: preferences, now: now).isEmpty)
        let encoded = try JSONEncoder().encode(codex)
        let restored = try JSONDecoder().decode(AIUsageReading.self, from: encoded)
        precondition(restored == codex)
        // A fake network and credential source exercise the real refresh/persistence paths.
        let suite = "NotchFlowAIUsageTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "aiUsage.codex.enabled")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UsageStub.self]
        let monitor = AIUsageMonitor(defaults: defaults, session: URLSession(configuration: config),
                                    credentialData: { _ in Data(#"{"tokens":{"access_token":"test-token","account_id":"test-account"}}"#.utf8) })
        var invalidPreferences = AIUsagePreferences()
        invalidPreferences.monthlyPrice = -.infinity
        invalidPreferences.currency = "invalid"
        monitor.updatePreferences(.codex, invalidPreferences)
        precondition(monitor.preferences[.codex]?.monthlyPrice == 0)
        precondition(monitor.preferences[.codex]?.currency == "BRL")
        UsageStub.body = Data(#"{"rate_limit":{"primary_window":{"used_percent":42}}}"#.utf8)
        await monitor.refresh(.codex)
        precondition(monitor.readings[.codex]?.windows.first?.usedPercent == 42)
        precondition(monitor.errors[.codex] == nil)
        precondition(UsageStub.authorization == "Bearer test-token")
        var alertPreferences = monitor.preferences[.codex]!
        alertPreferences.sessionAlerts = true
        alertPreferences.monthlyPrice = 120
        monitor.updatePreferences(.codex, alertPreferences)
        var delivered: [AIUsageAlert] = []
        monitor.onAlert = { delivered.append($0) }
        UsageStub.body = Data(#"{"rate_limit":{"primary_window":{"used_percent":81}}}"#.utf8)
        await monitor.refresh(.codex)
        await monitor.refresh(.codex)
        precondition(delivered.map(\.kind) == [.threshold(80)])
        let restarted = AIUsageMonitor(defaults: defaults, session: URLSession(configuration: config),
            credentialData: { _ in Data(#"{"tokens":{"access_token":"test-token","account_id":"test-account"}}"#.utf8) })
        restarted.onAlert = { delivered.append($0) }
        await restarted.refresh(.codex)
        precondition(delivered.count == 1)
        precondition(restarted.preferences[.codex]?.monthlyPrice == 120)
        let saved = defaults.data(forKey: "aiUsage.codex.reading")!
        precondition(!String(decoding: saved, as: UTF8.self).contains("test-token"))
        UsageStub.status = 401
        await monitor.refresh(.codex)
        precondition(monitor.errors[.codex] != nil && monitor.readings[.codex] != nil)
        UsageStub.status = 429
        await monitor.refresh(.codex)
        let requests = UsageStub.requests
        await monitor.refresh(.codex)
        precondition(UsageStub.requests == requests)
        precondition(defaults.object(forKey: "aiUsage.codex.retry") != nil)
        monitor.disconnect(.codex)
        precondition(monitor.readings.isEmpty && monitor.connected.isEmpty)
        precondition(defaults.data(forKey: "aiUsage.codex.reading") == nil)
        // The service switch reuses the tool's login without asking for a file in the normal path.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("NotchFlowLoginTest-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let login = folder.appendingPathComponent("auth.json")
        try Data(#"{"tokens":{"access_token":"first-login","account_id":"first-account"}}"#.utf8).write(to: login)
        UsageStub.status = 200
        let automatic = AIUsageMonitor(defaults: defaults, session: URLSession(configuration: config), loginFolder: { _ in folder })
        automatic.setMonitoring(.codex, enabled: true)
        await automatic.refresh(.codex)
        precondition(automatic.connected.contains(.codex) && automatic.readings[.codex] != nil)
        precondition(UsageStub.authorization == "Bearer first-login")
        precondition(defaults.data(forKey: "aiUsage.codex.bookmark") == nil)
        // Sign-in or account switching replaces auth.json; the next refresh follows that login.
        try Data(#"{"tokens":{"access_token":"second-login","account_id":"second-account"}}"#.utf8).write(to: login, options: .atomic)
        await automatic.refresh(.codex)
        precondition(UsageStub.authorization == "Bearer second-login")
        automatic.setMonitoring(.codex, enabled: false)
        precondition(automatic.connected.isEmpty && automatic.readings.isEmpty)
        precondition(FileManager.default.fileExists(atPath: login.path))
        let unchangedLogin = try Data(contentsOf: login)
        precondition(String(decoding: unchangedLogin, as: UTF8.self).contains("second-login"))
        print("AI usage tests passed")
    }
}

final class UsageStub: URLProtocol, @unchecked Sendable {
    static var status = 200
    static var body = Data()
    static var requests = 0
    static var authorization: String?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        Self.authorization = request.value(forHTTPHeaderField: "Authorization")
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
