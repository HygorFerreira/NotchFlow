import AppKit
import SwiftUI
import Security
import LocalAuthentication
import CryptoKit
import Darwin

/// Credentials belong to the coding tools. Only bookmarks and usage readings are persisted here.
@MainActor
final class AIUsageMonitor: ObservableObject {
    static let shared = AIUsageMonitor()
    @Published private(set) var readings: [AIProvider: AIUsageReading] = [:]
    @Published private(set) var errors: [AIProvider: String] = [:]
    @Published private(set) var connected: Set<AIProvider> = []
    @Published private(set) var refreshing: Set<AIProvider> = []
    private let defaults: UserDefaults
    private let session: URLSession
    private let credentialData: ((AIProvider) throws -> Data)?
    private let loginFolder: (AIProvider) -> URL
    private var bookmarks: [AIProvider: Data] = [:]
    private var generation: [AIProvider: UUID] = [:]
    private var retryAfter: [AIProvider: Date] = [:]
    private var polling: _Concurrency.Task<Void, Never>?
    private var cachedClaude: (reference: Data, modifiedAt: Date, credential: Credential)?

    init(defaults: UserDefaults = .standard, session: URLSession? = nil,
         credentialData: ((AIProvider) throws -> Data)? = nil,
         loginFolder: @escaping (AIProvider) -> URL = AIUsageMonitor.defaultLoginFolder) {
        self.defaults = defaults
        self.credentialData = credentialData
        self.loginFolder = loginFolder
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        self.session = session ?? URLSession(configuration: configuration, delegate: AIUsageRedirectGuard(), delegateQueue: nil)
        for provider in AIProvider.allCases {
            if defaults.bool(forKey: key(provider, "enabled")) { connected.insert(provider) }
            bookmarks[provider] = defaults.data(forKey: key(provider, "bookmark"))
            if connected.contains(provider), let data = defaults.data(forKey: key(provider, "reading")) {
                readings[provider] = try? JSONDecoder().decode(AIUsageReading.self, from: data)
            }
            retryAfter[provider] = defaults.object(forKey: key(provider, "retry")) as? Date
        }
    }

    func start() {
        guard polling == nil else { return }
        polling = _Concurrency.Task { [weak self] in
            while !_Concurrency.Task.isCancelled {
                await self?.refreshAll()
                do { try await _Concurrency.Task.sleep(for: .seconds(120)) }
                catch { return }
            }
        }
    }

    func refreshAll() async {
        for provider in AIProvider.allCases where connected.contains(provider) { await refresh(provider) }
    }

    /// The toggle monitors an existing login, not a second account owned by NotchFlow.
    func setMonitoring(_ provider: AIProvider, enabled: Bool) {
        guard enabled else { disconnect(provider); return }
        self.enable(provider)
        do {
            if provider == .claude && bookmarks[provider] == nil && credentialData == nil {
                _ = try claudeKeychain(interactive: true)
            } else {
                _ = try loadCredential(provider)
            }
        } catch {
            errors[provider] = message(for: error)
            if provider == .codex, case AIUsageError.access = error {
                // A sandboxed app needs a user-selected grant; present the expected folder directly.
                connectFile(provider, authorizingDefault: true)
            }
        }
    }

    nonisolated static func defaultLoginFolder(_ provider: AIProvider) -> URL {
        // NSHomeDirectory is the app container in a sandbox. passwd gives the user's home.
        let home = getpwuid(getuid()).flatMap { entry in entry.pointee.pw_dir.map { String(cString: $0) } }
            ?? NSHomeDirectory()
        if provider == .codex, let configured = ProcessInfo.processInfo.environment["CODEX_HOME"], !configured.isEmpty {
            return URL(fileURLWithPath: configured, isDirectory: true)
        }
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent(provider == .codex ? ".codex" : ".claude", isDirectory: true)
    }

