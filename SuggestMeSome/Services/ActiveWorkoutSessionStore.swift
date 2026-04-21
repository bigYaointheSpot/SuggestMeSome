//
//  ActiveWorkoutSessionStore.swift
//  SuggestMeSome
//
//  Owns the one in-progress workout draft for the whole app.
//

import Foundation

struct ActiveWorkoutSessionMutationResult: Equatable {
    let didChangeSession: Bool
    let shouldBroadcastWatch: Bool

    static let unchanged = ActiveWorkoutSessionMutationResult(
        didChangeSession: false,
        shouldBroadcastWatch: false
    )
}

struct ActiveWorkoutProgramContext: Codable, Equatable {
    var programRunID: UUID
    var programRunStableID: String? = nil
    var weekNumber: Int
    var sessionNumber: Int
}

struct ActiveWorkoutSession: Identifiable, Codable, Equatable {
    var id: UUID
    var startTime: Date
    var exerciseEntries: [DraftExerciseEntry]
    var caloriesText: String
    var comments: String
    var programContext: ActiveWorkoutProgramContext?
    var lifecycleState: WatchWorkoutLifecycleState
    var accumulatedElapsedSeconds: Int
    var stateChangedAt: Date
    var sessionPlanKind: WatchSessionPlanKind?
    var sessionSourceLabels: [String]?
    var sessionVersionStableID: String?
    var usesLinkedWatchHealthSession: Bool

    init(
        id: UUID = UUID(),
        startTime: Date,
        exerciseEntries: [DraftExerciseEntry] = [],
        caloriesText: String = "",
        comments: String = "",
        programContext: ActiveWorkoutProgramContext? = nil,
        lifecycleState: WatchWorkoutLifecycleState = .running,
        accumulatedElapsedSeconds: Int = 0,
        stateChangedAt: Date? = nil,
        sessionPlanKind: WatchSessionPlanKind? = nil,
        sessionSourceLabels: [String]? = nil,
        sessionVersionStableID: String? = nil,
        usesLinkedWatchHealthSession: Bool = false
    ) {
        self.id = id
        self.startTime = startTime
        self.exerciseEntries = exerciseEntries
        self.caloriesText = caloriesText
        self.comments = comments
        self.programContext = programContext
        self.lifecycleState = lifecycleState
        self.accumulatedElapsedSeconds = max(0, accumulatedElapsedSeconds)
        self.stateChangedAt = stateChangedAt ?? startTime
        self.sessionPlanKind = sessionPlanKind
        self.sessionSourceLabels = sessionSourceLabels
        self.sessionVersionStableID = sessionVersionStableID
        self.usesLinkedWatchHealthSession = usesLinkedWatchHealthSession
    }

