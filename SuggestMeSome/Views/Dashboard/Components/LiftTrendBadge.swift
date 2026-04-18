//
//  LiftTrendBadge.swift
//  SuggestMeSome
//
//  Horizontally scrollable trend chip for significant lift movements.
//

import SwiftUI

struct LiftTrendBadge: View {
    let trend: LiftPerformanceTrend

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: trend.trendStatus.dsTrendIcon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(trend.trendStatus.dsTrendColor)

            Text(trend.liftDisplayName)
                .font(.caption.weight(.semibold))

            if let changePercent = trend.fourWeekChangePercent {
                Text(String(format: "%+.1f%%", changePercent))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(changePercent >= 0 ? Color.green : Color.red)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(trend.trendStatus.dsTrendColor.opacity(0.10))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(trend.trendStatus.dsTrendColor.opacity(0.25), lineWidth: 1))
    }
}
