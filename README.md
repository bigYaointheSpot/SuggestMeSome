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

**Status:** Complete

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

#### Prompt 4 — Program Workout Execution

Starting and completing workouts within an active program run.

- **"Use Existing Program" flow:** Replaced placeholder with a real list of all saved `TrainingProgram`s sorted by createdDate descending. Each row shows name, length, sessions/week, and source label (Custom/Template/AI Generated). Tapping a row presents a confirmation dialog; confirming creates a `ProgramRun` linked to that program and navigates back to the Training Programs tab.
- **Program run detail:** Tapping any row in the Training Programs list navigates to `ProgramRunDetailView` showing program info, progress (X/Y workouts), status, and start/end dates. Active runs show an "End Program Early" button that marks the run as completed.
- **"Complete Program Workout" button:** Changed from a no-op NavigationLink to a Button that presents `CompleteProgramWorkoutSheet`. The sheet lists all active runs (skips selection if only one active run). After selecting a run, auto-detects the next uncompleted week/session in order (Week 1 Session 1 → Week 1 Session 2 → Week 2 Session 1 etc.). Displays the detected session with exercise list and optional target sets×reps. "Choose Different Session" button opens a picker sheet for manual week/session selection.
- **WorkoutView handoff:** `WorkoutView` accepts a new `programWorkout: ProgramWorkoutContext?` parameter alongside the existing `generatedWorkout`. On appear, pre-populates exercise entries from the session's `ProgramSessionExercise` list: if `targetSets`/`targetReps` are set, creates that many sets with reps pre-filled; otherwise defaults to 3 empty sets. Unit defaults to the user's last-known unit from PersonalRecords, or lbs.
- **Saving with program linkage:** When saving a program workout, the `Workout` record is created with `programRun`, `programWeekNumber`, and `programSessionNumber` populated.
- **Auto-completion:** After saving, checks if all `lengthInWeeks × sessionsPerWeek` sessions now have linked workouts for this run. If so, sets `ProgramRun.isCompleted = true` and `endDate = now`.
- **New file:** `SuggestMeSome/Views/ProgramWorkoutViews.swift` — contains `ProgramWorkoutContext`, `SelectProgramView`, `ProgramListRow`, `ProgramRunDetailView`, `CompleteProgramWorkoutSheet`, `SessionPickerSheet`.

**Commit:** `feat: add program workout execution with auto-detect and handoff to WorkoutView`

#### Prompt 5 — Program Detail View with Week Picker and Session History

Replaced non-functional program run row taps with an inline expandable detail view.

- **Expandable rows:** Program run rows in the Training Programs tab now expand inline (no navigation) with a rotating chevron indicator. The `programRunList` is now a `ScrollView + LazyVStack` for full layout control.
- **Info section:** Expanded view shows source badge (Custom Program / Template / AI Generated), status with colored dot, start date, end date (if completed), program length in weeks, and progress (N of M workouts completed).
- **End Program button:** Active program runs show an "End Program" button inside the expanded section with a destructive confirmation alert that marks `isCompleted = true` and sets `endDate`.
- **Week picker:** Horizontal scrollable capsule-style tab row showing "Week 1" through "Week N" based on `lengthInWeeks`. Selecting a week resets expanded session state.
- **Session cards:** Each session for the selected week is a collapsible card (collapsed by default). Header shows "Session N" with a green checkmark + "Completed" label if a linked Workout exists, or "Not completed" if not.
- **Completed session detail:** Expanding a completed session shows all exercises from the actual linked Workout using the existing `ExerciseDetailCard` — full sets/reps/weight table with gold star on PR sets, consistent with the Workouts tab history.
- **Uncompleted session detail:** Expanding an uncompleted session shows planned exercises from `ProgramSessionTemplate` with targets (e.g., "Bench Press — 4×8 planned", "Squat — 3 sets planned", or just "Planned" if no targets were set).
- **Reactivity:** Session completion and program end state update automatically via SwiftData `@Query` and `@Bindable`.

**Commit:** `feat: add program detail view with week picker and session history`

---

### Feature 4 — AI Program Generator

**Status:** Complete

---

#### Prompt 1 — Data Model Updates + New Seed Exercises — 2026-04-06

- **ProgramSessionExercise** updated: added `targetPercentage1RM` (optional Double, e.g. 0.85 = 85% 1RM), `targetRPE` (optional Double, 1–10 scale), `isWarmup` (Bool, default false)
- **ProgramSessionTemplate** updated: added `sessionName` (optional String, e.g. "Heavy Squat Day")
- **40 new exercises** added across 6 muscle groups via `migrateExercisesV2IfNeeded`:
  - Chest: Pause Bench Press, Close Grip Bench Press, Floor Press, Dumbbell Bench Press, Incline Dumbbell Press, Chest Dip, Pec Deck Machine Fly
  - Back: Sumo Deadlift, Deficit Deadlift, Block Pull, Pendlay Row, Dumbbell Row, Chin-ups, Straight Arm Pulldown
  - Shoulders: Barbell Strict Press, Cable Lateral Raise, Arnold Press, Machine Shoulder Press
  - Arms: EZ Bar Curl, Concentration Curl, Incline Dumbbell Curl, Cable Curl, Overhead Tricep Extension, Close Grip Push-ups, Cable Tricep Kickback
  - Legs: Pause Squat, Box Squat, Hack Squat, Hip Thrust, Good Mornings, Goblet Squat, Walking Lunges, Seated Calf Raise, Glute Bridge, Cable Pull Through, Sumo Squat
  - Core: Cable Crunch, Pallof Press, Dead Bug, Bird Dog, Weighted Plank
