import SwiftUI

struct AIUsageDashboardView: View {
    @ObservedObject var monitor = AIUsageMonitor.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            VStack(spacing: 8) {
                HStack {
                    Label("AI usage", systemImage: "sparkles").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button { AppDelegate.shared?.showAIUsageWindow() } label: {
                        Image(systemName: "slider.horizontal.3").frame(width: 24, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help("Connect AI services")
                    .accessibilityLabel("Connect AI services")
                }
                HStack(spacing: 10) {
                    ForEach(AIProvider.allCases) { provider in
                        compactCard(provider, now: timeline.date)
                    }
                }
                Text("Account limits · automatic refresh every 2 min")
                    .font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
            }
            .foregroundStyle(Theme.textPrimary)
        }
    }

    private func compactCard(_ provider: AIProvider, now: Date) -> some View {
        let reading = monitor.readings[provider]
        let window = reading?.windows.first
        let stale = reading?.isStale(at: now) == true || monitor.errors[provider] != nil
        return Button { AppDelegate.shared?.showAIUsageWindow() } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    AIUsageRing(window: window, stale: stale, size: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(provider.name).font(.system(size: 12, weight: .semibold))
                        Text(window?.title.localized ?? String(localized: "No reading"))
                            .font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
                        Text(stale ? String(localized: "Last known reading")
                             : monitor.connected.contains(provider) ? String(localized: "Connected") : String(localized: "Connect"))
                            .font(.system(size: 9)).foregroundStyle(stale ? .orange : Theme.textSecondary)
                    }
                }
                if let reset = window?.resetsAt {
                    Text(reset > now ? String(localized: "Resets at \(reset.formatted(date: .abbreviated, time: .shortened))")
                         : String(localized: "Awaiting updated limit"))
                        .font(.system(size: 9)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                } else {
                    Text("View limits and connections").font(.system(size: 9)).foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading).frame(height: 110)
            .flowSurface()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

struct AIUsageWindowView: View {
    @ObservedObject var monitor = AIUsageMonitor.shared
    @State private var signInProvider: AIProvider?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    FlowPageHeading(title: "AI usage", subtitle: "Your account limits at a glance", symbol: "sparkles", color: Theme.accent)
                    Text("Enable a service to follow the account already signed in on your Mac. Sign in and switch accounts in the coding tool itself.")
                        .font(.callout).foregroundStyle(.secondary)
                    ForEach(AIProvider.allCases) { provider in
                        providerCard(provider, now: timeline.date)
                    }
                    Text("Usage is refreshed every 2 minutes while NotchFlow is open. These services use internal endpoints that may change. Credentials are read only and never copied into NotchFlow data.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .flowAppearance()
        }
        .sheet(item: $signInProvider) { provider in
            VStack(alignment: .leading, spacing: 16) {
                Text(provider.name).font(.title2.weight(.semibold))
                Text("Run this command in your terminal and finish signing in through the coding tool. Return here when you are done.")
                Text(provider == .codex ? "codex login" : "claude auth login")
                    .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                HStack {
                    Button("Done") {
                        signInProvider = nil
                        monitor.setMonitoring(provider, enabled: true)
                    }
                    .keyboardShortcut(.defaultAction)
                    Button("Cancel") { signInProvider = nil }.keyboardShortcut(.cancelAction)
                }
            }
            .padding(24).frame(width: 430).flowAppearance()
        }
    }

    private func providerCard(_ provider: AIProvider, now: Date) -> some View {
        let reading = monitor.readings[provider]
        let connected = monitor.connected.contains(provider)
        let refreshing = monitor.refreshing.contains(provider)
        let stale = reading?.isStale(at: now) == true || monitor.errors[provider] != nil
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(provider.name).font(.headline)
                Spacer()
                if refreshing { ProgressView().controlSize(.small) }
                if connected {
                    Button("Refresh") { _Concurrency.Task { await monitor.refresh(provider) } }
                        .disabled(refreshing)
                }
                Toggle(provider.name, isOn: Binding(
                    get: { monitor.connected.contains(provider) },
                    set: { monitor.setMonitoring(provider, enabled: $0) }
                ))
                .labelsHidden().toggleStyle(.switch).accessibilityLabel(provider.name)
                .help("Turn off to stop monitoring. You stay signed in to the coding tool.")
            }
            if let error = monitor.errors[provider] {
                Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
            }
            if let reading {
                ForEach(reading.windows) { window in
                    HStack(spacing: 14) {
                        AIUsageRing(window: window, stale: stale, size: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(window.title.localized).font(.subheadline.weight(.semibold))
                            Text("Remaining: \((window.remainingPercent / 100).formatted(.percent.precision(.fractionLength(0))))")
                                .font(.caption).foregroundStyle(.secondary)
                            if let reset = window.resetsAt {
                                Text(reset > now ? String(localized: "Resets at \(reset.formatted(date: .abbreviated, time: .shortened))")
                                     : String(localized: "Awaiting updated limit"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .accessibilityElement(children: .combine)
                }
                HStack {
                    Text(stale ? "Last known reading" : "Last updated")
                    Text(reading.fetchedAt, format: .dateTime.day().month().hour().minute())
                }
                .font(.caption).foregroundStyle(stale ? .orange : .secondary)
            } else {
                Text(connected ? "Waiting for the first reading…" : "Connect to see your usage limits")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Button(connected ? "Switch account…" : "Sign in…") {
                    if provider == .codex { monitor.openCodex() }
                    else { signInProvider = provider }
                }
                if connected, monitor.errors[provider] != nil {
                    Button("Allow access…") {
                        if provider == .codex { monitor.connectFile(provider, authorizingDefault: true) }
                        else { monitor.connectClaudeKeychain() }
                    }
                }
                Spacer()
                Link("Open usage page", destination: provider.usageURL)
            }
            .font(.callout)
            Text(connected ? "Switch accounts in the coding tool; NotchFlow follows the login. Turning this off does not sign you out."
                 : "Turn on to monitor the existing login. If you are not signed in yet, use Sign in first.")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Connection options") {
                VStack(alignment: .leading, spacing: 10) {
                    Button(provider == .codex ? "Choose Codex folder…" : "Choose Claude folder…") { monitor.connectFile(provider) }
                    if provider == .codex { Button("Sign in with CLI…") { signInProvider = provider } }
                    Text("Use a different folder only for a custom profile. macOS may require folder or Keychain permission to read an existing login.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
            .font(.caption)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading).flowSurface()
    }
}

private struct AIUsageRing: View {
    let window: AIUsageWindow?
    let stale: Bool
    let size: CGFloat
    private var color: Color {
        guard let percent = window?.usedPercent else { return .secondary }
        return percent >= 95 ? .red : percent >= 80 ? .orange : Theme.accent
    }
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.15), lineWidth: 4)
            Circle().trim(from: 0, to: window?.fraction ?? 0)
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(window.map { "\($0.usedPercent.formatted(.number.precision(.fractionLength(0))))%" } ?? "—")
                .font(.system(size: size > 50 ? 14 : 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(width: size, height: size).opacity(stale ? 0.55 : 1)
    }
}
