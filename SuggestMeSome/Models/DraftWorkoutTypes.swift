//
//  DraftWorkoutTypes.swift
//  SuggestMeSome
//
//  Shared in-memory draft types used by WorkoutView and the Daily Coach
//  workout preparation service. Not persisted until the user saves.
//

import Foundation

// MARK: - DraftSet

struct DraftSet: Identifiable, Codable, Equatable {
    let id: UUID
    var setNumber: Int
    var repsText: String
    var weightText: String
    var isPR: Bool
    var isWarmup: Bool
    var completionLoggedAt: Date?
    var isPrefilledFromPrescription: Bool?

    init(
        setNumber: Int,
        repsText: String = "",
        weightText: String = "",
        isPR: Bool = false,
        isWarmup: Bool = false,
        completionLoggedAt: Date? = nil,
        isPrefilledFromPrescription: Bool? = nil
    ) {
        self.id = UUID()
        self.setNumber = setNumber
        self.repsText = repsText
        self.weightText = weightText
        self.isPR = isPR
        self.isWarmup = isWarmup
        self.completionLoggedAt = completionLoggedAt
        self.isPrefilledFromPrescription = isPrefilledFromPrescription
    }
}

// MARK: - DraftExerciseEntry

struct DraftExerciseEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var exerciseName: String
    var unit: WeightUnit
    var orderIndex: Int
    var sets: [DraftSet]
    var isCardio: Bool
    var cardioMinutesText: String
    var cardioSecondsText: String
    var cardioCompletionLogged: Bool?

    // Optional prescription snapshot for program-driven workouts.
    var sourceProgramSessionExerciseID: UUID?
    var prescribedTargetSets: Int?
    var prescribedTargetReps: Int?
    var prescribedTargetPercentage1RM: Double?
    var prescribedTargetRPE: Double?
    var prescribedTargetRIR: Double?
    var prescribedWeight: Double?
    var prescribedWeightUnit: String?
    var prescribedWorkingSetStyle: ProgramWorkingSetStyle?
    var prescribedTargetEffortType: ProgramTargetEffortType?

    // Feature 7 — effort capture (non-cardio only)
    var effortFeedback: WorkoutEffortFeedback?
    /// Top-set RPE entered by the user; nil unless they chose to add it.
    var topSetRPE: Double?

    var cardioDurationSeconds: Int {
        (Int(cardioMinutesText) ?? 0) * 60 + (Int(cardioSecondsText) ?? 0)
    }

    init(
        exerciseName: String,
        unit: WeightUnit,
        orderIndex: Int,
        sets: [DraftSet],
        isCardio: Bool = false,
        cardioMinutesText: String = "",
        cardioSecondsText: String = "",
        cardioCompletionLogged: Bool? = nil,
        sourceProgramSessionExerciseID: UUID? = nil,
        prescribedTargetSets: Int? = nil,
        prescribedTargetReps: Int? = nil,
        prescribedTargetPercentage1RM: Double? = nil,
        prescribedTargetRPE: Double? = nil,
        prescribedTargetRIR: Double? = nil,
        prescribedWeight: Double? = nil,
        prescribedWeightUnit: String? = nil,
        prescribedWorkingSetStyle: ProgramWorkingSetStyle? = nil,
        prescribedTargetEffortType: ProgramTargetEffortType? = nil
    ) {
        self.id = UUID()
        self.exerciseName = exerciseName
        self.unit = unit
        self.orderIndex = orderIndex
        self.sets = sets
        self.isCardio = isCardio
        self.cardioMinutesText = cardioMinutesText
        self.cardioSecondsText = cardioSecondsText
        self.cardioCompletionLogged = cardioCompletionLogged
        self.sourceProgramSessionExerciseID = sourceProgramSessionExerciseID
        self.prescribedTargetSets = prescribedTargetSets
        self.prescribedTargetReps = prescribedTargetReps
        self.prescribedTargetPercentage1RM = prescribedTargetPercentage1RM
        self.prescribedTargetRPE = prescribedTargetRPE
        self.prescribedTargetRIR = prescribedTargetRIR
        self.prescribedWeight = prescribedWeight
        self.prescribedWeightUnit = prescribedWeightUnit
        self.prescribedWorkingSetStyle = prescribedWorkingSetStyle
        self.prescribedTargetEffortType = prescribedTargetEffortType
    }
}

extension Array where Element == DraftExerciseEntry {
    /// Preserve the current visible draft order while rewriting persisted
    /// indices into a contiguous 0-based sequence.
    func normalizedExerciseOrder() -> [DraftExerciseEntry] {
        enumerated().map { index, entry in
            var normalizedEntry = entry
            normalizedEntry.orderIndex = index
            return normalizedEntry
        }
    }
}
