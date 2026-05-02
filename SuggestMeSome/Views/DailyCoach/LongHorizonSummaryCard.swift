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

    var body: some View {
        let coachCopy = CoachPresentationService.longHorizonSummary(for: summary)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.forward.circle")
                    .foregroundStyle(DSColor.primaryAction)
                Text("Multi-Block Trend")
                    .dsHeadline()
                Spacer()
                blockCountBadge
            }

            Divider()

            CoachPresentationSummaryCard(
                copy: coachCopy,
                eyebrow: "Coach Take",
                accent: DSColor.primaryAction,
                supportLimit: 2
            )

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
                        .background(DSColor.primaryAction)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DSColor.primaryAction.opacity(0.25), lineWidth: 1))
    }

    private var blockCountBadge: some View {
        Text("\(summary.blockCount) block\(summary.blockCount == 1 ? "" : "s")")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(DSColor.primaryAction.opacity(0.12))
            .foregroundStyle(DSColor.primaryAction)
            .clipShape(Capsule())
    }

}
