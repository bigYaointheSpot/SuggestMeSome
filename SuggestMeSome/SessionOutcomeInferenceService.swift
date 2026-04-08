//
//  SessionOutcomeInferenceService.swift
//  SuggestMeSome
//
//  Created by Codex on 4/7/26.
//

import Foundation
import SwiftData

/// Builds deterministic, auditable exercise-level outcomes from a completed workout.
/// - Program-linked entries with prescription data use prescribed-vs-actual scoring.
/// - Standalone entries (or program entries without usable prescriptions) use a
///   recency-weighted baseline against prior performance with lower confidence.
enum SessionOutcomeInferenceService {
    private static let standaloneRecencyHalfLifeDays = 42.0

    static func persistOutcomes(for workout: Workout, context: ModelContext) {
        let allEntries = (try? context.fetch(FetchDescriptor<ExerciseEntry>())) ?? []
        let historicalEntries = allEntries.filter {
            guard let priorWorkout = $0.workout else { return false }
            return priorWorkout.id != workout.id && priorWorkout.date < workout.date
        }

        let sortedEntries = workout.exerciseEntries.sorted {
            if $0.orderIndex == $1.orderIndex { return $0.id.uuidString < $1.id.uuidString }
            return $0.orderIndex < $1.orderIndex
        }

        for entry in sortedEntries {
            guard !entry.isCardio else { continue }

            let validSets = entry.sets
                .filter { $0.reps > 0 && $0.weight > 0 }
                .sorted { $0.setNumber < $1.setNumber }
            guard !validSets.isEmpty else { continue }

            let outcome = buildOutcome(
                for: entry,
                validSets: validSets,
                workout: workout,
                historicalEntries: historicalEntries
            )
            context.insert(outcome)
        }
    }

    // MARK: - Outcome Build

    private static func buildOutcome(
        for entry: ExerciseEntry,
        validSets: [SetEntry],
        workout: Workout,
        historicalEntries: [ExerciseEntry]
    ) -> ExercisePerformanceOutcome {
        let canonicalLiftKey = resolveCanonicalLiftKey(for: entry.exerciseName)
        let topSet = topSetFrom(validSets)
        let actualSetCount = validSets.count
        let avgReps = validSets.map { Double($0.reps) }.reduce(0, +) / Double(actualSetCount)
        let avgWeight = validSets.map(\.weight).reduce(0, +) / Double(actualSetCount)
        let topSetE1RMLbs = topSet.map { estimatedOneRepMax(weight: inLbs($0.weight, unit: entry.unit), reps: $0.reps) }

        let source: WorkoutSignalSource = workout.programRun == nil ? .standalone : .programLinked
        let hasPrescription = hasProgramPrescription(entry)

        let inferred: InferredScore
        if source == .programLinked && hasPrescription {
            inferred = inferProgramLinkedScore(
                entry: entry,
                validSets: validSets,
                topSet: topSet,
                topSetE1RMLbs: topSetE1RMLbs,
                canonicalLiftKey: canonicalLiftKey,
                historicalEntries: historicalEntries,
                workoutDate: workout.date
            )
        } else {
            inferred = inferBaselineScore(
                entry: entry,
                topSetE1RMLbs: topSetE1RMLbs,
                canonicalLiftKey: canonicalLiftKey,
                historicalEntries: historicalEntries,
                workoutDate: workout.date,
                source: source
            )
        }

        return ExercisePerformanceOutcome(
            createdAt: Date.now,
            programRun: workout.programRun,
            workout: workout,
            exerciseEntry: entry,
            workoutDate: workout.date,
            programWeekNumber: workout.programWeekNumber,
            programSessionNumber: workout.programSessionNumber,
            sourceProgramSessionExerciseID: entry.sourceProgramSessionExerciseID,
            exerciseName: entry.exerciseName,
            canonicalLiftKey: canonicalLiftKey,
            signalSource: source,
            signalConfidence: inferred.signalConfidence,
            signalWeight: inferred.signalWeight,
            prescribedSets: entry.prescribedTargetSets,
            prescribedReps: entry.prescribedTargetReps,
            prescribedWeight: entry.prescribedWeight,
            prescribedWeightUnit: entry.prescribedWeightUnit,
            prescribedTargetPercentage1RM: entry.prescribedTargetPercentage1RM,
            prescribedTargetRPE: entry.prescribedTargetRPE,
            prescribedTargetRIR: entry.prescribedTargetRIR,
            prescribedWorkingSetStyle: entry.prescribedWorkingSetStyle,
            prescribedTargetEffortType: entry.prescribedTargetEffortType,
            actualSetCount: actualSetCount,
            actualAverageReps: avgReps,
            actualAverageWeight: avgWeight,
            actualTopSetReps: topSet?.reps,
            actualTopSetWeight: topSet?.weight,
            // Stored in lbs for consistent cross-unit trend comparisons.
            actualTopSetEstimated1RM: topSetE1RMLbs,
            completionRatio: inferred.completionRatio,
            loadDeltaPercent: inferred.loadDeltaPercent,
            repsDelta: inferred.repsDelta,
            performanceScoreValue: inferred.scoreValue,
            performanceScore: inferred.performanceScore,
            inferredFatigueStatus: inferred.fatigueStatus,
            isTopSetSignal: inferred.isTopSetSignal,
            notes: inferred.notes
        )
    }

