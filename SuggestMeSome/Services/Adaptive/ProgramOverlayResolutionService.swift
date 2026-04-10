//
//  ProgramOverlayResolutionService.swift
//  SuggestMeSome
//
//  Created by Codex on 4/7/26.
//

import Foundation
import SwiftData

/// Resolves future-session program rows by applying active overlays non-destructively.
/// Base `TrainingProgram` templates stay unchanged; overlay effects are materialized at runtime.
@MainActor
enum ProgramOverlayResolutionService {
    static func resolvedExercises(
        for run: ProgramRun,
        week: Int,
        session: Int,
        context: ModelContext
    ) -> [ProgramSessionExercise] {
        guard
            let program = run.program,
            let weekTemplate = program.weeks.first(where: { $0.weekNumber == week }),
            let sessionTemplate = weekTemplate.sessions.first(where: { $0.sessionNumber == session })
        else {
            return []
        }

        let baseRows = sessionTemplate.exercises.sorted { $0.orderIndex < $1.orderIndex }
        guard !baseRows.isEmpty else { return [] }

        var resolvedRows = baseRows.map(cloneRow)
        let overlays = (try? context.fetch(FetchDescriptor<AppliedProgramOverlay>())) ?? []
        let applicableAdjustments = overlays
            .filter { overlay in
                guard overlay.programRun?.id == run.id else { return false }
                guard overlay.overlayStatus == .active else { return false }
                guard overlay.effectiveWeekStart <= week else { return false }
                if let weekEnd = overlay.effectiveWeekEnd, weekEnd < week { return false }
                return true
            }
            .sorted { lhs, rhs in
                if lhs.appliedAt == rhs.appliedAt { return lhs.id.uuidString < rhs.id.uuidString }
                return lhs.appliedAt < rhs.appliedAt
            }
            .flatMap { overlay in
                overlay.adjustments
                    .filter { adjustment in
                        if let targetWeek = adjustment.targetWeekNumber, targetWeek != week { return false }
                        if let targetSession = adjustment.targetSessionNumber, targetSession != session { return false }
                        return true
                    }
                    .sorted {
                        if $0.sequence == $1.sequence { return $0.id.uuidString < $1.id.uuidString }
                        return $0.sequence < $1.sequence
                    }
            }

        guard !applicableAdjustments.isEmpty else { return resolvedRows }

        for adjustment in applicableAdjustments {
            apply(adjustment: adjustment, to: &resolvedRows)
        }

        return resolvedRows
    }

    // MARK: - Adjustment Application

    private static func apply(
        adjustment: AppliedOverlayAdjustment,
        to rows: inout [ProgramSessionExercise]
    ) {
        switch adjustment.adjustmentType {
        case .variationSwap:
            guard let replacement = adjustment.replacementExerciseName, !replacement.isEmpty else { return }
            let indices = targetIndices(
                for: adjustment,
                rows: rows,
                includeGroupedRows: true
            )
            guard !indices.isEmpty else { return }

            for index in indices {
                applyVariationSwap(replacement: replacement, to: &rows[index])
            }

        case .volume:
            let indices = targetIndices(
                for: adjustment,
                rows: rows,
                includeGroupedRows: false
            )
            for index in indices {
                applySetAdjustment(
                    setDelta: adjustment.setDelta,
                    absoluteTargetSets: adjustment.absoluteTargetSets,
                    to: &rows[index]
                )
            }

        case .load:
            let indices = targetIndices(
                for: adjustment,
                rows: rows,
                includeGroupedRows: false
            )
            for index in indices {
                applyLoadAdjustment(
                    loadPercentDelta: adjustment.loadPercentDelta,
                    absoluteWeight: adjustment.absolutePrescribedWeight,
                    to: &rows[index]
                )
                applySetAdjustment(
                    setDelta: adjustment.setDelta,
                    absoluteTargetSets: adjustment.absoluteTargetSets,
                    to: &rows[index]
                )
            }

        case .deload:
            let indices = targetIndices(
                for: adjustment,
                rows: rows,
                includeGroupedRows: false
            )
            for index in indices {
                applyLoadAdjustment(
                    loadPercentDelta: adjustment.loadPercentDelta,
                    absoluteWeight: adjustment.absolutePrescribedWeight,
                    to: &rows[index]
                )
                applySetAdjustment(
                    setDelta: adjustment.setDelta,
                    absoluteTargetSets: adjustment.absoluteTargetSets,
                    to: &rows[index]
                )
            }

        case .reps:
            let indices = targetIndices(
                for: adjustment,
                rows: rows,
                includeGroupedRows: false
            )
            for index in indices {
                applyRepAdjustment(
                    repDelta: adjustment.repDelta,
                    absoluteTargetReps: adjustment.absoluteTargetReps,
                    to: &rows[index]
                )
            }
        }
    }

    private static func targetIndices(
        for adjustment: AppliedOverlayAdjustment,
        rows: [ProgramSessionExercise],
        includeGroupedRows: Bool
    ) -> [Int] {
        guard let targetID = adjustment.targetProgramSessionExerciseID else {
            return rows.indices.map { $0 }
        }
        guard let targetIndex = rows.firstIndex(where: { $0.id == targetID }) else {
            return []
        }

        guard includeGroupedRows else {
            return [targetIndex]
        }

        let targetGroup = rows[targetIndex].topBackoffGroupID
        if let targetGroup {
            return rows.indices.filter { rows[$0].topBackoffGroupID == targetGroup }
        }
        return [targetIndex]
    }

