import SwiftUI
import Charts

/// Bar history graph styled after the reference: blue gradient bars, dashed
/// gridlines, and floating pill value labels down the left edge.
struct HistoryChart: View {
    let resource: Resource
    let values: [Double]      // raw samples (%, or bytes for memory)

    var body: some View {
        Chart(Array(plotted.enumerated()), id: \.offset) { idx, v in
            BarMark(x: .value("t", idx), y: .value("v", v), width: .fixed(2.4))
                .foregroundStyle(
                    .linearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.55)],
                                    startPoint: .top, endPoint: .bottom))
        }
        .chartXAxis(.hidden)
        .chartYScale(domain: 0...yMax)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(.white.opacity(0.12))
                AxisValueLabel {
                    if let d = value.as(Double.self) {
                        Text(label(d))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(.black.opacity(0.45)))
                    }
                }
            }
        }
        .frame(height: 110)
        .animation(.easeOut(duration: 0.3), value: values.count)
    }

    private var plotted: [Double] {
        resource == .memory ? values.map { $0 / 1_073_741_824 } : values
    }

    private var yMax: Double {
        switch resource {
        case .memory:
            let maxGB = (values.max() ?? 0) / 1_073_741_824
            return max(1, (maxGB * 1.15).rounded(.up))
        default:
            return 100
        }
    }

    private func label(_ d: Double) -> String {
        resource == .memory ? String(format: "%.0f GB", d) : "\(Int(d))%"
    }
}
