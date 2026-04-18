//
//  WorkoutSaveCoordinator.swift
//  SuggestMeSome
//
//  Extracted non-UI workout save orchestration.
//

import Foundation
import OSLog
import SwiftData

struct WorkoutSaveProgramContext {
    let run: ProgramRun
    let weekNumber: Int
    let sessionNumber: Int
}

struct WorkoutSaveRequest {
    let workoutID: UUID?
    let startTime: Date
    let endTime: Date
    let durationSeconds: Int?
    let caloriesText: String
    let comments: String
    let exerciseEntries: [DraftExerciseEntry]
    let programContext: WorkoutSaveProgramContext?
    let healthKitEnabled: Bool
    let healthKitWritebackEnabled: Bool
    let skipHealthKitWriteback: Bool

    init(
        workoutID: UUID? = nil,
        startTime: Date,
        endTime: Date,
        durationSeconds: Int? = nil,
        caloriesText: String,
        comments: String,
        exerciseEntries: [DraftExerciseEntry],
        programContext: WorkoutSaveProgramContext?,
        healthKitEnabled: Bool,
        healthKitWritebackEnabled: Bool,
        skipHealthKitWriteback: Bool = false
    ) {
        self.workoutID = workoutID
        self.startTime = startTime
        self.endTime = endTime
        self.durationSeconds = durationSeconds
        self.caloriesText = caloriesText
        self.comments = comments
        self.exerciseEntries = exerciseEntries
        self.programContext = programContext
        self.healthKitEnabled = healthKitEnabled
        self.healthKitWritebackEnabled = healthKitWritebackEnabled
        self.skipHealthKitWriteback = skipHealthKitWriteback
    }
}

enum WorkoutSaveTransactionStatus: Equatable {
    case persisted
    case failed(String)
}

enum WorkoutSaveSideEffectKind: String, Equatable {
    case healthKitWriteback
    case outcomePersistence
    case weeklyAnalysis
    case programCompletion
}

enum WorkoutSaveSideEffectStatus: Equatable {
    case scheduled
    case succeeded
    case skipped
    case failed
}

struct WorkoutSaveSideEffectReport: Equatable {
    let kind: WorkoutSaveSideEffectKind
    let status: WorkoutSaveSideEffectStatus
    let message: String

    var isFailure: Bool {
        status == .failed
    }

    static func scheduled(_ kind: WorkoutSaveSideEffectKind, _ message: String) -> WorkoutSaveSideEffectReport {
        WorkoutSaveSideEffectReport(kind: kind, status: .scheduled, message: message)
    }

    static func succeeded(_ kind: WorkoutSaveSideEffectKind, _ message: String) -> WorkoutSaveSideEffectReport {
        WorkoutSaveSideEffectReport(kind: kind, status: .succeeded, message: message)
    }

    static func skipped(_ kind: WorkoutSaveSideEffectKind, _ message: String) -> WorkoutSaveSideEffectReport {
        WorkoutSaveSideEffectReport(kind: kind, status: .skipped, message: message)
    }

    static func failed(_ kind: WorkoutSaveSideEffectKind, _ message: String) -> WorkoutSaveSideEffectReport {
        WorkoutSaveSideEffectReport(kind: kind, status: .failed, message: message)
    }
}

struct WorkoutSaveResult {
    let workout: Workout
    let transactionStatus: WorkoutSaveTransactionStatus
    let sideEffectReports: [WorkoutSaveSideEffectReport]

    var didPersistWorkout: Bool {
        if case .persisted = transactionStatus {
            return true
        }
        return false
    }

    var nonFatalFailures: [WorkoutSaveSideEffectReport] {
        sideEffectReports.filter(\.isFailure)
    }

    var didMarkProgramComplete: Bool {
        sideEffectReports.contains {
            $0.kind == .programCompletion && $0.status == .succeeded
        }
    }
}

protocol WorkoutSaveIssueLogging {
    func record(report: WorkoutSaveSideEffectReport)
    func record(transactionStatus: WorkoutSaveTransactionStatus)
}

struct WorkoutSaveIssueLogger: WorkoutSaveIssueLogging {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "SuggestMeSome",
        category: "WorkoutSave"
    )

    func record(report: WorkoutSaveSideEffectReport) {
        guard report.isFailure else { return }
        logger.error("\(report.kind.rawValue, privacy: .public) failed: \(report.message, privacy: .public)")
    }

    func record(transactionStatus: WorkoutSaveTransactionStatus) {
        guard case let .failed(message) = transactionStatus else { return }
        logger.error("primary persistence failed: \(message, privacy: .public)")
    }
}

@MainActor
final class WorkoutSaveCoordinator {
    private let modelContext: ModelContext
    private let writebackCoordinator: WorkoutSaveHealthKitWritebackCoordinator
    private let outcomePersistor: (Workout, ModelContext) throws -> Void
    private let weeklyAnalyzer: (Workout, ModelContext) throws -> Void
    private let issueLogger: any WorkoutSaveIssueLogging

