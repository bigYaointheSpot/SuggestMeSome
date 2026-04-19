//
//  ProgramGeneratorDerivedState.swift
//  SuggestMeSome
//
//  Feature 16 Prompt 7 — cached generator preview and 1RM lookup state.
//

import Foundation
import SwiftData

struct ProgramGeneratorBestPRSnapshot {
    let exerciseName: String
    let estimatedOneRepMax: Double
    let roundedOneRepMax: Double
    let unit: WeightUnit
    let personalRecordID: UUID
}

struct ProgramGeneratorDerivedState {
    let previewInputToken: Int
    let personalRecordsToken: Int
    let adaptivePreview: ProgramAdaptivePreview?
    let adaptiveExplanationBundle: AdaptiveExplanationBundle?
    let bestPRByExerciseName: [String: ProgramGeneratorBestPRSnapshot]

    var refreshToken: Int {
        var hasher = Hasher()
        hasher.combine(previewInputToken)
        hasher.combine(personalRecordsToken)
        return hasher.finalize()
    }

    static let placeholder = ProgramGeneratorDerivedState(
        previewInputToken: 0,
        personalRecordsToken: 0,
        adaptivePreview: nil,
        adaptiveExplanationBundle: nil,
        bestPRByExerciseName: [:]
    )

    static func refreshToken(
        selectedFocus: ProgramFocus?,
        selectedLevel: ProgramLevel?,
        durationWeeks: Int,
        sessionsPerWeek: Int,
        steeringProfile: AdaptiveSteeringProfile,
        carryForwardContext: ProgramGenerationCarryForwardContext?,
        personalRecords: [PersonalRecord]
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(previewInputToken(
            selectedFocus: selectedFocus,
            selectedLevel: selectedLevel,
            durationWeeks: durationWeeks,
            sessionsPerWeek: sessionsPerWeek,
            steeringProfile: steeringProfile,
            carryForwardContext: carryForwardContext
        ))
        hasher.combine(personalRecordsToken(personalRecords))
        return hasher.finalize()
    }

    static func build(
        selectedFocus: ProgramFocus?,
        selectedLevel: ProgramLevel?,
        durationWeeks: Int,
        sessionsPerWeek: Int,
        steeringProfile: AdaptiveSteeringProfile,
        carryForwardContext: ProgramGenerationCarryForwardContext?,
        personalRecords: [PersonalRecord],
        fallbackExplanationBundle: AdaptiveExplanationBundle?,
        context: ModelContext,
        previous: ProgramGeneratorDerivedState? = nil
    ) -> ProgramGeneratorDerivedState {
        let nextPreviewInputToken = previewInputToken(
            selectedFocus: selectedFocus,
            selectedLevel: selectedLevel,
            durationWeeks: durationWeeks,
            sessionsPerWeek: sessionsPerWeek,
            steeringProfile: steeringProfile,
            carryForwardContext: carryForwardContext
        )
        let nextPersonalRecordsToken = personalRecordsToken(personalRecords)

        let adaptivePreview: ProgramAdaptivePreview?
        if previous?.previewInputToken == nextPreviewInputToken {
            adaptivePreview = previous?.adaptivePreview
        } else if let previewInput = previewInput(
            selectedFocus: selectedFocus,
            selectedLevel: selectedLevel,
            durationWeeks: durationWeeks,
            sessionsPerWeek: sessionsPerWeek,
            steeringProfile: steeringProfile,
            carryForwardContext: carryForwardContext
        ) {
            adaptivePreview = ProgramGenerationService().previewAdaptiveContext(
                input: previewInput,
                context: context
            )
        } else {
            adaptivePreview = nil
        }

        let bestPRByExerciseName: [String: ProgramGeneratorBestPRSnapshot]
        if previous?.personalRecordsToken == nextPersonalRecordsToken {
            bestPRByExerciseName = previous?.bestPRByExerciseName ?? [:]
        } else {
            bestPRByExerciseName = buildBestPRByExerciseName(personalRecords)
        }

        return ProgramGeneratorDerivedState(
            previewInputToken: nextPreviewInputToken,
            personalRecordsToken: nextPersonalRecordsToken,
            adaptivePreview: adaptivePreview,
            adaptiveExplanationBundle: adaptivePreview?.explanationBundle ?? fallbackExplanationBundle,
            bestPRByExerciseName: bestPRByExerciseName
        )
    }

