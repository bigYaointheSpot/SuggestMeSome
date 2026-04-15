//
//  Feature12Prompt6WatchSmartStackHardeningTests.swift
//  SuggestMeSomeTests
//
//  Feature 12 Prompt 6 — Smart Stack, hardening, and final validation.
//

import Foundation
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature12Prompt6WatchSmartStackHardeningTests {

    @Test func smartStackPrefersTodayPlanWhenIdle() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let snapshot = WatchWidgetSnapshot.mergingTodayPlan(
            makeTodayPlan(generatedAt: now),
            updatedAt: now
        )

        #expect(snapshot.preferredSurface(now: now) == .todayPlan)
        #expect(snapshot.todayPlan?.sessionLabel == "W1 · S1")
    }

    @Test func smartStackPrefersLiveWorkoutDuringActiveSession() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let today = WatchWidgetSnapshot.mergingTodayPlan(
            makeTodayPlan(generatedAt: now),
            updatedAt: now
        )
        let live = WatchWidgetSnapshot.mergingLiveWorkout(
            makeLiveWorkout(capturedAt: now, versionID: "run-1::w1s1::planned"),
            currentContext: makeCurrentContext(capturedAt: now, versionID: "run-1::w1s1::planned"),
            into: today,
            updatedAt: now
        )

        #expect(live.preferredSurface(now: now) == .liveWorkout)
        #expect(live.liveWorkout?.currentExerciseName == "Bench Press")
        #expect(live.liveWorkout?.currentSetSummary == "5 reps @ 185 lbs")
    }

    @Test func smartStackFallsBackToTodayPlanWhenLiveWorkoutIsStale() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let stale = now.addingTimeInterval(-(WatchWidgetSnapshot.activeWorkoutStaleAfter + 1))
        let today = WatchWidgetSnapshot.mergingTodayPlan(
            makeTodayPlan(generatedAt: now),
            updatedAt: now
        )
        let snapshot = WatchWidgetSnapshot.mergingLiveWorkout(
            makeLiveWorkout(capturedAt: stale, versionID: "run-1::w1s1::planned"),
            into: today,
            updatedAt: stale
        )

        #expect(snapshot.preferredSurface(now: now) == .todayPlan)
    }

    @Test func smartStackIgnoresMismatchedCurrentContextVersion() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let snapshot = WatchWidgetSnapshot.mergingLiveWorkout(
            makeLiveWorkout(capturedAt: now, versionID: "run-1::w1s1::planned"),
            currentContext: makeCurrentContext(capturedAt: now, versionID: "run-1::w1s1::runtime"),
            updatedAt: now
        )

        #expect(snapshot.liveWorkout?.currentExerciseName == "Squat")
        #expect(snapshot.liveWorkout?.currentSetSummary == nil)
    }

    @Test func activeWorkoutStoreRejectsMismatchedExecutionVersionActions() {
        let defaults = UserDefaults(suiteName: "Feature12Prompt6.versionGuard")!
        defaults.removePersistentDomain(forName: "Feature12Prompt6.versionGuard")
        let workoutID = UUID()
        let store = ActiveWorkoutSessionStore(
            userDefaults: defaults,
            persistenceKey: "activeWorkoutSession.versionGuard"
        )
        store.startSession(
            id: workoutID,
            startTime: Date(timeIntervalSince1970: 1_780_000_000),
            exerciseEntries: [makePartialEntry()],
            sessionPlanKind: .planned,
            sessionSourceLabels: ["Program"],
            sessionVersionStableID: "run-1::w1s1::planned"
        )

        let staleAction = WatchWorkoutExecutionActionDTO(
            workoutID: workoutID,
            sessionVersionStableID: "run-1::w1s1::runtime",
            actionKind: .completeCurrentSet,
            exerciseIndex: 0,
            setNumber: 1
        )

        let result = store.applyWatchExecutionAction(staleAction)

        #expect(result.status == .ignoredStaleCursor)
        #expect(store.session?.exerciseEntries[0].sets[0].repsText == "")
    }

    @Test func restTimerTransitionPolicyKeepsRestAliveAcrossSetAdvance() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let previous = makeCurrentContext(capturedAt: now, versionID: "run-1::w1s1::planned")
        var advanced = previous
        advanced.loggedSetsInExercise = 1
        advanced.currentSetNumber = 2
        advanced.nextSetNumber = 2
        advanced.currentSetTargetSummary = "5 reps @ 185 lbs"
        advanced.capturedAt = now.addingTimeInterval(2)

        #expect(
            WatchRestTimerTransitionPolicy.sessionIdentity(for: previous)
            == WatchRestTimerTransitionPolicy.sessionIdentity(for: advanced)
        )
        #expect(
            WatchRestTimerTransitionPolicy.shouldStopRestTimer(
                previousContext: previous,
                currentContext: advanced
            ) == false
        )
    }

    @Test func restTimerTransitionPolicyStopsForEndedOrReplacedSession() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let previous = makeCurrentContext(capturedAt: now, versionID: "run-1::w1s1::planned")
        let replaced = makeCurrentContext(capturedAt: now.addingTimeInterval(2), versionID: "run-1::w1s1::runtime")

        #expect(
            WatchRestTimerTransitionPolicy.shouldStopRestTimer(
                previousContext: previous,
                currentContext: replaced
            )
        )
        #expect(
            WatchRestTimerTransitionPolicy.shouldStopRestTimer(
                previousContext: previous,
                currentContext: nil
            )
        )
    }

    @Test func activeSessionBroadcastCarriesAllWorkoutAttribution() async throws {
        let bridge = MockWatchCompanionBridge()
        let coordinator = WatchSessionCoordinator(bridge: bridge)
        let workoutID = UUID()
        let session = ActiveWorkoutSession(
            id: workoutID,
            startTime: Date(timeIntervalSince1970: 1_780_000_000),
            exerciseEntries: [makePartialEntry()],
            programContext: ActiveWorkoutProgramContext(
                programRunID: UUID(),
                programRunStableID: "run-1",
                weekNumber: 1,
                sessionNumber: 1
            ),
            sessionPlanKind: .overlayAdjusted,
            sessionSourceLabels: ["Program", "Approved Overlay"],
            sessionVersionStableID: "run-1::w1s1::overlay"
        )

        await coordinator.broadcastActiveSessionState(
            session,
            capturedAt: Date(timeIntervalSince1970: 1_780_000_300)
        )

        let live = try unwrap(bridge.liveSnapshots.first)
        let current = try unwrap(bridge.sessionContexts.first)
        #expect(live.workoutID == workoutID)
        #expect(live.programRunStableID == "run-1")
        #expect(live.sessionPlanKind == .overlayAdjusted)
        #expect(live.sessionSourceLabels == ["Program", "Approved Overlay"])
        #expect(live.sessionVersionStableID == "run-1::w1s1::overlay")
        #expect(current.sessionVersionStableID == live.sessionVersionStableID)
    }

    private func makeTodayPlan(generatedAt: Date) -> WatchTodayPlanSnapshot {
        WatchTodayPlanSnapshot(
            confidence: "High",
            compactSummary: "Run as planned",
            primarySuggestionText: "Run the scheduled session.",
            readinessTier: "Strong",
            hasPainFlag: false,
            sessionLabel: "W1 · S1",
            programName: "Strength",
            programRunStableID: "run-1",
            programWeekNumber: 1,
            programSessionNumber: 1,
            activeSourceLabels: ["Manual Check-In", "Program"],
            whatChangedToday: "",
            adherenceHeadline: nil,
            adherenceGuidanceType: nil,
            sessionsBehindCount: 0,
            pendingProposalCount: 0,
            generatedAt: generatedAt
        )
    }

    private func makeLiveWorkout(capturedAt: Date, versionID: String) -> WatchLiveWorkoutSnapshot {
        WatchLiveWorkoutSnapshot(
            workoutID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            elapsedSeconds: 300,
            completedExercises: 1,
            totalExercises: 3,
            completedSetsInCurrentExercise: 1,
            totalSetsInCurrentExercise: 3,
            currentExerciseName: "Squat",
            sessionLabel: "W1 · S1",
            programRunStableID: "run-1",
            programWeekNumber: 1,
            programSessionNumber: 1,
            sessionPlanKind: .planned,
            sessionSourceLabels: ["Program"],
            sessionVersionStableID: versionID,
            capturedAt: capturedAt
        )
    }

    private func makeCurrentContext(capturedAt: Date, versionID: String) -> WatchCurrentSessionContext {
        WatchCurrentSessionContext(
            workoutID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            exerciseIndex: 1,
            exerciseName: "Bench Press",
            totalExercisesInSession: 3,
            totalSetsInExercise: 3,
            loggedSetsInExercise: 0,
            nextSetNumber: 1,
            nextPrescribedReps: 5,
            nextPrescribedWeight: 185,
            nextPrescribedWeightUnit: "lbs",
            isCardio: false,
            cardioTargetSeconds: nil,
            currentSetNumber: 1,
            currentSetTargetSummary: "5 reps @ 185 lbs",
            sessionPlanKind: .planned,
            sessionSourceLabels: ["Program"],
            sessionVersionStableID: versionID,
            capturedAt: capturedAt
        )
    }

    private func makePartialEntry() -> DraftExerciseEntry {
        DraftExerciseEntry(
            exerciseName: "Bench Press",
            unit: .lbs,
            orderIndex: 0,
            sets: [DraftSet(setNumber: 1)],
            prescribedTargetReps: 5,
            prescribedWeight: 185,
            prescribedWeightUnit: "lbs"
        )
    }

    private func unwrap<T>(_ value: T?) throws -> T {
        guard let value else { throw Prompt6UnwrapError.nilValue }
        return value
    }
}

private enum Prompt6UnwrapError: Error {
    case nilValue
}
