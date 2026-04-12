//
//  WatchSessionCoordinator.swift
//  SuggestMeSome
//
//  Feature 10 Prompt 7 — iPhone-side coordinator that maps app state into
//  watch-safe payloads and hands them to the companion bridge.
//
//  All mapping logic lives in `WatchPayloadMapper` as pure, deterministic
//  static functions so validation tests can cover payload generation without
//  a real WatchConnectivity session. The `WatchSessionCoordinator` is a thin
//  `@MainActor` façade that owns the bridge and broadcasts on the main actor,
//  matching the existing `DefaultWatchCompanionBridge` isolation.
//
//  Coaching trust: the coordinator never synthesises its own plan. Today Plan
//  snapshots are derived verbatim from `TodayPlan` values produced by
//  `TodayPlanEngine`, so the watch surface stays faithful to the explainable
//  iPhone output.
//

import Foundation

// MARK: - WatchPayloadMapper

/// Pure, deterministic mapping layer. All functions are side-effect free so
/// they can be exercised directly in unit tests.
enum WatchPayloadMapper {

    // MARK: Today Plan

    /// Map a full `TodayPlan` into the compact watch snapshot.
    static func makeTodayPlanSnapshot(
        from plan: TodayPlan,
        programName: String? = nil,
        programRunStableID: String? = nil,
        generatedAt: Date = Date()
    ) -> WatchTodayPlanSnapshot {
        let rec = plan.recommendation

        let sessionLabel: String
        var programWeek: Int? = nil
        var programSession: Int? = nil
        if let info = rec.nextProgramSession {
            programWeek = info.weekNumber
            programSession = info.sessionNumber
            if let name = info.sessionName, !name.isEmpty {
                sessionLabel = "W\(info.weekNumber) · S\(info.sessionNumber) — \(name)"
            } else {
                sessionLabel = "W\(info.weekNumber) · S\(info.sessionNumber)"
            }
        } else if let standalone = rec.standaloneSessionType {
            sessionLabel = standalone.rawValue
        } else {
            sessionLabel = "Training"
        }

        let readinessLabel: String
        switch rec.readinessTier {
        case .strong:  readinessLabel = "Strong"
        case .neutral: readinessLabel = "Neutral"
        case .low:     readinessLabel = "Low"
        case .unknown: readinessLabel = "Unknown"
        }

        let rescue = plan.adherenceRescue
        let adherenceHeadline = rescue?.headline
        let adherenceGuidanceType = rescue?.guidanceType.rawValue
        let sessionsBehindCount = rescue?.sessionsBehindCount ?? 0

        return WatchTodayPlanSnapshot(
            confidence: plan.confidence.rawValue,
            compactSummary: rec.compactSummary,
            primarySuggestionText: rec.primarySuggestion.compactText,
            readinessTier: readinessLabel,
            hasPainFlag: rec.hasPainFlag,
            sessionLabel: sessionLabel,
            programName: programName ?? rec.nextProgramSession?.programName,
            programRunStableID: programRunStableID,
            programWeekNumber: programWeek,
            programSessionNumber: programSession,
            activeSourceLabels: plan.attribution.activeSourceLabels,
            whatChangedToday: plan.whatChangedToday,
            adherenceHeadline: adherenceHeadline,
            adherenceGuidanceType: adherenceGuidanceType,
            sessionsBehindCount: sessionsBehindCount,
            pendingProposalCount: rec.pendingProposalCount,
            generatedAt: generatedAt
        )
    }

    // MARK: Launch Payload

    /// Build a workout launch payload, preserving the existing Feature 8
    /// wire shape while accepting richer source inputs.
    static func makeLaunchPayload(
        workoutID: UUID,
        startedAt: Date,
        programRunID: UUID? = nil,
        programWeekNumber: Int? = nil,
        programSessionNumber: Int? = nil
    ) -> WatchWorkoutLaunchPayload {
        WatchWorkoutLaunchPayload(
            workoutID: workoutID,
            startedAt: startedAt,
            programRunID: programRunID,
            programWeekNumber: programWeekNumber,
            programSessionNumber: programSessionNumber
        )
    }

