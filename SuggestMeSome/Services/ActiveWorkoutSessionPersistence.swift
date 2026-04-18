import Foundation

enum ActiveWorkoutSessionContractVersion: Int, Codable {
    case v1 = 1

    static let current = ActiveWorkoutSessionContractVersion.v1
}

struct ActiveWorkoutSessionEnvelope<Payload: Codable>: Codable {
    let schemaVersion: Int
    let payload: Payload

    init(
        schemaVersion: ActiveWorkoutSessionContractVersion = .current,
        payload: Payload
    ) {
        self.schemaVersion = schemaVersion.rawValue
        self.payload = payload
    }
}

private struct ActiveWorkoutSessionDecodingEnvelope<Payload: Decodable>: Decodable {
    let schemaVersion: Int
    let payload: Payload
}

enum ActiveWorkoutSessionPersistenceCodec {
    static func encode(_ session: ActiveWorkoutSession?) -> Data? {
        guard let session else { return nil }
        let encoder = JSONEncoder()
        return try? encoder.encode(
            ActiveWorkoutSessionEnvelope(payload: session)
        )
    }

    static func decode(_ data: Data?) -> ActiveWorkoutSession? {
        guard let data else { return nil }
        let decoder = JSONDecoder()

        if let envelope = try? decoder.decode(
            ActiveWorkoutSessionDecodingEnvelope<ActiveWorkoutSession>.self,
            from: data
        ) {
            return envelope.payload
        }

        return try? decoder.decode(ActiveWorkoutSession.self, from: data)
    }
}

struct ActiveWorkoutSessionPersistenceStore {
    let userDefaults: UserDefaults
    let persistenceKey: String

    func load() -> ActiveWorkoutSession? {
        ActiveWorkoutSessionPersistenceCodec.decode(
            userDefaults.data(forKey: persistenceKey)
        )
    }

    @discardableResult
    func save(_ session: ActiveWorkoutSession?) -> Bool {
        let data = ActiveWorkoutSessionPersistenceCodec.encode(session)
        let existingData = userDefaults.data(forKey: persistenceKey)

        if existingData == data {
            return false
        }

        guard let data else {
            userDefaults.removeObject(forKey: persistenceKey)
            return true
        }

        userDefaults.set(data, forKey: persistenceKey)
        return true
    }
}

struct ActiveWorkoutSessionWatchActionReduction {
    let session: ActiveWorkoutSession?
    let appliedActionIDs: Set<UUID>
    let result: WatchWorkoutExecutionActionApplyResult
}

enum ActiveWorkoutSessionWatchActionReducer {
    static func reduce(
        action: WatchWorkoutExecutionActionDTO,
        session: ActiveWorkoutSession?,
        appliedActionIDs: Set<UUID>
    ) -> ActiveWorkoutSessionWatchActionReduction {
        guard var session else {
            return ActiveWorkoutSessionWatchActionReduction(
                session: nil,
                appliedActionIDs: appliedActionIDs,
                result: WatchWorkoutExecutionActionApplyResult(
                    status: .ignoredEmptyDraft,
                    updatedEntries: []
                )
            )
        }

        guard action.workoutID == session.id else {
            return ActiveWorkoutSessionWatchActionReduction(
                session: session,
                appliedActionIDs: appliedActionIDs,
                result: WatchWorkoutExecutionActionApplyResult(
                    status: .ignoredStaleCursor,
                    updatedEntries: session.exerciseEntries
                )
            )
        }

        if let actionVersion = action.sessionVersionStableID,
           let sessionVersion = session.sessionVersionStableID,
           actionVersion != sessionVersion {
            return ActiveWorkoutSessionWatchActionReduction(
                session: session,
                appliedActionIDs: appliedActionIDs,
                result: WatchWorkoutExecutionActionApplyResult(
                    status: .ignoredStaleCursor,
                    updatedEntries: session.exerciseEntries
                )
            )
        }

        guard !appliedActionIDs.contains(action.actionID) else {
            return ActiveWorkoutSessionWatchActionReduction(
                session: session,
                appliedActionIDs: appliedActionIDs,
                result: WatchWorkoutExecutionActionApplyResult(
                    status: .ignoredStaleCursor,
                    updatedEntries: session.exerciseEntries
                )
            )
        }

        switch action.actionKind {
        case .applyCrownTicksToCurrentSetWeight, .applyCrownTicksToCurrentSetReps:
            return ActiveWorkoutSessionWatchActionReduction(
                session: session,
                appliedActionIDs: appliedActionIDs,
                result: WatchWorkoutExecutionActionApplyResult(
                    status: .ignoredIncompatibleAction,
                    updatedEntries: session.exerciseEntries
                )
            )
        case .completeCurrentSet, .completeCardioBlock:
            break
        }

        let result = WatchPayloadMapper.applyExecutionAction(
            action,
            to: session.exerciseEntries
        )
        guard result.didApply else {
            return ActiveWorkoutSessionWatchActionReduction(
                session: session,
                appliedActionIDs: appliedActionIDs,
                result: result
            )
        }

        session.exerciseEntries = result.updatedEntries
        var updatedActionIDs = appliedActionIDs
        updatedActionIDs.insert(action.actionID)

        return ActiveWorkoutSessionWatchActionReduction(
            session: session,
            appliedActionIDs: updatedActionIDs,
            result: result
        )
    }
}