    // MARK: - Program Inference

    private static func inferProgramLinkedScore(
        entry: ExerciseEntry,
        validSets: [SetEntry],
        topSet: SetEntry?,
        topSetE1RMLbs: Double?,
        canonicalLiftKey: String?,
        historicalEntries: [ExerciseEntry],
        workoutDate: Date
    ) -> InferredScore {
        let isPowerliftingLift = canonicalLiftKey == "squat" || canonicalLiftKey == "bench" || canonicalLiftKey == "deadlift"

        let completionRatio: Double? = {
            guard let prescribedSets = entry.prescribedTargetSets, prescribedSets > 0 else { return nil }
            return Double(validSets.count) / Double(prescribedSets)
        }()

        let repsDelta: Double? = {
            guard let prescribedReps = entry.prescribedTargetReps, prescribedReps > 0, let topSet else { return nil }
            return Double(topSet.reps - prescribedReps)
        }()

        let loadDeltaPercent: Double? = {
            guard let prescribedWeight = entry.prescribedWeight, prescribedWeight > 0, let topSet else { return nil }
            let prescribedLbs = inLbs(prescribedWeight, unitString: entry.prescribedWeightUnit ?? entry.unit.rawValue)
            let topLbs = inLbs(topSet.weight, unit: entry.unit)
            guard prescribedLbs > 0 else { return nil }
            return (topLbs - prescribedLbs) / prescribedLbs
        }()

        var components: [(value: Double, weight: Double)] = []
        if let loadDeltaPercent {
            components.append((loadDeltaPercent * 100, isPowerliftingLift ? 0.65 : 0.40))
        }
        if let repsDelta {
            components.append((repsDelta * 4.0, isPowerliftingLift ? 0.20 : 0.30))
        }
        if let completionRatio {
            components.append((((completionRatio - 1.0) * 40.0), isPowerliftingLift ? 0.15 : 0.30))
        }

        var scoreValue = weightedAverage(components) ?? 0
        var usedFallbackBaseline = false
        var notes = "method=program-prescription"

        // RPE/RIR prescriptions are handled conservatively until explicit RPE/RIR logging exists.
        let hasRPEorRIRTarget = entry.prescribedTargetRPE != nil || entry.prescribedTargetRIR != nil
        if hasRPEorRIRTarget {
            scoreValue *= 0.75
            notes += "; rpe_or_rir_target=true; reduced_magnitude_for_inferred_effort=true"
        }

        // If load target is unavailable (common for RPE-only accessories), compare to inferred baseline.
        if loadDeltaPercent == nil, let topSetE1RMLbs {
            let baseline = buildBaseline(
                for: entry,
                canonicalLiftKey: canonicalLiftKey,
                historicalEntries: historicalEntries,
                workoutDate: workoutDate
            )
            if let baseline {
                let fallbackDelta = (topSetE1RMLbs - baseline.baselineE1RMLbs) / baseline.baselineE1RMLbs
                scoreValue += fallbackDelta * 30.0
                usedFallbackBaseline = true
                notes += "; fallback_baseline_delta_pct=\(fmt1(fallbackDelta * 100))"
            }
        }

        let performanceScore: PerformanceScore = {
            if components.isEmpty && !usedFallbackBaseline { return .insufficientData }
            return classifyScore(
                scoreValue,
                severeThreshold: 12,
                standardThreshold: hasRPEorRIRTarget ? 6 : 4
            )
        }()
        let fatigueStatus = inferFatigueStatus(
            scoreValue: scoreValue,
            completionRatio: completionRatio,
            loadDeltaPercent: loadDeltaPercent
        )

        notes += "; top_set_priority=\(isPowerliftingLift)"
        notes += "; completion=\(fmt2(completionRatio))"
        notes += "; load_delta_pct=\(fmt1(loadDeltaPercent.map { $0 * 100 }))"
        notes += "; reps_delta=\(fmt1(repsDelta))"

        let signalConfidence: WorkoutSignalConfidence = performanceScore == .insufficientData ? .medium : .high
        let signalWeight: Double = performanceScore == .insufficientData ? 0.75 : AdaptiveSignalWeights.programWorkout

        return InferredScore(
            scoreValue: scoreValue,
            performanceScore: performanceScore,
            fatigueStatus: fatigueStatus,
            signalConfidence: signalConfidence,
            signalWeight: signalWeight,
            completionRatio: completionRatio,
            loadDeltaPercent: loadDeltaPercent,
            repsDelta: repsDelta,
            isTopSetSignal: isPowerliftingLift,
            notes: notes
        )
    }