    func elapsedSeconds(at date: Date = .now) -> Int {
        switch lifecycleState {
        case .running:
            return max(0, accumulatedElapsedSeconds + Int(date.timeIntervalSince(stateChangedAt)))
        case .paused:
            return max(0, accumulatedElapsedSeconds)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case startTime
        case exerciseEntries
        case caloriesText
        case comments
        case programContext
        case lifecycleState
        case accumulatedElapsedSeconds
        case stateChangedAt
        case sessionPlanKind
        case sessionSourceLabels
        case sessionVersionStableID
        case usesLinkedWatchHealthSession
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let startTime = try container.decode(Date.self, forKey: .startTime)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.startTime = startTime
        self.exerciseEntries = try container.decodeIfPresent([DraftExerciseEntry].self, forKey: .exerciseEntries) ?? []
        self.caloriesText = try container.decodeIfPresent(String.self, forKey: .caloriesText) ?? ""
        self.comments = try container.decodeIfPresent(String.self, forKey: .comments) ?? ""
        self.programContext = try container.decodeIfPresent(ActiveWorkoutProgramContext.self, forKey: .programContext)
        self.lifecycleState = try container.decodeIfPresent(WatchWorkoutLifecycleState.self, forKey: .lifecycleState) ?? .running
        self.accumulatedElapsedSeconds = max(
            0,
            try container.decodeIfPresent(Int.self, forKey: .accumulatedElapsedSeconds) ?? 0
        )
        self.stateChangedAt = try container.decodeIfPresent(Date.self, forKey: .stateChangedAt) ?? startTime
        self.sessionPlanKind = try container.decodeIfPresent(WatchSessionPlanKind.self, forKey: .sessionPlanKind)
        self.sessionSourceLabels = try container.decodeIfPresent([String].self, forKey: .sessionSourceLabels)
        self.sessionVersionStableID = try container.decodeIfPresent(String.self, forKey: .sessionVersionStableID)
        self.usesLinkedWatchHealthSession = try container.decodeIfPresent(Bool.self, forKey: .usesLinkedWatchHealthSession) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(exerciseEntries, forKey: .exerciseEntries)
        try container.encode(caloriesText, forKey: .caloriesText)
        try container.encode(comments, forKey: .comments)
        try container.encodeIfPresent(programContext, forKey: .programContext)
        try container.encode(lifecycleState, forKey: .lifecycleState)
        try container.encode(accumulatedElapsedSeconds, forKey: .accumulatedElapsedSeconds)
        try container.encode(stateChangedAt, forKey: .stateChangedAt)
        try container.encodeIfPresent(sessionPlanKind, forKey: .sessionPlanKind)
        try container.encodeIfPresent(sessionSourceLabels, forKey: .sessionSourceLabels)
        try container.encodeIfPresent(sessionVersionStableID, forKey: .sessionVersionStableID)
        try container.encode(usesLinkedWatchHealthSession, forKey: .usesLinkedWatchHealthSession)
    }
}

@MainActor
@Observable
final class ActiveWorkoutSessionStore {
    private let persistenceStore: ActiveWorkoutSessionPersistenceStore
    private let liveActivityBridge: (any WorkoutLiveActivityBridging)?
    private var appliedWatchActionIDs: Set<UUID> = []

    var latestWatchMetrics: WatchWorkoutMetricsPayload?
    var latestWatchHealthSummary: WatchWorkoutHealthSummaryPayload?

    var session: ActiveWorkoutSession? {
        didSet {
            persistSession()
            syncLiveActivity(oldValue: oldValue, newValue: session)
        }
    }

    var hasActiveSession: Bool {
        session != nil
    }

    init(
        userDefaults: UserDefaults = .standard,
        persistenceKey: String = "activeWorkoutSession.v1",
        liveActivityBridge: (any WorkoutLiveActivityBridging)? = WorkoutLiveActivityController.shared
    ) {
        self.persistenceStore = ActiveWorkoutSessionPersistenceStore(
            userDefaults: userDefaults,
            persistenceKey: persistenceKey
        )
        self.liveActivityBridge = liveActivityBridge
        self.session = persistenceStore.load()
    }

    func startSession(
        id: UUID = UUID(),
        startTime: Date = Date.now,
        exerciseEntries: [DraftExerciseEntry] = [],
        programContext: ActiveWorkoutProgramContext? = nil,
        sessionPlanKind: WatchSessionPlanKind? = nil,
        sessionSourceLabels: [String]? = nil,
        sessionVersionStableID: String? = nil,
        usesLinkedWatchHealthSession: Bool = false
    ) {
        let metadata = resolvedWatchMetadata(
            workoutID: id,
            programContext: programContext,
            sessionPlanKind: sessionPlanKind,
            sessionSourceLabels: sessionSourceLabels,
            sessionVersionStableID: sessionVersionStableID
        )
        session = ActiveWorkoutSession(
            id: id,
            startTime: startTime,
            exerciseEntries: exerciseEntries,
            programContext: programContext,
            lifecycleState: .running,
            accumulatedElapsedSeconds: 0,
            stateChangedAt: startTime,
            sessionPlanKind: metadata.kind,
            sessionSourceLabels: metadata.sourceLabels,
            sessionVersionStableID: metadata.versionID,
            usesLinkedWatchHealthSession: usesLinkedWatchHealthSession
        )
        // Reset the dedup set so action IDs from a prior session can't
        // accidentally suppress freshly-received ones. Paired with the
        // same reset in `discardSession`. UUID collision risk is zero
        // in practice, but the semantics are wrong without this.
        appliedWatchActionIDs.removeAll()
        latestWatchMetrics = nil
        latestWatchHealthSummary = nil
    }

