//
//  ProgramRunContinuityService.swift
//  SuggestMeSome
//
//  Feature 13 Prompt 5 — Persist additive continuity snapshots between blocks.
//

import Foundation
import SwiftData

enum ProgramRunContinuityService {
    static func sourceRun(
        matching stableID: String,
        context: ModelContext
    ) -> ProgramRun? {
        TrainingReadRepository.programRun(
            matchingStableID: stableID,
            context: context
        )
    }

    static func recordDecision(
        on sourceRun: ProgramRun,
        review: MesocycleReviewSnapshot,
        recommendation: MesocycleNextBlockRecommendation,
        decision: MesocycleRecommendationDecision,
        editedPrefill: NextBlockPrefillContext? = nil,
        steeringProfile: AdaptiveSteeringProfile? = nil,
        decidedAt: Date = Date()
    ) {
        let existing = sourceRun.recommendationDecisionHistorySnapshot
        let recommendationSnapshots = review.rankedRecommendations.map(ProgramRunRecommendationSnapshot.init)
        let userEditedFields = decision == .accepted
            ? changedFields(
                original: recommendation.prefill,
                edited: editedPrefill ?? recommendation.prefill
            )
            : []

        let event = ProgramRunRecommendationDecisionEvent(
            recommendationStableID: recommendation.stableID,
            decision: decision,
            decidedAt: decidedAt,
            userEditedFields: userEditedFields,
            confirmedSteeringProfile: decision == .accepted
                ? (steeringProfile ?? editedPrefill?.steeringProfile ?? recommendation.prefill.steeringProfile)
                : nil,
            editedAdjustmentSnapshot: decision == .accepted
                ? (editedPrefill?.explanationBundle?.adjustments ?? recommendation.prefill.explanationBundle?.adjustments)
                : nil
        )

        let selectedRecommendationStableID = decision == .accepted
            ? recommendation.stableID
            : existing?.selectedRecommendationStableID
        let selectedRecommendationSnapshot = selectedRecommendationStableID.flatMap { stableID in
            (existing?.recommendationSnapshots ?? recommendationSnapshots)
                .first(where: { $0.stableID == stableID })
                ?? recommendationSnapshots.first(where: { $0.stableID == stableID })
        }

        let snapshot = ProgramBlockContinuitySnapshot(
            sourceProgramRunStableID: review.programRunStableID,
            sourceTrainingProgramStableID: review.trainingProgramStableID,
            reviewStableID: review.reviewStableID,
            sourceProgramName: review.programName,
            snapshotRecordedAt: decidedAt,
            recommendationSnapshots: recommendationSnapshots,
            selectedRecommendationStableID: selectedRecommendationStableID,
            selectedRecommendationSnapshot: selectedRecommendationSnapshot,
            declinedRecommendationStableIDs: decision == .declined
                ? orderedUniqueStrings((existing?.declinedRecommendationStableIDs ?? []) + [recommendation.stableID])
                : (existing?.declinedRecommendationStableIDs ?? []),
            decisionEvents: (existing?.decisionEvents ?? []) + [event],
            carriedForwardContext: decision == .accepted
                ? (editedPrefill ?? recommendation.prefill).carryForwardContext
                : existing?.carriedForwardContext,
            editedPrefillSnapshot: decision == .accepted
                ? (editedPrefill ?? recommendation.prefill)
                : existing?.editedPrefillSnapshot,
            userEditedFields: decision == .accepted
                ? userEditedFields
                : (existing?.userEditedFields ?? []),
            latestConfirmedSteeringProfile: decision == .accepted
                ? (steeringProfile ?? editedPrefill?.steeringProfile ?? recommendation.prefill.steeringProfile)
                : existing?.latestConfirmedSteeringProfile,
            latestEditedAdjustments: decision == .accepted
                ? (editedPrefill?.explanationBundle?.adjustments ?? recommendation.prefill.explanationBundle?.adjustments)
                : existing?.latestEditedAdjustments
        )

        sourceRun.recommendationDecisionHistorySnapshot = existing?.merged(with: snapshot) ?? snapshot
        sourceRun.markSyncUpdated(at: decidedAt)
    }