    // MARK: - Baseline Inference

    private static func inferBaselineScore(
        entry: ExerciseEntry,
        topSetE1RMLbs: Double?,
        canonicalLiftKey: String?,
        historicalEntries: [ExerciseEntry],
        workoutDate: Date,
        source: WorkoutSignalSource
    ) -> InferredScore {
        guard let topSetE1RMLbs else {
            return InferredScore(
                scoreValue: 0,
                performanceScore: .insufficientData,
                fatigueStatus: .manageable,
                signalConfidence: .low,
                signalWeight: source == .programLinked ? 0.75 : 0.45,
                completionRatio: nil,
                loadDeltaPercent: nil,
                repsDelta: nil,
                isTopSetSignal: true,
                notes: "method=baseline; reason=no-top-set"
            )
        }

        guard let baseline = buildBaseline(
            for: entry,
            canonicalLiftKey: canonicalLiftKey,
            historicalEntries: historicalEntries,
            workoutDate: workoutDate
        ) else {
            return InferredScore(
                scoreValue: 0,
                performanceScore: .insufficientData,
                fatigueStatus: .manageable,
                signalConfidence: .low,
                signalWeight: source == .programLinked ? 0.80 : 0.45,
                completionRatio: nil,
                loadDeltaPercent: nil,
                repsDelta: nil,
                isTopSetSignal: true,
                notes: "method=baseline; reason=no-history"
            )
        }

        let deltaPercent = (topSetE1RMLbs - baseline.baselineE1RMLbs) / baseline.baselineE1RMLbs
        var scoreValue = deltaPercent * 100

        // Lower precision for sparse history to avoid over-claiming standalone confidence.
        if baseline.sampleCount < 3 {
            scoreValue *= 0.80
        }

        let performanceScore = classifyScore(
            scoreValue,
            severeThreshold: 14,
            standardThreshold: 6
        )
        let fatigueStatus: FatigueStatus = {
            if scoreValue <= -12 { return .elevated }
            if scoreValue >= 10 { return .low }
            return .manageable
        }()

        let confidence: WorkoutSignalConfidence = {
            if baseline.sampleCount >= 5 { return source == .programLinked ? .high : .medium }
            if baseline.sampleCount >= 3 { return .medium }
            return .low
        }()
        let weight: Double = {
            switch confidence {
            case .high: return source == .programLinked ? AdaptiveSignalWeights.programWorkout : AdaptiveSignalWeights.standaloneWorkout
            case .medium: return source == .programLinked ? 0.85 : AdaptiveSignalWeights.standaloneWorkout
            case .low: return source == .programLinked ? 0.75 : 0.45
            }
        }()

        let notes = [
            "method=baseline",
            "baseline_e1rm_lbs=\(fmt1(baseline.baselineE1RMLbs))",
            "current_e1rm_lbs=\(fmt1(topSetE1RMLbs))",
            "delta_pct=\(fmt1(deltaPercent * 100))",
            "samples=\(baseline.sampleCount)",
            "exact_matches=\(baseline.exactMatchCount)",
            "family_matches=\(baseline.familyMatchCount)",
            "half_life_days=\(fmt1(standaloneRecencyHalfLifeDays))"
        ].joined(separator: "; ")

        return InferredScore(
            scoreValue: scoreValue,
            performanceScore: performanceScore,
            fatigueStatus: fatigueStatus,
            signalConfidence: confidence,
            signalWeight: weight,
            completionRatio: nil,
            loadDeltaPercent: deltaPercent,
            repsDelta: nil,
            isTopSetSignal: true,
            notes: notes
        )
    }

