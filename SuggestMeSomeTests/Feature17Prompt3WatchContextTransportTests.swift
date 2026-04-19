import Foundation
import SwiftUI
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature17Prompt3WatchContextTransportTests {

    @Test func firstContextKeepsFullRosterInTransport() throws {
        let context = try #require(makeContext(entries: baseEntries()))

        let decision = WatchCurrentSessionContextTransportPolicy.makeDecision(
            context: context,
            lastSentRosterFingerprint: nil
        )

        #expect(decision.transportContext.sessionExerciseRoster == context.sessionExerciseRoster)
        #expect(decision.rosterFingerprint != nil)
    }

    @Test func unchangedRosterCompactsTransportButKeepsReplayableContextFull() throws {
        let initialEntries = baseEntries()
        let initialContext = try #require(makeContext(entries: initialEntries))
        let initialDecision = WatchCurrentSessionContextTransportPolicy.makeDecision(
            context: initialContext,
            lastSentRosterFingerprint: nil
        )
        var updatedEntries = initialEntries
        updatedEntries[1].sets[1].repsText = "5"
        updatedEntries[1].sets[1].weightText = "135"
        let updatedContext = try #require(
            makeContext(entries: updatedEntries)
        )

        let compactDecision = WatchCurrentSessionContextTransportPolicy.makeDecision(
            context: updatedContext,
            lastSentRosterFingerprint: initialDecision.rosterFingerprint
        )

        #expect(compactDecision.transportContext.sessionExerciseRoster == nil)
        #expect(compactDecision.replayableContext.sessionExerciseRoster == updatedContext.sessionExerciseRoster)
        #expect(compactDecision.rosterFingerprint == initialDecision.rosterFingerprint)
    }

    @Test func reorderForcesFullRosterTransport() throws {
        let initialEntries = baseEntries()
        let initialContext = try #require(makeContext(entries: initialEntries))
        let initialDecision = WatchCurrentSessionContextTransportPolicy.makeDecision(
            context: initialContext,
            lastSentRosterFingerprint: nil
        )
        var reorderedEntries = initialEntries
        reorderedEntries.move(fromOffsets: IndexSet(integer: 3), toOffset: 2)
        reorderedEntries = reorderedEntries.normalizedExerciseOrder()
        let reorderedContext = try #require(makeContext(entries: reorderedEntries))

        let decision = WatchCurrentSessionContextTransportPolicy.makeDecision(
            context: reorderedContext,
            lastSentRosterFingerprint: initialDecision.rosterFingerprint
        )

        #expect(decision.transportContext.sessionExerciseRoster == reorderedContext.sessionExerciseRoster)
        #expect(decision.rosterFingerprint != initialDecision.rosterFingerprint)
    }

    @Test func newWorkoutIDForcesFullRosterTransport() throws {
        let entries = baseEntries()
        let initialContext = try #require(makeContext(entries: entries, workoutID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!))
        let initialDecision = WatchCurrentSessionContextTransportPolicy.makeDecision(
            context: initialContext,
            lastSentRosterFingerprint: nil
        )
        let nextWorkoutContext = try #require(
            makeContext(entries: entries, workoutID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)
        )

        let decision = WatchCurrentSessionContextTransportPolicy.makeDecision(
            context: nextWorkoutContext,
            lastSentRosterFingerprint: initialDecision.rosterFingerprint
        )

        #expect(decision.transportContext.sessionExerciseRoster == nextWorkoutContext.sessionExerciseRoster)
        #expect(decision.rosterFingerprint != initialDecision.rosterFingerprint)
    }

    @Test func newSessionVersionForcesFullRosterTransport() throws {
        let entries = baseEntries()
        let initialContext = try #require(
            makeContext(entries: entries, sessionVersionStableID: "session-a")
        )
        let initialDecision = WatchCurrentSessionContextTransportPolicy.makeDecision(
            context: initialContext,
            lastSentRosterFingerprint: nil
        )
        let updatedContext = try #require(
            makeContext(entries: entries, sessionVersionStableID: "session-b")
        )

        let decision = WatchCurrentSessionContextTransportPolicy.makeDecision(
            context: updatedContext,
            lastSentRosterFingerprint: initialDecision.rosterFingerprint
        )

        #expect(decision.transportContext.sessionExerciseRoster == updatedContext.sessionExerciseRoster)
        #expect(decision.rosterFingerprint != initialDecision.rosterFingerprint)
    }

    @Test func compactedReplayableContextCanRehydrateFullRosterOnReplay() throws {
        let entries = baseEntries()
        let initialContext = try #require(makeContext(entries: entries))
        let initialDecision = WatchCurrentSessionContextTransportPolicy.makeDecision(
            context: initialContext,
            lastSentRosterFingerprint: nil
        )
        var updatedEntries = entries
        updatedEntries[0].sets[0].repsText = "10"
        let updatedContext = try #require(makeContext(entries: updatedEntries))

        let compactDecision = WatchCurrentSessionContextTransportPolicy.makeDecision(
            context: updatedContext,
            lastSentRosterFingerprint: initialDecision.rosterFingerprint
        )
        let replayDecision = WatchCurrentSessionContextTransportPolicy.makeDecision(
            context: compactDecision.replayableContext,
            lastSentRosterFingerprint: nil
        )

        #expect(compactDecision.transportContext.sessionExerciseRoster == nil)
        #expect(replayDecision.transportContext.sessionExerciseRoster == updatedContext.sessionExerciseRoster)
    }

    private func makeContext(
        entries: [DraftExerciseEntry],
        workoutID: UUID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
        sessionVersionStableID: String? = "session-a"
    ) -> WatchCurrentSessionContext? {
        WatchPayloadMapper.makeCurrentSessionContext(
            workoutID: workoutID,
            entries: entries,
            sessionVersionStableID: sessionVersionStableID
        )
    }

    private func baseEntries() -> [DraftExerciseEntry] {
        [
            makeCompletedEntry(name: "Warmup", orderIndex: 0),
            makePartialEntry(name: "Bench Press", orderIndex: 1, totalSets: 3, loggedSets: 1),
            makePendingEntry(name: "Row", orderIndex: 2, totalSets: 3),
            makePendingEntry(name: "Curl", orderIndex: 3, totalSets: 3)
        ]
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
