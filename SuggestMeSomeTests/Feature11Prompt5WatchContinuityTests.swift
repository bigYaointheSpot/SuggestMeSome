//
//  Feature11Prompt5WatchContinuityTests.swift
//  SuggestMeSomeTests
//
//  Feature 11 Prompt 5 — Watch-to-phone continuity and adjusted session
//  execution validation.
//
//  Covers:
//  - Transport/state continuity between Today Plan launch and watch
//  - Session-plan kind propagation for planned / overlay / runtime adjusted
//  - Session-version stable ID attribution integrity
//  - Progress handoff correctness (partial draft → current context + live)
//  - Adjusted-session compatibility (coach-adjusted drafts carry kind)
//  - Session completion handoff including counts and PR attribution
//

import Foundation
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature11Prompt5WatchContinuityTests {

    // MARK: - Session Plan Kind Mapping

    @Test func watchSessionPlanKindMirrorsLaunchPathForPlanned() {
        let kind = TodayPlanActionCoordinator.watchSessionPlanKind(for: .planned)
        #expect(kind == .planned)
    }

    @Test func watchSessionPlanKindMirrorsLaunchPathForApprovedOverlay() {
        let kind = TodayPlanActionCoordinator.watchSessionPlanKind(for: .approvedOverlayAdjusted)
        #expect(kind == .overlayAdjusted)
    }

    @Test func watchSessionPlanKindMirrorsLaunchPathForRuntimeAdjusted() {
        let kind = TodayPlanActionCoordinator.watchSessionPlanKind(for: .runtimeAdjusted)
        #expect(kind == .runtimeAdjusted)
    }

    // MARK: - Session Version Stable ID

    @Test func sessionVersionStableIDDifferentiatesLaunchPaths() {
        let planned = TodayPlanActionCoordinator.watchSessionVersionStableID(
            runStableID: "run-42",
            path: .planned,
            weekNumber: 2,
            sessionNumber: 3
        )
        let overlay = TodayPlanActionCoordinator.watchSessionVersionStableID(
            runStableID: "run-42",
            path: .approvedOverlayAdjusted,
            weekNumber: 2,
            sessionNumber: 3
        )
        let runtime = TodayPlanActionCoordinator.watchSessionVersionStableID(
            runStableID: "run-42",
            path: .runtimeAdjusted,
            weekNumber: 2,
            sessionNumber: 3
        )
        #expect(planned != overlay)
        #expect(planned != runtime)
        #expect(overlay != runtime)
        #expect(planned.contains("run-42"))
        #expect(planned.contains("w2s3"))
        #expect(runtime.hasSuffix("runtime"))
        #expect(overlay.hasSuffix("overlay"))
    }

    @Test func sessionVersionStableIDUsesStandaloneWhenNoProgramRun() {
        let id = TodayPlanActionCoordinator.watchSessionVersionStableID(
            runStableID: nil,
            path: .planned,
            weekNumber: nil,
            sessionNumber: nil
        )
        #expect(id.contains("standalone"))
        #expect(id.contains("free"))
    }

    // MARK: - Launch Payload Continuity

    @Test func launchPayloadCarriesSessionPlanKindAndSourceLabels() {
        let payload = WatchPayloadMapper.makeLaunchPayload(
            workoutID: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_700_300_000),
            programRunID: UUID(),
            programWeekNumber: 3,
            programSessionNumber: 2,
            sessionPlanKind: .overlayAdjusted,
            sessionSourceLabels: ["Manual Check-In", "Program", "Adaptive Overlay"],
            sessionVersionStableID: "run-7::w3s2::overlay"
        )
        #expect(payload.sessionPlanKind == .overlayAdjusted)
        #expect(payload.sessionSourceLabels == ["Manual Check-In", "Program", "Adaptive Overlay"])
        #expect(payload.sessionVersionStableID == "run-7::w3s2::overlay")
    }

    @Test func launchPayloadNormalizesEmptySourceLabelsToNil() {
        let payload = WatchPayloadMapper.makeLaunchPayload(
            workoutID: UUID(),
            startedAt: Date(),
            sessionPlanKind: .planned,
            sessionSourceLabels: ["  ", ""],
            sessionVersionStableID: "x::free::planned"
        )
        #expect(payload.sessionSourceLabels == nil)
        #expect(payload.sessionPlanKind == .planned)
    }

    @Test func launchPayloadOmitsContinuityFieldsWhenNotProvided() {
        let payload = WatchPayloadMapper.makeLaunchPayload(
            workoutID: UUID(),
            startedAt: Date()
        )
        #expect(payload.sessionPlanKind == nil)
        #expect(payload.sessionSourceLabels == nil)
        #expect(payload.sessionVersionStableID == nil)
    }

    // MARK: - Live Snapshot Continuity

    @Test func liveSnapshotCarriesPlanKindAndSourceLabels() {
        let entries: [DraftExerciseEntry] = [
            makeCompletedEntry(name: "Squat", orderIndex: 0, sets: 3),
            makePartialEntry(name: "Bench", orderIndex: 1, totalSets: 3, loggedSets: 1)
        ]
        let snap = WatchPayloadMapper.makeLiveWorkoutSnapshot(
            workoutID: UUID(),
            elapsedSeconds: 720,
            entries: entries,
            sessionLabel: "W2 · S1",
            programRunStableID: "run-9",
            programWeekNumber: 2,
            programSessionNumber: 1,
            sessionPlanKind: .runtimeAdjusted,
            sessionSourceLabels: ["Daily Coach"],
            sessionVersionStableID: "run-9::w2s1::runtime"
        )
        #expect(snap.sessionPlanKind == .runtimeAdjusted)
        #expect(snap.sessionSourceLabels == ["Daily Coach"])
        #expect(snap.sessionVersionStableID == "run-9::w2s1::runtime")
        #expect(snap.completedExercises == 1)
        #expect(snap.currentExerciseName == "Bench")
    }

    // MARK: - Current Session Context Continuity

    @Test func currentSessionContextCarriesFullAttribution() {
        var entry = makePartialEntry(name: "Deadlift", orderIndex: 0, totalSets: 3, loggedSets: 1)
        entry.prescribedTargetReps = 5
        entry.prescribedWeight = 315
        entry.prescribedWeightUnit = "lbs"
        let ctx = WatchPayloadMapper.makeCurrentSessionContext(
            workoutID: UUID(),
            entries: [entry],
            sessionPlanKind: .overlayAdjusted,
            sessionSourceLabels: ["Program", "Adaptive Overlay"],
            sessionVersionStableID: "run-5::w1s1::overlay"
        )
        let context = try! unwrap(ctx)
        #expect(context.sessionPlanKind == .overlayAdjusted)
        #expect(context.sessionSourceLabels == ["Program", "Adaptive Overlay"])
        #expect(context.sessionVersionStableID == "run-5::w1s1::overlay")
        #expect(context.currentSetNumber == 2)
        #expect(context.loggedSetsInExercise == 1)
    }

    // MARK: - Session Completion Handoff

    @Test func sessionCompletionPayloadReportsCorrectCounts() {
        let entries: [DraftExerciseEntry] = [
            makeCompletedEntry(name: "Squat", orderIndex: 0, sets: 3),
            makeCompletedEntry(name: "Bench", orderIndex: 1, sets: 3),
            makePartialEntry(name: "Row", orderIndex: 2, totalSets: 3, loggedSets: 2)
        ]
        let payload = WatchPayloadMapper.makeSessionCompletionPayload(
            workoutID: UUID(),
            completedAt: Date(timeIntervalSince1970: 1_700_400_000),
            totalElapsedSeconds: 2_400,
            entries: entries,
            sessionLabel: "W1 · S1",
            sessionPlanKind: .planned,
            sessionSourceLabels: ["Program"],
            sessionVersionStableID: "run-1::w1s1::planned",
            newPersonalRecordCount: 1
        )
        #expect(payload.totalExercises == 3)
        #expect(payload.completedExercises == 2)
        #expect(payload.totalSets == 9)
        #expect(payload.completedSets == 8)
        #expect(payload.newPersonalRecordCount == 1)
        #expect(payload.sessionPlanKind == .planned)
        #expect(payload.sessionSourceLabels == ["Program"])
        #expect(payload.sessionVersionStableID == "run-1::w1s1::planned")
    }

    @Test func sessionCompletionPayloadClampsNegativesAndHandlesCardio() {
        var cardio = DraftExerciseEntry(
            exerciseName: "Row Erg",
            unit: .lbs,
            orderIndex: 0,
            sets: [],
            isCardio: true,
            cardioMinutesText: "10",
            cardioSecondsText: "0"
        )
        _ = cardio
        let payload = WatchPayloadMapper.makeSessionCompletionPayload(
            workoutID: UUID(),
            completedAt: Date(),
            totalElapsedSeconds: -5,
            entries: [cardio],
            sessionLabel: "Cardio"
        )
        #expect(payload.totalElapsedSeconds == 0)
        #expect(payload.completedExercises == 1)
        #expect(payload.totalSets == 0)
        #expect(payload.completedSets == 1)
    }

    // MARK: - Envelope Round-Trip for Completion Payload

    @Test func envelopeRoundTripsForSessionCompletion() throws {
        let payload = WatchSessionCompletionPayload(
            workoutID: UUID(),
            completedAt: Date(timeIntervalSince1970: 1_700_500_000),
            totalElapsedSeconds: 1_800,
            completedExercises: 4,
            totalExercises: 4,
            completedSets: 12,
            totalSets: 12,
            sessionLabel: "W1 · S1",
            sessionPlanKind: .runtimeAdjusted,
            sessionSourceLabels: ["Manual Check-In", "Daily Coach"],
            sessionVersionStableID: "run-1::w1s1::runtime",
            newPersonalRecordCount: 2
        )
        let envelope = WatchPayloadEnvelope(
            kind: .sessionCompletion,
            payload: payload,
            sentAt: Date(timeIntervalSince1970: 1_700_500_100)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(envelope)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(WatchPayloadEnvelope<WatchSessionCompletionPayload>.self, from: data)
        #expect(decoded == envelope)
        #expect(decoded.kind == .sessionCompletion)
    }

    // MARK: - Coordinator End-to-End

    @Test func coordinatorBroadcastsPlannedLaunchAndCompletionWithContinuity() async {
        let bridge = MockWatchCompanionBridge()
        let coordinator = WatchSessionCoordinator(bridge: bridge)

        let workoutID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_700_600_000)
        await coordinator.broadcastWorkoutLaunch(
            workoutID: workoutID,
            startedAt: startedAt,
            programRunID: UUID(),
            programWeekNumber: 1,
            programSessionNumber: 1,
            sessionPlanKind: .planned,
            sessionSourceLabels: ["Program"],
            sessionVersionStableID: "run-0::w1s1::planned"
        )
        #expect(bridge.launchPayloads.count == 1)
        let launch = try! unwrap(bridge.launchPayloads.first)
        #expect(launch.sessionPlanKind == .planned)
        #expect(launch.sessionSourceLabels == ["Program"])
        #expect(launch.sessionVersionStableID == "run-0::w1s1::planned")

        let entries: [DraftExerciseEntry] = [
            makeCompletedEntry(name: "Squat", orderIndex: 0, sets: 3)
        ]
        await coordinator.broadcastLiveWorkout(
            workoutID: workoutID,
            elapsedSeconds: 900,
            entries: entries,
            sessionLabel: "W1 · S1",
            sessionPlanKind: .planned,
            sessionSourceLabels: ["Program"],
            sessionVersionStableID: "run-0::w1s1::planned"
        )
        let live = try! unwrap(bridge.liveSnapshots.first)
        #expect(live.sessionPlanKind == .planned)
        #expect(live.sessionSourceLabels == ["Program"])
        #expect(live.sessionVersionStableID == "run-0::w1s1::planned")

        await coordinator.broadcastCurrentSessionContext(
            workoutID: workoutID,
            entries: entries,
            sessionPlanKind: .planned,
            sessionSourceLabels: ["Program"],
            sessionVersionStableID: "run-0::w1s1::planned"
        )
        let ctx = try! unwrap(bridge.sessionContexts.first)
        #expect(ctx.sessionPlanKind == .planned)
        #expect(ctx.sessionVersionStableID == "run-0::w1s1::planned")

        await coordinator.broadcastSessionCompletion(
            workoutID: workoutID,
            completedAt: Date(timeIntervalSince1970: 1_700_600_900),
            totalElapsedSeconds: 900,
            entries: entries,
            sessionLabel: "W1 · S1",
            sessionPlanKind: .planned,
            sessionSourceLabels: ["Program"],
            sessionVersionStableID: "run-0::w1s1::planned",
            newPersonalRecordCount: 0
        )
        #expect(bridge.sessionCompletions.count == 1)
        let completion = try! unwrap(bridge.sessionCompletions.first)
        #expect(completion.sessionPlanKind == .planned)
        #expect(completion.completedExercises == 1)
        #expect(completion.totalElapsedSeconds == 900)
    }

    @Test func coordinatorBroadcastsRuntimeAdjustedKindEndToEnd() async {
        let bridge = MockWatchCompanionBridge()
        let coordinator = WatchSessionCoordinator(bridge: bridge)
        let entries: [DraftExerciseEntry] = [
            makePartialEntry(name: "OHP", orderIndex: 0, totalSets: 3, loggedSets: 0)
        ]
        await coordinator.broadcastWorkoutLaunch(
            workoutID: UUID(),
            startedAt: Date(),
            sessionPlanKind: .runtimeAdjusted,
            sessionSourceLabels: ["Daily Coach"],
            sessionVersionStableID: "x::w1s1::runtime"
        )
        await coordinator.broadcastCurrentSessionContext(
            workoutID: UUID(),
            entries: entries,
            sessionPlanKind: .runtimeAdjusted,
            sessionSourceLabels: ["Daily Coach"],
            sessionVersionStableID: "x::w1s1::runtime"
        )
        let launch = try! unwrap(bridge.launchPayloads.first)
        let ctx = try! unwrap(bridge.sessionContexts.first)
        #expect(launch.sessionPlanKind == .runtimeAdjusted)
        #expect(ctx.sessionPlanKind == .runtimeAdjusted)
        #expect(launch.sessionVersionStableID == ctx.sessionVersionStableID)
        #expect(launch.sessionSourceLabels == ctx.sessionSourceLabels)
    }

    // MARK: - Helpers

    private func unwrap<T>(_ value: T?) throws -> T {
        guard let v = value else { throw Prompt5UnwrapError.nilValue }
        return v
    }

    private func makeEmptyEntry(name: String, orderIndex: Int, sets: Int) -> DraftExerciseEntry {
        let draftSets = (1...max(1, sets)).map { DraftSet(setNumber: $0) }
        return DraftExerciseEntry(
            exerciseName: name,
            unit: .lbs,
            orderIndex: orderIndex,
            sets: draftSets
        )
    }

    private func makePartialEntry(name: String, orderIndex: Int, totalSets: Int, loggedSets: Int) -> DraftExerciseEntry {
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
            sets: draftSets
        )
    }

    private func makeCompletedEntry(name: String, orderIndex: Int, sets: Int) -> DraftExerciseEntry {
        let draftSets = (1...max(1, sets)).map { i in
            DraftSet(setNumber: i, repsText: "5", weightText: "135")
        }
        return DraftExerciseEntry(
            exerciseName: name,
            unit: .lbs,
            orderIndex: orderIndex,
            sets: draftSets
        )
    }
}

private enum Prompt5UnwrapError: Error {
    case nilValue
}
