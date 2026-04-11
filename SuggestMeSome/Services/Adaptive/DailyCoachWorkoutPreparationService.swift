//
//  DailyCoachWorkoutPreparationService.swift
//  SuggestMeSome
//
//  Feature 7 — Produces a modified workout draft for today only based on the
//  Daily Coach's primary suggestion type.
//
//  Rules:
//  - Never mutates any ProgramSessionExercise or TrainingProgram object.
//  - No SwiftData writes. No overlay creation. No AdaptationProposal creation.
//  - The resulting draft exists only in memory for the workout being launched.
//

import Foundation

// MARK: - PreparedWorkoutDraft

/// An ephemeral, in-memory workout draft produced by the preparation service.
/// Contains the modified exercise entries and a plain-English list of each change made.
struct PreparedWorkoutDraft {
    let entries: [DraftExerciseEntry]
    let changeDescriptions: [String]
    let adjustmentType: DailySuggestionType
}

// MARK: - DailyCoachWorkoutPreparationService

@MainActor
struct DailyCoachWorkoutPreparationService {

    // MARK: - Public Entry Point

    /// Returns a `PreparedWorkoutDraft` by applying the given suggestion type
    /// to the resolved session exercises. The base program is never touched.
    static func prepare(
        exercises: [ProgramSessionExercise],
        suggestionType: DailySuggestionType
    ) -> PreparedWorkoutDraft {
        let ordered = exercises.sorted { $0.orderIndex < $1.orderIndex }
        switch suggestionType {
        case .trimAccessories:
            return applyTrimAccessories(ordered)
        case .trimOneBackoffSet:
            return applyTrimOneBackoffSet(ordered)
        case .reduceWorkingLoadsSlightly:
            return applyReduceWorkingLoads(ordered)
        case .suggestManualVariationSwap:
            return applyVariationSwapReview(ordered)
        default:
            let entries = buildDraftEntries(from: ordered)
            return PreparedWorkoutDraft(entries: entries, changeDescriptions: [], adjustmentType: suggestionType)
        }
    }

    // MARK: - trimAccessories

    private static func applyTrimAccessories(_ ordered: [ProgramSessionExercise]) -> PreparedWorkoutDraft {
        let groups = ProgramSessionRowGroupingService.group(ordered)

        // Identify accessory groups and score them (lower value = lower priority = trim first).
        var accessoryItems: [(index: Int, priority: Int, name: String)] = []
        for (i, group) in groups.enumerated() {
            guard let anchor = group.first(where: { !$0.isWarmup }) ?? group.first else { continue }
            guard isAccessory(anchor) else { continue }
            accessoryItems.append((index: i, priority: accessoryPriority(anchor), name: anchor.exerciseName))
        }

        if accessoryItems.isEmpty {
            // Fallback: trim the last group that has no workingSetStyle and no topBackoffGroupID,
            // as long as it is not the first group in the session.
            let candidateIndex = groups.indices.last(where: { idx in
                idx > 0 && groups[idx].allSatisfy {
                    $0.topBackoffGroupID == nil && $0.workingSetStyle == nil && !$0.isWarmup
                }
            })
            if let idx = candidateIndex {
                let name = groups[idx].first?.exerciseName ?? "accessory exercise"
                let remaining = groups.enumerated()
                    .filter { $0.offset != idx }
                    .flatMap { $0.element }
                let entries = buildDraftEntries(from: remaining)
                return PreparedWorkoutDraft(
                    entries: entries,
                    changeDescriptions: ["Removed \(name) (lowest-priority accessory)"],
                    adjustmentType: .trimAccessories
                )
            }
            let entries = buildDraftEntries(from: ordered)
            return PreparedWorkoutDraft(
                entries: entries,
                changeDescriptions: ["No accessories identified — session unchanged"],
                adjustmentType: .trimAccessories
            )
        }

        // Sort ascending by priority and trim 1 (or 2 if 3+ accessories exist).
        let sorted = accessoryItems.sorted { $0.priority < $1.priority }
        let trimCount = sorted.count >= 3 ? 2 : 1
        let toTrimIndices = Set(sorted.prefix(trimCount).map { $0.index })
        let trimmedNames = sorted.prefix(trimCount).map { $0.name }

        let remaining = groups.enumerated().flatMap { (i, group) -> [ProgramSessionExercise] in
            toTrimIndices.contains(i) ? [] : group
        }

        let entries = buildDraftEntries(from: remaining)
        let descriptions = trimmedNames.map { "Removed \($0) (lowest-priority accessory)" }
        return PreparedWorkoutDraft(entries: entries, changeDescriptions: descriptions, adjustmentType: .trimAccessories)
    }

    // MARK: - trimOneBackoffSet

