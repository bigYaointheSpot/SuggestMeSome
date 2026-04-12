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
}
