//
//  WatchPayloadContracts.swift
//  SuggestMeSome
//
//  Feature 10 Prompt 7 — Shared watch-safe payload contracts.
//
//  Transport-safe DTOs used by the iPhone ↔ watch companion bridge. These are
//  the stable shapes the watch companion app (present or future) consumes. They
//  intentionally mirror the sync-ready DTO approach from `SyncPayloadContracts`
//  so that future cloud sync and watch transport share the same versioning
//  discipline without diverging into one-off shapes.
//
//  Rules:
//  - No SwiftData imports, no model references. Pure value types.
//  - Codable + Equatable so the bridge can JSON-encode and compare.
//  - Every payload carries an explicit contract version via the envelope.
//  - Additive evolution only — new fields must be optional to preserve
//    backward compatibility with older watch builds.
//

import Foundation

// MARK: - Contract Version

enum WatchPayloadContractVersion {
    static let v1 = 1
    static let current = v1
}

// MARK: - Payload Kind

/// String-typed discriminator used in bridge message dictionaries so the watch
/// side can dispatch to the correct decoder without peeking at the payload.
enum WatchPayloadKind: String, Codable {
    case workoutLaunch
    case workoutProgress
    case todayPlanSnapshot
    case currentSessionContext
    case liveWorkoutSnapshot
    case sessionCompletion
    case workoutExecutionAction
}

// MARK: - Execution Interaction Types

/// Preferred logging interaction model for the current watch execution screen.
enum WatchExecutionInteractionModel: String, Codable, Equatable {
    case digitalCrownFirst
}

/// Origin classification for today's session so watch rendering can stay
/// compatible with planned sessions, approved-overlay versions, and runtime
/// Daily Coach adjustments. Mirrors `TodayPlanLaunchPath` on the iPhone so
/// source-of-truth attribution flows cleanly through the bridge.
enum WatchSessionPlanKind: String, Codable, Equatable {
    case planned
    case overlayAdjusted
    case runtimeAdjusted
}

/// Narrow, watch-originated live workout controls. These are intentionally
/// action verbs rather than broad patch shapes so the phone remains the source
/// of truth for draft state and persistence.
enum WatchWorkoutExecutionActionKind: String, Codable, Equatable {
    case applyCrownTicksToCurrentSetWeight
    case applyCrownTicksToCurrentSetReps
    case completeCurrentSet
    case completeCardioBlock
}

/// Versioned, transport-safe command DTO sent from watch -> iPhone during an
/// active workout. Optional cursor fields let the phone ignore stale actions
/// when the visible watch context no longer matches the active draft.
struct WatchWorkoutExecutionActionDTO: Codable, Equatable {
    var actionID: UUID
    var actionSchemaVersion: Int
    var workoutID: UUID
    var sessionVersionStableID: String?
    var actionKind: WatchWorkoutExecutionActionKind
    var exerciseIndex: Int?
    var setNumber: Int?
    var ticks: Int?
    var completedReps: Int?
    var completedWeight: Double?
    var createdAt: Date

    init(
        actionID: UUID = UUID(),
        actionSchemaVersion: Int = WatchPayloadContractVersion.current,
        workoutID: UUID,
        sessionVersionStableID: String? = nil,
        actionKind: WatchWorkoutExecutionActionKind,
        exerciseIndex: Int? = nil,
        setNumber: Int? = nil,
        ticks: Int? = nil,
        completedReps: Int? = nil,
        completedWeight: Double? = nil,
        createdAt: Date = Date()
    ) {
        self.actionID = actionID
        self.actionSchemaVersion = actionSchemaVersion
        self.workoutID = workoutID
        self.sessionVersionStableID = sessionVersionStableID
        self.actionKind = actionKind
        self.exerciseIndex = exerciseIndex
        self.setNumber = setNumber
        self.ticks = ticks
        self.completedReps = completedReps
        self.completedWeight = completedWeight
        self.createdAt = createdAt
    }
}

// MARK: - Envelope

