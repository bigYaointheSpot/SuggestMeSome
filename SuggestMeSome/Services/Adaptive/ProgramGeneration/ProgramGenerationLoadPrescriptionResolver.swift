import Foundation

struct ProgramGenerationLoadPrescriptionResolver {

    func computePrescribedLoadContext(
        exercise: TemplateExercise,
        percentage1RM: Double?,
        oneRepMaxes: [String: (weight: Double, unit: String)]
    ) -> ProgramGenerationPrescribedLoadContext {
        let baseLift: String?
        let effectiveORM: (weight: Double, unit: String)?
        let usedMapped: Bool

        if let direct = oneRepMaxes[exercise.exerciseName] {
            baseLift = exercise.exerciseName
            effectiveORM = direct
            usedMapped = false
        } else if let sourceLift = exercise.loadSourceLift, let sourceORM = oneRepMaxes[sourceLift] {
            let multiplier = exercise.loadMultiplier ?? 1.0
            baseLift = sourceLift
            effectiveORM = (weight: sourceORM.weight * multiplier, unit: sourceORM.unit)
            usedMapped = true
        } else {
            baseLift = nil
            effectiveORM = nil
            usedMapped = false
        }

        guard let pct = percentage1RM, let orm = effectiveORM else {
            return ProgramGenerationPrescribedLoadContext(
                prescribedWeight: nil,
                prescribedWeightUnit: nil,
                baseLiftUsed: baseLift,
                effectiveOneRepMax: effectiveORM?.weight,
                effectiveOneRepMaxUnit: effectiveORM?.unit,
                usedMappedSourceLift: usedMapped
            )
        }

        let raw = pct * orm.weight
        let rounded: Double
        if orm.unit == "lbs" {
            rounded = max(5.0, (raw / 5.0).rounded() * 5.0)
        } else {
            rounded = max(2.5, (raw / 2.5).rounded() * 2.5)
        }
        return ProgramGenerationPrescribedLoadContext(
            prescribedWeight: rounded,
            prescribedWeightUnit: orm.unit,
            baseLiftUsed: baseLift,
            effectiveOneRepMax: orm.weight,
            effectiveOneRepMaxUnit: orm.unit,
            usedMappedSourceLift: usedMapped
        )
    }
}
