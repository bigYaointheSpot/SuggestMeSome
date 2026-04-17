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
    static func persistOutcomes(for workout: Workout, context: ModelContext) {
        let historicalEntries = SessionOutcomeHistoryLoader.loadHistoricalEntries(
            for: workout,
            context: context
        )

        for entry in SessionOutcomeHistoryLoader.sortedStrengthEntries(for: workout) {
            guard let input = SessionOutcomeBuilder.buildInput(
                for: entry,
                workout: workout
            ) else {
                continue
            }

            let inferred = SessionOutcomeScoringEngine.inferScore(
                for: input,
                historicalEntries: historicalEntries
            )
            context.insert(
                SessionOutcomeBuilder.buildOutcome(
                    from: input,
                    inferred: inferred
                )
            )
        }
    }
}
