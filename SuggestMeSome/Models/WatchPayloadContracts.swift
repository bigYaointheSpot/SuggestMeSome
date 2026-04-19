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
    static let v2 = 2
    static let current = v2
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
    case watchPresenceHeartbeat
    case workoutMetrics
    case workoutHealthSummary
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

/// Shared running / paused state carried across iPhone, watch UI, and the
/// linked watch-side HealthKit workout session.
enum WatchWorkoutLifecycleState: String, Codable, Equatable {
    case running
    case paused
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
    var lifecycleState: WatchWorkoutLifecycleState? = nil
    var usesLinkedWatchHealthSession: Bool? = nil
    /// Flat, ordered list of active source labels (e.g. "Manual Check-In",
    /// "Program", "Adaptive Overlay") so watch rendering can surface source
    /// provenance without re-deriving attribution.
    var sessionSourceLabels: [String]? = nil
    /// Stable identifier for the session version being executed. Used by watch
    /// tests and future companion app to detect when the phone swapped
    /// planned → runtime-adjusted mid-session.
    var sessionVersionStableID: String? = nil
    /// Ordered exercise roster for the active session. Each entry carries a
    /// stable identifier so the watch can track the same exercise across
    /// iOS-side reorders instead of pinning to a positional index. Optional
    /// for backward compatibility with pre-Feature-17 builds; when the phone
    /// sends a compact unchanged-roster update for the same workout/session
    /// version, `nil` means "preserve the existing roster."
    var sessionExerciseRoster: [WatchSessionExerciseRosterEntry]? = nil
    var capturedAt: Date
}

/// Per-exercise roster entry. Transmitted within
/// `WatchCurrentSessionContext.sessionExerciseRoster` so the watch can
/// render the upcoming exercise list and follow the same exercise across
/// reorders even though `exerciseIndex` is positional.
struct WatchSessionExerciseRosterEntry: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var orderIndex: Int
    var status: WatchRosterExerciseStatus
    var isCardio: Bool
}

enum WatchRosterExerciseStatus: String, Codable, Equatable {
    case completed
    case active
    case upcoming
}

enum WatchCurrentSessionContextMergePolicy {
    static func mergePreservingRoster(
        existing: WatchCurrentSessionContext?,
        incoming: WatchCurrentSessionContext?
    ) -> WatchCurrentSessionContext? {
        guard var incoming else { return nil }
        guard incoming.sessionExerciseRoster == nil else { return incoming }
        guard let existing, isSameSession(existing, incoming) else { return incoming }
        incoming.sessionExerciseRoster = existing.sessionExerciseRoster
        return incoming
    }

    private static func isSameSession(
        _ lhs: WatchCurrentSessionContext,
        _ rhs: WatchCurrentSessionContext
    ) -> Bool {
        lhs.workoutID == rhs.workoutID
            && lhs.sessionVersionStableID == rhs.sessionVersionStableID
    }
}

enum WatchSessionExerciseRosterPresentationPolicy {
    static func upcomingEntries(
        roster: [WatchSessionExerciseRosterEntry]?,
        activeExerciseIndex: Int?
    ) -> [WatchSessionExerciseRosterEntry] {
        let orderedRoster = (roster ?? []).sorted { lhs, rhs in
            lhs.orderIndex < rhs.orderIndex
        }
        guard !orderedRoster.isEmpty else { return [] }
        guard let activeExerciseIndex else {
            return orderedRoster.filter { $0.status == .upcoming }
        }
        let firstUpcomingIndex = min(max(activeExerciseIndex + 1, 0), orderedRoster.count)
        return Array(orderedRoster.dropFirst(firstUpcomingIndex))
    }
}

// MARK: - Watch Presence Heartbeat

/// Lightweight watch -> phone presence ping used to confirm the companion is
/// installed and awake even when `WCSession.isWatchAppInstalled` lags.
struct WatchPresenceHeartbeatPayload: Codable, Equatable {
    var sentAt: Date

