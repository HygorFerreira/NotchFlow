import SwiftUI

struct MachineDashboardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cpuUsage: Double?
    @State private var usedMemory: UInt64?
    @State private var cpuHistory: [Double?] = []
    @State private var memoryHistory: [Double?] = []
    @State private var didSample = false
    private let totalMemory = ProcessInfo.processInfo.physicalMemory
    private let cpuColor = Color(red: 0.40, green: 0.66, blue: 1)
    private let memoryColor = Color(red: 0.64, green: 0.53, blue: 1)

    private var memoryUsage: Double? {
        usedMemory.map { min(1, Double($0) / Double(max(totalMemory, 1))) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Machine usage", systemImage: "desktopcomputer")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(didSample && cpuUsage != nil && usedMemory != nil ? Theme.medication : Theme.textSecondary)
                        .frame(width: 5, height: 5)
                    Text(didSample ? (cpuUsage != nil && usedMemory != nil ? String(localized: "Live") : String(localized: "Unavailable")) : String(localized: "Sampling…"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .help("Updates every 2 seconds")
            }
            .frame(height: NotchViewModel.headerHeight)

            HStack(spacing: 10) {
                metric(title: "CPU", symbol: "cpu", value: cpuUsage, history: cpuHistory,
                       color: cpuColor, detail: String(localized: "Across all processor cores"))
                metric(title: "Memory", symbol: "memorychip", value: memoryUsage, history: memoryHistory,
                       color: memoryColor, detail: memoryDetail)
            }
            HStack(spacing: 5) {
                Image(systemName: "info.circle")
                Text("Last 60 seconds · updates every 2s")
                Spacer()
            }
            .font(.system(size: 10))
            .foregroundStyle(Theme.textSecondary)
            .frame(height: 16)
            .help("Memory includes active, wired and compressed RAM.")
        }
        .foregroundStyle(Theme.textPrimary)
        .task {
            var previous = MachineUsage.cpuTicks()
            usedMemory = MachineUsage.usedMemory()
            cpuUsage = nil
            didSample = false
            cpuHistory = []
            memoryHistory = []
            while !_Concurrency.Task.isCancelled {
                do { try await _Concurrency.Task.sleep(for: .seconds(2)) }
                catch { return }
                guard !_Concurrency.Task.isCancelled else { return }
                let current = MachineUsage.cpuTicks()
                cpuUsage = current.flatMap { ticks in previous.flatMap { ticks.usage(since: $0) } }
                previous = current
                usedMemory = MachineUsage.usedMemory()
                didSample = true
                cpuHistory = Array((cpuHistory + [cpuUsage]).suffix(30))
                memoryHistory = Array((memoryHistory + [memoryUsage]).suffix(30))
            }
        }
    }

    private var memoryDetail: String {
        guard let usedMemory else { return String(localized: didSample ? "Unavailable" : "Waiting for a sample…") }
        return "\(bytes(usedMemory)) / \(bytes(totalMemory))"
    }

    private func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }

    private func metric(title: LocalizedStringKey, symbol: String, value: Double?, history: [Double?],
                        color: Color, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(color)
                Text(title).foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            .font(.system(size: 11, weight: .semibold))
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(color.opacity(0.14), lineWidth: 4)
                    Circle().trim(from: 0, to: value ?? 0)
                        .stroke(color.gradient, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(color)
                }
                .frame(width: 42, height: 42)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(value.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—")
                        .font(.system(size: 25, weight: .semibold, design: .rounded).monospacedDigit())
                    Text(detail)
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .help(detail)
                }
            }
            UsageSparkline(samples: history)
                .stroke(color.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .frame(height: 19)
                .background(alignment: .bottom) {
                    Rectangle().fill(color.opacity(0.1)).frame(height: 1)
                }
                .accessibilityHidden(true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 124)
        .background {
            RoundedRectangle(cornerRadius: Theme.panelCorner)
                .fill(LinearGradient(colors: [color.opacity(0.12), Theme.panel], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.panelCorner).stroke(color.opacity(0.18), lineWidth: 1)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: value)
        .accessibilityElement(children: .combine)
    }
}

/// Fixed 60-second scale; missing readings break the line rather than showing zero usage.
private struct UsageSparkline: Shape {
    let samples: [Double?]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var connected = false
        for (index, sample) in samples.enumerated() {
            guard let sample else { connected = false; continue }
            let point = CGPoint(x: rect.minX + CGFloat(30 - samples.count + index) / 29 * rect.width,
                                y: rect.maxY - CGFloat(min(1, max(0, sample))) * rect.height)
            if connected { path.addLine(to: point) }
            else { path.move(to: point) }
            connected = true
        }
        return path
    }
}
