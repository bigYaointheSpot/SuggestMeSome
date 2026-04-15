//
//  Feature12Prompt4WatchActionsTests.swift
//  SuggestMeSomeTests
//
//  Feature 12 Prompt 4 — watch actions and phone-side workout control.
//

import Foundation
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature12Prompt4WatchActionsTests {

    @Test func executionActionDTORoundTripsThroughBridgeCodec() throws {
        let workoutID = UUID()
        let actionID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_712_966_400)
        let sentAt = Date(timeIntervalSince1970: 1_712_966_410)
        let action = WatchWorkoutExecutionActionDTO(
            actionID: actionID,
            workoutID: workoutID,
            sessionVersionStableID: "run-1::w1s1::planned",
            actionKind: .applyCrownTicksToCurrentSetReps,
            exerciseIndex: 1,
            setNumber: 2,
            ticks: 3,
            completedReps: 8,
            completedWeight: 155,
            createdAt: createdAt
        )

        let dictionary = try WatchBridgeMessageCodec.makeMessage(
            kind: .workoutExecutionAction,
            payload: action,
            sentAt: sentAt
        )
        let message = try WatchBridgeMessageCodec.decodeMessage(from: dictionary)
        let decoded = try WatchBridgeMessageCodec.decodePayload(
            WatchWorkoutExecutionActionDTO.self,
            from: message
        )

        #expect(message.kind == .workoutExecutionAction)
        #expect(message.schemaVersion == WatchPayloadContractVersion.current)
        #expect(decoded == action)
    }

    @Test func pureActionHelpersApplyRepsWeightAndCompletionToCurrentSet() throws {
        let entries = [
            makePartialEntry(name: "Bench Press", orderIndex: 0, totalSets: 2, loggedSets: 1)
        ]
        let workoutID = UUID()

        let repsAction = WatchWorkoutExecutionActionDTO(
            workoutID: workoutID,
            actionKind: .applyCrownTicksToCurrentSetReps,
            exerciseIndex: 0,
            setNumber: 2,
            ticks: 2
        )
        let repsResult = WatchPayloadMapper.applyExecutionAction(repsAction, to: entries)
        #expect(repsResult.didApply)
        #expect(repsResult.updatedEntries[0].sets[1].repsText == "7")

        let weightAction = WatchWorkoutExecutionActionDTO(
            workoutID: workoutID,
            actionKind: .applyCrownTicksToCurrentSetWeight,
            exerciseIndex: 0,
            setNumber: 2,
            ticks: -1
        )
        let weightResult = WatchPayloadMapper.applyExecutionAction(
            weightAction,
            to: repsResult.updatedEntries
        )
        #expect(weightResult.didApply)
        #expect(weightResult.updatedEntries[0].sets[1].weightText == "130")

        let emptyEntries = [
            makePartialEntry(name: "Bench Press", orderIndex: 0, totalSets: 2, loggedSets: 1)
        ]
        let completeAction = WatchWorkoutExecutionActionDTO(
            workoutID: workoutID,
            actionKind: .completeCurrentSet,
            exerciseIndex: 0,
            setNumber: 2
        )
        let completeResult = WatchPayloadMapper.applyExecutionAction(
            completeAction,
            to: emptyEntries
        )
        #expect(completeResult.didApply)
        #expect(WatchPayloadMapper.isExerciseComplete(completeResult.updatedEntries[0]))
    }

    @Test func pureActionHelperMarksCurrentCardioComplete() {
        let entries = [
            DraftExerciseEntry(
                exerciseName: "Bike",
                unit: .lbs,
                orderIndex: 0,
                sets: [],
                isCardio: true
            )
        ]
        let action = WatchWorkoutExecutionActionDTO(
            workoutID: UUID(),
            actionKind: .completeCardioBlock,
            exerciseIndex: 0
        )

        let result = WatchPayloadMapper.applyExecutionAction(action, to: entries)

        #expect(result.didApply)
        #expect(result.updatedEntries[0].cardioCompletionLogged == true)
        #expect(WatchPayloadMapper.isExerciseComplete(result.updatedEntries[0]))
    }

    @Test func pureActionHelperIgnoresStaleCursor() {
        let entries = [
            makePartialEntry(name: "Squat", orderIndex: 0, totalSets: 2, loggedSets: 1)
        ]
        let staleAction = WatchWorkoutExecutionActionDTO(
            workoutID: UUID(),
            actionKind: .completeCurrentSet,
            exerciseIndex: 0,
            setNumber: 1
        )

        let result = WatchPayloadMapper.applyExecutionAction(staleAction, to: entries)

        #expect(result.status == .ignoredStaleCursor)
        #expect(result.updatedEntries == entries)
    }

    @Test func completeCurrentSetUsesExplicitWatchValuesForManualCarryForward() {
        let entries = [
            DraftExerciseEntry(
                exerciseName: "Bench Press",
                unit: .lbs,
                orderIndex: 0,
                sets: [
                    DraftSet(setNumber: 1, repsText: "10", weightText: "100"),
                    DraftSet(setNumber: 2),
                    DraftSet(setNumber: 3)
                ]
            )
        ]
        let action = WatchWorkoutExecutionActionDTO(
            workoutID: UUID(),
            actionKind: .completeCurrentSet,
            exerciseIndex: 0,
            setNumber: 2,
            completedReps: 10,
            completedWeight: 105
        )

        let result = WatchPayloadMapper.applyExecutionAction(action, to: entries)

        #expect(result.didApply)
        #expect(result.updatedEntries[0].sets[1].repsText == "10")
        #expect(result.updatedEntries[0].sets[1].weightText == "105")
        #expect(WatchPayloadMapper.isSetLogged(result.updatedEntries[0].sets[1]))
        let context = WatchPayloadMapper.makeCurrentSessionContext(
            workoutID: action.workoutID,
            entries: result.updatedEntries
        )
        #expect(context != nil)
        #expect(context?.currentSetNumber == 3)
        #expect(context?.loggedSetsInExercise == 2)
    }

    @Test func completeCurrentSetAdvancesWhenCurrentSetWasOnlyPrefilled() {
        let entries = [
            DraftExerciseEntry(
                exerciseName: "Bench Press",
                unit: .lbs,
                orderIndex: 0,
                sets: [
                    DraftSet(
                        setNumber: 1,
                        repsText: "5",
                        weightText: "185",
                        isPrefilledFromPrescription: true
                    ),
                    DraftSet(
                        setNumber: 2,
                        repsText: "5",
                        weightText: "185",
                        isPrefilledFromPrescription: true
                    )
                ],
                prescribedTargetReps: 5,
                prescribedWeight: 185,
                prescribedWeightUnit: "lbs"
            )
        ]
        let action = WatchWorkoutExecutionActionDTO(
            workoutID: UUID(),
            actionKind: .completeCurrentSet,
            exerciseIndex: 0,
            setNumber: 1,
            completedReps: 5,
            completedWeight: 185
        )

        let result = WatchPayloadMapper.applyExecutionAction(action, to: entries)

        #expect(result.didApply)
        #expect(result.updatedEntries[0].sets[0].completionLoggedAt != nil)
        #expect(result.updatedEntries[0].sets[0].isPrefilledFromPrescription == false)
        let context = WatchPayloadMapper.makeCurrentSessionContext(
            workoutID: action.workoutID,
            entries: result.updatedEntries
        )
        #expect(context != nil)
        #expect(context?.currentSetNumber == 2)
        #expect(context?.loggedSetsInExercise == 1)
    }

    @Test func activeWorkoutStoreIgnoresActionWhenNoActiveWorkoutExists() {
        let defaults = UserDefaults(suiteName: "Feature12Prompt4WatchActionsTests.noActive")!
        defaults.removePersistentDomain(forName: "Feature12Prompt4WatchActionsTests.noActive")
        let store = ActiveWorkoutSessionStore(
            userDefaults: defaults,
            persistenceKey: "activeWorkoutSession.noActive"
        )
        let action = WatchWorkoutExecutionActionDTO(
            workoutID: UUID(),
            actionKind: .completeCurrentSet,
            exerciseIndex: 0,
            setNumber: 1
        )

        let result = store.applyWatchExecutionAction(action)

        #expect(!result.didApply)
        #expect(result.status == .ignoredEmptyDraft)
        #expect(store.session == nil)
    }

    private func makePartialEntry(
        name: String,
        orderIndex: Int,
        totalSets: Int,
        loggedSets: Int
    ) -> DraftExerciseEntry {
        let draftSets = (1...max(1, totalSets)).map { i -> DraftSet in
            if i <= loggedSets {
                return DraftSet(setNumber: i, repsText: "5", weightText: "135")
            }
            return DraftSet(setNumber: i)
        }
        return DraftExerciseEntry(
            exerciseName: name,
            unit: .lbs,
            orderIndex: orderIndex,
            sets: draftSets,
            prescribedTargetReps: 5,
            prescribedWeight: 135,
            prescribedWeightUnit: "lbs"
        )
    }
}
