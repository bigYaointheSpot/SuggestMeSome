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

    var program: TrainingProgram?

    init(
        id: UUID = UUID(),
        syncStableID: String? = nil,
        syncVersion: Int = 1,
        syncLastModifiedAt: Date = Date(),
        startDate: Date,
        endDate: Date? = nil,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.syncStableID = syncStableID ?? id.uuidString
        self.syncVersion = max(1, syncVersion)
        self.syncLastModifiedAt = syncLastModifiedAt
        self.startDate = startDate
        self.endDate = endDate
        self.isCompleted = isCompleted
    }
}
