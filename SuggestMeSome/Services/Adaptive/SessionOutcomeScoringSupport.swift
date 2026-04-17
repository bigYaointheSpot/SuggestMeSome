import Foundation

struct SessionOutcomeInput {
    let entry: ExerciseEntry
    let workout: Workout
    let validSets: [SetEntry]
    let canonicalLiftKey: String?
    let topSet: SetEntry?
    let actualSetCount: Int
    let averageReps: Double
    let averageWeight: Double
    let topSetEstimatedOneRepMaxLbs: Double?
    let source: WorkoutSignalSource
    let hasPrescription: Bool
}

struct SessionOutcomeBaselineResult {
    let baselineE1RMLbs: Double
    let sampleCount: Int
    let exactMatchCount: Int
    let familyMatchCount: Int
}

struct SessionOutcomeInferredScore {
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

enum SessionOutcomeBuilder {
    static func buildInput(
        for entry: ExerciseEntry,
        workout: Workout
    ) -> SessionOutcomeInput? {
        let validSets = SessionOutcomeHistoryLoader.validLoggedSets(for: entry)
        guard !validSets.isEmpty else { return nil }

        let actualSetCount = validSets.count
        let averageReps = validSets.map { Double($0.reps) }.reduce(0, +) / Double(actualSetCount)
        let averageWeight = validSets.map(\.weight).reduce(0, +) / Double(actualSetCount)
        let topSet = SessionOutcomeMath.topSet(from: validSets)
        let canonicalLiftKey = SessionOutcomeMath.resolveCanonicalLiftKey(for: entry.exerciseName)

        return SessionOutcomeInput(
            entry: entry,
            workout: workout,
            validSets: validSets,
            canonicalLiftKey: canonicalLiftKey,
            topSet: topSet,
            actualSetCount: actualSetCount,
            averageReps: averageReps,
            averageWeight: averageWeight,
            topSetEstimatedOneRepMaxLbs: topSet.map {
                SessionOutcomeMath.estimatedOneRepMax(
                    weight: SessionOutcomeMath.inLbs($0.weight, unit: entry.unit),
                    reps: $0.reps
                )
            },
            source: workout.programRun == nil ? .standalone : .programLinked,
            hasPrescription: hasProgramPrescription(entry)
        )
    }

    static func buildOutcome(
        from input: SessionOutcomeInput,
        inferred: SessionOutcomeInferredScore
    ) -> ExercisePerformanceOutcome {
        ExercisePerformanceOutcome(
            createdAt: Date.now,
            programRun: input.workout.programRun,
            workout: input.workout,
            exerciseEntry: input.entry,
            workoutDate: input.workout.date,
            programWeekNumber: input.workout.programWeekNumber,
            programSessionNumber: input.workout.programSessionNumber,
            sourceProgramSessionExerciseID: input.entry.sourceProgramSessionExerciseID,
            exerciseName: input.entry.exerciseName,
            canonicalLiftKey: input.canonicalLiftKey,
            signalSource: input.source,
            signalConfidence: inferred.signalConfidence,
            signalWeight: inferred.signalWeight,
            prescribedSets: input.entry.prescribedTargetSets,
            prescribedReps: input.entry.prescribedTargetReps,
            prescribedWeight: input.entry.prescribedWeight,
            prescribedWeightUnit: input.entry.prescribedWeightUnit,
            prescribedTargetPercentage1RM: input.entry.prescribedTargetPercentage1RM,
            prescribedTargetRPE: input.entry.prescribedTargetRPE,
            prescribedTargetRIR: input.entry.prescribedTargetRIR,
            prescribedWorkingSetStyle: input.entry.prescribedWorkingSetStyle,
            prescribedTargetEffortType: input.entry.prescribedTargetEffortType,
            actualSetCount: input.actualSetCount,
            actualAverageReps: input.averageReps,
            actualAverageWeight: input.averageWeight,
            actualTopSetReps: input.topSet?.reps,
            actualTopSetWeight: input.topSet?.weight,
            // Stored in lbs for consistent cross-unit trend comparisons.
            actualTopSetEstimated1RM: input.topSetEstimatedOneRepMaxLbs,
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

    private static func hasProgramPrescription(_ entry: ExerciseEntry) -> Bool {
        entry.sourceProgramSessionExerciseID != nil ||
        entry.prescribedTargetSets != nil ||
        entry.prescribedTargetReps != nil ||
        entry.prescribedTargetPercentage1RM != nil ||
        entry.prescribedTargetRPE != nil ||
        entry.prescribedTargetRIR != nil ||
        entry.prescribedWeight != nil
    }
}

enum SessionOutcomeMath {
    static func topSet(from sets: [SetEntry]) -> SetEntry? {
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

    static func resolveCanonicalLiftKey(for exerciseName: String) -> String? {
        let mappedSource = FocusTemplateLibrary.loadMapping(for: exerciseName)?.sourceLift
        let normalized = (mappedSource ?? exerciseName).lowercased()

        if normalized.contains(CanonicalLift.squat.rawValue) { return CanonicalLift.squat.rawValue }
        if normalized.contains(CanonicalLift.bench.rawValue) { return CanonicalLift.bench.rawValue }
        if normalized.contains(CanonicalLift.deadlift.rawValue) { return CanonicalLift.deadlift.rawValue }
        if normalized.contains("overhead press") || normalized.contains("strict press") {
            return CanonicalLift.overheadPress.rawValue
        }
        if normalized.contains("row") { return "row" }
        return nil
    }

    static func classifyScore(
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

    static func inferFatigueStatus(
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

    static func weightedAverage(_ values: [(value: Double, weight: Double)]) -> Double? {
        let valid = values.filter { $0.weight > 0 }
        guard !valid.isEmpty else { return nil }
        let weightedSum = valid.reduce(0.0) { $0 + ($1.value * $1.weight) }
        let totalWeight = valid.reduce(0.0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }
        return weightedSum / totalWeight
    }

    static func estimatedOneRepMax(weight: Double, reps: Int) -> Double {
        if reps <= 1 { return weight }
        return weight * (1 + Double(reps) / 30.0)
    }

    static func inLbs(_ weight: Double, unit: WeightUnit) -> Double {
        unit == .kg ? weight * 2.20462 : weight
    }

    static func inLbs(_ weight: Double, unitString: String) -> Double {
        unitString.lowercased() == "kg" ? weight * 2.20462 : weight
    }

    static func fmt1(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.1f", value)
    }

    static func fmt2(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.2f", value)
    }
}
