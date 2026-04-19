import Foundation
import SwiftData

@MainActor
struct LocalAdaptiveSyncStore {
    let context: LocalSyncStoreContext

    func fetchWeeklyTrainingAnalysisPayloads(since: Date?) throws -> [WeeklyTrainingAnalysisSyncDTO] {
        try context.measureSyncExport(named: "WeeklyTrainingAnalysis", since: since) {
            try context.fetchRows(weeklyTrainingAnalysisFetchDescriptor(since: since))
                .map { $0.toSyncDTO() }
        }
    }

    func upsertWeeklyTrainingAnalysisPayloads(_ payloads: [WeeklyTrainingAnalysisSyncDTO]) throws {
        guard !payloads.isEmpty else { return }

        var analyses = try context.stableIDMap(for: WeeklyTrainingAnalysis.self)
        let runs = try context.stableIDMap(for: ProgramRun.self)
        let programs = try context.stableIDMap(for: TrainingProgram.self)
        let workouts = try context.stableIDMap(for: Workout.self)
        let exerciseEntries = try context.stableIDMap(for: ExerciseEntry.self)

        for payload in payloads {
            if payload.metadata.deletedAt != nil {
                if let existing = analyses[payload.metadata.stableID] {
                    context.modelContext.delete(existing)
                    analyses[payload.metadata.stableID] = nil
                }
                continue
            }

            let programRun = payload.programRunStableID.flatMap { runs[$0] }
            let trainingProgram = payload.trainingProgramStableID.flatMap { programs[$0] }

            let analysis = analyses[payload.metadata.stableID] ?? {
                let created = WeeklyTrainingAnalysis(
                    id: UUID(uuidString: payload.metadata.stableID) ?? UUID(),
                    syncStableID: payload.metadata.stableID,
                    syncVersion: payload.metadata.version,
                    syncLastModifiedAt: payload.metadata.lastModifiedAt,
                    syncDeletedAt: payload.metadata.deletedAt,
                    createdAt: payload.createdAt,
                    weekStartDate: payload.weekStartDate,
                    weekEndDate: payload.weekEndDate,
                    programRun: programRun,
                    trainingProgram: trainingProgram,
                    programWeekNumber: payload.programWeekNumber,
                    focusSnapshot: payload.focusSnapshotRawValue.flatMap(ProgramFocus.init(rawValue:)),
                    programWorkoutCount: payload.programWorkoutCount,
                    standaloneWorkoutCount: payload.standaloneWorkoutCount,
                    totalOutcomeCount: payload.totalOutcomeCount,
                    totalSignalWeight: payload.totalSignalWeight,
                    programSignalWeight: payload.programSignalWeight,
                    standaloneSignalWeight: payload.standaloneSignalWeight,
                    weightedPerformanceScore: payload.weightedPerformanceScore,
                    adherenceScore: payload.adherenceScore,
                    plannedFatigueScore: payload.plannedFatigueScore,
                    observedFatigueScore: payload.observedFatigueScore,
                    fatigueStatus: FatigueStatus(rawValue: payload.fatigueStatusRawValue) ?? .manageable,
                    totalCompletedHardSets: payload.totalCompletedHardSets,
                    totalCompletedTonnage: payload.totalCompletedTonnage,
                    isFinalized: payload.isFinalized,
                    finalizedAt: payload.finalizedAt
                )
                context.modelContext.insert(created)
                analyses[payload.metadata.stableID] = created
                return created
            }()

            analysis.apply(
                syncDTO: payload,
                programRun: programRun,
                trainingProgram: trainingProgram
            )
            replaceOutcomeGraph(
                for: analysis,
                payloads: payload.outcomes,
                programRuns: runs,
                workouts: workouts,
                exerciseEntries: exerciseEntries
            )
            replaceVolumeMetrics(
                for: analysis,
                payloads: payload.volumeMetrics
            )
        }

        try context.save()
    }

    func fetchLiftPerformanceTrendPayloads(since: Date?) throws -> [LiftPerformanceTrendSyncDTO] {
        try context.measureSyncExport(named: "LiftPerformanceTrend", since: since) {
            try context.fetchRows(liftPerformanceTrendFetchDescriptor(since: since))
                .map { $0.toSyncDTO() }
        }
    }