- Migration is idempotent: checks existing exercise names before inserting, guarded by `hasSeededExercisesV2` UserDefaults flag. New installs skip the migration entirely.

**Commit:** `feat: update program models and add new exercises for AI program generator`

---

#### Prompt 2 — Focus Template Library — 2026-04-07

Data-only file defining structured templates for all 11 program focuses.

**New file:** `SuggestMeSome/FocusTemplateLibrary.swift`

**New types:**
- `ProgramFocus` enum — 11 cases: `increaseMaxSquat`, `increaseMaxBench`, `increaseMaxDeadlift`, `powerlifting`, `generalFitness`, `fullBody`, `pushPull`, `fiveByFive`, `powerbuilding`, `bodybuilding`, `cardioEndurance`
- `ExerciseRole` enum — `primary`, `variation`, `accessory`, `cardio`
- `TemplateExercise` — exercise name, role, defaultSets/Reps, optional percentage1RM, optional targetRPE
- `SessionDefinition` — sessionName, primaryExercises (always included), accessoryPool (rotated for variety), accessoryCount
- `FocusTemplate` — focus, displayName, minimumFrequency, requiredLifts, exercisesPerSession range, sessionDefinitions keyed by frequency
- `FocusTemplateLibrary` enum — static `template(for:)` function

**Template highlights:**
| Focus | Min Freq | Required Lifts | Exercises/Session | Notes |
|---|---|---|---|---|
| Increase Max Squat | 3 | Squat, Deadlift | 3–4 | Candito/CWS peaking |
| Increase Max Bench | 3 | Bench, OHP | 3–4 | Strengtheory frequency |
| Increase Max Deadlift | 3 | Deadlift, Squat | 3–4 | Candito/Mash pulling |
| Powerlifting | 3 | Squat, Bench, Deadlift | 4–5 | SBD specificity, higher bench frequency |
| General Fitness | 2 | Squat, Bench, Deadlift | 5–6 | Upper/Lower → PPL × 2 |
| Full Body | 2 | Squat, Bench, Deadlift | 5 | Lower + push + pull every session |
| Push / Pull | 3 | Squat, Bench, Deadlift, OHP | 5–6 | PPL → Upper/Lower → PPL A/B |
| 5×5 Strength | 3 | Squat, Bench, DL, OHP, Row | 3 | StrongLifts/Madcow A/B/C |
| Powerbuilding | 3 | Squat, Bench, Deadlift | 4–5 | Heavy compounds + hypertrophy |
| Bodybuilding | 4 | Squat, Bench, DL, OHP | 6–8 | Body-part splits, RPE accessories |
| Cardio Endurance | 3 | None | 2–3 | Steady/Interval/HIIT/Recovery |

Every focus defines sessions for each valid frequency from its minimum through 6. Cardio exercises use `defaultReps` as duration in minutes with `targetRPE` for intensity.

**Commit:** `feat: add focus template library for AI program generator`

---

#### Prompt 3 [Periodization Engine & Program Generation Service] — 2026-04-07
- Built `ProgramGenerationService.swift` — the core engine that takes a `ProgramGenerationInput` + `FocusTemplate` and outputs a fully populated `TrainingProgram`
- Added `ProgramGenerationInput` struct and `ProgramLevel` enum (`beginner`, `intermediate`, `advanced`)
- Implemented three periodization models:
  - **Beginner — Linear Progression**: 70%→90% 1RM at +2.5%/working week; deload every 4th week (same weight, ½ sets)
  - **Intermediate — DUP**: sessions rotate heavy/moderate/light intensity tiers; +1.5%/week per tier; deload every 4th week at 60% 1RM
  - **Advanced — Block Periodization**: hypertrophy (62–72%) → strength (75–85%) → peaking (88–95%) phases with deload weeks; phase layouts for 6/8/10/12-week durations
- Warmup set generation: 3 sets at 40/55/70% of working weight for primary/variation exercises with a %1RM target (skipped on deloads)
- Accessory rotation: seeded shuffle + cyclic week-to-week rotation; adjacent-week deduplication for `bodybuilding`/`generalFitness`; fixed accessories for `fiveByFive`
- Cardio duration encoded as `targetReps` (minutes), progressive at +3 min/working week
- ~~Known limitation: `ProgramSessionExercise` has no weight field~~ — resolved in subsequent bug fix: `prescribedWeight`/`prescribedWeightUnit` added and stamped at generation time

---

#### Prompt 5 [Program Review Screen] — 2026-04-07
- Replaced the placeholder "success" screen with a full `ProgramReviewView` embedded inside the existing `AIProgramGeneratorView` full-screen cover
- **Summary header**: editable program name (inline text field on pencil tap), level badge (color-coded), duration + frequency badges, periodization description, block phase breakdown string for advanced programs
- **Phase/week drill-down**: collapsible phase cards grouped by phase (Hypertrophy/Strength/Peaking/Deload for Block; Working Weeks/Deload Weeks for Linear and DUP), each expanding to show week rows, which expand to show session rows, which expand to show exercise rows
- **Exercise display**: warmup sets shown with orange dot + "Warmup" pill and lighter styling; working sets show `sets×reps @ weight unit (pct%)` for %1RM exercises, `sets×reps @ RPE X` for RPE exercises, `X min` for cardio
- **Editing**: tap any non-warmup exercise row to open `ExerciseEditSheet` — swap exercise name (opens `ReviewExercisePickerSheet` with search), edit sets/reps, edit % 1RM or RPE; trash button on each row for delete; "Add Exercise" button per session opens picker and creates a default 3×8 @ RPE 7 entry
- **Regenerate**: confirmation alert → deletes current program from context, re-generates with same inputs, replaces preview
- **Start Program**: saves `TrainingProgram` to SwiftData, inserts a new `ProgramRun` with `startDate = now`, dismisses sheet → run appears in Training Programs list
- AI-generated programs saved via "Start Program" appear in "Use Existing Program" with "AI Generated" label (already supported by existing `ProgramSource.aiGenerated` + `ProgramListRow`)
- New file: `SuggestMeSome/Views/ProgramReviewView.swift` — contains `ReviewPhaseGroup`, `ProgramReviewView`, `PhaseCardView`, `WeekRowView`, `SessionRowView`, `ExerciseRowView`, `ExerciseEditSheet`, `ReviewExercisePickerSheet`

