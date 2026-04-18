import Foundation
import SwiftData

struct ProgramRunSessionPreviewKey: Hashable {
    let runID: UUID
    let weekNumber: Int
    let sessionNumber: Int
}

struct ProgramSessionPreviewExerciseSnapshot: Identifiable, Equatable {
    let id: String
    let exerciseName: String
    let detailText: String
    let warmupCount: Int
}

struct ProgramSessionPreviewSnapshot: Equatable {
    static let empty = ProgramSessionPreviewSnapshot(workingExercises: [])

    let workingExercises: [ProgramSessionPreviewExerciseSnapshot]

    var isEmpty: Bool {
        workingExercises.isEmpty
    }

    static func load(
        for run: ProgramRun,
        weekNumber: Int,
        sessionNumber: Int,
        context: ModelContext
    ) -> ProgramSessionPreviewSnapshot {
        let allExercises = ProgramOverlayResolutionService.resolvedExercises(
            for: run,
            week: weekNumber,
            session: sessionNumber,
            context: context
        )
        let workingExercises = allExercises.filter { !$0.isWarmup }
        let warmupCounts = Dictionary(
            grouping: allExercises.filter { $0.isWarmup },
            by: \.exerciseName
        ).mapValues { $0.count }

        return ProgramSessionPreviewSnapshot(
            workingExercises: workingExercises.map { exercise in
                ProgramSessionPreviewExerciseSnapshot(
                    id: exercise.id.uuidString,
                    exerciseName: exercise.exerciseName,
                    detailText: programSessionPreviewDetailText(for: exercise),
                    warmupCount: warmupCounts[exercise.exerciseName] ?? 0
                )
            }
        )
    }
}

struct ProgramRunRowSnapshot {
    let completedWorkoutCount: Int
    let totalWorkoutCount: Int
    let pendingProposalCount: Int
    let adaptationEventCount: Int
    let sourceLabel: String
    let blockReviewSnapshot: MesocycleReviewSnapshot?
    let completedWorkoutBySessionKey: [ProgramRunSessionPreviewKey: Workout]

    static func fallback(for run: ProgramRun) -> ProgramRunRowSnapshot {
        ProgramRunRowSnapshot(
            completedWorkoutCount: 0,
            totalWorkoutCount: (run.program?.lengthInWeeks ?? 0) * (run.program?.sessionsPerWeek ?? 0),
            pendingProposalCount: 0,
            adaptationEventCount: 0,
            sourceLabel: programSourceLabel(for: run.program?.source),
            blockReviewSnapshot: nil,
            completedWorkoutBySessionKey: [:]
        )
    }

    func completedWorkout(
        weekNumber: Int,
        sessionNumber: Int,
        runID: UUID
    ) -> Workout? {
        completedWorkoutBySessionKey[
            ProgramRunSessionPreviewKey(
                runID: runID,
                weekNumber: weekNumber,
                sessionNumber: sessionNumber
            )
        ]
    }

}

struct ProgramRunListSnapshot {
    static let placeholder = ProgramRunListSnapshot(
        orderedRuns: [],
        rowSnapshotsByRunID: [:]
    )

    let orderedRuns: [ProgramRun]
    let rowSnapshotsByRunID: [UUID: ProgramRunRowSnapshot]

    func snapshot(for run: ProgramRun) -> ProgramRunRowSnapshot {
        rowSnapshotsByRunID[run.id] ?? ProgramRunRowSnapshot.fallback(for: run)
    }

    static func build(
        programRuns: [ProgramRun],
        workouts: [Workout],
        personalRecords: [PersonalRecord],
        proposals: [AdaptationProposal],
        events: [AdaptationEventHistory]
    ) -> ProgramRunListSnapshot {
        let orderedRuns = TrainingContextQueryService.activeProgramRuns(from: programRuns) +
            TrainingContextQueryService.completedProgramRuns(from: programRuns)

        let workoutsByRunID = workouts.reduce(into: [UUID: [Workout]]()) { result, workout in
            guard let runID = workout.programRun?.id else { return }
            result[runID, default: []].append(workout)
        }

        let pendingProposalCountByRunID = proposals.reduce(into: [UUID: Int]()) { result, proposal in
            guard
                proposal.proposalStatus == .pendingUserConfirmation,
                let runID = proposal.programRun?.id
            else {
                return
            }
            result[runID, default: 0] += 1
        }

        let adaptationEventCountByRunID = events.reduce(into: [UUID: Int]()) { result, event in
            guard let runID = event.programRun?.id else { return }
            result[runID, default: 0] += 1
        }

        let rowSnapshotsByRunID = orderedRuns.reduce(into: [UUID: ProgramRunRowSnapshot]()) { result, run in
            let runWorkouts = workoutsByRunID[run.id] ?? []
            let completedWorkoutBySessionKey = runWorkouts.reduce(
                into: [ProgramRunSessionPreviewKey: Workout]()
            ) { workoutsBySessionKey, workout in
                guard
                    let weekNumber = workout.programWeekNumber,
                    let sessionNumber = workout.programSessionNumber
                else {
                    return
                }

                workoutsBySessionKey[
                    ProgramRunSessionPreviewKey(
                        runID: run.id,
                        weekNumber: weekNumber,
                        sessionNumber: sessionNumber
                    )
                ] = workout
            }

            result[run.id] = ProgramRunRowSnapshot(
                completedWorkoutCount: runWorkouts.count,
                totalWorkoutCount: (run.program?.lengthInWeeks ?? 0) * (run.program?.sessionsPerWeek ?? 0),
                pendingProposalCount: pendingProposalCountByRunID[run.id] ?? 0,
                adaptationEventCount: adaptationEventCountByRunID[run.id] ?? 0,
                sourceLabel: ProgramRunRowSnapshot.fallback(for: run).sourceLabel,
                blockReviewSnapshot: TrainingContextQueryService.mesocycleReview(
                    for: run,
                    workouts: workouts,
                    personalRecords: personalRecords
                ),
                completedWorkoutBySessionKey: completedWorkoutBySessionKey
            )
        }

        return ProgramRunListSnapshot(
            orderedRuns: orderedRuns,
            rowSnapshotsByRunID: rowSnapshotsByRunID
        )
    }

