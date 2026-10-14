import SwiftUI

/// Shared adaptive palette; the physical notch keeps its dark appearance.
enum Theme {
    /// Semantic macOS colors follow accent, contrast, and appearance preferences.
    static let accent = Color(nsColor: .controlAccentColor)
    static let onAccent = Color.white
    static let border = Color(nsColor: .separatorColor)
    static let warm = Color.orange
    static let danger = Color.red
    static let medication = Color.teal
    static let pill = Color.black
    static let panel = Color(nsColor: .controlBackgroundColor)
    static let panelHover = Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    static let textPrimary = Color.primary
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let streakEmpty = Color(white: 0.14)

    static let sidebar = Color(nsColor: .windowBackgroundColor)

    static let notchCorner: CGFloat = 22
    static let panelCorner: CGFloat = 14
    static let success = Color.green
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
}

/// A rounded-bottom "notch" shape: flush square top (meets the screen edge),
/// generously rounded bottom corners.
struct NotchShape: Shape {
    var topRadius: CGFloat = 8
    var bottomRadius: CGFloat = Theme.notchCorner

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let tr = min(topRadius, rect.width / 2)
        let br = min(bottomRadius, rect.width / 2)
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // top edge with slight inner curve down into the notch
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - br, y: rect.maxY),
                       control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + br, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - br),
                       control: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        _ = tr
        return p
    }
}

/// An open-top rounded frame inset from the pill edges — the accent "tray" that
/// hugs the left, bottom, and right (never the top, which meets the screen edge),
/// with visible padding between it and the black pill. Used as a static outline
/// when expanded and as a progress track when a timer is running.
struct NotchTrayShape: Shape {
    var inset: CGFloat = 6
    var topInset: CGFloat = 6
    var corner: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(corner, (rect.width - inset * 2) / 2)
        let left = rect.minX + inset
        let right = rect.maxX - inset
        let bottom = rect.maxY - inset
        let top = rect.minY + topInset

        p.move(to: CGPoint(x: left, y: top))
        p.addLine(to: CGPoint(x: left, y: bottom - r))
        p.addQuadCurve(to: CGPoint(x: left + r, y: bottom),
                       control: CGPoint(x: left, y: bottom))
        p.addLine(to: CGPoint(x: right - r, y: bottom))
        p.addQuadCurve(to: CGPoint(x: right, y: bottom - r),
                       control: CGPoint(x: right, y: bottom))
        p.addLine(to: CGPoint(x: right, y: top))
        return p
    }
}


/// A persisted appearance preference shared by every window and the notch preview.
enum FlowAppearance {
    static let themeKey = "appearance.theme"
    enum Mode: String, CaseIterable {
        case system, light, dark
        var scheme: ColorScheme? {
            switch self { case .system: nil; case .light: .light; case .dark: .dark }
        }
        var title: LocalizedStringKey {
            switch self { case .system: "System"; case .light: "Light"; case .dark: "Dark" }
        }
    }
    static let liquidGlassKey = "appearance.liquidGlass"
    static let transparencyKey = "appearance.glassTransparency"
}

/// Native glass on macOS 26; material on earlier systems. Accessibility wins
/// over the appearance preference when the user requests opaque surfaces.
struct FlowBackdrop<S: Shape>: View {
    let shape: S
    var color: Color = Theme.panel
    var allowsGlass = false
    @AppStorage(FlowAppearance.liquidGlassKey) private var liquidGlass = true
    @AppStorage(FlowAppearance.transparencyKey) private var transparency = 50.0
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var fraction: Double {
        transparency.isFinite ? min(80, max(0, transparency)) / 100 : 0.5
    }

