//
//  FocusTemplateLibrary.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/6/26.
//

import Foundation

// MARK: - ProgramFocus

enum ProgramFocus: String, CaseIterable, Codable {
    case increaseMaxSquat
    case increaseMaxBench
    case increaseMaxDeadlift
    case powerlifting
    case generalFitness
    case fullBody
    case pushPull
    case fiveByFive
    case powerbuilding
    case bodybuilding
    case cardioEndurance
}

// MARK: - ExerciseRole

enum ExerciseRole: String, Codable {
    case primary, variation, accessory, cardio
}

// MARK: - TemplateIntensityStyle

enum TemplateIntensityStyle: String, Codable {
    case percentage
    case rpe
    case mixed
    case cardioDuration
}

// MARK: - Top/Backoff Prescriptions

struct TopSetPrescription {
    let setCount: Int
    /// Optional fixed RPE target for the top set.
    let targetRPE: Double?
}

struct BackoffPrescription {
    let setCount: Int
    /// Fractional load drop from top set (e.g. 0.05...0.08 = 5–8%).
    let loadDropRange: ClosedRange<Double>
    /// Additional reps to apply to backoff work (keeps low-rep tops from becoming all heavy singles).
    let repDelta: Int
}

// MARK: - TemplateExercise

struct TemplateExercise {
    let exerciseName: String
    let role: ExerciseRole
    let defaultSets: Int
    let defaultReps: Int
    /// Fraction of 1RM (e.g. 0.85 = 85%). Nil for RPE-based exercises.
    let percentage1RM: Double?
    /// Rate of perceived exertion, 1–10. Nil for %1RM-based exercises.
    let targetRPE: Double?
    /// Hidden metadata used for load derivation in variation lifts.
    let loadSourceLift: String?
    /// Multiplier applied to the source lift 1RM when deriving an effective 1RM.
    let loadMultiplier: Double?
    /// Optional programming style metadata for future periodization rules.
    let intensityStyle: TemplateIntensityStyle?
    /// Optional top set prescription (typically used for main lifts / key variations).
    let topSetPrescription: TopSetPrescription?
    /// Optional backoff prescription paired with top sets.
    let backoffPrescription: BackoffPrescription?

    init(
        exerciseName: String,
        role: ExerciseRole,
        defaultSets: Int,
        defaultReps: Int,
        percentage1RM: Double?,
        targetRPE: Double?,
        loadSourceLift: String? = nil,
        loadMultiplier: Double? = nil,
        intensityStyle: TemplateIntensityStyle? = nil,
        topSetPrescription: TopSetPrescription? = nil,
        backoffPrescription: BackoffPrescription? = nil
    ) {
        self.exerciseName = exerciseName
        self.role = role
        self.defaultSets = defaultSets
        self.defaultReps = defaultReps
        self.percentage1RM = percentage1RM
        self.targetRPE = targetRPE

        let mapped = FocusTemplateLibrary.loadMapping(for: exerciseName)
        self.loadSourceLift = loadSourceLift ?? mapped?.sourceLift
        self.loadMultiplier = loadMultiplier ?? mapped?.multiplier

        let topBackoff = FocusTemplateLibrary.topBackoffProfile(for: exerciseName)
        self.topSetPrescription = topSetPrescription ?? topBackoff?.topSet
        self.backoffPrescription = backoffPrescription ?? topBackoff?.backoff

        if let intensityStyle {
            self.intensityStyle = intensityStyle
        } else if role == .cardio {
            self.intensityStyle = .cardioDuration
        } else if percentage1RM != nil && targetRPE != nil {
            self.intensityStyle = .mixed
        } else if percentage1RM != nil {
            self.intensityStyle = .percentage
        } else if targetRPE != nil {
            self.intensityStyle = .rpe
        } else {
            self.intensityStyle = nil
        }
    }
}

// MARK: - SessionDefinition

struct SessionDefinition {
    let sessionName: String
    /// Always included in the session.
    let primaryExercises: [TemplateExercise]
    /// Rotate for variety; generator picks `accessoryCount` from this pool.
    let accessoryPool: [TemplateExercise]
    let accessoryCount: Int
}

// MARK: - FocusTemplate

struct FocusTemplate {
    let focus: ProgramFocus
    let displayName: String
    /// Minimum sessions per week this focus supports.
    let minimumFrequency: Int
    /// Exercise names for which the user must supply a 1RM before generation.
    let requiredLifts: [String]
    let exercisesPerSession: ClosedRange<Int>
    /// Complete session list for each supported frequency (key = sessions/week).
    let sessionDefinitions: [Int: [SessionDefinition]]
}

// MARK: - Library

enum FocusTemplateLibrary {
    struct LoadMapping {
        let sourceLift: String
        let multiplier: Double
    }

    struct TopBackoffProfile {
        let topSet: TopSetPrescription
        let backoff: BackoffPrescription
    }

    static func template(for focus: ProgramFocus) -> FocusTemplate {
        switch focus {
        case .increaseMaxSquat:    return squatTemplate
        case .increaseMaxBench:    return benchTemplate
        case .increaseMaxDeadlift: return deadliftTemplate
        case .powerlifting:        return powerliftingTemplate
        case .generalFitness:      return generalFitnessTemplate
        case .fullBody:            return fullBodyTemplate
        case .pushPull:            return pushPullTemplate
        case .fiveByFive:          return fiveByFiveTemplate
        case .powerbuilding:       return powerbuildingTemplate
        case .bodybuilding:        return bodybuildingTemplate
        case .cardioEndurance:     return cardioEnduranceTemplate
        }
    }

    static func loadMapping(for exerciseName: String) -> LoadMapping? {
        variationLoadMappings[exerciseName]
    }

    static func topBackoffProfile(for exerciseName: String) -> TopBackoffProfile? {
        topBackoffProfiles[exerciseName]
    }

    static func programmingProfile(for focus: ProgramFocus) -> ProgramFocusProgrammingProfile {
        ProgramFocusProgrammingProfileLibrary.profile(for: focus)
    }

    private static let variationLoadMappings: [String: LoadMapping] = [
        // Squat variations
        "Pause Squat": .init(sourceLift: "Back Squats", multiplier: 0.92),
        "Front Squat": .init(sourceLift: "Back Squats", multiplier: 0.85),
        "Box Squat": .init(sourceLift: "Back Squats", multiplier: 0.90),

        // Bench variations
        "Pause Bench Press": .init(sourceLift: "Bench Press", multiplier: 0.93),
        "Close Grip Bench Press": .init(sourceLift: "Bench Press", multiplier: 0.90),
        "Incline Bench": .init(sourceLift: "Bench Press", multiplier: 0.87),
        "Incline Dumbbell Press": .init(sourceLift: "Bench Press", multiplier: 0.75),
        "Floor Press": .init(sourceLift: "Bench Press", multiplier: 0.92),

        // Deadlift variations
        "Romanian Deadlift": .init(sourceLift: "Deadlift", multiplier: 0.78),
        "Deficit Deadlift": .init(sourceLift: "Deadlift", multiplier: 0.90),
        "Block Pull": .init(sourceLift: "Deadlift", multiplier: 1.05),
    ]

    private static let squatTopBackoff = TopBackoffProfile(
        topSet: .init(setCount: 1, targetRPE: 8.0),
        backoff: .init(setCount: 3, loadDropRange: 0.05...0.08, repDelta: 1)
    )

    private static let benchTopBackoff = TopBackoffProfile(
        topSet: .init(setCount: 1, targetRPE: 8.0),
        backoff: .init(setCount: 3, loadDropRange: 0.05...0.08, repDelta: 1)
    )

    private static let deadliftTopBackoff = TopBackoffProfile(
        topSet: .init(setCount: 1, targetRPE: 8.0),
        backoff: .init(setCount: 2, loadDropRange: 0.06...0.10, repDelta: 1)
    )

    private static let topBackoffProfiles: [String: TopBackoffProfile] = [
        // Main lifts
        "Back Squats": squatTopBackoff,
        "Bench Press": benchTopBackoff,
        "Deadlift": deadliftTopBackoff,

        // Key squat variations
        "Pause Squat": squatTopBackoff,
        "Front Squat": squatTopBackoff,
        "Box Squat": squatTopBackoff,

        // Key bench variations
        "Pause Bench Press": benchTopBackoff,
        "Close Grip Bench Press": benchTopBackoff,
        "Floor Press": benchTopBackoff,
        "Incline Bench": benchTopBackoff,

        // Key deadlift variations
        "Deficit Deadlift": deadliftTopBackoff,
        "Block Pull": deadliftTopBackoff,
    ]
}

// MARK: - Increase Max Squat
// Inspired by Candito and Chad Wesley Smith peaking methodologies.

