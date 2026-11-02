// © 2026 Ryan Truong. All rights reserved. Not licensed for copying, porting or
// reimplementation, by hand or with AI tools. See LICENSE.

import SwiftUI

struct MenuContent: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: panelSectionGap) {
            // Fixed header: the three tappable dials, always visible. Measured as
            // chrome so it sits outside the height-animated body and can never be
            // clipped or briefly overlaid during a home↔detail transition.
            HStack(spacing: 4) {
                ForEach(Resource.ringCases) { r in
                    Button {
                        withAnimation(Motion.screen) {
                            state.selected = (state.selected == r) ? nil : r
                        }
                    } label: {
                        RingGauge(resource: r,
                                  percent: state.percent(for: r),
                                  tint: state.tint(for: r),
                                  selected: state.selected == r,
                                  animated: state.panelVisible)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) {
                state.chromeHeight = $0
            }

            bodyArea
        }
        .padding(panelPadding)
        // Open/close: the content settles down into place inside the glass (the
        // glass itself fades with the window, never scaled — see StatusController).
        .opacity(state.panelVisible ? 1 : 0)
        .scaleEffect(state.panelVisible ? 1 : 0.97, anchor: .top)
        .offset(y: state.panelVisible ? 0 : -6)
        .frame(width: panelWidth, alignment: .top)
        // The glass — native NSGlassEffectView behind the content, hugging it and
        // animating its height with the body (all in SwiftUI; the window is clear).
        .background(GlassBackground())
        .overlay(panelShape.strokeBorder(.white.opacity(0.10), lineWidth: 0.8))
        .clipShape(panelShape)
        .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    /// The body below the rings: the active screen, cross-fading + scaling from the
    /// top, with its frame height animated to the current screen's natural height
    /// (measured by the hidden probe). Clipped so the outgoing screen doesn't spill
    /// while shorter — and the clip excludes the header (rings) above.
    private var bodyArea: some View {
        ZStack(alignment: .top) { activeScreen }
            .animation(Motion.screen, value: state.selected)
            .frame(height: state.screenHeight > 0 ? state.screenHeight : nil, alignment: .top)
            .clipped()
            .animation(Motion.screen, value: state.screenHeight)
            // Hidden, instantly-swapping copy reports the current screen's natural
            // height (no cross-fade union), without affecting layout.
            .background(alignment: .top) {
                ZStack(alignment: .top) { activeScreen }
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) {
                        state.reportScreenHeight($0)
                    }
            }
    }

    /// The screen for the current selection. Used twice — once visible (cross-faded
    /// + scaled) and once hidden to measure its natural height.
    @ViewBuilder
    private var activeScreen: some View {
        let move = AnyTransition.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)),
            removal: .opacity.animation(Motion.fadeOut))
        if let r = state.selected {
            ResourceDetail(resource: r).transition(move)
        } else {
            Controls().transition(move)
        }
    }
}

/// Default panel: prevent-sleep + clean-keyboard buttons, brightness slider, quit.
private struct Controls: View {
    @EnvironmentObject var state: AppState

    private var brightness: Binding<Double> {
        Binding(get: { 1 - state.dimLevel / 0.9 },
                set: { state.dimLevel = (1 - $0) * 0.9 })
    }

    var body: some View {
        VStack(spacing: 12) {
            SensorsStrip()

            if let b = state.battery { BatteryCard(reading: b) }

            ActionButton(title: state.preventSleep ? "Sleep prevented" : "Prevent sleep",
                         systemImage: "moon.zzz.fill", subtitle: state.awakeSubtitle,
                         active: state.preventSleep, action: { state.toggleSleep() }) {
                AwakeMenu()
            }
            .help("⌃⌥S toggles this from anywhere")
            ActionButton(title: state.cleaning ? "Stop cleaning" : "Clean keyboard",
                         systemImage: "keyboard", subtitle: "Also catproof", subtitleIcon: "cat.fill",
                         active: state.cleaning) {
                state.toggleCleaning()
            }
            .help("⌃⌥K starts this from anywhere")
            if let note = state.note {
                Text(note).font(.system(size: 11)).foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }

            Divider().opacity(0.4).padding(.vertical, 2)

            VStack(spacing: 8) {
                Text("External Monitor Brightness")
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity)
                HStack(spacing: 9) {
                    Image(systemName: "moon.fill").font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Slider(value: brightness, in: 0...1)
                    Image(systemName: "sun.max.fill").font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Keep-awake options, in the Prevent sleep button's trailing slot: how long,
/// "until this process quits", and whether the screen stays on too.
private struct AwakeMenu: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Menu {
            Section("Keep awake") {
                Button("Until I turn it off") { state.awake = .indefinitely }
                ForEach([30, 60, 120, 240], id: \.self) { m in
                    Button(m < 60 ? "For \(m) minutes" : "For \(m / 60) hour\(m > 60 ? "s" : "")") {
                        state.keepAwake(minutes: m)
                    }
                }
                Menu("Until a process quits") {
                    if state.awakeCandidates.isEmpty {
                        Text("No busy processes")
                    }
                    ForEach(state.awakeCandidates) { p in
                        Button("\(p.name)  ·  \(p.display) CPU") { state.keepAwake(whileRunning: p) }
                    }
                }
            }
            Divider()
            Toggle("Keep screen on", isOn: $state.keepScreenOn)
            Divider()
            Text("Toggle from anywhere: ⌃⌥S")
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .frame(width: 30)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .fixedSize(horizontal: true, vertical: false)
        .overlay(alignment: .leading) {
            Rectangle().fill(.white.opacity(0.15)).frame(width: 0.8).padding(.vertical, 9)
        }
        .help("Keep-awake options")
    }
}

/// The internal battery (MacBooks only): charge, time left, power draw, health.
private struct BatteryCard: View {
    let reading: BatteryMonitor.Reading

    private var tint: Color {
        if reading.charging || reading.pluggedIn { return .green }
        return reading.percent <= 10 ? .red : reading.percent <= 20 ? .orange : .primary
    }

    private var status: String {
        let left = reading.minutesLeft.map { m in m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m" }
        if reading.charging { return left.map { "\($0) to full" } ?? "Charging" }
        if reading.pluggedIn { return reading.percent >= 99 ? "Charged" : "Not charging" }
        return left.map { "\($0) left" } ?? "Estimating…"
    }

    var body: some View {
        VStack(spacing: 12) {
            // The bar is the battery gauge: green on power, orange/red when low.
            HStack(spacing: 8) {
                Text("\(reading.percent)%").font(.system(size: 14, weight: .semibold).monospacedDigit())
                if reading.charging {
                    Image(systemName: "bolt.fill").font(.system(size: 10)).foregroundStyle(.green)
                }
                chargeBar
                Text(status).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize()
            }
            HStack(spacing: 0) {
                if let w = reading.watts {
                    stat(reading.charging ? "Charging" : "Draw", String(format: "%.1f W", w))
                }
                if let h = reading.healthPercent { stat("Health", "\(h)%") }
                if let c = reading.cycles { stat("Cycles", "\(c)") }
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .innerCard(12, opacity: 0.05)
    }

    private var chargeBar: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.10))
                Capsule().fill(tint == .primary ? Color.primary.opacity(0.55) : tint)
                    .frame(width: max(6, g.size.width * CGFloat(reading.percent) / 100))
            }
        }
        .frame(height: 6).frame(minWidth: 24)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.system(size: 12, weight: .medium).monospacedDigit())
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
