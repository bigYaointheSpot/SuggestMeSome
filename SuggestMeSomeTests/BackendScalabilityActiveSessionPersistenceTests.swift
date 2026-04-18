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

    @Test func persistenceStoreSkipsWritesWhenEncodedPayloadIsUnchanged() {
        let suiteName = "BackendScalabilityActiveSessionPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = ActiveWorkoutSessionPersistenceStore(
            userDefaults: defaults,
            persistenceKey: "active-session"
        )
        let session = makeSession()

        let firstWrite = store.save(session)
        let secondWrite = store.save(session)

        #expect(firstWrite)
        #expect(secondWrite == false)
        #expect(store.load() == session)
    }

    @Test func updateSessionReturnsUnchangedWhenDraftValuesMatchExistingSession() {
        let store = makeStore()
        let session = makeSession()

        store.startSession(
            id: session.id,
            startTime: session.startTime,
            exerciseEntries: session.exerciseEntries,
            programContext: session.programContext,
            sessionPlanKind: session.sessionPlanKind,
            sessionSourceLabels: session.sessionSourceLabels,
            sessionVersionStableID: session.sessionVersionStableID,
            usesLinkedWatchHealthSession: session.usesLinkedWatchHealthSession
        )
        store.updateSession(
            startTime: session.startTime,
            exerciseEntries: session.exerciseEntries,
            caloriesText: session.caloriesText,
            comments: session.comments,
            programContext: session.programContext,
            sessionPlanKind: session.sessionPlanKind,
            sessionSourceLabels: session.sessionSourceLabels,
            sessionVersionStableID: session.sessionVersionStableID
        )

        let result = store.updateSession(
            startTime: session.startTime,
            exerciseEntries: session.exerciseEntries,
            caloriesText: session.caloriesText,
            comments: session.comments,
            programContext: session.programContext,
            sessionPlanKind: session.sessionPlanKind,
            sessionSourceLabels: session.sessionSourceLabels,
            sessionVersionStableID: session.sessionVersionStableID
        )

        #expect(result == .unchanged)
    }

    @Test func updateSessionSkipsWatchBroadcastForCommentAndCalorieOnlyEdits() {
        let store = makeStore()
        let session = makeSession()

        store.startSession(
            id: session.id,
            startTime: session.startTime,
            exerciseEntries: session.exerciseEntries,
            programContext: session.programContext,
            sessionPlanKind: session.sessionPlanKind,
            sessionSourceLabels: session.sessionSourceLabels,
            sessionVersionStableID: session.sessionVersionStableID,
            usesLinkedWatchHealthSession: session.usesLinkedWatchHealthSession
        )

        let result = store.updateSession(
            startTime: session.startTime,
            exerciseEntries: session.exerciseEntries,
            caloriesText: "245",
            comments: "Strong session",
            programContext: session.programContext,
            sessionPlanKind: session.sessionPlanKind,
            sessionSourceLabels: session.sessionSourceLabels,
            sessionVersionStableID: session.sessionVersionStableID
        )

        #expect(result.didChangeSession)
        #expect(result.shouldBroadcastWatch == false)
        #expect(store.session?.caloriesText == "245")
        #expect(store.session?.comments == "Strong session")
    }

    @Test func updateSessionBroadcastsWatchForExerciseEntryEdits() {
        let store = makeStore()
        let session = makeSession()

        store.startSession(
            id: session.id,
            startTime: session.startTime,
            exerciseEntries: session.exerciseEntries,
            programContext: session.programContext,
            sessionPlanKind: session.sessionPlanKind,
            sessionSourceLabels: session.sessionSourceLabels,
            sessionVersionStableID: session.sessionVersionStableID,
            usesLinkedWatchHealthSession: session.usesLinkedWatchHealthSession
        )

        var updatedEntries = session.exerciseEntries
        updatedEntries[0].sets[0].repsText = "6"

        let result = store.updateSession(
            startTime: session.startTime,
            exerciseEntries: updatedEntries,
            caloriesText: session.caloriesText,
            comments: session.comments,
            programContext: session.programContext,
            sessionPlanKind: session.sessionPlanKind,
            sessionSourceLabels: session.sessionSourceLabels,
            sessionVersionStableID: session.sessionVersionStableID
        )

        #expect(result.didChangeSession)
        #expect(result.shouldBroadcastWatch)
        #expect(store.session?.exerciseEntries[0].sets[0].repsText == "6")
    }

    private func makeStore() -> ActiveWorkoutSessionStore {
        let suiteName = "BackendScalabilityActiveSessionPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return ActiveWorkoutSessionStore(
            userDefaults: defaults,
            persistenceKey: "active-session"
        )
    }

    private func makeSession() -> ActiveWorkoutSession {
        ActiveWorkoutSession(
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
            caloriesText: "200",
            comments: "Baseline",
            programContext: ActiveWorkoutProgramContext(
                programRunID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
                programRunStableID: "run-1",
                weekNumber: 1,
                sessionNumber: 1
            ),
            lifecycleState: .running,
            accumulatedElapsedSeconds: 600,
            stateChangedAt: Date(timeIntervalSince1970: 1_780_000_600),
            sessionPlanKind: .planned,
            sessionSourceLabels: ["Program"],
            sessionVersionStableID: "run-1::w1s1::planned",
            usesLinkedWatchHealthSession: true
        )
    }
}
