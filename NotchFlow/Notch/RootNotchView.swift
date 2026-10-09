import SwiftUI

/// The panel's root. Paints the black pill (square top, rounded bottom) in
/// SwiftUI so it stays opaque, then draws the content and the accent tray on
/// top. Swaps between the collapsed timer pill and the expanded dashboard.
struct RootNotchView: View {
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var focus: FocusTimer
    @EnvironmentObject private var store: Store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Bottom-corner radius: roomy when expanded, tight when collapsed (a large
    /// radius on the short pill would swallow the tray's side segments).
    private var pillCorner: CGFloat { vm.expanded ? Theme.notchCorner : 12 }


private struct MedicationReminderDrop: View {
    let medication: Medication
    let openAction: () -> Void
    let takenAction: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: openAction) {
                HStack(spacing: 9) {
                    Image(systemName: "pills.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 34, height: 34)
                        .background(Theme.medication, in: Circle())
                        .symbolEffect(.pulse, options: .repeat(2))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hora do medicamento")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.medication)
                        Text(medication.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                medication.dosage.isEmpty
                    ? "Hora de tomar \(medication.name)"
                    : "Hora de tomar \(medication.name), \(medication.dosage)"
            )
            .accessibilityHint("Abre a lista de medicamentos")

            Spacer(minLength: 2)

            Button(action: takenAction) {
                Label("Tomei", systemImage: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Theme.medication, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Registra esta dose como tomada")
        }
        .padding(.horizontal, 8)
        .frame(width: 340, height: 44)
        .background(Theme.panel, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Theme.medication.opacity(0.6), lineWidth: 1)
        }
        .shadow(color: Theme.medication.opacity(0.2), radius: 8, y: 2)
    }
}

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
                    FlowBackdrop(shape: NotchShape(bottomRadius: pillCorner), color: .black,
                                 allowsGlass: vm.expanded)
                    content
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                }
                .clipShape(NotchShape(bottomRadius: pillCorner))
                trayOverlay
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        // The panel overlaps the menu bar and the notch; a safe-area inset
        // there must not shift or shrink the drawing.
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onHover { hovering in vm.hover(hovering) }
    }

    @ViewBuilder private var content: some View {
        if vm.expanded {
            NotchDashboardView()
                .transition(.opacity)
        } else {
            ZStack(alignment: .top) {
                CollapsedTimerView()

                if let medication = vm.medicationAlert {
                    MedicationReminderDrop(
                        medication: medication,
                        openAction: {
                            vm.dismissMedicationReminder()
                            vm.openMedicationsWindow()
                        },
                        takenAction: {
                            store.recordMedicationTaken(medication)
                            vm.dismissMedicationReminder()
                        }
                    )
                    .padding(.top, vm.notchHeight + 6)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .top).combined(with: .opacity)
                    )
                }
            }
            .transition(.opacity)
        }
    }

    /// The accent tray — identical treatment whether collapsed or expanded:
    /// a faint full track (visible on BOTH sides + bottom) plus a bright fill
    /// that grows with progress. Same line width in both states. Hidden only
    /// for the bare idle notch.
    private var trayLineWidth: CGFloat { 2.5 }

    @ViewBuilder private var trayOverlay: some View {
        // Collapsed pill only draws the tray when the timeline is enabled; the
        // expanded dashboard always keeps its accent border.
        if vm.expanded || (focus.isActive && store.settings.showTimeline) {
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
            if store.settings.rainbowTimeline {
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
                         track: Theme.accent.opacity(0.5),
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
                .animation(.linear(duration: 1.0), value: focus.progress)
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