---

#### Bug Fix — Prescribed weights stored at generation time — 2026-04-07
- **Root cause**: weight display relied on `ProgramGenerationInput.oneRepMaxes`, a transient struct never stored in the model — weights were unavailable after the generation closure
- **`ProgramSessionExercise`**: added `prescribedWeight: Double?` and `prescribedWeightUnit: String?`; SwiftData handles the lightweight migration automatically
- **`ProgramGenerationService`**: added `computePrescribedWeight(exerciseName:percentage1RM:oneRepMaxes:)` helper (rounds to nearest 5 lbs / 2.5 kg); `populateExercise` now receives `oneRepMaxes` and stamps both warmup (40/55/70%) and working set objects at creation time
- **`ProgramReviewView`** `exerciseDisplayText`: prefers stored `prescribedWeight` with fallback to runtime `oneRepMaxes` computation for programs generated before the fix; display format: `4×5 @ 165 lbs (83%)`
- **`ExerciseEditSheet`**: `save()` recomputes and updates `prescribedWeight` when the user edits the percentage
- **`TrainingProgramsTab`** `sessionPlannedDetail`: rewrote to read `prescribedWeight` directly — now shows full intensity info (`4×5 @ 165 lbs (83%)`) instead of `"N×M planned"`; warmup rows filtered out as primary entries, shown as `"3 warmup sets"` label

---

#### Bug Fix — Duplicate exercise rows collapsed into grouped display — 2026-04-07
- **Root cause**: generation correctly creates 3 warmup `ProgramSessionExercise` objects + 1 working set object per primary lift, but the UI displayed all 4 as separate flat rows (e.g. "Back Squat 1×5", "Back Squat 1×5", "Back Squat 1×5", "Back Squat 4×5")
- Added `ExerciseGroup` struct pairing a working set with its warmup siblings by exercise name
- Added `groupedExercises(from:)` function that groups consecutive same-name warmup rows under their working set
- Replaced flat `ForEach` in `SessionRowView` with new `GroupedExerciseRowView`: shows one row per exercise with a collapsible "🔥 N warmups" toggle that expands to show the 40/55/70% sub-rows

---

#### Bug Fix — Phase drill-down expansion state lost on re-render — 2026-04-07
- **Root cause**: `ReviewPhaseGroup.id` was `let id = UUID()` — a new random UUID on every struct creation; since `groups` is a computed property, any `@State` change (including tapping to expand) rebuilt all groups with new UUIDs, making `expandedPhaseIDs.contains(group.id)` always false — nothing could stay open
- Changed `ReviewPhaseGroup.id` from `UUID` to a deterministic `String` derived from the phase type (`"working"`, `"deload"`, `"hypertrophy"`, `"deload-5"`, etc.)
- Changed `expandedPhaseIDs` from `Set<UUID>` to `Set<String>` throughout

---

#### Prompt 4 [AI Program Generator Input UI] — 2026-04-07
- Added "Generate AI Program" button (teal) to the Training Programs tab alongside the existing blue and purple buttons; all three equally sized in one row
- Created `AIProgramGeneratorView.swift` — a full-screen sheet with a multi-step input flow:
  - **Screen 1 — Configure Program**: focus picker (11-option grid), experience level segmented control with periodization descriptions, duration picker (6/8/10/12 weeks), sessions/week picker (2–6) with greyed-out options below the selected focus's minimum frequency
  - **Screen 2 — Enter 1RMs**: pre-fills estimated 1RM from PR history using Epley formula (rounded to nearest 5 lbs / 2.5 kg), per-lift unit toggle, manual override text fields; skipped entirely for Cardio Endurance
  - **Success screen**: placeholder showing "Program Generated Successfully" and the program name
- All inputs persist via `@AppStorage` (keys: `generator.ai.*`) and are pre-selected on next open
- Calls `ProgramGenerationService.generateProgram()` with assembled `ProgramGenerationInput`

---

#### Prompt 6 [Variation Load Mapping for Prescribed Weights] — 2026-04-07
- Extended `TemplateExercise` with additive hidden programming metadata for load derivation: `loadSourceLift`, `loadMultiplier`, and optional `intensityStyle`
- Added a centralized variation load mapping table in `FocusTemplateLibrary` with source-lift + multiplier pairs; includes:
  - Pause Squat / Front Squat / Box Squat → Back Squats
  - Pause Bench Press / Close Grip Bench Press / Incline Bench / Incline Dumbbell Press / Floor Press → Bench Press
  - Romanian Deadlift / Deficit Deadlift / Block Pull → Deadlift
- Refactored `ProgramGenerationService.computePrescribedWeight`:
  - Uses direct 1RM when `exerciseName` exists in `input.oneRepMaxes`
  - Falls back to mapped source lift 1RM × `loadMultiplier` when direct 1RM is missing
  - Leaves `prescribedWeight` nil when neither direct nor mapped source 1RM is available
