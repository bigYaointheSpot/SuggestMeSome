//
//  HealthKitTypeCatalog.swift
//  SuggestMeSome
//
//  Feature 8 — Centralized HealthKit type definitions for read/write scopes.
//

import Foundation
import HealthKit

enum HealthKitTypeCatalog {
    static var sleepAnalysisType: HKCategoryType? {
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
    }

    static var restingHeartRateType: HKQuantityType? {
        HKObjectType.quantityType(forIdentifier: .restingHeartRate)
    }

    static var heartRateVariabilityType: HKQuantityType? {
        HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)
    }

    static var activeEnergyType: HKQuantityType? {
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
    }

    static var stepCountType: HKQuantityType? {
        HKObjectType.quantityType(forIdentifier: .stepCount)
    }

    static var bodyMassType: HKQuantityType? {
        HKObjectType.quantityType(forIdentifier: .bodyMass)
    }

    static var workoutType: HKWorkoutType {
        HKObjectType.workoutType()
    }

    static var recoveryReadTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        if let sleepAnalysisType {
            types.insert(sleepAnalysisType)
        }
        if let restingHeartRateType {
            types.insert(restingHeartRateType)
        }
        if let heartRateVariabilityType {
            types.insert(heartRateVariabilityType)
        }
        if let activeEnergyType {
            types.insert(activeEnergyType)
        }
        if let stepCountType {
            types.insert(stepCountType)
        }
        if let bodyMassType {
            types.insert(bodyMassType)
        }
        types.insert(workoutType)
        return types
    }

    /// Limited write scope for future workout summary writeback.
    static var workoutWriteTypes: Set<HKSampleType> {
        [workoutType]
    }
}
