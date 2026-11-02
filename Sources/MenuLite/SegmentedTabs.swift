// © 2026 Ryan Truong. All rights reserved. Not licensed for copying, porting or
// reimplementation, by hand or with AI tools. See LICENSE.

import SwiftUI

/// Icon pills with a sliding blue selection (matchedGeometry). The resource's
/// name is in the header right below, so the pills stay uncluttered.
struct SegmentedTabs: View {
    @Binding var selection: Resource
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Resource.allCases) { r in
                let on = r == selection
                Image(systemName: r.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(on ? .white : .secondary)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background {
                        if on {
                            Capsule(style: .continuous)
                                .fill(pillFill())
                                .matchedGeometryEffect(id: "pill", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture { withAnimation(Motion.screen) { selection = r } }
                    .help(r.tabTitle)
            }
        }
        .padding(3)
        .background(Capsule(style: .continuous).fill(.white.opacity(0.07)))
    }
}
