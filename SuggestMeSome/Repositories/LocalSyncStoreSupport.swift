import Foundation
import OSLog
import SwiftData

@MainActor
struct LocalSyncStoreContext {
    let modelContext: ModelContext
    let userDefaults: UserDefaults

    func fetchRows<T: PersistentModel>(_ type: T.Type) throws -> [T] {
        try modelContext.fetch(FetchDescriptor<T>())
    }

    func fetchRows<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
        try modelContext.fetch(descriptor)
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

    func stableIDMapByRowID<T: SyncTrackableModel & PersistentModel>(for type: T.Type) throws -> [UUID: T] {
        try fetchRows(type).reduce(into: [UUID: T]()) { map, row in
            map[row.id] = row
        }
    }

    func measureSyncExport<Payload>(
        named exportName: String,
        since: Date?,
        metadata: String? = nil,
        _ block: () throws -> [Payload]
    ) rethrows -> [Payload] {
        let startedAt = ProcessInfo.processInfo.systemUptime
        let payloads = try block()
        LocalSyncStoreDiagnostics.logExport(
            name: exportName,
            since: since,
            metadata: metadata,
            payloadCount: payloads.count,
            elapsedMilliseconds: (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
        )
        return payloads
    }

    func save() throws {
        try modelContext.save()
    }
}

private enum LocalSyncStoreDiagnostics {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "SuggestMeSome",
        category: "LocalSyncStore"
    )

    static func logExport(
        name: String,
        since: Date?,
        metadata: String?,
        payloadCount: Int,
        elapsedMilliseconds: Double
    ) {
        #if DEBUG
        let roundedMilliseconds = Int(elapsedMilliseconds.rounded())
        let sinceValue = since?.timeIntervalSince1970 ?? -1
        if let metadata, !metadata.isEmpty {
            logger.debug(
                "\(name, privacy: .public) export finished in \(roundedMilliseconds)ms; payloadCount=\(payloadCount) since=\(sinceValue) \(metadata, privacy: .public)"
            )
        } else {
            logger.debug(
                "\(name, privacy: .public) export finished in \(roundedMilliseconds)ms; payloadCount=\(payloadCount) since=\(sinceValue)"
            )
        }
        #endif
    }
}
