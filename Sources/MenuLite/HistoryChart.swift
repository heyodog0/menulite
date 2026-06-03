import SwiftUI
import Charts

/// A compact bar history graph for one resource, styled after a stats-app chart.
struct HistoryChart: View {
    let resource: Resource
    let values: [Double]      // raw samples (%, or bytes for memory)
    let color: Color

    var body: some View {
        Chart(Array(plotted.enumerated()), id: \.offset) { idx, v in
            BarMark(
                x: .value("t", idx),
                y: .value("v", v),
                width: .fixed(2)
            )
            .foregroundStyle(color.gradient)
        }
        .chartXAxis(.hidden)
        .chartYScale(domain: 0...yMax)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                AxisValueLabel {
                    if let d = value.as(Double.self) { Text(label(d)) }
                }
                .font(.system(size: 9))
            }
        }
        .frame(height: 90)
    }

    // Memory is plotted in GB; CPU/disk in percent.
    private var plotted: [Double] {
        resource == .memory ? values.map { $0 / 1_073_741_824 } : values
    }

    private var yMax: Double {
        switch resource {
        case .memory:
            let totalGB = (values.max() ?? 0) / 1_073_741_824
            return max(1, (totalGB * 1.15).rounded(.up))
        default:
            return 100
        }
    }

    private func label(_ d: Double) -> String {
        resource == .memory ? String(format: "%.0f GB", d) : "\(Int(d))%"
    }
}