    static func refreshToken(
        programRuns: [ProgramRun],
        workouts: [Workout],
        personalRecords: [PersonalRecord],
        proposals: [AdaptationProposal],
        events: [AdaptationEventHistory],
        overlays: [AppliedProgramOverlay]
    ) -> Int {
        var hasher = Hasher()

        for run in programRuns.sorted(by: { lhs, rhs in
            if lhs.startDate != rhs.startDate {
                return lhs.startDate > rhs.startDate
            }
            return lhs.id.uuidString > rhs.id.uuidString
        }) {
            hasher.combine(run.id)
            hasher.combine(run.startDate)
            hasher.combine(run.endDate)
            hasher.combine(run.isCompleted)
            hasher.combine(run.syncVersion)
            hasher.combine(run.syncLastModifiedAt)
        }

        for workout in workouts.sorted(by: { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date > rhs.date
            }
            return lhs.id.uuidString > rhs.id.uuidString
        }) {
            hasher.combine(workout.id)
            hasher.combine(workout.date)
            hasher.combine(workout.syncVersion)
            hasher.combine(workout.syncLastModifiedAt)
            hasher.combine(workout.programRun?.id)
            hasher.combine(workout.programWeekNumber)
            hasher.combine(workout.programSessionNumber)
        }

        for record in personalRecords.sorted(by: { lhs, rhs in
            if lhs.dateAchieved != rhs.dateAchieved {
                return lhs.dateAchieved > rhs.dateAchieved
            }
            return lhs.id.uuidString > rhs.id.uuidString
        }) {
            hasher.combine(record.id)
            hasher.combine(record.exerciseName)
            hasher.combine(record.repCount)
            hasher.combine(record.weight)
            hasher.combine(record.dateAchieved)
            hasher.combine(record.syncVersion)
        }

        for proposal in proposals.sorted(by: { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.id.uuidString > rhs.id.uuidString
        }) {
            hasher.combine(proposal.id)
            hasher.combine(proposal.programRun?.id)
            hasher.combine(proposal.priority)
            hasher.combine(proposal.proposalStatus.rawValue)
            hasher.combine(proposal.createdAt)
            hasher.combine(proposal.syncVersion)
            hasher.combine(proposal.syncLastModifiedAt)
        }

        for event in events.sorted(by: { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp > rhs.timestamp
            }
            return lhs.id.uuidString > rhs.id.uuidString
        }) {
            hasher.combine(event.id)
            hasher.combine(event.programRun?.id)
            hasher.combine(event.timestamp)
            hasher.combine(event.eventType.rawValue)
        }

        for overlay in overlays.sorted(by: { lhs, rhs in
            if lhs.appliedAt != rhs.appliedAt {
                return lhs.appliedAt > rhs.appliedAt
            }
            return lhs.id.uuidString > rhs.id.uuidString
        }) {
            hasher.combine(overlay.id)
            hasher.combine(overlay.programRun?.id)
            hasher.combine(overlay.appliedAt)
            hasher.combine(overlay.overlayStatus.rawValue)
            hasher.combine(overlay.summaryText)
        }

        return hasher.finalize()
    }
}

private func programSourceLabel(for source: ProgramSource?) -> String {
    switch source {
    case .userCreated:
        return "Custom Program"
    case .template:
        return "Template"
    case .aiGenerated:
        return "Smart Generated"
    case nil:
        return "Unknown"
    }
}

private func programSessionPreviewDetailText(for exercise: ProgramSessionExercise) -> String {
    let stylePrefix: String = {
        switch exercise.workingSetStyle {
        case .topSet:
            return "Top Set · "
        case .backoff:
            return "Backoff · "
        case .straight, .none:
            return "Straight Sets · "
        }
    }()

    if exercise.targetSets == nil, let minutes = exercise.targetReps {
        return "\(minutes) min"
    }

    let setsText = exercise.targetSets.map(String.init) ?? "—"
    let repsText = exercise.targetReps.map(String.init) ?? "—"

    if let percentage = exercise.targetPercentage1RM {
        let percentageInt = Int((percentage * 100).rounded())
        if let weight = exercise.prescribedWeight, let unit = exercise.prescribedWeightUnit {
            let weightText = weight == weight.rounded(.towardZero)
                ? "\(Int(weight)) \(unit)"
                : String(format: "%.1f \(unit)", weight)
            var detail = "\(setsText)×\(repsText) @ \(weightText) (\(percentageInt)%)"
            if let drop = exercise.backoffPercentageDrop {
                detail += String(format: " · -%.0f%%", drop * 100.0)
            }
            return stylePrefix + detail
        }

        var detail = "\(setsText)×\(repsText) @ \(percentageInt)%"
        if let drop = exercise.backoffPercentageDrop {
            detail += String(format: " · -%.0f%%", drop * 100.0)
        }
        return stylePrefix + detail
    }

    if let rpe = exercise.targetRPE {
        let rpeText = rpe.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(rpe))
            : String(format: "%.1f", rpe)
        return stylePrefix + "\(setsText)×\(repsText) @ RPE \(rpeText)"
    }

    return stylePrefix + "\(setsText)×\(repsText)"
}
