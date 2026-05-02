//
//  BlockContinuityCard.swift
//  SuggestMeSome
//
//  Feature 13 Prompt 6 — Compact block continuity strip for Daily Coach.
//

import SwiftUI

struct BlockContinuityCard: View {
    let completedRuns: [ProgramRun]
    let activeRun: ProgramRun?
    let onReviewLastBlock: () -> Void

    // Most-recent-last so the strip reads left → right chronologically.
    private var orderedCompleted: [ProgramRun] {
        completedRuns
            .sorted { ($0.endDate ?? $0.startDate) < ($1.endDate ?? $1.startDate) }
            .suffix(3)
            .map { $0 }
    }

    var body: some View {
        DSCard(.flat) {
            cardContent
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Block Continuity", systemImage: "arrow.forward.circle")
                .dsHeadline()

            DSDivider()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(orderedCompleted.enumerated()), id: \.element.id) { index, run in
                        blockNode(run: run, isCurrent: false)
                        chevronSeparator
                    }

                    if let active = activeRun {
                        blockNode(run: active, isCurrent: true)
                        chevronSeparator
                        nextBlockPlaceholder
                    } else {
                        betweenBlocksNode
                    }
                }
                .padding(.vertical, 2)
            }

            Button(action: onReviewLastBlock) {
                HStack(spacing: 5) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.caption2)
                    Text("Review Last Block")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.teal)
            }
            .buttonStyle(.plain)
        }
    }

    private func blockNode(run: ProgramRun, isCurrent: Bool) -> some View {
        let accent: Color = isCurrent ? .teal : .secondary
        return VStack(alignment: .leading, spacing: 3) {
            Text(run.program?.name ?? "Block")
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(isCurrent ? .teal : .primary)
            Text(shortDateLabel(run.startDate))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(accent.opacity(isCurrent ? 0.10 : 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(accent.opacity(isCurrent ? 0.35 : 0.0), lineWidth: 1)
        )
    }

    private var betweenBlocksNode: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Between Blocks")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
            Text("Ready for next")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    private var nextBlockPlaceholder: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Next Block")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Pending")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(.quaternarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var chevronSeparator: some View {
        Image(systemName: "chevron.right")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    private func shortDateLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM yy"
        return f.string(from: date)
    }
}
