import SwiftUI

struct AIUsageDashboardView: View {
    @ObservedObject var monitor = AIUsageMonitor.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            VStack(spacing: 8) {
                HStack {
                    Label("AI usage", systemImage: "sparkles").font(.system(size: 12, weight: .semibold))
                    Spacer()
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
        let settings = monitor.preferences[provider] ?? AIUsagePreferences()
        let window = reading?.primaryWindow(weekly: settings.weeklyPrimary)
        let stale = reading?.isStale(at: now) == true || monitor.errors[provider] != nil
        return Button {
            if stale && monitor.errors[provider] == nil {
                _Concurrency.Task { await monitor.refresh(provider) }
            } else { AppDelegate.shared?.showAIUsageWindow() }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    AIUsageRings(reading: reading, preferences: settings, stale: stale, size: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(provider.name).font(.system(size: 12, weight: .semibold))
                        Text(window.map { "\($0.title.localized) · \($0.usedPercent.formatted(.number.precision(.fractionLength(0))))% \(String(localized: "used"))" } ?? String(localized: "No reading"))
                            .font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
                        Text(monitor.refreshing.contains(provider) ? String(localized: "Refreshing…")
                             : stale ? String(localized: "Last known reading")
                             : monitor.connected.contains(provider) ? (reading == nil ? String(localized: "Waiting for the first reading…") : String(localized: "Connected")) : String(localized: "Connect"))
                            .font(.system(size: 9)).foregroundStyle(stale ? .orange : Theme.textSecondary)
                    }
                }
                if let error = monitor.errors[provider] {
                    Label("Reconnect", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.orange).help(error)
                } else if stale {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.orange)
                } else if let reset = window?.resetsAt {
                    Text(aiResetLabel(reset, now: now, remaining: settings.remainingTime))
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
            .background(Theme.windowBackground)
            .safeAreaInset(edge: .top, spacing: 0) { FlowWindowNavigation(current: .ai) }
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
        let settings = monitor.preferences[provider] ?? AIUsagePreferences()
        let connected = monitor.connected.contains(provider)
        let refreshing = monitor.refreshing.contains(provider)
        let stale = reading?.isStale(at: now) == true || monitor.errors[provider] != nil
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                AIUsageRings(reading: reading, preferences: settings, stale: stale, size: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.name).font(.headline)
                    Text(settings.weeklyPrimary ? "Main ring: weekly limit" : "Main ring: session limit")
                        .font(.caption).foregroundStyle(.secondary)
                }
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
                                Text(aiResetLabel(reset, now: now, remaining: settings.remainingTime))
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
            DisclosureGroup("Rings and renewal") {
                VStack(alignment: .leading, spacing: 12) {
                    FlowSegmentedControl(title: "Weekly ring", selection: preference(provider, \.weeklyRing),
                                         values: [AIWeeklyRingStyle.off, .inside, .outside], label: {
                        switch $0 {
                        case .off: return "Off"
                        case .inside: return "Inside"
                        case .outside: return "Outside"
                        }
                    })
                    Toggle("Weekly limit in main ring", isOn: preference(provider, \.weeklyPrimary))
                    Toggle("Show percentage", isOn: preference(provider, \.showPercent))
                    Toggle("Show time until renewal", isOn: preference(provider, \.remainingTime))
                    Text("The thin ring shows the other allowance. Gray rings mean no reading; faded rings show an outdated reading.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 10)
            }
            DisclosureGroup("Usage alerts") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Session alerts at 80% and 100%", isOn: alertPreference(provider, \.sessionAlerts))
                    Toggle("Weekly alerts at 80% and 100%", isOn: alertPreference(provider, \.weeklyAlerts))
                    Toggle("Notify when a limit renews", isOn: alertPreference(provider, \.resetAlerts))
                    Toggle("Play alert sound", isOn: preference(provider, \.alertSound))
                    Text("Each threshold alerts once per window, even after restarting. Renewal is detected on the next successful refresh. Enable NotchFlow notifications in System Settings.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 10)
            }
            costSection(provider, reading: reading, now: now, stale: stale)
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

    private func preference<Value>(_ provider: AIProvider, _ path: WritableKeyPath<AIUsagePreferences, Value>) -> Binding<Value> {
        Binding(get: { (monitor.preferences[provider] ?? AIUsagePreferences())[keyPath: path] },
                set: { value in
                    var settings = monitor.preferences[provider] ?? AIUsagePreferences()
                    settings[keyPath: path] = value
                    monitor.updatePreferences(provider, settings)
                })
    }

    private func alertPreference(_ provider: AIProvider, _ path: WritableKeyPath<AIUsagePreferences, Bool>) -> Binding<Bool> {
        let binding = preference(provider, path)
        return Binding(get: { binding.wrappedValue }, set: { value in
            binding.wrappedValue = value
            if value { NotificationService.shared.requestAuthorizationIfNeeded() }
        })
    }

    private func costSection(_ provider: AIProvider, reading: AIUsageReading?, now: Date, stale: Bool) -> some View {
        let settings = monitor.preferences[provider] ?? AIUsagePreferences()
        let estimate = stale ? nil : reading.flatMap { settings.weeklyCost(for: $0, at: now) }
        return DisclosureGroup("Subscription cost estimate") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TextField("Monthly price", value: preference(provider, \.monthlyPrice), format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(.roundedBorder)
                    Picker("Currency", selection: preference(provider, \.currency)) {
                        Text("BRL").tag("BRL")
                        Text("USD").tag("USD")
                        Text("EUR").tag("EUR")
                    }.frame(width: 160)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Weekly allowance value").font(.caption).foregroundStyle(.secondary)
                        Text(settings.monthlyPrice > 0 ? (settings.monthlyPrice / 4.35).formatted(.currency(code: settings.currency)) : "—")
                            .font(.title3.weight(.semibold))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Used this window (estimate)").font(.caption).foregroundStyle(.secondary)
                        Text(estimate.map { $0.formatted(.currency(code: settings.currency)) } ?? "—")
                            .font(.title3.weight(.semibold))
                    }
                }
                Text("Enter the monthly price you actually pay. Estimate = monthly price ÷ 4.35 × weekly usage. This allocates subscription value; it is not an extra charge or a token bill. Requires a current weekly reading.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 10)
        }
    }

}

private struct AIUsageRing: View {
    let window: AIUsageWindow?
    let stale: Bool
    let size: CGFloat
    var showPercent = true
    var lineWidth: CGFloat = 3
    private var color: Color {
        guard let percent = window?.usedPercent else { return .secondary }
        return percent >= 100 ? .red : percent >= 80 ? .orange : Theme.accent
    }
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle().trim(from: 0, to: window?.fraction ?? 0)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if showPercent {
                Text(window.map { "\($0.usedPercent.formatted(.number.precision(.fractionLength(0))))%" } ?? "—")
                    .font(.system(size: size > 50 ? 14 : 12, weight: .semibold))
                    .monospacedDigit()
            }
        }
        .frame(width: size, height: size).opacity(stale ? 0.55 : 1)
    }
}