- Updated `ProgramReviewView` fallback display and `ExerciseEditSheet.save()` weight recomputation to use the same mapped source-lift resolution when exercise names are swapped
- Migration impact is lightweight and additive: no SwiftData schema change required for this phase

---

#### Prompt 7 [Anchor-Relative Periodization in ProgramGenerationService] — 2026-04-07
- Refactored `ProgramGenerationService` so `TemplateExercise.percentage1RM` is treated as each exercise's anchor intensity instead of a generic gate
- Updated level logic to keep periodization while preserving template intent:
  - **Beginner**: small weekly offsets around anchor %1RM on working weeks
  - **Intermediate (DUP)**: heavy/moderate/light adjustments are now relative to each exercise anchor
  - **Advanced (Block)**: hypertrophy/strength/peaking apply phase-specific adjustments relative to each exercise anchor
- Deload logic is now explicit in each level branch and easier to tune (`BeginnerTuning`, `IntermediateTuning`, `AdvancedTuning`)
- `%1RM` prescriptions still flow into stored `prescribedWeight`/`prescribedWeightUnit`, so Program Review and Training Programs displays remain intact
- RPE-based accessories keep their template-driven RPE intent (with level-specific adjustments where applicable), preserving bodybuilding/powerbuilding behavior
- Updated Program Review phase descriptors to describe anchor-relative intensity progression instead of fixed absolute percentage bands

---

#### Prompt 8 [Top Set + Backoff Programming Support] — 2026-04-07
- Added lightweight top-set/backoff programming metadata to `TemplateExercise`:
  - `topSetPrescription` (optional)
  - `backoffPrescription` (optional)
- Added default top/backoff profiles in `FocusTemplateLibrary` for main lifts and key variations (squat/bench/deadlift and major competition-style variants)
- Updated `ProgramGenerationService` to emit working-set blocks instead of a single working row when applicable:
  - top set row (optional)
  - backoff row(s) with load drop from top set
  - straight sets fallback when top/backoff is not appropriate
- Implemented behavior targets:
  - top set + load-dropped backoffs for strength-focused work
  - heavy top single/double handling with higher-rep backoff volume when base reps are very low
  - straight sets retained for beginner programs, bodybuilding focus, deload weeks, and high-rep work
- Warmup generation remains intact and now references the heaviest working percentage when top/backoff rows are present
- Extended `ProgramSessionExercise` with additive metadata (`workingSetStyle`, `backoffPercentageDrop`) to classify rows without breaking existing data
- Program Review UI now clearly distinguishes warmups vs. top set vs. backoff vs. straight sets, while preserving existing edit/start program flows

---

#### Prompt 9 [Weekly Volume Accounting + Fatigue-Aware Accessory Selection] — 2026-04-07
- Added `ProgramExerciseMetadataService.swift` with programming-specific metadata:
  - new weekly hard-set muscle buckets: `chest`, `upperBackLats`, `quads`, `hamstrings`, `glutes`, `shoulders`, `biceps`, `triceps`, `calves`, `abs`
  - per-exercise muscle contribution mapping (plus heuristic fallback for unknown exercises)
  - fatigue tiers (`high` / `medium` / `low`) with helper logic that elevates heavy `%1RM` / top-set / low-rep compounds
  - focus + level weekly target ranges and focus + level + frequency fatigue budgets
- Refactored `ProgramGenerationService` accessory logic:
  - replaced blind seeded rotation with deterministic, week-aware accessory selection
  - weekly baseline is computed from primary/variation work first
  - accessory picks now prioritize under-target muscle groups and penalize over-target volume
  - fatigue constraints now influence selection (session cap, weekly cap, adjacent-session cap)
  - deadlift-heavy sessions get tighter fatigue handling and stronger penalties on high-fatigue add-ons
  - variability is retained via recency/novelty weighting + seeded jitter, but volume balancing has priority
- Added debug-focused weekly reporting on `ProgramGenerationService`:
  - `weeklySummary(for:)` returns structured week/session hard-set + fatigue totals
  - `debugWeeklySummary(for:)` returns a readable text summary for diagnostics without changing visible UI
- Behavior impact by focus:
  - **Powerlifting focuses**: keeps accessory work support-oriented with lower weekly hypertrophy targets and tighter fatigue control
  - **Bodybuilding**: drives higher weekly set targets while preferring more recoverable accessory combinations
  - **Powerbuilding**: balances main-lift support and hypertrophy volume with moderate-to-high targets and capped systemic fatigue

---

#### Prompt 10 [Adaptive Foundation + Program Logic Review + Feature 4 Validation] — 2026-04-07
- Added additive generation-assumption scaffolding (no full autoregulation loop yet):
  - new metadata enums in `ProgramGenerationMetadata.swift` (`ProgramProgressionModel`, `ProgramProgressionPhase`, `ProgramTargetEffortType`)
  - `TrainingProgram` now stores generation logic flags: progression model, lift mapping usage, volume balancing usage, fatigue balancing usage, and top-set/backoff usage
  - `ProgramWeekTemplate` now stores `isDeloadWeek`, `progressionPhase`, and planned weekly fatigue
  - `ProgramSessionTemplate` now stores planned session fatigue
  - `ProgramSessionExercise` now stores assumption fields: base lift used, effective 1RM used, mapped-lift flag, progression phase, estimated fatigue score, target effort type, optional target RIR, and top/backoff grouping id
- Added explicit future comparison anchors for completed workouts:
  - `ExerciseEntry` now snapshots source prescription metadata (`sourceProgramSessionExerciseID`, prescribed sets/reps/%/RPE/RIR/weight/style/effort type)
  - new `ProgramOutcomeComparisonService.swift` with `buildComparison(for:)` and TODO markers for:
    - reactive deloads
    - performance-based progression
    - adherence scoring
    - next-week adjustments
