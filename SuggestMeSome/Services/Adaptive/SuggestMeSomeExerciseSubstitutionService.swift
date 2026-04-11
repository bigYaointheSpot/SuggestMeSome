import Foundation

/// Equipment-aware exercise substitution service for SuggestMeSome.
///
/// Given an exercise that cannot be performed under the active equipment profile,
/// this service returns ranked substitute candidates that:
///  - match or closely approximate the original movement pattern
///  - are compatible with the given equipment profile
///  - are present in the provided exercise pool
///
/// The substitution table is intentionally compact — it covers the main seeded
/// exercises across all muscle groups and does not attempt a full ontology.
struct SuggestMeSomeExerciseSubstitutionService {

    // MARK: - Result type

    struct SubstitutionResult {
        let exercise: Exercise
        /// Short user-facing label, e.g. "Dumbbell Bench Press (replaces Bench Press)"
        let note: String
    }

    // MARK: - Public API

    /// Returns the highest-ranked compatible substitute for the given exercise, or nil.
    func bestSubstitute(
        for exercise: Exercise,
        equipmentProfile: SuggestMeSomeEquipmentProfile,
        availableExercises: [Exercise]
    ) -> SubstitutionResult? {
        rankedSubstitutes(for: exercise, equipmentProfile: equipmentProfile, availableExercises: availableExercises).first
    }

    /// Returns all ranked compatible substitutes for the given exercise.
    func rankedSubstitutes(
        for exercise: Exercise,
        equipmentProfile: SuggestMeSomeEquipmentProfile,
        availableExercises: [Exercise]
    ) -> [SubstitutionResult] {
        let lower = exercise.name.lowercased()
        guard let candidates = substitutionTable[lower] else { return [] }

        let byName: [String: Exercise] = Dictionary(
            uniqueKeysWithValues: availableExercises.map { ($0.name.lowercased(), $0) }
        )
        let profileTags = equipmentProfile.availableTags

        return candidates.compactMap { candidate in
            // Skip if the candidate's equipment isn't available in this profile
            guard !candidate.equipmentTags.isDisjoint(with: profileTags) else { return nil }
            // Skip if the exercise isn't in the available pool
            guard let sub = byName[candidate.exerciseName.lowercased()] else { return nil }
            let note = "\(sub.name) (replaces \(exercise.name) — \(candidate.label))"
            return SubstitutionResult(exercise: sub, note: note)
        }
    }

    // MARK: - Adaptation note

    /// Returns a user-facing adaptation note when substitutions were applied or
    /// the session shape had to fall back due to equipment constraints.
    /// Returns nil when no adaptation occurred.
    func adaptationNote(
        removedCompoundCount: Int,
        substitutionCount: Int,
        canBuildSession: Bool,
        equipmentProfile: SuggestMeSomeEquipmentProfile,
        mode: SuggestMeSomeSessionMode?,
        goal: SuggestMeSomeGenerationGoal?
    ) -> String? {
        guard substitutionCount > 0 || !canBuildSession else { return nil }

        let profileName = equipmentProfile.title

        // Fallback — pool too thin even after substitution
        if !canBuildSession {
            switch equipmentProfile {
            case .bodyweightOnly:
                if goal == .conditioning || mode == .conditioning {
                    return "Session adapted for \(profileName) — bodyweight conditioning and cardio intervals used instead of weighted patterns."
                }
                if mode == .lower {
                    return "Session adapted for \(profileName) — unilateral lower body and trunk work used in place of loaded squat/hinge patterns."
                }
                return "Session adapted for \(profileName) — bodyweight compound movements and circuit work used in place of loaded patterns."
            case .dumbbellsOnly, .hotelGym:
                if mode == .lower {
                    return "Session adapted for \(profileName) — unilateral lower body exercises substituted where barbell squat/hinge patterns weren't available."
                }
                return "Session partially adapted for \(profileName) — some intended movements could not be matched to available equipment."
            default:
                return "Session partially adapted for \(profileName) — some intended movements could not be matched to available equipment."
            }
        }

        // Successful substitution
        let word = substitutionCount == 1 ? "exercise" : "exercises"
        return "\(substitutionCount) \(word) adapted for \(profileName) — closest available alternatives applied."
    }

    // MARK: - Substitution table
    //
    // Key: lowercase original exercise name
    // Value: ranked candidates (first compatible match wins)
    // SubstitutionCandidate.equipmentTags: tags required for THE SUBSTITUTE (not the original)

    private struct SubstitutionCandidate {
        let exerciseName: String
        let equipmentTags: Set<String>
        let label: String   // why it was chosen, shown in the note
    }