    private static func applyVariationSwap(
        replacement: String,
        to row: inout ProgramSessionExercise
    ) {
        let previousExerciseName = row.exerciseName
        row.exerciseName = replacement

        if let mapping = FocusTemplateLibrary.loadMapping(for: replacement) {
            row.baseLiftUsed = mapping.sourceLift
            row.usedMappedSourceLift = true
        } else {
            row.baseLiftUsed = replacement
            row.usedMappedSourceLift = false
        }

        guard let targetPercent = row.targetPercentage1RM, targetPercent > 0 else { return }

        let unit = normalizedUnit(
            preferred: row.effectiveOneRepMaxUnit ?? row.prescribedWeightUnit ?? "lbs"
        )
        let replacementMultiplier = FocusTemplateLibrary.loadMapping(for: replacement)?.multiplier ?? 1.0
        let previousMultiplier = FocusTemplateLibrary.loadMapping(for: previousExerciseName)?.multiplier ?? 1.0

        let baseOneRepMax: Double? = {
            if let orm = row.effectiveOneRepMax, orm > 0 {
                return orm
            }
            if let prescribed = row.prescribedWeight, prescribed > 0 {
                let denominator = targetPercent * max(0.10, previousMultiplier)
                guard denominator > 0 else { return nil }
                return prescribed / denominator
            }
            return nil
        }()

        guard let baseOneRepMax, baseOneRepMax > 0 else { return }
        row.effectiveOneRepMax = baseOneRepMax
        row.effectiveOneRepMaxUnit = unit

        let derivedWeight = baseOneRepMax * replacementMultiplier * targetPercent
        row.prescribedWeight = roundedPrescribedWeight(derivedWeight, unit: unit)
        row.prescribedWeightUnit = unit
    }

    private static func applyLoadAdjustment(
        loadPercentDelta: Double?,
        absoluteWeight: Double?,
        to row: inout ProgramSessionExercise
    ) {
        guard !row.isWarmup else { return }

        let unit = normalizedUnit(
            preferred: row.effectiveOneRepMaxUnit ?? row.prescribedWeightUnit ?? "lbs"
        )
        if let absoluteWeight, absoluteWeight > 0 {
            row.prescribedWeight = roundedPrescribedWeight(absoluteWeight, unit: unit)
            row.prescribedWeightUnit = unit
            return
        }

        guard let loadPercentDelta, abs(loadPercentDelta) > 0.0001 else { return }
        let factor = max(0.10, 1.0 + loadPercentDelta)

        if let current = row.prescribedWeight, current > 0 {
            row.prescribedWeight = roundedPrescribedWeight(current * factor, unit: unit)
            row.prescribedWeightUnit = unit
        }
        if let targetPercent = row.targetPercentage1RM, targetPercent > 0 {
            row.targetPercentage1RM = max(0.35, min(1.10, targetPercent * factor))
        }
        if row.prescribedWeight == nil,
           let orm = row.effectiveOneRepMax,
           orm > 0,
           let targetPercent = row.targetPercentage1RM,
           targetPercent > 0 {
            let multiplier = FocusTemplateLibrary.loadMapping(for: row.exerciseName)?.multiplier ?? 1.0
            row.prescribedWeight = roundedPrescribedWeight(
                orm * multiplier * targetPercent,
                unit: unit
            )
            row.prescribedWeightUnit = unit
        }
    }

    private static func applySetAdjustment(
        setDelta: Int?,
        absoluteTargetSets: Int?,
        to row: inout ProgramSessionExercise
    ) {
        guard !row.isWarmup else { return }
        if let absoluteTargetSets, absoluteTargetSets > 0 {
            row.targetSets = absoluteTargetSets
            return
        }
        guard let setDelta, setDelta != 0 else { return }
        let currentSets = max(1, row.targetSets ?? 1)
        row.targetSets = max(1, currentSets + setDelta)
    }

    private static func applyRepAdjustment(
        repDelta: Int?,
        absoluteTargetReps: Int?,
        to row: inout ProgramSessionExercise
    ) {
        guard !row.isWarmup else { return }
        if let absoluteTargetReps, absoluteTargetReps > 0 {
            row.targetReps = absoluteTargetReps
            return
        }
        guard let repDelta, repDelta != 0 else { return }
        let currentReps = max(1, row.targetReps ?? 1)
        row.targetReps = max(1, currentReps + repDelta)
    }

    // MARK: - Clone

    private static func cloneRow(_ source: ProgramSessionExercise) -> ProgramSessionExercise {
        ProgramSessionExercise(
            id: source.id,
            exerciseName: source.exerciseName,
            orderIndex: source.orderIndex,
            targetSets: source.targetSets,
            targetReps: source.targetReps,
            targetPercentage1RM: source.targetPercentage1RM,
            targetRPE: source.targetRPE,
            targetRIR: source.targetRIR,
            isWarmup: source.isWarmup,
            prescribedWeight: source.prescribedWeight,
            prescribedWeightUnit: source.prescribedWeightUnit,
            workingSetStyle: source.workingSetStyle,
            backoffPercentageDrop: source.backoffPercentageDrop,
            targetEffortType: source.targetEffortType,
            baseLiftUsed: source.baseLiftUsed,
            effectiveOneRepMax: source.effectiveOneRepMax,
            effectiveOneRepMaxUnit: source.effectiveOneRepMaxUnit,
            usedMappedSourceLift: source.usedMappedSourceLift,
            progressionPhase: source.progressionPhase,
            estimatedFatigueScore: source.estimatedFatigueScore,
            topBackoffGroupID: source.topBackoffGroupID
        )
    }

    // MARK: - Formatting

    private static func normalizedUnit(preferred: String) -> String {
        preferred.lowercased() == "kg" ? "kg" : "lbs"
    }

    private static func roundedPrescribedWeight(_ weight: Double, unit: String) -> Double {
        let increment = unit.lowercased() == "kg" ? 2.5 : 5.0
        guard increment > 0 else { return weight }
        return (weight / increment).rounded() * increment
    }
}