- Generator behavior hardening:
  - generation now records the resolved session frequency on `TrainingProgram` (instead of trusting raw requested frequency when snapping to template-supported frequencies)
  - deterministic generation helper added for validation (`generateProgram(..., shuffleSeed:)`)
- `ProgramReviewView` upgraded for explainability while preserving existing phase/week/session expand-collapse behavior:
  - compact `Program Logic` section added near the summary header (progression model, lift mapping, volume balancing, fatigue balancing, top set + backoff)
  - optional compact week-level summary rows added under expanded weeks (weekly fatigue + hard-set chips by muscle group)
  - warmup/grouped lift logic extracted to `ProgramReviewGrouping.swift` for shared usage and regression validation
- Added Feature 4 validation coverage in `Feature4GeneratorValidationTests.swift`:
  - verifies week/session shape across all focuses
  - verifies minimum-frequency resolution
  - verifies mapped variation weight derivation when source 1RMs exist
  - verifies top-set/backoff ordering
  - verifies non-negative volume accounting + fatigue budget guardrails
  - verifies expected deload week placement
  - verifies review grouping stability for warmups/grouped lifts
- Implementation note:
  - this prompt intentionally lays adaptive architecture groundwork and validation safety nets without shipping reactive progression/autoregulation decisions yet

---

#### Prompt 11 [Program Preview Info Toggle + Default-Clean View] — 2026-04-07
- Reduced Program Review UI clutter by adding a compact `Show Additional Info` toggle in the summary header (default: off)
- Additional info is now hidden by default and only appears when toggled on:
  - Program Logic card (progression model + generation logic flags)
  - Week-level fatigue chip in week headers
  - Weekly hard-set summary chips under expanded weeks
- Existing phase/week/session expand-collapse behavior and edit/start flows remain unchanged

---

#### Prompt 12 [Powerlifting + Full Body Focus Expansion] — 2026-04-07
- Added a new `powerlifting` focus to the AI program generator and increased the documented focus count from 10 to 11
- Rebuilt the `fullBody` template so every session includes lower-body work, a push, and a pull, with accessories chosen to fill posterior chain, arm, calf, and core gaps while staying time-efficient
- Added a new `powerlifting` template family centered on SBD specificity:
  - competition squat and bench exposures appear multiple times per week
  - deadlift frequency is kept lower and paired with lower-fatigue secondary work
  - accessory pools bias upper back, triceps, hamstrings, and trunk support
- Extended `ProgramExerciseMetadataService` with a dedicated `fullBody` archetype and explicit `powerlifting` routing so weekly hard-set targets, fatigue budgets, and level-scaling differ from generic fitness templates
- Expanded Feature 4 validation coverage:
  - powerlifting template tests now verify high squat/bench/deadlift exposure across supported frequencies
  - generated full-body programs now verify each workout includes lower, push, and pull work

**Commit:** `feat: add powerlifting focus and upgrade full body generation`

---

#### Prompt 13 [Program Workout Entry Grouping Fix] — 2026-04-07
- Fixed program-driven workout prefill in `WorkoutView` so generated session rows no longer create duplicate `ExerciseEntry` cards for the same lift
- Root cause: the prefill path mapped each `ProgramSessionExercise` row 1:1 into a `DraftExerciseEntry`, so warmup/top/backoff rows became separate cards (e.g., `Back Squat 1x10`, `Back Squat 1x10`, `Back Squat 4x10`)
- Added grouping logic in `WorkoutView`:
  - groups by shared `topBackoffGroupID` when present
  - otherwise groups contiguous rows with the same `exerciseName`
- Each grouped exercise now creates one `DraftExerciseEntry` with consolidated `DraftSet` rows beneath it, preserving:
  - warmup flags
  - prescribed reps/weights
  - set ordering
- Cardio handling remains supported in the same flow and continues to build a single cardio entry with duration fields

**Commit:** `fix: group generated program rows into single workout exercise entries`

---

### Feature 5 — Home Dashboard

**Status:** Complete

---

#### Prompt 1 [Home Dashboard Tab + Quick Stats] — 2026-04-07

- **Tab restructure:** Added "Home" tab (house.fill, tag 0) as the first tab in `ContentView`. Workouts shifted to tag 1, Training Programs to tag 2. App opens to Home by default.
- **DashboardView:** New view at `SuggestMeSome/Views/DashboardView.swift` wrapped in its own `NavigationStack` with a large "Home" title.
- **Start Workout button:** Prominent full-width blue button that presents a `.confirmationDialog` with three options:
  - "Start Empty Workout" — navigates to `WorkoutView()` via `navigationDestination`
  - "SuggestMeSome" — opens `GeneratorSheetRootView` sheet (same flow as Workouts tab)
  - "Program Workout" — opens `CompleteProgramWorkoutSheet` (only shown when at least one active `ProgramRun` exists)
- **Time window selector:** Segmented `Picker` with options 4W / 3M / 1Y / All, backed by `DashboardTimeWindow` enum. Default: 4W. Each case exposes `startDate: Date?` (nil for All).
- **Quick stats bar:** Four `StatCard` tiles in a full-width `HStack`, all filtered by time window except Streak:
  1. **Workouts** — count of `Workout` records in window (`figure.strengthtraining.traditional`)
  2. **Time Trained** — sum of `durationSeconds` displayed as "Xh Ym" (`clock.fill`)
  3. **PRs Hit** — count of `SetEntry` where `isPR == true` across workouts in window (`star.fill`, yellow)
  4. **Streak** — consecutive Mon–Sun weeks going backwards from current week with at least one workout, ignores time window (`flame.fill`, orange), displayed as "Xwk"
