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

struct WatchSetCompletionAdvanceResult {
    var updatedEntries: [DraftExerciseEntry]
    var completedExerciseIndex: Int
    var completedSetNumber: Int
    var nextExerciseIndex: Int?
    var nextSetNumber: Int?
    var didAdvanceExercise: Bool
    var isSessionComplete: Bool
}

enum WatchWorkoutExecutionActionApplyStatus: Equatable {
    case applied
    case ignoredEmptyDraft
    case ignoredUnsupportedSchema
    case ignoredIncompatibleAction
    case ignoredStaleCursor
}

struct WatchWorkoutExecutionActionApplyResult: Equatable {
    var status: WatchWorkoutExecutionActionApplyStatus
    var updatedEntries: [DraftExerciseEntry]

    var didApply: Bool {
        status == .applied
    }
}

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
    /// wire shape while accepting richer source inputs. Prompt 5 adds
    /// `sessionPlanKind`, `sessionSourceLabels`, and `sessionVersionStableID`
    /// so the watch surface can render "Planned" vs "Adjusted" sessions
    /// without re-deriving attribution.
    static func makeLaunchPayload(
        workoutID: UUID,
        startedAt: Date,
        programRunID: UUID? = nil,
        programWeekNumber: Int? = nil,
        programSessionNumber: Int? = nil,
        sessionPlanKind: WatchSessionPlanKind? = nil,
        sessionSourceLabels: [String]? = nil,
        sessionVersionStableID: String? = nil
    ) -> WatchWorkoutLaunchPayload {
        WatchWorkoutLaunchPayload(
            workoutID: workoutID,
            startedAt: startedAt,
            programRunID: programRunID,
            programWeekNumber: programWeekNumber,
            programSessionNumber: programSessionNumber,
            sessionPlanKind: sessionPlanKind,
            sessionSourceLabels: normalizeSourceLabels(sessionSourceLabels),
            sessionVersionStableID: sessionVersionStableID
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
        sessionPlanKind: WatchSessionPlanKind? = nil,
        sessionSourceLabels: [String]? = nil,
        sessionVersionStableID: String? = nil,
        crownWeightStepOverride: Double? = nil,
        capturedAt: Date = Date()
    ) -> WatchCurrentSessionContext? {
        guard !entries.isEmpty else { return nil }
        let index = resolveCurrentExerciseIndex(entries: entries, cursor: cursor)

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
        let lastCompletedSet = entry.sets.last(where: { isSetLogged($0) })

        let crownWeightStep = crownWeightStepOverride ?? preferredCrownWeightStep(unitLabel: entry.prescribedWeightUnit ?? entry.unit.rawValue)
        let nextTargetSummary = makeTargetSummary(
            reps: reps ?? entry.prescribedTargetReps,
            weight: weight ?? entry.prescribedWeight,
            unit: entry.prescribedWeightUnit ?? entry.unit.rawValue,
            isCardio: entry.isCardio,
            cardioTargetSeconds: entry.cardioDurationSeconds
        )

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
            currentSetNumber: nextSetNumber,
            currentSetTargetSummary: nextTargetSummary,
            currentSetCompletedWeight: lastCompletedSet.flatMap { Double($0.weightText) },
            currentSetCompletedReps: lastCompletedSet.flatMap { Int($0.repsText) },
            crownWeightStep: entry.isCardio ? nil : crownWeightStep,
            quickCompleteEnabled: entry.isCardio ? nil : nextSetIdx != nil,
            preferredInteractionModel: entry.isCardio ? nil : .digitalCrownFirst,
            sessionPlanKind: sessionPlanKind,
            sessionSourceLabels: normalizeSourceLabels(sessionSourceLabels),
            sessionVersionStableID: sessionVersionStableID,
            capturedAt: capturedAt
        )
    }

    // MARK: Live Workout Snapshot

    /// Build a richer live workout snapshot from an in-progress draft. Prompt 5
    /// attaches the live session-plan-kind and source labels so the watch
    /// reflects planned/overlay/runtime attribution as progress streams.
    static func makeLiveWorkoutSnapshot(
        workoutID: UUID,
        elapsedSeconds: Int,
        entries: [DraftExerciseEntry],
        sessionLabel: String,
        programRunStableID: String? = nil,
        programWeekNumber: Int? = nil,
        programSessionNumber: Int? = nil,
        sessionPlanKind: WatchSessionPlanKind? = nil,
        sessionSourceLabels: [String]? = nil,
        sessionVersionStableID: String? = nil,
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
            sessionPlanKind: sessionPlanKind,
            sessionSourceLabels: normalizeSourceLabels(sessionSourceLabels),
            sessionVersionStableID: sessionVersionStableID,
            capturedAt: capturedAt
        )
    }

    // MARK: Session Completion Payload

    /// Build the terminal "session completed" payload from a finished draft.
    /// All counts are derived directly from the final draft list so the watch
    /// handoff agrees with the iPhone's saved workout.
    static func makeSessionCompletionPayload(
        workoutID: UUID,
        completedAt: Date,
        totalElapsedSeconds: Int,
        entries: [DraftExerciseEntry],
        sessionLabel: String,
        sessionPlanKind: WatchSessionPlanKind? = nil,
        sessionSourceLabels: [String]? = nil,
        sessionVersionStableID: String? = nil,
        newPersonalRecordCount: Int = 0
    ) -> WatchSessionCompletionPayload {
        let totalExercises = entries.count
        let completedExercises = entries.filter { isExerciseComplete($0) }.count
        let totalSets = entries.reduce(into: 0) { running, entry in
            running += entry.isCardio ? 0 : entry.sets.count
        }
        let completedSets = entries.reduce(into: 0) { running, entry in
            if entry.isCardio {
                running += isExerciseComplete(entry) ? 1 : 0
            } else {
                running += entry.sets.filter { isSetLogged($0) }.count
            }
        }
        return WatchSessionCompletionPayload(
            workoutID: workoutID,
            completedAt: completedAt,
            totalElapsedSeconds: max(0, totalElapsedSeconds),
            completedExercises: completedExercises,
            totalExercises: totalExercises,
            completedSets: completedSets,
            totalSets: totalSets,
            sessionLabel: sessionLabel,
            sessionPlanKind: sessionPlanKind,
            sessionSourceLabels: normalizeSourceLabels(sessionSourceLabels),
            sessionVersionStableID: sessionVersionStableID,
            newPersonalRecordCount: max(0, newPersonalRecordCount)
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

    // MARK: Crown-first Weight Entry Helpers

    /// Applies digital-crown ticks to a weight value. Keeps deterministic,
    /// snap-to-step behavior so watch-side interactions stay fast and stable.
    static func applyCrownTicksToWeight(
        currentWeight: Double?,
        ticks: Int,
        unitLabel: String?,
        stepOverride: Double? = nil,
        minWeight: Double = 0,
        maxWeight: Double = 1_000
    ) -> Double {
        let step = max(0.1, stepOverride ?? preferredCrownWeightStep(unitLabel: unitLabel))
        let base = max(minWeight, currentWeight ?? 0)
        let adjusted = base + (Double(ticks) * step)
        let clamped = min(maxWeight, max(minWeight, adjusted))
        return snappedWeight(clamped, step: step)
    }

    /// Applies crown ticks to the current in-progress set on the selected
    /// exercise and returns updated draft entries.
    static func applyCrownTicksToCurrentSet(
        entries: [DraftExerciseEntry],
        cursor: Int? = nil,
        ticks: Int,
        stepOverride: Double? = nil
    ) -> [DraftExerciseEntry] {
        guard !entries.isEmpty else { return entries }
        var updated = entries
        let exerciseIndex = resolveCurrentExerciseIndex(entries: entries, cursor: cursor)
        guard updated.indices.contains(exerciseIndex) else { return entries }
        guard !updated[exerciseIndex].isCardio else { return entries }
        guard let setIndex = updated[exerciseIndex].sets.firstIndex(where: { !isSetLogged($0) }) else { return entries }

        let entry = updated[exerciseIndex]
        let existingWeight = Double(entry.sets[setIndex].weightText) ?? entry.prescribedWeight
        let adjusted = applyCrownTicksToWeight(
            currentWeight: existingWeight,
            ticks: ticks,
            unitLabel: entry.prescribedWeightUnit ?? entry.unit.rawValue,
            stepOverride: stepOverride
        )
        updated[exerciseIndex].sets[setIndex].weightText = formatWeight(adjusted)
        return updated
    }

    /// Applies digital-crown ticks to reps for the current unlogged set. Reps
    /// stay integer and bounded so watch input cannot create invalid draft
    /// text.
    static func applyCrownTicksToCurrentSetReps(
        entries: [DraftExerciseEntry],
        cursor: Int? = nil,
        ticks: Int,
        minReps: Int = 0,
        maxReps: Int = 100
    ) -> [DraftExerciseEntry] {
        guard !entries.isEmpty else { return entries }
        var updated = entries
        let exerciseIndex = resolveCurrentExerciseIndex(entries: entries, cursor: cursor)
        guard updated.indices.contains(exerciseIndex) else { return entries }
        guard !updated[exerciseIndex].isCardio else { return entries }
        guard let setIndex = updated[exerciseIndex].sets.firstIndex(where: { !isSetLogged($0) }) else { return entries }

        let entry = updated[exerciseIndex]
        let existingReps = Int(entry.sets[setIndex].repsText) ?? entry.prescribedTargetReps ?? 0
        let adjusted = min(maxReps, max(minReps, existingReps + ticks))
        updated[exerciseIndex].sets[setIndex].repsText = adjusted > 0 ? "\(adjusted)" : ""
        return updated
    }

    /// Marks the current cardio block complete without inventing new duration
    /// values. Duration remains whatever the phone draft already contains.
    static func markCurrentCardioBlockComplete(
        entries: [DraftExerciseEntry],
        cursor: Int? = nil
    ) -> [DraftExerciseEntry] {
        guard !entries.isEmpty else { return entries }
        var updated = entries
        let exerciseIndex = resolveCurrentExerciseIndex(entries: entries, cursor: cursor)
        guard updated.indices.contains(exerciseIndex), updated[exerciseIndex].isCardio else { return entries }
        updated[exerciseIndex].cardioCompletionLogged = true
        return updated
    }

    /// Applies a watch-originated execution command to draft entries only. The
    /// phone caller owns persistence and broadcasting after this pure transform.
    static func applyExecutionAction(
        _ action: WatchWorkoutExecutionActionDTO,
        to entries: [DraftExerciseEntry],
        cursor: Int? = nil
    ) -> WatchWorkoutExecutionActionApplyResult {
        guard action.actionSchemaVersion <= WatchPayloadContractVersion.current else {
            return WatchWorkoutExecutionActionApplyResult(status: .ignoredUnsupportedSchema, updatedEntries: entries)
        }
        guard !entries.isEmpty else {
            return WatchWorkoutExecutionActionApplyResult(status: .ignoredEmptyDraft, updatedEntries: entries)
        }

        let exerciseIndex = resolveCurrentExerciseIndex(entries: entries, cursor: cursor)
        guard cursorMatches(action: action, entries: entries, exerciseIndex: exerciseIndex) else {
            return WatchWorkoutExecutionActionApplyResult(status: .ignoredStaleCursor, updatedEntries: entries)
        }

        let updatedEntries: [DraftExerciseEntry]
        switch action.actionKind {
        case .applyCrownTicksToCurrentSetWeight:
            guard let ticks = action.ticks, ticks != 0 else {
                return WatchWorkoutExecutionActionApplyResult(status: .ignoredIncompatibleAction, updatedEntries: entries)
            }
            updatedEntries = applyCrownTicksToCurrentSet(entries: entries, cursor: exerciseIndex, ticks: ticks)
        case .applyCrownTicksToCurrentSetReps:
            guard let ticks = action.ticks, ticks != 0 else {
                return WatchWorkoutExecutionActionApplyResult(status: .ignoredIncompatibleAction, updatedEntries: entries)
            }
            updatedEntries = applyCrownTicksToCurrentSetReps(entries: entries, cursor: exerciseIndex, ticks: ticks)
        case .completeCurrentSet:
            guard let result = completeCurrentSetAndAdvance(
                entries: entries,
                cursor: exerciseIndex,
                completedWeight: action.completedWeight,
                completedReps: action.completedReps
            ) else {
                return WatchWorkoutExecutionActionApplyResult(status: .ignoredIncompatibleAction, updatedEntries: entries)
            }
            updatedEntries = result.updatedEntries
        case .completeCardioBlock:
            updatedEntries = markCurrentCardioBlockComplete(entries: entries, cursor: exerciseIndex)
        }

        guard updatedEntries != entries else {
            return WatchWorkoutExecutionActionApplyResult(status: .ignoredIncompatibleAction, updatedEntries: entries)
        }
        return WatchWorkoutExecutionActionApplyResult(status: .applied, updatedEntries: updatedEntries)
    }

    // MARK: Set Completion + Advance

    /// Completes the current set and returns the updated draft plus next cursor
    /// coordinates, enabling one-tap "complete + advance" watch behavior.
    static func completeCurrentSetAndAdvance(
        entries: [DraftExerciseEntry],
        cursor: Int? = nil,
        completedWeight: Double? = nil,
        completedReps: Int? = nil,
        completedAt: Date = Date()
    ) -> WatchSetCompletionAdvanceResult? {
        guard !entries.isEmpty else { return nil }
        var updated = entries
        let exerciseIndex = resolveCurrentExerciseIndex(entries: entries, cursor: cursor)
        guard updated.indices.contains(exerciseIndex) else { return nil }
        guard !updated[exerciseIndex].isCardio else { return nil }
        guard let setIndex = updated[exerciseIndex].sets.firstIndex(where: { !isSetLogged($0) }) else { return nil }

        let entry = updated[exerciseIndex]
        let setNumber = entry.sets[setIndex].setNumber
        let reps = completedReps ?? Int(entry.sets[setIndex].repsText) ?? entry.prescribedTargetReps ?? 0
        let weight = completedWeight
            ?? Double(entry.sets[setIndex].weightText)
            ?? entry.prescribedWeight
            ?? 0

        updated[exerciseIndex].sets[setIndex].repsText = reps > 0 ? "\(reps)" : ""
        updated[exerciseIndex].sets[setIndex].weightText = weight > 0 ? formatWeight(weight) : ""
        updated[exerciseIndex].sets[setIndex].completionLoggedAt = completedAt
        updated[exerciseIndex].sets[setIndex].isPrefilledFromPrescription = false

        let nextExerciseIndex = updated.firstIndex(where: { !isExerciseComplete($0) })
        let nextSetNumber: Int? = {
            guard let idx = nextExerciseIndex else { return nil }
            return updated[idx].sets.first(where: { !isSetLogged($0) })?.setNumber
        }()

        return WatchSetCompletionAdvanceResult(
            updatedEntries: updated,
            completedExerciseIndex: exerciseIndex,
            completedSetNumber: setNumber,
            nextExerciseIndex: nextExerciseIndex,
            nextSetNumber: nextSetNumber,
            didAdvanceExercise: nextExerciseIndex != nil && nextExerciseIndex != exerciseIndex,
            isSessionComplete: nextExerciseIndex == nil
        )
    }

    // MARK: Draft Completion Helpers

    static func isExerciseComplete(_ entry: DraftExerciseEntry) -> Bool {
        if entry.isCardio {
            return entry.cardioCompletionLogged ?? (entry.cardioDurationSeconds > 0)
        }
        guard !entry.sets.isEmpty else { return false }
        return entry.sets.allSatisfy { isSetLogged($0) }
    }

    static func isSetLogged(_ set: DraftSet) -> Bool {
        if set.completionLoggedAt != nil {
            return true
        }
        guard !set.repsText.isEmpty && !set.weightText.isEmpty else { return false }
        return set.isPrefilledFromPrescription != true
    }

    private static func resolveCurrentExerciseIndex(entries: [DraftExerciseEntry], cursor: Int?) -> Int {
        if let cursor, entries.indices.contains(cursor) {
            return cursor
        }
        if let firstIncomplete = entries.firstIndex(where: { !isExerciseComplete($0) }) {
            return firstIncomplete
        }
        return max(0, entries.count - 1)
    }

    private static func cursorMatches(
        action: WatchWorkoutExecutionActionDTO,
        entries: [DraftExerciseEntry],
        exerciseIndex: Int
    ) -> Bool {
        guard entries.indices.contains(exerciseIndex) else { return false }
        if let actionExerciseIndex = action.exerciseIndex, actionExerciseIndex != exerciseIndex {
            return false
        }

        guard !entries[exerciseIndex].isCardio else {
            return action.setNumber == nil
        }

        guard let setIndex = entries[exerciseIndex].sets.firstIndex(where: { !isSetLogged($0) }) else {
            return false
        }
        if let actionSetNumber = action.setNumber,
           actionSetNumber != entries[exerciseIndex].sets[setIndex].setNumber {
            return false
        }
        return true
    }

    private static func preferredCrownWeightStep(unitLabel: String?) -> Double {
        let label = (unitLabel ?? "").lowercased()
        if label == "kg" || label == "kgs" || label == "kilogram" || label == "kilograms" {
            return 2.5
        }
        return 5.0
    }

    private static func snappedWeight(_ value: Double, step: Double) -> Double {
        guard step > 0 else { return value }
        return (value / step).rounded() * step
    }

    private static func formatWeight(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }

    /// Trim + drop empty entries so source-attribution arrays stay compact
    /// and watch rendering never shows a dangling " · ".
    static func normalizeSourceLabels(_ labels: [String]?) -> [String]? {
        guard let labels else { return nil }
        let cleaned = labels
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func makeTargetSummary(
        reps: Int?,
        weight: Double?,
        unit: String?,
        isCardio: Bool,
        cardioTargetSeconds: Int
    ) -> String? {
        if isCardio {
            guard cardioTargetSeconds > 0 else { return nil }
            let minutes = cardioTargetSeconds / 60
            let seconds = cardioTargetSeconds % 60
            return seconds == 0 ? "\(minutes)m cardio target" : "\(minutes)m \(seconds)s cardio target"
        }

        guard reps != nil || weight != nil else { return nil }
        var parts: [String] = []
        if let reps {
            parts.append("\(reps) reps")
        }
        if let weight {
            if let unit, !unit.isEmpty {
                parts.append("@ \(formatWeight(weight)) \(unit)")
            } else {
                parts.append("@ \(formatWeight(weight))")
            }
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - WatchSessionCoordinator

/// Thin façade that owns the bridge and forwards typed broadcasts. Main-actor
/// bound to match `DefaultWatchCompanionBridge`. All synthesis happens inside
/// `WatchPayloadMapper`, keeping this type trivially replaceable in tests.
@MainActor
final class WatchSessionCoordinator {
    static let shared = WatchSessionCoordinator(bridge: DefaultWatchCompanionBridge.shared)

    private var bridge: WatchCompanionBridge

    init(bridge: WatchCompanionBridge? = nil) {
        self.bridge = bridge ?? DefaultWatchCompanionBridge.shared
    }

    func installExecutionActionHandler(activeWorkoutSessionStore: ActiveWorkoutSessionStore) {
        bridge.executionActionHandler = { [weak activeWorkoutSessionStore, weak self] action in
            guard let activeWorkoutSessionStore, let self else { return }
            _ = activeWorkoutSessionStore.applyWatchExecutionAction(action)
            guard let session = activeWorkoutSessionStore.session,
                  session.id == action.workoutID else {
                return
            }
            Task { @MainActor in
                await self.broadcastActiveSessionState(session)
            }
        }
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
        programSessionNumber: Int? = nil,
        sessionPlanKind: WatchSessionPlanKind? = nil,
        sessionSourceLabels: [String]? = nil,
        sessionVersionStableID: String? = nil
    ) async {
        let payload = WatchPayloadMapper.makeLaunchPayload(
            workoutID: workoutID,
            startedAt: startedAt,
            programRunID: programRunID,
            programWeekNumber: programWeekNumber,
            programSessionNumber: programSessionNumber,
            sessionPlanKind: sessionPlanKind,
            sessionSourceLabels: sessionSourceLabels,
            sessionVersionStableID: sessionVersionStableID
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
        sessionPlanKind: WatchSessionPlanKind? = nil,
        sessionSourceLabels: [String]? = nil,
        sessionVersionStableID: String? = nil,
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
            sessionPlanKind: sessionPlanKind,
            sessionSourceLabels: sessionSourceLabels,
            sessionVersionStableID: sessionVersionStableID,
            capturedAt: capturedAt
        )
        await bridge.sendLiveWorkoutSnapshot(live)
    }

    // MARK: Current Session Context

    func broadcastCurrentSessionContext(
        workoutID: UUID,
        entries: [DraftExerciseEntry],
        cursor: Int? = nil,
        sessionPlanKind: WatchSessionPlanKind? = nil,
        sessionSourceLabels: [String]? = nil,
        sessionVersionStableID: String? = nil,
        capturedAt: Date = Date()
    ) async {
        guard let context = WatchPayloadMapper.makeCurrentSessionContext(
            workoutID: workoutID,
            entries: entries,
            cursor: cursor,
            sessionPlanKind: sessionPlanKind,
            sessionSourceLabels: sessionSourceLabels,
            sessionVersionStableID: sessionVersionStableID,
            capturedAt: capturedAt
        ) else { return }
        await bridge.sendCurrentSessionContext(context)
    }

    func broadcastActiveSessionState(
        _ session: ActiveWorkoutSession,
        capturedAt: Date = Date()
    ) async {
        let elapsedSeconds = Int(capturedAt.timeIntervalSince(session.startTime))
        let label = activeSessionLabel(for: session)
        await broadcastLiveWorkout(
            workoutID: session.id,
            elapsedSeconds: elapsedSeconds,
            entries: session.exerciseEntries,
            sessionLabel: label,
            programRunStableID: session.programRunStableID,
            programWeekNumber: session.programContext?.weekNumber,
            programSessionNumber: session.programContext?.sessionNumber,
            sessionPlanKind: session.sessionPlanKind,
            sessionSourceLabels: session.sessionSourceLabels,
            sessionVersionStableID: session.sessionVersionStableID,
            capturedAt: capturedAt
        )
        await broadcastCurrentSessionContext(
            workoutID: session.id,
            entries: session.exerciseEntries,
            sessionPlanKind: session.sessionPlanKind,
            sessionSourceLabels: session.sessionSourceLabels,
            sessionVersionStableID: session.sessionVersionStableID,
            capturedAt: capturedAt
        )
    }

    // MARK: Session Completion Handoff

    /// Terminal broadcast sent after a workout is saved. Lets watch execution
    /// close its live screen and celebrate PRs while staying fully decoupled
    /// from any SwiftData lifecycle.
    func broadcastSessionCompletion(
        workoutID: UUID,
        completedAt: Date,
        totalElapsedSeconds: Int,
        entries: [DraftExerciseEntry],
        sessionLabel: String,
        sessionPlanKind: WatchSessionPlanKind? = nil,
        sessionSourceLabels: [String]? = nil,
        sessionVersionStableID: String? = nil,
        newPersonalRecordCount: Int = 0
    ) async {
        let payload = WatchPayloadMapper.makeSessionCompletionPayload(
            workoutID: workoutID,
            completedAt: completedAt,
            totalElapsedSeconds: totalElapsedSeconds,
            entries: entries,
            sessionLabel: sessionLabel,
            sessionPlanKind: sessionPlanKind,
            sessionSourceLabels: sessionSourceLabels,
            sessionVersionStableID: sessionVersionStableID,
            newPersonalRecordCount: newPersonalRecordCount
        )
        await bridge.sendSessionCompletion(payload)
    }

    private func activeSessionLabel(for session: ActiveWorkoutSession) -> String {
        if let programContext = session.programContext {
            return "W\(programContext.weekNumber) · S\(programContext.sessionNumber)"
        }
        if session.sessionSourceLabels?.contains("SuggestMeSome Generated") == true {
            return "Suggested workout"
        }
        return "Active workout"
    }
}

private extension ActiveWorkoutSession {
    var programRunStableID: String? {
        programContext?.programRunStableID
    }
}
