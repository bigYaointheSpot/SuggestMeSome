//
//  AdaptationProposalConfirmationService.swift
//  SuggestMeSome
//
//  Created by Codex on 4/7/26.
//

import Foundation
import SwiftData

/// Handles user decisions for adaptive proposals that require confirmation
/// and persists corresponding non-destructive overlays.
@MainActor
enum AdaptationProposalConfirmationService {
    private static let supportedUserProposalTypes: Set<ProposalType> = [
        .increaseVolume,
        .decreaseVolume,
        .deload,
        .decreaseLoad
    ]

    enum ActionError: LocalizedError {
        case unsupportedProposal
        case invalidProposalData

        var errorDescription: String? {
            switch self {
            case .unsupportedProposal:
                return "This proposal is no longer eligible for manual confirmation."
            case .invalidProposalData:
                return "This proposal is missing required adjustment data and cannot be applied."
            }
        }
    }

    static func pendingUserProposals(
        for run: ProgramRun,
        proposals: [AdaptationProposal]
    ) -> [AdaptationProposal] {
        proposals
            .filter {
                $0.programRun?.id == run.id &&
                isPendingUserProposal($0)
            }
            .sorted(by: pendingSort)
    }

    static func isPendingUserProposal(_ proposal: AdaptationProposal) -> Bool {
        proposal.requiresUserConfirmation &&
        proposal.proposalStatus == .pendingUserConfirmation &&
        supportedUserProposalTypes.contains(proposal.proposalType)
    }

    static func approve(
        _ proposal: AdaptationProposal,
        context: ModelContext
    ) throws {
        guard isPendingUserProposal(proposal) else {
            throw ActionError.unsupportedProposal
        }

        let now = Date.now
        let overlay = try upsertAppliedOverlay(for: proposal, at: now, context: context)

        proposal.proposalStatus = .confirmed
        proposal.decidedAt = now

        markProposalCreatedEventsResolved(
            proposal: proposal,
            context: context
        )
        upsertDecisionEvent(
            type: .proposalConfirmed,
            proposal: proposal,
            overlay: overlay,
            at: now,
            context: context
        )
        upsertOverlayAppliedEvent(
            proposal: proposal,
            overlay: overlay,
            at: now,
            context: context
        )

        try context.save()
    }

    static func reject(
        _ proposal: AdaptationProposal,
        context: ModelContext
    ) throws {
        guard isPendingUserProposal(proposal) else {
            throw ActionError.unsupportedProposal
        }

        let now = Date.now
        proposal.proposalStatus = .rejected
        proposal.decidedAt = now

        for overlay in proposal.appliedOverlays {
            overlay.overlayStatus = .reverted
        }

        markProposalCreatedEventsResolved(
            proposal: proposal,
            context: context
        )
        upsertDecisionEvent(
            type: .proposalRejected,
            proposal: proposal,
            overlay: nil,
            at: now,
            context: context
        )

        try context.save()
    }

    // MARK: - Overlay Apply

    private static func upsertAppliedOverlay(
        for proposal: AdaptationProposal,
        at timestamp: Date,
        context: ModelContext
    ) throws -> AppliedProgramOverlay {
        let overlays = (try? context.fetch(FetchDescriptor<AppliedProgramOverlay>())) ?? []
        let overlay = overlays.first(where: { $0.sourceProposal?.id == proposal.id }) ?? {
            let created = AppliedProgramOverlay(
                programRun: proposal.programRun,
                trainingProgram: proposal.trainingProgram,
                sourceProposal: proposal,
                effectiveWeekStart: proposal.targetWeekStart,
                effectiveWeekEnd: proposal.targetWeekEnd,
                appliedByUserConfirmation: true,
                adjustmentReason: proposal.adjustmentReason,
                summaryText: proposal.summaryText
            )
            context.insert(created)
            return created
        }()

        overlay.appliedAt = timestamp
        overlay.programRun = proposal.programRun
        overlay.trainingProgram = proposal.trainingProgram
        overlay.sourceProposal = proposal
        overlay.effectiveWeekStart = proposal.targetWeekStart
        overlay.effectiveWeekEnd = proposal.targetWeekEnd ?? proposal.targetWeekStart
        overlay.overlayStatus = .active
        overlay.appliedByUserConfirmation = true
        overlay.adjustmentReason = proposal.adjustmentReason
        overlay.summaryText = proposal.summaryText

        let adjustments = try buildAdjustments(for: proposal, overlay: overlay)
        guard !adjustments.isEmpty else { throw ActionError.invalidProposalData }

        for existing in overlay.adjustments {
            context.delete(existing)
        }
        overlay.adjustments.removeAll()

        for (index, adjustment) in adjustments.enumerated() {
            adjustment.overlay = overlay
            adjustment.sequence = index
            context.insert(adjustment)
        }
        overlay.adjustments = adjustments

        return overlay
    }