    // MARK: Current Session Context

    /// Compute the "current" exercise context from a draft list. Picks the
    /// first exercise whose sets are not all fully logged; falls back to the
    /// explicit index when every exercise is complete or the caller knows
    /// the cursor.
    static func makeCurrentSessionContext(
        workoutID: UUID,
        entries: [DraftExerciseEntry],
        cursor: Int? = nil,
        capturedAt: Date = Date()
    ) -> WatchCurrentSessionContext? {
        guard !entries.isEmpty else { return nil }
        let index: Int
        if let cursor, entries.indices.contains(cursor) {
            index = cursor
        } else if let firstIncomplete = entries.firstIndex(where: { !isExerciseComplete($0) }) {
            index = firstIncomplete
        } else {
            index = max(0, entries.count - 1)
        }

        let entry = entries[index]
        let totalSets = entry.sets.count
        let loggedSets = entry.sets.filter { isSetLogged($0) }.count
        let nextSetIdx = entry.sets.firstIndex(where: { !isSetLogged($0) })
        let nextSetNumber: Int? = nextSetIdx.map { entry.sets[$0].setNumber }

        let reps: Int? = {
            guard let idx = nextSetIdx else { return nil }
            return Int(entry.sets[idx].repsText)
        }()
        let weight: Double? = {
            guard let idx = nextSetIdx else { return nil }
            return Double(entry.sets[idx].weightText)
        }()

        return WatchCurrentSessionContext(
            workoutID: workoutID,
            exerciseIndex: index,
            exerciseName: entry.exerciseName,
            totalExercisesInSession: entries.count,
            totalSetsInExercise: totalSets,
            loggedSetsInExercise: loggedSets,
            nextSetNumber: nextSetNumber,
            nextPrescribedReps: reps ?? entry.prescribedTargetReps,
            nextPrescribedWeight: weight ?? entry.prescribedWeight,
            nextPrescribedWeightUnit: entry.prescribedWeightUnit ?? entry.unit.rawValue,
            isCardio: entry.isCardio,
            cardioTargetSeconds: entry.isCardio ? entry.cardioDurationSeconds : nil,
            capturedAt: capturedAt
        )
    }

    // MARK: Live Workout Snapshot

    /// Build a richer live workout snapshot from an in-progress draft.
    static func makeLiveWorkoutSnapshot(
        workoutID: UUID,
        elapsedSeconds: Int,
        entries: [DraftExerciseEntry],
        sessionLabel: String,
        programRunStableID: String? = nil,
        programWeekNumber: Int? = nil,
        programSessionNumber: Int? = nil,
        capturedAt: Date = Date()
    ) -> WatchLiveWorkoutSnapshot {
        let totalExercises = entries.count
        let completedExercises = entries.filter { isExerciseComplete($0) }.count
        let currentIndex = entries.firstIndex(where: { !isExerciseComplete($0) }) ?? max(0, totalExercises - 1)
        let current = entries.indices.contains(currentIndex) ? entries[currentIndex] : nil
        let currentTotalSets = current?.sets.count ?? 0
        let currentLoggedSets = current.map { $0.sets.filter { isSetLogged($0) }.count } ?? 0

        return WatchLiveWorkoutSnapshot(
            workoutID: workoutID,
            elapsedSeconds: max(0, elapsedSeconds),
            completedExercises: completedExercises,
            totalExercises: totalExercises,
            completedSetsInCurrentExercise: currentLoggedSets,
            totalSetsInCurrentExercise: currentTotalSets,
            currentExerciseName: current?.exerciseName,
            sessionLabel: sessionLabel,
            programRunStableID: programRunStableID,
            programWeekNumber: programWeekNumber,
            programSessionNumber: programSessionNumber,
            capturedAt: capturedAt
        )
    }

    // MARK: Progress (compact legacy shape)