/// Versioned wrapper used when bridging any watch payload over WatchConnectivity.
/// Kept intentionally separate from `SyncEnvelopeDTO` so cloud sync evolution
/// and watch transport evolution can diverge, while sharing the same idioms.
struct WatchPayloadEnvelope<Payload: Codable & Equatable>: Codable, Equatable {
    var schemaVersion: Int
    var kind: WatchPayloadKind
    var sentAt: Date
    var payload: Payload

    init(
        kind: WatchPayloadKind,
        payload: Payload,
        sentAt: Date = Date(),
        schemaVersion: Int = WatchPayloadContractVersion.current
    ) {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.sentAt = sentAt
        self.payload = payload
    }
}

// MARK: - Today Plan Snapshot

/// Watch-facing summary of a TodayPlan. Purely display-facing; coaching
/// decisions remain on iPhone inside `TodayPlanEngine` — the watch never
/// invents its own plan, it only renders this snapshot.
struct WatchTodayPlanSnapshot: Codable, Equatable {
    var confidence: String               // "High" / "Medium" / "Low"
    var compactSummary: String
    var primarySuggestionText: String
    var readinessTier: String            // "Strong" / "Neutral" / "Low" / "Unknown"
    var hasPainFlag: Bool
    var sessionLabel: String             // short label for the session (watch-safe)
    var programName: String?
    var programRunStableID: String? = nil
    var programWeekNumber: Int?
    var programSessionNumber: Int?
    var activeSourceLabels: [String]
    var whatChangedToday: String         // may be empty
    var adherenceHeadline: String?       // non-nil when adherence rescue is active
    var adherenceGuidanceType: String?   // non-nil when adherence rescue is active
    var sessionsBehindCount: Int         // 0 when on track
    var pendingProposalCount: Int
    var generatedAt: Date
}

// MARK: - Current Session Context

/// Point-in-time view of the current exercise + set the user is working on.
/// Updated continuously during a live workout so the watch can show the
/// right thing when the user glances at it.
struct WatchCurrentSessionContext: Codable, Equatable {
    var workoutID: UUID
    var exerciseIndex: Int               // 0-based position in the draft list
    var exerciseName: String
    var totalExercisesInSession: Int
    var totalSetsInExercise: Int
    var loggedSetsInExercise: Int        // how many sets already have reps+weight
    var nextSetNumber: Int?              // 1-based number of the next set to log, nil when done
    var nextPrescribedReps: Int?
    var nextPrescribedWeight: Double?
    var nextPrescribedWeightUnit: String?
    var isCardio: Bool
    var cardioTargetSeconds: Int?
    var currentSetNumber: Int? = nil
    var currentSetTargetSummary: String? = nil
    var currentSetCompletedWeight: Double? = nil
    var currentSetCompletedReps: Int? = nil
    var crownWeightStep: Double? = nil
    var quickCompleteEnabled: Bool? = nil
    var preferredInteractionModel: WatchExecutionInteractionModel? = nil
    var sessionPlanKind: WatchSessionPlanKind? = nil
    /// Flat, ordered list of active source labels (e.g. "Manual Check-In",
    /// "Program", "Adaptive Overlay") so watch rendering can surface source
    /// provenance without re-deriving attribution.
    var sessionSourceLabels: [String]? = nil
    /// Stable identifier for the session version being executed. Used by watch
    /// tests and future companion app to detect when the phone swapped
    /// planned → runtime-adjusted mid-session.
    var sessionVersionStableID: String? = nil
    var capturedAt: Date
}

enum WatchRestTimerTransitionPolicy {
    static func sessionIdentity(for context: WatchCurrentSessionContext?) -> String? {
        guard let context else { return nil }
        return "\(context.workoutID.uuidString)|\(context.sessionVersionStableID ?? "")"
    }

    static func shouldStopRestTimer(
        previousContext: WatchCurrentSessionContext?,
        currentContext: WatchCurrentSessionContext?
    ) -> Bool {
        guard previousContext != nil else { return false }
        return sessionIdentity(for: previousContext) != sessionIdentity(for: currentContext)
    }
}

enum WatchCurrentSetPresentationPolicy {
    private static func setOrdinal(for context: WatchCurrentSessionContext) -> Int {
        if context.isCardio {
            return context.loggedSetsInExercise
        }
        return context.currentSetNumber ?? context.nextSetNumber ?? (context.totalSetsInExercise + 1)
    }

