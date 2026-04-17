import Foundation
import SwiftData
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature10SyncFoundationValidationTests {

    @Test func workoutDTOMappingRoundTripPreservesNestedStructure() {
        let workoutID = UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!
        let entryID = UUID(uuidString: "A0000000-0000-0000-0000-000000000002")!
        let setID = UUID(uuidString: "A0000000-0000-0000-0000-000000000003")!

        let set = SetEntry(
            id: setID,
            syncStableID: "set-sync-1",
            syncVersion: 3,
            syncLastModifiedAt: day(3),
            setNumber: 1,
            reps: 5,
            weight: 225,
            isPR: true
        )

        let entry = ExerciseEntry(
            id: entryID,
            syncStableID: "entry-sync-1",
            syncVersion: 2,
            syncLastModifiedAt: day(2),
            exerciseName: "Bench Press",
            unit: .lbs,
            orderIndex: 0
        )
        entry.sets = [set]

        let workout = Workout(
            id: workoutID,
            syncStableID: "workout-sync-1",
            syncVersion: 4,
            syncLastModifiedAt: day(4),
            date: day(4),
            startTime: day(4),
            durationSeconds: 1800,
            comments: "Strong day"
        )
        workout.exerciseEntries = [entry]

        let dto = workout.toSyncDTO()
        let roundTrip = Workout.fromSyncDTO(dto)

        #expect(dto.metadata.stableID == "workout-sync-1")
        #expect(dto.exerciseEntries.count == 1)
        #expect(dto.exerciseEntries[0].sets.count == 1)

        #expect(roundTrip.syncStableID == "workout-sync-1")
        #expect(roundTrip.exerciseEntries.count == 1)
        #expect(roundTrip.exerciseEntries[0].syncStableID == "entry-sync-1")
        #expect(roundTrip.exerciseEntries[0].sets[0].syncStableID == "set-sync-1")
    }

    @Test func syncStableIDFallsBackToModelIDWhenMissing() {
        let id = UUID(uuidString: "B0000000-0000-0000-0000-000000000001")!
        let workout = Workout(
            id: id,
            syncStableID: nil,
            syncVersion: 0,
            syncLastModifiedAt: .distantPast,
            date: day(0),
            startTime: day(0),
            durationSeconds: 1200
        )

        #expect(workout.resolvedSyncStableID == id.uuidString)
        workout.initializeSyncMetadataIfNeeded(at: day(1))
        #expect(workout.syncStableID == id.uuidString)
        #expect(workout.syncVersion == 1)
        #expect(workout.syncLastModifiedAt == day(1))
    }

    @Test func conflictPolicyWorkoutMergeIsDeterministic() {
        let policy = SyncConflictResolutionPolicy()

        let local = makeWorkoutDTO(
            stableID: "workout-1",
            lastModifiedAt: day(1),
            version: 2,
            comments: "Local comment",
            entryStableIDs: ["entry-a"]
        )

        let remote = makeWorkoutDTO(
            stableID: "workout-1",
            lastModifiedAt: day(2),
            version: 2,
            comments: "Remote comment",
            entryStableIDs: ["entry-b"]
        )

        let merged = policy.mergeWorkouts(local: local, remote: remote)

        #expect(merged.comments == "Remote comment")
        #expect(merged.exerciseEntries.count == 2)
        #expect(Set(merged.exerciseEntries.map { $0.metadata.stableID }) == Set(["entry-a", "entry-b"]))
    }

    @Test func conflictPolicyCheckInAndProposalResolutionFollowsRules() {
        let policy = SyncConflictResolutionPolicy()

        let localCheckIn = DailyCoachCheckInSyncDTO(
            metadata: SyncRecordMetadataDTO(stableID: "checkin-1", version: 1, lastModifiedAt: day(1)),
            date: day(1),
            dayStart: day(1),
            sleepQuality: 2,
            soreness: 3,
            energy: 2,
            stress: 4,
            availableTimeMinutes: 45,
            hasPainOrDiscomfort: false,
            painNotes: nil,
            programRunStableID: nil,
            createdAt: day(1),
            updatedAt: day(1)
        )

        let remoteCheckIn = DailyCoachCheckInSyncDTO(
            metadata: SyncRecordMetadataDTO(stableID: "checkin-1", version: 1, lastModifiedAt: day(2)),
            date: day(1),
            dayStart: day(1),
            sleepQuality: 5,
            soreness: 1,
            energy: 5,
            stress: 1,
            availableTimeMinutes: 60,
            hasPainOrDiscomfort: false,
            painNotes: nil,
            programRunStableID: nil,
            createdAt: day(1),
            updatedAt: day(2)
        )

        let mergedCheckIn = policy.mergeDailyCheckInSameDay(local: localCheckIn, remote: remoteCheckIn)
        #expect(mergedCheckIn.sleepQuality == 5)

        let localProposal = AdaptationProposalSyncDTO(
            metadata: SyncRecordMetadataDTO(stableID: "proposal-1", version: 4, lastModifiedAt: day(3)),
            createdAt: day(1),
            decidedAt: day(3),
            programRunStableID: nil,
            trainingProgramStableID: nil,
            sourceAnalysisStableID: nil,
            proposalTypeRawValue: ProposalType.deload.rawValue,
            proposalStatusRawValue: ProposalStatus.confirmed.rawValue,
            requiresUserConfirmation: true,
            autoApplyEligible: false,
            confidenceScore: 0.8,
            priority: 10,
            targetWeekStart: 3,
            targetWeekEnd: nil,
            targetSessionNumber: nil,
            targetProgramSessionExerciseStableID: nil,
            targetLiftKey: nil,
            proposedLoadPercentDelta: nil,
            proposedSetDelta: nil,
            proposedRepDelta: nil,
            proposedDeloadFactor: 0.9,
            swapFromExerciseName: nil,
            swapToExerciseName: nil,
            adjustmentReasonRawValue: AdjustmentReason.fatigueAccumulation.rawValue,
            summaryText: "Local",
            detailText: nil,
            expiresAt: nil
        )

        let remoteProposal = AdaptationProposalSyncDTO(
            metadata: SyncRecordMetadataDTO(stableID: "proposal-1", version: 5, lastModifiedAt: day(4)),
            createdAt: day(1),
            decidedAt: day(3),
            programRunStableID: nil,
            trainingProgramStableID: nil,
            sourceAnalysisStableID: nil,
            proposalTypeRawValue: ProposalType.deload.rawValue,
            proposalStatusRawValue: ProposalStatus.rejected.rawValue,
            requiresUserConfirmation: true,
            autoApplyEligible: false,
            confidenceScore: 0.8,
            priority: 10,
            targetWeekStart: 3,
            targetWeekEnd: nil,
            targetSessionNumber: nil,
            targetProgramSessionExerciseStableID: nil,
            targetLiftKey: nil,
            proposedLoadPercentDelta: nil,
            proposedSetDelta: nil,
            proposedRepDelta: nil,
            proposedDeloadFactor: 0.9,
            swapFromExerciseName: nil,
            swapToExerciseName: nil,
            adjustmentReasonRawValue: AdjustmentReason.fatigueAccumulation.rawValue,
            summaryText: "Remote",
            detailText: nil,
            expiresAt: nil
        )

        let mergedProposal = policy.mergeAdaptationProposal(local: localProposal, remote: remoteProposal)
        #expect(mergedProposal.proposalStatusRawValue == ProposalStatus.rejected.rawValue)
    }

    @Test func conflictPolicyOverlayAndProgramRunRulesAreDeterministic() {
        let policy = SyncConflictResolutionPolicy()

        let activeOld = AppliedProgramOverlaySyncDTO(
            metadata: SyncRecordMetadataDTO(stableID: "overlay-1", version: 1, lastModifiedAt: day(1)),
            createdAt: day(1),
            appliedAt: day(1),
            programRunStableID: "run-1",
            trainingProgramStableID: nil,
            sourceProposalStableID: nil,
            effectiveWeekStart: 2,
            effectiveWeekEnd: 2,
            overlayStatusRawValue: OverlayStatus.active.rawValue,
            appliedByUserConfirmation: true,
            adjustmentReasonRawValue: AdjustmentReason.fatigueAccumulation.rawValue,
            summaryText: nil,
            adjustments: []
        )
        let activeNew = AppliedProgramOverlaySyncDTO(
            metadata: SyncRecordMetadataDTO(stableID: "overlay-2", version: 1, lastModifiedAt: day(2)),
            createdAt: day(2),
            appliedAt: day(2),
            programRunStableID: "run-1",
            trainingProgramStableID: nil,
            sourceProposalStableID: nil,
            effectiveWeekStart: 2,
            effectiveWeekEnd: 2,
            overlayStatusRawValue: OverlayStatus.active.rawValue,
            appliedByUserConfirmation: true,
            adjustmentReasonRawValue: AdjustmentReason.fatigueAccumulation.rawValue,
            summaryText: nil,
            adjustments: []
        )

        let resolvedOverlays = policy.resolveOverlayActivationConflicts(local: [activeOld], remote: [activeNew])
        let oldResolved = resolvedOverlays.first { $0.metadata.stableID == "overlay-1" }
        let newResolved = resolvedOverlays.first { $0.metadata.stableID == "overlay-2" }
        #expect(oldResolved?.overlayStatusRawValue == OverlayStatus.superseded.rawValue)
        #expect(newResolved?.overlayStatusRawValue == OverlayStatus.active.rawValue)

        let localRun = ProgramRunSyncDTO(
            metadata: SyncRecordMetadataDTO(stableID: "run-1", version: 2, lastModifiedAt: day(1)),
            startDate: day(0),
            endDate: nil,
            isCompleted: false,
            trainingProgramStableID: "program-1"
        )
        let remoteRun = ProgramRunSyncDTO(
            metadata: SyncRecordMetadataDTO(stableID: "run-1", version: 3, lastModifiedAt: day(2)),
            startDate: day(1),
            endDate: day(5),
            isCompleted: true,
            trainingProgramStableID: "program-1"
        )

        let mergedRun = policy.mergeProgramRunProgress(local: localRun, remote: remoteRun)
        #expect(mergedRun.startDate == day(0))
        #expect(mergedRun.endDate == day(5))
        #expect(mergedRun.isCompleted)
    }

    @Test func localSyncRepositoryUpsertsAndTombstonesWorkout() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let repository = LocalSyncRepository(modelContext: context)

        let first = makeWorkoutDTO(
            stableID: "workout-repo-1",
            lastModifiedAt: day(1),
            version: 1,
            comments: "First",
            entryStableIDs: ["entry-repo-1"]
        )
        try repository.upsertWorkoutPayloads([first])

        var fetched = try repository.fetchWorkoutPayloads(since: nil, includeDeleted: false)
        #expect(fetched.count == 1)
        #expect(fetched[0].comments == "First")
        #expect(fetched[0].exerciseEntries.count == 1)

        var updated = first
        updated.metadata.version = 2
        updated.metadata.lastModifiedAt = day(2)
        updated.comments = "Updated"
        updated.exerciseEntries = []
        try repository.upsertWorkoutPayloads([updated])

        fetched = try repository.fetchWorkoutPayloads(since: nil, includeDeleted: false)
        #expect(fetched.count == 1)
        #expect(fetched[0].comments == "Updated")
        #expect(fetched[0].exerciseEntries.isEmpty)

        try repository.markWorkoutDeleted(stableID: "workout-repo-1", deletedAt: day(3))

        let visible = try repository.fetchWorkoutPayloads(since: nil, includeDeleted: false)
        let includingDeleted = try repository.fetchWorkoutPayloads(since: nil, includeDeleted: true)
        #expect(visible.isEmpty)
        #expect(includingDeleted.count == 1)
        #expect(includingDeleted[0].metadata.deletedAt == day(3))
    }

    @Test func localSyncRepositoryUpsertsProgramAndAdaptiveGraphs() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let repository = LocalSyncRepository(modelContext: context)

        let programDTO = TrainingProgramSyncDTO(
            metadata: SyncRecordMetadataDTO(
                stableID: "program-sync-1",
                version: 1,
                lastModifiedAt: day(1)
            ),
            name: "Powerlifting Base",
            lengthInWeeks: 8,
            sessionsPerWeek: 4,
            createdDate: day(0),
            sourceRawValue: ProgramSource.userCreated.rawValue,
            descriptionText: "Base block",
            progressionModelRawValue: ProgramProgressionModel.linear.rawValue,
            usedLiftMapping: true,
            usedVolumeBalancing: true,
            usedFatigueBalancing: true,
            usedTopSetBackoff: true,
            prescriptions: []
        )
        try repository.upsertTrainingProgramPayloads([programDTO])

        let runDTO = ProgramRunSyncDTO(
            metadata: SyncRecordMetadataDTO(
                stableID: "run-sync-1",
                version: 1,
                lastModifiedAt: day(2)
            ),
            startDate: day(1),
            endDate: nil,
            isCompleted: false,
            trainingProgramStableID: "program-sync-1",
            previousProgramRunStableID: "run-sync-0",
            recommendationDecisionHistoryJSON: "{\"accepted\":[]}",
            continuitySnapshotJSON: "{\"version\":1}"
        )
        try repository.upsertProgramRunPayloads([runDTO])

        let programs = try fetchAll(TrainingProgram.self, context)
        let runs = try fetchAll(ProgramRun.self, context)
        #expect(programs.count == 1)
        #expect(runs.count == 1)
        #expect(runs[0].program?.id == programs[0].id)
        #expect(runs[0].previousProgramRunStableID == "run-sync-0")
        #expect(runs[0].continuitySnapshotJSON == "{\"version\":1}")

        let analysis = WeeklyTrainingAnalysis(
            id: UUID(uuidString: "C0000000-0000-0000-0000-000000000001")!,
            weekStartDate: day(0),
            weekEndDate: day(6),
            programRun: runs[0],
            trainingProgram: programs[0],
            programWeekNumber: 1,
            isFinalized: true,
            finalizedAt: day(7)
        )
        context.insert(analysis)
        try context.save()

        let proposalDTO = AdaptationProposalSyncDTO(
            metadata: SyncRecordMetadataDTO(
                stableID: "proposal-sync-1",
                version: 1,
                lastModifiedAt: day(3)
            ),
            createdAt: day(3),
            decidedAt: nil,
            programRunStableID: "run-sync-1",
            trainingProgramStableID: "program-sync-1",
            sourceAnalysisStableID: analysis.id.uuidString,
            proposalTypeRawValue: ProposalType.increaseLoad.rawValue,
            proposalStatusRawValue: ProposalStatus.pendingUserConfirmation.rawValue,
            requiresUserConfirmation: true,
            autoApplyEligible: false,
            confidenceScore: 0.8,
            priority: 10,
            targetWeekStart: 2,
            targetWeekEnd: nil,
            targetSessionNumber: 1,
            targetProgramSessionExerciseStableID: UUID().uuidString,
            targetLiftKey: "squat",
            proposedLoadPercentDelta: 2.5,
            proposedSetDelta: nil,
            proposedRepDelta: nil,
            proposedDeloadFactor: nil,
            swapFromExerciseName: nil,
            swapToExerciseName: nil,
            adjustmentReasonRawValue: AdjustmentReason.topSetBeatTarget.rawValue,
            summaryText: "Increase squat load",
            detailText: "Strong performance",
            expiresAt: day(10)
        )
        try repository.upsertAdaptationProposalPayloads([proposalDTO])

        let overlayDTO = AppliedProgramOverlaySyncDTO(
            metadata: SyncRecordMetadataDTO(
                stableID: "overlay-sync-1",
                version: 1,
                lastModifiedAt: day(4)
            ),
            createdAt: day(4),
            appliedAt: day(4),
            programRunStableID: "run-sync-1",
            trainingProgramStableID: "program-sync-1",
            sourceProposalStableID: "proposal-sync-1",
            effectiveWeekStart: 2,
            effectiveWeekEnd: 2,
            overlayStatusRawValue: OverlayStatus.active.rawValue,
            appliedByUserConfirmation: true,
            adjustmentReasonRawValue: AdjustmentReason.topSetBeatTarget.rawValue,
            summaryText: "Applied progression",
            adjustments: [
                AppliedOverlayAdjustmentSyncDTO(
                    metadata: SyncRecordMetadataDTO(
                        stableID: "adjustment-sync-1",
                        version: 1,
                        lastModifiedAt: day(4)
                    ),
                    sequence: 0,
                    targetProgramSessionExerciseStableID: UUID().uuidString,
                    targetWeekNumber: 2,
                    targetSessionNumber: 1,
                    adjustmentTypeRawValue: OverlayAdjustmentType.load.rawValue,
                    loadPercentDelta: 2.5,
                    absolutePrescribedWeight: nil,
                    setDelta: nil,
                    absoluteTargetSets: nil,
                    repDelta: nil,
                    absoluteTargetReps: nil,
                    replacementExerciseName: nil,
                    adjustmentReasonRawValue: AdjustmentReason.topSetBeatTarget.rawValue,
                    isAutoApplied: false
                )
            ]
        )
        try repository.upsertAppliedOverlayPayloads([overlayDTO])

        let proposals = try fetchAll(AdaptationProposal.self, context)
        let overlays = try fetchAll(AppliedProgramOverlay.self, context)
        let adjustments = try fetchAll(AppliedOverlayAdjustment.self, context)

        #expect(proposals.count == 1)
        #expect(proposals[0].programRun?.id == runs[0].id)
        #expect(proposals[0].trainingProgram?.id == programs[0].id)
        #expect(proposals[0].sourceAnalysis?.id == analysis.id)

        #expect(overlays.count == 1)
        #expect(overlays[0].programRun?.id == runs[0].id)
        #expect(overlays[0].trainingProgram?.id == programs[0].id)
        #expect(overlays[0].sourceProposal?.id == proposals[0].id)
        #expect(adjustments.count == 1)
        #expect(adjustments[0].overlay?.id == overlays[0].id)
    }

    @Test func localSyncRepositoryUpsertsCoachAndHealthKitRows() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let repository = LocalSyncRepository(modelContext: context)

        let program = TrainingProgram(
            id: UUID(uuidString: "D0000000-0000-0000-0000-000000000001")!,
            syncStableID: "program-sync-coach",
            syncVersion: 1,
            syncLastModifiedAt: day(0),
            name: "Coach Program",
            lengthInWeeks: 4,
            sessionsPerWeek: 3,
            createdDate: day(0)
        )
        context.insert(program)

        let run = ProgramRun(
            id: UUID(uuidString: "D0000000-0000-0000-0000-000000000002")!,
            syncStableID: "run-sync-coach",
            syncVersion: 1,
            syncLastModifiedAt: day(0),
            startDate: day(0)
        )
        run.program = program
        context.insert(run)
        try context.save()

        try repository.upsertDailyCheckInPayloads([
            DailyCoachCheckInSyncDTO(
                metadata: SyncRecordMetadataDTO(
                    stableID: "checkin-sync-1",
                    version: 1,
                    lastModifiedAt: day(1)
                ),
                date: day(1),
                dayStart: day(1),
                sleepQuality: 4,
                soreness: 2,
                energy: 4,
                stress: 2,
                availableTimeMinutes: 50,
                hasPainOrDiscomfort: false,
                painNotes: nil,
                programRunStableID: "run-sync-coach",
                createdAt: day(1),
                updatedAt: day(1)
            )
        ])
        try repository.upsertWeeklyReviewPayloads([
            DailyCoachWeeklyReviewSyncDTO(
                metadata: SyncRecordMetadataDTO(
                    stableID: "review-sync-1",
                    version: 1,
                    lastModifiedAt: day(2)
                ),
                weekStart: day(0),
                weekEnd: day(6),
                isProgramWeek: true,
                programRunStableID: "run-sync-coach",
                headline: "Solid week",
                winText: "Bench moved well",
                watchoutText: "Sleep slipped",
                nextActionText: "Keep recovery steady",
                sourceWeeklyAnalysisIDText: nil,
                hasBeenSeen: false,
                createdAt: day(2)
            )
        ])
        try repository.upsertHealthKitSummaryPayloads([
            HealthKitDailySummarySyncDTO(
                metadata: SyncRecordMetadataDTO(
                    stableID: "health-sync-1",
                    version: 1,
                    lastModifiedAt: day(3)
                ),
                dayStart: day(1),
                sleepDurationSeconds: 28_000,
                timeInBedSeconds: 30_000,
                restingHeartRateBPM: 55,
                heartRateVariabilityMS: 48,
                activeEnergyKilocalories: 620,
                stepCount: 9_500,
                bodyMassKilograms: 84.5,
                sourceUpdatedAt: day(3),
                createdAt: day(3),
                updatedAt: day(3)
            )
        ])

        let checkIns = try fetchAll(DailyCoachCheckIn.self, context)
        let reviews = try fetchAll(DailyCoachWeeklyReview.self, context)
        let healthSummaries = try fetchAll(HealthKitDailySummary.self, context)

        #expect(checkIns.count == 1)
        #expect(checkIns[0].programRun?.id == run.id)
        #expect(reviews.count == 1)
        #expect(reviews[0].programRun?.id == run.id)
        #expect(healthSummaries.count == 1)
        #expect(healthSummaries[0].restingHeartRateBPM == 55)

        let since = try repository.fetchHealthKitSummaryPayloads(since: day(2))
        #expect(since.count == 1)
        #expect(since[0].metadata.stableID == "health-sync-1")
    }

    // MARK: - Helpers

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            MuscleGroup.self,
            Exercise.self,
            Workout.self,
            ExerciseEntry.self,
            SetEntry.self,
            PersonalRecord.self,
            TrainingProgram.self,
            ProgramWeekTemplate.self,
            ProgramSessionTemplate.self,
            ProgramSessionExercise.self,
            ProgramRun.self,
            ExercisePerformanceOutcome.self,
            WeeklyTrainingAnalysis.self,
            WeeklyVolumeMetric.self,
            LiftPerformanceTrend.self,
            LiftTrendSnapshot.self,
            AdaptationProposal.self,
            AppliedProgramOverlay.self,
            AppliedOverlayAdjustment.self,
            AdaptationEventHistory.self,
            DailyCoachCheckIn.self,
            DailyCoachWeeklyReview.self,
            HealthKitDailySummary.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeWorkoutDTO(
        stableID: String,
        lastModifiedAt: Date,
        version: Int,
        comments: String,
        entryStableIDs: [String]
    ) -> WorkoutSyncDTO {
        let entries = entryStableIDs.enumerated().map { index, entryID in
            ExerciseEntrySyncDTO(
                metadata: SyncRecordMetadataDTO(stableID: entryID, version: version, lastModifiedAt: lastModifiedAt),
                exerciseName: "Exercise \(index)",
                unitRawValue: WeightUnit.lbs.rawValue,
                orderIndex: index,
                isCardio: false,
                cardioDurationSeconds: nil,
                sourceProgramSessionExerciseStableID: nil,
                prescribedTargetSets: nil,
                prescribedTargetReps: nil,
                prescribedTargetPercentage1RM: nil,
                prescribedTargetRPE: nil,
                prescribedTargetRIR: nil,
                prescribedWeight: nil,
                prescribedWeightUnit: nil,
                prescribedWorkingSetStyleRawValue: nil,
                prescribedTargetEffortTypeRawValue: nil,
                effortFeedbackRawValue: nil,
                topSetRPE: nil,
                sets: [
                    SetEntrySyncDTO(
                        metadata: SyncRecordMetadataDTO(stableID: "\(entryID)-set-1", version: version, lastModifiedAt: lastModifiedAt),
                        setNumber: 1,
                        reps: 5,
                        weight: 135,
                        isPR: false
                    )
                ]
            )
        }

        return WorkoutSyncDTO(
            metadata: SyncRecordMetadataDTO(stableID: stableID, version: version, lastModifiedAt: lastModifiedAt),
            date: lastModifiedAt,
            startTime: lastModifiedAt,
            durationSeconds: 1800,
            caloriesBurned: nil,
            comments: comments,
            sourceTypeRawValue: WorkoutSourceType.loggedInApp.rawValue,
            sourceExternalIdentifier: nil,
            sourceDisplayName: nil,
            sourceWorkoutTypeIdentifier: nil,
            sourceWorkoutTypeDisplayName: nil,
            sourceImportedAt: nil,
            healthKitExportedAt: nil,
            healthKitWritebackIdentifier: nil,
            programRunStableID: nil,
            programWeekNumber: nil,
            programSessionNumber: nil,
            exerciseEntries: entries
        )
    }

    private func day(_ offset: Int) -> Date {
        let base = Date(timeIntervalSince1970: 1_765_000_000)
        return Calendar(identifier: .gregorian).date(byAdding: .day, value: offset, to: base) ?? base
    }

    private func fetchAll<T: PersistentModel>(_ type: T.Type, _ context: ModelContext) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }
}
