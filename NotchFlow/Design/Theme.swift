import SwiftUI

/// Shared adaptive palette; the physical notch keeps its dark appearance.
enum Theme {
    /// Follows the user's macOS accent color (System Settings › Appearance).
    static let accent = Color(nsColor: .controlAccentColor)
    static let danger = Color(red: 0.95, green: 0.23, blue: 0.23)    // pause red
    static let medication = Color(red: 0.18, green: 0.78, blue: 0.72)
    static let pill = Color.black
    static let panel = adaptive(light: "#FFFFFF", dark: "#172131")
    static let panelHover = adaptive(light: "#EDF2F9", dark: "#223249")
    static let textPrimary = Color.primary
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let streakEmpty = Color(white: 0.14)

    static let sidebar = adaptive(light: "#EEF2F8", dark: "#0D1420")

    private static func adaptive(light: String, dark: String) -> Color {
        let lightColor = NSColor(Color(hex: light))
        let darkColor = NSColor(Color(hex: dark))
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? darkColor : lightColor
        })
    }

    static let notchCorner: CGFloat = 22
    static let panelCorner: CGFloat = 16
    static let success = adaptive(light: "#16866A", dark: "#5DD6B2")
    static let windowBackground = LinearGradient(
        colors: [adaptive(light: "#F5F7FB", dark: "#101824"), adaptive(light: "#E9EEF6", dark: "#080C13")],
        startPoint: .topLeading, endPoint: .bottomTrailing)
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
    var allowsGlass = true
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
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background {
                FlowBackdrop(
                    shape: RoundedRectangle(cornerRadius: Theme.panelCorner, style: .continuous),
                    color: scheme == .dark ? Theme.panel : Color(nsColor: .controlBackgroundColor))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.panelCorner, style: .continuous)
                    .strokeBorder(LinearGradient(
                        colors: scheme == .dark
                            ? [Color.white.opacity(0.12), Color.white.opacity(0.035)]
                            : [Color.black.opacity(0.07), Color.black.opacity(0.04)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
            }
    }
}

struct FlowAppearanceModifier: ViewModifier {
    @AppStorage(FlowAppearance.themeKey) private var mode = FlowAppearance.Mode.dark.rawValue
    func body(content: Content) -> some View {
        #if DEBUG
        content.preferredColorScheme(Snapshots.isRequested ? nil : (FlowAppearance.Mode(rawValue: mode) ?? .dark).scheme)
        #else
        content.preferredColorScheme((FlowAppearance.Mode(rawValue: mode) ?? .dark).scheme)
        #endif
    }
}

extension View {
    func flowAppearance() -> some View { modifier(FlowAppearanceModifier()) }
    func flowSurface() -> some View { modifier(FlowSurface()) }
}

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
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(configuration.role == .destructive ? Theme.danger : (prominent ? .white : .primary))
            .background {
                FlowBackdrop(shape: RoundedRectangle(cornerRadius: 10, style: .continuous),
                             color: prominent ? Theme.accent : (hovered && enabled ? Theme.panelHover : Theme.panel))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(hovered && enabled ? 0.18 : 0.07))
            }
            .opacity(enabled ? (configuration.isPressed ? 0.72 : 1) : 0.4)
            .scaleEffect(configuration.isPressed && enabled && !reduceMotion ? 0.98 : 1)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
    }
}

struct FlowTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(11)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.12)))
    }
}

struct FlowProgressBar: View {
    var value: Double
    var height: CGFloat = 6
    var color: Color = Theme.accent
    private var fraction: Double { value.isFinite ? min(1, max(0, value)) : 0 }
    var body: some View {
        GeometryReader { geometry in
            Capsule().fill(color.opacity(0.14))
                .overlay(alignment: .leading) {
                    Capsule().fill(color.gradient).frame(width: geometry.size.width * fraction)
                }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue(fraction.formatted(.percent.precision(.fractionLength(0))))
    }
}

struct FlowNavigationRow: View {
    let title: LocalizedStringKey
    let symbol: String
    var color: Color = Theme.accent
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 30, height: 30)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(FlowButtonStyle())
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
                Text(title).font(.system(size: 24, weight: .bold, design: .rounded))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
}

/// The same destinations stay within reach from every standalone overview window.
struct FlowWindowNavigation: View {
    enum Destination: String, CaseIterable, Identifiable {
        case tasks = "Tasks", medications = "Medications", water = "Water", summary = "Weekly summary"
        var id: Self { self }
        var symbol: String {
            switch self {
            case .tasks: return "checklist"
            case .medications: return "pills.fill"
            case .water: return "drop.fill"
            case .summary: return "chart.bar"
            }
        }
        @MainActor func open() {
            switch self {
            case .tasks: AppDelegate.shared?.showTasksWindow()
            case .medications: AppDelegate.shared?.showMedicationsWindow()
            case .water: AppDelegate.shared?.showWaterWindow()
            case .summary: AppDelegate.shared?.showWeeklySummaryWindow()
            }
        }
    }
    let current: Destination
    var body: some View {
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
        .padding(.vertical, 8)
        .background {
            FlowBackdrop(shape: Rectangle(), color: Theme.sidebar)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
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
