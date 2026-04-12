import Foundation

/// Derives exercise preference signals from a user's recent workout history.
///
/// Purely functional — reads workout data, returns a value type, writes nothing.
/// The signals are used by `SuggestMeSomeRecommendationService` to bias anchor
/// lift selection toward familiar patterns and surface variety candidates.
struct SuggestMeSomePreferenceLearnerService {

    // MARK: - Configuration

    /// Number of recent workouts scanned for frequency counting.
    private let frequencyWindowSize: Int
    /// Minimum appearances in the frequency window to be "frequently used."
    private let frequencyThreshold: Int
    /// Number of most-recent workouts checked when determining underused exercises.
    private let recencyWindowSize: Int

    init(
        frequencyWindowSize: Int = 30,
        frequencyThreshold: Int = 3,
        recencyWindowSize: Int = 8
    ) {
        self.frequencyWindowSize = frequencyWindowSize
        self.frequencyThreshold = frequencyThreshold
        self.recencyWindowSize = recencyWindowSize
    }

    // MARK: - Public API

    /// Derives exercise preferences from the supplied workout history.
    ///
    /// - Parameter workouts: All available workouts, sorted newest-first by the caller.
    ///                       The service respects the order for recency checks.
    func learnPreferences(from workouts: [Workout]) -> SuggestMeSomeExercisePreferences {
        guard !workouts.isEmpty else {
            return SuggestMeSomeExercisePreferences()
        }

        let frequencyWindow = Array(workouts.prefix(frequencyWindowSize))
        let recencyWindow = Array(workouts.prefix(recencyWindowSize))

        let frequencyCounts = countExerciseAppearances(in: frequencyWindow)
        let recentlyUsed = Set(exerciseNamesIn(recencyWindow))

        let frequentlyUsed = frequencyCounts
            .filter { $0.value >= frequencyThreshold }
            .map(\.key)
            .sorted()

        let underused = frequencyCounts.keys
            .filter { !recentlyUsed.contains($0) }
            .sorted()

        return SuggestMeSomeExercisePreferences(
            frequentlyUsedExercises: frequentlyUsed,
            underusedExercises: underused
        )
    }

    // MARK: - Helpers

    /// Returns a dictionary mapping exercise name → appearance count across workouts.
    /// Each workout contributes at most 1 to a given exercise's count (deduped per session).
    private func countExerciseAppearances(in workouts: [Workout]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for workout in workouts {
            let namesInSession = Set(workout.exerciseEntries.map(\.exerciseName))
            for name in namesInSession {
                counts[name, default: 0] += 1
            }
        }
        return counts
    }

    /// Returns all distinct exercise names across the given workouts.
    private func exerciseNamesIn(_ workouts: [Workout]) -> [String] {
        workouts.flatMap { $0.exerciseEntries.map(\.exerciseName) }
    }
}
