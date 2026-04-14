//
//  ActiveWorkoutSessionStore.swift
//  SuggestMeSome
//
//  Owns the one in-progress workout draft for the whole app.
//

import Foundation

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
    var sessionPlanKind: WatchSessionPlanKind?
    var sessionSourceLabels: [String]?
    var sessionVersionStableID: String?

    init(
        id: UUID = UUID(),
        startTime: Date,
        exerciseEntries: [DraftExerciseEntry] = [],
        caloriesText: String = "",
        comments: String = "",
        programContext: ActiveWorkoutProgramContext? = nil,
        sessionPlanKind: WatchSessionPlanKind? = nil,
        sessionSourceLabels: [String]? = nil,
        sessionVersionStableID: String? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.exerciseEntries = exerciseEntries
        self.caloriesText = caloriesText
        self.comments = comments
        self.programContext = programContext
        self.sessionPlanKind = sessionPlanKind
        self.sessionSourceLabels = sessionSourceLabels
        self.sessionVersionStableID = sessionVersionStableID
    }
}

@MainActor
@Observable
final class ActiveWorkoutSessionStore {
    private let userDefaults: UserDefaults
    private let persistenceKey: String
    private var appliedWatchActionIDs: Set<UUID> = []

    var session: ActiveWorkoutSession? {
        didSet {
            persistSession()
        }
    }

    var hasActiveSession: Bool {
        session != nil
    }

    init(
        userDefaults: UserDefaults = .standard,
        persistenceKey: String = "activeWorkoutSession.v1"
    ) {
        self.userDefaults = userDefaults
        self.persistenceKey = persistenceKey

        if let data = userDefaults.data(forKey: persistenceKey),
           let restored = try? JSONDecoder().decode(ActiveWorkoutSession.self, from: data) {
            self.session = restored
        } else {
            self.session = nil
        }
    }

    func startSession(
        id: UUID = UUID(),
        startTime: Date = Date.now,
        exerciseEntries: [DraftExerciseEntry] = [],
        programContext: ActiveWorkoutProgramContext? = nil,
        sessionPlanKind: WatchSessionPlanKind? = nil,
        sessionSourceLabels: [String]? = nil,
        sessionVersionStableID: String? = nil
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
            sessionPlanKind: metadata.kind,
            sessionSourceLabels: metadata.sourceLabels,
            sessionVersionStableID: metadata.versionID
        )
    }

    func updateSession(
        startTime: Date,
        exerciseEntries: [DraftExerciseEntry],
        caloriesText: String,
        comments: String,
        programContext: ActiveWorkoutProgramContext?,
        sessionPlanKind: WatchSessionPlanKind? = nil,
        sessionSourceLabels: [String]? = nil,
        sessionVersionStableID: String? = nil
    ) {
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
                sessionPlanKind: metadata.kind,
                sessionSourceLabels: metadata.sourceLabels,
                sessionVersionStableID: metadata.versionID
            )
            return
        }

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
        session = current
    }

    func discardSession() {
        session = nil
        appliedWatchActionIDs.removeAll()
    }

    @discardableResult
    func applyWatchExecutionAction(_ action: WatchWorkoutExecutionActionDTO) -> WatchWorkoutExecutionActionApplyResult {
        guard var current = session else {
            return WatchWorkoutExecutionActionApplyResult(status: .ignoredEmptyDraft, updatedEntries: [])
        }

        guard action.workoutID == current.id else {
            return WatchWorkoutExecutionActionApplyResult(
                status: .ignoredStaleCursor,
                updatedEntries: current.exerciseEntries
            )
        }

        if let actionVersion = action.sessionVersionStableID,
           let sessionVersion = current.sessionVersionStableID,
           actionVersion != sessionVersion {
            return WatchWorkoutExecutionActionApplyResult(
                status: .ignoredStaleCursor,
                updatedEntries: current.exerciseEntries
            )
        }

        guard !appliedWatchActionIDs.contains(action.actionID) else {
            return WatchWorkoutExecutionActionApplyResult(
                status: .ignoredStaleCursor,
                updatedEntries: current.exerciseEntries
            )
        }

        let result = WatchPayloadMapper.applyExecutionAction(
            action,
            to: current.exerciseEntries
        )
        guard result.didApply else { return result }

        current.exerciseEntries = result.updatedEntries
        session = current
        appliedWatchActionIDs.insert(action.actionID)
        return result
    }

    private func persistSession() {
        guard let session else {
            userDefaults.removeObject(forKey: persistenceKey)
            return
        }

        guard let data = try? JSONEncoder().encode(session) else { return }
        userDefaults.set(data, forKey: persistenceKey)
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
