// © 2026 Ryan Truong. All rights reserved. Not licensed for copying, porting or
// reimplementation, by hand or with AI tools. See LICENSE.

import SwiftUI
import Charts

/// The last ~3 minutes as a smooth filled area: a soft gradient under a thin
/// line, faint dashed gridlines, and small axis labels on the trailing edge.
struct HistoryChart: View {
    let resource: Resource
    let values: [Double]      // raw samples (%, or bytes for memory)
    var tint: Color = .accentColor
    var height: CGFloat = 84

    var body: some View {
        let offset = max(0, slots - plotted.count)
        Chart(Array(plotted.enumerated()), id: \.offset) { i, v in
            let idx = i + offset
            AreaMark(x: .value("t", idx), yStart: .value("0", 0), yEnd: .value("v", v))
                .interpolationMethod(.monotone)
                .foregroundStyle(.linearGradient(colors: [tint.opacity(0.38), tint.opacity(0.02)],
                                                 startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("t", idx), y: .value("v", v))
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                .foregroundStyle(tint)
        }
        .chartXAxis(.hidden)
        .chartXScale(domain: 0...max(1, Double(slots - 1)))
        .chartYScale(domain: 0...yMax)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [2, 3]))
                    .foregroundStyle(.white.opacity(0.10))
                AxisValueLabel {
                    if let d = value.as(Double.self) {
                        Text(label(d)).font(.system(size: 8, weight: .medium).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.3), value: values.count)
    }

    /// The chart's width is the full history window, so a fresh panel fills in
    /// from the right instead of stretching a few samples across.
    private let slots = 90   // AppState.maxHistory

    private var plotted: [Double] {
        let raw: [Double]
        switch resource {
        case .memory:  raw = values.map { $0 / 1_073_741_824 }
        case .network: raw = values.map { $0 / netDivisor }
        default:       raw = values
        }
        return raw
    }

    // Network auto-picks MB/s vs KB/s based on the peak in view.
    private var netUseMB: Bool { (values.max() ?? 0) >= 1_000_000 }
    private var netDivisor: Double { netUseMB ? 1_000_000 : 1_000 }

    private var yMax: Double {
        switch resource {
        case .memory:
            let maxGB = (values.max() ?? 0) / 1_073_741_824
            return max(1, (maxGB * 1.15).rounded(.up))
        case .network:
            return max(netUseMB ? 1 : 10, ((plotted.max() ?? 0) * 1.2).rounded(.up))
        default:
            return 100
        }
    }

    private func label(_ d: Double) -> String {
        switch resource {
        case .memory:  return String(format: "%.0f GB", d)
        case .network: return netUseMB ? String(format: "%.0f MB/s", d) : String(format: "%.0f KB/s", d)
        default:       return "\(Int(d))%"
        }
    }
}
