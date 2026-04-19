import Foundation
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature17Prompt4WatchRosterPreservationTests {

    @Test func liveWorkoutStatePreservesRosterAcrossCompactContextUpdates() throws {
        let state = WatchLiveWorkoutState()
        let initialContext = try #require(makeContext(cursor: 1, sessionVersionStableID: "session-a"))
        let advancedContext = try #require(makeContext(cursor: 2, sessionVersionStableID: "session-a"))
        var compactAdvancedContext = advancedContext
        compactAdvancedContext.sessionExerciseRoster = nil

        state.setCurrentContext(initialContext)
        state.setCurrentContext(compactAdvancedContext)

        let mergedContext = try #require(state.currentContext)
        #expect(mergedContext.exerciseIndex == 2)
        #expect(mergedContext.exerciseName == "Row")
        #expect(mergedContext.sessionExerciseRoster == initialContext.sessionExerciseRoster)
    }

    @Test func compactRosterPreservationStopsAtWorkoutOrSessionBoundaries() throws {
        let initialContext = try #require(makeContext(cursor: 1, sessionVersionStableID: "session-a"))
        var differentWorkoutContext = try #require(
            makeContext(
                cursor: 2,
                workoutID: UUID(uuidString: "22222222-3333-4444-5555-666666666666")!,
                sessionVersionStableID: "session-a"
            )
        )
        differentWorkoutContext.sessionExerciseRoster = nil

        let mergedAcrossWorkout = WatchCurrentSessionContextMergePolicy.mergePreservingRoster(
            existing: initialContext,
            incoming: differentWorkoutContext
        )

        #expect(mergedAcrossWorkout?.sessionExerciseRoster == nil)

        var differentSessionContext = try #require(makeContext(cursor: 2, sessionVersionStableID: "session-b"))
        differentSessionContext.sessionExerciseRoster = nil

        let mergedAcrossSession = WatchCurrentSessionContextMergePolicy.mergePreservingRoster(
            existing: initialContext,
            incoming: differentSessionContext
        )

        #expect(mergedAcrossSession?.sessionExerciseRoster == nil)
    }

    @Test func liveWorkoutStateClearsPreservedRosterOnResetAndCompletion() throws {
        let state = WatchLiveWorkoutState()
        let initialContext = try #require(makeContext(cursor: 1, sessionVersionStableID: "session-a"))

        state.setCurrentContext(initialContext)
        state.resetActivePayloads()
        #expect(state.currentContext == nil)

        state.setCurrentContext(initialContext)
        state.clearForCompletion()
        #expect(state.currentContext == nil)
    }

    @Test func upNextUsesPreservedRosterOrderWhenStatusesAreStale() throws {
        let initialContext = try #require(makeContext(cursor: 1, sessionVersionStableID: "session-a"))
        let advancedContext = try #require(makeContext(cursor: 2, sessionVersionStableID: "session-a"))
        var compactAdvancedContext = advancedContext
        compactAdvancedContext.sessionExerciseRoster = nil

        let mergedContext = try #require(
            WatchCurrentSessionContextMergePolicy.mergePreservingRoster(
                existing: initialContext,
                incoming: compactAdvancedContext
            )
        )

        let upcoming = WatchSessionExerciseRosterPresentationPolicy.upcomingEntries(
            roster: mergedContext.sessionExerciseRoster,
            activeExerciseIndex: mergedContext.exerciseIndex
        )

        #expect(upcoming.map(\.name) == ["Curl"])
    }

    private func makeContext(
        cursor: Int,
        workoutID: UUID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
        sessionVersionStableID: String?
    ) -> WatchCurrentSessionContext? {
        WatchPayloadMapper.makeCurrentSessionContext(
            workoutID: workoutID,
            entries: [
                makeCompletedEntry(name: "Warmup", orderIndex: 0),
                makePartialEntry(name: "Bench Press", orderIndex: 1, totalSets: 3, loggedSets: 1),
                makePendingEntry(name: "Row", orderIndex: 2, totalSets: 3),
                makePendingEntry(name: "Curl", orderIndex: 3, totalSets: 3)
            ],
            cursor: cursor,
            sessionVersionStableID: sessionVersionStableID
        )
    }

    private func makePartialEntry(
        name: String,
        orderIndex: Int,
        totalSets: Int,
        loggedSets: Int
    ) -> DraftExerciseEntry {
        let sets = (1...max(1, totalSets)).map { index -> DraftSet in
            if index <= loggedSets {
                return DraftSet(setNumber: index, repsText: "5", weightText: "135")
            }
            return DraftSet(setNumber: index)
        }
        return DraftExerciseEntry(
            exerciseName: name,
            unit: .lbs,
            orderIndex: orderIndex,
            sets: sets
        )
    }

    private func makePendingEntry(name: String, orderIndex: Int, totalSets: Int) -> DraftExerciseEntry {
        makePartialEntry(name: name, orderIndex: orderIndex, totalSets: totalSets, loggedSets: 0)
    }

    private func makeCompletedEntry(name: String, orderIndex: Int) -> DraftExerciseEntry {
        makePartialEntry(name: name, orderIndex: orderIndex, totalSets: 2, loggedSets: 2)
    }
}
