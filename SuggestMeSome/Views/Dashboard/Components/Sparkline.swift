//
//  Sparkline.swift
//  SuggestMeSome
//
//  Compact inline trend visual for stat cards.
//

import SwiftUI
import Charts

struct Sparkline: View {
    let values: [Double]
    var tint: Color = DSColor.primaryAction
    var height: CGFloat = 22

    var body: some View {
        if values.count < 2 {
            Color.clear.frame(height: height)
        } else {
            Chart {
                ForEach(Array(values.enumerated()), id: \.offset) { idx, value in
                    LineMark(
                        x: .value("Index", idx),
                        y: .value("Value", value)
                    )
                    .foregroundStyle(tint)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))

                    AreaMark(
                        x: .value("Index", idx),
                        y: .value("Value", value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [tint.opacity(0.35), tint.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartPlotStyle { plot in
                plot.background(Color.clear)
            }
            .frame(height: height)
        }
    }
}
