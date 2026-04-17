import Foundation

enum SessionOutcomeScoringEngine {
    private static let standaloneRecencyHalfLifeDays = 42.0

    static func inferScore(
        for input: SessionOutcomeInput,
        historicalEntries: [ExerciseEntry]
    ) -> SessionOutcomeInferredScore {
        if input.source == .programLinked && input.hasPrescription {
            return inferProgramLinkedScore(
                for: input,
                historicalEntries: historicalEntries
            )
        }

        return inferBaselineScore(
            for: input,
            historicalEntries: historicalEntries
        )
    }

    private static func inferProgramLinkedScore(
        for input: SessionOutcomeInput,
        historicalEntries: [ExerciseEntry]
    ) -> SessionOutcomeInferredScore {
        let isPowerliftingLift =
            input.canonicalLiftKey == CanonicalLift.squat.rawValue ||
            input.canonicalLiftKey == CanonicalLift.bench.rawValue ||
            input.canonicalLiftKey == CanonicalLift.deadlift.rawValue

        let completionRatio: Double? = {
            guard let prescribedSets = input.entry.prescribedTargetSets, prescribedSets > 0 else { return nil }
            return Double(input.validSets.count) / Double(prescribedSets)
        }()

        let repsDelta: Double? = {
            guard let prescribedReps = input.entry.prescribedTargetReps,
                  prescribedReps > 0,
                  let topSet = input.topSet else {
                return nil
            }
            return Double(topSet.reps - prescribedReps)
        }()

        let loadDeltaPercent: Double? = {
            guard let prescribedWeight = input.entry.prescribedWeight,
                  prescribedWeight > 0,
                  let topSet = input.topSet else {
                return nil
            }
            let prescribedLbs = SessionOutcomeMath.inLbs(
                prescribedWeight,
                unitString: input.entry.prescribedWeightUnit ?? input.entry.unit.rawValue
            )
            let topLbs = SessionOutcomeMath.inLbs(topSet.weight, unit: input.entry.unit)
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

        var scoreValue = SessionOutcomeMath.weightedAverage(components) ?? 0
        var usedFallbackBaseline = false
        var notes = "method=program-prescription"

        let hasRPEorRIRTarget =
            input.entry.prescribedTargetRPE != nil ||
            input.entry.prescribedTargetRIR != nil
        if hasRPEorRIRTarget {
            scoreValue *= 0.75
            notes += "; rpe_or_rir_target=true; reduced_magnitude_for_inferred_effort=true"
        }

        if loadDeltaPercent == nil,
           let topSetE1RMLbs = input.topSetEstimatedOneRepMaxLbs,
           let baseline = buildBaseline(
               for: input,
               historicalEntries: historicalEntries
           ) {
            let fallbackDelta = (topSetE1RMLbs - baseline.baselineE1RMLbs) / baseline.baselineE1RMLbs
            scoreValue += fallbackDelta * 30.0
            usedFallbackBaseline = true
            notes += "; fallback_baseline_delta_pct=\(SessionOutcomeMath.fmt1(fallbackDelta * 100))"
        }

        let performanceScore: PerformanceScore = {
            if components.isEmpty && !usedFallbackBaseline { return .insufficientData }
            return SessionOutcomeMath.classifyScore(
                scoreValue,
                severeThreshold: 12,
                standardThreshold: hasRPEorRIRTarget ? 6 : 4
            )
        }()
        let fatigueStatus = SessionOutcomeMath.inferFatigueStatus(
            scoreValue: scoreValue,
            completionRatio: completionRatio,
            loadDeltaPercent: loadDeltaPercent
        )

        notes += "; top_set_priority=\(isPowerliftingLift)"
        notes += "; completion=\(SessionOutcomeMath.fmt2(completionRatio))"
        notes += "; load_delta_pct=\(SessionOutcomeMath.fmt1(loadDeltaPercent.map { $0 * 100 }))"
        notes += "; reps_delta=\(SessionOutcomeMath.fmt1(repsDelta))"

        let signalConfidence: WorkoutSignalConfidence =
            performanceScore == .insufficientData ? .medium : .high
        let signalWeight: Double =
            performanceScore == .insufficientData ? 0.75 : AdaptiveSignalWeights.programWorkout

        return SessionOutcomeInferredScore(
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

    private static func inferBaselineScore(
        for input: SessionOutcomeInput,
        historicalEntries: [ExerciseEntry]
    ) -> SessionOutcomeInferredScore {
        guard let topSetE1RMLbs = input.topSetEstimatedOneRepMaxLbs else {
            return SessionOutcomeInferredScore(
                scoreValue: 0,
                performanceScore: .insufficientData,
                fatigueStatus: .manageable,
                signalConfidence: .low,
                signalWeight: input.source == .programLinked ? 0.75 : 0.45,
                completionRatio: nil,
                loadDeltaPercent: nil,
                repsDelta: nil,
                isTopSetSignal: true,
                notes: "method=baseline; reason=no-top-set"
            )
        }

        guard let baseline = buildBaseline(
            for: input,
            historicalEntries: historicalEntries
        ) else {
            return SessionOutcomeInferredScore(
                scoreValue: 0,
                performanceScore: .insufficientData,
                fatigueStatus: .manageable,
                signalConfidence: .low,
                signalWeight: input.source == .programLinked ? 0.80 : 0.45,
                completionRatio: nil,
                loadDeltaPercent: nil,
                repsDelta: nil,
                isTopSetSignal: true,
                notes: "method=baseline; reason=no-history"
            )
        }

        let deltaPercent = (topSetE1RMLbs - baseline.baselineE1RMLbs) / baseline.baselineE1RMLbs
        var scoreValue = deltaPercent * 100

        if baseline.sampleCount < 3 {
            scoreValue *= 0.80
        }

        let performanceScore = SessionOutcomeMath.classifyScore(
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
            if baseline.sampleCount >= 5 { return input.source == .programLinked ? .high : .medium }
            if baseline.sampleCount >= 3 { return .medium }
            return .low
        }()
        let weight: Double = {
            switch confidence {
            case .high:
                return input.source == .programLinked
                    ? AdaptiveSignalWeights.programWorkout
                    : AdaptiveSignalWeights.standaloneWorkout
            case .medium:
                return input.source == .programLinked
                    ? 0.85
                    : AdaptiveSignalWeights.standaloneWorkout
            case .low:
                return input.source == .programLinked ? 0.75 : 0.45
            }
        }()

        let notes = [
            "method=baseline",
            "baseline_e1rm_lbs=\(SessionOutcomeMath.fmt1(baseline.baselineE1RMLbs))",
            "current_e1rm_lbs=\(SessionOutcomeMath.fmt1(topSetE1RMLbs))",
            "delta_pct=\(SessionOutcomeMath.fmt1(deltaPercent * 100))",
            "samples=\(baseline.sampleCount)",
            "exact_matches=\(baseline.exactMatchCount)",
            "family_matches=\(baseline.familyMatchCount)",
            "half_life_days=\(SessionOutcomeMath.fmt1(standaloneRecencyHalfLifeDays))"
        ].joined(separator: "; ")

        return SessionOutcomeInferredScore(
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
        for input: SessionOutcomeInput,
        historicalEntries: [ExerciseEntry]
    ) -> SessionOutcomeBaselineResult? {
        var weightedSum = 0.0
        var totalWeight = 0.0
        var sampleCount = 0
        var exactMatchCount = 0
        var familyMatchCount = 0

        for prior in historicalEntries {
            let priorSets = SessionOutcomeHistoryLoader.validLoggedSets(for: prior)
            guard !priorSets.isEmpty, let priorWorkout = prior.workout else { continue }

            let exactMatch = prior.exerciseName == input.entry.exerciseName
            let familyMatch: Bool = {
                guard let canonicalLiftKey = input.canonicalLiftKey else { return false }
                return SessionOutcomeMath.resolveCanonicalLiftKey(for: prior.exerciseName) == canonicalLiftKey
            }()

            guard exactMatch || familyMatch else { continue }
            guard let priorTop = SessionOutcomeMath.topSet(from: priorSets) else { continue }

            let priorTopLbs = SessionOutcomeMath.inLbs(priorTop.weight, unit: prior.unit)
            let priorE1RM = SessionOutcomeMath.estimatedOneRepMax(weight: priorTopLbs, reps: priorTop.reps)
            let ageDays = max(0.0, input.workout.date.timeIntervalSince(priorWorkout.date) / 86_400.0)

            let recencyWeight = pow(0.5, ageDays / standaloneRecencyHalfLifeDays)
            let identityWeight = exactMatch ? 1.0 : 0.75
            let sampleWeight = recencyWeight * identityWeight

            weightedSum += priorE1RM * sampleWeight
            totalWeight += sampleWeight
            sampleCount += 1
            if exactMatch {
                exactMatchCount += 1
            } else {
                familyMatchCount += 1
            }
        }

        guard sampleCount > 0, totalWeight > 0 else { return nil }
        return SessionOutcomeBaselineResult(
            baselineE1RMLbs: weightedSum / totalWeight,
            sampleCount: sampleCount,
            exactMatchCount: exactMatchCount,
            familyMatchCount: familyMatchCount
        )
    }
}