    init(sentAt: Date = Date()) {
        self.sentAt = sentAt
    }
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

    private static func targetSignature(for context: WatchCurrentSessionContext) -> String {
        let reps = context.nextPrescribedReps.map(String.init) ?? "nil"
        let weight: String
        if let weightValue = context.nextPrescribedWeight {
            if weightValue.truncatingRemainder(dividingBy: 1) == 0 {
                weight = String(Int(weightValue))
            } else {
                weight = String(format: "%.1f", weightValue)
            }
        } else {
            weight = "nil"
        }
        return [
            reps,
            weight,
            context.nextPrescribedWeightUnit ?? "nil",
            context.currentSetTargetSummary ?? "nil"
        ].joined(separator: "|")
    }

    private static func compareProgress(
        _ lhs: WatchCurrentSessionContext,
        _ rhs: WatchCurrentSessionContext
    ) -> ComparisonResult? {
        let lhsSession = WatchRestTimerTransitionPolicy.sessionIdentity(for: lhs)
        let rhsSession = WatchRestTimerTransitionPolicy.sessionIdentity(for: rhs)
        guard lhsSession == rhsSession else { return nil }

        if lhs.exerciseIndex != rhs.exerciseIndex {
            return lhs.exerciseIndex < rhs.exerciseIndex ? .orderedAscending : .orderedDescending
        }

        let lhsOrdinal = setOrdinal(for: lhs)
        let rhsOrdinal = setOrdinal(for: rhs)
        if lhsOrdinal == rhsOrdinal {
            return .orderedSame
        }
        return lhsOrdinal < rhsOrdinal ? .orderedAscending : .orderedDescending
    }

    static func setSignature(for context: WatchCurrentSessionContext?) -> String? {
        guard let context, !context.isCardio else { return nil }
        let setNumber = context.currentSetNumber ?? context.nextSetNumber ?? -1
        return [
            "\(context.exerciseIndex)",
            "\(setNumber)",
            "\(context.loggedSetsInExercise)",
            targetSignature(for: context),
            context.lifecycleState?.rawValue ?? "running"
        ].joined(separator: "-")
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

        let existingOrdinal = setOrdinal(for: existing)
        let incomingOrdinal = setOrdinal(for: incoming)
        if existingOrdinal == incomingOrdinal {
            if targetSignature(for: existing) != targetSignature(for: incoming) {
                return incoming.capturedAt >= existing.capturedAt
            }
            if existing.lifecycleState != incoming.lifecycleState {
                return incoming.capturedAt >= existing.capturedAt
            }
        }

        return incomingOrdinal > existingOrdinal
    }

    static func isAheadOfPhone(
        displayedContext: WatchCurrentSessionContext?,
        phoneContext: WatchCurrentSessionContext?
    ) -> Bool {
        guard let displayedContext, let phoneContext else { return false }
        return compareProgress(displayedContext, phoneContext) == .orderedDescending
    }

    static func hasCaughtUp(
        phoneContext: WatchCurrentSessionContext?,
        to displayedContext: WatchCurrentSessionContext?
    ) -> Bool {
        guard let displayedContext else { return true }
        guard let phoneContext else { return false }
        guard let comparison = compareProgress(phoneContext, displayedContext) else {
            return true
        }
        switch comparison {
        case .orderedDescending, .orderedSame:
            return true
        case .orderedAscending:
            return false
        }
    }

    static func hasLiveWorkoutCaughtUp(
        liveWorkout: WatchLiveWorkoutSnapshot?,
        to displayedContext: WatchCurrentSessionContext?
    ) -> Bool {
        guard let displayedContext, let liveWorkout else { return false }
        guard liveWorkout.workoutID == displayedContext.workoutID else { return false }

        if let displayedVersion = displayedContext.sessionVersionStableID,
           let liveVersion = liveWorkout.sessionVersionStableID,
           liveVersion != displayedVersion {
            return false
        }

        if liveWorkout.completedExercises > displayedContext.exerciseIndex {
            return true
        }
        guard liveWorkout.completedExercises == displayedContext.exerciseIndex else {
            return false
        }

        if let currentExerciseName = liveWorkout.currentExerciseName,
           !currentExerciseName.isEmpty,
           currentExerciseName != displayedContext.exerciseName {
            return false
        }

        return liveWorkout.completedSetsInCurrentExercise >= displayedContext.loggedSetsInExercise
    }

