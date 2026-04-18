//
//  BodyHeatmapView.swift
//  SuggestMeSome
//
//  Per-muscle stress saturation visualization.
//

import SwiftUI

struct BodyHeatmapView: View {
    /// Saturation values from TrainingStateSnapshot.perMuscleStressSaturation (0.0–1.4).
    let saturation: [ProgramVolumeMuscle: Double]

    private let columns = [GridItem(.flexible(), spacing: DSSpacing.s), GridItem(.flexible(), spacing: DSSpacing.s)]

    private var sortedMuscles: [ProgramVolumeMuscle] {
        ProgramVolumeMuscle.allCases.sorted { lhs, rhs in
            (saturation[lhs] ?? 0) > (saturation[rhs] ?? 0)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            LazyVGrid(columns: columns, spacing: DSSpacing.s) {
                ForEach(sortedMuscles, id: \.self) { muscle in
                    muscleTile(muscle)
                }
            }

            HStack(spacing: DSSpacing.m) {
                legendDot(color: .gray.opacity(0.35),                label: "Low")
                legendDot(color: DSColor.signalNeutral.opacity(0.6), label: "Moderate")
                legendDot(color: DSColor.signalCaution,              label: "High")
                legendDot(color: DSColor.signalCritical,             label: "Saturated")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func muscleTile(_ muscle: ProgramVolumeMuscle) -> some View {
        let value = saturation[muscle] ?? 0
        let color = heatColor(for: value)

        return HStack(spacing: DSSpacing.s) {
            RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous)
                .fill(color)
                .frame(width: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(muscle.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(saturationLabel(value))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DSSpacing.s)
        .padding(.horizontal, DSSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous))
    }

    private func heatColor(for value: Double) -> Color {
        switch value {
        case ..<0.35:       return .gray.opacity(0.4)
        case 0.35..<0.70:   return DSColor.signalNeutral.opacity(0.7)
        case 0.70..<1.0:    return DSColor.signalCaution
        default:            return DSColor.signalCritical
        }
    }

    private func saturationLabel(_ value: Double) -> String {
        let pct = Int((min(value, 1.4) * 100).rounded())
        return "\(pct)%"
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
        }
    }
}
