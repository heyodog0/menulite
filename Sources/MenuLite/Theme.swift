// © 2026 Ryan Truong. All rights reserved. Not licensed for copying, porting or
// reimplementation, by hand or with AI tools. See LICENSE.

import SwiftUI
import AppKit

// MARK: layout — shared so the measured panel height and the views agree.

let panelWidth: CGFloat = 264
let panelCornerRadius: CGFloat = 26
let panelShape = RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
/// Padding inside the glass, and the gap between the rings row and the body.
let panelPadding = EdgeInsets(top: 8, leading: 14, bottom: 14, trailing: 14)
let panelSectionGap: CGFloat = 12
/// Every detail screen's body below the chart is this tall, so switching tabs
/// doesn't resize the panel. The process list scrolls within it.
let detailBodyHeight: CGFloat = 187
let processListHeight: CGFloat = 144
/// Clear margin around the glass (sides + bottom) inside the window, so the
/// SwiftUI shadow can fade out instead of being cut off at the window edge.
let shadowMargin: CGFloat = 44

/// The selected-pill fill, shared by the tab pills and active buttons.
func pillFill(_ tint: Color = .blue) -> LinearGradient {
    LinearGradient(colors: [tint, tint.opacity(0.82)], startPoint: .top, endPoint: .bottom)
}

/// Shared motion, so every screen change moves with the same feel.
enum Motion {
    /// Screen changes: home ↔ detail, tab switches, panel height.
    static let duration: Double = 0.34
    static let screen = Animation.spring(duration: duration, bounce: 0.08)
    /// Outgoing screen fades fast so it never overlaps the incoming one.
    static let fadeOut = Animation.easeOut(duration: 0.1)
    /// Panel open/close. The glass fades via the window's alpha (the backdrop
    /// blur fades cleanly that way); only the content inside it moves.
    static let openDuration: Double = 0.24
    static let closeDuration: Double = 0.14
    static let open = Animation.spring(duration: openDuration, bounce: 0.1)
    static let close = Animation.easeIn(duration: closeDuration)
}

extension View {
    func innerCard(_ radius: CGFloat = 14, opacity: Double = 0.05) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.white.opacity(opacity)))
    }
}

/// Real AppKit Liquid Glass (NSGlassEffectView) exposed to SwiftUI so SwiftUI can
/// size and animate it. The window itself is transparent; this is what you see.
/// NSGlassEffectView resizes natively, so when SwiftUI animates its frame the
/// glass follows smoothly — no recursion like SwiftUI's own `.glassEffect`.
struct GlassBackground: NSViewRepresentable {
    var cornerRadius: CGFloat = panelCornerRadius
    func makeNSView(context: Context) -> NSGlassEffectView {
        let v = NSGlassEffectView()
        v.cornerRadius = cornerRadius
        return v
    }
    func updateNSView(_ v: NSGlassEffectView, context: Context) {
        v.cornerRadius = cornerRadius
    }
}

/// Fills the clear window: the glass panel (MenuContent) pinned to the top, over
/// a transparent area that dismisses the panel when clicked.
struct RootView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        ZStack(alignment: .top) {
            // Transparent dismiss area (covers any margin below the panel while it
            // animates shorter). Clicks elsewhere already dismiss via resignKey.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { state.closePanel?() }

            MenuContent()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .tint(.blue)
    }
}

/// Full-width action button; tints blue when active. Two lines: the action,
/// and a quieter line of detail (how long sleep is held off, that cleaning is
/// catproof) — so every button reads the same way. An optional trailing control
/// (e.g. the keep-awake options menu) sits inside the same capsule with its own
/// hit area. (Plain controls on the glass panel — not themselves glass.)
struct ActionButton<Trailing: View>: View {
    let title: String
    let systemImage: String
    var subtitle: String
    var subtitleIcon: String? = nil
    var active: Bool = false
    let action: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.system(size: 13, weight: .medium))
                        HStack(spacing: 3) {
                            if let subtitleIcon { Image(systemName: subtitleIcon) }
                            Text(subtitle).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.system(size: 10))
                        .opacity(0.7)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 7).padding(.leading, 12).padding(.trailing, 8)
                .contentShape(shape)
            }
            .buttonStyle(.plain)
            trailing()
        }
        .foregroundStyle(active ? .white : .primary)
        .background {
            if active {
                shape.fill(LinearGradient(colors: [.blue, .blue.opacity(0.82)],
                                          startPoint: .top, endPoint: .bottom))
            } else {
                shape.fill(.white.opacity(0.08))
            }
        }
        .overlay(shape.strokeBorder(.white.opacity(active ? 0.30 : 0.12), lineWidth: 0.8))
        .animation(.easeOut(duration: 0.2), value: active)
    }
}

extension ActionButton where Trailing == EmptyView {
    init(title: String, systemImage: String, subtitle: String, subtitleIcon: String? = nil,
         active: Bool = false, action: @escaping () -> Void) {
        self.init(title: title, systemImage: systemImage, subtitle: subtitle,
                  subtitleIcon: subtitleIcon, active: active, action: action, trailing: { EmptyView() })
    }
}

extension View {
    /// A scroll view whose edges fade out only where there's more to scroll,
    /// with no scroll bar drawn over the rows.
    func scrollEdges() -> some View { modifier(ScrollEdges()) }
}

private struct ScrollEdges: ViewModifier {
    @State private var moreAbove = false
    @State private var moreBelow = false
    private let fade: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: [Bool].self, of: { g in
                let top = g.contentOffset.y + g.contentInsets.top
                return [top > 1,
                        top + g.containerSize.height < g.contentSize.height - 1]
            }, action: { _, edges in
                moreAbove = edges[0]; moreBelow = edges[1]
            })
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: moreAbove ? fade : 0)
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: moreBelow ? fade : 0)
                }
                .animation(.easeOut(duration: 0.2), value: moreAbove)
                .animation(.easeOut(duration: 0.2), value: moreBelow)
            }
    }
}