    func openCodex() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") else {
            errors[.codex] = String(localized: "Codex is not installed. Install it or sign in with Codex CLI.")
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Selecting the directory also covers auth.json when the owning app atomically replaces it.
    func connectFile(_ provider: AIProvider, authorizingDefault: Bool = false) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.showsHiddenFiles = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = loginFolder(provider)
        panel.prompt = String(localized: "Allow access")
        panel.message = authorizingDefault
            ? String(localized: "Allow NotchFlow to read the Codex login in this folder. Your account stays signed in through Codex.")
            : String(localized: provider == .codex
            ? "Select your .codex folder. NotchFlow reads auth.json to consult your account limits."
            : "Select your .claude folder containing .credentials.json. On macOS, use Keychain if this file is absent.")
        guard panel.runModal() == .OK, let url = panel.url else {
            if authorizingDefault { errors[provider] = String(localized: "Folder access is needed to read the Codex session. Use Allow access to try again.") }
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            _ = try credential(provider, data: Data(contentsOf: url.appendingPathComponent(filename(provider))))
            let bookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                includingResourceValuesForKeys: nil, relativeTo: nil)
            disconnect(provider)
            bookmarks[provider] = bookmark
            defaults.set(bookmark, forKey: key(provider, "bookmark"))
            enable(provider)
        } catch {
            errors[provider] = message(for: error)
        }
    }

    func connectClaudeKeychain() {
        do {
            _ = try claudeKeychain(interactive: true)
            let cache = cachedClaude
            disconnect(.claude)
            cachedClaude = cache
            enable(.claude)
        } catch { errors[.claude] = message(for: error) }
    }

    private func enable(_ provider: AIProvider) {
        connected.insert(provider)
        defaults.set(true, forKey: key(provider, "enabled"))
        _Concurrency.Task { await refresh(provider) }
    }

    func disconnect(_ provider: AIProvider) {
        generation[provider] = UUID() // Ignore responses from an earlier connection.
        connected.remove(provider)
        readings[provider] = nil
        errors[provider] = nil
        bookmarks[provider] = nil
        retryAfter[provider] = nil
        refreshing.remove(provider)
        if provider == .claude { cachedClaude = nil }
        for field in ["enabled", "reading", "bookmark", "retry"] { defaults.removeObject(forKey: key(provider, field)) }
    }

    func refresh(_ provider: AIProvider) async {
        guard connected.contains(provider), !refreshing.contains(provider) else { return }
        if let date = retryAfter[provider], date > Date() {
            errors[provider] = String(localized: "Too many requests. Automatic refresh will retry later.")
            return
        }
        let version = generation[provider] ?? UUID()
        generation[provider] = version
        refreshing.insert(provider)
        defer { if generation[provider] == version { refreshing.remove(provider) } }
        do {
            let auth = try loadCredential(provider)
            var request = URLRequest(url: URL(string: provider == .codex
                ? "https://chatgpt.com/backend-api/wham/usage"
                : "https://api.anthropic.com/api/oauth/usage")!)
            request.setValue("Bearer \(auth.token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if provider == .codex { request.setValue(auth.account, forHTTPHeaderField: "ChatGPT-Account-Id") }
            else { request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta") }
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AIUsageError.response }
            if http.statusCode == 401 || http.statusCode == 403 { throw AIUsageError.expired }
            if http.statusCode == 429 {
                throw AIUsageError.rateLimited(max(120, Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 600))
            }
            guard (200..<300).contains(http.statusCode) else { throw AIUsageError.response }
            let reading = try AIUsageParser.parse(data, provider: provider)
            guard generation[provider] == version, connected.contains(provider) else { return }
            readings[provider] = reading
            errors[provider] = nil
            retryAfter[provider] = nil
            defaults.removeObject(forKey: key(provider, "retry"))
            defaults.set(try JSONEncoder().encode(reading), forKey: key(provider, "reading"))
        } catch {
            guard generation[provider] == version, connected.contains(provider) else { return }
            if case AIUsageError.rateLimited(let seconds) = error {
                let date = Date().addingTimeInterval(seconds)
                retryAfter[provider] = date
                defaults.set(date, forKey: key(provider, "retry"))
            }
            errors[provider] = message(for: error)
        }
    }

    private struct Credential { let token: String; let account: String?; let expiresAt: Date? }

    private func credential(_ provider: AIProvider, data: Data) throws -> Credential {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIUsageError.credentials }
        let object = root[provider == .codex ? "tokens" : "claudeAiOauth"] as? [String: Any]
        guard let token = object?[provider == .codex ? "access_token" : "accessToken"] as? String,
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIUsageError.credentials }
        let account = object?["account_id"] as? String
        if provider == .codex && (account?.isEmpty != false) { throw AIUsageError.credentials }
        let expiresAt = provider == .claude
            ? (object?["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) } : nil
        if let expiresAt, expiresAt <= Date() { throw AIUsageError.expired }
        return Credential(token: token, account: account, expiresAt: expiresAt)
    }

    private func loadCredential(_ provider: AIProvider) throws -> Credential {
        if let credentialData { return try credential(provider, data: credentialData(provider)) }
        guard let bookmark = bookmarks[provider] else {
            if provider == .claude { return try claudeKeychain(interactive: false) }
            do {
                let data = try Data(contentsOf: loginFolder(provider).appendingPathComponent(filename(provider)))
                return try credential(provider, data: data)
            } catch let error as CocoaError {
                throw error.code == .fileReadNoSuchFile ? AIUsageError.credentials : AIUsageError.access
            }
        }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                                relativeTo: nil, bookmarkDataIsStale: &stale) else { throw AIUsageError.access }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if stale {
            let renewed = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                               includingResourceValuesForKeys: nil, relativeTo: nil)
            bookmarks[provider] = renewed
            defaults.set(renewed, forKey: key(provider, "bookmark"))
        }
        guard let data = try? Data(contentsOf: url.appendingPathComponent(filename(provider))) else { throw AIUsageError.access }
        return try credential(provider, data: data)
    }

    private func claudeKeychain(interactive: Bool) throws -> Credential {
        // macOS handles consent on an explicit click. Background refresh never opens a prompt.
        let attributesContext = LAContext()
        attributesContext.interactionNotAllowed = true
        let suffix = SHA256.hash(data: Data(loginFolder(.claude).path.utf8))
            .map { String(format: "%02x", $0) }.joined().prefix(8)
        var items: [[String: Any]] = []
        for service in ["Claude Code-credentials", "Claude Code-credentials-\(suffix)"] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecMatchLimit as String: kSecMatchLimitAll,
                kSecReturnAttributes as String: true,
                kSecReturnPersistentRef as String: true,
                kSecUseAuthenticationContext as String: attributesContext
            ]
            var attributes: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &attributes)
            if status == errSecSuccess, let found = attributes as? [[String: Any]] { items += found }
            else if status != errSecItemNotFound { throw AIUsageError.access }
        }
        guard let newest = items.max(by: {
                  ($0[kSecAttrModificationDate as String] as? Date ?? .distantPast)
                      < ($1[kSecAttrModificationDate as String] as? Date ?? .distantPast)
              }), let reference = newest[kSecValuePersistentRef as String] as? Data else { throw AIUsageError.credentials }
        let modifiedAt = newest[kSecAttrModificationDate as String] as? Date
        // A token refresh can update an item without changing its persistent reference.
        if let cachedClaude, let modifiedAt, cachedClaude.reference == reference,
           cachedClaude.modifiedAt == modifiedAt {
            if let expiry = cachedClaude.credential.expiresAt, expiry <= Date() { throw AIUsageError.expired }
            return cachedClaude.credential
        }
        let secretContext = LAContext()
        secretContext.interactionNotAllowed = !interactive
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecValuePersistentRef as String: reference,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: secretContext
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { throw AIUsageError.access }
        let credential = try credential(.claude, data: data)
        cachedClaude = modifiedAt.map { (reference, $0, credential) }
        return credential
    }

    private func filename(_ provider: AIProvider) -> String { provider == .codex ? "auth.json" : ".credentials.json" }
    private func key(_ provider: AIProvider, _ field: String) -> String { "aiUsage.\(provider.rawValue).\(field)" }
    private func message(for error: Error) -> String {
        switch error {
        case AIUsageError.credentials: return String(localized: "No subscription login found. Use Sign in to connect through the coding tool.")
        case AIUsageError.expired: return String(localized: "Session expired. Open the coding tool to renew your login.")
        case AIUsageError.access: return String(localized: "Access unavailable. Reconnect the folder or allow Keychain access.")
        case AIUsageError.noLimits: return String(localized: "This account did not report usage limits.")
        case AIUsageError.rateLimited: return String(localized: "Too many requests. Automatic refresh will retry later.")
        default: return String(localized: "Could not update usage. The last reading is shown when available.")
        }
    }

    #if DEBUG
    static func demo(stale: Bool = false) -> AIUsageMonitor {
        let monitor = AIUsageMonitor(defaults: UserDefaults(suiteName: "notchflow-ai-preview-\(UUID())")!)
        let now = Date()
        for (provider, percent) in [(AIProvider.codex, 42.0), (.claude, 68.0)] {
            monitor.connected.insert(provider)
            monitor.readings[provider] = AIUsageReading(windows: [
                AIUsageWindow(id: "session", title: "Current session", usedPercent: percent, resetsAt: now.addingTimeInterval(7200)),
                AIUsageWindow(id: "weekly", title: "Weekly limit", usedPercent: 23, resetsAt: now.addingTimeInterval(172800))
            ], fetchedAt: stale ? now.addingTimeInterval(-600) : now)
            if stale { monitor.errors[provider] = String(localized: "Could not update usage. The last reading is shown when available.") }
        }
        return monitor
    }
    #endif
}

/// Authentication is sent only to the fixed endpoint; redirects cannot forward the credential.
private final class AIUsageRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
