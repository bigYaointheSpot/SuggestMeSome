import Foundation
import SwiftData

@MainActor
final class LocalSyncRepository: WorkoutSyncRepository, ProgramSyncRepository, DailyCoachSyncRepository, AdaptiveSyncRepository, HealthKitSummarySyncRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchWorkoutPayloads(since: Date?, includeDeleted: Bool = false) throws -> [WorkoutSyncDTO] {
        let workouts = try modelContext.fetch(FetchDescriptor<Workout>())
            .filter { includeDeleted || $0.syncDeletedAt == nil }
        return filteredBySince(workouts, since: since)
            .sorted { $0.date > $1.date }
            .map { $0.toSyncDTO() }
    }

    func upsertWorkoutPayloads(_ payloads: [WorkoutSyncDTO]) throws {
        guard !payloads.isEmpty else { return }

        var existingWorkouts = try dictionaryByStableID(modelContext.fetch(FetchDescriptor<Workout>()))
        let programRuns = try dictionaryByStableID(modelContext.fetch(FetchDescriptor<ProgramRun>()))

        for payload in payloads {
            let programRun = payload.programRunStableID.flatMap { programRuns[$0] }
            if let existing = existingWorkouts[payload.metadata.stableID] {
                existing.apply(syncDTO: payload, programRun: programRun)
                try upsertExerciseEntries(payload.exerciseEntries, into: existing)
            } else {
                let workout = Workout.fromSyncDTO(payload, programRun: programRun)
                modelContext.insert(workout)
                for entry in workout.exerciseEntries {
                    entry.workout = workout
                    modelContext.insert(entry)
                    for set in entry.sets {
                        set.exerciseEntry = entry
                        modelContext.insert(set)
                    }
                }
                existingWorkouts[payload.metadata.stableID] = workout
            }
        }

        try modelContext.save()
    }

    func markWorkoutDeleted(stableID: String, deletedAt: Date = Date()) throws {
        let workouts = try modelContext.fetch(FetchDescriptor<Workout>())
        guard let workout = workouts.first(where: { $0.resolvedSyncStableID == stableID }) else { return }
        workout.markSyncDeleted(at: deletedAt)
        try modelContext.save()
    }

    func fetchTrainingProgramPayloads(since: Date?) throws -> [TrainingProgramSyncDTO] {
        let programs = try modelContext.fetch(FetchDescriptor<TrainingProgram>())
        return filteredBySince(programs, since: since)
            .sorted { $0.createdDate > $1.createdDate }
            .map { $0.toSyncDTO() }
    }

    func upsertTrainingProgramPayloads(_ payloads: [TrainingProgramSyncDTO]) throws {
        guard !payloads.isEmpty else { return }
        var existing = try dictionaryByStableID(modelContext.fetch(FetchDescriptor<TrainingProgram>()))

        for payload in payloads {
            if let model = existing[payload.metadata.stableID] {
                model.apply(syncDTO: payload)
            } else {
                let model = TrainingProgram(
                    id: UUID(uuidString: payload.metadata.stableID) ?? UUID(),
                    syncStableID: payload.metadata.stableID,
                    syncVersion: payload.metadata.version,
                    syncLastModifiedAt: payload.metadata.lastModifiedAt,
                    name: payload.name,
                    lengthInWeeks: payload.lengthInWeeks,
                    sessionsPerWeek: payload.sessionsPerWeek,
                    createdDate: payload.createdDate,
                    source: ProgramSource(rawValue: payload.sourceRawValue) ?? .userCreated,
                    descriptionText: payload.descriptionText,
                    progressionModel: payload.progressionModelRawValue.flatMap(ProgramProgressionModel.init(rawValue:)),
                    usedLiftMapping: payload.usedLiftMapping,
                    usedVolumeBalancing: payload.usedVolumeBalancing,
                    usedFatigueBalancing: payload.usedFatigueBalancing,
                    usedTopSetBackoff: payload.usedTopSetBackoff
                )
                modelContext.insert(model)
                existing[payload.metadata.stableID] = model
            }
        }

        try modelContext.save()
    }

    func fetchProgramRunPayloads(since: Date?) throws -> [ProgramRunSyncDTO] {
        let runs = try modelContext.fetch(FetchDescriptor<ProgramRun>())
        return filteredBySince(runs, since: since)
            .sorted { $0.startDate > $1.startDate }
            .map { $0.toSyncDTO() }
    }

    func upsertProgramRunPayloads(_ payloads: [ProgramRunSyncDTO]) throws {
        guard !payloads.isEmpty else { return }
        var runs = try dictionaryByStableID(modelContext.fetch(FetchDescriptor<ProgramRun>()))
        let programs = try dictionaryByStableID(modelContext.fetch(FetchDescriptor<TrainingProgram>()))

        for payload in payloads {
            let program = payload.trainingProgramStableID.flatMap { programs[$0] }
            if let existing = runs[payload.metadata.stableID] {
                existing.apply(syncDTO: payload, program: program)
            } else {
                let run = ProgramRun(
                    id: UUID(uuidString: payload.metadata.stableID) ?? UUID(),
                    syncStableID: payload.metadata.stableID,
                    syncVersion: payload.metadata.version,
                    syncLastModifiedAt: payload.metadata.lastModifiedAt,
                    startDate: payload.startDate,
                    endDate: payload.endDate,
                    isCompleted: payload.isCompleted,
                    previousProgramRunStableID: payload.previousProgramRunStableID,
                    recommendationDecisionHistoryJSON: payload.recommendationDecisionHistoryJSON,
                    continuitySnapshotJSON: payload.continuitySnapshotJSON
                )
                run.program = program
                modelContext.insert(run)
                runs[payload.metadata.stableID] = run
            }
        }

        try modelContext.save()
    }

    func fetchDailyCheckInPayloads(since: Date?) throws -> [DailyCoachCheckInSyncDTO] {
        let rows = try modelContext.fetch(FetchDescriptor<DailyCoachCheckIn>())
        return filteredBySince(rows, since: since)
            .sorted { $0.date > $1.date }
            .map { $0.toSyncDTO() }
    }

    func upsertDailyCheckInPayloads(_ payloads: [DailyCoachCheckInSyncDTO]) throws {
        guard !payloads.isEmpty else { return }
        var checkIns = try dictionaryByStableID(modelContext.fetch(FetchDescriptor<DailyCoachCheckIn>()))
        let runs = try dictionaryByStableID(modelContext.fetch(FetchDescriptor<ProgramRun>()))

        for payload in payloads {
            let run = payload.programRunStableID.flatMap { runs[$0] }
            if let existing = checkIns[payload.metadata.stableID] {
                existing.apply(syncDTO: payload, programRun: run)
            } else {
                let checkIn = DailyCoachCheckIn(
                    id: UUID(uuidString: payload.metadata.stableID) ?? UUID(),
                    syncStableID: payload.metadata.stableID,
                    syncVersion: payload.metadata.version,
                    syncLastModifiedAt: payload.metadata.lastModifiedAt,
                    date: payload.date,
                    dayStart: payload.dayStart,
                    sleepQuality: payload.sleepQuality,
                    soreness: payload.soreness,
                    energy: payload.energy,
                    stress: payload.stress,
                    availableTimeMinutes: payload.availableTimeMinutes,
                    hasPainOrDiscomfort: payload.hasPainOrDiscomfort,
                    painNotes: payload.painNotes,
                    programRun: run,
                    createdAt: payload.createdAt,
                    updatedAt: payload.updatedAt
                )
                modelContext.insert(checkIn)
                checkIns[payload.metadata.stableID] = checkIn
            }
        }

        try modelContext.save()
    }

    func fetchWeeklyReviewPayloads(since: Date?) throws -> [DailyCoachWeeklyReviewSyncDTO] {
        let rows = try modelContext.fetch(FetchDescriptor<DailyCoachWeeklyReview>())
        return filteredBySince(rows, since: since)
            .sorted { $0.weekStart > $1.weekStart }
            .map { $0.toSyncDTO() }
    }

    func upsertWeeklyReviewPayloads(_ payloads: [DailyCoachWeeklyReviewSyncDTO]) throws {
        guard !payloads.isEmpty else { return }
        var reviews = try dictionaryByStableID(modelContext.fetch(FetchDescriptor<DailyCoachWeeklyReview>()))
        let runs = try dictionaryByStableID(modelContext.fetch(FetchDescriptor<ProgramRun>()))

        for payload in payloads {
            let run = payload.programRunStableID.flatMap { runs[$0] }
            if let existing = reviews[payload.metadata.stableID] {
                existing.syncStableID = payload.metadata.stableID
                existing.syncVersion = payload.metadata.version
                existing.syncLastModifiedAt = payload.metadata.lastModifiedAt
                existing.weekStart = payload.weekStart
                existing.weekEnd = payload.weekEnd
                existing.isProgramWeek = payload.isProgramWeek
                existing.programRun = run
                existing.headline = payload.headline
                existing.winText = payload.winText
                existing.watchoutText = payload.watchoutText
                existing.nextActionText = payload.nextActionText
                existing.sourceWeeklyAnalysisIDText = payload.sourceWeeklyAnalysisIDText
                existing.hasBeenSeen = payload.hasBeenSeen
                existing.createdAt = payload.createdAt
            } else {
                let review = DailyCoachWeeklyReview(
                    id: UUID(uuidString: payload.metadata.stableID) ?? UUID(),
                    syncStableID: payload.metadata.stableID,
                    syncVersion: payload.metadata.version,
                    syncLastModifiedAt: payload.metadata.lastModifiedAt,
                    weekStart: payload.weekStart,
                    weekEnd: payload.weekEnd,
                    isProgramWeek: payload.isProgramWeek,
                    programRun: run,
                    headline: payload.headline,
                    winText: payload.winText,
                    watchoutText: payload.watchoutText,
                    nextActionText: payload.nextActionText,
                    sourceWeeklyAnalysisIDText: payload.sourceWeeklyAnalysisIDText,
                    hasBeenSeen: payload.hasBeenSeen,
                    createdAt: payload.createdAt
                )
                modelContext.insert(review)
                reviews[payload.metadata.stableID] = review
            }
        }

        try modelContext.save()
    }

    func fetchAdaptationProposalPayloads(since: Date?) throws -> [AdaptationProposalSyncDTO] {
        let rows = try modelContext.fetch(FetchDescriptor<AdaptationProposal>())
        return filteredBySince(rows, since: since)
            .sorted { $0.createdAt > $1.createdAt }
            .map { $0.toSyncDTO() }
    }

    func upsertAdaptationProposalPayloads(_ payloads: [AdaptationProposalSyncDTO]) throws {
        guard !payloads.isEmpty else { return }
        var proposals = try dictionaryByStableID(modelContext.fetch(FetchDescriptor<AdaptationProposal>()))
        let runs = try dictionaryByStableID(modelContext.fetch(FetchDescriptor<ProgramRun>()))
        let programs = try dictionaryByStableID(modelContext.fetch(FetchDescriptor<TrainingProgram>()))
        let analysesByID = try modelContext.fetch(FetchDescriptor<WeeklyTrainingAnalysis>()).reduce(into: [String: WeeklyTrainingAnalysis]()) { map, row in
            map[row.id.uuidString] = row
        }

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
                modelContext.insert(proposal)
                proposals[payload.metadata.stableID] = proposal
            }
        }

        try modelContext.save()
    }

    func fetchAppliedOverlayPayloads(since: Date?) throws -> [AppliedProgramOverlaySyncDTO] {
        let rows = try modelContext.fetch(FetchDescriptor<AppliedProgramOverlay>())
        return filteredBySince(rows, since: since)
            .sorted { $0.appliedAt > $1.appliedAt }
            .map { $0.toSyncDTO() }
    }

    func upsertAppliedOverlayPayloads(_ payloads: [AppliedProgramOverlaySyncDTO]) throws {
        guard !payloads.isEmpty else { return }
        var overlays = try dictionaryByStableID(modelContext.fetch(FetchDescriptor<AppliedProgramOverlay>()))
        let runs = try dictionaryByStableID(modelContext.fetch(FetchDescriptor<ProgramRun>()))
        let programs = try dictionaryByStableID(modelContext.fetch(FetchDescriptor<TrainingProgram>()))
        let proposals = try dictionaryByStableID(modelContext.fetch(FetchDescriptor<AdaptationProposal>()))

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
                modelContext.insert(overlay)
                for adjustmentPayload in payload.adjustments {
                    let adjustment = AppliedOverlayAdjustment.fromSyncDTO(adjustmentPayload)
                    adjustment.overlay = overlay
                    modelContext.insert(adjustment)
                }
                overlays[payload.metadata.stableID] = overlay
            }
        }

        try modelContext.save()
    }

    func fetchHealthKitSummaryPayloads(since: Date?) throws -> [HealthKitDailySummarySyncDTO] {
        let rows = try modelContext.fetch(FetchDescriptor<HealthKitDailySummary>())
        return filteredBySince(rows, since: since)
            .sorted { $0.dayStart > $1.dayStart }
            .map { $0.toSyncDTO() }
    }

    func upsertHealthKitSummaryPayloads(_ payloads: [HealthKitDailySummarySyncDTO]) throws {
        guard !payloads.isEmpty else { return }
        var summaries = try dictionaryByStableID(modelContext.fetch(FetchDescriptor<HealthKitDailySummary>()))

        for payload in payloads {
            if let existing = summaries[payload.metadata.stableID] {
                existing.apply(syncDTO: payload)
            } else {
                let row = HealthKitDailySummary(
                    id: UUID(uuidString: payload.metadata.stableID) ?? UUID(),
                    syncStableID: payload.metadata.stableID,
                    syncVersion: payload.metadata.version,
                    syncLastModifiedAt: payload.metadata.lastModifiedAt,
                    dayStart: payload.dayStart,
                    sleepDurationSeconds: payload.sleepDurationSeconds,
                    timeInBedSeconds: payload.timeInBedSeconds,
                    restingHeartRateBPM: payload.restingHeartRateBPM,
                    heartRateVariabilityMS: payload.heartRateVariabilityMS,
                    activeEnergyKilocalories: payload.activeEnergyKilocalories,
                    stepCount: payload.stepCount,
                    bodyMassKilograms: payload.bodyMassKilograms,
                    sourceUpdatedAt: payload.sourceUpdatedAt,
                    createdAt: payload.createdAt,
                    updatedAt: payload.updatedAt
                )
                modelContext.insert(row)
                summaries[payload.metadata.stableID] = row
            }
        }

        try modelContext.save()
    }

    private func upsertExerciseEntries(_ payloads: [ExerciseEntrySyncDTO], into workout: Workout) throws {
        var existingByID: [String: ExerciseEntry] = [:]
        for entry in workout.exerciseEntries {
            entry.initializeSyncMetadataIfNeeded()
            existingByID[entry.resolvedSyncStableID] = entry
        }

        var incomingIDs: Set<String> = []
        for payload in payloads {
            incomingIDs.insert(payload.metadata.stableID)
            if let existing = existingByID[payload.metadata.stableID] {
                existing.apply(syncDTO: payload)
                existing.workout = workout
                try upsertSets(payload.sets, into: existing)
            } else {
                let entry = ExerciseEntry.fromSyncDTO(payload)
                entry.workout = workout
                modelContext.insert(entry)
                for set in entry.sets {
                    set.exerciseEntry = entry
                    modelContext.insert(set)
                }
            }
        }

        for stale in workout.exerciseEntries where !incomingIDs.contains(stale.resolvedSyncStableID) {
            modelContext.delete(stale)
        }
    }

    private func upsertSets(_ payloads: [SetEntrySyncDTO], into entry: ExerciseEntry) throws {
        var existingByID: [String: SetEntry] = [:]
        for set in entry.sets {
            set.initializeSyncMetadataIfNeeded()
            existingByID[set.resolvedSyncStableID] = set
        }

        var incomingIDs: Set<String> = []
        for payload in payloads {
            incomingIDs.insert(payload.metadata.stableID)
            if let existing = existingByID[payload.metadata.stableID] {
                existing.apply(syncDTO: payload)
                existing.exerciseEntry = entry
            } else {
                let set = SetEntry.fromSyncDTO(payload)
                set.exerciseEntry = entry
                modelContext.insert(set)
            }
        }

        for stale in entry.sets where !incomingIDs.contains(stale.resolvedSyncStableID) {
            modelContext.delete(stale)
        }
    }

    private func upsertOverlayAdjustments(_ payloads: [AppliedOverlayAdjustmentSyncDTO], into overlay: AppliedProgramOverlay) throws {
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
                modelContext.insert(adjustment)
            }
        }

        for stale in overlay.adjustments where !incomingIDs.contains(stale.resolvedSyncStableID) {
            modelContext.delete(stale)
        }
    }

    private func dictionaryByStableID<T: SyncTrackableModel>(_ rows: [T]) throws -> [String: T] {
        var map: [String: T] = [:]
        for row in rows {
            row.initializeSyncMetadataIfNeeded()
            map[row.resolvedSyncStableID] = row
        }
        return map
    }

    private func filteredBySince<T: SyncTrackableModel>(_ rows: [T], since: Date?) -> [T] {
        guard let since else { return rows }
        return rows.filter { $0.syncLastModifiedAt >= since }
    }
}