    private static func buildBaseline(
        for entry: ExerciseEntry,
        canonicalLiftKey: String?,
        historicalEntries: [ExerciseEntry],
        workoutDate: Date
    ) -> BaselineResult? {
        var weightedSum = 0.0
        var totalWeight = 0.0
        var sampleCount = 0
        var exactMatchCount = 0
        var familyMatchCount = 0

        for prior in historicalEntries {
            let priorSets = prior.sets.filter { $0.reps > 0 && $0.weight > 0 }
            guard !priorSets.isEmpty, let priorWorkout = prior.workout else { continue }

            let exactMatch = prior.exerciseName == entry.exerciseName
            let familyMatch: Bool = {
                guard let canonicalLiftKey else { return false }
                return resolveCanonicalLiftKey(for: prior.exerciseName) == canonicalLiftKey
            }()

            guard exactMatch || familyMatch else { continue }

            let priorTop = topSetFrom(priorSets)
            guard let priorTop else { continue }

            let priorTopLbs = inLbs(priorTop.weight, unit: prior.unit)
            let priorE1RM = estimatedOneRepMax(weight: priorTopLbs, reps: priorTop.reps)
            let ageDays = max(0.0, workoutDate.timeIntervalSince(priorWorkout.date) / 86_400.0)

            let recencyWeight = pow(0.5, ageDays / standaloneRecencyHalfLifeDays)
            let identityWeight = exactMatch ? 1.0 : 0.75
            let sampleWeight = recencyWeight * identityWeight

            weightedSum += priorE1RM * sampleWeight
            totalWeight += sampleWeight
            sampleCount += 1
            if exactMatch { exactMatchCount += 1 } else { familyMatchCount += 1 }
        }

        guard sampleCount > 0, totalWeight > 0 else { return nil }
        return BaselineResult(
            baselineE1RMLbs: weightedSum / totalWeight,
            sampleCount: sampleCount,
            exactMatchCount: exactMatchCount,
            familyMatchCount: familyMatchCount
        )
    }

    // MARK: - Helpers