    private static func buildAdjustments(
        for proposal: AdaptationProposal,
        overlay: AppliedProgramOverlay
    ) throws -> [AppliedOverlayAdjustment] {
        switch proposal.proposalType {
        case .increaseVolume, .decreaseVolume:
            guard proposal.targetProgramSessionExerciseID != nil else {
                throw ActionError.invalidProposalData
            }
            guard let setDelta = proposal.proposedSetDelta, setDelta != 0 else {
                throw ActionError.invalidProposalData
            }

            return effectiveWeeks(for: proposal).enumerated().map { index, week in
                AppliedOverlayAdjustment(
                    overlay: overlay,
                    sequence: index,
                    targetProgramSessionExerciseID: proposal.targetProgramSessionExerciseID,
                    targetWeekNumber: week,
                    targetSessionNumber: proposal.targetSessionNumber,
                    adjustmentType: .volume,
                    setDelta: setDelta,
                    adjustmentReason: proposal.adjustmentReason,
                    isAutoApplied: false
                )
            }

        case .deload:
            guard proposal.proposedLoadPercentDelta != nil || proposal.proposedSetDelta != nil else {
                throw ActionError.invalidProposalData
            }

            return effectiveWeeks(for: proposal).enumerated().map { index, week in
                AppliedOverlayAdjustment(
                    overlay: overlay,
                    sequence: index,
                    targetProgramSessionExerciseID: nil,
                    targetWeekNumber: week,
                    targetSessionNumber: nil,
                    adjustmentType: .deload,
                    loadPercentDelta: proposal.proposedLoadPercentDelta,
                    setDelta: proposal.proposedSetDelta,
                    adjustmentReason: proposal.adjustmentReason,
                    isAutoApplied: false
                )
            }

        case .decreaseLoad:
            guard proposal.proposedLoadPercentDelta != nil || proposal.proposedSetDelta != nil else {
                throw ActionError.invalidProposalData
            }

            return effectiveWeeks(for: proposal).enumerated().map { index, week in
                AppliedOverlayAdjustment(
                    overlay: overlay,
                    sequence: index,
                    targetProgramSessionExerciseID: nil,
                    targetWeekNumber: week,
                    targetSessionNumber: nil,
                    adjustmentType: .load,
                    loadPercentDelta: proposal.proposedLoadPercentDelta,
                    setDelta: proposal.proposedSetDelta,
                    adjustmentReason: proposal.adjustmentReason,
                    isAutoApplied: false
                )
            }

        default:
            throw ActionError.unsupportedProposal
        }
    }

    private static func effectiveWeeks(for proposal: AdaptationProposal) -> [Int] {
        let start = proposal.targetWeekStart
        let end = max(start, proposal.targetWeekEnd ?? start)
        return Array(start...end)
    }

    // MARK: - Event History

    private static func markProposalCreatedEventsResolved(
        proposal: AdaptationProposal,
        context: ModelContext
    ) {
        let events = (try? context.fetch(FetchDescriptor<AdaptationEventHistory>())) ?? []
        for event in events {
            guard event.proposal?.id == proposal.id else { continue }
            guard event.eventType == .proposalCreated else { continue }
            event.requiresUserAction = false
            event.userActionTaken = true
            event.timestamp = Date.now
        }
    }

