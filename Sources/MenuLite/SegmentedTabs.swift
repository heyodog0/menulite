import SwiftUI

/// Pill-style segmented control with a sliding blue selection (matchedGeometry).
struct SegmentedTabs: View {
    @Binding var selection: Resource
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Resource.allCases) { r in
                let on = r == selection
                Text(label(r))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(on ? .white : .secondary)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background {
                        if on {
                            Capsule(style: .continuous)
                                .fill(Color.accentColor)
                                .matchedGeometryEffect(id: "pill", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture {
                        withAnimation(.snappy(duration: 0.28)) { selection = r }
                    }
            }
        }
        .padding(3)
        .background(Capsule(style: .continuous).fill(.white.opacity(0.07)))
    }

    private func label(_ r: Resource) -> String {
        switch r {
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .disk: return "Disk"
        }
    }
}
