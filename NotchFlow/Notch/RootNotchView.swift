import SwiftUI

/// A black camera footprint connects to the rounded graphite dashboard below.
/// The compact state keeps the camera gap clear and shows an inline timeline.
struct RootNotchView: View {
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var focus: FocusTimer
    @EnvironmentObject private var store: Store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Bottom-corner radius: roomy when expanded, tight when collapsed (a large
    /// radius on the short pill would swallow the tray's side segments).
    private var pillCorner: CGFloat { vm.expanded ? Theme.notchCorner : 12 }


    var body: some View {
        // The pill and the tray take the window's size, never the content's:
        // the window owns the frame animation, and content that was taller
        // than the window used to stretch the pill past the window's bottom
        // edge, cutting off the bottom line. Content is pinned to the same
        // size and clipped, so it can never push them out again.
        GeometryReader { geo in
            ZStack(alignment: .top) {
                // Clip ONLY the black pill + content to the notch shape. The accent
                // tray is drawn on top, OUTSIDE the clip: it's fully inset within the
                // pill, so it never needs clipping — and running it through the clip
                // is exactly what shaved its rounded bottom corners flat.
                ZStack(alignment: .top) {
                    if vm.expanded {
                        Color.black.frame(width: vm.notchWidth, height: vm.notchHeight)
                        FlowBackdrop(shape: RoundedRectangle(cornerRadius: 16, style: .continuous),
                                     color: NotchPalette.background, allowsGlass: true)
                            .padding(.top, vm.notchHeight)
                    } else {
                        NotchShape(bottomRadius: pillCorner).fill(.black)
                    }
                    content
                        .frame(width: vm.expanded ? vm.expandedWidth : vm.collapsedWidth, height: vm.notchContentHeight, alignment: .top)
                }
                .frame(width: vm.expanded ? vm.expandedWidth : vm.collapsedWidth, height: vm.notchContentHeight)
                .clipShape(NotchShape(bottomRadius: pillCorner))
                .overlay {
                    if vm.expanded {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(NotchPalette.border, lineWidth: 1)
                            .padding(.top, vm.notchHeight)
                            .allowsHitTesting(false)
                    }
                }
                trayOverlay
                    .padding(.top, vm.expanded ? vm.notchHeight : 0)
                    .frame(width: vm.expanded ? vm.expandedWidth : vm.collapsedWidth, height: vm.notchContentHeight)
                if let reminder = vm.reminderAlert {
                    RoutineReminderPill(reminder: reminder, serving: store.hydrationSettings.servingMilliliters,
                                        confirm: vm.confirmReminder, dismiss: vm.dismissReminder)
                        .padding(.top, vm.notchContentHeight + 10)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        // The panel overlaps the menu bar and the notch; a safe-area inset
        // there must not shift or shrink the drawing.
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onHover { hovering in vm.hover(hovering) }
    }

    @ViewBuilder private var content: some View {
        if vm.expanded {
            NotchDashboardView()
                .transition(.opacity)
        } else {
            CollapsedTimerView()
                .transition(.opacity)
        }
    }

    /// Color signals an active session; idle surfaces keep a quiet neutral edge.
    private var trayLineWidth: CGFloat { vm.expanded ? 1.5 : 2 }

    @ViewBuilder private var trayOverlay: some View {
        if focus.isActive && store.settings.showTimeline
            && (store.settings.minimalMode || store.settings.rainbowTimeline) {
            // Collapsed: hug tightly (small insets, low corner) so the short
            // side segments still read. Expanded: roomier inset.
            //
            // The tray is no longer clipped, so its corner just needs to sit
            // concentric inside the pill's rounded bottom: radius = pillCorner
            // minus the inset keeps a constant gap between the two curves.
            let inset: CGFloat = vm.expanded ? 7 : 6
            let corner = max(4, pillCorner - inset)
            let shape = NotchTrayShape(inset: inset,
                                       topInset: vm.expanded ? 7 : 5,
                                       corner: corner)
            let style = StrokeStyle(lineWidth: trayLineWidth, lineCap: .round)
            if store.settings.rainbowTimeline && !reduceMotion {
                // Animated RGB: the whole hue spectrum is laid out ALONG the
                // line at once (a moving multicolor gradient), not one shifting
                // solid color. `TimelineView(.animation)` re-derives the phase
                // every frame and only ticks while the view is on screen.
                TimelineView(.animation) { timeline in
                    let phase = Self.rainbowPhase(at: timeline.date)
                    trayBody(shape: shape, style: style,
                             track: Self.rainbowGradient(phase: phase, opacity: 0.25),
                             fill: Self.rainbowGradient(phase: phase, opacity: 1),
                             glow: Color(hue: phase, saturation: 0.9, brightness: 1))
                }
            } else {
                trayBody(shape: shape, style: style,
                         track: Color.white.opacity(0.10),
                         fill: Theme.accent, glow: nil)
            }
        }
    }

    /// One tray: faint full track + bright progress fill, optionally glowing.
    /// Generic over the stroke style so it works for both a solid `Color` and
    /// the animated rainbow `LinearGradient`.
    private func trayBody<S: ShapeStyle>(shape: NotchTrayShape, style: StrokeStyle,
                                         track: S, fill: S, glow: Color?) -> some View {
        ZStack {
            // Full track, both sides + bottom, always visible.
            shape.stroke(track, style: style)
            // Bright progress fill (0 when no timer is running). Animate over
            // a full second so it flows continuously instead of ticking.
            shape.trim(from: 0, to: focus.isActive ? focus.progress : 0)
                .stroke(fill, style: style)
                .animation(reduceMotion ? nil : .linear(duration: 1.0), value: focus.progress)
        }
        .shadow(color: glow ?? .clear, radius: glow == nil ? 0 : 6)
    }

    /// Phase in 0..<1 that advances a full turn every `period` seconds; drives
    /// the gradient's motion. Derived purely from the clock so it stays smooth.
    private static func rainbowPhase(at date: Date, period: Double = 4) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
    }

    /// The full hue spectrum spread across the line, rotated by `phase` so the
    /// colors flow. Opacity is baked into the stops so the faint track and the
    /// bright fill can share one builder.
    private static func rainbowGradient(phase: Double, opacity: Double) -> LinearGradient {
        let stops = stride(from: 0.0, through: 1.0, by: 0.1).map { p -> Gradient.Stop in
            let hue = (p + phase).truncatingRemainder(dividingBy: 1)
            return .init(color: Color(hue: hue, saturation: 0.9, brightness: 1).opacity(opacity),
                         location: p)
        }
        return LinearGradient(gradient: Gradient(stops: stops),
                              startPoint: .leading, endPoint: .trailing)
    }
}


private struct RoutineReminderPill: View {
    let reminder: NotchReminder
    let serving: Int
    let confirm: () -> Void
    let dismiss: () -> Void

    private var color: Color {
        Theme.accent
    }
    private var symbol: String { reminder == .water ? "drop.fill" : "pills.fill" }
    private var title: String {
        reminder == .water ? String(localized: "Time to drink water") : String(localized: "Medication reminder")
    }
    private var detail: String {
        switch reminder {
        case .water: return String(localized: "\(serving) ml · Stay hydrated")
        case .medication(let medication):
            return medication.dosage.isEmpty ? medication.name : "\(medication.name) · \(medication.dosage)"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(color)
                Text(detail).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary).lineLimit(1).help(detail)
            }
            Spacer(minLength: 0)
            Button(action: confirm) {
                Text(reminder == .water ? String(localized: "Drank water") : String(localized: "Taken"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.black).padding(.horizontal, 10)
                    .frame(height: 28).background(color, in: Capsule())
            }
            .buttonStyle(.plain)
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary).frame(width: 24, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss reminder")
        }
        .padding(.horizontal, 10)
        .frame(width: 380, height: 48)
        .background(.black, in: Capsule())
        .overlay { Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1) }
    }
}
