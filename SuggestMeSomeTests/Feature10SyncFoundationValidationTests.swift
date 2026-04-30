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
        _ = try repository.upsertWorkoutPayloads([first])

        var fetched = try repository.fetchWorkoutPayloads(since: nil, includeDeleted: false)
        #expect(fetched.count == 1)
        #expect(fetched[0].comments == "First")
        #expect(fetched[0].exerciseEntries.count == 1)

        var updated = first
        updated.metadata.version = 2
        updated.metadata.lastModifiedAt = day(2)
        updated.comments = "Updated"
        updated.exerciseEntries = []
        _ = try repository.upsertWorkoutPayloads([updated])

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

    @Test func localSyncRepositoryUpsertsCoachRows() throws {
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

        let checkIns = try fetchAll(DailyCoachCheckIn.self, context)
        let reviews = try fetchAll(DailyCoachWeeklyReview.self, context)

        #expect(checkIns.count == 1)
        #expect(checkIns[0].programRun?.id == run.id)
        #expect(reviews.count == 1)
        #expect(reviews[0].programRun?.id == run.id)
    }

    @Test func localSyncRepositoryAppliesIncrementalSincePredicatesAcrossDomains() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let repository = LocalSyncRepository(modelContext: context)

        let programOld = TrainingProgram(
            id: UUID(uuidString: "E0000000-0000-0000-0000-000000000001")!,
            syncStableID: "program-old",
            syncVersion: 1,
            syncLastModifiedAt: day(1),
            name: "Old Program",
            lengthInWeeks: 4,
            sessionsPerWeek: 3,
            createdDate: day(1)
        )
        let programNew = TrainingProgram(
            id: UUID(uuidString: "E0000000-0000-0000-0000-000000000002")!,
            syncStableID: "program-new",
            syncVersion: 2,
            syncLastModifiedAt: day(4),
            name: "New Program",
            lengthInWeeks: 6,
            sessionsPerWeek: 4,
            createdDate: day(4)
        )

        let runOld = ProgramRun(
            id: UUID(uuidString: "E0000000-0000-0000-0000-000000000003")!,
            syncStableID: "run-old",
            syncVersion: 1,
            syncLastModifiedAt: day(1),
            startDate: day(1)
        )
        runOld.program = programOld
        let runNew = ProgramRun(
            id: UUID(uuidString: "E0000000-0000-0000-0000-000000000004")!,
            syncStableID: "run-new",
            syncVersion: 2,
            syncLastModifiedAt: day(4),
            startDate: day(4)
        )
        runNew.program = programNew

        let workoutOld = Workout(
            id: UUID(uuidString: "E0000000-0000-0000-0000-000000000005")!,
            syncStableID: "workout-old",
            syncVersion: 1,
            syncLastModifiedAt: day(1),
            date: day(1),
            startTime: day(1),
            durationSeconds: 1_800
        )
        let workoutNew = Workout(
            id: UUID(uuidString: "E0000000-0000-0000-0000-000000000006")!,
            syncStableID: "workout-new",
            syncVersion: 2,
            syncLastModifiedAt: day(4),
            date: day(4),
            startTime: day(4),
            durationSeconds: 2_100
        )
        let workoutDeleted = Workout(
            id: UUID(uuidString: "E0000000-0000-0000-0000-000000000007")!,
            syncStableID: "workout-deleted",
            syncVersion: 3,
            syncLastModifiedAt: day(5),
            syncDeletedAt: day(5),
            date: day(5),
            startTime: day(5),
            durationSeconds: 1_200
        )

        let proposalOld = AdaptationProposal(
            id: UUID(uuidString: "E0000000-0000-0000-0000-000000000008")!,
            syncStableID: "proposal-old",
            syncVersion: 1,
            syncLastModifiedAt: day(1),
            createdAt: day(1),
            programRun: runOld,
            trainingProgram: programOld,
            proposalType: .increaseLoad,
            proposalStatus: .pendingUserConfirmation,
            requiresUserConfirmation: true,
            targetWeekStart: 1,
            adjustmentReason: .topSetBeatTarget,
            summaryText: "Old proposal"
        )
        let proposalNew = AdaptationProposal(
            id: UUID(uuidString: "E0000000-0000-0000-0000-000000000009")!,
            syncStableID: "proposal-new",
            syncVersion: 2,
            syncLastModifiedAt: day(4),
            createdAt: day(4),
            programRun: runNew,
            trainingProgram: programNew,
            proposalType: .increaseLoad,
            proposalStatus: .pendingUserConfirmation,
            requiresUserConfirmation: true,
            targetWeekStart: 2,
            adjustmentReason: .topSetBeatTarget,
            summaryText: "New proposal"
        )

        let overlayOld = AppliedProgramOverlay(
            id: UUID(uuidString: "E0000000-0000-0000-0000-000000000010")!,
            syncStableID: "overlay-old",
            syncVersion: 1,
            syncLastModifiedAt: day(1),
            createdAt: day(1),
            appliedAt: day(1),
            programRun: runOld,
            trainingProgram: programOld,
            sourceProposal: proposalOld,
            effectiveWeekStart: 1,
            appliedByUserConfirmation: true,
            adjustmentReason: .topSetBeatTarget,
            summaryText: "Old overlay"
        )
        let overlayNew = AppliedProgramOverlay(
            id: UUID(uuidString: "E0000000-0000-0000-0000-000000000011")!,
            syncStableID: "overlay-new",
            syncVersion: 2,
            syncLastModifiedAt: day(4),
            createdAt: day(4),
            appliedAt: day(4),
            programRun: runNew,
            trainingProgram: programNew,
            sourceProposal: proposalNew,
            effectiveWeekStart: 2,
            appliedByUserConfirmation: true,
            adjustmentReason: .topSetBeatTarget,
            summaryText: "New overlay"
        )

        let checkInOld = DailyCoachCheckIn(
            id: UUID(uuidString: "E0000000-0000-0000-0000-000000000012")!,
            syncStableID: "checkin-old",
            syncVersion: 1,
            syncLastModifiedAt: day(1),
            date: day(1),
            dayStart: day(1),
            createdAt: day(1),
            updatedAt: day(1)
        )
        let checkInNew = DailyCoachCheckIn(
            id: UUID(uuidString: "E0000000-0000-0000-0000-000000000013")!,
            syncStableID: "checkin-new",
            syncVersion: 2,
            syncLastModifiedAt: day(4),
            date: day(4),
            dayStart: day(4),
            createdAt: day(4),
            updatedAt: day(4)
        )

        let reviewOld = DailyCoachWeeklyReview(
            id: UUID(uuidString: "E0000000-0000-0000-0000-000000000014")!,
            syncStableID: "review-old",
            syncVersion: 1,
            syncLastModifiedAt: day(1),
            weekStart: day(1),
            weekEnd: day(6),
            headline: "Old review",
            winText: "Old win",
            watchoutText: "Old watchout",
            nextActionText: "Old action",
            createdAt: day(1)
        )
        let reviewNew = DailyCoachWeeklyReview(
            id: UUID(uuidString: "E0000000-0000-0000-0000-000000000015")!,
            syncStableID: "review-new",
            syncVersion: 2,
            syncLastModifiedAt: day(4),
            weekStart: day(4),
            weekEnd: day(10),
            headline: "New review",
            winText: "New win",
            watchoutText: "New watchout",
            nextActionText: "New action",
            createdAt: day(4)
        )

        context.insert(programOld)
        context.insert(programNew)
        context.insert(runOld)
        context.insert(runNew)
        context.insert(workoutOld)
        context.insert(workoutNew)
        context.insert(workoutDeleted)
        context.insert(proposalOld)
        context.insert(proposalNew)
        context.insert(overlayOld)
        context.insert(overlayNew)
        context.insert(checkInOld)
        context.insert(checkInNew)
        context.insert(reviewOld)
        context.insert(reviewNew)
        try context.save()

        let since = day(2)

        #expect(try repository.fetchTrainingProgramPayloads(since: since).map(\.metadata.stableID) == ["program-new"])
        #expect(try repository.fetchProgramRunPayloads(since: since).map(\.metadata.stableID) == ["run-new"])
        #expect(try repository.fetchWorkoutPayloads(since: since, includeDeleted: false).map(\.metadata.stableID) == ["workout-new"])

        let workoutsIncludingDeleted = try repository.fetchWorkoutPayloads(since: since, includeDeleted: true)
        #expect(workoutsIncludingDeleted.map(\.metadata.stableID) == ["workout-deleted", "workout-new"])
        #expect(workoutsIncludingDeleted.first?.metadata.deletedAt == day(5))

        #expect(try repository.fetchAdaptationProposalPayloads(since: since).map(\.metadata.stableID) == ["proposal-new"])
        #expect(try repository.fetchAppliedOverlayPayloads(since: since).map(\.metadata.stableID) == ["overlay-new"])
        #expect(try repository.fetchDailyCheckInPayloads(since: since).map(\.metadata.stableID) == ["checkin-new"])
        #expect(try repository.fetchWeeklyReviewPayloads(since: since).map(\.metadata.stableID) == ["review-new"])
    }

    @Test func trainingPreferencesSyncStoreRoundTripsAndRespectsSinceFiltering() throws {
        let suiteName = "Feature18TrainingPreferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let container = try makeInMemoryContainer()
        let repository = LocalSyncRepository(
            modelContext: container.mainContext,
            userDefaults: defaults
        )

        defaults.set(WeightUnit.kg.rawValue, forKey: "globalWeightUnit")
        defaults.set(180, forKey: "defaultRestTimerSeconds")
        defaults.set(0b0101010, forKey: "coachPreferredDays")
        TrainingPreferencesStore.markUpdated(
            userDefaults: defaults,
            at: day(3)
        )

        let initial = try repository.fetchTrainingPreferencesPayload(since: nil)
        #expect(initial?.globalWeightUnitRawValue == WeightUnit.kg.rawValue)
        #expect(initial?.defaultRestTimerSeconds == 180)
        #expect(initial?.coachPreferredDaysBitmask == 0b0101010)
        #expect(initial?.metadata.lastModifiedAt == day(3))
        #expect(try repository.fetchTrainingPreferencesPayload(since: day(4)) == nil)

        let remote = TrainingPreferencesSyncDTO(
            metadata: SyncRecordMetadataDTO(
                stableID: TrainingPreferencesStore.stableID,
                version: 9,
                lastModifiedAt: day(5)
            ),
            globalWeightUnitRawValue: WeightUnit.lbs.rawValue,
            defaultRestTimerSeconds: 120,
            coachPreferredDaysBitmask: 0b0011100
        )
        try repository.upsertTrainingPreferencesPayload(remote)

        let fetched = try repository.fetchTrainingPreferencesPayload(since: day(4))
        #expect(fetched == remote)
        #expect(defaults.string(forKey: "globalWeightUnit") == WeightUnit.lbs.rawValue)
        #expect(defaults.integer(forKey: "defaultRestTimerSeconds") == 120)
        #expect(defaults.integer(forKey: "coachPreferredDays") == 0b0011100)
    }

    @Test func cloudSyncStateStorePersistsCursorsPendingBatchesAndActivity() {
        let suiteName = "Feature18CloudSyncStateStore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = CloudSyncStateStore(userDefaults: defaults)
        let deviceID = store.deviceID()
        let accountID = UUID(uuidString: "F2000000-0000-0000-0000-000000000001")!
        let cursor = CloudSyncCollectionCursorDTO(
            collection: .workouts,
            nextCursor: "cursor-1",
            lastSuccessfulSyncAt: day(4)
        )
        let payload = CloudSyncBatchPayload(
            workouts: [makeWorkoutDTO(
                stableID: "pending-workout-1",
                lastModifiedAt: day(5),
                version: 2,
                comments: "Queued",
                entryStableIDs: ["pending-entry-1"]
            )]
        )
        let pendingBatch = PendingCloudSyncBatch(
            createdAt: day(5),
            reason: "Queued workout deletion sync",
            payload: payload
        )
        let activity = CloudSyncActivityRecord(
            date: day(6),
            level: .warning,
            message: "Retry sync soon"
        )

        store.setCursors([cursor])
        store.setLastSuccessfulSyncAt(day(4))
        store.setPendingBatches([pendingBatch])
        store.appendActivity(activity)
        store.setBootstrappedAccountID(accountID)

        #expect(store.deviceID() == deviceID)
        #expect(store.cursors() == [cursor])
        #expect(store.lastSuccessfulSyncAt() == day(4))
        #expect(store.pendingBatches() == [pendingBatch])
        #expect(store.activity().first == activity)
        #expect(store.bootstrappedAccountID() == accountID)

        store.clearRuntimeState()
        #expect(store.deviceID() == deviceID)
        #expect(store.cursors().isEmpty)
        #expect(store.lastSuccessfulSyncAt() == nil)
        #expect(store.pendingBatches().isEmpty)
        #expect(store.bootstrappedAccountID() == nil)
        #expect(store.activity().first == activity)
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
