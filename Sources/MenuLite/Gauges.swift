import SwiftUI

/// A circular progress ring with a centered icon + label — the CPU/MEM/DISK dials.
struct RingGauge: View {
    let resource: Resource
    let fraction: Double      // 0…1
    let percent: Double       // 0…100 (drives color)
    var selected: Bool = false

    private let size: CGFloat = 66
    private let line: CGFloat = 6

    var body: some View {
        ZStack {
            // inset by half the line width so the stroke stays inside the frame
            Circle().inset(by: line / 2)
                .stroke(Color.primary.opacity(0.14), lineWidth: line)
            Circle().inset(by: line / 2)
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(loadColor(percent),
                        style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: fraction)
            VStack(spacing: 1) {
                Image(systemName: resource.icon)
                    .font(.system(size: 16, weight: .regular))
                Text(resource.rawValue)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .padding(6)
        .background(
            Circle().fill(Color.white.opacity(selected ? 0.10 : 0))
        )
        .contentShape(Circle())
    }
}
