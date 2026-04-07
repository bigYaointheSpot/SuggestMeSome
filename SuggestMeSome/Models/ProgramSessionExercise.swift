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
    /// Target reps-in-reserve (RIR); nil when not prescribed.
    var targetRIR: Double?
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
    /// Effort indicator source for this row.
    var targetEffortType: ProgramTargetEffortType?

    // MARK: Generation assumptions (future adaptive progression foundation)

    /// Lift used as the load anchor for this row (direct exercise or mapped source lift).
    var baseLiftUsed: String?
    /// Effective 1RM used to derive this row's prescribed weight.
    var effectiveOneRepMax: Double?
    var effectiveOneRepMaxUnit: String?
    /// True when load came from a mapped source lift instead of direct exercise 1RM.
    var usedMappedSourceLift: Bool?
    /// Progression phase at generation time.
    var progressionPhase: ProgramProgressionPhase?
    /// Estimated fatigue contribution of this row.
    var estimatedFatigueScore: Double?
    /// Shared group id tying warmup/top/backoff rows for the same lift prescription block.
    var topBackoffGroupID: UUID?

    var session: ProgramSessionTemplate?

    init(
        id: UUID = UUID(),
        exerciseName: String,
        orderIndex: Int,
        targetSets: Int? = nil,
        targetReps: Int? = nil,
        targetPercentage1RM: Double? = nil,
        targetRPE: Double? = nil,
        targetRIR: Double? = nil,
        isWarmup: Bool = false,
        prescribedWeight: Double? = nil,
        prescribedWeightUnit: String? = nil,
        workingSetStyle: ProgramWorkingSetStyle? = nil,
        backoffPercentageDrop: Double? = nil,
        targetEffortType: ProgramTargetEffortType? = nil,
        baseLiftUsed: String? = nil,
        effectiveOneRepMax: Double? = nil,
        effectiveOneRepMaxUnit: String? = nil,
        usedMappedSourceLift: Bool? = nil,
        progressionPhase: ProgramProgressionPhase? = nil,
        estimatedFatigueScore: Double? = nil,
        topBackoffGroupID: UUID? = nil
    ) {
        self.id = id
        self.exerciseName = exerciseName
        self.orderIndex = orderIndex
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.targetPercentage1RM = targetPercentage1RM
        self.targetRPE = targetRPE
        self.targetRIR = targetRIR
        self.isWarmup = isWarmup
        self.prescribedWeight = prescribedWeight
        self.prescribedWeightUnit = prescribedWeightUnit
        self.workingSetStyle = workingSetStyle
        self.backoffPercentageDrop = backoffPercentageDrop
        self.targetEffortType = targetEffortType
        self.baseLiftUsed = baseLiftUsed
        self.effectiveOneRepMax = effectiveOneRepMax
        self.effectiveOneRepMaxUnit = effectiveOneRepMaxUnit
        self.usedMappedSourceLift = usedMappedSourceLift
        self.progressionPhase = progressionPhase
        self.estimatedFatigueScore = estimatedFatigueScore
        self.topBackoffGroupID = topBackoffGroupID
    }
}
