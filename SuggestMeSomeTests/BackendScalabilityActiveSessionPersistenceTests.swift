import Foundation
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct BackendScalabilityActiveSessionPersistenceTests {

    @Test func sessionPersistenceCodecDecodesLegacyRawPayloadAndCurrentEnvelope() throws {
        let session = ActiveWorkoutSession(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            startTime: Date(timeIntervalSince1970: 1_780_000_000),
            exerciseEntries: [
                DraftExerciseEntry(
                    exerciseName: "Bench Press",
                    unit: .lbs,
                    orderIndex: 0,
                    sets: [DraftSet(setNumber: 1, repsText: "5", weightText: "185")]
                )
            ],
            programContext: ActiveWorkoutProgramContext(
                programRunID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
                programRunStableID: "run-1",
                weekNumber: 1,
                sessionNumber: 1
            )
        )

        let legacyData = try JSONEncoder().encode(session)
        let currentData = ActiveWorkoutSessionPersistenceCodec.encode(session)

        #expect(ActiveWorkoutSessionPersistenceCodec.decode(legacyData) == session)
        #expect(ActiveWorkoutSessionPersistenceCodec.decode(currentData) == session)
    }

    @Test func watchActionReducerTracksDuplicateActionsWithoutMutatingSessionTwice() {
        let workoutID = UUID()
        let actionID = UUID()
        let session = ActiveWorkoutSession(
            id: workoutID,
            startTime: Date(timeIntervalSince1970: 1_780_000_000),
            exerciseEntries: [
                DraftExerciseEntry(
                    exerciseName: "Bench Press",
                    unit: .lbs,
                    orderIndex: 0,
                    sets: [DraftSet(setNumber: 1)]
                )
            ],
            sessionVersionStableID: "run-1::w1s1::planned"
        )
        let action = WatchWorkoutExecutionActionDTO(
            actionID: actionID,
            workoutID: workoutID,
            sessionVersionStableID: "run-1::w1s1::planned",
            actionKind: .completeCurrentSet,
            exerciseIndex: 0,
            setNumber: 1,
            completedReps: 5,
            completedWeight: 185
        )

        let first = ActiveWorkoutSessionWatchActionReducer.reduce(
            action: action,
            session: session,
            appliedActionIDs: []
        )
        let second = ActiveWorkoutSessionWatchActionReducer.reduce(
            action: action,
            session: first.session,
            appliedActionIDs: first.appliedActionIDs
        )

        #expect(first.result.didApply)
        #expect(first.session?.exerciseEntries[0].sets[0].repsText == "5")
        #expect(second.result.status == .ignoredStaleCursor)
        #expect(second.session?.exerciseEntries[0].sets[0].repsText == "5")
    }
}
