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
    @State private var pendingProposals: [AdaptationProposal] = []

    @State private var inFlightProposalID: UUID?
    @State private var proposalPendingReject: AdaptationProposal?
    @State private var errorMessage: String?

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
        .task(id: run.id) {
            reloadPendingProposals()
        }
    }

    @ViewBuilder
    private func proposalCard(for proposal: AdaptationProposal) -> some View {
        let summary = AdaptationProposalPresentationService.makeDisplaySummary(
            for: proposal,
            program: run.program
        )
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Text(summary.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(summary.affectedWindowText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
            }

            Text(summary.changeSummary)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Text("Why: \(summary.reasonText)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let detail = summary.detailText, !detail.isEmpty {
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
            reloadPendingProposals()
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
            reloadPendingProposals()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func isBusy(with proposalID: UUID) -> Bool {
        inFlightProposalID == proposalID
    }

    private func reloadPendingProposals() {
        pendingProposals = ReadQueryRepository
            .pendingUserProposals(for: run, context: modelContext, limit: 32)
            .filter { AdaptationProposalConfirmationService.isPendingUserProposal($0) }
    }
}
