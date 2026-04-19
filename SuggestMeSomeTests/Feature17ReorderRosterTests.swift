//
//  Feature17ReorderRosterTests.swift
//  SuggestMeSomeTests
//
//  Feature 17 — exercise reorder + watch session roster.
//

import Foundation
import SwiftUI
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature17ReorderRosterTests {

    // MARK: - Roster DTO Codec

    @Test func rosterEntryRoundTripsThroughCodable() throws {
        let original = WatchSessionExerciseRosterEntry(
            id: UUID(),
            name: "Goblet Squat",
            orderIndex: 2,
            status: .upcoming,
            isCardio: false
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WatchSessionExerciseRosterEntry.self, from: data)

        #expect(decoded == original)
    }

    @Test func currentSessionContextOmitsRosterWhenAbsent() throws {
        let legacyJSON = """
        {
            "workoutID": "11111111-2222-3333-4444-555555555555",
            "exerciseIndex": 0,
            "exerciseName": "Bench Press",
            "totalExercisesInSession": 2,
            "totalSetsInExercise": 3,
            "loggedSetsInExercise": 0,
            "isCardio": false,
            "capturedAt": 0
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(WatchCurrentSessionContext.self, from: legacyJSON)

        #expect(decoded.sessionExerciseRoster == nil)
        #expect(decoded.exerciseName == "Bench Press")
    }

    // MARK: - Roster Construction

    @Test func rosterLabelsCompletedActiveAndUpcoming() {
        let entries = [
            makeCompletedEntry(name: "Warmup", orderIndex: 0),
            makePartialEntry(name: "Bench Press", orderIndex: 1, totalSets: 3, loggedSets: 1),
            makePendingEntry(name: "Row", orderIndex: 2, totalSets: 3),
            makePendingEntry(name: "Curl", orderIndex: 3, totalSets: 3)
        ]

        let roster = WatchPayloadMapper.makeExerciseRoster(entries: entries, activeIndex: 1)

        #expect(roster.count == 4)
        #expect(roster[0].status == .completed)
        #expect(roster[1].status == .active)
        #expect(roster[2].status == .upcoming)
        #expect(roster[3].status == .upcoming)
        #expect(roster.map(\.name) == ["Warmup", "Bench Press", "Row", "Curl"])
    }

    @Test func currentSessionContextEmbedsRosterThatTracksCurrentExercise() throws {
        let entries = [
            makeCompletedEntry(name: "Warmup", orderIndex: 0),
            makePartialEntry(name: "Bench Press", orderIndex: 1, totalSets: 3, loggedSets: 1),
            makePendingEntry(name: "Row", orderIndex: 2, totalSets: 3)
        ]

        let context = WatchPayloadMapper.makeCurrentSessionContext(
            workoutID: UUID(),
            entries: entries
        )

        let roster = try #require(context?.sessionExerciseRoster)
        #expect(roster.count == 3)
        #expect(roster[1].id == entries[1].id)
        #expect(roster[1].status == .active)
    }

    // MARK: - Reorder Clamping

    /// Mirrors `WorkoutView.handleExerciseMove` — completed + active prefix
    /// must stay pinned in place when an upcoming row is dragged above them.
    @Test func reorderClampsDestinationAboveLockedPrefix() {
        var entries = [
            makeCompletedEntry(name: "Warmup", orderIndex: 0),
            makePartialEntry(name: "Bench Press", orderIndex: 1, totalSets: 3, loggedSets: 1),
            makePendingEntry(name: "Row", orderIndex: 2, totalSets: 3),
            makePendingEntry(name: "Curl", orderIndex: 3, totalSets: 3)
        ]
        let originalCurl = entries[3]

        // Active is index 1 → first movable index is 2.
        // Request a move to offset 0 (top); clamp should prevent it from
        // landing above the locked prefix.
        let firstMovable = 2
        let requestedDestination = 0
        let clamped = max(firstMovable, requestedDestination)

        entries.move(fromOffsets: IndexSet(integer: 3), toOffset: clamped)

        // After clamp, Curl should land at the first movable slot, never
        // above the active exercise.
        #expect(entries[0].exerciseName == "Warmup")
        #expect(entries[1].exerciseName == "Bench Press")
        #expect(entries[2].id == originalCurl.id)
        #expect(entries[3].exerciseName == "Row")
    }

    @Test func reorderPreservesOrderIndexRenumbering() {
        var entries = [
            makePendingEntry(name: "A", orderIndex: 0, totalSets: 3),
            makePendingEntry(name: "B", orderIndex: 1, totalSets: 3),
            makePendingEntry(name: "C", orderIndex: 2, totalSets: 3)
        ]

        entries.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        for idx in entries.indices {
            entries[idx].orderIndex = idx
        }

        #expect(entries.map(\.exerciseName) == ["C", "A", "B"])
        #expect(entries.map(\.orderIndex) == [0, 1, 2])
    }

    @Test func normalizedExerciseOrderRepairsDeleteAndAddSequence() {
        var entries = [
            makePendingEntry(name: "A", orderIndex: 0, totalSets: 3),
            makePendingEntry(name: "B", orderIndex: 1, totalSets: 3),
            makePendingEntry(name: "C", orderIndex: 2, totalSets: 3)
        ]

        entries.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        entries = entries.normalizedExerciseOrder()
        entries.removeAll { $0.exerciseName == "A" }
        entries.append(makePendingEntry(name: "D", orderIndex: entries.count, totalSets: 3))

        let normalized = entries.normalizedExerciseOrder()

        #expect(normalized.map(\.exerciseName) == ["C", "B", "D"])
        #expect(normalized.map(\.orderIndex) == [0, 1, 2])
        #expect(Set(normalized.map(\.orderIndex)).count == normalized.count)
    }

    @Test func normalizedExerciseOrderPreservesVisibleArrayOrderDuringHydration() {
        let entries = [
            makePendingEntry(name: "Bench Press", orderIndex: 4, totalSets: 3),
            makePendingEntry(name: "Row", orderIndex: 1, totalSets: 3),
            makePendingEntry(name: "Curl", orderIndex: 9, totalSets: 3)
        ]

        let normalized = entries.normalizedExerciseOrder()

        #expect(normalized.map(\.exerciseName) == ["Bench Press", "Row", "Curl"])
        #expect(normalized.map(\.orderIndex) == [0, 1, 2])
    }

    // MARK: - Helpers

    private func makePartialEntry(
        name: String,
        orderIndex: Int,
        totalSets: Int,
        loggedSets: Int
    ) -> DraftExerciseEntry {
        let sets = (1...max(1, totalSets)).map { i -> DraftSet in
            if i <= loggedSets {
                return DraftSet(setNumber: i, repsText: "5", weightText: "135")
            }
            return DraftSet(setNumber: i)
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
