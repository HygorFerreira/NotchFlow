import SwiftUI
import Charts

struct WeeklySummaryView: View {
    @EnvironmentObject private var store: Store
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
                        Label("Weekly summary", systemImage: "chart.bar.xaxis").font(.system(size: 26, weight: .bold, design: .rounded))
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
                    metric("Focus time", value: duration(summary.totalSeconds))
                    metric("Completed tasks", value: "\(summary.completedTasks)")
                    metric("Completed blocks", value: "\(summary.completedBlocks)")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Focus by day").font(.headline)
                    Chart(summary.days) { day in
                        BarMark(x: .value("Day", day.date, unit: .day),
                                y: .value("Minutes", day.seconds / 60))
                            .foregroundStyle(Theme.accent.gradient)
                            .cornerRadius(5)
                            .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide)))
                            .accessibilityValue(duration(day.seconds))
                    }
                    .chartXAxis {
                        AxisMarks(values: summary.days.map(\.date)) { _ in
                            AxisValueLabel(format: .dateTime.weekday(.abbreviated), anchor: .top)
                        }
                    }
                    .chartYAxisLabel(String(localized: "Minutes"))
                    .frame(height: 190)
                    Text(comparison(summary)).font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(16)
                .flowSurface()

                VStack(alignment: .leading, spacing: 10) {
                    Stepper(value: $store.settings.weeklyGoalMinutes, in: 15...10080, step: 15) {
                        Text("Weekly goal: \(store.settings.weeklyGoalMinutes) minutes")
                    }
                    FlowProgressBar(value: summary.totalSeconds / 60 / Double(max(1, store.settings.weeklyGoalMinutes)))
                    Text("\(Int(summary.totalSeconds / 60)) / \(store.settings.weeklyGoalMinutes) min")
                        .font(.caption).foregroundStyle(.secondary)
                }

                .padding(16)
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
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(task.title).lineLimit(2)
                            if !task.project.isEmpty { Text(task.project).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Text(duration(task.seconds)).monospacedDigit()
                    }
                    .padding(12)
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
                }
                Text("Completed-task totals include tasks completed since this feature was added and still in your list.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .frame(minWidth: 620, minHeight: 600)
        .background(Theme.windowBackground)
        .safeAreaInset(edge: .top, spacing: 0) { FlowWindowNavigation(current: .summary) }
        .preferredColorScheme(.dark)
    }

    private func metric(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .flowSurface()
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