    init(
        modelContext: ModelContext,
        writebackCoordinator: WorkoutSaveHealthKitWritebackCoordinator? = nil,
        outcomePersistor: ((Workout, ModelContext) throws -> Void)? = nil,
        weeklyAnalyzer: ((Workout, ModelContext) throws -> Void)? = nil,
        issueLogger: (any WorkoutSaveIssueLogging)? = nil
    ) {
        self.modelContext = modelContext
        self.writebackCoordinator = writebackCoordinator ?? WorkoutSaveHealthKitWritebackCoordinator()
        self.outcomePersistor = outcomePersistor ?? { workout, context in
            SessionOutcomeInferenceService.persistOutcomes(for: workout, context: context)
        }
        self.weeklyAnalyzer = weeklyAnalyzer ?? { workout, context in
            WeeklyTrainingAnalysisService.analyzeCompletedWeeks(triggeredBy: workout, context: context)
        }
        self.issueLogger = issueLogger ?? WorkoutSaveIssueLogger()
    }

    @discardableResult
    func saveWorkout(using request: WorkoutSaveRequest) -> Workout {
        saveWorkoutResult(using: request).workout
    }

    @discardableResult
    func saveWorkoutResult(using request: WorkoutSaveRequest) -> WorkoutSaveResult {
        let workout = buildWorkout(using: request)
        modelContext.insert(workout)

        var personalRecords = TrainingReadRepository.historySnapshot(context: modelContext).personalRecords
        persistExerciseEntries(request.exerciseEntries, for: workout, at: request.endTime, personalRecords: &personalRecords)

        let transactionStatus = persistPrimaryTransaction()
        issueLogger.record(transactionStatus: transactionStatus)
        guard case .persisted = transactionStatus else {
            return WorkoutSaveResult(
                workout: workout,
                transactionStatus: transactionStatus,
                sideEffectReports: []
            )
        }

        let sideEffectReports = runPostSavePipeline(for: workout, request: request)
        return WorkoutSaveResult(
            workout: workout,
            transactionStatus: transactionStatus,
            sideEffectReports: sideEffectReports
        )
    }

    private func buildWorkout(using request: WorkoutSaveRequest) -> Workout {
        let workout = Workout(
            id: request.workoutID ?? UUID(),
            date: request.endTime,
            startTime: request.startTime,
            durationSeconds: request.durationSeconds ?? Int(request.endTime.timeIntervalSince(request.startTime)),
            caloriesBurned: Int(request.caloriesText),
            comments: request.comments.isEmpty ? nil : request.comments,
            programRun: request.programContext?.run,
            programWeekNumber: request.programContext?.weekNumber,
            programSessionNumber: request.programContext?.sessionNumber
        )
        workout.initializeSyncMetadataIfNeeded(at: request.endTime)
        return workout
    }

    private func persistExerciseEntries(
        _ drafts: [DraftExerciseEntry],
        for workout: Workout,
        at date: Date,
        personalRecords: inout [PersonalRecord]
    ) {
        for draftEntry in drafts {
            let entry = ExerciseEntry(
                exerciseName: draftEntry.exerciseName,
                unit: draftEntry.unit,
                orderIndex: draftEntry.orderIndex,
                isCardio: draftEntry.isCardio,
                cardioDurationSeconds: draftEntry.isCardio ? draftEntry.cardioDurationSeconds : nil,
                sourceProgramSessionExerciseID: draftEntry.sourceProgramSessionExerciseID,
                prescribedTargetSets: draftEntry.prescribedTargetSets,
                prescribedTargetReps: draftEntry.prescribedTargetReps,
                prescribedTargetPercentage1RM: draftEntry.prescribedTargetPercentage1RM,
                prescribedTargetRPE: draftEntry.prescribedTargetRPE,
                prescribedTargetRIR: draftEntry.prescribedTargetRIR,
                prescribedWeight: draftEntry.prescribedWeight,
                prescribedWeightUnit: draftEntry.prescribedWeightUnit,
                prescribedWorkingSetStyle: draftEntry.prescribedWorkingSetStyle,
                prescribedTargetEffortType: draftEntry.prescribedTargetEffortType
            )
            entry.effortFeedback = draftEntry.isCardio ? nil : draftEntry.effortFeedback
            entry.topSetRPE = draftEntry.isCardio ? nil : draftEntry.topSetRPE
            entry.workout = workout
            modelContext.insert(entry)

            guard !draftEntry.isCardio else { continue }

            for draftSet in draftEntry.sets {
                let reps = Int(draftSet.repsText) ?? 0
                let weight = Double(draftSet.weightText) ?? 0.0
                let setEntry = SetEntry(setNumber: draftSet.setNumber, reps: reps, weight: weight)
                setEntry.exerciseEntry = entry
                modelContext.insert(setEntry)

                guard reps > 0, weight > 0 else { continue }
                evaluatePR(
                    exerciseName: draftEntry.exerciseName,
                    unit: draftEntry.unit,
                    setEntry: setEntry,
                    date: date,
                    personalRecords: &personalRecords
                )
            }
        }
    }