    private static func previewInput(
        selectedFocus: ProgramFocus?,
        selectedLevel: ProgramLevel?,
        durationWeeks: Int,
        sessionsPerWeek: Int,
        steeringProfile: AdaptiveSteeringProfile,
        carryForwardContext: ProgramGenerationCarryForwardContext?
    ) -> ProgramGenerationInput? {
        guard
            let focus = selectedFocus,
            let level = selectedLevel,
            durationWeeks > 0,
            sessionsPerWeek > 0
        else {
            return nil
        }

        return ProgramGenerationInput(
            focus: focus,
            level: level,
            durationWeeks: durationWeeks,
            sessionsPerWeek: sessionsPerWeek,
            oneRepMaxes: [:],
            carryForwardContext: carryForwardContext,
            steeringProfile: steeringProfile
        )
    }

    private static func previewInputToken(
        selectedFocus: ProgramFocus?,
        selectedLevel: ProgramLevel?,
        durationWeeks: Int,
        sessionsPerWeek: Int,
        steeringProfile: AdaptiveSteeringProfile,
        carryForwardContext: ProgramGenerationCarryForwardContext?
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(selectedFocus?.rawValue)
        hasher.combine(selectedLevel?.rawValue)
        hasher.combine(durationWeeks)
        hasher.combine(sessionsPerWeek)
        combineEncodable(steeringProfile, into: &hasher)
        combineEncodable(carryForwardContext, into: &hasher)
        return hasher.finalize()
    }

    private static func personalRecordsToken(_ personalRecords: [PersonalRecord]) -> Int {
        var hasher = Hasher()
        for record in personalRecords.sorted(by: personalRecordSort) {
            hasher.combine(record.id)
            hasher.combine(record.syncVersion)
            hasher.combine(record.exerciseName)
            hasher.combine(record.repCount)
            hasher.combine(record.weight)
            hasher.combine(record.unit.rawValue)
            hasher.combine(record.dateAchieved)
        }
        return hasher.finalize()
    }

    private static func buildBestPRByExerciseName(
        _ personalRecords: [PersonalRecord]
    ) -> [String: ProgramGeneratorBestPRSnapshot] {
        personalRecords.reduce(into: [String: ProgramGeneratorBestPRSnapshot]()) { partialResult, record in
            let estimatedOneRepMax = epleyEstimatedOneRepMax(for: record)
            let candidate = ProgramGeneratorBestPRSnapshot(
                exerciseName: record.exerciseName,
                estimatedOneRepMax: estimatedOneRepMax,
                roundedOneRepMax: roundOneRepMax(estimatedOneRepMax, unit: record.unit),
                unit: record.unit,
                personalRecordID: record.id
            )

            guard let existing = partialResult[record.exerciseName] else {
                partialResult[record.exerciseName] = candidate
                return
            }

            let shouldReplace =
                candidate.estimatedOneRepMax > existing.estimatedOneRepMax ||
                (
                    candidate.estimatedOneRepMax == existing.estimatedOneRepMax &&
                    candidate.personalRecordID.uuidString > existing.personalRecordID.uuidString
                )

            if shouldReplace {
                partialResult[record.exerciseName] = candidate
            }
        }
    }

    private static func epleyEstimatedOneRepMax(for record: PersonalRecord) -> Double {
        record.weight * (1.0 + Double(record.repCount) / 30.0)
    }

    private static func roundOneRepMax(_ value: Double, unit: WeightUnit) -> Double {
        switch unit {
        case .lbs:
            return (value / 5.0).rounded() * 5.0
        case .kg:
            return (value / 2.5).rounded() * 2.5
        }
    }

    nonisolated private static func personalRecordSort(_ lhs: PersonalRecord, _ rhs: PersonalRecord) -> Bool {
        if lhs.exerciseName != rhs.exerciseName {
            return lhs.exerciseName < rhs.exerciseName
        }
        if lhs.repCount != rhs.repCount {
            return lhs.repCount < rhs.repCount
        }
        if lhs.dateAchieved != rhs.dateAchieved {
            return lhs.dateAchieved < rhs.dateAchieved
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func combineEncodable<Value: Encodable>(_ value: Value?, into hasher: inout Hasher) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            hasher.combine(0)
            return
        }
        hasher.combine(data)
    }
}
