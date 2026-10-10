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
        UsageStub.body = Data(#"{"rate_limit":{"primary_window":{"used_percent":42}}}"#.utf8)
        await monitor.refresh(.codex)
        precondition(monitor.readings[.codex]?.windows.first?.usedPercent == 42)
        precondition(monitor.errors[.codex] == nil)
        precondition(UsageStub.authorization == "Bearer test-token")
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