    private let substitutionTable: [String: [SubstitutionCandidate]] = [

        // MARK: Horizontal Push
        "bench press": [
            SubstitutionCandidate(exerciseName: "Dumbbell Bench Press", equipmentTags: ["dumbbell"], label: "dumbbell variation"),
            SubstitutionCandidate(exerciseName: "Push-ups", equipmentTags: ["bodyweight"], label: "bodyweight variation"),
            SubstitutionCandidate(exerciseName: "Chest Dip", equipmentTags: ["bodyweight"], label: "bodyweight pushing compound"),
        ],
        "incline bench": [
            SubstitutionCandidate(exerciseName: "Incline Dumbbell Press", equipmentTags: ["dumbbell"], label: "dumbbell variation"),
            SubstitutionCandidate(exerciseName: "Push-ups", equipmentTags: ["bodyweight"], label: "bodyweight alternative"),
        ],
        "pause bench press": [
            SubstitutionCandidate(exerciseName: "Dumbbell Bench Press", equipmentTags: ["dumbbell"], label: "dumbbell bench alternative"),
            SubstitutionCandidate(exerciseName: "Push-ups", equipmentTags: ["bodyweight"], label: "bodyweight alternative"),
        ],
        "close grip bench press": [
            SubstitutionCandidate(exerciseName: "Close Grip Push-ups", equipmentTags: ["bodyweight"], label: "bodyweight triceps variation"),
            SubstitutionCandidate(exerciseName: "Overhead Tricep Extension", equipmentTags: ["dumbbell"], label: "dumbbell triceps work"),
        ],
        "floor press": [
            SubstitutionCandidate(exerciseName: "Dumbbell Bench Press", equipmentTags: ["dumbbell"], label: "dumbbell pressing alternative"),
            SubstitutionCandidate(exerciseName: "Push-ups", equipmentTags: ["bodyweight"], label: "bodyweight alternative"),
        ],

        // MARK: Vertical Push
        "overhead press": [
            SubstitutionCandidate(exerciseName: "DB Shoulder Press", equipmentTags: ["dumbbell"], label: "dumbbell variation"),
            SubstitutionCandidate(exerciseName: "Arnold Press", equipmentTags: ["dumbbell"], label: "dumbbell variation"),
            SubstitutionCandidate(exerciseName: "Machine Shoulder Press", equipmentTags: ["machine"], label: "machine variation"),
        ],
        "barbell strict press": [
            SubstitutionCandidate(exerciseName: "DB Shoulder Press", equipmentTags: ["dumbbell"], label: "dumbbell variation"),
            SubstitutionCandidate(exerciseName: "Arnold Press", equipmentTags: ["dumbbell"], label: "dumbbell variation"),
            SubstitutionCandidate(exerciseName: "Machine Shoulder Press", equipmentTags: ["machine"], label: "machine variation"),
        ],

        // MARK: Horizontal Pull
        "barbell row": [
            SubstitutionCandidate(exerciseName: "Dumbbell Row", equipmentTags: ["dumbbell"], label: "dumbbell variation"),
            SubstitutionCandidate(exerciseName: "Pull-ups", equipmentTags: ["bodyweight"], label: "bodyweight pulling compound"),
        ],
        "pendlay row": [
            SubstitutionCandidate(exerciseName: "Dumbbell Row", equipmentTags: ["dumbbell"], label: "dumbbell rowing alternative"),
            SubstitutionCandidate(exerciseName: "Pull-ups", equipmentTags: ["bodyweight"], label: "bodyweight pulling compound"),
        ],

        // MARK: Vertical Pull
        "lat pulldown": [
            SubstitutionCandidate(exerciseName: "Pull-ups", equipmentTags: ["bodyweight"], label: "bodyweight equivalent"),
            SubstitutionCandidate(exerciseName: "Chin-ups", equipmentTags: ["bodyweight"], label: "bodyweight variation"),
        ],
        "straight arm pulldown": [
            SubstitutionCandidate(exerciseName: "Pull-ups", equipmentTags: ["bodyweight"], label: "bodyweight pulling compound"),
            SubstitutionCandidate(exerciseName: "Chin-ups", equipmentTags: ["bodyweight"], label: "bodyweight variation"),
        ],

        // MARK: Squat
        "back squats": [
            SubstitutionCandidate(exerciseName: "Goblet Squat", equipmentTags: ["dumbbell"], label: "dumbbell squat variation"),
            SubstitutionCandidate(exerciseName: "Hack Squat", equipmentTags: ["machine"], label: "machine squat variation"),
            SubstitutionCandidate(exerciseName: "Bulgarian Split Squat", equipmentTags: ["bodyweight"], label: "unilateral bodyweight alternative"),
            SubstitutionCandidate(exerciseName: "Walking Lunges", equipmentTags: ["bodyweight"], label: "bodyweight lower-body alternative"),
        ],
        "front squat": [
            SubstitutionCandidate(exerciseName: "Goblet Squat", equipmentTags: ["dumbbell"], label: "dumbbell front-loaded squat"),
            SubstitutionCandidate(exerciseName: "Hack Squat", equipmentTags: ["machine"], label: "machine squat variation"),
            SubstitutionCandidate(exerciseName: "Bulgarian Split Squat", equipmentTags: ["bodyweight"], label: "unilateral bodyweight alternative"),
        ],
        "pause squat": [
            SubstitutionCandidate(exerciseName: "Goblet Squat", equipmentTags: ["dumbbell"], label: "dumbbell squat variation"),
            SubstitutionCandidate(exerciseName: "Bulgarian Split Squat", equipmentTags: ["bodyweight"], label: "unilateral bodyweight alternative"),
        ],
        "box squat": [
            SubstitutionCandidate(exerciseName: "Goblet Squat", equipmentTags: ["dumbbell"], label: "dumbbell squat variation"),
            SubstitutionCandidate(exerciseName: "Bulgarian Split Squat", equipmentTags: ["bodyweight"], label: "unilateral bodyweight alternative"),
        ],
        "sumo squat": [
            SubstitutionCandidate(exerciseName: "Goblet Squat", equipmentTags: ["dumbbell"], label: "dumbbell squat variation"),
            SubstitutionCandidate(exerciseName: "Bulgarian Split Squat", equipmentTags: ["bodyweight"], label: "unilateral bodyweight alternative"),
        ],
        "hack squat": [
            SubstitutionCandidate(exerciseName: "Goblet Squat", equipmentTags: ["dumbbell"], label: "dumbbell squat alternative"),
            SubstitutionCandidate(exerciseName: "Back Squats", equipmentTags: ["barbell", "rack"], label: "barbell squat alternative"),
            SubstitutionCandidate(exerciseName: "Bulgarian Split Squat", equipmentTags: ["bodyweight"], label: "unilateral alternative"),
        ],
        "leg press": [
            SubstitutionCandidate(exerciseName: "Goblet Squat", equipmentTags: ["dumbbell"], label: "dumbbell squat alternative"),
            SubstitutionCandidate(exerciseName: "Back Squats", equipmentTags: ["barbell", "rack"], label: "barbell alternative"),
            SubstitutionCandidate(exerciseName: "Bulgarian Split Squat", equipmentTags: ["bodyweight"], label: "unilateral bodyweight alternative"),
        ],

        // MARK: Hinge
        "deadlift": [
            SubstitutionCandidate(exerciseName: "Romanian Deadlift", equipmentTags: ["barbell", "rack"], label: "barbell hinge variation"),
            SubstitutionCandidate(exerciseName: "Dumbbell Row", equipmentTags: ["dumbbell"], label: "dumbbell posterior-chain work"),
            SubstitutionCandidate(exerciseName: "Glute Bridge", equipmentTags: ["bodyweight"], label: "bodyweight posterior-chain work"),
            SubstitutionCandidate(exerciseName: "Walking Lunges", equipmentTags: ["bodyweight"], label: "bodyweight lower-body alternative"),
        ],
        "sumo deadlift": [
            SubstitutionCandidate(exerciseName: "Romanian Deadlift", equipmentTags: ["barbell", "rack"], label: "barbell hinge variation"),
            SubstitutionCandidate(exerciseName: "Glute Bridge", equipmentTags: ["bodyweight"], label: "bodyweight glute/hip hinge"),
        ],
        "deficit deadlift": [
            SubstitutionCandidate(exerciseName: "Romanian Deadlift", equipmentTags: ["barbell", "rack"], label: "barbell hinge variation"),
            SubstitutionCandidate(exerciseName: "Glute Bridge", equipmentTags: ["bodyweight"], label: "bodyweight posterior chain"),
        ],
        "block pull": [
            SubstitutionCandidate(exerciseName: "Dumbbell Row", equipmentTags: ["dumbbell"], label: "dumbbell pull alternative"),
            SubstitutionCandidate(exerciseName: "Glute Bridge", equipmentTags: ["bodyweight"], label: "bodyweight posterior chain"),
        ],
        "romanian deadlift": [
            SubstitutionCandidate(exerciseName: "Glute Bridge", equipmentTags: ["bodyweight"], label: "bodyweight hip hinge"),
            SubstitutionCandidate(exerciseName: "Walking Lunges", equipmentTags: ["bodyweight"], label: "bodyweight posterior-chain work"),
            SubstitutionCandidate(exerciseName: "Bulgarian Split Squat", equipmentTags: ["bodyweight"], label: "unilateral posterior-chain work"),
        ],
        "good mornings": [
            SubstitutionCandidate(exerciseName: "Romanian Deadlift", equipmentTags: ["barbell", "rack"], label: "barbell hinge alternative"),
            SubstitutionCandidate(exerciseName: "Glute Bridge", equipmentTags: ["bodyweight"], label: "bodyweight hinge alternative"),
        ],
        "hip thrust": [
            SubstitutionCandidate(exerciseName: "Glute Bridge", equipmentTags: ["bodyweight"], label: "bodyweight glute variation"),
        ],

        // MARK: Cable / Machine Accessories
        "face pulls": [
            SubstitutionCandidate(exerciseName: "Dumbbell Row", equipmentTags: ["dumbbell"], label: "dumbbell rear-delt alternative"),
        ],
        "cable lateral raise": [
            SubstitutionCandidate(exerciseName: "DB Shoulder Press", equipmentTags: ["dumbbell"], label: "dumbbell shoulder work"),
        ],
        "pallof press": [
            SubstitutionCandidate(exerciseName: "Plank", equipmentTags: ["bodyweight"], label: "bodyweight anti-rotation core"),
            SubstitutionCandidate(exerciseName: "Dead Bug", equipmentTags: ["bodyweight"], label: "bodyweight core stability"),
        ],
        "cable crunch": [
            SubstitutionCandidate(exerciseName: "Dead Bug", equipmentTags: ["bodyweight"], label: "bodyweight core alternative"),
            SubstitutionCandidate(exerciseName: "Bird Dog", equipmentTags: ["bodyweight"], label: "bodyweight core alternative"),
        ],
        "cable pull through": [
            SubstitutionCandidate(exerciseName: "Glute Bridge", equipmentTags: ["bodyweight"], label: "bodyweight glute/hip hinge"),
        ],

        // MARK: Biceps Isolation
        "barbell curl": [
            SubstitutionCandidate(exerciseName: "EZ Bar Curl", equipmentTags: ["barbell", "rack"], label: "barbell curl variation"),
            SubstitutionCandidate(exerciseName: "Concentration Curl", equipmentTags: ["dumbbell"], label: "dumbbell curl variation"),
            SubstitutionCandidate(exerciseName: "Incline Dumbbell Curl", equipmentTags: ["dumbbell"], label: "dumbbell curl variation"),
            SubstitutionCandidate(exerciseName: "Chin-ups", equipmentTags: ["bodyweight"], label: "bodyweight biceps compound"),
        ],
        "ez bar curl": [
            SubstitutionCandidate(exerciseName: "Concentration Curl", equipmentTags: ["dumbbell"], label: "dumbbell curl variation"),
            SubstitutionCandidate(exerciseName: "Incline Dumbbell Curl", equipmentTags: ["dumbbell"], label: "dumbbell curl variation"),
            SubstitutionCandidate(exerciseName: "Chin-ups", equipmentTags: ["bodyweight"], label: "bodyweight biceps compound"),
        ],
        "cable curl": [
            SubstitutionCandidate(exerciseName: "Concentration Curl", equipmentTags: ["dumbbell"], label: "dumbbell curl variation"),
            SubstitutionCandidate(exerciseName: "Incline Dumbbell Curl", equipmentTags: ["dumbbell"], label: "dumbbell curl variation"),
        ],

        // MARK: Triceps Isolation
        "cable tricep kickback": [
            SubstitutionCandidate(exerciseName: "Overhead Tricep Extension", equipmentTags: ["dumbbell"], label: "dumbbell triceps work"),
            SubstitutionCandidate(exerciseName: "Close Grip Push-ups", equipmentTags: ["bodyweight"], label: "bodyweight triceps work"),
            SubstitutionCandidate(exerciseName: "Dips", equipmentTags: ["bodyweight"], label: "bodyweight triceps compound"),
        ],

        // MARK: Machine compound alternatives
        "pec deck machine fly": [
            SubstitutionCandidate(exerciseName: "Dumbbell Bench Press", equipmentTags: ["dumbbell"], label: "dumbbell chest pressing"),
            SubstitutionCandidate(exerciseName: "Push-ups", equipmentTags: ["bodyweight"], label: "bodyweight chest work"),
        ],
        "machine shoulder press": [
            SubstitutionCandidate(exerciseName: "DB Shoulder Press", equipmentTags: ["dumbbell"], label: "dumbbell variation"),
            SubstitutionCandidate(exerciseName: "Arnold Press", equipmentTags: ["dumbbell"], label: "dumbbell variation"),
        ],
        "seated calf raise": [
            SubstitutionCandidate(exerciseName: "Walking Lunges", equipmentTags: ["bodyweight"], label: "bodyweight lower-leg and calf work"),
        ],
    ]
}