    @ViewBuilder var body: some View {
        if liquidGlass && allowsGlass && !reduceTransparency && fraction > 0 {
            #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                Color.clear
                    .background(shape.fill(color.opacity(1 - fraction)))
                    .glassEffect(.regular.tint(color.opacity((1 - fraction) * 0.3)), in: shape)
            } else {
                shape.fill(.regularMaterial)
                    .overlay(shape.fill(color.opacity(1 - fraction)))
            }
            #else
            shape.fill(.regularMaterial)
                .overlay(shape.fill(color.opacity(1 - fraction)))
            #endif
        } else {
            shape.fill(color)
        }
    }
}

/// Shared surfaces preserve native light appearance in Settings and the dark notch palette.
struct FlowSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                FlowBackdrop(
                    shape: RoundedRectangle(cornerRadius: Theme.panelCorner, style: .continuous),
                    color: Theme.panel, allowsGlass: false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.panelCorner, style: .continuous)
                    .strokeBorder(Theme.border.opacity(0.75), lineWidth: 1)
            }

    }
}

struct FlowAppearanceModifier: ViewModifier {
    @AppStorage(FlowAppearance.themeKey) private var mode = FlowAppearance.Mode.system.rawValue
    func body(content: Content) -> some View {
        #if DEBUG
        content.preferredColorScheme(Snapshots.isRequested ? nil : (FlowAppearance.Mode(rawValue: mode) ?? .system).scheme)
        #else
        content.preferredColorScheme((FlowAppearance.Mode(rawValue: mode) ?? .system).scheme)
        #endif
    }
}

extension View {
    func flowAppearance() -> some View { modifier(FlowAppearanceModifier()) }
    func flowSurface() -> some View { modifier(FlowSurface()) }
}

/// Let the active macOS SDK draw controls and provide keyboard and pointer feedback.
struct FlowButtonStyle: PrimitiveButtonStyle {
    var prominent = false

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if prominent {
            Button(role: configuration.role, action: configuration.trigger) { configuration.label }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
        } else {
            Button(role: configuration.role, action: configuration.trigger) { configuration.label }
                .buttonStyle(.bordered)
                .controlSize(.regular)
        }
    }
}

struct FlowTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.textFieldStyle(.roundedBorder).controlSize(.large)
    }
}

struct FlowProgressBar: View {
    var value: Double
    var height: CGFloat = 6
    var color: Color = Theme.accent
    private var fraction: Double { value.isFinite ? min(1, max(0, value)) : 0 }
    var body: some View {
        ProgressView(value: fraction)
            .progressViewStyle(.linear)
            .tint(color)
            .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue(fraction.formatted(.percent.precision(.fractionLength(0))))
    }
}