    static func setSignature(for context: WatchCurrentSessionContext?) -> String? {
        guard let context, !context.isCardio else { return nil }
        let setNumber = context.currentSetNumber ?? context.nextSetNumber ?? -1
        return "\(context.exerciseIndex)-\(setNumber)-\(context.loggedSetsInExercise)"
    }

    static func shouldReplaceDisplayedContext(
        existing: WatchCurrentSessionContext?,
        incoming: WatchCurrentSessionContext?
    ) -> Bool {
        guard let incoming else { return false }
        guard let existing else { return true }

        let existingSession = WatchRestTimerTransitionPolicy.sessionIdentity(for: existing)
        let incomingSession = WatchRestTimerTransitionPolicy.sessionIdentity(for: incoming)
        if existingSession != incomingSession {
            return true
        }

        if incoming.exerciseIndex != existing.exerciseIndex {
            return incoming.exerciseIndex > existing.exerciseIndex
        }

        return setOrdinal(for: incoming) > setOrdinal(for: existing)
    }

    static func optimisticNextSetContext(
        afterCompleting context: WatchCurrentSessionContext,
        completedReps: Int?,
        completedWeight: Double?,
        capturedAt: Date = Date()
    ) -> WatchCurrentSessionContext? {
        guard !context.isCardio else { return nil }
        guard let currentSetNumber = context.currentSetNumber ?? context.nextSetNumber else { return nil }

        let nextSetNumber = currentSetNumber + 1
        guard nextSetNumber <= context.totalSetsInExercise else { return nil }

        var updated = context
        updated.loggedSetsInExercise = min(context.totalSetsInExercise, context.loggedSetsInExercise + 1)
        updated.currentSetNumber = nextSetNumber
        updated.nextSetNumber = nextSetNumber
        updated.nextPrescribedReps = nil
        updated.nextPrescribedWeight = nil
        updated.currentSetTargetSummary = nil
        updated.currentSetCompletedReps = completedReps ?? context.currentSetCompletedReps ?? context.nextPrescribedReps
        updated.currentSetCompletedWeight = completedWeight ?? context.currentSetCompletedWeight ?? context.nextPrescribedWeight
        updated.capturedAt = capturedAt
        return updated
    }
}

// MARK: - Live Workout Snapshot

/// Richer, forward-compatible progress snapshot. `WatchWorkoutProgressSnapshot`
/// (defined in `WatchCompanionTypes.swift`) remains the minimal shape for the
/// existing Feature 8 bridge; this struct is the expanded shape the watch
/// companion app will consume for its live session glance.
struct WatchLiveWorkoutSnapshot: Codable, Equatable {
    var workoutID: UUID
    var elapsedSeconds: Int
    var completedExercises: Int
    var totalExercises: Int
    var completedSetsInCurrentExercise: Int
    var totalSetsInCurrentExercise: Int
    var currentExerciseName: String?
    var sessionLabel: String
    var programRunStableID: String?
    var programWeekNumber: Int?
    var programSessionNumber: Int?
    var sessionPlanKind: WatchSessionPlanKind? = nil
    var sessionSourceLabels: [String]? = nil
    var sessionVersionStableID: String? = nil
    var capturedAt: Date
}

// MARK: - Session Completion Handoff

/// Terminal handoff sent when an in-progress workout has been saved. Lets the
/// watch surface wrap up its live execution state and celebrate completion
/// without requerying the iPhone. Remains additive + versioned so future
/// companion builds can ignore fields they don't understand.
struct WatchSessionCompletionPayload: Codable, Equatable {
    var workoutID: UUID
    var completedAt: Date
    var totalElapsedSeconds: Int
    var completedExercises: Int
    var totalExercises: Int
    var completedSets: Int
    var totalSets: Int
    var sessionLabel: String
    var sessionPlanKind: WatchSessionPlanKind?
    var sessionSourceLabels: [String]?
    var sessionVersionStableID: String?
    var newPersonalRecordCount: Int
}