private extension FocusTemplateLibrary {
    static var squatTemplate: FocusTemplate {
        let heavySquatDay = SessionDefinition(
            sessionName: "Heavy Squat Day",
            primaryExercises: [
                .init(exerciseName: "Back Squats", role: .primary, defaultSets: 5, defaultReps: 3, percentage1RM: 0.88, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Leg Press",             role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Bulgarian Split Squat", role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Good Mornings",         role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Leg Curl",              role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Ab Rollout",            role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Pallof Press",          role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 2
        )

        let volumeSquatDay = SessionDefinition(
            sessionName: "Volume Squat Day",
            primaryExercises: [
                .init(exerciseName: "Pause Squat", role: .variation, defaultSets: 4, defaultReps: 4, percentage1RM: 0.72, targetRPE: nil),
                .init(exerciseName: "Back Squats", role: .primary,   defaultSets: 3, defaultReps: 5, percentage1RM: 0.75, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Leg Press",             role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Bulgarian Split Squat", role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Leg Extension",         role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Calf Raises",           role: .accessory, defaultSets: 4, defaultReps: 12, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Pallof Press",          role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 1
        )

        let deadliftPostChainDay = SessionDefinition(
            sessionName: "Deadlift & Posterior Chain",
            primaryExercises: [
                .init(exerciseName: "Deadlift", role: .primary, defaultSets: 4, defaultReps: 3, percentage1RM: 0.85, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Romanian Deadlift", role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil,  targetRPE: 7),
                .init(exerciseName: "Hip Thrust",        role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil,  targetRPE: 7),
                .init(exerciseName: "Cable Pull Through",role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil,  targetRPE: 7),
                .init(exerciseName: "Leg Curl",          role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil,  targetRPE: 7),
                .init(exerciseName: "Pendlay Row",       role: .accessory, defaultSets: 3, defaultReps: 6,  percentage1RM: 0.75, targetRPE: nil),
                .init(exerciseName: "Good Mornings",     role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil,  targetRPE: 6),
            ],
            accessoryCount: 2
        )

        let accessoryGPPDay = SessionDefinition(
            sessionName: "Accessory & GPP",
            primaryExercises: [
                .init(exerciseName: "Leg Press", role: .accessory, defaultSets: 4, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryPool: [
                .init(exerciseName: "Walking Lunges",    role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Goblet Squat",      role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Seated Calf Raise", role: .accessory, defaultSets: 4, defaultReps: 12, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Glute Bridge",      role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Hanging Leg Raises",role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Cable Crunch",      role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Dead Bug",          role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 3
        )

        let variationBDay = SessionDefinition(
            sessionName: "Squat Variation B",
            primaryExercises: [
                .init(exerciseName: "Front Squat", role: .variation, defaultSets: 4, defaultReps: 4, percentage1RM: 0.68, targetRPE: nil),
                .init(exerciseName: "Box Squat",   role: .variation, defaultSets: 3, defaultReps: 3, percentage1RM: 0.82, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Hack Squat",    role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Leg Press",     role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Leg Extension", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Good Mornings", role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 1
        )

        let squat_upperMaintenanceDay = SessionDefinition(
            sessionName: "Upper Body Maintenance",
            primaryExercises: [
                .init(exerciseName: "Bench Press", role: .primary,   defaultSets: 3, defaultReps: 5, percentage1RM: 0.75, targetRPE: nil),
                .init(exerciseName: "Barbell Row", role: .accessory, defaultSets: 3, defaultReps: 5, percentage1RM: 0.75, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Overhead Press",  role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Lat Pulldown",    role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Tricep Pushdown", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Barbell Curl",    role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Face Pulls",      role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 2
        )

        return FocusTemplate(
            focus: .increaseMaxSquat,
            displayName: "Increase Max Squat",
            minimumFrequency: 3,
            requiredLifts: ["Back Squats", "Deadlift"],
            exercisesPerSession: 3...4,
            sessionDefinitions: [
                3: [heavySquatDay, volumeSquatDay, deadliftPostChainDay],
                4: [heavySquatDay, volumeSquatDay, deadliftPostChainDay, accessoryGPPDay],
                5: [heavySquatDay, volumeSquatDay, deadliftPostChainDay, accessoryGPPDay, variationBDay],
                6: [heavySquatDay, volumeSquatDay, deadliftPostChainDay, accessoryGPPDay, variationBDay, squat_upperMaintenanceDay],
            ]
        )
    }
}

// MARK: - Increase Max Bench
// Inspired by Strengtheory bench frequency research.

private extension FocusTemplateLibrary {
    static var benchTemplate: FocusTemplate {
        let heavyBenchDay = SessionDefinition(
            sessionName: "Heavy Bench Day",
            primaryExercises: [
                .init(exerciseName: "Bench Press", role: .primary, defaultSets: 5, defaultReps: 3, percentage1RM: 0.88, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Dumbbell Bench Press",      role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Chest Dip",                 role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Tricep Pushdown",           role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Skull Crushers",            role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Overhead Tricep Extension", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Lateral Raises",            role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 2
        )

        let volumeBenchDay = SessionDefinition(
            sessionName: "Volume Bench Day",
            primaryExercises: [
                .init(exerciseName: "Close Grip Bench Press", role: .variation, defaultSets: 4, defaultReps: 6, percentage1RM: 0.72, targetRPE: nil),
                .init(exerciseName: "Pause Bench Press",      role: .variation, defaultSets: 3, defaultReps: 5, percentage1RM: 0.75, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Incline Bench",       role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Floor Press",         role: .variation, defaultSets: 3, defaultReps: 6,  percentage1RM: 0.75, targetRPE: nil),
                .init(exerciseName: "Incline Dumbbell Press",role: .accessory,defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Cable Flyes",         role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Dumbbell Flyes",      role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Pec Deck Machine Fly",role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryCount: 1
        )

        let ohpDay = SessionDefinition(
            sessionName: "Overhead Press Day",
            primaryExercises: [
                .init(exerciseName: "Overhead Press", role: .primary, defaultSets: 4, defaultReps: 5, percentage1RM: 0.80, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Lateral Raises",    role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Front Raises",      role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Reverse Flyes",     role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Cable Lateral Raise",role: .accessory,defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Face Pulls",        role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Arnold Press",      role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Machine Shoulder Press", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryCount: 2
        )

        let backBalanceDay = SessionDefinition(
            sessionName: "Back & Structural Balance",
            primaryExercises: [
                .init(exerciseName: "Barbell Row", role: .primary, defaultSets: 4, defaultReps: 5, percentage1RM: 0.78, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Lat Pulldown",     role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Seated Cable Row", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Pull-ups",         role: .accessory, defaultSets: 3, defaultReps: 6,  percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Chin-ups",         role: .accessory, defaultSets: 3, defaultReps: 6,  percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Dumbbell Row",     role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Face Pulls",       role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Reverse Flyes",    role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 3
        )

        let volumeBenchBDay = SessionDefinition(
            sessionName: "Volume Bench B",
            primaryExercises: [
                .init(exerciseName: "Incline Bench", role: .variation, defaultSets: 4, defaultReps: 6, percentage1RM: 0.74, targetRPE: nil),
                .init(exerciseName: "Floor Press",   role: .variation, defaultSets: 3, defaultReps: 5, percentage1RM: 0.78, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Dumbbell Bench Press",      role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Pec Deck Machine Fly",      role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Cable Flyes",               role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Chest Dip",                 role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Overhead Tricep Extension", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Skull Crushers",            role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryCount: 2
        )

        let bench_legMaintenanceDay = SessionDefinition(
            sessionName: "Leg Maintenance",
            primaryExercises: [
                .init(exerciseName: "Back Squats",      role: .primary,   defaultSets: 3, defaultReps: 5, percentage1RM: 0.78, targetRPE: nil),
                .init(exerciseName: "Romanian Deadlift",role: .accessory, defaultSets: 3, defaultReps: 8, percentage1RM: nil,  targetRPE: 7),
            ],
            accessoryPool: [
                .init(exerciseName: "Leg Press",     role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Leg Curl",      role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Leg Extension", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Calf Raises",   role: .accessory, defaultSets: 4, defaultReps: 12, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Glute Bridge",  role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 2
        )

        return FocusTemplate(
            focus: .increaseMaxBench,
            displayName: "Increase Max Bench",
            minimumFrequency: 3,
            requiredLifts: ["Bench Press", "Overhead Press"],
            exercisesPerSession: 3...4,
            sessionDefinitions: [
                3: [heavyBenchDay, volumeBenchDay, ohpDay],
                4: [heavyBenchDay, volumeBenchDay, ohpDay, backBalanceDay],
                5: [heavyBenchDay, volumeBenchDay, ohpDay, backBalanceDay, volumeBenchBDay],
                6: [heavyBenchDay, volumeBenchDay, ohpDay, backBalanceDay, volumeBenchBDay, bench_legMaintenanceDay],
            ]
        )
    }
}

// MARK: - Increase Max Deadlift
// Inspired by Candito Deadlift Program and Travis Mash pulling methodology.

private extension FocusTemplateLibrary {
    static var deadliftTemplate: FocusTemplate {
        let heavyDeadliftDay = SessionDefinition(
            sessionName: "Heavy Deadlift Day",
            primaryExercises: [
                .init(exerciseName: "Deadlift", role: .primary, defaultSets: 4, defaultReps: 3, percentage1RM: 0.88, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Romanian Deadlift", role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil,  targetRPE: 7),
                .init(exerciseName: "Hip Thrust",        role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil,  targetRPE: 7),
                .init(exerciseName: "Cable Pull Through",role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil,  targetRPE: 7),
                .init(exerciseName: "Leg Curl",          role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil,  targetRPE: 7),
                .init(exerciseName: "Good Mornings",     role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil,  targetRPE: 6),
                .init(exerciseName: "Barbell Row",       role: .accessory, defaultSets: 3, defaultReps: 5,  percentage1RM: 0.75, targetRPE: nil),
            ],
            accessoryCount: 2
        )

        let deadliftVariationDay = SessionDefinition(
            sessionName: "Deadlift Variation Day",
            primaryExercises: [
                .init(exerciseName: "Deficit Deadlift", role: .variation, defaultSets: 4, defaultReps: 4, percentage1RM: 0.72, targetRPE: nil),
                .init(exerciseName: "Block Pull",       role: .variation, defaultSets: 3, defaultReps: 3, percentage1RM: 0.85, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Romanian Deadlift", role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil,  targetRPE: 7),
                .init(exerciseName: "Sumo Deadlift",     role: .variation, defaultSets: 3, defaultReps: 4,  percentage1RM: 0.72, targetRPE: nil),
                .init(exerciseName: "Hip Thrust",        role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil,  targetRPE: 7),
                .init(exerciseName: "Leg Curl",          role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil,  targetRPE: 7),
                .init(exerciseName: "Good Mornings",     role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil,  targetRPE: 6),
                .init(exerciseName: "Pendlay Row",       role: .accessory, defaultSets: 3, defaultReps: 6,  percentage1RM: 0.75, targetRPE: nil),
                .init(exerciseName: "Cable Pull Through",role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil,  targetRPE: 7),
            ],
            accessoryCount: 1
        )

        let squatPostChainDay = SessionDefinition(
            sessionName: "Squat & Posterior Chain",
            primaryExercises: [
                .init(exerciseName: "Back Squats", role: .primary, defaultSets: 4, defaultReps: 5, percentage1RM: 0.78, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Romanian Deadlift", role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Hip Thrust",        role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Leg Press",         role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Leg Curl",          role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Good Mornings",     role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Cable Pull Through",role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Glute Bridge",      role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 2
        )

        let backVolumeDay = SessionDefinition(
            sessionName: "Back Volume Day",
            primaryExercises: [
                .init(exerciseName: "Barbell Row",  role: .primary, defaultSets: 4, defaultReps: 6, percentage1RM: 0.72, targetRPE: nil),
                .init(exerciseName: "Pendlay Row",  role: .primary, defaultSets: 3, defaultReps: 5, percentage1RM: 0.78, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Lat Pulldown",      role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Seated Cable Row",  role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "T-Bar Row",         role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Dumbbell Row",      role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Chin-ups",          role: .accessory, defaultSets: 3, defaultReps: 6,  percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Straight Arm Pulldown", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Hanging Leg Raises",role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Ab Rollout",        role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryCount: 3
        )

        let sumoVariationDay = SessionDefinition(
            sessionName: "Sumo & Variation B",
            primaryExercises: [
                .init(exerciseName: "Sumo Deadlift", role: .variation, defaultSets: 4, defaultReps: 4, percentage1RM: 0.72, targetRPE: nil),
                .init(exerciseName: "Hip Thrust",    role: .accessory, defaultSets: 3, defaultReps: 8, percentage1RM: nil,  targetRPE: 7),
            ],
            accessoryPool: [
                .init(exerciseName: "Romanian Deadlift", role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Good Mornings",     role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Cable Pull Through",role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Leg Curl",          role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Glute Bridge",      role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 2
        )

        let dl_upperMaintenanceDay = SessionDefinition(
            sessionName: "Upper Body Maintenance",
            primaryExercises: [
                .init(exerciseName: "Bench Press",    role: .primary, defaultSets: 3, defaultReps: 5, percentage1RM: 0.75, targetRPE: nil),
                .init(exerciseName: "Overhead Press", role: .primary, defaultSets: 3, defaultReps: 5, percentage1RM: 0.75, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Incline Bench",   role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Lat Pulldown",    role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Face Pulls",      role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Barbell Curl",    role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Tricep Pushdown", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryCount: 2
        )

        return FocusTemplate(
            focus: .increaseMaxDeadlift,
            displayName: "Increase Max Deadlift",
            minimumFrequency: 3,
            requiredLifts: ["Deadlift", "Back Squats"],
            exercisesPerSession: 3...4,
            sessionDefinitions: [
                3: [heavyDeadliftDay, deadliftVariationDay, squatPostChainDay],
                4: [heavyDeadliftDay, deadliftVariationDay, squatPostChainDay, backVolumeDay],
                5: [heavyDeadliftDay, deadliftVariationDay, squatPostChainDay, backVolumeDay, sumoVariationDay],
                6: [heavyDeadliftDay, deadliftVariationDay, squatPostChainDay, backVolumeDay, sumoVariationDay, dl_upperMaintenanceDay],
            ]
        )
    }
}

// MARK: - General Fitness

private extension FocusTemplateLibrary {
    static var generalFitnessTemplate: FocusTemplate {
        // 2-day: Upper / Lower
        let gf_upperDay = SessionDefinition(
            sessionName: "Upper Body",
            primaryExercises: [
                .init(exerciseName: "Bench Press", role: .primary, defaultSets: 3, defaultReps: 5, percentage1RM: 0.75, targetRPE: nil),
                .init(exerciseName: "Barbell Row", role: .primary, defaultSets: 3, defaultReps: 5, percentage1RM: 0.75, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Overhead Press",   role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Lat Pulldown",     role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Incline Bench",    role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Dips",             role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Pull-ups",         role: .accessory, defaultSets: 3, defaultReps: 6,  percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Lateral Raises",   role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Tricep Pushdown",  role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Barbell Curl",     role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Face Pulls",       role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Seated Cable Row", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryCount: 4
        )

        let gf_lowerDay = SessionDefinition(
            sessionName: "Lower Body",
            primaryExercises: [
                .init(exerciseName: "Back Squats",      role: .primary,   defaultSets: 3, defaultReps: 5, percentage1RM: 0.75, targetRPE: nil),
                .init(exerciseName: "Romanian Deadlift",role: .accessory, defaultSets: 3, defaultReps: 8, percentage1RM: nil,  targetRPE: 7),
            ],
            accessoryPool: [
                .init(exerciseName: "Leg Press",             role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Leg Curl",              role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Leg Extension",         role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Calf Raises",           role: .accessory, defaultSets: 4, defaultReps: 12, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Hip Thrust",            role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Bulgarian Split Squat", role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Glute Bridge",          role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Walking Lunges",        role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Good Mornings",         role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 4
        )

        // 3-day: Push / Pull / Legs
        let gf_pushDay = SessionDefinition(
            sessionName: "Push",
            primaryExercises: [
                .init(exerciseName: "Bench Press",    role: .primary, defaultSets: 3, defaultReps: 5, percentage1RM: 0.75, targetRPE: nil),
                .init(exerciseName: "Overhead Press", role: .primary, defaultSets: 3, defaultReps: 8, percentage1RM: 0.72, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Incline Bench",   role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Chest Dip",       role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Dumbbell Bench Press", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Lateral Raises",  role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Tricep Pushdown", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Skull Crushers",  role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Cable Flyes",     role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryCount: 3
        )

        let gf_pullDay = SessionDefinition(
            sessionName: "Pull",
            primaryExercises: [
                .init(exerciseName: "Deadlift",    role: .primary, defaultSets: 3, defaultReps: 5, percentage1RM: 0.80, targetRPE: nil),
                .init(exerciseName: "Barbell Row", role: .primary, defaultSets: 3, defaultReps: 6, percentage1RM: 0.72, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Lat Pulldown",     role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Pull-ups",         role: .accessory, defaultSets: 3, defaultReps: 6,  percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Seated Cable Row", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Chin-ups",         role: .accessory, defaultSets: 3, defaultReps: 6,  percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Dumbbell Row",     role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Barbell Curl",     role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Hammer Curl",      role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Face Pulls",       role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 3
        )

        let gf_legsDay = SessionDefinition(
            sessionName: "Legs",
            primaryExercises: [
                .init(exerciseName: "Back Squats",      role: .primary,   defaultSets: 3, defaultReps: 5, percentage1RM: 0.78, targetRPE: nil),
                .init(exerciseName: "Romanian Deadlift",role: .accessory, defaultSets: 3, defaultReps: 8, percentage1RM: nil,  targetRPE: 7),
            ],
            accessoryPool: [
                .init(exerciseName: "Leg Press",             role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Leg Curl",              role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Leg Extension",         role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Calf Raises",           role: .accessory, defaultSets: 4, defaultReps: 12, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Bulgarian Split Squat", role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Hip Thrust",            role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Glute Bridge",          role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Walking Lunges",        role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryCount: 3
        )

        // 4-day: Upper A / Lower A / Upper B / Lower B
        let gf_upperA = SessionDefinition(
            sessionName: "Upper A",
            primaryExercises: [
                .init(exerciseName: "Bench Press",    role: .primary, defaultSets: 4, defaultReps: 5, percentage1RM: 0.78, targetRPE: nil),
                .init(exerciseName: "Overhead Press", role: .primary, defaultSets: 3, defaultReps: 6, percentage1RM: 0.75, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Incline Bench",   role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Dumbbell Bench Press", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Lateral Raises",  role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Tricep Pushdown", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Skull Crushers",  role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryCount: 3
        )

        let gf_lowerA = SessionDefinition(
            sessionName: "Lower A",
            primaryExercises: [
                .init(exerciseName: "Back Squats", role: .primary, defaultSets: 4, defaultReps: 5, percentage1RM: 0.78, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Leg Press",     role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Leg Curl",      role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Leg Extension", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Calf Raises",   role: .accessory, defaultSets: 4, defaultReps: 12, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Hip Thrust",    role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Good Mornings", role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 3
        )

        let gf_upperB = SessionDefinition(
            sessionName: "Upper B",
            primaryExercises: [
                .init(exerciseName: "Overhead Press", role: .primary, defaultSets: 4, defaultReps: 5, percentage1RM: 0.78, targetRPE: nil),
                .init(exerciseName: "Barbell Row",    role: .primary, defaultSets: 4, defaultReps: 5, percentage1RM: 0.75, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Pull-ups",         role: .accessory, defaultSets: 3, defaultReps: 6,  percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Lat Pulldown",     role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Incline Bench",    role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Seated Cable Row", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Lateral Raises",   role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Face Pulls",       role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Barbell Curl",     role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Tricep Pushdown",  role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Rowing Machine",   role: .cardio,    defaultSets: 1, defaultReps: 20, percentage1RM: nil, targetRPE: nil),
            ],
            accessoryCount: 3
        )

        let gf_lowerB = SessionDefinition(
            sessionName: "Lower B",
            primaryExercises: [
                .init(exerciseName: "Deadlift",         role: .primary,   defaultSets: 3, defaultReps: 5, percentage1RM: 0.82, targetRPE: nil),
                .init(exerciseName: "Romanian Deadlift",role: .accessory, defaultSets: 3, defaultReps: 8, percentage1RM: nil,  targetRPE: 7),
            ],
            accessoryPool: [
                .init(exerciseName: "Bulgarian Split Squat", role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Leg Curl",              role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Hip Thrust",            role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Glute Bridge",          role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Walking Lunges",        role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Calf Raises",           role: .accessory, defaultSets: 4, defaultReps: 12, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 3
        )

        // 5-day: PPL + Upper + Lower
        let gf_push5 = SessionDefinition(
            sessionName: "Push",
            primaryExercises: [
                .init(exerciseName: "Bench Press", role: .primary, defaultSets: 4, defaultReps: 5, percentage1RM: 0.78, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Incline Bench",         role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Dumbbell Bench Press",  role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Tricep Pushdown",       role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Skull Crushers",        role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Lateral Raises",        role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Cable Lateral Raise",   role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 3
        )

        let gf_pull5 = SessionDefinition(
            sessionName: "Pull",
            primaryExercises: [
                .init(exerciseName: "Barbell Row",  role: .primary,   defaultSets: 4, defaultReps: 5, percentage1RM: 0.75, targetRPE: nil),
                .init(exerciseName: "Lat Pulldown", role: .accessory, defaultSets: 3, defaultReps: 8, percentage1RM: nil,  targetRPE: 7),
            ],
            accessoryPool: [
                .init(exerciseName: "Pull-ups",         role: .accessory, defaultSets: 3, defaultReps: 6,  percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Chin-ups",         role: .accessory, defaultSets: 3, defaultReps: 6,  percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Seated Cable Row", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Barbell Curl",     role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Hammer Curl",      role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Face Pulls",       role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 3
        )

        let gf_legs5 = SessionDefinition(
            sessionName: "Legs",
            primaryExercises: [
                .init(exerciseName: "Back Squats", role: .primary, defaultSets: 4, defaultReps: 5, percentage1RM: 0.78, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Leg Press",     role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Leg Curl",      role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Leg Extension", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Calf Raises",   role: .accessory, defaultSets: 4, defaultReps: 12, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Hip Thrust",    role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
            ],
            accessoryCount: 3
        )

        let gf_upper5 = SessionDefinition(
            sessionName: "Upper Strength",
            primaryExercises: [
                .init(exerciseName: "Overhead Press", role: .primary, defaultSets: 3, defaultReps: 6, percentage1RM: 0.75, targetRPE: nil),
                .init(exerciseName: "Deadlift",       role: .primary, defaultSets: 3, defaultReps: 4, percentage1RM: 0.82, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Lat Pulldown",   role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Incline Bench",  role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Face Pulls",     role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Reverse Flyes",  role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Tricep Pushdown",role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Exercise Bike",  role: .cardio,    defaultSets: 1, defaultReps: 20, percentage1RM: nil, targetRPE: nil),
            ],
            accessoryCount: 2
        )

        let gf_lower5 = SessionDefinition(
            sessionName: "Lower Accessory",
            primaryExercises: [
                .init(exerciseName: "Romanian Deadlift",     role: .accessory, defaultSets: 3, defaultReps: 8, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Bulgarian Split Squat", role: .accessory, defaultSets: 3, defaultReps: 8, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryPool: [
                .init(exerciseName: "Leg Curl",      role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Leg Extension", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Walking Lunges",role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Hip Thrust",    role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Glute Bridge",  role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Calf Raises",   role: .accessory, defaultSets: 4, defaultReps: 12, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 3
        )

        // 6-day: PPL x2 (A/B variants)
        let gf_pushA6 = SessionDefinition(
            sessionName: "Push A",
            primaryExercises: [
                .init(exerciseName: "Bench Press", role: .primary, defaultSets: 4, defaultReps: 5, percentage1RM: 0.78, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Incline Bench",         role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Dumbbell Bench Press",  role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Chest Dip",             role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Tricep Pushdown",       role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Overhead Tricep Extension", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryCount: 3
        )

        let gf_pullA6 = SessionDefinition(
            sessionName: "Pull A",
            primaryExercises: [
                .init(exerciseName: "Deadlift",    role: .primary, defaultSets: 3, defaultReps: 4, percentage1RM: 0.85, targetRPE: nil),
                .init(exerciseName: "Barbell Row", role: .primary, defaultSets: 3, defaultReps: 6, percentage1RM: 0.72, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Lat Pulldown",     role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Seated Cable Row", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Chin-ups",         role: .accessory, defaultSets: 3, defaultReps: 6,  percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Barbell Curl",     role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Hammer Curl",      role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryCount: 3
        )

        let gf_legsA6 = SessionDefinition(
            sessionName: "Legs A",
            primaryExercises: [
                .init(exerciseName: "Back Squats", role: .primary, defaultSets: 4, defaultReps: 5, percentage1RM: 0.78, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Leg Press",     role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Leg Curl",      role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Leg Extension", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Calf Raises",   role: .accessory, defaultSets: 4, defaultReps: 12, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Hip Thrust",    role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
            ],
            accessoryCount: 3
        )

        let gf_pushB6 = SessionDefinition(
            sessionName: "Push B",
            primaryExercises: [
                .init(exerciseName: "Overhead Press", role: .primary,   defaultSets: 4, defaultReps: 5, percentage1RM: 0.78, targetRPE: nil),
                .init(exerciseName: "Incline Bench",  role: .variation, defaultSets: 3, defaultReps: 8, percentage1RM: 0.72, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Cable Flyes",       role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Dumbbell Flyes",    role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Lateral Raises",    role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Skull Crushers",    role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Cable Tricep Kickback", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryCount: 3
        )

        let gf_pullB6 = SessionDefinition(
            sessionName: "Pull B",
            primaryExercises: [
                .init(exerciseName: "Pull-ups",     role: .primary,   defaultSets: 4, defaultReps: 5, percentage1RM: nil,  targetRPE: 8),
                .init(exerciseName: "Pendlay Row",  role: .primary,   defaultSets: 3, defaultReps: 5, percentage1RM: 0.75, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "T-Bar Row",          role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Dumbbell Row",       role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "EZ Bar Curl",        role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Incline Dumbbell Curl", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Face Pulls",         role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Reverse Flyes",      role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Rowing Machine",     role: .cardio,    defaultSets: 1, defaultReps: 20, percentage1RM: nil, targetRPE: nil),
            ],
            accessoryCount: 3
        )

        let gf_legsB6 = SessionDefinition(
            sessionName: "Legs B",
            primaryExercises: [
                .init(exerciseName: "Romanian Deadlift", role: .accessory, defaultSets: 3, defaultReps: 8, percentage1RM: nil,  targetRPE: 7),
                .init(exerciseName: "Hack Squat",        role: .variation, defaultSets: 3, defaultReps: 8, percentage1RM: 0.75, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Bulgarian Split Squat", role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Walking Lunges",        role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Glute Bridge",          role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Leg Curl",              role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Seated Calf Raise",     role: .accessory, defaultSets: 4, defaultReps: 12, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Cable Pull Through",    role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryCount: 3
        )

        return FocusTemplate(
            focus: .generalFitness,
            displayName: "General Fitness",
            minimumFrequency: 2,
            requiredLifts: ["Back Squats", "Bench Press", "Deadlift"],
            exercisesPerSession: 5...6,
            sessionDefinitions: [
                2: [gf_upperDay, gf_lowerDay],
                3: [gf_pushDay, gf_pullDay, gf_legsDay],
                4: [gf_upperA, gf_lowerA, gf_upperB, gf_lowerB],
                5: [gf_push5, gf_pull5, gf_legs5, gf_upper5, gf_lower5],
                6: [gf_pushA6, gf_pullA6, gf_legsA6, gf_pushB6, gf_pullB6, gf_legsB6],
            ]
        )
    }
}

// MARK: - Full Body
// Inspired by full-body frequency research and Jeff Nippard-style efficient split design.

private extension FocusTemplateLibrary {
    static var fullBodyTemplate: FocusTemplate {
        let fb_A = SessionDefinition(
            sessionName: "Full Body A (Squat + Bench)",
            primaryExercises: [
                .init(exerciseName: "Back Squats", role: .primary, defaultSets: 4, defaultReps: 5, percentage1RM: 0.78, targetRPE: nil),
                .init(exerciseName: "Bench Press", role: .primary, defaultSets: 4, defaultReps: 5, percentage1RM: 0.76, targetRPE: nil),
                .init(exerciseName: "Seated Cable Row", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryPool: [
                .init(exerciseName: "Romanian Deadlift", role: .accessory, defaultSets: 3, defaultReps: 8, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Pull-ups", role: .accessory, defaultSets: 3, defaultReps: 6, percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Leg Curl", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Lateral Raises", role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Ab Rollout", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Calf Raises", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 2
        )

        let fb_B = SessionDefinition(
            sessionName: "Full Body B (Hinge + Vertical Push)",
            primaryExercises: [
                .init(exerciseName: "Deadlift", role: .primary, defaultSets: 3, defaultReps: 4, percentage1RM: 0.83, targetRPE: nil),
                .init(exerciseName: "Overhead Press", role: .accessory, defaultSets: 3, defaultReps: 6, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Lat Pulldown", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryPool: [
                .init(exerciseName: "Goblet Squat", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Incline Dumbbell Press", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Seated Cable Row", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Hip Thrust", role: .accessory, defaultSets: 3, defaultReps: 8, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Tricep Pushdown", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Dead Bug", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 2
        )

        let fb_C = SessionDefinition(
            sessionName: "Full Body C (Variation Strength)",
            primaryExercises: [
                .init(exerciseName: "Front Squat", role: .variation, defaultSets: 3, defaultReps: 5, percentage1RM: 0.72, targetRPE: nil),
                .init(exerciseName: "Incline Bench", role: .variation, defaultSets: 3, defaultReps: 6, percentage1RM: 0.74, targetRPE: nil),
                .init(exerciseName: "Chin-ups", role: .accessory, defaultSets: 3, defaultReps: 6, percentage1RM: nil, targetRPE: 8),
            ],
            accessoryPool: [
                .init(exerciseName: "Romanian Deadlift", role: .accessory, defaultSets: 3, defaultReps: 8, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Leg Extension", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Cable Lateral Raise", role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Hammer Curl", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Pallof Press", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Glute Bridge", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 2
        )

        let fb_D = SessionDefinition(
            sessionName: "Full Body D (Bench + Posterior Chain)",
            primaryExercises: [
                .init(exerciseName: "Pause Bench Press", role: .variation, defaultSets: 4, defaultReps: 4, percentage1RM: 0.80, targetRPE: nil),
                .init(exerciseName: "Romanian Deadlift", role: .accessory, defaultSets: 3, defaultReps: 8, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Pull-ups", role: .accessory, defaultSets: 3, defaultReps: 6, percentage1RM: nil, targetRPE: 8),
            ],
            accessoryPool: [
                .init(exerciseName: "Leg Press", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Dumbbell Bench Press", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Face Pulls", role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Leg Curl", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Cable Tricep Kickback", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Calf Raises", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 2
        )

        let fb_E = SessionDefinition(
            sessionName: "Full Body E (Recovery Bias)",
            primaryExercises: [
                .init(exerciseName: "Goblet Squat", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Floor Press", role: .variation, defaultSets: 3, defaultReps: 8, percentage1RM: 0.72, targetRPE: nil),
                .init(exerciseName: "Seated Cable Row", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryPool: [
                .init(exerciseName: "Walking Lunges", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Lat Pulldown", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Arnold Press", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Glute Bridge", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Overhead Tricep Extension", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Cable Curl", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Exercise Bike", role: .cardio, defaultSets: 1, defaultReps: 20, percentage1RM: nil, targetRPE: nil),
            ],
            accessoryCount: 2
        )

        let fb_F = SessionDefinition(
            sessionName: "Full Body F (Frequency Support)",
            primaryExercises: [
                .init(exerciseName: "Pause Squat", role: .variation, defaultSets: 3, defaultReps: 4, percentage1RM: 0.78, targetRPE: nil),
                .init(exerciseName: "Close Grip Bench Press", role: .variation, defaultSets: 3, defaultReps: 6, percentage1RM: 0.76, targetRPE: nil),
                .init(exerciseName: "Lat Pulldown", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryPool: [
                .init(exerciseName: "Hip Thrust", role: .accessory, defaultSets: 3, defaultReps: 8, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Dumbbell Row", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Lateral Raises", role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Leg Curl", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Concentration Curl", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Ab Rollout", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Rowing Machine", role: .cardio, defaultSets: 1, defaultReps: 20, percentage1RM: nil, targetRPE: nil),
            ],
            accessoryCount: 2
        )

        return FocusTemplate(
            focus: .fullBody,
            displayName: "Full Body",
            minimumFrequency: 2,
            requiredLifts: ["Back Squats", "Bench Press", "Deadlift"],
            exercisesPerSession: 5...5,
            sessionDefinitions: [
                2: [fb_A, fb_B],
                3: [fb_A, fb_B, fb_C],
                4: [fb_A, fb_B, fb_C, fb_D],
                5: [fb_A, fb_B, fb_C, fb_D, fb_E],
                6: [fb_A, fb_B, fb_C, fb_D, fb_E, fb_F],
            ]
        )
    }
}

// MARK: - Push Pull

private extension FocusTemplateLibrary {
    static var pushPullTemplate: FocusTemplate {
        // 3-day: Push / Pull / Legs
        let pp_push3 = SessionDefinition(
            sessionName: "Push",
            primaryExercises: [
                .init(exerciseName: "Bench Press",    role: .primary, defaultSets: 4, defaultReps: 5, percentage1RM: 0.78, targetRPE: nil),
                .init(exerciseName: "Overhead Press", role: .primary, defaultSets: 3, defaultReps: 5, percentage1RM: 0.75, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Incline Bench",         role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Dumbbell Bench Press",  role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Chest Dip",             role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Tricep Pushdown",       role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Skull Crushers",        role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Overhead Tricep Extension", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Lateral Raises",        role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Cable Lateral Raise",   role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 3
        )

        let pp_pull3 = SessionDefinition(
            sessionName: "Pull",
            primaryExercises: [
                .init(exerciseName: "Deadlift",    role: .primary, defaultSets: 3, defaultReps: 4, percentage1RM: 0.83, targetRPE: nil),
                .init(exerciseName: "Barbell Row", role: .primary, defaultSets: 3, defaultReps: 5, percentage1RM: 0.75, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Lat Pulldown",     role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Pull-ups",         role: .accessory, defaultSets: 3, defaultReps: 6,  percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Seated Cable Row", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Chin-ups",         role: .accessory, defaultSets: 3, defaultReps: 6,  percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Dumbbell Row",     role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Barbell Curl",     role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Hammer Curl",      role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "EZ Bar Curl",      role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Face Pulls",       role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 3
        )

        let pp_legs3 = SessionDefinition(
            sessionName: "Legs",
            primaryExercises: [
                .init(exerciseName: "Back Squats",      role: .primary,   defaultSets: 4, defaultReps: 5, percentage1RM: 0.78, targetRPE: nil),
                .init(exerciseName: "Romanian Deadlift",role: .accessory, defaultSets: 3, defaultReps: 8, percentage1RM: nil,  targetRPE: 7),
            ],
            accessoryPool: [
                .init(exerciseName: "Leg Press",             role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Leg Curl",              role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Leg Extension",         role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Calf Raises",           role: .accessory, defaultSets: 4, defaultReps: 12, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Bulgarian Split Squat", role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Hip Thrust",            role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Walking Lunges",        role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Glute Bridge",          role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 3
        )

        // 4-day: Upper A / Lower A / Upper B / Lower B
        let pp_upperA4 = SessionDefinition(
            sessionName: "Upper A (Push Focus)",
            primaryExercises: [
                .init(exerciseName: "Bench Press", role: .primary, defaultSets: 4, defaultReps: 5, percentage1RM: 0.78, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Overhead Press",    role: .accessory, defaultSets: 3, defaultReps: 6,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Incline Bench",     role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Dumbbell Bench Press", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Tricep Pushdown",   role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Skull Crushers",    role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Lateral Raises",    role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Seated Cable Row",  role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryCount: 4
        )

        let pp_lowerA4 = SessionDefinition(
            sessionName: "Lower A (Squat Focus)",
            primaryExercises: [
                .init(exerciseName: "Back Squats", role: .primary, defaultSets: 4, defaultReps: 5, percentage1RM: 0.78, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Leg Press",             role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Leg Curl",              role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Leg Extension",         role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Hip Thrust",            role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Romanian Deadlift",     role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Calf Raises",           role: .accessory, defaultSets: 4, defaultReps: 12, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Walking Lunges",        role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryCount: 3
        )

        let pp_upperB4 = SessionDefinition(
            sessionName: "Upper B (Pull Focus)",
            primaryExercises: [
                .init(exerciseName: "Barbell Row",    role: .primary, defaultSets: 4, defaultReps: 5, percentage1RM: 0.75, targetRPE: nil),
                .init(exerciseName: "Overhead Press", role: .primary, defaultSets: 3, defaultReps: 5, percentage1RM: 0.78, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Lat Pulldown",     role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Pull-ups",         role: .accessory, defaultSets: 3, defaultReps: 6,  percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Chin-ups",         role: .accessory, defaultSets: 3, defaultReps: 6,  percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Seated Cable Row", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Barbell Curl",     role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Hammer Curl",      role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Face Pulls",       role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Reverse Flyes",    role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 4
        )

        let pp_lowerB4 = SessionDefinition(
            sessionName: "Lower B (Deadlift Focus)",
            primaryExercises: [
                .init(exerciseName: "Deadlift", role: .primary, defaultSets: 3, defaultReps: 4, percentage1RM: 0.83, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Romanian Deadlift", role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Hip Thrust",        role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Cable Pull Through",role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Leg Curl",          role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Good Mornings",     role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Glute Bridge",      role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Bulgarian Split Squat", role: .accessory, defaultSets: 3, defaultReps: 8, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryCount: 4
        )

        // 5-day: PPL A/B (Push/Pull/Legs/Push B/Pull B)
        let pp_pushA5 = SessionDefinition(
            sessionName: "Push A",
            primaryExercises: [
                .init(exerciseName: "Bench Press",    role: .primary, defaultSets: 4, defaultReps: 5, percentage1RM: 0.78, targetRPE: nil),
                .init(exerciseName: "Overhead Press", role: .primary, defaultSets: 3, defaultReps: 5, percentage1RM: 0.75, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Incline Bench",   role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Chest Dip",       role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Tricep Pushdown", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Skull Crushers",  role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Lateral Raises",  role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 2
        )

        let pp_pullA5 = SessionDefinition(
            sessionName: "Pull A",
            primaryExercises: [
                .init(exerciseName: "Deadlift",    role: .primary, defaultSets: 3, defaultReps: 4, percentage1RM: 0.83, targetRPE: nil),
                .init(exerciseName: "Barbell Row", role: .primary, defaultSets: 3, defaultReps: 6, percentage1RM: 0.72, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Lat Pulldown",     role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Chin-ups",         role: .accessory, defaultSets: 3, defaultReps: 6,  percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Seated Cable Row", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Barbell Curl",     role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "EZ Bar Curl",      role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Face Pulls",       role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 2
        )

        let pp_legs5 = SessionDefinition(
            sessionName: "Legs",
            primaryExercises: [
                .init(exerciseName: "Back Squats", role: .primary, defaultSets: 4, defaultReps: 5, percentage1RM: 0.78, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Leg Press",     role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Leg Curl",      role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Leg Extension", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Calf Raises",   role: .accessory, defaultSets: 4, defaultReps: 12, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Hip Thrust",    role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
            ],
            accessoryCount: 3
        )

        let pp_pushB5 = SessionDefinition(
            sessionName: "Push B",
            primaryExercises: [
                .init(exerciseName: "Overhead Press", role: .primary,   defaultSets: 4, defaultReps: 5, percentage1RM: 0.78, targetRPE: nil),
                .init(exerciseName: "Incline Bench",  role: .variation, defaultSets: 3, defaultReps: 8, percentage1RM: 0.72, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Close Grip Bench Press",    role: .variation, defaultSets: 3, defaultReps: 6,  percentage1RM: 0.72, targetRPE: nil),
                .init(exerciseName: "Dumbbell Bench Press",      role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil,  targetRPE: 7),
                .init(exerciseName: "Overhead Tricep Extension", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil,  targetRPE: 7),
                .init(exerciseName: "Cable Tricep Kickback",     role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil,  targetRPE: 7),
                .init(exerciseName: "Cable Lateral Raise",       role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil,  targetRPE: 6),
                .init(exerciseName: "Arnold Press",              role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil,  targetRPE: 7),
            ],
            accessoryCount: 2
        )

        let pp_pullB5 = SessionDefinition(
            sessionName: "Pull B",
            primaryExercises: [
                .init(exerciseName: "Pull-ups",    role: .primary,   defaultSets: 4, defaultReps: 5, percentage1RM: nil,  targetRPE: 8),
                .init(exerciseName: "Pendlay Row", role: .primary,   defaultSets: 3, defaultReps: 5, percentage1RM: 0.75, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "T-Bar Row",          role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Dumbbell Row",       role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Hammer Curl",        role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Incline Dumbbell Curl", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Concentration Curl", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Straight Arm Pulldown", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Reverse Flyes",      role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 2
        )

        // 6-day: PPL A/B — same Push A/B, Pull A/B, Legs A + Legs B
        let pp_legsB6 = SessionDefinition(
            sessionName: "Legs B",
            primaryExercises: [
                .init(exerciseName: "Romanian Deadlift", role: .accessory, defaultSets: 3, defaultReps: 8, percentage1RM: nil,  targetRPE: 7),
                .init(exerciseName: "Hack Squat",        role: .variation, defaultSets: 3, defaultReps: 8, percentage1RM: 0.75, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Bulgarian Split Squat", role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Walking Lunges",        role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Glute Bridge",          role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Leg Curl",              role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Seated Calf Raise",     role: .accessory, defaultSets: 4, defaultReps: 12, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Cable Pull Through",    role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryCount: 3
        )

        return FocusTemplate(
            focus: .pushPull,
            displayName: "Push / Pull",
            minimumFrequency: 3,
            requiredLifts: ["Back Squats", "Bench Press", "Deadlift", "Overhead Press"],
            exercisesPerSession: 5...6,
            sessionDefinitions: [
                3: [pp_push3, pp_pull3, pp_legs3],
                4: [pp_upperA4, pp_lowerA4, pp_upperB4, pp_lowerB4],
                5: [pp_pushA5, pp_pullA5, pp_legs5, pp_pushB5, pp_pullB5],
                6: [pp_pushA5, pp_pullA5, pp_legs5, pp_pushB5, pp_pullB5, pp_legsB6],
            ]
        )
    }
}

// MARK: - 5×5
// Inspired by StrongLifts and Madcow 5×5 methodologies.

private extension FocusTemplateLibrary {
    static var fiveByFiveTemplate: FocusTemplate {
        let workoutA = SessionDefinition(
            sessionName: "Workout A",
            primaryExercises: [
                .init(exerciseName: "Back Squats", role: .primary, defaultSets: 5, defaultReps: 5, percentage1RM: 0.82, targetRPE: nil),
                .init(exerciseName: "Bench Press", role: .primary, defaultSets: 5, defaultReps: 5, percentage1RM: 0.80, targetRPE: nil),
                .init(exerciseName: "Barbell Row", role: .primary, defaultSets: 5, defaultReps: 5, percentage1RM: 0.78, targetRPE: nil),
            ],
            accessoryPool: [],
            accessoryCount: 0
        )

        let workoutB = SessionDefinition(
            sessionName: "Workout B",
            primaryExercises: [
                .init(exerciseName: "Back Squats",    role: .primary, defaultSets: 5, defaultReps: 5, percentage1RM: 0.82, targetRPE: nil),
                .init(exerciseName: "Overhead Press", role: .primary, defaultSets: 5, defaultReps: 5, percentage1RM: 0.80, targetRPE: nil),
                .init(exerciseName: "Deadlift",       role: .primary, defaultSets: 1, defaultReps: 5, percentage1RM: 0.87, targetRPE: nil),
            ],
            accessoryPool: [],
            accessoryCount: 0
        )

        // C workout added at 4+ frequency
        let workoutC = SessionDefinition(
            sessionName: "Workout C",
            primaryExercises: [
                .init(exerciseName: "Front Squat",   role: .variation, defaultSets: 5, defaultReps: 5, percentage1RM: 0.72, targetRPE: nil),
                .init(exerciseName: "Incline Bench", role: .variation, defaultSets: 5, defaultReps: 5, percentage1RM: 0.77, targetRPE: nil),
                .init(exerciseName: "Chin-ups",      role: .accessory, defaultSets: 5, defaultReps: 5, percentage1RM: nil,  targetRPE: 8),
            ],
            accessoryPool: [],
            accessoryCount: 0
        )

        return FocusTemplate(
            focus: .fiveByFive,
            displayName: "5×5 Strength",
            minimumFrequency: 3,
            requiredLifts: ["Back Squats", "Bench Press", "Deadlift", "Overhead Press", "Barbell Row"],
            exercisesPerSession: 3...3,
            sessionDefinitions: [
                3: [workoutA, workoutB, workoutA],
                4: [workoutA, workoutB, workoutC, workoutA],
                5: [workoutA, workoutB, workoutC, workoutA, workoutB],
                6: [workoutA, workoutB, workoutC, workoutA, workoutB, workoutC],
            ]
        )
    }
}

// MARK: - Powerlifting
// Inspired by SBD-specific strength principles, higher bench frequency, and fatigue-aware deadlift exposure.

private extension FocusTemplateLibrary {
    static var powerliftingTemplate: FocusTemplate {
        let pl_squatBench = SessionDefinition(
            sessionName: "Competition Squat + Bench",
            primaryExercises: [
                .init(exerciseName: "Back Squats", role: .primary, defaultSets: 4, defaultReps: 3, percentage1RM: 0.88, targetRPE: nil),
                .init(exerciseName: "Bench Press", role: .primary, defaultSets: 4, defaultReps: 4, percentage1RM: 0.82, targetRPE: nil),
                .init(exerciseName: "Barbell Row", role: .accessory, defaultSets: 3, defaultReps: 8, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryPool: [
                .init(exerciseName: "Pause Squat", role: .variation, defaultSets: 3, defaultReps: 4, percentage1RM: 0.80, targetRPE: nil),
                .init(exerciseName: "Leg Press", role: .accessory, defaultSets: 3, defaultReps: 8, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Lat Pulldown", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Tricep Pushdown", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Ab Rollout", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Face Pulls", role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 2
        )

        let pl_benchDeadlift = SessionDefinition(
            sessionName: "Competition Bench + Deadlift",
            primaryExercises: [
                .init(exerciseName: "Bench Press", role: .primary, defaultSets: 5, defaultReps: 3, percentage1RM: 0.88, targetRPE: nil),
                .init(exerciseName: "Deadlift", role: .primary, defaultSets: 4, defaultReps: 3, percentage1RM: 0.88, targetRPE: nil),
                .init(exerciseName: "Seated Cable Row", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryPool: [
                .init(exerciseName: "Pause Bench Press", role: .variation, defaultSets: 3, defaultReps: 4, percentage1RM: 0.80, targetRPE: nil),
                .init(exerciseName: "Leg Curl", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Pull-ups", role: .accessory, defaultSets: 3, defaultReps: 6, percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Skull Crushers", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Pallof Press", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Hip Thrust", role: .accessory, defaultSets: 3, defaultReps: 8, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryCount: 2
        )

        let pl_secondarySBD = SessionDefinition(
            sessionName: "Secondary Squat + Bench Volume",
            primaryExercises: [
                .init(exerciseName: "Pause Squat", role: .variation, defaultSets: 3, defaultReps: 4, percentage1RM: 0.82, targetRPE: nil),
                .init(exerciseName: "Close Grip Bench Press", role: .variation, defaultSets: 4, defaultReps: 6, percentage1RM: 0.78, targetRPE: nil),
                .init(exerciseName: "Chin-ups", role: .accessory, defaultSets: 3, defaultReps: 6, percentage1RM: nil, targetRPE: 8),
            ],
            accessoryPool: [
                .init(exerciseName: "Front Squat", role: .variation, defaultSets: 3, defaultReps: 5, percentage1RM: 0.75, targetRPE: nil),
                .init(exerciseName: "Incline Bench", role: .variation, defaultSets: 3, defaultReps: 8, percentage1RM: 0.72, targetRPE: nil),
                .init(exerciseName: "Leg Press", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Barbell Curl", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Face Pulls", role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Dead Bug", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 2
        )

        let pl_benchIntensity = SessionDefinition(
            sessionName: "Bench Intensity + Pull Support",
            primaryExercises: [
                .init(exerciseName: "Bench Press", role: .primary, defaultSets: 4, defaultReps: 4, percentage1RM: 0.84, targetRPE: nil),
                .init(exerciseName: "Block Pull", role: .variation, defaultSets: 3, defaultReps: 4, percentage1RM: 0.86, targetRPE: nil),
                .init(exerciseName: "Lat Pulldown", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryPool: [
                .init(exerciseName: "Overhead Tricep Extension", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "T-Bar Row", role: .accessory, defaultSets: 3, defaultReps: 8, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Leg Curl", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Face Pulls", role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Ab Rollout", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Cable Lateral Raise", role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 2
        )

        let pl_squatDeadliftSupport = SessionDefinition(
            sessionName: "Squat Intensity + Deadlift Support",
            primaryExercises: [
                .init(exerciseName: "Back Squats", role: .primary, defaultSets: 3, defaultReps: 2, percentage1RM: 0.90, targetRPE: nil),
                .init(exerciseName: "Deficit Deadlift", role: .variation, defaultSets: 3, defaultReps: 4, percentage1RM: 0.82, targetRPE: nil),
                .init(exerciseName: "Pull-ups", role: .accessory, defaultSets: 3, defaultReps: 6, percentage1RM: nil, targetRPE: 8),
            ],
            accessoryPool: [
                .init(exerciseName: "Romanian Deadlift", role: .accessory, defaultSets: 3, defaultReps: 6, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Good Mornings", role: .accessory, defaultSets: 3, defaultReps: 8, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Tricep Pushdown", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Seated Cable Row", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Pallof Press", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Calf Raises", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 2
        )

        let pl_techniqueGPP = SessionDefinition(
            sessionName: "Technique + GPP",
            primaryExercises: [
                .init(exerciseName: "Front Squat", role: .variation, defaultSets: 3, defaultReps: 5, percentage1RM: 0.74, targetRPE: nil),
                .init(exerciseName: "Pause Bench Press", role: .variation, defaultSets: 3, defaultReps: 5, percentage1RM: 0.80, targetRPE: nil),
                .init(exerciseName: "Seated Cable Row", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryPool: [
                .init(exerciseName: "Hip Thrust", role: .accessory, defaultSets: 3, defaultReps: 8, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Leg Curl", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Face Pulls", role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "EZ Bar Curl", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Overhead Tricep Extension", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Dead Bug", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 2
        )

        return FocusTemplate(
            focus: .powerlifting,
            displayName: "Powerlifting",
            minimumFrequency: 3,
            requiredLifts: ["Back Squats", "Bench Press", "Deadlift"],
            exercisesPerSession: 4...5,
            sessionDefinitions: [
                3: [pl_squatBench, pl_benchDeadlift, pl_secondarySBD],
                4: [pl_squatBench, pl_benchDeadlift, pl_secondarySBD, pl_benchIntensity],
                5: [pl_squatBench, pl_benchDeadlift, pl_secondarySBD, pl_benchIntensity, pl_squatDeadliftSupport],
                6: [pl_squatBench, pl_benchDeadlift, pl_secondarySBD, pl_benchIntensity, pl_squatDeadliftSupport, pl_techniqueGPP],
            ]
        )
    }
}

// MARK: - Powerbuilding
// Inspired by Jeff Nippard Powerbuilding programs and PHUL methodology.

private extension FocusTemplateLibrary {
    static var powerbuildingTemplate: FocusTemplate {
        // Heavy compound opener → hypertrophy accessories
        let pb_squatDay = SessionDefinition(
            sessionName: "Squat Power Day",
            primaryExercises: [
                .init(exerciseName: "Back Squats", role: .primary,   defaultSets: 4, defaultReps: 3, percentage1RM: 0.88, targetRPE: nil),
                .init(exerciseName: "Pause Squat", role: .variation, defaultSets: 3, defaultReps: 5, percentage1RM: 0.75, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Leg Press",             role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Romanian Deadlift",     role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Leg Curl",              role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Leg Extension",         role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Hip Thrust",            role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Walking Lunges",        role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryCount: 2
        )

        let pb_benchDay = SessionDefinition(
            sessionName: "Bench Power Day",
            primaryExercises: [
                .init(exerciseName: "Bench Press",    role: .primary, defaultSets: 5, defaultReps: 3, percentage1RM: 0.88, targetRPE: nil),
                .init(exerciseName: "Overhead Press", role: .primary, defaultSets: 3, defaultReps: 6, percentage1RM: 0.75, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Incline Bench",         role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Dumbbell Bench Press",  role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Chest Dip",             role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Tricep Pushdown",       role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Skull Crushers",        role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Lateral Raises",        role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Cable Lateral Raise",   role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 2
        )

        let pb_deadliftDay = SessionDefinition(
            sessionName: "Deadlift Power Day",
            primaryExercises: [
                .init(exerciseName: "Deadlift",    role: .primary, defaultSets: 4, defaultReps: 3, percentage1RM: 0.88, targetRPE: nil),
                .init(exerciseName: "Barbell Row", role: .primary, defaultSets: 3, defaultReps: 5, percentage1RM: 0.78, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Romanian Deadlift", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Hip Thrust",        role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Lat Pulldown",      role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Pull-ups",          role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Seated Cable Row",  role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Barbell Curl",      role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Hammer Curl",       role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Face Pulls",        role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 2
        )

        let pb_hyperUpperDay = SessionDefinition(
            sessionName: "Upper Hypertrophy",
            primaryExercises: [
                .init(exerciseName: "Close Grip Bench Press", role: .variation, defaultSets: 3, defaultReps: 8, percentage1RM: 0.72, targetRPE: nil),
                .init(exerciseName: "Overhead Press",         role: .primary,   defaultSets: 3, defaultReps: 8, percentage1RM: 0.70, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Incline Dumbbell Press",    role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Dumbbell Bench Press",      role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Lat Pulldown",              role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Seated Cable Row",          role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Barbell Curl",              role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Tricep Pushdown",           role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Face Pulls",                role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Lateral Raises",            role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 3
        )

        let pb_hyperLowerDay = SessionDefinition(
            sessionName: "Lower Hypertrophy",
            primaryExercises: [
                .init(exerciseName: "Front Squat",      role: .variation, defaultSets: 3, defaultReps: 8, percentage1RM: 0.65, targetRPE: nil),
                .init(exerciseName: "Romanian Deadlift",role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryPool: [
                .init(exerciseName: "Leg Press",             role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Leg Curl",              role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Leg Extension",         role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Bulgarian Split Squat", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Hip Thrust",            role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Glute Bridge",          role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Calf Raises",           role: .accessory, defaultSets: 4, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 3
        )

        let pb_armsDay = SessionDefinition(
            sessionName: "Arms & Accessories",
            primaryExercises: [
                .init(exerciseName: "Barbell Curl",    role: .accessory, defaultSets: 3, defaultReps: 8, percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Tricep Pushdown", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 8),
            ],
            accessoryPool: [
                .init(exerciseName: "EZ Bar Curl",               role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Hammer Curl",               role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Preacher Curl",             role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Overhead Tricep Extension", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Skull Crushers",            role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Cable Tricep Kickback",     role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Close Grip Push-ups",       role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryCount: 4
        )

        return FocusTemplate(
            focus: .powerbuilding,
            displayName: "Powerbuilding",
            minimumFrequency: 3,
            requiredLifts: ["Back Squats", "Bench Press", "Deadlift"],
            exercisesPerSession: 4...5,
            sessionDefinitions: [
                3: [pb_squatDay, pb_benchDay, pb_deadliftDay],
                4: [pb_squatDay, pb_benchDay, pb_deadliftDay, pb_hyperUpperDay],
                5: [pb_squatDay, pb_benchDay, pb_deadliftDay, pb_hyperUpperDay, pb_hyperLowerDay],
                6: [pb_squatDay, pb_benchDay, pb_deadliftDay, pb_hyperUpperDay, pb_hyperLowerDay, pb_armsDay],
            ]
        )
    }
}

// MARK: - Bodybuilding
// Inspired by Jeff Nippard hypertrophy programs and MorePlatesMoreDates volume principles.

private extension FocusTemplateLibrary {
    static var bodybuildingTemplate: FocusTemplate {
        // 4-day: Chest/Tri, Back/Bi, Shoulders, Legs
        let bb_chestTri4 = SessionDefinition(
            sessionName: "Chest & Triceps",
            primaryExercises: [
                .init(exerciseName: "Bench Press",   role: .primary,   defaultSets: 4, defaultReps: 6, percentage1RM: 0.75, targetRPE: nil),
                .init(exerciseName: "Incline Bench", role: .variation, defaultSets: 4, defaultReps: 8, percentage1RM: 0.70, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Dumbbell Bench Press",      role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Incline Dumbbell Press",    role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Chest Dip",                 role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Cable Flyes",               role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Dumbbell Flyes",            role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Pec Deck Machine Fly",      role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Tricep Pushdown",           role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Skull Crushers",            role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Overhead Tricep Extension", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Close Grip Bench Press",    role: .variation, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Cable Tricep Kickback",     role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryCount: 4
        )

        let bb_backBi4 = SessionDefinition(
            sessionName: "Back & Biceps",
            primaryExercises: [
                .init(exerciseName: "Deadlift",    role: .primary, defaultSets: 3, defaultReps: 4, percentage1RM: 0.85, targetRPE: nil),
                .init(exerciseName: "Barbell Row", role: .primary, defaultSets: 4, defaultReps: 6, percentage1RM: 0.72, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Lat Pulldown",       role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Pull-ups",           role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Chin-ups",           role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Seated Cable Row",   role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "T-Bar Row",          role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Dumbbell Row",       role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Straight Arm Pulldown", role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Barbell Curl",       role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "EZ Bar Curl",        role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Hammer Curl",        role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Preacher Curl",      role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Incline Dumbbell Curl", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Concentration Curl", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Cable Curl",         role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryCount: 4
        )

        let bb_shoulders4 = SessionDefinition(
            sessionName: "Shoulders",
            primaryExercises: [
                .init(exerciseName: "Overhead Press",       role: .primary,   defaultSets: 4, defaultReps: 6, percentage1RM: 0.75, targetRPE: nil),
                .init(exerciseName: "Barbell Strict Press", role: .variation, defaultSets: 3, defaultReps: 6, percentage1RM: 0.72, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "DB Shoulder Press",    role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Arnold Press",         role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Machine Shoulder Press",role: .accessory,defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Lateral Raises",       role: .accessory, defaultSets: 4, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Cable Lateral Raise",  role: .accessory, defaultSets: 4, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Front Raises",         role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Reverse Flyes",        role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Face Pulls",           role: .accessory, defaultSets: 3, defaultReps: 20, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 4
        )

        let bb_legs4 = SessionDefinition(
            sessionName: "Legs",
            primaryExercises: [
                .init(exerciseName: "Back Squats",      role: .primary,   defaultSets: 4, defaultReps: 6, percentage1RM: 0.75, targetRPE: nil),
                .init(exerciseName: "Romanian Deadlift",role: .accessory, defaultSets: 3, defaultReps: 8, percentage1RM: nil,  targetRPE: 7),
            ],
            accessoryPool: [
                .init(exerciseName: "Front Squat",           role: .variation, defaultSets: 3, defaultReps: 8,  percentage1RM: 0.68, targetRPE: nil),
                .init(exerciseName: "Leg Press",             role: .accessory, defaultSets: 4, defaultReps: 12, percentage1RM: nil,  targetRPE: 7),
                .init(exerciseName: "Bulgarian Split Squat", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil,  targetRPE: 7),
                .init(exerciseName: "Hack Squat",            role: .variation, defaultSets: 3, defaultReps: 10, percentage1RM: nil,  targetRPE: 7),
                .init(exerciseName: "Leg Curl",              role: .accessory, defaultSets: 4, defaultReps: 12, percentage1RM: nil,  targetRPE: 7),
                .init(exerciseName: "Leg Extension",         role: .accessory, defaultSets: 4, defaultReps: 15, percentage1RM: nil,  targetRPE: 7),
                .init(exerciseName: "Calf Raises",           role: .accessory, defaultSets: 4, defaultReps: 15, percentage1RM: nil,  targetRPE: 6),
                .init(exerciseName: "Seated Calf Raise",     role: .accessory, defaultSets: 4, defaultReps: 15, percentage1RM: nil,  targetRPE: 6),
                .init(exerciseName: "Hip Thrust",            role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil,  targetRPE: 7),
                .init(exerciseName: "Glute Bridge",          role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil,  targetRPE: 6),
                .init(exerciseName: "Walking Lunges",        role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil,  targetRPE: 7),
                .init(exerciseName: "Good Mornings",         role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil,  targetRPE: 6),
            ],
            accessoryCount: 5
        )

        // 5-day: Chest, Back, Shoulders, Legs, Arms
        let bb_chest5 = SessionDefinition(
            sessionName: "Chest",
            primaryExercises: [
                .init(exerciseName: "Bench Press", role: .primary, defaultSets: 4, defaultReps: 6, percentage1RM: 0.75, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Incline Bench",         role: .variation, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Dumbbell Bench Press",  role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Incline Dumbbell Press",role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Chest Dip",             role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Cable Flyes",           role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Pec Deck Machine Fly",  role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Close Grip Bench Press",role: .variation, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryCount: 4
        )

        let bb_back5 = SessionDefinition(
            sessionName: "Back",
            primaryExercises: [
                .init(exerciseName: "Barbell Row", role: .primary, defaultSets: 4, defaultReps: 6, percentage1RM: 0.72, targetRPE: nil),
                .init(exerciseName: "Deadlift",    role: .primary, defaultSets: 3, defaultReps: 4, percentage1RM: 0.85, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Lat Pulldown",       role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Pull-ups",           role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Seated Cable Row",   role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "T-Bar Row",          role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Chin-ups",           role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Dumbbell Row",       role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Straight Arm Pulldown", role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryCount: 3
        )

        let bb_shoulders5 = SessionDefinition(
            sessionName: "Shoulders",
            primaryExercises: [
                .init(exerciseName: "Overhead Press", role: .primary, defaultSets: 4, defaultReps: 6, percentage1RM: 0.75, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "DB Shoulder Press",    role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Arnold Press",         role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Machine Shoulder Press",role: .accessory,defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Lateral Raises",       role: .accessory, defaultSets: 4, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Cable Lateral Raise",  role: .accessory, defaultSets: 4, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Face Pulls",           role: .accessory, defaultSets: 3, defaultReps: 20, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Reverse Flyes",        role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 4
        )

        let bb_legs5 = SessionDefinition(
            sessionName: "Legs",
            primaryExercises: [
                .init(exerciseName: "Back Squats",      role: .primary,   defaultSets: 4, defaultReps: 6, percentage1RM: 0.75, targetRPE: nil),
                .init(exerciseName: "Romanian Deadlift",role: .accessory, defaultSets: 3, defaultReps: 8, percentage1RM: nil,  targetRPE: 7),
            ],
            accessoryPool: [
                .init(exerciseName: "Leg Press",             role: .accessory, defaultSets: 4, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Hack Squat",            role: .variation, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Bulgarian Split Squat", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Leg Curl",              role: .accessory, defaultSets: 4, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Leg Extension",         role: .accessory, defaultSets: 4, defaultReps: 15, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Hip Thrust",            role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Calf Raises",           role: .accessory, defaultSets: 4, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Seated Calf Raise",     role: .accessory, defaultSets: 4, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Walking Lunges",        role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryCount: 4
        )

        let bb_arms5 = SessionDefinition(
            sessionName: "Arms",
            primaryExercises: [
                .init(exerciseName: "Barbell Curl",    role: .accessory, defaultSets: 4, defaultReps: 8,  percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Tricep Pushdown", role: .accessory, defaultSets: 4, defaultReps: 10, percentage1RM: nil, targetRPE: 8),
            ],
            accessoryPool: [
                .init(exerciseName: "EZ Bar Curl",               role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Hammer Curl",               role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Preacher Curl",             role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Concentration Curl",        role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Cable Curl",                role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Skull Crushers",            role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Overhead Tricep Extension", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Close Grip Bench Press",    role: .variation, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Cable Tricep Kickback",     role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Close Grip Push-ups",       role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryCount: 4
        )

        // 6-day: Chest/Tri, Back/Bi, Shoulders, Quads, Arms, Hamstrings/Glutes
        let bb_chestTri6 = SessionDefinition(
            sessionName: "Chest & Triceps",
            primaryExercises: [
                .init(exerciseName: "Bench Press",   role: .primary,   defaultSets: 4, defaultReps: 6, percentage1RM: 0.75, targetRPE: nil),
                .init(exerciseName: "Incline Bench", role: .variation, defaultSets: 4, defaultReps: 8, percentage1RM: 0.70, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Dumbbell Bench Press",      role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Chest Dip",                 role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Cable Flyes",               role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Pec Deck Machine Fly",      role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Tricep Pushdown",           role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Skull Crushers",            role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Overhead Tricep Extension", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Cable Tricep Kickback",     role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryCount: 4
        )

        let bb_backBi6 = SessionDefinition(
            sessionName: "Back & Biceps",
            primaryExercises: [
                .init(exerciseName: "Barbell Row",  role: .primary, defaultSets: 4, defaultReps: 6, percentage1RM: 0.72, targetRPE: nil),
                .init(exerciseName: "Pendlay Row",  role: .primary, defaultSets: 3, defaultReps: 5, percentage1RM: 0.75, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Lat Pulldown",       role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Pull-ups",           role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Chin-ups",           role: .accessory, defaultSets: 3, defaultReps: 8,  percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Seated Cable Row",   role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "T-Bar Row",          role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Dumbbell Row",       role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Barbell Curl",       role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "EZ Bar Curl",        role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Hammer Curl",        role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Preacher Curl",      role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryCount: 4
        )

        let bb_shoulders6 = SessionDefinition(
            sessionName: "Shoulders",
            primaryExercises: [
                .init(exerciseName: "Overhead Press", role: .primary, defaultSets: 4, defaultReps: 6, percentage1RM: 0.75, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "DB Shoulder Press",    role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Arnold Press",         role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Machine Shoulder Press",role: .accessory,defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Lateral Raises",       role: .accessory, defaultSets: 4, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Cable Lateral Raise",  role: .accessory, defaultSets: 4, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Front Raises",         role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Reverse Flyes",        role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Face Pulls",           role: .accessory, defaultSets: 3, defaultReps: 20, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 4
        )

        let bb_quads6 = SessionDefinition(
            sessionName: "Quads",
            primaryExercises: [
                .init(exerciseName: "Back Squats", role: .primary,   defaultSets: 4, defaultReps: 6, percentage1RM: 0.75, targetRPE: nil),
                .init(exerciseName: "Front Squat", role: .variation, defaultSets: 3, defaultReps: 6, percentage1RM: 0.68, targetRPE: nil),
            ],
            accessoryPool: [
                .init(exerciseName: "Leg Press",             role: .accessory, defaultSets: 4, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Hack Squat",            role: .variation, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Bulgarian Split Squat", role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Leg Extension",         role: .accessory, defaultSets: 4, defaultReps: 15, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Calf Raises",           role: .accessory, defaultSets: 4, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Seated Calf Raise",     role: .accessory, defaultSets: 4, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Walking Lunges",        role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Goblet Squat",          role: .variation, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryCount: 4
        )

        let bb_arms6 = SessionDefinition(
            sessionName: "Arms",
            primaryExercises: [
                .init(exerciseName: "Barbell Curl",    role: .accessory, defaultSets: 4, defaultReps: 8,  percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Tricep Pushdown", role: .accessory, defaultSets: 4, defaultReps: 10, percentage1RM: nil, targetRPE: 8),
            ],
            accessoryPool: [
                .init(exerciseName: "EZ Bar Curl",               role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Hammer Curl",               role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Preacher Curl",             role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Concentration Curl",        role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Cable Curl",                role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Skull Crushers",            role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Overhead Tricep Extension", role: .accessory, defaultSets: 3, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Cable Tricep Kickback",     role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 7),
            ],
            accessoryCount: 4
        )

        let bb_hamGlutes6 = SessionDefinition(
            sessionName: "Hamstrings & Glutes",
            primaryExercises: [
                .init(exerciseName: "Deadlift",         role: .primary,   defaultSets: 3, defaultReps: 4, percentage1RM: 0.85, targetRPE: nil),
                .init(exerciseName: "Romanian Deadlift",role: .accessory, defaultSets: 4, defaultReps: 8, percentage1RM: nil,  targetRPE: 7),
            ],
            accessoryPool: [
                .init(exerciseName: "Hip Thrust",        role: .accessory, defaultSets: 4, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Leg Curl",          role: .accessory, defaultSets: 4, defaultReps: 12, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Glute Bridge",      role: .accessory, defaultSets: 4, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Good Mornings",     role: .accessory, defaultSets: 3, defaultReps: 10, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Cable Pull Through",role: .accessory, defaultSets: 3, defaultReps: 15, percentage1RM: nil, targetRPE: 7),
                .init(exerciseName: "Seated Calf Raise", role: .accessory, defaultSets: 4, defaultReps: 15, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 3
        )

        return FocusTemplate(
            focus: .bodybuilding,
            displayName: "Bodybuilding",
            minimumFrequency: 4,
            requiredLifts: ["Back Squats", "Bench Press", "Deadlift", "Overhead Press"],
            exercisesPerSession: 6...8,
            sessionDefinitions: [
                4: [bb_chestTri4, bb_backBi4, bb_shoulders4, bb_legs4],
                5: [bb_chest5, bb_back5, bb_shoulders5, bb_legs5, bb_arms5],
                6: [bb_chestTri6, bb_backBi6, bb_shoulders6, bb_quads6, bb_arms6, bb_hamGlutes6],
            ]
        )
    }
}

// MARK: - Cardio Endurance
// All sessions draw from the Cardio muscle group.
// defaultReps represents target duration in minutes before progression adjustments.
// Session names encode cardio archetype so ProgramGenerationService can apply
// session-type progression rules (easy, threshold, interval, long, recovery).

private extension FocusTemplateLibrary {
    static var cardioEnduranceTemplate: FocusTemplate {
        let easyAerobicDay = SessionDefinition(
            sessionName: "Easy Aerobic / Zone 2",
            primaryExercises: [
                .init(exerciseName: "Treadmill", role: .cardio, defaultSets: 1, defaultReps: 30, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryPool: [
                .init(exerciseName: "Exercise Bike",    role: .cardio, defaultSets: 1, defaultReps: 30, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Elliptical",       role: .cardio, defaultSets: 1, defaultReps: 30, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Incline Treadmill",role: .cardio, defaultSets: 1, defaultReps: 30, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Rowing Machine",   role: .cardio, defaultSets: 1, defaultReps: 25, percentage1RM: nil, targetRPE: 6),
                .init(exerciseName: "Stairmaster",      role: .cardio, defaultSets: 1, defaultReps: 25, percentage1RM: nil, targetRPE: 6),
            ],
            accessoryCount: 0
        )

        let thresholdDay = SessionDefinition(
            sessionName: "Threshold / Tempo",
            primaryExercises: [
                .init(exerciseName: "Exercise Bike", role: .cardio, defaultSets: 1, defaultReps: 28, percentage1RM: nil, targetRPE: 8),
            ],
            accessoryPool: [
                .init(exerciseName: "Rowing Machine",   role: .cardio, defaultSets: 1, defaultReps: 28, percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Incline Treadmill",role: .cardio, defaultSets: 1, defaultReps: 26, percentage1RM: nil, targetRPE: 8),
                .init(exerciseName: "Stairmaster",      role: .cardio, defaultSets: 1, defaultReps: 24, percentage1RM: nil, targetRPE: 8),
            ],
            accessoryCount: 0
        )

        let intervalDay = SessionDefinition(
            sessionName: "Interval / VO2",
            primaryExercises: [
                .init(exerciseName: "Rowing Machine", role: .cardio, defaultSets: 1, defaultReps: 22, percentage1RM: nil, targetRPE: 9),
            ],
            accessoryPool: [
                .init(exerciseName: "Exercise Bike", role: .cardio, defaultSets: 1, defaultReps: 22, percentage1RM: nil, targetRPE: 9),
                .init(exerciseName: "Jump Rope",     role: .cardio, defaultSets: 1, defaultReps: 18, percentage1RM: nil, targetRPE: 9),
                .init(exerciseName: "Treadmill",     role: .cardio, defaultSets: 1, defaultReps: 22, percentage1RM: nil, targetRPE: 9),
                .init(exerciseName: "Stairmaster",   role: .cardio, defaultSets: 1, defaultReps: 20, percentage1RM: nil, targetRPE: 8),
            ],
            accessoryCount: 0
        )

        let longSteadyStateDay = SessionDefinition(
            sessionName: "Long Steady Session",
            primaryExercises: [
                .init(exerciseName: "Elliptical", role: .cardio, defaultSets: 1, defaultReps: 45, percentage1RM: nil, targetRPE: 5),
            ],
            accessoryPool: [
                .init(exerciseName: "Treadmill",        role: .cardio, defaultSets: 1, defaultReps: 45, percentage1RM: nil, targetRPE: 5),
                .init(exerciseName: "Incline Treadmill",role: .cardio, defaultSets: 1, defaultReps: 40, percentage1RM: nil, targetRPE: 5),
                .init(exerciseName: "Rowing Machine",   role: .cardio, defaultSets: 1, defaultReps: 40, percentage1RM: nil, targetRPE: 5),
                .init(exerciseName: "Stairmaster",      role: .cardio, defaultSets: 1, defaultReps: 35, percentage1RM: nil, targetRPE: 5),
            ],
            accessoryCount: 0
        )

        let activeRecoveryDay = SessionDefinition(
            sessionName: "Recovery Session",
            primaryExercises: [
                .init(exerciseName: "Elliptical", role: .cardio, defaultSets: 1, defaultReps: 30, percentage1RM: nil, targetRPE: 4),
            ],
            accessoryPool: [
                .init(exerciseName: "Exercise Bike",role: .cardio, defaultSets: 1, defaultReps: 30, percentage1RM: nil, targetRPE: 4),
                .init(exerciseName: "Treadmill",    role: .cardio, defaultSets: 1, defaultReps: 30, percentage1RM: nil, targetRPE: 4),
                .init(exerciseName: "Rowing Machine",role: .cardio,defaultSets: 1, defaultReps: 25, percentage1RM: nil, targetRPE: 4),
            ],
            accessoryCount: 0
        )

        return FocusTemplate(
            focus: .cardioEndurance,
            displayName: "Cardio Endurance",
            minimumFrequency: 3,
            requiredLifts: [],
            exercisesPerSession: 1...1,
            sessionDefinitions: [
                3: [easyAerobicDay, thresholdDay, longSteadyStateDay],
                4: [easyAerobicDay, thresholdDay, intervalDay, longSteadyStateDay],
                5: [easyAerobicDay, thresholdDay, intervalDay, longSteadyStateDay, easyAerobicDay],
                6: [easyAerobicDay, thresholdDay, intervalDay, longSteadyStateDay, easyAerobicDay, activeRecoveryDay],
            ]
        )
    }
}