    @discardableResult
    func updateSession(
        startTime: Date,
        exerciseEntries: [DraftExerciseEntry],
        caloriesText: String,
        comments: String,
        programContext: ActiveWorkoutProgramContext?,
        sessionPlanKind: WatchSessionPlanKind? = nil,
        sessionSourceLabels: [String]? = nil,
        sessionVersionStableID: String? = nil
    ) -> ActiveWorkoutSessionMutationResult {
        guard var current = session else {
            let id = UUID()
            let metadata = resolvedWatchMetadata(
                workoutID: id,
                programContext: programContext,
                sessionPlanKind: sessionPlanKind,
                sessionSourceLabels: sessionSourceLabels,
                sessionVersionStableID: sessionVersionStableID
            )
            session = ActiveWorkoutSession(
                id: id,
                startTime: startTime,
                exerciseEntries: exerciseEntries,
                caloriesText: caloriesText,
                comments: comments,
                programContext: programContext,
                lifecycleState: .running,
                accumulatedElapsedSeconds: 0,
                stateChangedAt: startTime,
                sessionPlanKind: metadata.kind,
                sessionSourceLabels: metadata.sourceLabels,
                sessionVersionStableID: metadata.versionID
            )
            return ActiveWorkoutSessionMutationResult(
                didChangeSession: true,
                shouldBroadcastWatch: true
            )
        }

        let existingWatchBroadcastSnapshot = current.watchBroadcastSnapshot
        current.startTime = startTime
        current.exerciseEntries = exerciseEntries
        current.caloriesText = caloriesText
        current.comments = comments
        if let programContext {
            current.programContext = programContext
        }
        if let sessionPlanKind {
            current.sessionPlanKind = sessionPlanKind
        }
        if let normalizedLabels = WatchPayloadMapper.normalizeSourceLabels(sessionSourceLabels) {
            current.sessionSourceLabels = normalizedLabels
        }
        if let sessionVersionStableID {
            current.sessionVersionStableID = sessionVersionStableID
        }
        guard session != current else {
            return .unchanged
        }

        let shouldBroadcastWatch = existingWatchBroadcastSnapshot != current.watchBroadcastSnapshot
        session = current
        return ActiveWorkoutSessionMutationResult(
            didChangeSession: true,
            shouldBroadcastWatch: shouldBroadcastWatch
        )
    }

    func pauseSession(at date: Date = .now) {
        guard var current = session, current.lifecycleState == .running else { return }
        current.accumulatedElapsedSeconds = current.elapsedSeconds(at: date)
        current.lifecycleState = .paused
        current.stateChangedAt = date
        setSessionIfChanged(current)
    }

    func resumeSession(at date: Date = .now) {
        guard var current = session, current.lifecycleState == .paused else { return }
        current.lifecycleState = .running
        current.stateChangedAt = date
        setSessionIfChanged(current)
    }

    func markLinkedWatchHealthSessionActive(_ isActive: Bool, for workoutID: UUID) {
        guard var current = session, current.id == workoutID else { return }
        current.usesLinkedWatchHealthSession = isActive
        setSessionIfChanged(current)
    }

    func updateLatestWatchMetrics(_ payload: WatchWorkoutMetricsPayload) {
        guard let current = session, current.id == payload.workoutID else { return }
        latestWatchMetrics = payload
        markLinkedWatchHealthSessionActive(payload.isLinkedHealthSessionActive, for: payload.workoutID)
    }

    func updateLatestWatchHealthSummary(_ payload: WatchWorkoutHealthSummaryPayload) {
        guard let current = session, current.id == payload.workoutID else { return }
        latestWatchHealthSummary = payload
        markLinkedWatchHealthSessionActive(true, for: payload.workoutID)
    }

    func resolvedElapsedSeconds(at date: Date = .now) -> Int {
        session?.elapsedSeconds(at: date) ?? 0
    }

    func discardSession() {
        session = nil
        appliedWatchActionIDs.removeAll()
        latestWatchMetrics = nil
        latestWatchHealthSummary = nil
    }

    @discardableResult
    func applyWatchExecutionAction(_ action: WatchWorkoutExecutionActionDTO) -> WatchWorkoutExecutionActionApplyResult {
        let reduction = ActiveWorkoutSessionWatchActionReducer.reduce(
            action: action,
            session: session,
            appliedActionIDs: appliedWatchActionIDs
        )
        setSessionIfChanged(reduction.session)
        appliedWatchActionIDs = reduction.appliedActionIDs
        return reduction.result
    }

