//
//  RecoveryPressureCard.swift
//  SuggestMeSome
//
//  Surfaces AdaptiveTrainingStateEngine.recoveryPressure + HealthKit insight.
//

import SwiftUI

struct RecoveryPressureCard: View {
    let pressure: TrainingStateRecoveryPressure
    let fatigueStatus: FatigueStatus?
    let healthKitInsight: ObjectiveRecoveryInsight?

    var body: some View {
        ExpandableCard(tint: pressure.dsAccentColor) {
            VStack(alignment: .leading, spacing: DSSpacing.m) {
                DSSectionHeader(
                    icon: "heart.circle.fill",
                    title: "Recovery",
                    iconColor: pressure.dsAccentColor
                )

                HStack(spacing: DSSpacing.l) {
                    gauge
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pressure.dsDisplayName)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(pressure.dsAccentColor)
                        Text(pressure.dsGuidance)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                if let insight = healthKitInsight {
                    HStack(spacing: DSSpacing.s) {
                        DSBadge("Sleep", tint: insight.status.dsAccentColor, systemImage: "bed.double.fill")
                        DSBadge("HRV",   tint: insight.status.dsAccentColor, systemImage: "waveform.path.ecg")
                        DSBadge("RHR",   tint: insight.status.dsAccentColor, systemImage: "heart.fill")
                    }
                }
            }
        } expanded: {
            VStack(alignment: .leading, spacing: DSSpacing.s) {
                if let fatigueStatus {
                    rowLine(
                        label: "Training fatigue",
                        value: fatigueStatus.dsDisplayName,
                        tint: fatigueStatus.dsAccentColor
                    )
                }
                if let insight = healthKitInsight {
                    Text(insight.detailSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Connect HealthKit in Settings to blend in HRV, sleep, and resting heart rate.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(explanationForPressure)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var gauge: some View {
        ZStack {
            Circle()
                .stroke(pressure.dsAccentColor.opacity(0.15), lineWidth: 6)
            Circle()
                .trim(from: 0, to: gaugeFraction)
                .stroke(pressure.dsAccentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: gaugeIcon)
                .font(.footnote.weight(.bold))
                .foregroundStyle(pressure.dsAccentColor)
        }
        .frame(width: 44, height: 44)
    }

    private var gaugeFraction: Double {
        switch pressure {
        case .conservative: return 0.33
        case .neutral:      return 0.66
        case .elevated:     return 1.0
        }
    }

    private var gaugeIcon: String {
        switch pressure {
        case .conservative: return "tortoise.fill"
        case .neutral:      return "equal"
        case .elevated:     return "bolt.fill"
        }
    }

    private var explanationForPressure: String {
        switch pressure {
        case .conservative:
            return "Why: elevated fatigue, volume behind plan, or low adherence. The engine will scale back intensity today."
        case .neutral:
            return "Why: training load and completion are near baseline. No adjustments needed."
        case .elevated:
            return "Why: recovery signals and adherence are strong. There's room to push."
        }
    }

    private func rowLine(label: String, value: String, tint: Color) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
        }
    }
}
