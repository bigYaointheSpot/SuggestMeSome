import Foundation
import SwiftData

@MainActor
struct LocalAdaptiveSyncStore {
    let context: LocalSyncStoreContext

    func fetchAdaptationProposalPayloads(since: Date?) throws -> [AdaptationProposalSyncDTO] {
        try context.measureSyncExport(named: "AdaptationProposal", since: since) {
            try context.fetchRows(adaptationProposalFetchDescriptor(since: since))
                .map { $0.toSyncDTO() }
        }
    }

    func upsertAdaptationProposalPayloads(_ payloads: [AdaptationProposalSyncDTO]) throws {
        guard !payloads.isEmpty else { return }

        var proposals = try context.stableIDMap(for: AdaptationProposal.self)
        let runs = try context.stableIDMap(for: ProgramRun.self)
        let programs = try context.stableIDMap(for: TrainingProgram.self)
        let analysesByID = try context.analysesByID()

        for payload in payloads {
            if let existing = proposals[payload.metadata.stableID] {
                existing.apply(syncDTO: payload)
                existing.programRun = payload.programRunStableID.flatMap { runs[$0] }
                existing.trainingProgram = payload.trainingProgramStableID.flatMap { programs[$0] }
                existing.sourceAnalysis = payload.sourceAnalysisStableID.flatMap { analysesByID[$0] }
            } else {
                let proposal = AdaptationProposal(
                    id: UUID(uuidString: payload.metadata.stableID) ?? UUID(),
                    syncStableID: payload.metadata.stableID,
                    syncVersion: payload.metadata.version,
                    syncLastModifiedAt: payload.metadata.lastModifiedAt,
                    createdAt: payload.createdAt,
                    decidedAt: payload.decidedAt,
                    programRun: payload.programRunStableID.flatMap { runs[$0] },
                    trainingProgram: payload.trainingProgramStableID.flatMap { programs[$0] },
                    sourceAnalysis: payload.sourceAnalysisStableID.flatMap { analysesByID[$0] },
                    proposalType: ProposalType(rawValue: payload.proposalTypeRawValue) ?? .increaseLoad,
                    proposalStatus: ProposalStatus(rawValue: payload.proposalStatusRawValue) ?? .draft,
                    requiresUserConfirmation: payload.requiresUserConfirmation,
                    autoApplyEligible: payload.autoApplyEligible,
                    confidenceScore: payload.confidenceScore,
                    priority: payload.priority,
                    targetWeekStart: payload.targetWeekStart,
                    targetWeekEnd: payload.targetWeekEnd,
                    targetSessionNumber: payload.targetSessionNumber,
                    targetProgramSessionExerciseID: payload.targetProgramSessionExerciseStableID.flatMap(UUID.init(uuidString:)),
                    targetLiftKey: payload.targetLiftKey,
                    proposedLoadPercentDelta: payload.proposedLoadPercentDelta,
                    proposedSetDelta: payload.proposedSetDelta,
                    proposedRepDelta: payload.proposedRepDelta,
                    proposedDeloadFactor: payload.proposedDeloadFactor,
                    swapFromExerciseName: payload.swapFromExerciseName,
                    swapToExerciseName: payload.swapToExerciseName,
                    adjustmentReason: AdjustmentReason(rawValue: payload.adjustmentReasonRawValue) ?? .programSignalPriority,
                    summaryText: payload.summaryText,
                    detailText: payload.detailText,
                    expiresAt: payload.expiresAt
                )
                context.modelContext.insert(proposal)
                proposals[payload.metadata.stableID] = proposal
            }
        }

        try context.save()
    }

    func fetchAppliedOverlayPayloads(since: Date?) throws -> [AppliedProgramOverlaySyncDTO] {
        try context.measureSyncExport(named: "AppliedProgramOverlay", since: since) {
            try context.fetchRows(appliedOverlayFetchDescriptor(since: since))
                .map { $0.toSyncDTO() }
        }
    }

