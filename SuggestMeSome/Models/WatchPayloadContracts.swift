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
}

// MARK: - Execution Interaction Types

/// Preferred logging interaction model for the current watch execution screen.
enum WatchExecutionInteractionModel: String, Codable, Equatable {
    case digitalCrownFirst
}

/// Origin classification for today's session so watch rendering can stay
/// compatible with planned sessions and coach-adjusted runtime drafts.
enum WatchSessionPlanKind: String, Codable, Equatable {
    case planned
    case coachAdjusted
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
    var capturedAt: Date
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
    var capturedAt: Date
}
