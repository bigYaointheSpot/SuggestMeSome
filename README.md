# SuggestMeSome

A personal iOS workout tracking and AI-powered workout generation app.
Built with SwiftUI + SwiftData.

---

## App Overview

SuggestMeSome lets users manually log workouts, auto-generate AI-suggested
workouts, and track personal records over time. The app is structured around
a tab-based navigation with a Workouts tab and a Training Programs tab.

**Tech Stack:** SwiftUI, SwiftData, Xcode
**Platform:** iOS
**Storage:** On-device (SQLite via SwiftData)

---

## Changelog

---

### Feature 1 — Manual Workout Logging

**Status:** Complete

Core workout tracking feature. Users can start a workout, log exercises with
individual set-by-set weight and reps, and review their history.

---

#### Prompt 1 — Data Models

**Commit:** `feat: initial project setup with data models, workout tracking, history, and exercise management`

Established the full SwiftData schema:

- **MuscleGroup** — name, seeded with: Chest, Back, Shoulders, Arms, Legs, Core
- **Exercise** — name, relationship to MuscleGroup, seeded with ~50 default exercises
- **Workout** — id, date, startTime, durationSeconds (stored as Int, displayed as hh:mm:ss), optional caloriesBurned, optional comments. One-to-many → ExerciseEntry (cascade delete)
- **ExerciseEntry** — id, exerciseName, unit (lbs/kg enum, set per entry), orderIndex. One-to-many → SetEntry (cascade delete)
- **SetEntry** — id, setNumber, reps, weight (Double), isPR (Bool, default false)
- **PersonalRecord** — id, exerciseName, repCount, weight, unit, dateAchieved. One record max per exercise per rep count. Auto-created or updated when a saved SetEntry exceeds the previous best for that exercise at that rep count

Seed data populates MuscleGroups and Exercises on first launch only. ModelContainer configured at App entry point with all models registered.

---

#### Prompt 2 — Active Workout Screen (WorkoutView)

Workout logging UI with a live timer and set-by-set entry.

- **Timer:** Start button stores startTime as a Date. Elapsed time displayed as hh:mm:ss, calculated from (now - startTime) and updated every second. Survives backgrounding because it derives time from stored startTime, not an incrementing counter
- **Adding exercises:** Button opens a picker — muscle group first, then exercises within that group
- **Set logging:** Each exercise generates individual rows (Option B). Each row captures reps and weight independently, supporting per-set variation
- **Finishing:** End Workout button stops the timer, runs PR detection across all sets, saves the Workout to SwiftData
- **PR detection:** Automatic, per rep count. If a set's weight exceeds the stored PersonalRecord for that exercise at that rep count, PR is updated and isPR flagged on the SetEntry

---

#### Prompt 3 — Home Screen & History

Main navigation and workout history.

- **Home screen:** "Start Workout" button navigates to WorkoutView. Below it, a scrollable list of all past workouts sorted by date descending
- **Workout row:** Shows date (formatted e.g. "Mon, Apr 4, 2026"), duration in hh:mm:ss, number of exercises, and a gold star if any PR was achieved in that session
- **Filtering:** Filter bar above the list with date range pickers, exercise picker (shows only workouts containing that exercise), PR toggle, and a Clear Filters button
- **Workout detail:** Tapping a row opens a read-only view showing date, duration, calories, all exercises with sets/reps/weights, gold stars on PR sets, and comments
- **Edit:** Edit button on the detail view allows modifying any field. On save, PR detection re-runs. Handles cases where lowering a weight may invalidate an existing PR
- **Delete:** Swipe-to-delete on history rows with a confirmation alert

---

#### Prompt 4 — Exercise Management Screen

Settings screen accessible via gear icon in the nav bar.

- View all muscle groups and exercises in a grouped list
- Add, rename, or delete muscle groups (with confirmation; warns if exercises exist under it)
- Add, rename, or delete exercises (with confirmation; warns if used in past workouts)
- Personal Records screen showing all PRs organized by exercise — rep count, weight, unit, and date achieved

---

### Feature 2 — AI Workout Generator (SuggestMeSome)

**Status:** Complete

AI-powered workout generation based on muscle group selection, intensity, and
available time. Generated workouts pre-populate WorkoutView and are fully editable.

---

#### Prompt 1 — Data Model Updates (Cardio + Exercise Types)

Updated existing models to support exercise classification and cardio.