    func upsertLiftPerformanceTrendPayloads(_ payloads: [LiftPerformanceTrendSyncDTO]) throws {
        guard !payloads.isEmpty else { return }

        var trends = try context.stableIDMap(for: LiftPerformanceTrend.self)
        let runs = try context.stableIDMap(for: ProgramRun.self)
        let programs = try context.stableIDMap(for: TrainingProgram.self)
        let analyses = try context.stableIDMap(for: WeeklyTrainingAnalysis.self)

        for payload in payloads {
            if payload.metadata.deletedAt != nil {
                if let existing = trends[payload.metadata.stableID] {
                    context.modelContext.delete(existing)
                    trends[payload.metadata.stableID] = nil
                }
                continue
            }

            let programRun = payload.programRunStableID.flatMap { runs[$0] }
            let trainingProgram = payload.trainingProgramStableID.flatMap { programs[$0] }

            let trend = trends[payload.metadata.stableID] ?? {
                let created = LiftPerformanceTrend(
                    id: UUID(uuidString: payload.metadata.stableID) ?? UUID(),
                    syncStableID: payload.metadata.stableID,
                    syncVersion: payload.metadata.version,
                    syncLastModifiedAt: payload.metadata.lastModifiedAt,
                    syncDeletedAt: payload.metadata.deletedAt,
                    updatedAt: payload.updatedAt,
                    programRun: programRun,
                    trainingProgram: trainingProgram,
                    canonicalLiftKey: payload.canonicalLiftKey,
                    liftDisplayName: payload.liftDisplayName,
                    totalDataPoints: payload.totalDataPoints,
                    programLinkedDataPoints: payload.programLinkedDataPoints,
                    standaloneDataPoints: payload.standaloneDataPoints,
                    weightedSignalCount: payload.weightedSignalCount,
                    confidenceScore: payload.confidenceScore,
                    firstObservationDate: payload.firstObservationDate,
                    lastObservationDate: payload.lastObservationDate,
                    currentEstimated1RM: payload.currentEstimated1RM,
                    previousEstimated1RM: payload.previousEstimated1RM,
                    rollingBestEstimated1RM: payload.rollingBestEstimated1RM,
                    fourWeekChangePercent: payload.fourWeekChangePercent,
                    trendStatus: LiftTrendStatus(rawValue: payload.trendStatusRawValue) ?? .insufficientData,
                    fatigueStatus: FatigueStatus(rawValue: payload.fatigueStatusRawValue) ?? .manageable,
                    latestTopSetWeight: payload.latestTopSetWeight,
                    latestTopSetReps: payload.latestTopSetReps,
                    latestPerformanceScoreValue: payload.latestPerformanceScoreValue,
                    lastPerformanceScore: payload.lastPerformanceScoreRawValue.flatMap(PerformanceScore.init(rawValue:))
                )
                context.modelContext.insert(created)
                trends[payload.metadata.stableID] = created
                return created
            }()

            trend.apply(
                syncDTO: payload,
                programRun: programRun,
                trainingProgram: trainingProgram
            )
            replaceTrendSnapshots(
                for: trend,
                payloads: payload.snapshots,
                analyses: analyses,
                programRun: programRun,
                trainingProgram: trainingProgram
            )
        }

        try context.save()
    }

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
            if payload.metadata.deletedAt != nil {
                if let existing = proposals[payload.metadata.stableID] {
                    context.modelContext.delete(existing)
                    proposals[payload.metadata.stableID] = nil
                }
                continue
            }

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
                    syncDeletedAt: payload.metadata.deletedAt,
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
            if payload.metadata.deletedAt != nil {
                if let existing = overlays[payload.metadata.stableID] {
                    context.modelContext.delete(existing)
                    overlays[payload.metadata.stableID] = nil
                }
                continue
            }

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
                    syncDeletedAt: payload.metadata.deletedAt,
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

    func fetchAdaptationEventPayloads(since: Date?) throws -> [AdaptationEventHistorySyncDTO] {
        try context.measureSyncExport(named: "AdaptationEventHistory", since: since) {
            try context.fetchRows(adaptationEventFetchDescriptor(since: since))
                .map { $0.toSyncDTO() }
        }
    }

