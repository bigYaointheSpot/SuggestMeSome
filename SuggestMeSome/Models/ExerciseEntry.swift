//
//  ExerciseEntry.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/5/26.
//

import Foundation
import SwiftData

@Model
final class ExerciseEntry {
    var id: UUID
    /// Snapshot of the exercise name at the time of logging.
    var exerciseName: String
    var unit: WeightUnit
    var orderIndex: Int
    var isCardio: Bool = false
    /// Duration in seconds; only set when isCardio is true.
    var cardioDurationSeconds: Int?

    // MARK: Program prescription snapshot (for future outcome comparison)
    /// Source generated row id when this entry comes from a program session prescription.
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

    // MARK: Feature 7 — Daily Coach effort capture
    /// User's subjective effort rating for this exercise after the session.
    var effortFeedback: WorkoutEffortFeedback?
    /// RPE of the top (heaviest/hardest) set for this exercise, 1–10 scale.
    var topSetRPE: Double?

    var workout: Workout?

    @Relationship(deleteRule: .cascade, inverse: \SetEntry.exerciseEntry)
    var sets: [SetEntry] = []

    init(
        id: UUID = UUID(),
        exerciseName: String,
        unit: WeightUnit,
        orderIndex: Int,
        isCardio: Bool = false,
        cardioDurationSeconds: Int? = nil,
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
        self.id = id
        self.exerciseName = exerciseName
        self.unit = unit
        self.orderIndex = orderIndex
        self.isCardio = isCardio
        self.cardioDurationSeconds = cardioDurationSeconds
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
