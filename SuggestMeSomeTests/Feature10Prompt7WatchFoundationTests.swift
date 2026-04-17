//
//  Feature10Prompt7WatchFoundationTests.swift
//  SuggestMeSomeTests
//
//  Feature 10 Prompt 7 — Apple Watch Companion and Today Plan Transport
//  Foundation validation tests.
//
//  Covers:
//  - Watch payload contract envelope versioning + Codable round-trip
//  - Today Plan snapshot mapping (program, standalone, pain, low readiness,
//    adherence rescue, what-changed propagation)
//  - Launch payload generation
//  - Live workout snapshot mapping (counts + current exercise)
//  - Current session context mapping (first incomplete, logged sets, cursor override)
//  - Progress snapshot parity with live snapshot counts
//  - Coordinator broadcasts through the bridge (mock bridge, no WatchConnectivity)
//

import Foundation
import Testing
@testable import SuggestMeSome

// MARK: - Feature 10 Prompt 7 Suite

@Suite(.serialized)
@MainActor
struct Feature10Prompt7WatchFoundationTests {

    // MARK: - Contract Envelope

    @Test func envelopeRoundTripsForTodayPlanSnapshot() throws {
        let snapshot = WatchTodayPlanSnapshot(
            confidence: "High",
            compactSummary: "Run as planned",
            primarySuggestionText: "Run your scheduled session.",
            readinessTier: "Neutral",
            hasPainFlag: false,
            sessionLabel: "W2 · S1",
            programName: "Test Program",
            programWeekNumber: 2,
            programSessionNumber: 1,
            activeSourceLabels: ["Manual Check-In", "Program"],
            whatChangedToday: "",
            adherenceHeadline: nil,
            adherenceGuidanceType: nil,
            sessionsBehindCount: 0,
            pendingProposalCount: 0,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let envelope = WatchPayloadEnvelope(
            kind: .todayPlanSnapshot,
            payload: snapshot,
            sentAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        #expect(envelope.schemaVersion == WatchPayloadContractVersion.current)
        #expect(envelope.kind == .todayPlanSnapshot)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(envelope)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(WatchPayloadEnvelope<WatchTodayPlanSnapshot>.self, from: data)

        #expect(decoded == envelope)
    }

    @Test func envelopeRoundTripsForLiveWorkoutSnapshot() throws {
        let snapshot = WatchLiveWorkoutSnapshot(
            workoutID: UUID(),
            elapsedSeconds: 125,
            completedExercises: 1,
            totalExercises: 3,
            completedSetsInCurrentExercise: 2,
            totalSetsInCurrentExercise: 4,
            currentExerciseName: "Bench Press",
            sessionLabel: "W1 · S1",
            programRunStableID: "run-123",
            programWeekNumber: 1,
            programSessionNumber: 1,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_500)
        )

        let envelope = WatchPayloadEnvelope(
            kind: .liveWorkoutSnapshot,
            payload: snapshot,
            sentAt: Date(timeIntervalSince1970: 1_700_000_600)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(envelope)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(WatchPayloadEnvelope<WatchLiveWorkoutSnapshot>.self, from: data)
        #expect(decoded == envelope)
        #expect(decoded.schemaVersion == WatchPayloadContractVersion.v1)
    }

    @Test func envelopeRoundTripsForCurrentSessionContext() throws {
        let context = WatchCurrentSessionContext(
            workoutID: UUID(),
            exerciseIndex: 1,
            exerciseName: "Back Squat",
            totalExercisesInSession: 5,
            totalSetsInExercise: 3,
            loggedSetsInExercise: 1,
            nextSetNumber: 2,
            nextPrescribedReps: 5,
            nextPrescribedWeight: 225,
            nextPrescribedWeightUnit: "lbs",
            isCardio: false,
            cardioTargetSeconds: nil,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_900)
        )
        let envelope = WatchPayloadEnvelope(
            kind: .currentSessionContext,
            payload: context,
            sentAt: Date(timeIntervalSince1970: 1_700_001_000)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(envelope)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(WatchPayloadEnvelope<WatchCurrentSessionContext>.self, from: data)
        #expect(decoded == envelope)
    }

    @Test func envelopeRoundTripsForWatchPresenceHeartbeat() throws {
        let heartbeat = WatchPresenceHeartbeatPayload(
            sentAt: Date(timeIntervalSince1970: 1_700_001_100)
        )
        let envelope = WatchPayloadEnvelope(
            kind: .watchPresenceHeartbeat,
            payload: heartbeat,
            sentAt: Date(timeIntervalSince1970: 1_700_001_101)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(envelope)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(
            WatchPayloadEnvelope<WatchPresenceHeartbeatPayload>.self,
            from: data
        )

        #expect(decoded == envelope)
    }

    @Test func watchStatusResolverStaysPendingBeforeActivationCompletes() {
        let checkedAt = Date(timeIntervalSince1970: 1_700_002_000)
        let status = WatchCompanionStatusResolver.makeStatus(
            from: WatchCompanionSessionSnapshot(
                isSupported: true,
                activationState: .notActivated,
                isPaired: false,
                isWatchAppInstalled: false,
                isReachable: false
            ),
            evidence: WatchCompanionEvidence(),
            checkedAt: checkedAt
        )

        #expect(status.availability == .statusPending)
        #expect(status.activationState == .notActivated)
        #expect(status.message.contains("activating"))
    }

    @Test func watchStatusResolverKeepsConfirmedCompanionDuringInactiveSessionTransitions() {
        let checkedAt = Date(timeIntervalSince1970: 1_700_002_100)
        var evidence = WatchCompanionEvidence()
        evidence.recordInstalledCompanion(at: checkedAt.addingTimeInterval(-300))

        let status = WatchCompanionStatusResolver.makeStatus(
            from: WatchCompanionSessionSnapshot(
                isSupported: true,
                activationState: .inactive,
                isPaired: false,
                isWatchAppInstalled: false,
                isReachable: false
            ),
            evidence: evidence,
            checkedAt: checkedAt
        )

        #expect(status.availability == .statusPending)
        #expect(status.message.contains("previously confirmed"))
    }

    @Test func watchHeartbeatEvidenceTracksLastWatchContact() {
        let heartbeatAt = Date(timeIntervalSince1970: 1_700_002_200)
        var evidence = WatchCompanionEvidence()

        evidence.recordWatchContact(at: heartbeatAt)

        #expect(evidence.lastWatchContactAt == heartbeatAt)
        #expect(evidence.lastConfirmedInstallAt == heartbeatAt)
    }

    @Test func watchStatusResolverAllowsReplayAfterTransientFalseInstallRead() {
        let now = Date(timeIntervalSince1970: 1_700_002_300)
        var evidence = WatchCompanionEvidence()
        evidence.recordWatchContact(at: now.addingTimeInterval(-60))

        let snapshot = WatchCompanionSessionSnapshot(
            isSupported: true,
            activationState: .activated,
            isPaired: true,
            isWatchAppInstalled: false,
            isReachable: false
        )
        let status = WatchCompanionStatusResolver.makeStatus(
            from: snapshot,
            evidence: evidence,
            checkedAt: now
        )

        #expect(WatchCompanionStatusResolver.canSendPayloads(with: snapshot, evidence: evidence, now: now))
        #expect(status.availability == .companionInstalled)
        #expect(status.lastWatchContactAt == evidence.lastWatchContactAt)
    }

    // MARK: - Today Plan Snapshot Mapping

    @Test func todayPlanSnapshotCarriesProgramSessionLabel() {
        let plan = makePlan(
            confidence: .high,
            compact: "Heavy day",
            primary: "Work hard",
            readiness: .neutral,
            nextProgramSession: NextProgramSessionInfo(
                weekNumber: 3,
                sessionNumber: 2,
                sessionName: "Lower A",
                programName: "Squat Focus"
            ),
            activeSourceLabels: ["Manual Check-In", "Program"],
            whatChanged: ""
        )

        let snapshot = WatchPayloadMapper.makeTodayPlanSnapshot(
            from: plan,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        #expect(snapshot.confidence == "High")
        #expect(snapshot.compactSummary == "Heavy day")
        #expect(snapshot.primarySuggestionText == "Work hard")
        #expect(snapshot.readinessTier == "Neutral")
        #expect(snapshot.hasPainFlag == false)
        #expect(snapshot.sessionLabel.contains("W3"))
        #expect(snapshot.sessionLabel.contains("S2"))
        #expect(snapshot.sessionLabel.contains("Lower A"))
        #expect(snapshot.programName == "Squat Focus")
        #expect(snapshot.programWeekNumber == 3)
        #expect(snapshot.programSessionNumber == 2)
        #expect(snapshot.activeSourceLabels == ["Manual Check-In", "Program"])
        #expect(snapshot.sessionsBehindCount == 0)
        #expect(snapshot.adherenceHeadline == nil)
    }

    @Test func todayPlanSnapshotFallsBackToStandaloneSessionType() {
        let plan = makePlan(
            confidence: .medium,
            compact: "Full body",
            primary: "Run a balanced session",
            readiness: .strong,
            standaloneSessionType: .fullBody
        )
        let snapshot = WatchPayloadMapper.makeTodayPlanSnapshot(from: plan)
        #expect(snapshot.sessionLabel == StandaloneSessionType.fullBody.rawValue)
        #expect(snapshot.programWeekNumber == nil)
        #expect(snapshot.programSessionNumber == nil)
        #expect(snapshot.readinessTier == "Strong")
        #expect(snapshot.confidence == "Medium")
    }

    @Test func todayPlanSnapshotCarriesPainFlag() {
        let plan = makePlan(
            confidence: .low,
            compact: "Pain flagged",
            primary: "Prioritise pain-free movement",
            readiness: .unknown,
            hasPainFlag: true
        )
        let snapshot = WatchPayloadMapper.makeTodayPlanSnapshot(from: plan)
        #expect(snapshot.hasPainFlag == true)
        #expect(snapshot.readinessTier == "Unknown")
        #expect(snapshot.confidence == "Low")
    }

    @Test func todayPlanSnapshotCarriesAdherenceRescue() {
        let rescue = AdherenceRescue(
            status: .slightlyBehind(sessionsBehind: 1),
            guidanceType: .trimAndResume,
            headline: "1 session behind",
            details: "Trim a set to catch up.",
            sessionsBehindCount: 1
        )
        let plan = makePlan(
            confidence: .medium,
            compact: "Catch up",
            primary: "Trim and resume",
            readiness: .neutral,
            adherenceRescue: rescue
        )
        let snapshot = WatchPayloadMapper.makeTodayPlanSnapshot(from: plan)
        #expect(snapshot.sessionsBehindCount == 1)
        #expect(snapshot.adherenceHeadline == "1 session behind")
        #expect(snapshot.adherenceGuidanceType == AdherenceGuidanceType.trimAndResume.rawValue)
    }

    @Test func todayPlanSnapshotPropagatesWhatChangedTodayAndProposals() {
        let plan = makePlan(
            confidence: .medium,
            compact: "Mixed signals",
            primary: "Run with caution",
            readiness: .low,
            pendingProposalCount: 2,
            whatChanged: "Readiness is below normal — conservative adjustments applied."
        )
        let snapshot = WatchPayloadMapper.makeTodayPlanSnapshot(from: plan)
        #expect(snapshot.whatChangedToday.contains("below normal"))
        #expect(snapshot.pendingProposalCount == 2)
        #expect(snapshot.readinessTier == "Low")
    }

    // MARK: - Launch Payload

    @Test func launchPayloadCarriesProgramCoordinates() {
        let workoutID = UUID()
        let runID = UUID()
        let started = Date(timeIntervalSince1970: 1_700_100_000)
        let payload = WatchPayloadMapper.makeLaunchPayload(
            workoutID: workoutID,
            startedAt: started,
            programRunID: runID,
            programWeekNumber: 4,
            programSessionNumber: 2
        )
        #expect(payload.workoutID == workoutID)
        #expect(payload.startedAt == started)
        #expect(payload.programRunID == runID)
        #expect(payload.programWeekNumber == 4)
        #expect(payload.programSessionNumber == 2)
    }

    @Test func launchPayloadOmitsProgramCoordinatesForStandalone() {
        let payload = WatchPayloadMapper.makeLaunchPayload(
            workoutID: UUID(),
            startedAt: Date()
        )
        #expect(payload.programRunID == nil)
        #expect(payload.programWeekNumber == nil)
        #expect(payload.programSessionNumber == nil)
    }

    // MARK: - Current Session Context Mapping

    @Test func currentSessionContextPicksFirstIncompleteExercise() {
        let entries: [DraftExerciseEntry] = [
            makeCompletedEntry(name: "Squat", orderIndex: 0, sets: 3),
            makePartialEntry(name: "Bench", orderIndex: 1, totalSets: 3, loggedSets: 1),
            makeEmptyEntry(name: "Row", orderIndex: 2, sets: 3)
        ]
        let ctx = WatchPayloadMapper.makeCurrentSessionContext(
            workoutID: UUID(),
            entries: entries
        )
        let context = try! unwrap(ctx)
        #expect(context.exerciseIndex == 1)
        #expect(context.exerciseName == "Bench")
        #expect(context.totalExercisesInSession == 3)
        #expect(context.totalSetsInExercise == 3)
        #expect(context.loggedSetsInExercise == 1)
        #expect(context.nextSetNumber == 2)
    }

    @Test func currentSessionContextHonoursCursorOverride() {
        let entries: [DraftExerciseEntry] = [
            makeEmptyEntry(name: "Squat", orderIndex: 0, sets: 3),
            makeEmptyEntry(name: "Bench", orderIndex: 1, sets: 3),
            makeEmptyEntry(name: "Row", orderIndex: 2, sets: 3)
        ]
        let ctx = WatchPayloadMapper.makeCurrentSessionContext(
            workoutID: UUID(),
            entries: entries,
            cursor: 2
        )
        let context = try! unwrap(ctx)
        #expect(context.exerciseIndex == 2)
        #expect(context.exerciseName == "Row")
    }

    @Test func currentSessionContextReturnsNilForEmptyEntries() {
        let ctx = WatchPayloadMapper.makeCurrentSessionContext(
            workoutID: UUID(),
            entries: []
        )
        #expect(ctx == nil)
    }

    @Test func currentSessionContextReadsPrescribedTargetsWhenNoLiveValues() {
        var entry = makeEmptyEntry(name: "Deadlift", orderIndex: 0, sets: 3)
        entry.prescribedTargetReps = 5
        entry.prescribedWeight = 315
        entry.prescribedWeightUnit = "lbs"
        let ctx = WatchPayloadMapper.makeCurrentSessionContext(
            workoutID: UUID(),
            entries: [entry]
        )
        let context = try! unwrap(ctx)
        #expect(context.nextPrescribedReps == 5)
        #expect(context.nextPrescribedWeight == 315)
        #expect(context.nextPrescribedWeightUnit == "lbs")
    }

    @Test func currentSessionContextIncludesCurrentSetSummaryAndCrownDefaults() {
        var entry = makePartialEntry(name: "Bench", orderIndex: 0, totalSets: 3, loggedSets: 1)
        entry.prescribedTargetReps = 6
        entry.prescribedWeight = 185
        entry.prescribedWeightUnit = "lbs"
        let ctx = WatchPayloadMapper.makeCurrentSessionContext(
            workoutID: UUID(),
            entries: [entry],
            sessionPlanKind: .planned
        )
        let context = try! unwrap(ctx)
        #expect(context.currentSetNumber == 2)
        #expect(context.currentSetTargetSummary == "6 reps @ 185 lbs")
        #expect(context.currentSetCompletedWeight == 135)
        #expect(context.currentSetCompletedReps == 5)
        #expect(context.crownWeightStep == 5.0)
        #expect(context.quickCompleteEnabled == true)
        #expect(context.preferredInteractionModel == .digitalCrownFirst)
        #expect(context.sessionPlanKind == .planned)
    }

    @Test func currentSessionContextSupportsRuntimeAdjustedKind() {
        var entry = makeEmptyEntry(name: "Squat", orderIndex: 0, sets: 3)
        entry.prescribedTargetReps = 5
        entry.prescribedWeight = 225
        entry.prescribedWeightUnit = "lbs"
        let ctx = WatchPayloadMapper.makeCurrentSessionContext(
            workoutID: UUID(),
            entries: [entry],
            sessionPlanKind: .runtimeAdjusted
        )
        let context = try! unwrap(ctx)
        #expect(context.sessionPlanKind == .runtimeAdjusted)
        #expect(context.currentSetNumber == 1)
        #expect(context.currentSetTargetSummary == "5 reps @ 225 lbs")
    }

    @Test func currentSessionContextDoesNotTreatPrefilledPrescriptionSetsAsCompleted() {
        let entry = DraftExerciseEntry(
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

        let ctx = WatchPayloadMapper.makeCurrentSessionContext(
            workoutID: UUID(),
            entries: [entry]
        )
        let context = try! unwrap(ctx)
        #expect(context.currentSetNumber == 1)
        #expect(context.loggedSetsInExercise == 0)
        #expect(context.currentSetTargetSummary == "5 reps @ 185 lbs")
    }

    @Test func currentSessionContextFallsBackToLastEntryWhenAllComplete() {
        let entries: [DraftExerciseEntry] = [
            makeCompletedEntry(name: "Squat", orderIndex: 0, sets: 3),
            makeCompletedEntry(name: "Bench", orderIndex: 1, sets: 3)
        ]
        let ctx = WatchPayloadMapper.makeCurrentSessionContext(
            workoutID: UUID(),
            entries: entries
        )
        let context = try! unwrap(ctx)
        #expect(context.exerciseIndex == 1)
        #expect(context.exerciseName == "Bench")
        #expect(context.nextSetNumber == nil)
        #expect(context.loggedSetsInExercise == 3)
    }

    // MARK: - Crown-first Weight Entry

    @Test func crownTicksAdjustCurrentSetWeightUsingDefaultLbsStep() {
        let entries: [DraftExerciseEntry] = [makeEmptyEntry(name: "Bench", orderIndex: 0, sets: 3)]
        let updated = WatchPayloadMapper.applyCrownTicksToCurrentSet(
            entries: entries,
            ticks: 2
        )
        #expect(updated[0].sets[0].weightText == "10")
    }

    @Test func crownTicksUseKgStepOverrideWhenRequested() {
        let adjusted = WatchPayloadMapper.applyCrownTicksToWeight(
            currentWeight: 100,
            ticks: 3,
            unitLabel: "kg",
            stepOverride: 1.25
        )
        #expect(adjusted == 103.75)
    }

    // MARK: - Completion + Advance

    @Test func completeCurrentSetAdvancesWithinSameExerciseWhenSetsRemain() {
        let entries: [DraftExerciseEntry] = [makeEmptyEntry(name: "Bench", orderIndex: 0, sets: 3)]
        let result = WatchPayloadMapper.completeCurrentSetAndAdvance(
            entries: entries,
            completedWeight: 145,
            completedReps: 6
        )
        let advance = try! unwrap(result)
        #expect(advance.completedExerciseIndex == 0)
        #expect(advance.completedSetNumber == 1)
        #expect(advance.didAdvanceExercise == false)
        #expect(advance.nextExerciseIndex == 0)
        #expect(advance.nextSetNumber == 2)
        #expect(advance.isSessionComplete == false)
        #expect(advance.updatedEntries[0].sets[0].weightText == "145")
        #expect(advance.updatedEntries[0].sets[0].repsText == "6")
    }

    @Test func completeCurrentSetAdvancesToNextExerciseWhenCurrentExerciseFinishes() {
        let entries: [DraftExerciseEntry] = [
            makePartialEntry(name: "Bench", orderIndex: 0, totalSets: 2, loggedSets: 1),
            makeEmptyEntry(name: "Row", orderIndex: 1, sets: 2)
        ]
        let result = WatchPayloadMapper.completeCurrentSetAndAdvance(
            entries: entries,
            completedWeight: 155,
            completedReps: 5
        )
        let advance = try! unwrap(result)
        #expect(advance.completedExerciseIndex == 0)
        #expect(advance.completedSetNumber == 2)
        #expect(advance.didAdvanceExercise == true)
        #expect(advance.nextExerciseIndex == 1)
        #expect(advance.nextSetNumber == 1)
        #expect(advance.isSessionComplete == false)
    }

    @Test func completeCurrentSetMarksSessionCompleteWhenLastSetIsLogged() {
        let entries: [DraftExerciseEntry] = [makePartialEntry(name: "Bench", orderIndex: 0, totalSets: 1, loggedSets: 0)]
        let result = WatchPayloadMapper.completeCurrentSetAndAdvance(
            entries: entries,
            completedWeight: 135,
            completedReps: 5
        )
        let advance = try! unwrap(result)
        #expect(advance.nextExerciseIndex == nil)
        #expect(advance.nextSetNumber == nil)
        #expect(advance.isSessionComplete == true)
    }

    // MARK: - Live Workout Snapshot Mapping

    @Test func liveWorkoutSnapshotCountsCompletedExercises() {
        let workoutID = UUID()
        let entries: [DraftExerciseEntry] = [
            makeCompletedEntry(name: "Squat", orderIndex: 0, sets: 3),
            makePartialEntry(name: "Bench", orderIndex: 1, totalSets: 4, loggedSets: 2),
            makeEmptyEntry(name: "Row", orderIndex: 2, sets: 3)
        ]
        let snap = WatchPayloadMapper.makeLiveWorkoutSnapshot(
            workoutID: workoutID,
            elapsedSeconds: 600,
            entries: entries,
            sessionLabel: "W1 · S1",
            programWeekNumber: 1,
            programSessionNumber: 1
        )
        #expect(snap.workoutID == workoutID)
        #expect(snap.elapsedSeconds == 600)
        #expect(snap.totalExercises == 3)
        #expect(snap.completedExercises == 1)
        #expect(snap.currentExerciseName == "Bench")
        #expect(snap.completedSetsInCurrentExercise == 2)
        #expect(snap.totalSetsInCurrentExercise == 4)
        #expect(snap.sessionLabel == "W1 · S1")
        #expect(snap.programWeekNumber == 1)
        #expect(snap.programSessionNumber == 1)
    }

    @Test func liveWorkoutSnapshotClampsNegativeElapsed() {
        let snap = WatchPayloadMapper.makeLiveWorkoutSnapshot(
            workoutID: UUID(),
            elapsedSeconds: -50,
            entries: [],
            sessionLabel: "Training"
        )
        #expect(snap.elapsedSeconds == 0)
        #expect(snap.totalExercises == 0)
        #expect(snap.completedExercises == 0)
    }

    @Test func liveWorkoutSnapshotTreatsCompletedCardioAsDone() {
        var cardio = DraftExerciseEntry(
            exerciseName: "Row",
            unit: .lbs,
            orderIndex: 0,
            sets: [],
            isCardio: true,
            cardioMinutesText: "15",
            cardioSecondsText: "0"
        )
        _ = cardio // silence unused warning if any
        let snap = WatchPayloadMapper.makeLiveWorkoutSnapshot(
            workoutID: UUID(),
            elapsedSeconds: 900,
            entries: [cardio],
            sessionLabel: "Recovery"
        )
        #expect(snap.completedExercises == 1)
    }

    // MARK: - Progress Snapshot Parity

    @Test func progressSnapshotReportsSameCompletedCount() {
        let entries: [DraftExerciseEntry] = [
            makeCompletedEntry(name: "Squat", orderIndex: 0, sets: 3),
            makeCompletedEntry(name: "Bench", orderIndex: 1, sets: 3),
            makeEmptyEntry(name: "Row", orderIndex: 2, sets: 3)
        ]
        let progress = WatchPayloadMapper.makeProgressSnapshot(
            workoutID: UUID(),
            elapsedSeconds: 300,
            entries: entries
        )
        #expect(progress.totalExercises == 3)
        #expect(progress.completedExercises == 2)
    }

    // MARK: - Coordinator Broadcasts

    @Test func coordinatorBroadcastsLaunchProgressAndLiveSnapshot() async {
        let bridge = MockWatchCompanionBridge()
        let coordinator = WatchSessionCoordinator(bridge: bridge)

        let workoutID = UUID()
        let started = Date(timeIntervalSince1970: 1_700_200_000)
        await coordinator.broadcastWorkoutLaunch(
            workoutID: workoutID,
            startedAt: started,
            programRunID: nil,
            programWeekNumber: 2,
            programSessionNumber: 1
        )
        #expect(bridge.launchPayloads.count == 1)
        #expect(bridge.launchPayloads.first?.workoutID == workoutID)
        #expect(bridge.launchPayloads.first?.programWeekNumber == 2)

        let entries: [DraftExerciseEntry] = [
            makeCompletedEntry(name: "Squat", orderIndex: 0, sets: 3),
            makePartialEntry(name: "Bench", orderIndex: 1, totalSets: 3, loggedSets: 1)
        ]
        await coordinator.broadcastLiveWorkout(
            workoutID: workoutID,
            elapsedSeconds: 420,
            entries: entries,
            sessionLabel: "W2 · S1",
            programWeekNumber: 2,
            programSessionNumber: 1
        )
        #expect(bridge.progressSnapshots.count == 1)
        #expect(bridge.progressSnapshots.first?.completedExercises == 1)
        #expect(bridge.liveSnapshots.count == 1)
        let live = try! unwrap(bridge.liveSnapshots.first)
        #expect(live.currentExerciseName == "Bench")
        #expect(live.completedSetsInCurrentExercise == 1)
        #expect(live.totalSetsInCurrentExercise == 3)
    }

    @Test func coordinatorBroadcastsTodayPlanSnapshot() async {
        let bridge = MockWatchCompanionBridge()
        let coordinator = WatchSessionCoordinator(bridge: bridge)

        let plan = makePlan(
            confidence: .high,
            compact: "Run as planned",
            primary: "Execute the scheduled session",
            readiness: .strong,
            nextProgramSession: NextProgramSessionInfo(
                weekNumber: 1, sessionNumber: 1, sessionName: "Upper A", programName: "Test"
            ),
            activeSourceLabels: ["Manual Check-In", "Program"]
        )
        await coordinator.broadcastTodayPlan(plan)

        #expect(bridge.todayPlanSnapshots.count == 1)
        let snap = try! unwrap(bridge.todayPlanSnapshots.first)
        #expect(snap.confidence == "High")
        #expect(snap.sessionLabel.contains("W1"))
        #expect(snap.sessionLabel.contains("Upper A"))
    }

    @Test func coordinatorBroadcastsCurrentSessionContext() async {
        let bridge = MockWatchCompanionBridge()
        let coordinator = WatchSessionCoordinator(bridge: bridge)
        let entries: [DraftExerciseEntry] = [
            makePartialEntry(name: "OHP", orderIndex: 0, totalSets: 3, loggedSets: 0)
        ]
        await coordinator.broadcastCurrentSessionContext(
            workoutID: UUID(),
            entries: entries
        )
        #expect(bridge.sessionContexts.count == 1)
        #expect(bridge.sessionContexts.first?.exerciseName == "OHP")
    }

    @Test func coordinatorSkipsCurrentSessionContextWhenEntriesEmpty() async {
        let bridge = MockWatchCompanionBridge()
        let coordinator = WatchSessionCoordinator(bridge: bridge)
        await coordinator.broadcastCurrentSessionContext(
            workoutID: UUID(),
            entries: []
        )
        #expect(bridge.sessionContexts.isEmpty)
    }

    // MARK: - Helpers

    private func unwrap<T>(_ value: T?) throws -> T {
        guard let v = value else { throw WatchFoundationUnwrapError.nilValue }
        return v
    }

    // MARK: Draft factories

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

    // MARK: TodayPlan factory

    private func makePlan(
        confidence: TodayPlanConfidence,
        compact: String,
        primary: String,
        readiness: ReadinessTier,
        hasPainFlag: Bool = false,
        nextProgramSession: NextProgramSessionInfo? = nil,
        standaloneSessionType: StandaloneSessionType? = nil,
        pendingProposalCount: Int = 0,
        activeSourceLabels: [String] = [],
        whatChanged: String = "",
        adherenceRescue: AdherenceRescue? = nil
    ) -> TodayPlan {
        let recommendation = DailyCoachRecommendation(
            compactSummary: compact,
            expandedDetails: "Details",
            primarySuggestion: DailyCoachSuggestionItem(
                type: .runAsPlanned, compactText: primary, expandedText: "Expanded"
            ),
            secondarySuggestions: [],
            readinessTier: readiness,
            hasPainFlag: hasPainFlag,
            nextProgramSession: nextProgramSession,
            standaloneSessionType: standaloneSessionType,
            pendingProposalCount: pendingProposalCount,
            objectiveRecoveryInsight: nil,
            recommendationSources: [],
            sourceAttributionDetails: ""
        )
        let attribution = TodayPlanSourceAttribution(
            manualReadinessInfluence: "",
            healthKitInfluence: "",
            programPrescriptionInfluence: "",
            adaptiveOverlayInfluence: "",
            recentHistoryInfluence: "",
            activeSourceLabels: activeSourceLabels,
            influenceFlags: TodayPlanInfluenceFlags(
                usedActiveProgramContext: nextProgramSession != nil,
                usedApprovedOverlayContext: false,
                usedPendingProposalContext: pendingProposalCount > 0,
                usedRuntimeCoachAdjustment: false,
                usedRecentHistoryContext: true,
                usedHealthKitRecoveryNudge: false
            )
        )
        let changeSummary = TodayPlanChangeSummary(
            changeType: whatChanged.isEmpty ? .noChanges : .runtimeOnlyAdjustment,
            headline: whatChanged.isEmpty ? "No notable changes from baseline." : "Runtime Daily Coach adjustments are active.",
            details: whatChanged.isEmpty ? [] : [whatChanged]
        )
        return TodayPlan(
            recommendation: recommendation,
            objectiveRecoveryEvaluation: .disabled(),
            confidence: confidence,
            confidenceRationale: "Rationale",
            attribution: attribution,
            adherenceRescue: adherenceRescue,
            whyToday: "Why",
            whatChangedToday: whatChanged,
            changeSummary: changeSummary,
            proposalAwareness: [],
            nextStepGuidance: TodayPlanNextStepGuidance(
                contextMode: nextProgramSession != nil ? .activeProgram : .standaloneHistoryInformed,
                headline: "Next",
                actions: []
            )
        )
    }
}

// MARK: - Helper Error

private enum WatchFoundationUnwrapError: Error {
    case nilValue
}

// MARK: - MockWatchCompanionBridge

@MainActor
final class MockWatchCompanionBridge: WatchCompanionBridge {
    var latestStatus: WatchCompanionStatus = .unsupported()
    var executionActionHandler: WatchExecutionActionHandler?
    var launchPayloads: [WatchWorkoutLaunchPayload] = []
    var progressSnapshots: [WatchWorkoutProgressSnapshot] = []
    var todayPlanSnapshots: [WatchTodayPlanSnapshot] = []
    var liveSnapshots: [WatchLiveWorkoutSnapshot] = []
    var sessionContexts: [WatchCurrentSessionContext] = []
    var sessionCompletions: [WatchSessionCompletionPayload] = []

    func refreshStatus() async -> WatchCompanionStatus {
        latestStatus
    }

    func sendWorkoutLaunch(_ payload: WatchWorkoutLaunchPayload) async {
        launchPayloads.append(payload)
    }

    func sendWorkoutProgress(_ snapshot: WatchWorkoutProgressSnapshot) async {
        progressSnapshots.append(snapshot)
    }

    func sendTodayPlanSnapshot(_ snapshot: WatchTodayPlanSnapshot) async {
        todayPlanSnapshots.append(snapshot)
    }

    func sendLiveWorkoutSnapshot(_ snapshot: WatchLiveWorkoutSnapshot) async {
        liveSnapshots.append(snapshot)
    }

    func sendCurrentSessionContext(_ context: WatchCurrentSessionContext) async {
        sessionContexts.append(context)
    }

    func sendSessionCompletion(_ payload: WatchSessionCompletionPayload) async {
        sessionCompletions.append(payload)
    }
}
