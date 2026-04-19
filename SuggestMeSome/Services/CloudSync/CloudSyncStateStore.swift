import Foundation

enum CloudSyncActivityLevel: String, Codable, Equatable {
    case info
    case warning
    case error
}

struct CloudSyncActivityRecord: Codable, Equatable, Identifiable {
    let id: UUID
    let date: Date
    let level: CloudSyncActivityLevel
    let message: String

    init(
        id: UUID = UUID(),
        date: Date = .now,
        level: CloudSyncActivityLevel,
        message: String
    ) {
        self.id = id
        self.date = date
        self.level = level
        self.message = message
    }
}

struct PendingCloudSyncBatch: Codable, Equatable, Identifiable {
    let id: UUID
    let createdAt: Date
    let reason: String
    let payload: CloudSyncBatchPayload

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        reason: String,
        payload: CloudSyncBatchPayload
    ) {
        self.id = id
        self.createdAt = createdAt
        self.reason = reason
        self.payload = payload
    }
}

final class CloudSyncStateStore {
    private enum Key {
        static let deviceID = "cloudsync.device-id.v1"
        static let cursors = "cloudsync.cursors.v1"
        static let lastSuccessfulSyncAt = "cloudsync.last-success-at.v1"
        static let pendingBatches = "cloudsync.pending-batches.v1"
        static let activity = "cloudsync.activity.v1"
        static let bootstrappedAccountID = "cloudsync.bootstrapped-account-id.v1"
    }

    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func deviceID() -> String {
        if let existing = userDefaults.string(forKey: Key.deviceID), !existing.isEmpty {
            return existing
        }
        let generated = UUID().uuidString
        userDefaults.set(generated, forKey: Key.deviceID)
        return generated
    }

    func cursors() -> [CloudSyncCollectionCursorDTO] {
        load([CloudSyncCollectionCursorDTO].self, forKey: Key.cursors) ?? []
    }

    func setCursors(_ cursors: [CloudSyncCollectionCursorDTO]) {
        save(cursors, forKey: Key.cursors)
    }

    func lastSuccessfulSyncAt() -> Date? {
        userDefaults.object(forKey: Key.lastSuccessfulSyncAt) as? Date
    }

    func setLastSuccessfulSyncAt(_ date: Date?) {
        if let date {
            userDefaults.set(date, forKey: Key.lastSuccessfulSyncAt)
        } else {
            userDefaults.removeObject(forKey: Key.lastSuccessfulSyncAt)
        }
    }

    func pendingBatches() -> [PendingCloudSyncBatch] {
        load([PendingCloudSyncBatch].self, forKey: Key.pendingBatches) ?? []
    }

    func setPendingBatches(_ batches: [PendingCloudSyncBatch]) {
        save(batches, forKey: Key.pendingBatches)
    }

    func enqueuePendingBatch(_ batch: PendingCloudSyncBatch) {
        var batches = pendingBatches()
        batches.append(batch)
        setPendingBatches(batches)
    }

    func removePendingBatch(id: UUID) {
        setPendingBatches(pendingBatches().filter { $0.id != id })
    }

    func activity() -> [CloudSyncActivityRecord] {
        load([CloudSyncActivityRecord].self, forKey: Key.activity) ?? []
    }

    func appendActivity(_ record: CloudSyncActivityRecord, maxCount: Int = 20) {
        var records = activity()
        records.insert(record, at: 0)
        if records.count > maxCount {
            records = Array(records.prefix(maxCount))
        }
        save(records, forKey: Key.activity)
    }

    func bootstrappedAccountID() -> UUID? {
        guard let rawValue = userDefaults.string(forKey: Key.bootstrappedAccountID) else {
            return nil
        }
        return UUID(uuidString: rawValue)
    }

    func isBootstrapped(accountID: UUID?) -> Bool {
        guard let accountID else { return false }
        return bootstrappedAccountID() == accountID
    }

    func setBootstrappedAccountID(_ accountID: UUID?) {
        if let accountID {
            userDefaults.set(accountID.uuidString, forKey: Key.bootstrappedAccountID)
        } else {
            userDefaults.removeObject(forKey: Key.bootstrappedAccountID)
        }
    }

    func clearRuntimeState() {
        userDefaults.removeObject(forKey: Key.cursors)
        userDefaults.removeObject(forKey: Key.lastSuccessfulSyncAt)
        userDefaults.removeObject(forKey: Key.pendingBatches)
        userDefaults.removeObject(forKey: Key.bootstrappedAccountID)
    }

    private func load<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = userDefaults.data(forKey: key),
              let decoded = try? decoder.decode(type, from: data) else {
            return nil
        }
        return decoded
    }

    private func save<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? encoder.encode(value) else { return }
        userDefaults.set(data, forKey: key)
    }
}