    func upsertAdaptationEventPayloads(_ payloads: [AdaptationEventHistorySyncDTO]) throws {
        guard !payloads.isEmpty else { return }

        var events = try context.stableIDMap(for: AdaptationEventHistory.self)
        let runs = try context.stableIDMap(for: ProgramRun.self)
        let programs = try context.stableIDMap(for: TrainingProgram.self)
        let analyses = try context.stableIDMap(for: WeeklyTrainingAnalysis.self)
        let proposals = try context.stableIDMap(for: AdaptationProposal.self)
        let overlays = try context.stableIDMap(for: AppliedProgramOverlay.self)

        for payload in payloads {
            if payload.metadata.deletedAt != nil {
                if let existing = events[payload.metadata.stableID] {
                    context.modelContext.delete(existing)
                    events[payload.metadata.stableID] = nil
                }
                continue
            }

            let programRun = payload.programRunStableID.flatMap { runs[$0] }
            let trainingProgram = payload.trainingProgramStableID.flatMap { programs[$0] }
            let analysis = payload.analysisStableID.flatMap { analyses[$0] }
            let proposal = payload.proposalStableID.flatMap { proposals[$0] }
            let overlay = payload.overlayStableID.flatMap { overlays[$0] }

            if let existing = events[payload.metadata.stableID] {
                existing.apply(
                    syncDTO: payload,
                    programRun: programRun,
                    trainingProgram: trainingProgram,
                    analysis: analysis,
                    proposal: proposal,
                    overlay: overlay
                )
            } else {
                let event = AdaptationEventHistory(
                    id: UUID(uuidString: payload.metadata.stableID) ?? UUID(),
                    syncStableID: payload.metadata.stableID,
                    syncVersion: payload.metadata.version,
                    syncLastModifiedAt: payload.metadata.lastModifiedAt,
                    syncDeletedAt: payload.metadata.deletedAt,
                    timestamp: payload.timestamp,
                    programRun: programRun,
                    trainingProgram: trainingProgram,
                    analysis: analysis,
                    proposal: proposal,
                    overlay: overlay,
                    eventType: AdaptationEventType(rawValue: payload.eventTypeRawValue) ?? .proposalCreated,
                    analysisWeekNumber: payload.analysisWeekNumber,
                    targetLiftKey: payload.targetLiftKey,
                    message: payload.message,
                    explanation: payload.explanation,
                    adjustmentReason: payload.adjustmentReasonRawValue.flatMap(AdjustmentReason.init(rawValue:)),
                    performanceScoreSnapshot: payload.performanceScoreSnapshotRawValue.flatMap(PerformanceScore.init(rawValue:)),
                    fatigueStatusSnapshot: payload.fatigueStatusSnapshotRawValue.flatMap(FatigueStatus.init(rawValue:)),
                    liftTrendStatusSnapshot: payload.liftTrendStatusSnapshotRawValue.flatMap(LiftTrendStatus.init(rawValue:)),
                    confidenceSnapshot: payload.confidenceSnapshot,
                    requiresUserAction: payload.requiresUserAction,
                    userActionTaken: payload.userActionTaken
                )
                context.modelContext.insert(event)
                events[payload.metadata.stableID] = event
            }
        }

        try context.save()
    }

    private func replaceOutcomeGraph(
        for analysis: WeeklyTrainingAnalysis,
        payloads: [ExercisePerformanceOutcomeSyncDTO],
        programRuns: [String: ProgramRun],
        workouts: [String: Workout],
        exerciseEntries: [String: ExerciseEntry]
    ) {
        for outcome in analysis.outcomes {
            context.modelContext.delete(outcome)
        }
        analysis.outcomes.removeAll()

        for payload in payloads {
            let outcome = ExercisePerformanceOutcome.fromSyncDTO(
                payload,
                analysis: analysis,
                programRun: payload.programRunStableID.flatMap { programRuns[$0] } ?? analysis.programRun,
                workout: payload.workoutStableID.flatMap { workouts[$0] },
                exerciseEntry: payload.exerciseEntryStableID.flatMap { exerciseEntries[$0] }
            )
            context.modelContext.insert(outcome)
            analysis.outcomes.append(outcome)
        }
    }

    private func replaceVolumeMetrics(
        for analysis: WeeklyTrainingAnalysis,
        payloads: [WeeklyVolumeMetricSyncDTO]
    ) {
        for metric in analysis.volumeMetrics {
            context.modelContext.delete(metric)
        }
        analysis.volumeMetrics.removeAll()

        for payload in payloads {
            let metric = WeeklyVolumeMetric.fromSyncDTO(payload, analysis: analysis)
            context.modelContext.insert(metric)
            analysis.volumeMetrics.append(metric)
        }
    }