    static func applyAcceptedContinuity(
        to targetRun: ProgramRun,
        sourceRun: ProgramRun?,
        input: ProgramGenerationInput,
        startedAt: Date = Date()
    ) {
        guard let carryForwardContext = input.carryForwardContext else { return }

        let sourceSnapshot = sourceRun?.recommendationDecisionHistorySnapshot
        let selectedRecommendationStableID = carryForwardContext.recommendationStableID ??
            sourceSnapshot?.selectedRecommendationStableID
        let recommendationSnapshots = sourceSnapshot?.recommendationSnapshots ?? []

        targetRun.previousProgramRunStableID = carryForwardContext.sourceProgramRunStableID
        targetRun.continuitySnapshot = ProgramBlockContinuitySnapshot(
            sourceProgramRunStableID: carryForwardContext.sourceProgramRunStableID,
            sourceTrainingProgramStableID: sourceRun?.program?.resolvedSyncStableID ??
                sourceSnapshot?.sourceTrainingProgramStableID,
            reviewStableID: sourceSnapshot?.reviewStableID ??
                "\(carryForwardContext.sourceProgramRunStableID)::mesocycle-review",
            sourceProgramName: sourceRun?.program?.name ??
                sourceSnapshot?.sourceProgramName ??
                "Completed Block",
            snapshotRecordedAt: startedAt,
            recommendationSnapshots: recommendationSnapshots,
            selectedRecommendationStableID: selectedRecommendationStableID,
            selectedRecommendationSnapshot: selectedRecommendationStableID.flatMap { stableID in
                recommendationSnapshots.first(where: { $0.stableID == stableID })
            } ?? sourceSnapshot?.selectedRecommendationSnapshot,
            declinedRecommendationStableIDs: sourceSnapshot?.declinedRecommendationStableIDs ?? [],
            decisionEvents: sourceSnapshot?.decisionEvents ?? [],
            carriedForwardContext: carryForwardContext,
            editedPrefillSnapshot: sourceSnapshot?.editedPrefillSnapshot,
            userEditedFields: sourceSnapshot?.userEditedFields ?? [],
            latestConfirmedSteeringProfile: sourceSnapshot?.latestConfirmedSteeringProfile,
            latestEditedAdjustments: sourceSnapshot?.latestEditedAdjustments
        )
    }

    private static func changedFields(
        original: NextBlockPrefillContext,
        edited: NextBlockPrefillContext
    ) -> [NextBlockPrefillField] {
        var fields: [NextBlockPrefillField] = []

        if original.focus != edited.focus {
            fields.append(.focus)
        }
        if original.style != edited.style {
            fields.append(.style)
        }
        if original.durationWeeks != edited.durationWeeks {
            fields.append(.durationWeeks)
        }
        if original.sessionsPerWeek != edited.sessionsPerWeek {
            fields.append(.sessionsPerWeek)
        }
        if original.level != edited.level {
            fields.append(.level)
        }
        if original.resolvedSteeringProfile != edited.resolvedSteeringProfile {
            fields.append(.steering)
        }
        if original.preservedExerciseNames != edited.preservedExerciseNames {
            fields.append(.notableExercises)
        }
        if original.rationaleText != edited.rationaleText {
            fields.append(.rationale)
        }
        if normalizedOneRepMaxSuggestions(original.oneRepMaxSuggestions) !=
            normalizedOneRepMaxSuggestions(edited.oneRepMaxSuggestions) {
            fields.append(.trainingMaxes)
        }

        return orderedUniqueFields(fields)
    }

    private static func normalizedOneRepMaxSuggestions(
        _ suggestions: [MesocycleOneRepMaxPrefill]
    ) -> [String] {
        suggestions
            .map {
                let roundedWeight = Int(($0.weight * 100).rounded())
                return "\($0.exerciseName)|\(roundedWeight)|\($0.unit.rawValue)"
            }
            .sorted()
    }
}
