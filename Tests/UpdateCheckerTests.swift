import Foundation

@main
struct UpdateCheckerTests {
    @MainActor
    static func main() async throws {
        precondition(UpdateChecker.isNewer("v1.2.1", than: "1.2"))
        precondition(UpdateChecker.isNewer("2.0", than: "1.99"))
        precondition(!UpdateChecker.isNewer("1.2.0", than: "1.2"))
        for invalid in ["latest", "1..2", "1.2-beta", "", "9999999999999999999999999"] {
            precondition(!UpdateChecker.isNewer(invalid, than: "1.0"))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateStub.self]
        let checker = UpdateChecker(session: URLSession(configuration: configuration), currentVersion: "1.0.0")
        func check() async throws {
            checker.checkForUpdates(force: true)
            let deadline = Date().addingTimeInterval(5)
            while checker.isChecking, Date() < deadline {
                try await _Concurrency.Task.sleep(for: .milliseconds(10))
            }
            precondition(!checker.isChecking)
        }
        func payload(_ version: String, url: String = "https://github.com/HygorFerreira/NotchFlow/releases/tag/v1.1.0", prerelease: Bool = false) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["tag_name": version, "html_url": url, "draft": false, "prerelease": prerelease])
        }
        UpdateStub.body = try payload("v1.1.0")
        try await check()
        precondition(checker.availableUpdate?.version == "1.1.0" && !checker.checkFailed)
        precondition(checker.lastChecked != nil)
        let requests = UpdateStub.requests
        checker.checkForUpdates()
        precondition(UpdateStub.requests == requests && !checker.isChecking)
        UpdateStub.status = 404
        try await check()
        precondition(checker.checkFailed && checker.errorMessage != nil)
        precondition(checker.availableUpdate?.version == "1.1.0")
        UpdateStub.status = 429
        try await check()
        precondition(checker.checkFailed && checker.errorMessage != nil)
        UpdateStub.status = 200
        for body in [try payload("latest"), try payload("v1.2.0", url: "https://example.com/update"), try payload("v1.2.0", prerelease: true), Data("{}".utf8)] {
            UpdateStub.body = body
            try await check()
            precondition(checker.checkFailed && checker.availableUpdate?.version == "1.1.0")
        }
        UpdateStub.body = try payload("v1.0.0")
        try await check()
        precondition(!checker.checkFailed && checker.errorMessage == nil && checker.availableUpdate == nil)
        print("Update checker tests passed")
    }
}

final class UpdateStub: URLProtocol, @unchecked Sendable {
    static var status = 200
    static var body = Data()
    static var requests = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