- **ExerciseType enum** added to Exercise model: `compound`, `isolation`, `accessory`, `cardio`
- **baseTimeMinutes** computed property on Exercise: compound = 30 min, accessory = 15 min, isolation = 10 min, cardio = 0 (user-specified duration)
- **Cardio muscle group** seeded with: Exercise Bike, Elliptical, Treadmill, Incline Treadmill, Stairmaster, Rowing Machine, Jump Rope — all typed `.cardio`
- **All existing seed exercises** updated with correct ExerciseType (Bench Press, Deadlift, Squat etc. → compound; Curls, Flyes etc. → isolation; Lateral Raises, Face Pulls etc. → accessory)
- **ExerciseEntry** updated with `isCardio` (Bool, default false) and `cardioDurationSeconds` (optional Int). Cardio entries have zero SetEntry children
- **WorkoutView** updated to render cardio entries with a single time input field (minutes and seconds) — no sets, no weight, no PR star

**Commit:** `feat: update data models with exercise types and cardio support`

---

#### Prompt 2 — WorkoutGeneratorService

Core generation logic as a standalone service.

**Intensity → Rep Range mapping:**
| Intensity | Rep Range |
|-----------|-----------|
| 1 | 10–12 reps |
| 2 | 8–10 reps |
| 3 | 6–8 reps |
| 4 | 5–6 reps |
| 5 | 3–5 reps |

**Set structure per exercise:**
- 3 warmup sets: 40%, 55%, 70% of heaviest working set weight
- 4 working sets: ramping up, capped at 95% of the user's PR for that exercise at that rep count
- If no PR exists: suggestedWeight left as nil (displayed as "—")

**Custom workout generation (muscle groups + exercises + duration + intensity):**
1. Build pool from selected muscle groups + explicitly selected exercises
2. Exclude cardio exercises from pool
3. Score exercises: compound = 3, accessory = 2, isolation = 1
4. Shuffle pool, sort by score descending (compounds first)
5. Greedily select exercises until next addition would exceed duration
6. Must include at least 1 compound; tries for 2 if duration allows

**Full body generation (duration + intensity only):**
- Pool built from all muscle groups except Cardio
- Same scoring and selection logic
- Ensures coverage across Legs, Chest, Back, and Shoulders before doubling up any group

Uses `Int.random` and shuffling throughout to ensure non-deterministic output on every generation.

**Commit:** `feat: add workout generator service with intensity-based logic`

---

#### Prompt 3 — Generator UI & Home Screen Integration

UI for workout generation and integration into the main home screen.

- **Home screen:** "SuggestMeSome" button added below "Start Workout," in a visually distinct color. Tapping presents a choice: "Custom Workout" or "Full Body Workout"
- **Custom input screen:** Multi-select muscle group picker, optional specific exercise picker (grouped by muscle group), duration picker (30–180 min in 15-min intervals), intensity selector (5 discrete tappable buttons labeled 1–5 with descriptions), and a Generate button
- **Full body input screen:** Duration picker + intensity selector only, no exercise selection
- **Generated workout preview:** List of exercises showing warmup sets (visually distinct, lighter styling or "Warmup" label) and working sets with suggested reps and weights. Missing weight shown as "—"
- **Shuffle button:** Regenerates the workout with the same inputs without returning to the input screen
- **Start This Workout:** Loads all generated exercises into WorkoutView with suggestions pre-filled. Timer starts, all values are editable. PR detection and saving work exactly as in Feature 1
- **Last settings persisted:** Generation inputs saved via @AppStorage or SwiftData and pre-filled on next open

**Commit:** `feat: add SuggestMeSome workout generator UI and home screen button`

---

#### Prompt 4 — Cardio Generator

Cardio support in the generator flow.

- Selecting the Cardio muscle group in the custom generator does not produce sets/reps/weight output
- Cardio duration in the generated workout is calculated from remaining time budget after strength exercises are allocated
- Preview screen displays cardio as "Exercise Bike — 20 min" style (no sets or reps)
- Handing off to WorkoutView loads the cardio entry using the cardio display mode (time input only, no sets/reps/weight)

**Commit:** `feat: add cardio support to workout generator`

---

### Feature 3 — Training Programs

**Status:** In Progress

Structured multi-week training programs that link workouts to a prescribed schedule.

---

#### Prompt 1 — Data Models

**Commit:** `feat: add training program data models and update Workout for program linkage`

New SwiftData models added to support reusable program templates and tracked program runs:

- **ProgramSource enum** — `userCreated`, `template`, `aiGenerated`
- **TrainingProgram** — id, name, lengthInWeeks (6/8/10/12), sessionsPerWeek (2–6), createdDate, source (ProgramSource), optional descriptionText. One-to-many → ProgramWeekTemplate (cascade delete)
- **ProgramWeekTemplate** — id, weekNumber (1-based), belongs to TrainingProgram. One-to-many → ProgramSessionTemplate (cascade delete)
- **ProgramSessionTemplate** — id, sessionNumber (1-based, range 1–6), belongs to ProgramWeekTemplate. One-to-many → ProgramSessionExercise (cascade delete)
- **ProgramSessionExercise** — id, exerciseName, orderIndex, optional targetSets, optional targetReps, belongs to ProgramSessionTemplate
- **ProgramRun** — id, startDate, optional endDate, isCompleted (default false), belongs to TrainingProgram

**Workout model updated** with three optional fields for program linkage (all nil for standalone workouts):
- `programRun` — relationship to ProgramRun
- `programWeekNumber` — Int
- `programSessionNumber` — Int

All new models registered in the ModelContainer at app entry point.

**Known limitations:** No UI yet; data layer only.

---

#### Prompt 2 — Tab Bar Navigation & Training Programs Shell

Converted the app from a single-screen layout to a TabView and added the Training Programs tab shell.

- **ContentView** converted to a `TabView` with two tabs: "Workouts" (dumbbell icon) and "Training Programs" (list.clipboard icon)
- **WorkoutsTab** extracted from the old ContentView — all existing workout history, filtering, and generator flow unchanged
- **Action button row** updated: "Start Workout", "SuggestMeSome", and "Complete Program Workout" (orange) sit in a single horizontal HStack with equal widths. "Complete Program Workout" only renders when at least one active (not completed) `ProgramRun` exists
- **TrainingProgramsTab** — new view with "Create Your Own Program" (blue) and "Use Existing Program" (purple) buttons at top, plus a list of all `ProgramRun` records sorted active-first then completed by endDate descending. Each row shows program name, Active/Completed badge, start date, and X/Y workouts count
- **CreateProgramView / SelectProgramView** — placeholder views ("Coming Soon") for future prompts
- Tapping a program run row does nothing yet

**Commit:** `feat: add tab bar navigation and training programs tab shell`

---

#### Prompt 3 — Program Creation Flow

Multi-step wizard for creating a user-defined training program.

- **Step 1 — Program Basics:** Name text field (required to proceed), length picker (6/8/10/12 weeks), sessions per week picker (2–6). Next button disabled until name is non-empty.
- **Step 2 — Exercise Selection:** Muscle group → exercise hierarchy using DisclosureGroups with checkmark multi-select. Selected exercises listed in insertion order. Count badge in safeAreaInset. Next button disabled until at least 1 exercise selected.
- **Step 3 — Assign to Sessions:** Each selected exercise shows session toggle buttons (S1–SN), plus optional Target Sets and Target Reps text fields. Validation ensures every session has at least 1 exercise before proceeding.
- **Step 4 — Review & Customize:** All weeks auto-populated from the Week 1 template. Weeks collapse/expand with a tap. Expanded weeks show each session with its exercises. Per-session: swipe-to-delete exercises, drag-to-reorder (via EditButton in nav bar), add exercise button (opens `ProgramExercisePickerSheet` with optional sets/reps), inline editing of targetSets/targetReps. "Save Program" button creates all SwiftData objects and dismisses.
- **ProgramExercisePickerSheet:** Reusable sheet for picking an exercise by muscle group → exercise hierarchy, then specifying optional target sets/reps before adding.
- **New file:** `SuggestMeSome/Views/CreateProgramView.swift` — contains `DraftSessionExercise`, `DraftSession`, `DraftWeek` value types plus `CreateProgramView` and `ProgramExercisePickerSheet`.

**Commit:** `feat: add training program creation flow with weekly customization`

---

## Project Setup

- **Language:** Swift
- **Framework:** SwiftUI + SwiftData
- **Minimum Deployment:** iOS 17+
- **Version Control:** Git
- **AI Tooling:** Claude Code (Claude Pro)
- **Session Persistence:** CLAUDE.md in project root

---

## Notes for Future Sessions

- Weight units (lbs/kg) are toggled per ExerciseEntry, not globally
- Duration is always stored in seconds; formatted as hh:mm:ss for display
- PR detection is automatic on workout save, per rep count
- Generated workouts cap suggested weight at 95% of PR — never suggest attempting a PR
- Cardio exercises follow a completely separate data and display path from strength exercises