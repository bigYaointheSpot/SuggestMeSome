//
//  AdaptationProposalReviewView.swift
//  SuggestMeSome
//
//  Created by Codex on 4/7/26.
//

import SwiftUI
import SwiftData

/// Review UI for adaptive proposals that require manual confirmation.
/// Volume changes and deload/downshift proposals are approved or rejected here.
struct AdaptationProposalReviewView: View {
    @Bindable var run: ProgramRun

    @Environment(\.modelContext) private var modelContext
    @Query private var allProposals: [AdaptationProposal]

    @State private var inFlightProposalID: UUID?
    @State private var proposalPendingReject: AdaptationProposal?
    @State private var errorMessage: String?

    private var pendingProposals: [AdaptationProposal] {
        AdaptationProposalConfirmationService
            .pendingUserProposals(for: run, proposals: allProposals)
    }

    var body: some View {
        List {
            if pendingProposals.isEmpty {
                ContentUnavailableView(
                    "No Pending Proposals",
                    systemImage: "checkmark.circle",
                    description: Text("Adaptive volume and deload changes that need confirmation will appear here.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section("Pending Confirmation") {
                    ForEach(pendingProposals) { proposal in
                        proposalCard(for: proposal)
                            .padding(.vertical, 6)
                            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                            .listRowBackground(Color.clear)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Adaptive Proposals")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Reject Proposal?",
            isPresented: Binding(
                get: { proposalPendingReject != nil },
                set: { if !$0 { proposalPendingReject = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Reject", role: .destructive) {
                if let proposal = proposalPendingReject {
                    reject(proposal)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(proposalPendingReject?.summaryText ?? "")
        }
        .alert(
            "Couldn’t Update Proposal",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    @ViewBuilder
    private func proposalCard(for proposal: AdaptationProposal) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Text(title(for: proposal))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(affectedWindowText(for: proposal))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
            }

            Text(changeSummary(for: proposal))
                .font(.subheadline)
                .foregroundStyle(.primary)

            Text("Why: \(reasonText(for: proposal.adjustmentReason))")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let detail = proposal.detailText, !detail.isEmpty {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
            }

            HStack(spacing: 8) {
                Button {
                    approve(proposal)
                } label: {
                    Text("Approve")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(isBusy(with: proposal.id))

                Button {
                    proposalPendingReject = proposal
                } label: {
                    Text("Reject")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(isBusy(with: proposal.id))
            }

            Text("Decide later by leaving this proposal pending.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
    }

    private func approve(_ proposal: AdaptationProposal) {
        guard inFlightProposalID == nil else { return }
        inFlightProposalID = proposal.id
        defer { inFlightProposalID = nil }

        do {
            try AdaptationProposalConfirmationService.approve(proposal, context: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reject(_ proposal: AdaptationProposal) {
        guard inFlightProposalID == nil else { return }
        inFlightProposalID = proposal.id
        defer {
            proposalPendingReject = nil
            inFlightProposalID = nil
        }

        do {
            try AdaptationProposalConfirmationService.reject(proposal, context: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func isBusy(with proposalID: UUID) -> Bool {
        inFlightProposalID == proposalID
    }

    private func title(for proposal: AdaptationProposal) -> String {
        switch proposal.proposalType {
        case .increaseVolume: return "Volume Increase"
        case .decreaseVolume: return "Volume Decrease"
        case .deload: return "Deload Week"
        case .decreaseLoad: return "Downshift"
        default: return "Adaptive Proposal"
        }
    }

    private func affectedWindowText(for proposal: AdaptationProposal) -> String {
        let start = proposal.targetWeekStart
        let end = max(start, proposal.targetWeekEnd ?? start)
        if start == end {
            if let session = proposal.targetSessionNumber {
                return "Week \(start), S\(session)"
            }
            return "Week \(start)"
        }
        return "Weeks \(start)-\(end)"
    }

    private func changeSummary(for proposal: AdaptationProposal) -> String {
        switch proposal.proposalType {
        case .increaseVolume, .decreaseVolume:
            let delta = proposal.proposedSetDelta ?? 0
            let deltaText = delta > 0 ? "+\(delta)" : "\(delta)"
            let exerciseName = targetExerciseName(for: proposal) ?? "target accessory work"
            return "Adjust sets by \(deltaText) for \(exerciseName)."

        case .deload:
            var parts: [String] = ["Apply a recovery-focused deload."]
            if let loadDelta = proposal.proposedLoadPercentDelta {
                parts.append("Load \(percentText(loadDelta)).")
            }
            if let setDelta = proposal.proposedSetDelta {
                let setText = setDelta > 0 ? "+\(setDelta)" : "\(setDelta)"
                parts.append("Sets \(setText).")
            }
            if let factor = proposal.proposedDeloadFactor {
                parts.append("Deload factor \(percentText(factor - 1)).")
            }
            return parts.joined(separator: " ")

        case .decreaseLoad:
            var parts: [String] = ["Apply a conservative downshift."]
            if let loadDelta = proposal.proposedLoadPercentDelta {
                parts.append("Load \(percentText(loadDelta)).")
            }
            if let setDelta = proposal.proposedSetDelta {
                let setText = setDelta > 0 ? "+\(setDelta)" : "\(setDelta)"
                parts.append("Sets \(setText).")
            }
            return parts.joined(separator: " ")

        default:
            return proposal.summaryText
        }
    }

    private func targetExerciseName(for proposal: AdaptationProposal) -> String? {
        guard let targetID = proposal.targetProgramSessionExerciseID else { return nil }
        guard let program = run.program else { return nil }

        for week in program.weeks {
            for session in week.sessions {
                if let match = session.exercises.first(where: { $0.id == targetID }) {
                    return match.exerciseName
                }
            }
        }
        return nil
    }

    private func reasonText(for reason: AdjustmentReason) -> String {
        switch reason {
        case .topSetBeatTarget: return "Top-set performance exceeded target"
        case .topSetMissedTarget: return "Top-set performance missed target"
        case .accessoryOutperformance: return "Accessory performance is ahead"
        case .accessoryUnderperformance: return "Accessory performance is behind"
        case .fatigueAccumulation: return "Fatigue has accumulated across the week"
        case .fatigueResolved: return "Fatigue appears resolved"
        case .positiveLiftTrend: return "Lift-family trend is improving"
        case .negativeLiftTrend: return "Lift-family trend is declining"
        case .plateauDetected: return "Trend indicates a plateau"
        case .lowAdherence: return "Session adherence was low"
        case .standaloneTrendSupport: return "Standalone sessions support this trend"
        case .programSignalPriority: return "Program-linked signals had higher confidence"
        }
    }

    private func percentText(_ value: Double) -> String {
        let percent = value * 100
        if percent >= 0 {
            return String(format: "+%.0f%%", percent)
        }
        return String(format: "%.0f%%", percent)
    }
}
