//
//  DSTypography.swift
//  SuggestMeSome
//
//  Rounded monospaced-digit metric styles + a semantic typography ladder
//  introduced in Feature 22 Prompt 3. The metric variants stay for any
//  numeric readout (timers, reps, weight) so digit widths stay stable
//  while values animate. The role modifiers (`dsHero`, `dsDisplay`,
//  `dsTitle`, `dsHeadline`, `dsBody`, `dsCaption`) are how non-metric
//  text picks up the new aesthetic without scattering raw `.font(.headline)`
//  / `.font(.caption)` calls across the codebase.
//

import SwiftUI

// MARK: - Metric font (numbers)

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
        modifier(DSMetricFont(size: 20, weight: .semibold))
    }
}

// MARK: - Typography ladder (semantic roles)

/// Hero: 44pt rounded bold. Use for the single most important number on a
/// surface (rest timer, today's hero weight, dashboard hero stat). Pair
/// with `.dsHeroGradientFill()` to apply the brand gradient.
extension View {
    func dsHero() -> some View {
        font(.system(size: 44, weight: .bold, design: .rounded))
            .minimumScaleFactor(0.6)
    }

    func dsDisplay() -> some View {
        font(.system(size: 34, weight: .semibold, design: .rounded))
            .minimumScaleFactor(0.7)
    }

    func dsTitle() -> some View {
        font(.system(size: 22, weight: .semibold, design: .rounded))
            .minimumScaleFactor(0.8)
    }

    func dsHeadline() -> some View {
        font(.system(size: 17, weight: .semibold, design: .rounded))
    }

    func dsBody() -> some View {
        font(.system(size: 15, weight: .regular, design: .rounded))
    }

    func dsCaption() -> some View {
        font(.system(size: 13, weight: .regular, design: .rounded))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Hero gradient fill

/// Applies the brand `heroAccent` gradient to text/SF symbol foregrounds.
/// When the v2 flag is OFF, falls back to a flat primary tint so legacy
/// surfaces don't suddenly bloom violet.
extension View {
    func dsHeroGradientFill() -> some View {
        Group {
            if FeatureFlag.uiRefreshV2.isEnabled {
                self.foregroundStyle(DSGradient.heroAccent)
            } else {
                self.foregroundStyle(DSColor.primaryAction)
            }
        }
    }
}
