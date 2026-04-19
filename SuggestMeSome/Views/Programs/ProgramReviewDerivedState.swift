//
//  ProgramReviewDerivedState.swift
//  SuggestMeSome
//
//  Feature 16 Prompt 7 — cached review summaries and explainability state.
//

import Foundation
import SwiftData

struct ReviewPhaseGroup: Identifiable {
    let id: String
    let title: String
    let weekRange: String
    let schemeDescription: String
    let weeks: [ProgramWeekTemplate]
    let isDeload: Bool
}

struct ProgramLogicSnapshot {
    let progressionModel: String
    let usedLiftMapping: Bool
    let usedVolumeBalancing: Bool
    let usedFatigueBalancing: Bool
    let usedTopSetBackoff: Bool

    static let placeholder = ProgramLogicSnapshot(
        progressionModel: "Unknown",
        usedLiftMapping: false,
        usedVolumeBalancing: true,
        usedFatigueBalancing: true,
        usedTopSetBackoff: false
    )
}

struct ProgramReviewDerivedState {
    let refreshToken: Int
    let phaseGroups: [ReviewPhaseGroup]
    let weeklySummariesByWeek: [Int: ProgramGeneratedWeekSummary]
    let programLogic: ProgramLogicSnapshot
    let adaptiveExplanationBundle: AdaptiveExplanationBundle?

    static let placeholder = ProgramReviewDerivedState(
        refreshToken: 0,
        phaseGroups: [],
        weeklySummariesByWeek: [:],
        programLogic: .placeholder,
        adaptiveExplanationBundle: nil
    )

    static func build(
        program: TrainingProgram,
        input: ProgramGenerationInput,
        context: ModelContext,
        previous: ProgramReviewDerivedState? = nil
    ) -> ProgramReviewDerivedState {
        let nextRefreshToken = refreshToken(program: program, input: input)
        if let previous, previous.refreshToken == nextRefreshToken {
            return previous
        }

        let generationService = ProgramGenerationService()
        let weeklySummaries = generationService.weeklySummary(for: program)
        let adaptiveExplanationBundle = input.explanationBundle ?? generationService.previewAdaptiveContext(
            input: input,
            context: context
        ).explanationBundle

        return ProgramReviewDerivedState(
            refreshToken: nextRefreshToken,
            phaseGroups: buildPhaseGroups(input: input, weeks: program.weeks),
            weeklySummariesByWeek: Dictionary(
                uniqueKeysWithValues: weeklySummaries.map { ($0.weekNumber, $0) }
            ),
            programLogic: buildProgramLogic(program: program, input: input),
            adaptiveExplanationBundle: adaptiveExplanationBundle
        )
    }

    static func refreshToken(program: TrainingProgram, input: ProgramGenerationInput) -> Int {
        var hasher = Hasher()
        hasher.combine(program.id)
        hasher.combine(program.syncVersion)
        hasher.combine(program.name)
        hasher.combine(program.lengthInWeeks)
        hasher.combine(program.sessionsPerWeek)
        hasher.combine(program.descriptionText)
        hasher.combine(program.progressionModel?.rawValue)
        hasher.combine(program.usedLiftMapping)
        hasher.combine(program.usedVolumeBalancing)
        hasher.combine(program.usedFatigueBalancing)
        hasher.combine(program.usedTopSetBackoff)

        for week in program.weeks.sorted(by: weekSort) {
            hasher.combine(week.id)
            hasher.combine(week.weekNumber)
            hasher.combine(week.isDeloadWeek)
            hasher.combine(week.progressionPhase?.rawValue)
            hasher.combine(week.plannedFatigueScore)

            for session in week.sessions.sorted(by: sessionSort) {
                hasher.combine(session.id)
                hasher.combine(session.sessionNumber)
                hasher.combine(session.sessionName)
                hasher.combine(session.plannedFatigueScore)
                hasher.combine(session.explainabilityReason?.rawValue)

                for exercise in session.exercises.sorted(by: exerciseSort) {
                    hasher.combine(exercise.id)
                    hasher.combine(exercise.syncVersion)
                    hasher.combine(exercise.exerciseName)
                    hasher.combine(exercise.orderIndex)
                    hasher.combine(exercise.targetSets)
                    hasher.combine(exercise.targetReps)
                    hasher.combine(exercise.targetPercentage1RM)
                    hasher.combine(exercise.targetRPE)
                    hasher.combine(exercise.targetRIR)
                    hasher.combine(exercise.isWarmup)
                    hasher.combine(exercise.prescribedWeight)
                    hasher.combine(exercise.prescribedWeightUnit)
                    hasher.combine(exercise.workingSetStyle?.rawValue)
                    hasher.combine(exercise.backoffPercentageDrop)
                    hasher.combine(exercise.usedMappedSourceLift)
                    hasher.combine(exercise.explainabilityPurpose?.rawValue)
                    hasher.combine(exercise.explainabilitySelectionReason?.rawValue)
                }
            }
        }

        hasher.combine(input.focus.rawValue)
        hasher.combine(input.level.rawValue)
        hasher.combine(input.durationWeeks)
        hasher.combine(input.sessionsPerWeek)
        for key in input.oneRepMaxes.keys.sorted() {
            if let value = input.oneRepMaxes[key] {
                hasher.combine(key)
                hasher.combine(value.weight)
                hasher.combine(value.unit)
            }
        }
        combineEncodable(input.carryForwardContext, into: &hasher)
        combineEncodable(input.stateSnapshotOverride, into: &hasher)
        combineEncodable(input.steeringProfile, into: &hasher)
        combineEncodable(input.explanationBundle, into: &hasher)

        return hasher.finalize()
    }