    private func replaceTrendSnapshots(
        for trend: LiftPerformanceTrend,
        payloads: [LiftTrendSnapshotSyncDTO],
        analyses: [String: WeeklyTrainingAnalysis],
        programRun: ProgramRun?,
        trainingProgram: TrainingProgram?
    ) {
        for snapshot in trend.snapshots {
            context.modelContext.delete(snapshot)
        }
        trend.snapshots.removeAll()

        for payload in payloads {
            let analysis = payload.analysisStableID.flatMap { analyses[$0] }
            let snapshot = LiftTrendSnapshot.fromSyncDTO(
                payload,
                trend: trend,
                analysis: analysis,
                programRun: programRun ?? analysis?.programRun,
                trainingProgram: trainingProgram ?? analysis?.trainingProgram
            )
            context.modelContext.insert(snapshot)
            trend.snapshots.append(snapshot)
        }
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

    private func weeklyTrainingAnalysisFetchDescriptor(since: Date?) -> FetchDescriptor<WeeklyTrainingAnalysis> {
        let sortBy = [SortDescriptor(\WeeklyTrainingAnalysis.weekStartDate, order: .reverse)]
        guard let sinceDate = since else {
            return FetchDescriptor<WeeklyTrainingAnalysis>(
                predicate: #Predicate<WeeklyTrainingAnalysis> { analysis in
                    analysis.syncDeletedAt == nil
                },
                sortBy: sortBy
            )
        }
        return FetchDescriptor<WeeklyTrainingAnalysis>(
            predicate: #Predicate<WeeklyTrainingAnalysis> { analysis in
                analysis.syncLastModifiedAt >= sinceDate
            },
            sortBy: sortBy
        )
    }

    private func liftPerformanceTrendFetchDescriptor(since: Date?) -> FetchDescriptor<LiftPerformanceTrend> {
        let sortBy = [SortDescriptor(\LiftPerformanceTrend.updatedAt, order: .reverse)]
        guard let sinceDate = since else {
            return FetchDescriptor<LiftPerformanceTrend>(
                predicate: #Predicate<LiftPerformanceTrend> { trend in
                    trend.syncDeletedAt == nil
                },
                sortBy: sortBy
            )
        }
        return FetchDescriptor<LiftPerformanceTrend>(
            predicate: #Predicate<LiftPerformanceTrend> { trend in
                trend.syncLastModifiedAt >= sinceDate
            },
            sortBy: sortBy
        )
    }

    private func adaptationProposalFetchDescriptor(since: Date?) -> FetchDescriptor<AdaptationProposal> {
        let sortBy = [SortDescriptor(\AdaptationProposal.createdAt, order: .reverse)]
        guard let sinceDate = since else {
            return FetchDescriptor<AdaptationProposal>(
                predicate: #Predicate<AdaptationProposal> { proposal in
                    proposal.syncDeletedAt == nil
                },
                sortBy: sortBy
            )
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
            return FetchDescriptor<AppliedProgramOverlay>(
                predicate: #Predicate<AppliedProgramOverlay> { overlay in
                    overlay.syncDeletedAt == nil
                },
                sortBy: sortBy
            )
        }
        return FetchDescriptor<AppliedProgramOverlay>(
            predicate: #Predicate<AppliedProgramOverlay> { overlay in
                overlay.syncLastModifiedAt >= sinceDate
            },
            sortBy: sortBy
        )
    }

    private func adaptationEventFetchDescriptor(since: Date?) -> FetchDescriptor<AdaptationEventHistory> {
        let sortBy = [SortDescriptor(\AdaptationEventHistory.timestamp, order: .reverse)]
        guard let sinceDate = since else {
            return FetchDescriptor<AdaptationEventHistory>(
                predicate: #Predicate<AdaptationEventHistory> { event in
                    event.syncDeletedAt == nil
                },
                sortBy: sortBy
            )
        }
        return FetchDescriptor<AdaptationEventHistory>(
            predicate: #Predicate<AdaptationEventHistory> { event in
                event.syncLastModifiedAt >= sinceDate
            },
            sortBy: sortBy
        )
    }
}