    static func isPhoneContextStaleComparedToLiveWorkout(
        phoneContext: WatchCurrentSessionContext?,
        liveWorkout: WatchLiveWorkoutSnapshot?
    ) -> Bool {
        guard let phoneContext, let liveWorkout else { return false }
        guard liveWorkout.workoutID == phoneContext.workoutID else { return false }

        if let phoneVersion = phoneContext.sessionVersionStableID,
           let liveVersion = liveWorkout.sessionVersionStableID,
           liveVersion != phoneVersion {
            return true
        }

        if liveWorkout.completedExercises > phoneContext.exerciseIndex {
            return true
        }
        if liveWorkout.completedExercises < phoneContext.exerciseIndex {
            return false
        }

        if let currentExerciseName = liveWorkout.currentExerciseName,
           !currentExerciseName.isEmpty,
           currentExerciseName != phoneContext.exerciseName {
            return true
        }

        return liveWorkout.completedSetsInCurrentExercise > phoneContext.loggedSetsInExercise
    }

    static func hasLiveWorkoutAdvancedPastCompletedExercise(
        liveWorkout: WatchLiveWorkoutSnapshot?,
        sessionIdentity: String,
        completedExerciseIndex: Int
    ) -> Bool {
        guard let liveWorkout else { return false }
        let liveIdentity = "\(liveWorkout.workoutID.uuidString)|\(liveWorkout.sessionVersionStableID ?? "")"
        guard liveIdentity == sessionIdentity else { return true }
        return liveWorkout.completedExercises > completedExerciseIndex
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
        // Preserve the next prescribed target until the phone confirms the new
        // set-specific prescription. This avoids falling back to the just
        // completed set's values as the optimistic default on watch.
        updated.nextPrescribedReps = context.nextPrescribedReps
        updated.nextPrescribedWeight = context.nextPrescribedWeight
        updated.nextPrescribedWeightUnit = context.nextPrescribedWeightUnit
        updated.currentSetTargetSummary = context.currentSetTargetSummary
        updated.currentSetCompletedReps = nil
        updated.currentSetCompletedWeight = nil
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
    var lifecycleState: WatchWorkoutLifecycleState? = nil
    var usesLinkedWatchHealthSession: Bool? = nil
    var sessionSourceLabels: [String]? = nil
    var sessionVersionStableID: String? = nil
    var capturedAt: Date
}

/// Live watch-side HealthKit workout metrics mirrored back to the phone so the
/// iPhone workout screen can surface wrist-derived heart rate and active
/// energy while a session is active.
struct WatchWorkoutMetricsPayload: Codable, Equatable {
    var workoutID: UUID
    var sessionVersionStableID: String?
    var lifecycleState: WatchWorkoutLifecycleState
    var isLinkedHealthSessionActive: Bool
    var heartRateBPM: Double?
    var activeEnergyKilocalories: Double?
    var capturedAt: Date
}

/// Terminal watch-side HealthKit summary returned after the linked workout
/// finishes on Apple Watch. Used by iPhone to avoid duplicate summary
/// writeback and to stamp the persisted workout with the HealthKit UUID.
struct WatchWorkoutHealthSummaryPayload: Codable, Equatable {
    var workoutID: UUID
    var sessionVersionStableID: String?
    var healthKitWorkoutUUID: String
    var exportedAt: Date
    var totalActiveEnergyKilocalories: Double?
    var finalHeartRateBPM: Double?
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