    private static func buildProgramLogic(
        program: TrainingProgram,
        input: ProgramGenerationInput
    ) -> ProgramLogicSnapshot {
        let exercises = program.weeks.flatMap(\.sessions).flatMap(\.exercises)
        let mapped = program.usedLiftMapping ?? exercises.contains { $0.usedMappedSourceLift == true }
        let topBackoff = program.usedTopSetBackoff ?? exercises.contains {
            $0.workingSetStyle == .topSet || $0.workingSetStyle == .backoff
        }
        let progressionName = (program.progressionModel ?? fallbackProgressionModel(for: input.level)).displayName

        return ProgramLogicSnapshot(
            progressionModel: progressionName,
            usedLiftMapping: mapped,
            usedVolumeBalancing: program.usedVolumeBalancing ?? true,
            usedFatigueBalancing: program.usedFatigueBalancing ?? true,
            usedTopSetBackoff: topBackoff
        )
    }

    private static func fallbackProgressionModel(for level: ProgramLevel) -> ProgramProgressionModel {
        switch level {
        case .beginner:
            return .linear
        case .intermediate:
            return .dup
        case .advanced:
            return .block
        }
    }

    private static func buildPhaseGroups(
        input: ProgramGenerationInput,
        weeks: [ProgramWeekTemplate]
    ) -> [ReviewPhaseGroup] {
        let sortedWeeks = weeks.sorted(by: weekSort)
        switch input.level {
        case .beginner, .intermediate:
            let workingWeeks = sortedWeeks.filter { !$0.isDeloadWeek }
            let deloadWeeks = sortedWeeks.filter(\.isDeloadWeek)
            let scheme = input.level == .beginner
                ? "Linear: template-anchor %1RM with small weekly increases"
                : "DUP: heavy/moderate/light anchor-relative intensity shifts"
            var groups = [
                ReviewPhaseGroup(
                    id: "working",
                    title: "Working Weeks",
                    weekRange: weekRangeText(workingWeeks.isEmpty ? sortedWeeks : workingWeeks),
                    schemeDescription: scheme,
                    weeks: workingWeeks.isEmpty ? sortedWeeks : workingWeeks,
                    isDeload: false
                )
            ]

            if !deloadWeeks.isEmpty {
                groups.append(
                    ReviewPhaseGroup(
                        id: "deload",
                        title: "Deload Weeks",
                        weekRange: weekRangeText(deloadWeeks),
                        schemeDescription: "Reduced volume (~50%) with explicit intensity drop",
                        weeks: deloadWeeks,
                        isDeload: true
                    )
                )
            }
            return groups

        case .advanced:
            return buildBlockPhaseGroups(durationWeeks: input.durationWeeks, weeks: sortedWeeks)
        }
    }