    private func persistPrimaryTransaction() -> WorkoutSaveTransactionStatus {
        do {
            try modelContext.save()
            return .persisted
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func runPostSavePipeline(
        for workout: Workout,
        request: WorkoutSaveRequest
    ) -> [WorkoutSaveSideEffectReport] {
        var reports: [WorkoutSaveSideEffectReport] = []
        reports.append(scheduleHealthKitWritebackIfNeeded(for: workout, request: request))
        reports.append(runSynchronousSideEffect(kind: .outcomePersistence) {
            try outcomePersistor(workout, modelContext)
            try modelContext.save()
        })
        reports.append(runSynchronousSideEffect(kind: .weeklyAnalysis) {
            try weeklyAnalyzer(workout, modelContext)
            try modelContext.save()
        })

        if let run = request.programContext?.run {
            reports.append(checkProgramCompletion(run: run))
        }

        return reports
    }

    private func scheduleHealthKitWritebackIfNeeded(
        for workout: Workout,
        request: WorkoutSaveRequest
    ) -> WorkoutSaveSideEffectReport {
        if request.skipHealthKitWriteback {
            return .skipped(
                .healthKitWriteback,
                "Linked Apple Watch HealthKit workout will stamp this workout instead of iPhone summary writeback."
            )
        }
        return writebackCoordinator.scheduleNonFatalWritebackIfEligible(
            for: workout,
            healthKitEnabled: request.healthKitEnabled,
            writebackEnabled: request.healthKitWritebackEnabled,
            persistChanges: { [self] in
                try self.modelContext.save()
            },
            onFailure: { [self] report in
                self.issueLogger.record(report: report)
            }
        )
    }

    private func runSynchronousSideEffect(
        kind: WorkoutSaveSideEffectKind,
        action: () throws -> Void
    ) -> WorkoutSaveSideEffectReport {
        do {
            try action()
            return .succeeded(kind, successMessage(for: kind))
        } catch {
            let report = WorkoutSaveSideEffectReport.failed(
                kind,
                error.localizedDescription
            )
            issueLogger.record(report: report)
            return report
        }
    }

    private func checkProgramCompletion(run: ProgramRun) -> WorkoutSaveSideEffectReport {
        guard let program = run.program else {
            return .skipped(.programCompletion, "No training program is attached to this run.")
        }
        let expected = program.lengthInWeeks * program.sessionsPerWeek
        let completed = TrainingReadRepository.programRunProgressSnapshot(
            for: run,
            context: modelContext
        ).completedWorkoutCount
        guard completed >= expected else {
            return .skipped(
                .programCompletion,
                "Program run progress is \(completed)/\(expected); completion not reached."
            )
        }
        guard !run.isCompleted else {
            return .skipped(.programCompletion, "Program run was already marked complete.")
        }

        let completedAt = Date.now
        run.isCompleted = true
        run.endDate = completedAt
        run.markSyncUpdated(at: completedAt)

        do {
            try modelContext.save()
            return .succeeded(.programCompletion, "Marked program run complete.")
        } catch {
            let report = WorkoutSaveSideEffectReport.failed(
                .programCompletion,
                error.localizedDescription
            )
            issueLogger.record(report: report)
            return report
        }
    }

    private func successMessage(for kind: WorkoutSaveSideEffectKind) -> String {
        switch kind {
        case .healthKitWriteback:
            return "Scheduled Apple Health writeback."
        case .outcomePersistence:
            return "Persisted inferred session outcomes."
        case .weeklyAnalysis:
            return "Updated weekly training analysis."
        case .programCompletion:
            return "Marked program run complete."
        }
    }

    /// Checks whether `setEntry` is a new personal record and updates the store accordingly.
    /// Weights are always compared in lbs to handle mixed-unit entries (1 kg = 2.20462 lbs).
    private func evaluatePR(
        exerciseName: String,
        unit: WeightUnit,
        setEntry: SetEntry,
        date: Date,
        personalRecords: inout [PersonalRecord]
    ) {
        let newWeightLbs = inLbs(setEntry.weight, unit: unit)

        if let existing = TrainingContextQueryService.personalRecord(
            exerciseName: exerciseName,
            repCount: setEntry.reps,
            in: personalRecords
        ) {
            guard newWeightLbs > inLbs(existing.weight, unit: existing.unit) else { return }
            existing.weight = setEntry.weight
            existing.unit = unit
            existing.dateAchieved = date
            existing.markSyncUpdated(at: date)
            setEntry.isPR = true
        } else {
            let pr = PersonalRecord(
                exerciseName: exerciseName,
                repCount: setEntry.reps,
                weight: setEntry.weight,
                unit: unit,
                dateAchieved: date
            )
            modelContext.insert(pr)
            personalRecords.append(pr)
            setEntry.isPR = true
        }
    }

    private func inLbs(_ weight: Double, unit: WeightUnit) -> Double {
        unit == .kg ? weight * 2.20462 : weight
    }
}
