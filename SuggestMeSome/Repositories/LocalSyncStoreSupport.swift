import Foundation
import SwiftData

@MainActor
struct LocalSyncStoreContext {
    let modelContext: ModelContext

    func fetchRows<T: PersistentModel>(_ type: T.Type) throws -> [T] {
        try modelContext.fetch(FetchDescriptor<T>())
    }

    func stableIDMap<T: SyncTrackableModel>(_ rows: [T]) throws -> [String: T] {
        var map: [String: T] = [:]
        for row in rows {
            row.initializeSyncMetadataIfNeeded()
            map[row.resolvedSyncStableID] = row
        }
        return map
    }

    func stableIDMap<T: SyncTrackableModel & PersistentModel>(for type: T.Type) throws -> [String: T] {
        try stableIDMap(fetchRows(type))
    }

    func filteredBySince<T: SyncTrackableModel>(_ rows: [T], since: Date?) -> [T] {
        guard let since else { return rows }
        return rows.filter { $0.syncLastModifiedAt >= since }
    }

    func analysesByID() throws -> [String: WeeklyTrainingAnalysis] {
        try fetchRows(WeeklyTrainingAnalysis.self).reduce(into: [String: WeeklyTrainingAnalysis]()) { map, row in
            map[row.id.uuidString] = row
        }
    }

    func save() throws {
        try modelContext.save()
    }
}
