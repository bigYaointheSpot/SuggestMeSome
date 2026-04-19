//
//  DSTypography.swift
//  SuggestMeSome
//
//  Rounded monospaced-digit metric styles that match the Apple Fitness /
//  Health aesthetic. Use for any numeric readout — timers, reps, weight,
//  percentages — so digit widths stay stable while values animate.
//

import SwiftUI

private struct DSMetricFont: ViewModifier {
    let size: CGFloat
    let weight: Font.Weight

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: weight, design: .rounded))
            .monospacedDigit()
            .minimumScaleFactor(0.6)
            .contentTransition(.numericText())
    }
}

extension View {
    func dsMetricLarge() -> some View {
        modifier(DSMetricFont(size: 48, weight: .semibold))
    }

    func dsMetricMedium() -> some View {
        modifier(DSMetricFont(size: 28, weight: .semibold))
    }

    func dsMetricSmall() -> some View {
        modifier(DSMetricFont(size: 17, weight: .semibold))
    }
}
