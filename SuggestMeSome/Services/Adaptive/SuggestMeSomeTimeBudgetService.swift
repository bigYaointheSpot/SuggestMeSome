import Foundation

struct SuggestMeSomeTimeBudgetService {
    /// Per-exercise time multiplier applied to baseTimeMinutes for budget calculations.
    /// Lower intensity -> shorter rests -> more exercises; higher intensity -> longer rests -> fewer exercises.
    func intensityFactor(for intensity: Int) -> Double {
        0.35 + Double(intensity) * 0.05
    }

    func effectiveTimeMinutes(for exercise: Exercise, intensity: Int) -> Double {
        Double(exercise.baseTimeMinutes) * intensityFactor(for: intensity)
    }
}