- **Placeholder sections:** Rounded-rectangle placeholders for PR Feed, Strength Chart, Volume Trend, and Recent Workouts so layout is testable end-to-end.
- **New file:** `SuggestMeSome/Views/DashboardView.swift`
- **Edited file:** `SuggestMeSome/ContentView.swift`

**Commit:** `feat: add home dashboard tab with quick stats and start workout flow`

---

#### Prompt 2 [PR Feed + Strength Trends Chart] — 2026-04-07

- **Recent PRs Feed:** Replaces the "PR Feed" placeholder. Shows the 5 most recent `PersonalRecord` entries (sorted by `dateAchieved` descending, always unfiltered by time window). Each row displays exercise name + rep count, date, current PR weight, and a delta badge:
  - **"+X lbs/kg" in green** — computed by scanning all `SetEntry` records for that exercise+repCount in workouts _before_ the PR date, taking the previous best weight and subtracting from the PR weight.
  - **"First PR" badge in blue** — shown when no prior history exists for that exercise+repCount.
  - "See All" link navigates to the existing `PersonalRecordsView`.
- **Strength Trends Chart:** Replaces the "Strength Chart" placeholder using Swift Charts (`import Charts`).
  - **Lift pill selector:** Horizontal scroll row of capsule pills for Bench Press, Squat, Deadlift, Overhead Press. Max 3 active at once. Each pill has a fixed color (blue, green, orange, purple). Active = filled, inactive = outlined.
  - **Line chart:** One `LineMark` + `PointMark` series per active exercise. X axis = date filtered by time window. Y axis = estimated 1RM in lbs (auto-scaled). Uses `.catmullRom` interpolation.
  - **e1RM formula (Epley):** `weight × (1 + reps / 30.0)`. Returns `weight` unchanged for single-rep sets. One data point per workout = the best e1RM across all sets of that exercise in the session.
  - Exercises with fewer than 2 data points in the selected window are excluded from the chart; a "Not enough data for: …" caption is shown below when applicable.
  - If all active lifts lack sufficient data, the chart area shows a placeholder card instead.
- **New file:** `SuggestMeSome/Services/StrengthAnalytics.swift` — contains `ChartPoint` struct and `StrengthAnalytics` enum with three static helpers: `estimatedOneRepMax`, `chartPoints`, `previousBest`.
- **Edited file:** `SuggestMeSome/Views/DashboardView.swift`

**Commit:** `feat: add PR feed and strength trends chart to dashboard`

---

#### Prompt 3 [Workout Frequency Chart + Active Program Progress] — 2026-04-07

- **Workout Frequency Chart:** Replaces the "Volume Trend" placeholder using Swift Charts.
  - **Bar chart:** One `BarMark` per calendar Mon–Sun week in the selected time window, labeled by the Monday date (e.g. "Mar 24"). X axis is time-based with `.weekOfYear` unit.
  - **Bar coloring:** Weeks meeting or exceeding the target → solid blue. Weeks below target → blue at 40% opacity.
  - **Target reference line:** Horizontal `RuleMark` (dashed, blue) labeled "Target". Value is the active program's `sessionsPerWeek` when a program is running; otherwise the average workouts/week across the visible window.
  - Monday alignment computed manually from weekday component to be locale-independent.
  - Empty window shows a placeholder card.
- **Active Program Progress:** Replaces the "Recent Workouts" placeholder.
  - **When a program is active:** Shows the most recently started `ProgramRun` (sorted by `startDate` descending).
    - **Circular progress ring:** Custom `Circle().trim` arc showing `completedSessions / totalSessions` (total = `lengthInWeeks × sessionsPerWeek`). Percentage displayed in center.
    - **Week label:** "Week X of Y" computed as `floor((now − startDate) / 7d) + 1`, capped at `lengthInWeeks`.
    - **This Week indicators:** Row of `checkmark.circle.fill` / `circle` icons for each session slot; filled count = workouts where `programWeekNumber == currentWeek` and `programRun.id` matches.
    - **Continue Program button:** Full-width blue button that opens `CompleteProgramWorkoutSheet` (same flow as the existing "Program Workout" option in the start dialog).
  - **When no program is active:** Muted card with "No active program" and a "Browse Programs" button that switches the root `TabView` to the Training Programs tab (tag 2).
- **Tab selection binding:** `ContentView` now owns `@State private var selectedTab = 0` and passes `$selectedTab` into `DashboardView`. The `TabView` uses `selection: $selectedTab` so DashboardView can programmatically switch tabs.
- **Edited files:** `SuggestMeSome/Views/DashboardView.swift`, `SuggestMeSome/ContentView.swift`

**Commit:** `feat: add workout frequency chart and active program progress to dashboard`

---

### [Volume by Muscle Group + Dashboard Polish] — 2026-04-07
- Added **Volume by Muscle Group** horizontal bar chart (Swift Charts) showing total working sets per muscle group in the selected time window
  - Set counting: iterates `filteredWorkouts → exerciseEntries` (skipping cardio), looks up each `exerciseName` in `allExercises` to resolve `muscleGroup.name`; exercises with no matching Exercise record are skipped
  - Fixed color map: Chest=blue, Back=green, Legs=orange, Shoulders=purple, Arms=red, Core=teal; unknown groups fallback to gray
  - Inline set-count annotations on each bar