    func upsertAppliedOverlayPayloads(_ payloads: [AppliedProgramOverlaySyncDTO]) throws {
        guard !payloads.isEmpty else { return }

        var overlays = try context.stableIDMap(for: AppliedProgramOverlay.self)
        let runs = try context.stableIDMap(for: ProgramRun.self)
        let programs = try context.stableIDMap(for: TrainingProgram.self)
        let proposals = try context.stableIDMap(for: AdaptationProposal.self)

        for payload in payloads {
            let run = payload.programRunStableID.flatMap { runs[$0] }
            let program = payload.trainingProgramStableID.flatMap { programs[$0] }
            let proposal = payload.sourceProposalStableID.flatMap { proposals[$0] }

            if let existing = overlays[payload.metadata.stableID] {
                existing.apply(syncDTO: payload)
                existing.programRun = run
                existing.trainingProgram = program
                existing.sourceProposal = proposal
                try upsertOverlayAdjustments(payload.adjustments, into: existing)
            } else {
                let overlay = AppliedProgramOverlay(
                    id: UUID(uuidString: payload.metadata.stableID) ?? UUID(),
                    syncStableID: payload.metadata.stableID,
                    syncVersion: payload.metadata.version,
                    syncLastModifiedAt: payload.metadata.lastModifiedAt,
                    createdAt: payload.createdAt,
                    appliedAt: payload.appliedAt,
                    programRun: run,
                    trainingProgram: program,
                    sourceProposal: proposal,
                    effectiveWeekStart: payload.effectiveWeekStart,
                    effectiveWeekEnd: payload.effectiveWeekEnd,
                    overlayStatus: OverlayStatus(rawValue: payload.overlayStatusRawValue) ?? .active,
                    appliedByUserConfirmation: payload.appliedByUserConfirmation,
                    adjustmentReason: AdjustmentReason(rawValue: payload.adjustmentReasonRawValue) ?? .programSignalPriority,
                    summaryText: payload.summaryText
                )
                context.modelContext.insert(overlay)
                for adjustmentPayload in payload.adjustments {
                    let adjustment = AppliedOverlayAdjustment.fromSyncDTO(adjustmentPayload)
                    adjustment.overlay = overlay
                    context.modelContext.insert(adjustment)
                }
                overlays[payload.metadata.stableID] = overlay
            }
        }

        try context.save()
    }

    private func upsertOverlayAdjustments(
        _ payloads: [AppliedOverlayAdjustmentSyncDTO],
        into overlay: AppliedProgramOverlay
    ) throws {
        var existingByID: [String: AppliedOverlayAdjustment] = [:]
        for adjustment in overlay.adjustments {
            adjustment.initializeSyncMetadataIfNeeded()
            existingByID[adjustment.resolvedSyncStableID] = adjustment
        }

        var incomingIDs: Set<String> = []
        for payload in payloads {
            incomingIDs.insert(payload.metadata.stableID)
            if let existing = existingByID[payload.metadata.stableID] {
                existing.syncStableID = payload.metadata.stableID
                existing.syncVersion = payload.metadata.version
                existing.syncLastModifiedAt = payload.metadata.lastModifiedAt
                existing.sequence = payload.sequence
                existing.targetProgramSessionExerciseID = payload.targetProgramSessionExerciseStableID.flatMap(UUID.init(uuidString:))
                existing.targetWeekNumber = payload.targetWeekNumber
                existing.targetSessionNumber = payload.targetSessionNumber
                existing.adjustmentType = OverlayAdjustmentType(rawValue: payload.adjustmentTypeRawValue) ?? .load
                existing.loadPercentDelta = payload.loadPercentDelta
                existing.absolutePrescribedWeight = payload.absolutePrescribedWeight
                existing.setDelta = payload.setDelta
                existing.absoluteTargetSets = payload.absoluteTargetSets
                existing.repDelta = payload.repDelta
                existing.absoluteTargetReps = payload.absoluteTargetReps
                existing.replacementExerciseName = payload.replacementExerciseName
                existing.adjustmentReason = AdjustmentReason(rawValue: payload.adjustmentReasonRawValue) ?? .programSignalPriority
                existing.isAutoApplied = payload.isAutoApplied
                existing.overlay = overlay
            } else {
                let adjustment = AppliedOverlayAdjustment.fromSyncDTO(payload)
                adjustment.overlay = overlay
                context.modelContext.insert(adjustment)
            }
        }

        for stale in overlay.adjustments where !incomingIDs.contains(stale.resolvedSyncStableID) {
            context.modelContext.delete(stale)
        }
    }

    private func adaptationProposalFetchDescriptor(since: Date?) -> FetchDescriptor<AdaptationProposal> {
        let sortBy = [SortDescriptor(\AdaptationProposal.createdAt, order: .reverse)]
        guard let sinceDate = since else {
            return FetchDescriptor<AdaptationProposal>(sortBy: sortBy)
        }
        return FetchDescriptor<AdaptationProposal>(
            predicate: #Predicate<AdaptationProposal> { proposal in
                proposal.syncLastModifiedAt >= sinceDate
            },
            sortBy: sortBy
        )
    }

    private func appliedOverlayFetchDescriptor(since: Date?) -> FetchDescriptor<AppliedProgramOverlay> {
        let sortBy = [SortDescriptor(\AppliedProgramOverlay.appliedAt, order: .reverse)]
        guard let sinceDate = since else {
            return FetchDescriptor<AppliedProgramOverlay>(sortBy: sortBy)
        }
        return FetchDescriptor<AppliedProgramOverlay>(
            predicate: #Predicate<AppliedProgramOverlay> { overlay in
                overlay.syncLastModifiedAt >= sinceDate
            },
            sortBy: sortBy
        )
    }
}
