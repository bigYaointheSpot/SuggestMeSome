import Foundation

@MainActor
struct LocalTrainingPreferencesSyncStore {
    let context: LocalSyncStoreContext

    func fetchTrainingPreferencesPayload(since: Date?) throws -> TrainingPreferencesSyncDTO? {
        let payload = TrainingPreferencesStore.currentSyncDTO(userDefaults: context.userDefaults)
        guard let since else { return payload }
        return payload.metadata.lastModifiedAt >= since ? payload : nil
    }

    func upsertTrainingPreferencesPayload(_ payload: TrainingPreferencesSyncDTO) throws {
        TrainingPreferencesStore.apply(payload, userDefaults: context.userDefaults)
    }
}
