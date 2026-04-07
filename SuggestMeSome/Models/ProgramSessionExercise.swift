//
//  ProgramSessionExercise.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/6/26.
//

import Foundation
import SwiftData

enum ProgramWorkingSetStyle: String, Codable {
    case straight
    case topSet
    case backoff
}

@Model
final class ProgramSessionExercise {
    var id: UUID
    var exerciseName: String
    /// Display ordering within the session.
    var orderIndex: Int
    /// Prescribed number of sets; nil for user-created programs that leave this blank.
    var targetSets: Int?
    /// Prescribed reps per set; nil for user-created programs that leave this blank.
    var targetReps: Int?
    /// Target percentage of one-rep max (e.g. 0.85 = 85%); nil if not prescribed.
    var targetPercentage1RM: Double?
    /// Target rate of perceived exertion on a 1–10 scale; nil if not prescribed.
    var targetRPE: Double?
    /// True for warmup sets; false for working sets.
    var isWarmup: Bool = false
    /// Actual computed weight to lift, stored at generation time. Nil for RPE-only or cardio exercises.
    var prescribedWeight: Double?
    /// Unit for prescribedWeight: "lbs" or "kg". Nil when prescribedWeight is nil.
    var prescribedWeightUnit: String?
    /// Optional working-set classification for generated strength prescriptions.
    var workingSetStyle: ProgramWorkingSetStyle?
    /// Fractional backoff drop from top set load (e.g. 0.06 = 6%); only for backoff rows.
    var backoffPercentageDrop: Double?

    var session: ProgramSessionTemplate?

    init(
        id: UUID = UUID(),
        exerciseName: String,
        orderIndex: Int,
        targetSets: Int? = nil,
        targetReps: Int? = nil,
        targetPercentage1RM: Double? = nil,
        targetRPE: Double? = nil,
        isWarmup: Bool = false,
        prescribedWeight: Double? = nil,
        prescribedWeightUnit: String? = nil,
        workingSetStyle: ProgramWorkingSetStyle? = nil,
        backoffPercentageDrop: Double? = nil
    ) {
        self.id = id
        self.exerciseName = exerciseName
        self.orderIndex = orderIndex
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.targetPercentage1RM = targetPercentage1RM
        self.targetRPE = targetRPE
        self.isWarmup = isWarmup
        self.prescribedWeight = prescribedWeight
        self.prescribedWeightUnit = prescribedWeightUnit
        self.workingSetStyle = workingSetStyle
        self.backoffPercentageDrop = backoffPercentageDrop
    }
}