- Improved **empty states** across all sections: encouraging copy for no PRs, no strength data, no frequency data, and no volume data
- Wrapped all three chart sections (Strength Trends, Workout Frequency, Volume by Muscle Group) in card containers (`secondarySystemBackground`, 16pt padding, 12pt corner radius)
- Polished **Start Workout button** with a blue linear gradient and a subtle drop shadow
- Standardized section spacing to 24pt; chart section headers now use consistent `HStack(icon + bold title)` pattern
- Added `@Query private var allExercises: [Exercise]` to `DashboardView` for muscle group lookups
- No new models; no new files
- **Known limitations:** exercises not present in the Exercise library (e.g. ad-hoc names) are silently skipped from volume totals

---

### Feature 6 — Adaptive Coaching Data Layer

**Status:** In Progress

---

#### Prompt 1 [Adaptive Coaching Persistence + Overlay Schema] — 2026-04-07

- Added new persisted adaptive-coaching models in `SuggestMeSome/Models/AdaptiveCoachingModels.swift`:
  - `ExercisePerformanceOutcome` — exercise-level prescribed-vs-actual snapshot + weighted scoring signal
  - `WeeklyTrainingAnalysis` — week rollup across both program and standalone workouts
  - `WeeklyVolumeMetric` — per-muscle weekly hard-set tracking linked to `WeeklyTrainingAnalysis`
  - `LiftPerformanceTrend` — lift-specific rolling trend and confidence state
  - `AdaptationProposal` — persisted recommendation object with lifecycle status + explainability text
  - `AppliedProgramOverlay` — non-destructive applied adaptation layer targeting future weeks/sessions
  - `AppliedOverlayAdjustment` — concrete adjustment rows (load/volume/reps/variation/deload) inside an overlay
  - `AdaptationEventHistory` — timeline events for future user-facing adaptation explanations
- Added Feature 6 enums for adaptive state classification:
  - `PerformanceScore`, `FatigueStatus`, `LiftTrendStatus`
  - `ProposalType`, `ProposalStatus`, `AdjustmentReason`
  - `WorkoutSignalConfidence`, `WorkoutSignalSource`
  - `OverlayAdjustmentType`, `OverlayStatus`, `AdaptationEventType`
- Added non-persisted helper types for service-layer logic:
  - `AdaptiveSignalWeights` (default signal weighting constants)
  - `AnalysisWeekWindow` (date window helper)
- Registered all new Feature 6 models in `SuggestMeSomeApp.sharedSchema` so they are included in the SwiftData container
- Behavior and architecture notes:
  - standalone workouts are explicitly represented as lower-confidence signals via `WorkoutSignalSource` + `WorkoutSignalConfidence` + numeric `signalWeight`
  - adaptation application is persisted as overlays (`AppliedProgramOverlay` + `AppliedOverlayAdjustment`) rather than mutating original generated program templates
  - explainability groundwork is persisted through proposal text fields and `AdaptationEventHistory` snapshots
- Scope guardrails:
  - this prompt adds persisted data architecture only
  - no adaptive engine decision logic has been implemented yet

---

#### Prompt 2 [Session Outcome Inference + Outcome Persistence] — 2026-04-07

- Added `SuggestMeSome/SessionOutcomeInferenceService.swift` and integrated it into the existing workout save flow (`WorkoutView.saveWorkout`)
- On each workout save, the service now creates one `ExercisePerformanceOutcome` per non-cardio exercise entry with valid completed sets and persists it in SwiftData
- Program-linked workout behavior:
  - when prescription fields exist, outcomes are scored as prescribed-vs-actual using deterministic components:
    - completion ratio (completed sets vs prescribed sets when available)
    - top-set load delta vs prescribed load (when available)
    - top-set reps delta vs prescribed reps (when available)
  - percentage-based prescriptions are handled via prescribed load comparison (`prescribedWeight` / `prescribedWeightUnit`)
  - RPE/RIR-targeted prescriptions are handled conservatively (reduced score magnitude + audit note) until explicit RPE/RIR logging is added
  - top-set weighting is prioritized for powerlifting-oriented lift families (`squat`, `bench`, `deadlift`)
- Standalone workout behavior (and program entries without usable prescription targets):
  - infers outcome against a recency-weighted historical baseline from prior sessions
  - baseline uses exercise identity first, then mapped lift family support via canonical lift-key resolution (including variation source-lift mapping from `FocusTemplateLibrary`)
  - confidence and signal weight are intentionally lower than program-prescribed signals to avoid over-claiming precision
- Persisted outcome linkage and auditability:
  - each outcome links back to `Workout`, `ExerciseEntry`, optional `ProgramRun`, and program week/session numbers when available
  - stores `canonicalLiftKey`, signal source/confidence/weight, top-set snapshot (with e1RM in lbs for cross-unit consistency), performance score band, inferred fatigue status, and deterministic method notes
- Important implementation notes:
  - inference is deterministic and service-driven (no randomness; model structs remain logic-light)
  - existing PR detection and workout save behavior remain intact; outcome persistence is additive within the same save transaction

---

#### Prompt 3 [Weekly Analysis Engine + Lift Trend Updates] — 2026-04-07

- Added `SuggestMeSome/WeeklyTrainingAnalysisService.swift` and integrated it into workout save flow (`WorkoutView.saveWorkout`) after session outcome inference
- Weekly analysis now runs at the week level (not per workout decisioning):
  - for program runs, weeks are anchored to `ProgramRun.startDate` in 7-day blocks and are analyzed once the week is complete (all sessions done) or when the week boundary has passed
  - for standalone training, weeks are anchored to ISO calendar weeks (Monday–Sunday) and analyzed only after the week has ended
