import SwiftUI

/// Shared adaptive palette; the physical notch keeps its dark appearance.
enum Theme {
    /// A quiet graphite palette, with one blue accent for actions and progress.
    private static func adaptive(_ name: String, light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: NSColor.Name(name)) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((rgb >> 16) & 255) / 255,
                           green: Double((rgb >> 8) & 255) / 255,
                           blue: Double(rgb & 255) / 255, alpha: 1)
        })
    }

    static let accent = adaptive("FlowAccent", light: 0x376AC8, dark: 0x7AA4EF)
    static let onAccent = adaptive("FlowOnAccent", light: 0xFFFFFF, dark: 0x101722)
    static let border = Color.primary.opacity(0.09)
    static let selection = Color.primary.opacity(0.09)
    static let control = Color.primary.opacity(0.055)
    static let warm = Color.orange
    static let danger = Color.red
    static let medication = accent
    static let pill = Color.black
    static let panel = adaptive("FlowPanel", light: 0xFFFFFF, dark: 0x202125)
    static let panelHover = adaptive("FlowPanelHover", light: 0xF0F1F3, dark: 0x292B30)
    static let textPrimary = adaptive("FlowText", light: 0x24252B, dark: 0xE8E9ED)
    static let textSecondary = adaptive("FlowSecondaryText", light: 0x696A73, dark: 0xA1A2AC)
    static let streakEmpty = Color(white: 0.14)

    static let sidebar = adaptive("FlowSidebar", light: 0xEEEFF1, dark: 0x121316)

    static let notchCorner: CGFloat = 22
    static let panelCorner: CGFloat = 12
    static let pageTitle = Font.system(size: 24, weight: .semibold)
    static let success = Color.green
    static let windowBackground = adaptive("FlowWindow", light: 0xF6F6F7, dark: 0x18191C)
}

/// Fixed dark surfaces for the notch, matching the minimal design reference.
enum NotchPalette {
    static let background = Color(hex: "#1D1F23")
    static let card = Color(hex: "#25272D")
    static let cardHover = Color(hex: "#2C2F36")
    static let secondary = Color(hex: "#A6A9B3")
    static let text = Color(hex: "#ECEEF4")
    static let accent = Color(hex: "#4D7FD8")
    static let border = Color.white.opacity(0.065)
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
    @AppStorage(FlowAppearance.liquidGlassKey) private var liquidGlass = false
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
                    .strokeBorder(Theme.border, lineWidth: 1)
            }

    }
}

struct FlowAppearanceModifier: ViewModifier {
    @AppStorage(FlowAppearance.themeKey) private var mode = FlowAppearance.Mode.system.rawValue
    func body(content: Content) -> some View {
        Group {
        #if DEBUG
        content.preferredColorScheme(Snapshots.isRequested ? nil : (FlowAppearance.Mode(rawValue: mode) ?? .system).scheme)
        #else
        content.preferredColorScheme((FlowAppearance.Mode(rawValue: mode) ?? .system).scheme)
        #endif
        }
        .foregroundStyle(Theme.textPrimary)
        .tint(Theme.accent)
        .buttonStyle(FlowButtonStyle())
    }
}

extension View {
    func flowAppearance() -> some View { modifier(FlowAppearanceModifier()) }
    func flowSurface() -> some View { modifier(FlowSurface()) }
}

/// Compact, matte controls shared by forms, toolbars and overview actions.
struct FlowButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        FlowButtonBody(configuration: configuration, prominent: prominent)
    }
}

private struct FlowButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(configuration.role == .destructive ? Theme.danger : prominent ? Theme.onAccent : Theme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 32)
            .background(prominent ? Theme.accent : hovered && enabled ? Theme.selection : Theme.control,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(prominent ? Color.clear : Theme.border, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
    }
}

struct FlowTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.textFieldStyle(.roundedBorder).controlSize(.large)
    }
}

/// A neutral segmented control with consistent spacing in every window.
struct FlowSegmentedControl<Value: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Value
    let values: [Value]
    let label: (Value) -> String

    var body: some View {
        HStack(spacing: 3) {
            ForEach(values, id: \.self) { value in
                Button { selection = value } label: {
                    Text(label(value).localized)
                        .font(.system(size: 11, weight: selection == value ? .semibold : .medium))
                        .foregroundStyle(selection == value ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                        .background(selection == value ? Theme.selection : .clear,
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(FlowCompactButtonStyle())
                .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Theme.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

struct FlowProgressBar: View {
    var value: Double
    var height: CGFloat = 6
    var color: Color = Theme.accent
    private var fraction: Double { value.isFinite ? min(1, max(0, value)) : 0 }
    var body: some View {
        GeometryReader { geometry in
            Capsule()
                .fill(color)
                .frame(width: geometry.size.width * fraction)
        }
        .frame(height: height)
        .background(Theme.control, in: Capsule())
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
                    .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                    .frame(width: 22, height: 22)
                Text(title).font(.system(size: 12, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(selected ? Theme.selection : .clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(FlowCompactButtonStyle())
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
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 32, height: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.pageTitle).tracking(-0.6)
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
                        .foregroundStyle(current == destination ? Theme.textPrimary : Theme.textSecondary)
                        .background(current == destination ? Theme.selection : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(FlowCompactButtonStyle())
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
            FlowBackdrop(shape: Rectangle(), color: Theme.sidebar)
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
                .strokeBorder(selected ? Theme.border : Color.clear))
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
                .foregroundStyle(Theme.textSecondary)
            Text("NotchFlow")
                .font(.system(size: 17, weight: .semibold))
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
                    .foregroundStyle(Theme.textSecondary)
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