    /// Build the minimal `WatchWorkoutProgressSnapshot` shape retained from
    /// Feature 8. Reused so both old and new listeners see consistent counts.
    static func makeProgressSnapshot(
        workoutID: UUID,
        elapsedSeconds: Int,
        entries: [DraftExerciseEntry],
        capturedAt: Date = Date()
    ) -> WatchWorkoutProgressSnapshot {
        let total = entries.count
        let completed = entries.filter { isExerciseComplete($0) }.count
        return WatchWorkoutProgressSnapshot(
            workoutID: workoutID,
            elapsedSeconds: max(0, elapsedSeconds),
            completedExercises: completed,
            totalExercises: total,
            capturedAt: capturedAt
        )
    }

    // MARK: Draft Completion Helpers

    static func isExerciseComplete(_ entry: DraftExerciseEntry) -> Bool {
        if entry.isCardio {
            return entry.cardioDurationSeconds > 0
        }
        guard !entry.sets.isEmpty else { return false }
        return entry.sets.allSatisfy { isSetLogged($0) }
    }

    static func isSetLogged(_ set: DraftSet) -> Bool {
        !set.repsText.isEmpty && !set.weightText.isEmpty
    }
}

// MARK: - WatchSessionCoordinator

/// Thin façade that owns the bridge and forwards typed broadcasts. Main-actor
/// bound to match `DefaultWatchCompanionBridge`. All synthesis happens inside
/// `WatchPayloadMapper`, keeping this type trivially replaceable in tests.
@MainActor
final class WatchSessionCoordinator {
    private let bridge: WatchCompanionBridge

    init(bridge: WatchCompanionBridge? = nil) {
        self.bridge = bridge ?? DefaultWatchCompanionBridge()
    }

    // MARK: Today Plan

    func broadcastTodayPlan(
        _ plan: TodayPlan,
        programName: String? = nil,
        programRunStableID: String? = nil,
        generatedAt: Date = Date()
    ) async {
        let snapshot = WatchPayloadMapper.makeTodayPlanSnapshot(
            from: plan,
            programName: programName,
            programRunStableID: programRunStableID,
            generatedAt: generatedAt
        )
        await bridge.sendTodayPlanSnapshot(snapshot)
    }

    // MARK: Workout Launch

    func broadcastWorkoutLaunch(
        workoutID: UUID,
        startedAt: Date,
        programRunID: UUID? = nil,
        programWeekNumber: Int? = nil,
        programSessionNumber: Int? = nil
    ) async {
        let payload = WatchPayloadMapper.makeLaunchPayload(
            workoutID: workoutID,
            startedAt: startedAt,
            programRunID: programRunID,
            programWeekNumber: programWeekNumber,
            programSessionNumber: programSessionNumber
        )
        await bridge.sendWorkoutLaunch(payload)
    }

    // MARK: Live Progress

    func broadcastLiveWorkout(
        workoutID: UUID,
        elapsedSeconds: Int,
        entries: [DraftExerciseEntry],
        sessionLabel: String,
        programRunStableID: String? = nil,
        programWeekNumber: Int? = nil,
        programSessionNumber: Int? = nil,
        capturedAt: Date = Date()
    ) async {
        let compact = WatchPayloadMapper.makeProgressSnapshot(
            workoutID: workoutID,
            elapsedSeconds: elapsedSeconds,
            entries: entries,
            capturedAt: capturedAt
        )
        await bridge.sendWorkoutProgress(compact)

        let live = WatchPayloadMapper.makeLiveWorkoutSnapshot(
            workoutID: workoutID,
            elapsedSeconds: elapsedSeconds,
            entries: entries,
            sessionLabel: sessionLabel,
            programRunStableID: programRunStableID,
            programWeekNumber: programWeekNumber,
            programSessionNumber: programSessionNumber,
            capturedAt: capturedAt
        )
        await bridge.sendLiveWorkoutSnapshot(live)
    }

    // MARK: Current Session Context

    func broadcastCurrentSessionContext(
        workoutID: UUID,
        entries: [DraftExerciseEntry],
        cursor: Int? = nil,
        capturedAt: Date = Date()
    ) async {
        guard let context = WatchPayloadMapper.makeCurrentSessionContext(
            workoutID: workoutID,
            entries: entries,
            cursor: cursor,
            capturedAt: capturedAt
        ) else { return }
        await bridge.sendCurrentSessionContext(context)
    }
}
