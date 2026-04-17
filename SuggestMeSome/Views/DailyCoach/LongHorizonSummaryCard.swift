//
//  LongHorizonSummaryCard.swift
//  SuggestMeSome
//
//  Feature 13 Prompt 6 — Multi-block trend card for Daily Coach.
//

import SwiftUI

struct LongHorizonSummaryCard: View {
    let summary: LongHorizonAdaptationSummary
    let onReviewBlock: () -> Void
    let onGenerateNextBlock: () -> Void

    private var actionableInsights: [LongHorizonAdaptationInsight] {
        summary.insights
            .filter { $0.kind != .insufficientData }
            .prefix(3)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.forward.circle")
                    .foregroundStyle(.indigo)
                Text("Multi-Block Trend")
                    .font(.headline)
                Spacer()
                blockCountBadge
            }

            Divider()

            Text(summary.headline)
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)

            if !actionableInsights.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(actionableInsights, id: \.title) { insight in
                        insightRow(insight)
                    }
                }
            }

            Divider()

            HStack(spacing: 10) {
                Button(action: onReviewBlock) {
                    Text("Review Block")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(.tertiarySystemBackground))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Button(action: onGenerateNextBlock) {
                    Text("Generate Next Block")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.indigo)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.indigo.opacity(0.25), lineWidth: 1))
    }

    private var blockCountBadge: some View {
        Text("\(summary.blockCount) block\(summary.blockCount == 1 ? "" : "s")")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.indigo.opacity(0.12))
            .foregroundStyle(.indigo)
            .clipShape(Capsule())
    }

    private func insightRow(_ insight: LongHorizonAdaptationInsight) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: insightIcon(insight.kind))
                .font(.caption2)
                .foregroundStyle(insightColor(insight.kind))
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(insight.title)
                    .font(.caption.weight(.semibold))
                Text(insight.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func insightIcon(_ kind: LongHorizonAdaptationInsightKind) -> String {
        switch kind {
        case .adherenceTrend:       return "chart.line.uptrend.xyaxis"
        case .movementContinuity:   return "arrow.2.circlepath"
        case .toleratedFrequency:   return "calendar"
        case .missedSessionPattern: return "exclamationmark.triangle"
        case .standaloneInfluence:  return "plus.circle"
        case .insufficientData:     return "info.circle"
        }
    }

    private func insightColor(_ kind: LongHorizonAdaptationInsightKind) -> Color {
        switch kind {
        case .adherenceTrend:       return .green
        case .movementContinuity:   return .teal
        case .toleratedFrequency:   return .blue
        case .missedSessionPattern: return .orange
        case .standaloneInfluence:  return .indigo
        case .insufficientData:     return .secondary
        }
    }
}
