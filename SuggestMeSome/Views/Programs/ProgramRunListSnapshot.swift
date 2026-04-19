import Foundation
import SwiftData

private struct ProgramRunListRefreshFingerprint: Hashable {
    let runFingerprints: [ProgramRunRefreshFingerprint]
    let workoutFingerprints: [ProgramRunWorkoutRefreshFingerprint]
    let proposalFingerprints: [ProgramRunProposalRefreshFingerprint]
    let eventFingerprints: [ProgramRunEventRefreshFingerprint]
}

private struct ProgramRunRefreshFingerprint: Hashable {
    let runID: UUID
    let startDate: Date
    let endDate: Date?
    let isCompleted: Bool
    let syncVersion: Int
    let syncLastModifiedAt: Date
}

private struct ProgramRunWorkoutRefreshFingerprint: Hashable {
    let workoutID: UUID
    let date: Date
    let syncVersion: Int
    let syncLastModifiedAt: Date
    let runID: UUID?
    let weekNumber: Int?
    let sessionNumber: Int?
}

private struct ProgramRunProposalRefreshFingerprint: Hashable {
    let proposalID: UUID
    let runID: UUID?
    let priority: Int
    let statusRawValue: String
    let createdAt: Date
    let syncVersion: Int
    let syncLastModifiedAt: Date
}

private struct ProgramRunEventRefreshFingerprint: Hashable {
    let eventID: UUID
    let runID: UUID?
    let timestamp: Date
    let eventTypeRawValue: String
}

private struct TrainingProgramsPreviewCacheRefreshFingerprint: Hashable {
    let overlayFingerprints: [ProgramRunOverlayRefreshFingerprint]
}

private struct ProgramRunOverlayRefreshFingerprint: Hashable {
    let overlayID: UUID
    let runID: UUID?
    let appliedAt: Date
    let overlayStatusRawValue: String
    let summaryText: String
    let syncVersion: Int
    let syncLastModifiedAt: Date
}

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
    let blockReviewAvailable: Bool
    let completedWorkoutBySessionKey: [ProgramRunSessionPreviewKey: Workout]

    static func fallback(for run: ProgramRun) -> ProgramRunRowSnapshot {
        ProgramRunRowSnapshot(
            completedWorkoutCount: 0,
            totalWorkoutCount: (run.program?.lengthInWeeks ?? 0) * (run.program?.sessionsPerWeek ?? 0),
            pendingProposalCount: 0,
            adaptationEventCount: 0,
            sourceLabel: programSourceLabel(for: run.program?.source),
            blockReviewAvailable: MesocycleReviewService.isEligible(for: run),
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
            let progressSnapshot = ProgramRunProgressReadSnapshot.build(
                for: run,
                workouts: runWorkouts
            )
            let completedWorkoutBySessionKey = progressSnapshot.workoutBySessionKey.reduce(
                into: [ProgramRunSessionPreviewKey: Workout]()
            ) { workoutsBySessionKey, entry in
                workoutsBySessionKey[
                    ProgramRunSessionPreviewKey(
                        runID: run.id,
                        weekNumber: entry.key.weekNumber,
                        sessionNumber: entry.key.sessionNumber
                    )
                ] = entry.value
            }

            result[run.id] = ProgramRunRowSnapshot(
                completedWorkoutCount: progressSnapshot.completedWorkoutCount,
                totalWorkoutCount: progressSnapshot.totalSessions,
                pendingProposalCount: pendingProposalCountByRunID[run.id] ?? 0,
                adaptationEventCount: adaptationEventCountByRunID[run.id] ?? 0,
                sourceLabel: ProgramRunRowSnapshot.fallback(for: run).sourceLabel,
                blockReviewAvailable: MesocycleReviewService.isEligible(for: run),
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
        proposals: [AdaptationProposal],
        events: [AdaptationEventHistory]
    ) -> Int {
        let fingerprint = ProgramRunListRefreshFingerprint(
            runFingerprints: programRuns
                .map { run in
                    ProgramRunRefreshFingerprint(
                        runID: run.id,
                        startDate: run.startDate,
                        endDate: run.endDate,
                        isCompleted: run.isCompleted,
                        syncVersion: run.syncVersion,
                        syncLastModifiedAt: run.syncLastModifiedAt
                    )
                }
                .sorted(by: { lhs, rhs in
                    if lhs.startDate != rhs.startDate {
                        return lhs.startDate > rhs.startDate
                    }
                    return lhs.runID.uuidString > rhs.runID.uuidString
                }),
            workoutFingerprints: workouts
                .map { workout in
                    ProgramRunWorkoutRefreshFingerprint(
                        workoutID: workout.id,
                        date: workout.date,
                        syncVersion: workout.syncVersion,
                        syncLastModifiedAt: workout.syncLastModifiedAt,
                        runID: workout.programRun?.id,
                        weekNumber: workout.programWeekNumber,
                        sessionNumber: workout.programSessionNumber
                    )
                }
                .sorted(by: { lhs, rhs in
                    if lhs.date != rhs.date {
                        return lhs.date > rhs.date
                    }
                    return lhs.workoutID.uuidString > rhs.workoutID.uuidString
                }),
            proposalFingerprints: proposals
                .map { proposal in
                    ProgramRunProposalRefreshFingerprint(
                        proposalID: proposal.id,
                        runID: proposal.programRun?.id,
                        priority: proposal.priority,
                        statusRawValue: proposal.proposalStatus.rawValue,
                        createdAt: proposal.createdAt,
                        syncVersion: proposal.syncVersion,
                        syncLastModifiedAt: proposal.syncLastModifiedAt
                    )
                }
                .sorted(by: { lhs, rhs in
                    if lhs.createdAt != rhs.createdAt {
                        return lhs.createdAt > rhs.createdAt
                    }
                    return lhs.proposalID.uuidString > rhs.proposalID.uuidString
                }),
            eventFingerprints: events
                .map { event in
                    ProgramRunEventRefreshFingerprint(
                        eventID: event.id,
                        runID: event.programRun?.id,
                        timestamp: event.timestamp,
                        eventTypeRawValue: event.eventType.rawValue
                    )
                }
                .sorted(by: { lhs, rhs in
                    if lhs.timestamp != rhs.timestamp {
                        return lhs.timestamp > rhs.timestamp
                    }
                    return lhs.eventID.uuidString > rhs.eventID.uuidString
                })
        )

        var hasher = Hasher()
        hasher.combine(fingerprint)
        return hasher.finalize()
    }

    static func previewCacheRefreshToken(overlays: [AppliedProgramOverlay]) -> Int {
        let fingerprint = TrainingProgramsPreviewCacheRefreshFingerprint(
            overlayFingerprints: overlays
                .map { overlay in
                    ProgramRunOverlayRefreshFingerprint(
                        overlayID: overlay.id,
                        runID: overlay.programRun?.id,
                        appliedAt: overlay.appliedAt,
                        overlayStatusRawValue: overlay.overlayStatus.rawValue,
                        summaryText: overlay.summaryText ?? "",
                        syncVersion: overlay.syncVersion,
                        syncLastModifiedAt: overlay.syncLastModifiedAt
                    )
                }
                .sorted(by: { lhs, rhs in
                    if lhs.appliedAt != rhs.appliedAt {
                        return lhs.appliedAt > rhs.appliedAt
                    }
                    return lhs.overlayID.uuidString > rhs.overlayID.uuidString
                })
        )

        var hasher = Hasher()
        hasher.combine(fingerprint)
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