    private static func applyTrimOneBackoffSet(_ ordered: [ProgramSessionExercise]) -> PreparedWorkoutDraft {
        let backoffRows = ordered.filter { $0.workingSetStyle == .backoff }

        if backoffRows.isEmpty {
            // Fallback: trim the last set in the primary block when no explicit backoff rows exist.
            let groups = ProgramSessionRowGroupingService.group(ordered)
            if let primaryGroup = groups.first(where: { $0.contains { !$0.isWarmup } }),
               primaryGroup.count > 1,
               let rowToRemove = primaryGroup.last {
                let remaining = ordered.filter { $0.id != rowToRemove.id }
                let setCount = rowToRemove.targetSets ?? 1
                let setLabel = setCount == 1 ? "1 set" : "\(setCount) sets"
                let entries = buildDraftEntries(from: remaining)
                return PreparedWorkoutDraft(
                    entries: entries,
                    changeDescriptions: ["Removed \(setLabel) from \(rowToRemove.exerciseName)"],
                    adjustmentType: .trimOneBackoffSet
                )
            }
            let entries = buildDraftEntries(from: ordered)
            return PreparedWorkoutDraft(
                entries: entries,
                changeDescriptions: ["No backoff sets found — session unchanged"],
                adjustmentType: .trimOneBackoffSet
            )
        }

        // Group backoff rows by topBackoffGroupID; nil keys are their own group.
        var byGroupID: [UUID?: [ProgramSessionExercise]] = [:]
        for row in backoffRows {
            byGroupID[row.topBackoffGroupID, default: []].append(row)
        }

        guard let largestEntry = byGroupID.max(by: { $0.value.count < $1.value.count }) else {
            let entries = buildDraftEntries(from: ordered)
            return PreparedWorkoutDraft(entries: entries, changeDescriptions: [], adjustmentType: .trimOneBackoffSet)
        }

        let groupRows = largestEntry.value.sorted { $0.orderIndex < $1.orderIndex }
        guard let rowToRemove = groupRows.last else {
            let entries = buildDraftEntries(from: ordered)
            return PreparedWorkoutDraft(entries: entries, changeDescriptions: [], adjustmentType: .trimOneBackoffSet)
        }

        let remaining = ordered.filter { $0.id != rowToRemove.id }
        let setCount = rowToRemove.targetSets ?? 1
        let setLabel = setCount == 1 ? "1 backoff set" : "\(setCount) backoff sets"
        let entries = buildDraftEntries(from: remaining)
        return PreparedWorkoutDraft(
            entries: entries,
            changeDescriptions: ["Removed \(setLabel) from \(rowToRemove.exerciseName)"],
            adjustmentType: .trimOneBackoffSet
        )
    }

    // MARK: - reduceWorkingLoadsSlightly

    private static func applyReduceWorkingLoads(_ ordered: [ProgramSessionExercise]) -> PreparedWorkoutDraft {
        var entries = buildDraftEntries(from: ordered)
        var didReduceAny = false

        for i in entries.indices {
            guard !entries[i].isCardio else { continue }
            for j in entries[i].sets.indices {
                guard !entries[i].sets[j].isWarmup else { continue }
                let text = entries[i].sets[j].weightText
                if let w = Double(text), w > 0 {
                    let reduced = (w * 0.95).rounded()
                    entries[i].sets[j].weightText = formatWeight(reduced)
                    didReduceAny = true
                }
            }
        }

        let description = didReduceAny
            ? "Working loads reduced by ~5% for today only"
            : "No prescribed loads found — session structure unchanged"
        return PreparedWorkoutDraft(
            entries: entries,
            changeDescriptions: [description],
            adjustmentType: .reduceWorkingLoadsSlightly
        )
    }

    // MARK: - suggestManualVariationSwap

    private static func applyVariationSwapReview(_ ordered: [ProgramSessionExercise]) -> PreparedWorkoutDraft {
        let entries = buildDraftEntries(from: ordered)
        let primaryName = ordered
            .first(where: { !$0.isWarmup && ($0.workingSetStyle == .topSet || $0.workingSetStyle == nil) })?
            .exerciseName

        var descriptions = ["Session loaded as-planned (no automatic swaps)"]
        if let name = primaryName {
            descriptions.append("Pain flagged — consider swapping \(name) to a pain-free movement before starting")
        } else {
            descriptions.append("Pain flagged — review and swap any painful movements manually")
        }
        descriptions.append("All exercise names remain editable once the session is open")

        return PreparedWorkoutDraft(
            entries: entries,
            changeDescriptions: descriptions,
            adjustmentType: .suggestManualVariationSwap
        )
    }

    // MARK: - Draft Building

    private static func buildDraftEntries(from exercises: [ProgramSessionExercise]) -> [DraftExerciseEntry] {
        ProgramWorkoutDraftBuilder.buildEntries(from: exercises) { _ in
            AppPreferences.defaultWeightUnit
        }
    }

    // MARK: - Accessory Detection

    private static func isAccessory(_ exercise: ProgramSessionExercise) -> Bool {
        if let purpose = exercise.explainabilityPurpose {
            return purpose != .specificity
        }
        // Fallback: no topBackoffGroupID and no workingSetStyle = likely an accessory
        return exercise.topBackoffGroupID == nil && exercise.workingSetStyle == nil && !exercise.isWarmup
    }

    /// Returns a priority score — lower value means remove first.
    private static func accessoryPriority(_ exercise: ProgramSessionExercise) -> Int {
        switch exercise.explainabilitySelectionReason {
        case .defaultRule:        return 0
        case .noveltyRotation:    return 1
        case .recoveryBias:       return 2
        case .fatigueFit:         return 3
        case .movementCoverage:   return 4
        case .muscleDeficit:      return 5
        case .sessionSpecificity: return 6
        case nil:                 return 2
        }
    }

    // MARK: - Formatting

    private static func formatWeight(_ w: Double?) -> String {
        guard let w, w > 0 else { return "" }
        return w.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(w)) : String(format: "%.1f", w)
    }

}
