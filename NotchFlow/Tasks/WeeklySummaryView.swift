import SwiftUI
import Charts

struct WeeklySummaryView: View {
    @Environment(\.workspaceNavigation) private var workspace
    @EnvironmentObject private var store: Store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedWeek = Date()

    private var summary: WeeklySummary {
        WeeklySummary(date: selectedWeek, tasks: store.tasks, sessions: store.sessions)
    }

    var body: some View {
        let summary = summary
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        FlowPageHeading(title: "Weekly summary", subtitle: "Focus by day", symbol: "chart.bar.xaxis")
                        Text(summary.interval.start.formatted(date: .abbreviated, time: .omitted)
                             + " - " + summary.days.last!.date.formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                    Button { changeWeek(-1) } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(FlowButtonStyle())
                        .accessibilityLabel("Previous week")
                    Button("This week") { selectedWeek = Date() }
                        .buttonStyle(FlowButtonStyle())
                    Button { changeWeek(1) } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(FlowButtonStyle())
                        .accessibilityLabel("Next week")
                    Spacer()
                    }
                }

                HStack(spacing: 12) {
                    metric("Focus time", value: duration(summary.totalSeconds), symbol: "timer", color: Theme.accent)
                    metric("Completed tasks", value: "\(summary.completedTasks)", symbol: "checkmark.circle", color: Theme.success)
                    metric("Completed blocks", value: "\(summary.completedBlocks)", symbol: "square.stack", color: Theme.warm)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Focus by day").font(.headline)
                    Chart(summary.days) { day in
                        BarMark(x: .value("Day", day.date, unit: .day),
                                y: .value("Minutes", day.seconds / 60))
                            .foregroundStyle(Calendar.current.isDateInToday(day.date) ? Theme.accent : Theme.accent.opacity(0.65))
                            .cornerRadius(5)
                            .annotation(position: .top) {
                                if day.seconds > 0 {
                                    Text("\(Int(day.seconds / 60))")
                                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide)))
                            .accessibilityValue(duration(day.seconds))
                    }
                    .chartXAxis {
                        AxisMarks(values: summary.days.map(\.date)) { _ in
                            AxisValueLabel(format: .dateTime.weekday(.abbreviated), anchor: .top)
                        }
                    }
                    .chartYScale(domain: 0...max(30, (summary.days.map { $0.seconds / 60 }.max() ?? 0) * 1.2))
                    .chartYAxisLabel(String(localized: "Minutes"))
                    .frame(height: 190)
                    Text(comparison(summary)).font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(16)
                .flowSurface()

                HStack(spacing: 20) {
                    goalRing(summary)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Weekly goal").font(.headline)
                        Stepper(value: $store.settings.weeklyGoalMinutes, in: 15...10080, step: 15) {
                            Text("Weekly goal: \(store.settings.weeklyGoalMinutes) minutes")
                                .font(.system(size: 12))
                        }
                        FlowProgressBar(value: goalFraction(summary))
                        Text("\(Int(summary.totalSeconds / 60)) / \(store.settings.weeklyGoalMinutes) min")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                .padding(20)
                .flowSurface()

                Text("Focus by task").font(.headline)
                if summary.taskTimes.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "chart.bar").font(.system(size: 28)).foregroundStyle(Theme.accent)
                        Text("No focus sessions this week").foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .flowSurface()
                }
                ForEach(summary.taskTimes) { task in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(task.title).lineLimit(2)
                                if !task.project.isEmpty { Text(task.project).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Text(duration(task.seconds)).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                        }
                        FlowProgressBar(value: task.seconds / max(1, summary.totalSeconds))
                    }
                    .padding(12)
                    .flowSurface()
                }
                Text("Completed-task totals include tasks completed since this feature was added and still in your list.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .frame(minWidth: workspace == nil ? 620 : 0, minHeight: workspace == nil ? 600 : 0)
        .background(Theme.windowBackground)
        .safeAreaInset(edge: .top, spacing: 0) { FlowWindowNavigation(current: .summary) }
        .flowAppearance()
    }

    private func metric(_ title: LocalizedStringKey, value: String, symbol: String, color: Color) -> some View {
        FlowMetricCard(title: title, value: value, symbol: symbol, color: color)
    }

    private func goalFraction(_ summary: WeeklySummary) -> Double {
        summary.totalSeconds / 60 / Double(max(1, store.settings.weeklyGoalMinutes))
    }

    private func goalRing(_ summary: WeeklySummary) -> some View {
        let fraction = goalFraction(summary)
        return ZStack {
            Circle().stroke(Theme.accent.opacity(0.12), lineWidth: 8)
            Circle().trim(from: 0, to: min(1, max(0, fraction)))
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 3) {
                Image(systemName: fraction >= 1 ? "checkmark" : "target").foregroundStyle(Theme.accent)
                Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                    .font(.system(size: 18, weight: .semibold)).monospacedDigit()
            }
        }
        .frame(width: 92, height: 92)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weekly goal")
        .accessibilityValue(fraction.formatted(.percent.precision(.fractionLength(0))))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: fraction)
    }

    private func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(0, seconds)).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    private func comparison(_ summary: WeeklySummary) -> String {
        let delta = Int((summary.totalSeconds - summary.previousWeekSeconds) / 60)
        return delta >= 0
            ? String(localized: "\(delta) more minutes than the previous week")
            : String(localized: "\(-delta) fewer minutes than the previous week")
    }

    private func changeWeek(_ offset: Int) {
        selectedWeek = Calendar.current.date(byAdding: .weekOfYear, value: offset, to: selectedWeek) ?? selectedWeek
    }
}
