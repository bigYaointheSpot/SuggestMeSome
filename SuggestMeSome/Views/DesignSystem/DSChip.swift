//
//  DSChip.swift
//  SuggestMeSome
//
//  Metric chip: a compact icon + value + optional label trio used on
//  Dashboard and Daily Coach cards to surface a single readout (e.g.,
//  "🔥 78 RPE 8"). Consolidates the inline pill constructions in
//  RecoveryPressureCard, DashboardStatCard, and a few Daily Coach cards.
//

import SwiftUI

struct DSChip: View {
    let systemImage: String?
    let value: String
    let label: String?
    var tint: Color

    init(
        systemImage: String? = nil,
        value: String,
        label: String? = nil,
        tint: Color = DSColor.primaryAction
    ) {
        self.systemImage = systemImage
        self.value = value
        self.label = label
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: DSSpacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
            }
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let label {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, DSSpacing.s)
        .padding(.vertical, 4)
        .background(tint.opacity(0.10))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label.map { "\($0): \(value)" } ?? value)
    }
}
