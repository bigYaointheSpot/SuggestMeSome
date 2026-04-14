//
//  ActiveWorkoutSessionStore.swift
//  SuggestMeSome
//
//  Owns the one in-progress workout draft for the whole app.
//

import Foundation

struct ActiveWorkoutProgramContext: Codable, Equatable {
    var programRunID: UUID
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

    init(
        id: UUID = UUID(),
        startTime: Date,
        exerciseEntries: [DraftExerciseEntry] = [],
        caloriesText: String = "",
        comments: String = "",
        programContext: ActiveWorkoutProgramContext? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.exerciseEntries = exerciseEntries
        self.caloriesText = caloriesText
        self.comments = comments
        self.programContext = programContext
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
        startTime: Date = Date.now,
        exerciseEntries: [DraftExerciseEntry] = [],
        programContext: ActiveWorkoutProgramContext? = nil
    ) {
        session = ActiveWorkoutSession(
            startTime: startTime,
            exerciseEntries: exerciseEntries,
            programContext: programContext
        )
    }

    func updateSession(
        startTime: Date,
        exerciseEntries: [DraftExerciseEntry],
        caloriesText: String,
        comments: String,
        programContext: ActiveWorkoutProgramContext?
    ) {
        guard var current = session else {
            session = ActiveWorkoutSession(
                startTime: startTime,
                exerciseEntries: exerciseEntries,
                caloriesText: caloriesText,
                comments: comments,
                programContext: programContext
            )
            return
        }

        current.startTime = startTime
        current.exerciseEntries = exerciseEntries
        current.caloriesText = caloriesText
        current.comments = comments
        current.programContext = programContext
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
}