private struct AIUsageRings: View {
    let reading: AIUsageReading?
    let preferences: AIUsagePreferences
    let stale: Bool
    let size: CGFloat

    var body: some View {
        let main = reading?.primaryWindow(weekly: preferences.weeklyPrimary)
        let secondary = preferences.weeklyPrimary ? reading?.sessionWindow : reading?.weeklyWindow
        let hasSecondary = secondary != nil && secondary?.id != main?.id && preferences.weeklyRing != .off
        let mainSize = hasSecondary && preferences.weeklyRing == .outside ? size - 12 : size
        ZStack {
            AIUsageRing(window: main, stale: stale, size: mainSize, showPercent: preferences.showPercent)
            if hasSecondary {
                AIUsageRing(window: secondary, stale: stale,
                            size: preferences.weeklyRing == .outside ? size : size - 12, showPercent: false, lineWidth: 2)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(main.map {
            "\($0.title.localized): \($0.usedPercent.formatted())%" +
            (hasSecondary ? "; \(secondary!.title.localized): \(secondary!.usedPercent.formatted())%" : "") +
            (stale ? "; \(String(localized: "Last known reading"))" : "")
        } ?? String(localized: "No reading"))
    }
}

private func aiResetLabel(_ reset: Date, now: Date, remaining: Bool) -> String {
    guard reset > now else { return String(localized: "Awaiting updated limit") }
    guard remaining else {
        return String(localized: "Resets at \(reset.formatted(date: .abbreviated, time: .shortened))")
    }
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = reset.timeIntervalSince(now) >= 86400 ? [.day, .hour] : [.hour, .minute]
    formatter.unitsStyle = .abbreviated
    formatter.maximumUnitCount = 2
    let duration = formatter.string(from: max(60, reset.timeIntervalSince(now))) ?? "—"
    return String(localized: "Renews in \(duration)")
}
