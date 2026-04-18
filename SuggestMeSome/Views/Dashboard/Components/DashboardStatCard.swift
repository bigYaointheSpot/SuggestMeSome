//
//  DashboardStatCard.swift
//  SuggestMeSome
//
//  Hero statistic tile with animated count + inline sparkline.
//

import SwiftUI

struct DashboardStatCard: View {
    let icon: String
    let iconColor: Color
    let value: String
    let label: String
    var sparkline: [Double] = []

    @State private var displayedInt: Int = 0

    private var targetInt: Int? { Int(value) }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: icon)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(iconColor)
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }

            Group {
                if targetInt != nil {
                    Text("\(displayedInt)")
                } else {
                    Text(value)
                }
            }
            .font(.title2.weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .contentTransition(.numericText())

            Sparkline(values: sparkline, tint: iconColor, height: 18)
                .padding(.top, 2)
        }
        .padding(.vertical, DSSpacing.m)
        .padding(.horizontal, DSSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous))
        .onAppear {
            if let target = targetInt { animateCount(to: target) }
        }
        .onChange(of: value) { _, _ in
            if let target = targetInt { animateCount(to: target) }
        }
    }

    private func animateCount(to target: Int) {
        displayedInt = 0
        guard target > 0 else { return }
        let steps = min(target, 24)
        let duration = 0.8
        for i in 1...steps {
            let delay = duration * Double(i) / Double(steps)
            let stepValue = Int(Double(target) * Double(i) / Double(steps))
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeOut(duration: 0.05)) {
                    displayedInt = stepValue
                }
            }
        }
    }
}
