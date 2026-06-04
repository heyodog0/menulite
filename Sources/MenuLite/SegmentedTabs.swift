import SwiftUI

/// Pill-style segmented control with a sliding blue selection (matchedGeometry).
struct SegmentedTabs: View {
    @Binding var selection: Resource
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Resource.allCases) { r in
                let on = r == selection
                Text(r.tabTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.8)
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
}
