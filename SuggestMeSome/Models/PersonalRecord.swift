//
//  PersonalRecord.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/5/26.
//

import Foundation
import SwiftData

/// Stores the best weight lifted for a given exercise at a specific rep count.
/// Uniqueness constraint: one record per (exerciseName, repCount) pair —
/// enforced in code when saving a workout (see `updatePersonalRecords`).
@Model
final class PersonalRecord {
    var id: UUID
    /// Stable identifier for cross-device sync contracts.
    var syncStableID: String?
    /// Monotonic version for deterministic merge tie-breaks.
    var syncVersion: Int
    /// Last modified timestamp used by sync conflict policies.
    var syncLastModifiedAt: Date
    var exerciseName: String
    var repCount: Int
    var weight: Double
    var unit: WeightUnit
    var dateAchieved: Date

    init(
        id: UUID = UUID(),
        syncStableID: String? = nil,
        syncVersion: Int = 1,
        syncLastModifiedAt: Date = Date(),
        exerciseName: String,
        repCount: Int,
        weight: Double,
        unit: WeightUnit,
        dateAchieved: Date
    ) {
        self.id = id
        self.syncStableID = syncStableID ?? id.uuidString
        self.syncVersion = max(1, syncVersion)
        self.syncLastModifiedAt = syncLastModifiedAt
        self.exerciseName = exerciseName
        self.repCount = repCount
        self.weight = weight
        self.unit = unit
        self.dateAchieved = dateAchieved
    }
}