- Signal aggregation now persists `WeeklyTrainingAnalysis` rollups with:
  - blended outcome signals from both program and standalone workouts
  - program vs standalone signal weighting retained via stored outcome `signalWeight`
  - weighted weekly performance score, adherence score, observed/planned fatigue, weekly fatigue status
  - weekly completed hard sets and normalized weekly tonnage (lbs-based)
- Added weekly muscle-volume aggregation and persistence into `WeeklyVolumeMetric`:
  - completed hard sets by `ProgramVolumeMuscle`
  - weighted completed hard sets (confidence-aware)
  - planned hard sets for program weeks from the original program template
  - delta between completed and planned volume where available
- Added lift-family trend update pipeline in the same engine:
  - updates `LiftPerformanceTrend` per lift key using finalized weekly outcomes
  - tracks data-point counts, confidence, current/previous/rolling-best e1RM, 4-week change %, trend status, and fatigue status
  - includes top-set emphasis for main lifts through stored outcome signals
- Added weekly explainability event persistence via `AdaptationEventHistory` (`weeklyAnalysisFinalized`) including compact debug-style summaries (signals, fatigue, top sets, trend statuses)
- Double-counting safeguards:
  - program-week analysis deduplicates repeated session logs by keeping the latest workout per `programSessionNumber`
  - outcome attachment is upserted per week analysis to keep reruns deterministic and avoid duplicate rollup entries
- Standalone outside-program behavior:
  - standalone weeks that overlap any program run are skipped as standalone analyses so those signals are handled in the program-week scope

---

#### Prompt 4 [Adaptive Top-Set Load Progression Proposals] — 2026-04-07

- Added `SuggestMeSome/AdaptiveLoadProgressionService.swift` and integrated it into the weekly program analysis pipeline (`WeeklyTrainingAnalysisService.analyzeProgramWeek`)
- Weekly adaptation cadence is now enforced for load progression:
  - proposal generation runs only from finalized program-week analyses
  - proposals target the next program week (`currentWeek + 1`) and never mutate base templates
- Implemented deterministic per-lift decisioning for main lift families (`squat`, `bench`, `deadlift`) including close variations via lift-key mapping:
  - uses weekly top-set outcomes as the primary signal
  - blends recent top-set history and persisted lift trend context
  - includes fatigue-aware adjustments from inferred performance-only fatigue states
- Added progression behavior by decision state:
  - **ahead:** proposes controlled load increases
  - **onTarget:** maintains baseline Feature 4 progression (no load-change proposal, trend event persisted)
  - **behind:** proposes hold/reduction, or variation simplification when performance + fatigue indicate high strain
- Added prescription-style-aware scaling:
  - percentage-based prescriptions allow fuller deltas
  - RPE/RIR-informed prescriptions use more conservative deltas due inferred-effort uncertainty
- Added conservative, bounded week-to-week rules:
  - inferred beginner/intermediate/advanced policy from program metadata text
  - beginner changes are most conservative
  - all deltas quantized and capped to avoid large weekly swings
- Persisted output and explainability:
  - writes `AdaptationProposal` records (`increaseLoad`, `decreaseLoad`, `variationSwap`) as non-destructive overlay proposals
  - supersedes conflicting open proposals for the same run/lift/week to keep proposal state deterministic
  - writes `AdaptationEventHistory` entries for both proposal creation and maintain decisions with machine-auditable detail strings
- Scope note:
  - this prompt persists and manages adaptive load progression proposals only
  - no direct destructive mutation of `TrainingProgram` / `ProgramSessionExercise` occurs

---

#### Prompt 5 [Weekly Accessory Volume Adjustment Proposals] — 2026-04-07

- Added `SuggestMeSome/AdaptiveVolumeProgressionService.swift` and integrated it into weekly program analysis finalization (`WeeklyTrainingAnalysisService.analyzeProgramWeek`)
- Weekly volume adaptation now runs on finalized weeks and targets the next week only (`currentWeek + 1`)
- Decision inputs combine:
  - weekly hard-set volume by muscle from `WeeklyVolumeMetric`
  - recent muscle-level performance inferred from `ExercisePerformanceOutcome`
  - weekly/recent fatigue state for recoverability protection
  - existing Feature 4/4.5 volume targets via `ProgramExerciseMetadataService.weeklyVolumeTargets`
- Added profile-aware volume logic:
  - **Powerlifting:** lowest accessory aggressiveness; only limited support-muscle increases (e.g. upper back, triceps, abs, posterior chain) when clearly underdosed and recoverable
  - **Bodybuilding:** highest volume tolerance; prioritizes underdosed muscles for small increases when fatigue allows
  - **Powerbuilding:** blended logic between powerlifting specificity and hypertrophy volume needs
- Proposal behavior:
  - creates persisted `AdaptationProposal` records with type `increaseVolume` / `decreaseVolume`
  - all volume proposals are `pendingUserConfirmation` and `requiresUserConfirmation = true`
  - no auto-apply for volume (`autoApplyEligible = false`)
  - each proposal is scoped to a concrete future accessory row (`targetProgramSessionExerciseID`, `targetSessionNumber`, target week)
  - uses small set adjustments only (`proposedSetDelta = +1` or `-1`)
- Overlay and state management:
  - proposals remain non-destructive overlays; base program templates are unchanged
  - conflicting open volume proposals for the same run/week/muscle are superseded deterministically
  - `AdaptationEventHistory` proposal-created events are persisted with explicit reasons/details for future user-facing explainability
- Recoverability guardrails:
  - high/critical fatigue weeks bias toward reductions only
  - elevated fatigue dampens increases unless underdose is strong
  - per-week change count is capped by profile to avoid broad volume swings

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