    private static func upsertDecisionEvent(
        type: AdaptationEventType,
        proposal: AdaptationProposal,
        overlay: AppliedProgramOverlay?,
        at timestamp: Date,
        context: ModelContext
    ) {
        let events = (try? context.fetch(FetchDescriptor<AdaptationEventHistory>())) ?? []
        let event = events.first(where: {
            $0.proposal?.id == proposal.id &&
            $0.eventType == type
        }) ?? {
            let created = AdaptationEventHistory(
                programRun: proposal.programRun,
                trainingProgram: proposal.trainingProgram,
                analysis: proposal.sourceAnalysis,
                proposal: proposal,
                overlay: overlay,
                eventType: type,
                analysisWeekNumber: proposal.sourceAnalysis?.programWeekNumber,
                targetLiftKey: proposal.targetLiftKey,
                message: proposal.summaryText
            )
            context.insert(created)
            return created
        }()

        event.timestamp = timestamp
        event.programRun = proposal.programRun
        event.trainingProgram = proposal.trainingProgram
        event.analysis = proposal.sourceAnalysis
        event.proposal = proposal
        event.overlay = overlay
        event.eventType = type
        event.analysisWeekNumber = proposal.sourceAnalysis?.programWeekNumber
        event.targetLiftKey = proposal.targetLiftKey
        event.message = message(for: type, proposal: proposal)
        event.explanation = proposal.detailText
        event.adjustmentReason = proposal.adjustmentReason
        event.performanceScoreSnapshot = nil
        event.fatigueStatusSnapshot = proposal.sourceAnalysis?.fatigueStatus
        event.liftTrendStatusSnapshot = nil
        event.confidenceSnapshot = proposal.confidenceScore
        event.requiresUserAction = false
        event.userActionTaken = true
    }

    private static func upsertOverlayAppliedEvent(
        proposal: AdaptationProposal,
        overlay: AppliedProgramOverlay,
        at timestamp: Date,
        context: ModelContext
    ) {
        let events = (try? context.fetch(FetchDescriptor<AdaptationEventHistory>())) ?? []
        let event = events.first(where: {
            $0.proposal?.id == proposal.id &&
            $0.overlay?.id == overlay.id &&
            $0.eventType == .overlayApplied
        }) ?? {
            let created = AdaptationEventHistory(
                programRun: proposal.programRun,
                trainingProgram: proposal.trainingProgram,
                analysis: proposal.sourceAnalysis,
                proposal: proposal,
                overlay: overlay,
                eventType: .overlayApplied,
                analysisWeekNumber: proposal.sourceAnalysis?.programWeekNumber,
                targetLiftKey: proposal.targetLiftKey,
                message: proposal.summaryText
            )
            context.insert(created)
            return created
        }()

        event.timestamp = timestamp
        event.programRun = proposal.programRun
        event.trainingProgram = proposal.trainingProgram
        event.analysis = proposal.sourceAnalysis
        event.proposal = proposal
        event.overlay = overlay
        event.eventType = .overlayApplied
        event.analysisWeekNumber = proposal.sourceAnalysis?.programWeekNumber
        event.targetLiftKey = proposal.targetLiftKey
        event.message = "Applied confirmed overlay for week \(proposal.targetWeekStart)"
        event.explanation = proposal.detailText
        event.adjustmentReason = proposal.adjustmentReason
        event.performanceScoreSnapshot = nil
        event.fatigueStatusSnapshot = proposal.sourceAnalysis?.fatigueStatus
        event.liftTrendStatusSnapshot = nil
        event.confidenceSnapshot = proposal.confidenceScore
        event.requiresUserAction = false
        event.userActionTaken = true
    }

    // MARK: - Helpers

    private static func message(
        for type: AdaptationEventType,
        proposal: AdaptationProposal
    ) -> String {
        switch type {
        case .proposalConfirmed:
            return "Proposal approved: \(proposal.summaryText)"
        case .proposalRejected:
            return "Proposal rejected: \(proposal.summaryText)"
        default:
            return proposal.summaryText
        }
    }

    private static func pendingSort(
        lhs: AdaptationProposal,
        rhs: AdaptationProposal
    ) -> Bool {
        if lhs.priority != rhs.priority {
            return lhs.priority > rhs.priority
        }
        if lhs.targetWeekStart != rhs.targetWeekStart {
            return lhs.targetWeekStart < rhs.targetWeekStart
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