struct FlowNavigationRow: View {
    var selected = false
    let title: LocalizedStringKey
    let symbol: String
    var color: Color = Theme.accent
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selected ? Theme.onAccent : color)
                    .frame(width: 30, height: 30)
                    .background((selected ? Theme.onAccent : color).opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                Text(title).font(.system(size: 12, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Theme.onAccent : Theme.textPrimary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(FlowButtonStyle(prominent: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct FlowPageHeading: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let symbol: String
    var color: Color = Theme.accent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 24, weight: .bold))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
}

/// The same destinations stay within reach from every standalone overview window.
struct FlowWindowNavigation: View {
    typealias Destination = WorkspaceDestination
    let current: Destination
    @Environment(\.flowFocusTimer) private var focus
    @Environment(\.workspaceNavigation) private var workspace
    var body: some View {
        if workspace == nil {
        VStack(spacing: 0) {
        HStack(spacing: 6) {
            ForEach(Destination.allCases) { destination in
                Button { destination.open() } label: {
                    Label(destination.rawValue.localized, systemImage: destination.symbol)
                        .font(.system(size: 11, weight: current == destination ? .semibold : .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .foregroundStyle(current == destination ? Theme.accent : Theme.textSecondary)
                        .background(current == destination ? Theme.accent.opacity(0.13) : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(FlowCompactButtonStyle(selected: current == destination))
                .accessibilityAddTraits(current == destination ? .isSelected : [])
            }
            Spacer(minLength: 0)
            Button { AppDelegate.shared?.showSettingsWindow() } label: {
                Image(systemName: "gearshape").frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help("Settings")
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            FlowBackdrop(shape: Rectangle(), color: Theme.sidebar, allowsGlass: true)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
        if let focus {
            FlowFocusControls(focus: focus)
                .padding(.horizontal, 14)
        }
        }
        }
    }
}

/// Compact controls share pointer, keyboard, and press feedback.
struct FlowCompactButtonStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        CompactButtonBody(configuration: configuration, selected: selected)
    }
}

private struct CompactButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let selected: Bool
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        configuration.label
            .background(Color.primary.opacity(hovered && enabled ? 0.07 : 0),
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(selected ? Theme.accent.opacity(0.4) : Color.clear))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .scaleEffect(configuration.isPressed && enabled && !reduceMotion ? 0.96 : 1)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct FlowFocusBadge: View {
    @EnvironmentObject private var focus: FocusTimer
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: focus.state == .paused ? "pause.circle.fill" : "timer")
            Text(focus.state == .paused ? "Paused" : "In focus")
            Text(focus.timeLabel).monospacedDigit()
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(Theme.accent.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// Shared brand signature for the app's navigation surfaces.
struct FlowBrand: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.path")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("NotchFlow")
                .font(.system(size: 19, weight: .bold))
                .tracking(-0.6)
        }
        .accessibilityElement(children: .combine)
    }
}

struct FlowMetricCard: View {
    let title: LocalizedStringKey
    let value: String
    let symbol: String
    var color: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                    .font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 0)
                Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textSecondary)
            }
            Text(value).font(.system(size: 23, weight: .semibold)).monospacedDigit().tracking(-0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .flowSurface()
        .accessibilityElement(children: .combine)
    }
}

private struct FlowFocusTimerKey: EnvironmentKey {
    static var defaultValue: FocusTimer? { nil }
}

extension EnvironmentValues {
    var flowFocusTimer: FocusTimer? {
        get { self[FlowFocusTimerKey.self] }
        set { self[FlowFocusTimerKey.self] = newValue }
    }
}

/// Every overview exposes the same running session without starting another timer.
struct FlowFocusControls: View {
    @ObservedObject var focus: FocusTimer

    var body: some View {
        if focus.isActive {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Label(focus.state == .paused ? "Paused" : "In focus",
                          systemImage: focus.state == .paused ? "pause.circle" : "timer")
                        .foregroundStyle(Theme.accent)
                    Spacer(minLength: 4)
                    Text(focus.timeLabel).monospacedDigit()
                        .accessibilityLabel("Time remaining")
                        .accessibilityValue(focus.timeLabel)
                }
                .font(.system(size: 12, weight: .semibold))
                HStack(spacing: 8) {
                    Text(focus.activeTask?.title ?? String(localized: "Focus time"))
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                    Button { focus.togglePause() } label: {
                        Image(systemName: focus.state == .paused ? "play.fill" : "pause.fill")
                    }
                    .accessibilityLabel(Text(focus.state == .paused ? "Resume" : "Pause"))
                    .help(focus.state == .paused ? String(localized: "Resume") : String(localized: "Pause"))
                    Button { focus.stop() } label: { Image(systemName: "stop.fill") }
                        .accessibilityLabel("Stop focus")
                        .help("Stop focus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(12)
            .flowSurface()
            .padding(.vertical, 6)
        }
    }
}

@MainActor
extension WorkspaceDestination {
    func open() { AppDelegate.shared?.showWorkspace(self) }
}

private struct WorkspaceNavigationKey: EnvironmentKey {
    static var defaultValue: WorkspaceNavigation? { nil }
}

extension EnvironmentValues {
    var workspaceNavigation: WorkspaceNavigation? {
        get { self[WorkspaceNavigationKey.self] }
        set { self[WorkspaceNavigationKey.self] = newValue }
    }
}
