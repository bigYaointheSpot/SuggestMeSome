//
//  HealthKitDailySummary.swift
//  SuggestMeSome
//
//  Feature 8 — Daily HealthKit recovery snapshot storage.
//

import Foundation
import SwiftData

@Model
final class HealthKitDailySummary {
    var id: UUID
    /// Stable identifier for cross-device or watch transport contracts.
    var syncStableID: String?
    /// Monotonic version for deterministic merge tie-breaks.
    var syncVersion: Int
    /// Last modified timestamp used by sync conflict policies.
    var syncLastModifiedAt: Date
    var dayStart: Date

    var sleepDurationSeconds: Int?
    var timeInBedSeconds: Int?
    var restingHeartRateBPM: Double?
    var heartRateVariabilityMS: Double?
    var activeEnergyKilocalories: Double?
    var stepCount: Double?
    var bodyMassKilograms: Double?

    /// Timestamp from the upstream source payload refresh.
    var sourceUpdatedAt: Date
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        syncStableID: String? = nil,
        syncVersion: Int = 1,
        syncLastModifiedAt: Date? = nil,
        dayStart: Date,
        sleepDurationSeconds: Int? = nil,
        timeInBedSeconds: Int? = nil,
        restingHeartRateBPM: Double? = nil,
        heartRateVariabilityMS: Double? = nil,
        activeEnergyKilocalories: Double? = nil,
        stepCount: Double? = nil,
        bodyMassKilograms: Double? = nil,
        sourceUpdatedAt: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.syncStableID = syncStableID ?? id.uuidString
        self.syncVersion = max(1, syncVersion)
        self.dayStart = dayStart
        self.sleepDurationSeconds = sleepDurationSeconds
        self.timeInBedSeconds = timeInBedSeconds
        self.restingHeartRateBPM = restingHeartRateBPM
        self.heartRateVariabilityMS = heartRateVariabilityMS
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.stepCount = stepCount
        self.bodyMassKilograms = bodyMassKilograms
        self.sourceUpdatedAt = sourceUpdatedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncLastModifiedAt = syncLastModifiedAt ?? updatedAt
    }
}
