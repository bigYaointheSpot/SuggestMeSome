//
//  Feature20LiveActivityTests.swift
//  SuggestMeSomeTests
//
//  Coverage for the WorkoutLiveActivity content-state factory and the
//  ActiveWorkoutSessionStore lifecycle bridge. Pure-Foundation tests so
//  they don't need ActivityKit — all ActivityKit calls in the real
//  controller live behind `#if canImport` guards.
//

import Foundation
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature20LiveActivityTests {

    // MARK: - ContentState.fromSession

    @Test func fromSessionDerivesCurrentExerciseAndProgress() {
        let session = Self.sampleSession(
            exercises: [
                Self.strength(name: "Bench Press", logged: 2, total: 3),
                Self.strength(name: "Incline Press", logged: 0, total: 3)
            ]
        )
        let state = WorkoutLiveActivityAttributes.ContentState.fromSession(session)

        // Current exercise = first non-complete = Bench (2 of 3 logged, still incomplete).
        #expect(state.currentExerciseName == "Bench Press")
        #expect(state.currentExerciseInitial == "B")
        #expect(state.completedSetCount == 2)
        #expect(state.totalSetCount == 6)
        #expect(!state.isPaused)
        #expect(state.progressFraction > 0.3 && state.progressFraction < 0.4)
    }

    @Test func fromSessionPausedReportsAccumulatedSeconds() {
        var session = Self.sampleSession(exercises: [])
        session.lifecycleState = .paused
        session.accumulatedElapsedSeconds = 120
        session.stateChangedAt = Date().addingTimeInterval(-60)

        let state = WorkoutLiveActivityAttributes.ContentState.fromSession(session)
        #expect(state.isPaused)
        #expect(state.pausedElapsedSeconds == 120)
    }

    @Test func fromSessionNextSetTargetIncludesWeight() {
        var set = DraftSet(setNumber: 1, repsText: "8", weightText: "185")
        set.isPrefilledFromPrescription = true
        let entry = DraftExerciseEntry(
            exerciseName: "Bench Press",
            unit: .lbs,
            orderIndex: 0,
            sets: [set, DraftSet(setNumber: 2, repsText: "8", weightText: "185")]
        )
        let session = Self.sampleSession(exercises: [entry])
        let state = WorkoutLiveActivityAttributes.ContentState.fromSession(session)

        // Set 1 is prefilled-from-prescription so not counted as "logged" —
        // that's the pending next set.
        #expect(state.nextSetTarget == "Set 1/2 · 8 × 185 lbs")
    }

    @Test func fromSessionNextSetTargetDropsWeightForBodyweight() {
        let bodyweight = DraftExerciseEntry(
            exerciseName: "Pull-ups",
            unit: .lbs,
            orderIndex: 0,
            sets: [DraftSet(setNumber: 1, repsText: "10", weightText: "")]
        )
        let state = WorkoutLiveActivityAttributes.ContentState.fromSession(
            Self.sampleSession(exercises: [bodyweight])
        )
        #expect(state.nextSetTarget == "Set 1/1 · 10 reps")
    }

    @Test func fromSessionNextSetTargetSkipsCardioAndFallsThrough() {
        // Cardio has no per-set progression, so it doesn't contribute a
        // next-set line — the lock-screen title line already shows which
        // cardio exercise is active.
        let cardio = DraftExerciseEntry(
            exerciseName: "Row",
            unit: .lbs,
            orderIndex: 0,
            sets: [],
            isCardio: true,
            cardioMinutesText: ""
        )
        let cardioOnly = WorkoutLiveActivityAttributes.ContentState.fromSession(
            Self.sampleSession(exercises: [cardio])
        )
        #expect(cardioOnly.nextSetTarget == nil)

        // Cardio at the front should not block a strength exercise's
        // pending set from appearing.
        let strength = Self.strength(name: "Squat", logged: 0, total: 3)
        let mixed = WorkoutLiveActivityAttributes.ContentState.fromSession(
            Self.sampleSession(exercises: [cardio, strength])
        )
        #expect(mixed.nextSetTarget?.hasPrefix("Set 1/3") == true)
    }

    @Test func fromSessionNextSetTargetIsNilWhenFullyLogged() {
        let entry = Self.strength(name: "Squat", logged: 3, total: 3)
        let state = WorkoutLiveActivityAttributes.ContentState.fromSession(
            Self.sampleSession(exercises: [entry])
        )
        #expect(state.nextSetTarget == nil)
    }

    // MARK: - Initial glyph

    @Test func initialGlyphStripsDiacriticsAndHandlesEmptyInput() {
        #expect(WorkoutLiveActivityAttributes.ContentState.initialGlyph(for: "Bench Press") == "B")
        #expect(WorkoutLiveActivityAttributes.ContentState.initialGlyph(for: "  bench") == "B")
        #expect(WorkoutLiveActivityAttributes.ContentState.initialGlyph(for: "Élan") == "E")
        #expect(WorkoutLiveActivityAttributes.ContentState.initialGlyph(for: "") == nil)
        #expect(WorkoutLiveActivityAttributes.ContentState.initialGlyph(for: "   ") == nil)
        #expect(WorkoutLiveActivityAttributes.ContentState.initialGlyph(for: nil) == nil)
    }

    // MARK: - Codable round-trip

    @Test func contentStateRoundTripsThroughJSON() throws {
        let original = WorkoutLiveActivityAttributes.ContentState(
            startDate: Date(timeIntervalSince1970: 1_776_000_000),
            isPaused: true,
            pausedElapsedSeconds: 540,
            currentExerciseName: "Squat",
            currentExerciseInitial: "S",
            completedSetCount: 4,
            totalSetCount: 9,
            nextSetTarget: "Set 5/9 · 5 × 225 lbs"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            WorkoutLiveActivityAttributes.ContentState.self,
            from: data
        )
        #expect(decoded == original)
    }

    // MARK: - Session store lifecycle bridge

    @Test func sessionStoreStartsActivityOnFirstSession() {
        let bridge = SpyLiveActivityBridge()
        let store = ActiveWorkoutSessionStore(
            userDefaults: Self.ephemeralDefaults(),
            liveActivityBridge: bridge
        )

        let session = Self.sampleSession(exercises: [])
        store.session = session

        #expect(bridge.starts.map(\.id) == [session.id])
        #expect(bridge.updates.isEmpty)
        #expect(bridge.ends.isEmpty)
    }

    @Test func sessionStoreUpdatesActivityOnSessionMutation() {
        let bridge = SpyLiveActivityBridge()
        let store = ActiveWorkoutSessionStore(
            userDefaults: Self.ephemeralDefaults(),
            liveActivityBridge: bridge
        )
        var session = Self.sampleSession(exercises: [])
        store.session = session

        session.caloriesText = "350"
        store.session = session

        #expect(bridge.starts.count == 1)
        #expect(bridge.updates.map(\.id) == [session.id])
    }

    @Test func sessionStoreEndsActivityOnDiscard() {
        let bridge = SpyLiveActivityBridge()
        let store = ActiveWorkoutSessionStore(
            userDefaults: Self.ephemeralDefaults(),
            liveActivityBridge: bridge
        )
        let session = Self.sampleSession(exercises: [])
        store.session = session
        store.session = nil

        #expect(bridge.starts.count == 1)
        #expect(bridge.ends == [session.id])
    }

    @Test func sessionStoreSwapsActivityWhenIdentityChanges() {
        let bridge = SpyLiveActivityBridge()
        let store = ActiveWorkoutSessionStore(
            userDefaults: Self.ephemeralDefaults(),
            liveActivityBridge: bridge
        )
        let first = Self.sampleSession(exercises: [])
        let second = Self.sampleSession(exercises: [])
        store.session = first
        store.session = second

        #expect(bridge.starts.map(\.id) == [first.id, second.id])
        #expect(bridge.ends == [first.id])
    }

    // MARK: - Helpers

    private final class SpyLiveActivityBridge: WorkoutLiveActivityBridging {
        var starts: [ActiveWorkoutSession] = []
        var updates: [ActiveWorkoutSession] = []
        var ends: [UUID] = []

        func startLiveActivity(for session: ActiveWorkoutSession) { starts.append(session) }
        func updateLiveActivity(for session: ActiveWorkoutSession) { updates.append(session) }
        func endLiveActivity(sessionID: UUID) { ends.append(sessionID) }
    }

    private static func sampleSession(exercises: [DraftExerciseEntry]) -> ActiveWorkoutSession {
        ActiveWorkoutSession(
            startTime: Date(timeIntervalSince1970: 1_776_000_000),
            exerciseEntries: exercises
        )
    }

    private static func strength(name: String, logged: Int, total: Int) -> DraftExerciseEntry {
        var sets: [DraftSet] = []
        for i in 0..<total {
            let isLogged = i < logged
            sets.append(DraftSet(
                setNumber: i + 1,
                repsText: isLogged ? "8" : "",
                weightText: isLogged ? "135" : "",
                completionLoggedAt: isLogged ? Date() : nil
            ))
        }
        return DraftExerciseEntry(
            exerciseName: name,
            unit: .lbs,
            orderIndex: 0,
            sets: sets
        )
    }

    private static func ephemeralDefaults() -> UserDefaults {
        UserDefaults(suiteName: "Feature20LiveActivity.\(UUID().uuidString)")!
    }
}