    private static func hasProgramPrescription(_ entry: ExerciseEntry) -> Bool {
        entry.sourceProgramSessionExerciseID != nil ||
        entry.prescribedTargetSets != nil ||
        entry.prescribedTargetReps != nil ||
        entry.prescribedTargetPercentage1RM != nil ||
        entry.prescribedTargetRPE != nil ||
        entry.prescribedTargetRIR != nil ||
        entry.prescribedWeight != nil
    }

    private static func topSetFrom(_ sets: [SetEntry]) -> SetEntry? {
        sets.max { lhs, rhs in
            let lhsE1RM = estimatedOneRepMax(weight: lhs.weight, reps: lhs.reps)
            let rhsE1RM = estimatedOneRepMax(weight: rhs.weight, reps: rhs.reps)
            if lhsE1RM == rhsE1RM {
                if lhs.weight == rhs.weight {
                    if lhs.reps == rhs.reps {
                        return lhs.setNumber < rhs.setNumber
                    }
                    return lhs.reps < rhs.reps
                }
                return lhs.weight < rhs.weight
            }
            return lhsE1RM < rhsE1RM
        }
    }

    private static func resolveCanonicalLiftKey(for exerciseName: String) -> String? {
        let mappedSource = FocusTemplateLibrary.loadMapping(for: exerciseName)?.sourceLift
        let normalized = (mappedSource ?? exerciseName).lowercased()

        if normalized.contains("squat") { return "squat" }
        if normalized.contains("bench") { return "bench" }
        if normalized.contains("deadlift") { return "deadlift" }
        if normalized.contains("overhead press") || normalized.contains("strict press") { return "overheadPress" }
        if normalized.contains("row") { return "row" }
        return nil
    }

    private static func classifyScore(
        _ score: Double,
        severeThreshold: Double,
        standardThreshold: Double
    ) -> PerformanceScore {
        if score <= -severeThreshold { return .severeUnderperformance }
        if score <= -standardThreshold { return .underperformance }
        if score < standardThreshold { return .onTarget }
        if score < severeThreshold { return .overperformance }
        return .exceptionalPerformance
    }

    private static func inferFatigueStatus(
        scoreValue: Double,
        completionRatio: Double?,
        loadDeltaPercent: Double?
    ) -> FatigueStatus {
        if let completionRatio, completionRatio < 0.70 { return .high }
        if let loadDeltaPercent, loadDeltaPercent < -0.08 { return .high }
        if let completionRatio, completionRatio < 0.85 { return .elevated }
        if scoreValue < -10 { return .elevated }
        if scoreValue > 10 { return .low }
        return .manageable
    }

    private static func weightedAverage(_ values: [(value: Double, weight: Double)]) -> Double? {
        let valid = values.filter { $0.weight > 0 }
        guard !valid.isEmpty else { return nil }
        let weightedSum = valid.reduce(0.0) { $0 + ($1.value * $1.weight) }
        let totalWeight = valid.reduce(0.0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }
        return weightedSum / totalWeight
    }

    private static func estimatedOneRepMax(weight: Double, reps: Int) -> Double {
        if reps <= 1 { return weight }
        return weight * (1 + Double(reps) / 30.0)
    }

    private static func inLbs(_ weight: Double, unit: WeightUnit) -> Double {
        unit == .kg ? weight * 2.20462 : weight
    }

    private static func inLbs(_ weight: Double, unitString: String) -> Double {
        unitString.lowercased() == "kg" ? weight * 2.20462 : weight
    }

    private static func fmt1(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.1f", value)
    }

    private static func fmt2(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.2f", value)
    }
}

private struct BaselineResult {
    let baselineE1RMLbs: Double
    let sampleCount: Int
    let exactMatchCount: Int
    let familyMatchCount: Int
}

private struct InferredScore {
    let scoreValue: Double
    let performanceScore: PerformanceScore
    let fatigueStatus: FatigueStatus
    let signalConfidence: WorkoutSignalConfidence
    let signalWeight: Double
    let completionRatio: Double?
    let loadDeltaPercent: Double?
    let repsDelta: Double?
    let isTopSetSignal: Bool
    let notes: String
}
