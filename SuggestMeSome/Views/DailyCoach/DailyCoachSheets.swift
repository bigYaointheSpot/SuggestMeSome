//
//  DailyCoachSheets.swift
//  SuggestMeSome
//
//  Modal sheets extracted from DailyCoachView in Feature 22 Prompt 1.
//

import SwiftUI
import SwiftData

struct TodayPlanProposalReviewSheet: View {
    let proposal: AdaptationProposal
    let program: TrainingProgram?
    let onApprove: () -> Void
    let onReject: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let summary = AdaptationProposalPresentationService.makeDisplaySummary(
            for: proposal,
            program: program
        )
        NavigationStack {
            List {
                Section("Proposal") {
                    Text(summary.title)
                        .font(.subheadline.weight(.semibold))
                    Text(summary.changeSummary)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(summary.affectedWindowText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Why") {
                    Text(summary.reasonText)
                        .font(.subheadline)
                    if let detail = summary.detailText, !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section {
                    Text("Approve/reject requires one more confirmation. Base program rows are never mutated.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Review Proposal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button("Reject", role: .destructive) {
                        onReject()
                    }
                    Button("Approve") {
                        onApprove()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - DraftReviewSheet

struct DraftReviewSheet: View {
    let draft: PreparedWorkoutDraft
    let sessionLabel: String
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(sessionLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Session")
                }

                Section {
                    if draft.changeDescriptions.isEmpty {
                        Text("No changes — session will run as planned.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(draft.changeDescriptions.enumerated()), id: \.offset) { _, desc in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: changeIcon)
                                    .font(.subheadline)
                                    .foregroundStyle(changeColor)
                                    .frame(width: 20)
                                Text(desc)
                                    .font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    Text("Suggested Changes")
                } footer: {
                    Text("These changes apply only to today's session. Your program is not modified.")
                        .font(.caption)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Review Suggested Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start Suggested Session") {
                        onConfirm()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var changeIcon: String {
        switch draft.adjustmentType {
        case .trimAccessories:            return "minus.circle"
        case .trimOneBackoffSet:          return "arrow.down.circle"
        case .reduceWorkingLoadsSlightly: return "scalemass"
        case .suggestManualVariationSwap: return "exclamationmark.triangle"
        default:                          return "checkmark.circle"
        }
    }

    private var changeColor: Color {
        switch draft.adjustmentType {
        case .trimAccessories:            return .orange
        case .trimOneBackoffSet:          return .yellow
        case .reduceWorkingLoadsSlightly: return .orange
        case .suggestManualVariationSwap: return .red
        default:                          return .green
        }
    }
}
