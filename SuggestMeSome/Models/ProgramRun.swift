//
//  ProgramRun.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/6/26.
//

import Foundation
import SwiftData

@Model
final class ProgramRun {
    var id: UUID
    /// Stable identifier for cross-device sync contracts.
    var syncStableID: String?
    /// Monotonic version for deterministic merge tie-breaks.
    var syncVersion: Int
    /// Last modified timestamp used by sync conflict policies.
    var syncLastModifiedAt: Date
    var startDate: Date
    var endDate: Date?
    var isCompleted: Bool
    /// Stable ID of the prior completed run when this block was started from a
    /// carried-forward recommendation.
    var previousProgramRunStableID: String?
    /// JSON snapshot of completed-block recommendation decisions for sync-safe,
    /// additive continuity logging on the source run.
    var recommendationDecisionHistoryJSON: String?
    /// JSON snapshot copied onto the next run so continuity survives even if the
    /// source review is no longer loaded in memory.
    var continuitySnapshotJSON: String?

    var program: TrainingProgram?

    init(
        id: UUID = UUID(),
        syncStableID: String? = nil,
        syncVersion: Int = 1,
        syncLastModifiedAt: Date = Date(),
        startDate: Date,
        endDate: Date? = nil,
        isCompleted: Bool = false,
        previousProgramRunStableID: String? = nil,
        recommendationDecisionHistoryJSON: String? = nil,
        continuitySnapshotJSON: String? = nil
    ) {
        self.id = id
        self.syncStableID = syncStableID ?? id.uuidString
        self.syncVersion = max(1, syncVersion)
        self.syncLastModifiedAt = syncLastModifiedAt
        self.startDate = startDate
        self.endDate = endDate
        self.isCompleted = isCompleted
        self.previousProgramRunStableID = previousProgramRunStableID
        self.recommendationDecisionHistoryJSON = recommendationDecisionHistoryJSON
        self.continuitySnapshotJSON = continuitySnapshotJSON
    }
}