    private func persistSession() {
        _ = persistenceStore.save(session)
    }

    /// Bridge the session-lifecycle `didSet` transitions into
    /// Live Activity start / update / end calls. Handles all four
    /// transitions (nil→nil no-op, nil→value start, value→nil end,
    /// value→value update-or-swap). Tests inject a mock bridge.
    private func syncLiveActivity(
        oldValue: ActiveWorkoutSession?,
        newValue: ActiveWorkoutSession?
    ) {
        guard let liveActivityBridge else { return }
        switch (oldValue, newValue) {
        case (nil, nil):
            return
        case (nil, .some(let new)):
            liveActivityBridge.startLiveActivity(for: new)
        case (.some(let old), nil):
            liveActivityBridge.endLiveActivity(sessionID: old.id)
        case (.some(let old), .some(let new)) where old.id == new.id:
            liveActivityBridge.updateLiveActivity(for: new)
        case (.some(let old), .some(let new)):
            liveActivityBridge.endLiveActivity(sessionID: old.id)
            liveActivityBridge.startLiveActivity(for: new)
        }
    }

    private func setSessionIfChanged(_ newSession: ActiveWorkoutSession?) {
        guard session != newSession else { return }
        session = newSession
    }

    private func resolvedWatchMetadata(
        workoutID: UUID,
        programContext: ActiveWorkoutProgramContext?,
        sessionPlanKind: WatchSessionPlanKind?,
        sessionSourceLabels: [String]?,
        sessionVersionStableID: String?
    ) -> (
        kind: WatchSessionPlanKind?,
        sourceLabels: [String]?,
        versionID: String
    ) {
        let kind = sessionPlanKind ?? (programContext == nil ? nil : .planned)
        let fallbackLabels = programContext == nil ? ["Manual Workout"] : ["Program"]
        let sourceLabels = WatchPayloadMapper.normalizeSourceLabels(sessionSourceLabels) ?? fallbackLabels
        let versionID = sessionVersionStableID ?? defaultSessionVersionStableID(
            workoutID: workoutID,
            programContext: programContext,
            kind: kind
        )
        return (kind, sourceLabels, versionID)
    }

    private func defaultSessionVersionStableID(
        workoutID: UUID,
        programContext: ActiveWorkoutProgramContext?,
        kind: WatchSessionPlanKind?
    ) -> String {
        guard let programContext else {
            return "manual::\(workoutID.uuidString)"
        }
        let runSegment = programContext.programRunStableID ?? programContext.programRunID.uuidString
        let suffix: String
        switch kind {
        case .overlayAdjusted:
            suffix = "overlay"
        case .runtimeAdjusted:
            suffix = "runtime"
        case .planned, .none:
            suffix = "planned"
        }
        return "\(runSegment)::w\(programContext.weekNumber)s\(programContext.sessionNumber)::\(suffix)"
    }
}

private struct ActiveWorkoutSessionWatchBroadcastSnapshot: Equatable {
    let id: UUID
    let startTime: Date
    let exerciseEntries: [DraftExerciseEntry]
    let programContext: ActiveWorkoutProgramContext?
    let lifecycleState: WatchWorkoutLifecycleState
    let accumulatedElapsedSeconds: Int
    let stateChangedAt: Date
    let sessionPlanKind: WatchSessionPlanKind?
    let sessionSourceLabels: [String]?
    let sessionVersionStableID: String?
    let usesLinkedWatchHealthSession: Bool
}

private extension ActiveWorkoutSession {
    var watchBroadcastSnapshot: ActiveWorkoutSessionWatchBroadcastSnapshot {
        ActiveWorkoutSessionWatchBroadcastSnapshot(
            id: id,
            startTime: startTime,
            exerciseEntries: exerciseEntries,
            programContext: programContext,
            lifecycleState: lifecycleState,
            accumulatedElapsedSeconds: accumulatedElapsedSeconds,
            stateChangedAt: stateChangedAt,
            sessionPlanKind: sessionPlanKind,
            sessionSourceLabels: sessionSourceLabels,
            sessionVersionStableID: sessionVersionStableID,
            usesLinkedWatchHealthSession: usesLinkedWatchHealthSession
        )
    }
}
