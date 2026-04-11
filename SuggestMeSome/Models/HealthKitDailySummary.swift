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
    }
}