    private static func buildBlockPhaseGroups(
        durationWeeks: Int,
        weeks: [ProgramWeekTemplate]
    ) -> [ReviewPhaseGroup] {
        let sequence: [(String?, Int)]
        switch durationWeeks {
        case 6:
            sequence = [("Hypertrophy", 2), (nil, 1), ("Strength", 2), ("Peaking", 1)]
        case 8:
            sequence = [("Hypertrophy", 3), (nil, 1), ("Strength", 2), ("Peaking", 1), (nil, 1)]
        case 10:
            sequence = [("Hypertrophy", 3), (nil, 1), ("Strength", 3), (nil, 1), ("Peaking", 2)]
        case 12:
            sequence = [("Hypertrophy", 4), (nil, 1), ("Strength", 3), (nil, 1), ("Peaking", 2), (nil, 1)]
        default:
            sequence = [("Hypertrophy", 4), (nil, 1), ("Strength", 3), (nil, 1), ("Peaking", 2), (nil, 1)]
        }

        var groups: [ReviewPhaseGroup] = []
        var weekIndex = 1
        for (name, count) in sequence {
            let phaseWeeks = weeks.filter { $0.weekNumber >= weekIndex && $0.weekNumber < weekIndex + count }
            let weekRange = count == 1
                ? "Week \(weekIndex)"
                : "Weeks \(weekIndex)–\(weekIndex + count - 1)"

            if let name {
                let schemeDescription: String
                switch name {
                case "Hypertrophy":
                    schemeDescription = "Anchor-relative lower intensity accumulation"
                case "Strength":
                    schemeDescription = "Anchor-relative strength intensification"
                case "Peaking":
                    schemeDescription = "Anchor-relative high-intensity peaking"
                default:
                    schemeDescription = ""
                }

                groups.append(
                    ReviewPhaseGroup(
                        id: name.lowercased(),
                        title: "\(name) Phase",
                        weekRange: weekRange,
                        schemeDescription: schemeDescription,
                        weeks: phaseWeeks,
                        isDeload: false
                    )
                )
            } else {
                groups.append(
                    ReviewPhaseGroup(
                        id: "deload-\(weekIndex)",
                        title: "Deload",
                        weekRange: weekRange,
                        schemeDescription: "Reduced volume (~50%) with explicit intensity drop",
                        weeks: phaseWeeks,
                        isDeload: true
                    )
                )
            }

            weekIndex += count
        }
        return groups
    }

    private static func weekRangeText(_ weeks: [ProgramWeekTemplate]) -> String {
        let weekNumbers = weeks.map(\.weekNumber).sorted()
        guard let first = weekNumbers.first else {
            return ""
        }
        if weekNumbers.count == 1 {
            return "Week \(first)"
        }

        var ranges: [ClosedRange<Int>] = []
        var currentStart = first
        var currentEnd = first

        for number in weekNumbers.dropFirst() {
            if number == currentEnd + 1 {
                currentEnd = number
            } else {
                ranges.append(currentStart...currentEnd)
                currentStart = number
                currentEnd = number
            }
        }
        ranges.append(currentStart...currentEnd)

        return ranges.map { range in
            range.lowerBound == range.upperBound
                ? "Week \(range.lowerBound)"
                : "Weeks \(range.lowerBound)–\(range.upperBound)"
        }
        .joined(separator: ", ")
    }

    nonisolated private static func weekSort(_ lhs: ProgramWeekTemplate, _ rhs: ProgramWeekTemplate) -> Bool {
        if lhs.weekNumber != rhs.weekNumber {
            return lhs.weekNumber < rhs.weekNumber
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    nonisolated private static func sessionSort(_ lhs: ProgramSessionTemplate, _ rhs: ProgramSessionTemplate) -> Bool {
        if lhs.sessionNumber != rhs.sessionNumber {
            return lhs.sessionNumber < rhs.sessionNumber
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    nonisolated private static func exerciseSort(_ lhs: ProgramSessionExercise, _ rhs: ProgramSessionExercise) -> Bool {
        if lhs.orderIndex != rhs.orderIndex {
            return lhs.orderIndex < rhs.orderIndex
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
