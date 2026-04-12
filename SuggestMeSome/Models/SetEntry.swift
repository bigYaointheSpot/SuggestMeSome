//
//  SetEntry.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/5/26.
//

import Foundation
import SwiftData

@Model
final class SetEntry {
    var id: UUID
    /// Stable identifier for cross-device sync contracts.
    var syncStableID: String?
    /// Monotonic version for deterministic merge tie-breaks.
    var syncVersion: Int
    /// Last modified timestamp used by sync conflict policies.
    var syncLastModifiedAt: Date
    var setNumber: Int
    var reps: Int
    var weight: Double
    var isPR: Bool
    var exerciseEntry: ExerciseEntry?

    init(
        id: UUID = UUID(),
        syncStableID: String? = nil,
        syncVersion: Int = 1,
        syncLastModifiedAt: Date = Date(),
        setNumber: Int,
        reps: Int,
        weight: Double,
        isPR: Bool = false
    ) {
        self.id = id
        self.syncStableID = syncStableID ?? id.uuidString
        self.syncVersion = max(1, syncVersion)
        self.syncLastModifiedAt = syncLastModifiedAt
        self.setNumber = setNumber
        self.reps = reps
        self.weight = weight
        self.isPR = isPR
    }
}
