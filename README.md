# SuggestMeSome

SuggestMeSome is an iOS training companion for lifters who want the app to do
more than store completed workouts. It combines fast workout logging,
AI-guided session and program generation, readiness-aware daily coaching,
HealthKit-informed recovery signals, progress analytics, and adaptive
programming into one local SwiftUI + SwiftData experience.

---

## App Overview

Great workout apps make logging simple. Great training apps also connect the
plan, the workout, the feedback, and the next adjustment. SuggestMeSome is built
around that complete loop. A user can start from a blank session, generate a
goal-driven workout, run a structured multi-week program, log effort and
top-set feedback, review strength and volume trends, and receive explainable
coaching guidance without stitching together a tracker, spreadsheet, program
generator, and recovery app.

The product is designed around three questions lifters face every week:

- What should I do today?
- Am I actually progressing?
- What should change next?

What sets SuggestMeSome apart is that generated workouts, logged workouts,
program prescriptions, readiness check-ins, HealthKit recovery data, and
adaptive coaching all feed the same training system. The app does not treat AI
generation as a one-off randomizer. It uses duration, intensity, selected
muscle groups, cardio needs, active program state, fatigue status, readiness,
pending coaching proposals, and learned exercise preferences to shape
recommendations users can inspect, edit, and trust.

Key highlights:

- Fast set-by-set workout logging with timers, editable generated sessions,
  history, filtering, effort feedback, top-set RPE capture, and automatic
  personal record detection.
- AI-guided workout generation for strength, cardio, recovery, conditioning,
  and mixed sessions, with recommendations that can account for recent
  training, equipment constraints, fatigue, readiness, and active program
  context.
- A structured program generation engine that builds 6 to 12-week plans across
  multiple training focuses, with experience-based progression models,
  prescribed loading, top-set and backoff logic, anchor-relative
  periodization, weekly volume targets, fatigue-aware accessory selection, and
  deload handling.
- A Daily Coach surface that combines manual readiness check-ins, active
  program status, recent workout history, HealthKit recovery insights, pending
  proposals, confidence scoring, source attribution, and adherence rescue into
  a practical Today Plan.
- An adaptive coaching system that persists workout outcomes, rolls them into
  weekly analysis, tracks fatigue and lift performance trends, and generates
  explainable recommendations for load progression, volume changes,
  deload/downshift decisions, and exercise variation swaps.
- A non-destructive overlay model for coaching adjustments, so approved
  changes can affect future sessions while the original program remains
  auditable and intact.
- A dashboard layer that makes progress visible through PR feeds, estimated 1RM
  trends, workout frequency, muscle-group volume, active program progress,
  fatigue status, and lift-specific trend signals.
- Optional HealthKit integration for recovery summaries, workout import, and
  limited workout writeback, with the app remaining fully usable without Health
  access.
- Sync-ready and watch-ready architecture foundations, including stable
  transport payloads for future cloud sync and Apple Watch companion surfaces.
- On-device SwiftData persistence, keeping the core experience fast, local, and
  privacy-friendly.

In practical terms, SuggestMeSome is a workout tracker, program builder, daily
coach, and adaptive training engine in one product. Its core promise is not just
recording what happened in the gym, but helping the user decide what to do next
and why.

### What Makes SuggestMeSome Different

Most training apps pick a lane: a logger, a program library, a readiness
tracker, or an AI workout generator. SuggestMeSome is built on the belief
that these surfaces are only useful when they share the same state. Every
feature in the app writes into — and reads from — a single training system,
which is what allows the Daily Coach, the program engine, and the AI
generator to stay internally consistent instead of contradicting each other.

Four design principles shape the product:

1. **One source of truth.** Logged workouts, generated sessions, program
   prescriptions, readiness check-ins, HealthKit recovery, fatigue state,
   and coaching proposals all feed the same adaptive coaching data layer.
   There is no second brain to reconcile.

2. **Explainability over magic.** Every AI suggestion — a load bump, a
   volume change, a deload, an exercise swap, a Today Plan recommendation —
   ships with confidence scoring, source attribution, and the inputs that
   produced it. Users can inspect, edit, approve, or reject before anything
   affects their plan.

3. **Non-destructive adaptation.** Coaching adjustments apply as overlays
   on top of the original program. Approved changes shape future sessions
   while the prescribed plan remains auditable and intact, so lifters never
   lose the thread of what they were supposed to be doing.

4. **Local-first, privacy-friendly, offline-capable.** The full experience
   runs on-device through SwiftData. HealthKit, sync, and the Apple Watch
   companion are additive — the core loop never depends on them.

The result is a training companion that answers the three questions lifters
actually face each week — *What should I do today? Am I progressing? What
should change next?* — with reasoning the user can follow, trust, and
override. SuggestMeSome is not trying to replace the coach in a lifter's
head. It is trying to be the first training app that can explain itself.

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

**Status:** Complete

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

#### Prompt 6 [Fatigue Detection + Deload/Downshift Proposals] — 2026-04-07

- Added `SuggestMeSome/AdaptiveFatigueDeloadService.swift` and integrated it into weekly program analysis finalization (`WeeklyTrainingAnalysisService.analyzeProgramWeek`)
- Weekly fatigue evaluation now runs at program-week cadence only and uses training-performance signals only (v1 readiness inputs still excluded)
- Fatigue signal detection combines:
  - repeated behind-performance patterns over recent weeks
  - repeated top-set underperformance patterns
  - sustained high-effort exposure where prescribed targets exist (high RPE / low RIR rows)
  - week-over-week performance regression vs recent baseline
  - excessive weekly volume/fatigue exposure vs planned targets
  - lift-trend context (count of declining main lifts)
- Added localized-vs-global guardrail:
  - when misses are concentrated to one lift while global fatigue/volume signals remain manageable, global deload is suppressed to avoid overreactive behavior
- Added conservative trigger rules:
  - moderate fatigue accumulation -> downshift proposal (`decreaseLoad` + small set/intensity reduction)
  - higher-confidence broad fatigue accumulation -> deload proposal (`deload` with deload factor and downshift fields)
  - no trigger -> persisted fatigue check event for explainability with computed risk context
- Proposal persistence and trust controls:
  - deload/downshift proposals are persisted as `AdaptationProposal` and scoped to future week overlays (no base program mutation)
  - all fatigue-driven deload/downshift proposals require user confirmation (`pendingUserConfirmation`, `requiresUserConfirmation = true`, `autoApplyEligible = false`)
  - proposal detail text stores structured signal/risk reasoning for future UI explanation
  - conflicting open next-week progression proposals are superseded when broader fatigue actions are generated to prevent chaotic mixed directives
- Existing persisted fatigue fields remain the authoritative weekly state:
  - `WeeklyTrainingAnalysis.observedFatigueScore`
  - `WeeklyTrainingAnalysis.fatigueStatus`

---

#### Prompt 7 [Lift-Specific Trend Tracking] — 2026-04-07

- Added `SuggestMeSome/LiftTrendTrackingService.swift` and moved lift-trend computation into a dedicated service consumed by weekly analysis finalization
- Weekly trend updates now run through `LiftTrendTrackingService.updateTrends(for:context:)` from `WeeklyTrainingAnalysisService` for both:
  - finalized program-week analyses
  - finalized standalone-week analyses
- Added persisted weekly trend snapshots for explainability/audit:
  - new SwiftData model `LiftTrendSnapshot` in `AdaptiveCoachingModels.swift`
  - linked to both `LiftPerformanceTrend` and `WeeklyTrainingAnalysis`
  - registered in `SuggestMeSomeApp.sharedSchema`
- Trend scoring and classification behavior:
  - tracks canonical lift families (`squat`, `bench`, `deadlift`) plus secondary families (`overheadPress`, `row`) and any other observed mapped families
  - uses canonical lift keys from persisted outcomes, so mapped lift families matter more than exact exercise-name matching
  - blends program + standalone outcomes with confidence-aware weighting; program-linked signals retain higher influence
  - emphasizes top-set signals for main powerlifting lifts by increasing their contribution weight
  - classifies trend status with robust thresholds (`improving`, `stable` as stagnant-equivalent, `declining`, `volatile`, `insufficientData`)
- Robustness guardrails to avoid anomalous-overweight behavior:
  - collapses multiple same-workout signals for a lift family to one representative point
  - uses trimmed robust weighted averages for rolling/current/prior windows
  - applies volatility-aware confidence adjustments before final status assignment
- Persisted output now includes:
  - updated rolling state in `LiftPerformanceTrend` (confidence, current/baseline e1RM, 4-week change, fatigue, latest top set)
  - per-analysis `LiftTrendSnapshot` rows with weighted signal composition, change %, status, and explainability note text

---

#### Prompt 8 [Automatic Variation Swap Overlays] — 2026-04-07

- Added `SuggestMeSome/AdaptiveVariationSwapService.swift` and integrated it into weekly program analysis finalization (`WeeklyTrainingAnalysisService.analyzeProgramWeek`)
- Automatic swap behavior now runs at weekly cadence and only for future program weeks (no direct mutation of `TrainingProgram` / `ProgramSessionExercise`)
- Swap trigger logic combines:
  - lift-trend direction/confidence (`LiftPerformanceTrend`)
  - weekly + lift fatigue context (`WeeklyTrainingAnalysis.fatigueStatus`, trend fatigue)
  - recent outcome underperformance/top-set miss patterns
  - conservative plateau and recoverability heuristics
- Profile-aware prioritization:
  - **Powerlifting:** most conservative (max 1 swap/week, specificity-first replacements)
  - **Powerbuilding / Bodybuilding:** still conservative, but allows slightly broader variation choices
- Replacement selection uses the existing template/library ecosystem and continuity guards:
  - chooses from known lift-family variation pools (e.g., pause/close-grip/deficit/block/front variants)
  - requires load-mapping continuity (`FocusTemplateLibrary.loadMapping`) or direct competition-lift fallback
  - avoids unnecessary novelty by preferring recently unused alternatives
- Auto-application persistence:
  - writes `AdaptationProposal` as `variationSwap` with `proposalStatus = .autoApplied`
  - writes `AppliedProgramOverlay` + `AppliedOverlayAdjustment` (`adjustmentType = .variationSwap`) for target future week/session
  - writes `AdaptationEventHistory` entries (`overlayApplied`) with explanation details for future user-facing history
- Added `SuggestMeSome/ProgramOverlayResolutionService.swift` and wired `CompleteProgramWorkoutSheet` to resolve session exercises through overlays at runtime
  - active overlays are applied when preparing future session workouts
  - base program rows are cloned and adjusted in-memory, preserving non-destructive overlay architecture
  - variation swap resolution updates replacement exercise identity and mapped load metadata for continuity

---

#### Prompt 9 [User Confirmation Flow for Volume/Deload Proposals] — 2026-04-07

- Added `SuggestMeSome/Views/AdaptationProposalReviewView.swift`:
  - new iOS-native review screen for pending adaptive proposals that require confirmation
  - supports user decisions for:
    - volume increase/decrease proposals
    - deload/downshift proposals
  - each proposal card shows:
    - what changes (`changeSummary`)
    - why (`adjustmentReason` + detail text)
    - which future week/session is affected
  - decision actions:
    - **Approve** (applies overlay + confirms proposal)
    - **Reject** (rejects proposal)
    - defer by leaving the item pending
- Added `SuggestMeSome/AdaptationProposalConfirmationService.swift`:
  - central service for proposal decision handling (`approve` / `reject`)
  - persists proposal lifecycle updates:
    - `pendingUserConfirmation -> confirmed`
    - `pendingUserConfirmation -> rejected`
  - on approve:
    - creates/updates `AppliedProgramOverlay` tied to the proposal (non-destructive)
    - writes `AppliedOverlayAdjustment` entries for `volume`, `load`, or `deload` actions
    - writes/updates `AdaptationEventHistory` (`proposalConfirmed`, `overlayApplied`) and resolves pending user-action events
  - on reject:
    - marks proposal rejected and writes `proposalRejected` history event
- Extended `SuggestMeSome/ProgramOverlayResolutionService.swift`:
  - overlays now resolve more than variation swaps; runtime application now supports:
    - `volume` adjustments (`setDelta` / absolute sets)
    - `load` adjustments (load deltas + optional set trim)
    - `deload` adjustments (global load + set reduction)
    - `reps` adjustments (future-proof support)
  - `variationSwap` behavior remains unchanged
- Updated `SuggestMeSome/Views/TrainingProgramsTab.swift`:
  - each expanded program-run row now exposes an **Adaptive Proposals** navigation row with pending count
  - planned-session preview now resolves exercises through `ProgramOverlayResolutionService`, so approved overlays are reflected in future-session views without mutating base templates
- Behavior and trust notes:
  - volume and deload/downshift proposals stay user-confirmed before becoming active overlays
  - approved changes are layered as overlays and remain auditable via event history and proposal records
  - original generated program templates remain unchanged

---

#### Prompt 10 [Adaptation Explainability + History Surface] — 2026-04-07

- Added `SuggestMeSome/Views/AdaptationHistoryView.swift`:
  - compact, debug-friendly Feature 6 history screen scoped to a single `ProgramRun`
  - surfaces persisted adaptive data in one place:
    - recent `WeeklyTrainingAnalysis` rollups (including fatigue status)
    - latest `LiftTrendSnapshot` by lift family
    - `AdaptationProposal` lifecycle records (created, approved, rejected, auto-applied, superseded)
    - auto-applied variation swap proposals as a dedicated section
    - `AppliedProgramOverlay` records with effective week ranges and adjustment counts
    - `AdaptationEventHistory` timeline with reason badges and explanation text
  - includes a `Show Debug` toggle to separate user-facing summaries from raw internal detail strings and technical metadata
- Updated `SuggestMeSome/Views/TrainingProgramsTab.swift`:
  - added a new **Adaptation History** navigation row inside each expanded program run
  - row shows whether adaptation events exist for quick visibility
- Explainability/UX behavior notes:
  - event and proposal entries display friendly labels plus explicit reason text (`AdjustmentReason`)
  - raw explanation payloads (`detailText`, `explanation`) remain accessible in debug mode for auditability
  - overlay architecture is visible in UI (`AppliedProgramOverlay` + adjustment summaries) without mutating base program templates

---

#### Prompt 11 [Feature 6 Validation Coverage] — 2026-04-07

- Added `SuggestMeSomeTests/Feature6ValidationTests.swift` with serialized Swift Testing coverage for Feature 6 adaptive coaching persistence and behavior
- Validation coverage added for:
  - persisted adaptive model relationship graph (`ExercisePerformanceOutcome`, `WeeklyTrainingAnalysis`, trends, proposals, overlays, history)
  - session outcome inference for both program-linked and standalone workouts
  - weekly analysis generation with mixed signal sources and dedupe of repeated program-session logs
  - top-set-driven load progression proposal generation
  - weekly volume proposal generation requiring user confirmation
  - fatigue/deload proposal generation from repeated underperformance patterns
  - lift-family trend classification with combined program + standalone signal contributions
  - automatic variation swap overlay creation and non-destructive runtime overlay resolution
  - proposal approval/rejection lifecycle updates and overlay activation behavior
  - regression guard for baseline workout/program save flow while adaptive services run
- Added deterministic in-memory SwiftData fixture helpers inside the test suite to keep validations auditable and repeatable
- Important implementation note:
  - volume proposal validation fixture now uses `Lateral Raises` (exact metadata key) so shoulder-volume contributions resolve deterministically
- Test execution note:
  - `xcodebuild -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SuggestMeSomeTests/Feature6ValidationTests test` passes
  - full `SuggestMeSomeTests` run still reports an existing unrelated failure in `Feature4GeneratorValidationTests/volumeAndFatigueAccountingStayWithinSafeBounds()`

---

### [Feature 5 Dashboard Enhancement — 2026-04-07]
- Replaced single "Start Workout" button + confirmation dialog with three direct quick-action buttons (Empty / Suggest / Program) — Program is always visible and navigates to the Programs tab when no run is active
- Added AI Coaching Insights card surfacing `WeeklyTrainingAnalysis` fatigue status (color-coded Low → Critical), weekly performance vs. target, and adherence score — intelligence previously invisible to the user
- Added adaptive proposals banner: shows pending `AdaptationProposal` count with the top proposal's summary text and a one-tap link into `AdaptationProposalReviewView`
- Added pending proposal badge on the Program quick-start button so the count is always in view
- Added Lift Trend Badges row above the strength chart — pulls from `LiftPerformanceTrend` to display 4-week change % and trend status (improving / stable / declining / volatile) per tracked lift
- Active Program card moved above the time-window picker when a program is active; now shows live fatigue status and adherence % from the most recent `WeeklyTrainingAnalysis`, plus a shortcut brain button to open proposal review
- Active Program "browse" CTA remains at the bottom when no program is active
- No new models or files added — all new UI reads from Feature 6 persisted SwiftData models

### [Feature 6.5 — Safety Hardening] — 2026-04-10
- Scoped store recovery in `SuggestMeSomeApp` to only delete SwiftData SQLite files (`.sqlite`, `.sqlite-wal`, `.sqlite-shm`) instead of wiping the entire Application Support directory
- Renamed recovery helper to `deleteSwiftDataStoreFiles()` to reflect the narrowed scope
- Added an explicit `modelContext.save()` in `WorkoutView.saveWorkout()` immediately after all workout/entry/set insertions so the workout is durably persisted before any Feature 6 coaching services run
- Wrapped `SessionOutcomeInferenceService` and `WeeklyTrainingAnalysisService` calls in individual `do/catch` blocks so a failure in adaptive coaching never prevents a workout from being saved
- No new models or files added

### [Feature 6.5 — CanonicalLift Enum Refactor] — 2026-04-10
- Created `SuggestMeSome/Models/CanonicalLift.swift` — `CanonicalLift: String, CaseIterable` enum with four cases (`bench`, `squat`, `deadlift`, `overheadPress`), `displayName`, `variationNames`, and a `from(exerciseName:)` factory
- Replaced all scattered lift key string literals (`"bench"`, `"squat"`, `"deadlift"`, `"overheadPress"`) with `CanonicalLift.<case>.rawValue` or `.displayName` across seven service/view files: `AdaptiveLoadProgressionService`, `AdaptiveFatigueDeloadService`, `LiftTrendTrackingService`, `AdaptiveVariationSwapService`, `AdaptiveVolumeProgressionService`, `SessionOutcomeInferenceService`, `WeeklyTrainingAnalysisService`, `ProgramGenerationService`, and `DashboardView`
- No behavior changes — purely a string-constant consolidation

### [Feature 6.5 — Global Weight Unit Preference] — 2026-04-10
- Created `SuggestMeSome/Models/AppPreferences.swift` — `AppPreferences` enum with a single `static var defaultWeightUnit: WeightUnit` backed by UserDefaults key `"globalWeightUnit"`, defaulting to `.lbs`
- Added a "Preferences" section at the top of `SettingsView` with a segmented `Picker` bound to `@AppStorage("globalWeightUnit")` — changes take effect immediately for all new entries
- Replaced all hardcoded `.lbs` fallbacks in `WorkoutView` with `AppPreferences.defaultWeightUnit`: picker-created entries, generated-workout cardio entries, generated-workout strength unit fallback, and program-driven entry unit fallback
- Prescribed units (from program templates or prior PR lookup) still take priority; preference is only applied when no unit is already specified

### [Feature 6.5 — DashboardViewModel Extraction] — 2026-04-10
- Created `SuggestMeSome/ViewModels/DashboardViewModel.swift` — `@Observable final class DashboardViewModel` holding all navigation/preference state, input arrays synced from `@Query`, and every computed property previously inline in `DashboardView`
- Moved `WeekBucket` struct from `DashboardView` (was `fileprivate`) into the ViewModel file as an internal type so it can be returned from `workoutFrequencyBuckets` and iterated in the view
- `DashboardView` retains all `@Query` properties (SwiftData constraint); a single `@State private var viewModel = DashboardViewModel()` replaces eleven former `@State` properties
- `@Query` results are pushed into the ViewModel on `.onAppear` and via `.onChange(of:)` observers for each query array
- All view-body references updated to `viewModel.propertyName`; bindings use `$viewModel.property` via `@Observable`+`@State` Bindable projection (iOS 17+)
- No visual or behavioral changes — pure logic extraction

### [Feature 6.5 — Cleanup] — 2026-04-10
- Removed "Show Debug" / "Hide Debug" toolbar button and all `showDebugDetails`-gated blocks from `AdaptationHistoryView.swift`; event explanation always shows user-facing text with a 3-line limit
- Added inline comments above each migration call in `SuggestMeSomeApp.swift` annotating the schema version / feature each migration was introduced for
- Removed 4 stale `// TODO` comments from `ProgramOutcomeComparisonService.swift` (planned future features that are out of scope for the current build)
- `print(` statements in `WorkoutView.swift` catch blocks retained as intentional F6 error logging

### [Feature 6.5 — Focus-Specific Program Generation Rigor] — 2026-04-10

#### Prompt 1 [Focus-Specific Programming Metadata Scaffold] — 2026-04-10
- Added new focus-level programming metadata models in `ProgramGenerationMetadata.swift`, including `ProgramFocusProgrammingProfile` and supporting enums for adaptation goal, progression strategy family, weekly exposure priorities, top-set/backoff policy, deload style, recovery profile, and cardio programming metadata
- Added `ProgramFocusProgrammingProfileLibrary.profile(for:)` with explicit profile coverage for every `ProgramFocus`
- Extended the existing template system with centralized retrieval via `FocusTemplateLibrary.programmingProfile(for:)`
- Wired `ProgramGenerationService` to resolve focus programming profile at generation entry and route it through progression model selection, schedule building, periodization description, accessory load estimation, and top-set/backoff policy checks (compatibility scaffold; behavior intentionally preserved for Prompt 1)
- Added Feature 4 validation tests for profile resolution across all `ProgramFocus` values and for entry-point wiring via focus-policy-driven top/backoff behavior checks (`bodybuilding` disabled, `powerlifting` template-driven)
- **Commit:** `feat: add focus-specific programming metadata scaffold`

#### Prompt 2 [Focus-Specific Progression Strategy Refactor] — 2026-04-10
- Refactored `ProgramGenerationService` progression flow to resolve strategy in two stages: focus-level `ProgramProgressionStrategyFamily` first, then level-specific tuning inside that family
- Added explicit family-separated progression paths for maximal strength/specificity, mixed strength+hypertrophy, hypertrophy, balanced training, and cardio/endurance across progression model selection, weekly scheduling, phase labels, and parameter computation
- Reworked `computeParams` into family-specific helpers (`strengthSkillParams`, `mixedStrengthHypertrophyParams`, `hypertrophyParams`, `balancedTrainingParams`, `enduranceConditioningParams`) to keep branching readable and local
- Added test coverage validating that the same `ProgramLevel` now resolves different strategy families and progression models depending on focus
- Preserved generated-program persistence/data model behavior and kept template library/data storage wiring intact
- **Commit:** `feat: refactor generator to use focus-specific progression strategies`

#### Prompt 3 [Focus-Specific Volume and Fatigue Rule Split] — 2026-04-10
- Replaced coarse focus archetype collapsing in `ProgramExerciseMetadataService` with explicit per-`ProgramFocus` volume/fatigue profiles used by weekly target and fatigue budget resolution
- Defined distinct hard-set target ranges per focus to reflect programming intent, including:
  - tighter accessory pressure for max-lift and strength-specialization focuses
  - balanced strength/hypertrophy exposure for powerbuilding
  - higher hypertrophy-oriented volume ceilings for bodybuilding with recoverability-oriented fatigue caps
  - sustainable whole-body floors for general fitness and full-body, with tighter adjacent-session fatigue control for full-body
  - upper-body-biased targets with lower-body minimum floors for push/pull
  - lower-accessory-noise strength-biased ranges for fiveByFive
  - cardio-endurance special handling that zeros resistance-style hard-set targets to avoid distortion
- Updated fatigue budget profiles per focus with explicit weekly/session/adjacent scaling differences while preserving existing weekly summary and fatigue accounting integration
- Added Feature 4 validation tests for focus-specific volume target and fatigue budget resolution so each focus resolves distinct, defensible rules
- **Commit:** `feat: split generator volume and fatigue rules by focus`

#### Prompt 4 [Bodybuilding Generation Rigor Upgrade] — 2026-04-10
- Upgraded hypertrophy progression in `ProgramGenerationService` with bodybuilding-specific parameter logic that explicitly separates compound, stable-variation, and pump/isolation prescriptions for reps, set bounds, and progression behavior
- Added proximity-to-failure handling for bodybuilding sessions via `targetRIR` programming on hypertrophy work where appropriate, while retaining percentage-based loading anchors for key compounds
- Replaced blunt bodybuilding top-set exclusion with a focused `compoundOpener` policy in `ProgramGenerationMetadata`, allowing limited opener top/backoff use on suitable compound session openers while keeping bodybuilding predominantly straight-set
- Tightened bodybuilding accessory planning to reduce junk volume and session sprawl by:
  - capping accessory picks per session with explicit bodybuilding limits
  - rejecting low-value accessories that do not address weekly deficits or session priorities
  - biasing candidate scoring toward session-identity muscles (e.g., chest/triceps, back/biceps, quads, hamstrings/glutes)
- Added Feature 4 validation tests covering bodybuilding weekly frequency intent, anti-bloat/anti-underdose dosing bounds, and hypertrophy session identity protections
- **Commit:** `feat: upgrade bodybuilding program generation rigor`

#### Prompt 5 [Balanced Focus Movement-Coverage Rigor Upgrade] — 2026-04-10
- Added explicit movement-pattern metadata in `ProgramExerciseMetadataService` (`ProgramMovementPattern`) and centralized pattern mapping/heuristics for all generator exercises, including optional conditioning classification for cardio movements
- Added focus-specific weekly movement-coverage targets for `generalFitness`, `fullBody`, and `pushPull`, covering squat/knee-dominant, hinge, horizontal push, vertical push, horizontal pull, vertical pull, single-leg, trunk, and optional conditioning where appropriate
- Refactored accessory planning in `ProgramGenerationService` to track per-session pattern coverage and weekly pattern exposures, then score/reject candidates using movement-target gaps in addition to existing volume/fatigue constraints
- Strengthened focus identity guardrails in accessory selection:
  - `generalFitness`: balanced weekly coverage with sustainable accessory caps
  - `fullBody`: each session maintains lower + push + pull pattern identity with tighter accessory count
  - `pushPull`: upper-specialized session identity preserved while enforcing lower-body minimum effective weekly floor
- Added optional conditioning candidates to relevant `generalFitness` and `fullBody` template accessory pools so weekly work-capacity targets can be satisfied without bloating default session structure
- Added Feature 4 validation tests verifying weekly movement-pattern coverage and focus identity for `generalFitness`, `fullBody`, and `pushPull`
- **Commit:** `feat: strengthen balanced focus program generation logic`

#### Prompt 6 [Cardio Endurance Planner Overhaul] — 2026-04-10
- Upgraded cardio programming metadata in `ProgramGenerationMetadata.swift` with explicit endurance session rules (`ProgramCardioSessionRule`), effort-distribution targets (`ProgramCardioEffortBucket`), progression methods (`duration`, `intervalCount`, `intervalDensity`, `workBlockDuration`), and optional work/rest progression parameters
- Reworked cardio templates in `FocusTemplateLibrary` around explicit archetypes: `Easy Aerobic / Zone 2`, `Threshold / Tempo`, `Interval / VO2`, `Long Steady Session`, and `Recovery Session`, with frequency-specific weekly mixes that preserve endurance identity
- Replaced the prior global cardio minute ramp in `ProgramGenerationService` with session-type-aware prescription resolution that:
  - progresses easy and long sessions primarily by duration
  - progresses interval/threshold sessions via work/rest-aware logic and interval progression inputs
  - applies deload step-back scaling for duration and effort targets
  - stores cardio effort guidance as `targetRPE` while keeping existing UI-compatible cardio row shape (`targetSets == nil`, `targetReps == minutes`)
- Unified cardio fatigue estimation around session duration + effort instead of a single flat per-minute multiplier, keeping weekly summary/fatigue accounting coherent for cardio blocks
- Added Feature 4 generator tests validating cardio weekly intensity mix and archetype-specific progression behavior with deload step-backs
- **Commit:** `feat: overhaul cardio endurance program generation`

#### Prompt 7 [Generator Explainability + Whole-Program Validation] — 2026-04-10
- Added compact explainability reason-code metadata in `ProgramGenerationMetadata.swift` and persisted fields on generated entities: session-level reason (`ProgramSessionTemplate.explainabilityReason`) plus exercise-level purpose and accessory-selection reason (`ProgramSessionExercise.explainabilityPurpose`, `explainabilitySelectionReason`)
- Wired `ProgramGenerationService` to stamp explainability metadata during generation:
  - session reason assignment by focus strategy and session archetype (including cardio and deload handling)
  - exercise purpose assignment for specificity, volume fill, fatigue control, technique, recovery, and cardio quality/base intent
  - accessory selection reason assignment based on deficit fill, movement coverage, fatigue fit, session identity, and rotation pressure
- Extended review/debug visibility in `ProgramReviewView` (without UI redesign) by surfacing compact reason labels when `Show Additional Info` is enabled at session and exercise row levels
- Added backward-compatible initializers for updated model constructors to avoid breaking existing test/build call sites while keeping changes additive
- Expanded Feature 4 generator validation with new whole-program checks for explainability coverage, strength specificity/heavy exposure constraints, bodybuilding frequency+volume-floor identity, balanced-focus movement coverage, and cardio session-type/intensity explainability behavior
- **Commit:** `feat: add generator explainability and focus-specific validation`

#### Prompt 8 [Integration and Hardening Pass] — 2026-04-10
- Resolved stale step-numbering comments in `ProgramGenerationService.buildProgram` — comments had drifted to 1, 5, 3–4, 6, 4 across earlier refactors; renumbered sequentially 1–6 to match actual execution order
- Removed dead `|| (week.weekNumber % 4 == 0)` fallback from `ProgramReviewView.buildPhaseGroups`; `isDeloadWeek` is reliably stamped during generation for all focus and deload-style combinations, making the week-modulo condition incorrect for focuses with non-every-4th-week deload schedules
- Tightened `ProgramFocusProgrammingProfileLibrary`: `fiveByFive` previously shared an identical profile with `powerlifting`; updated `fiveByFive` to `recoveryProfile: .conservative` and added `.verticalPush` to `weeklyExposurePriorities` to reflect its deliberately low-volume, three-day-per-week identity built around Squat / Bench / OHP / Deadlift / Row
- Feature 6.5 README entries verified for consistent `#### Prompt N [Title] — YYYY-MM-DD` heading format; no heading syntax corrections were needed
- Residual risk: `volumeAndFatigueAccountingStayWithinSafeBounds` is a pre-existing failure noted in Feature 4 Prompt 11 validation output; this pass does not introduce new regressions to that test
- **Commit:** `feat: finalize focus-specific program generation overhaul`

---

### Feature 7 — Daily Coach

**Status:** Complete

A program-first daily coaching system that collects readiness check-ins, surfaces weekly reviews, and uses check-in data to personalize daily session suggestions.

---

#### Prompt 1 [Daily Coach Data Foundation] — 2026-04-10
- Added `WorkoutEffortFeedback` enum (`tooEasy`, `onTarget`, `tooHard`) — `Codable` + `RawRepresentable` via `String`
- Added `DailyCoachCheckIn` SwiftData model: `id`, `date`, `dayStart`, `sleepQuality`, `soreness`, `energy`, `stress`, `availableTimeMinutes`, `hasPainOrDiscomfort`, `painNotes?`, optional `programRun` relationship, `createdAt`, `updatedAt`
- Added `DailyCoachWeeklyReview` SwiftData model: `id`, `weekStart`, `weekEnd`, `isProgramWeek`, optional `programRun` relationship, `headline`, `winText`, `watchoutText`, `nextActionText`, `sourceWeeklyAnalysisIDText?`, `hasBeenSeen`, `createdAt`
- Added additive fields to `ExerciseEntry`: `effortFeedback: WorkoutEffortFeedback?` and `topSetRPE: Double?`
- Registered `DailyCoachCheckIn` and `DailyCoachWeeklyReview` in the shared SwiftData schema in `SuggestMeSomeApp`
- All changes are additive and backward-compatible; no existing behavior altered
- **Commit:** `feat: add daily coach data foundation`

#### Prompt 2 [Daily Coach First Tab Shell] — 2026-04-10
- Added `DailyCoachView.swift` at `Views/DailyCoach/DailyCoachView.swift` — a `NavigationStack`-based scroll view with five distinct sections
- Restructured `ContentView` tab order: Daily Coach (tag 0, `brain.head.profile`), Home (tag 1), Workouts (tag 2), Training Programs (tag 3); app opens to Daily Coach by default
- **Today's Training card**: when an active `ProgramRun` exists, shows program name, current week / total weeks / sessions-per-week, and latest fatigue status dot from `WeeklyTrainingAnalysis`; falls back to a friendly standalone state when no program is running
- **Readiness card** (placeholder): shows today's `DailyCoachCheckIn` stats (sleep, energy, soreness, stress) if one exists; otherwise shows a "not yet recorded" placeholder with a deferred-feature note
- **Coach Recommendation card** (placeholder): static text indicating the engine is coming in a future prompt
- **Pending Proposals row**: compact orange-tinted row showing the count of `AdaptationProposal` entries with `.pendingUserConfirmation` status; only rendered when at least one exists
- **Latest Weekly Review card**: renders the most recent `DailyCoachWeeklyReview` (date range, headline, win, watchout) with a "New" badge when `hasBeenSeen == false`; falls back to an empty state when no reviews exist
- All data is read via `@Query`; no writes or services introduced in this prompt
- Existing Home dashboard tab is fully preserved and functional at tag 1
- **Commit:** `feat: add daily coach first tab shell`

#### Prompt 3 [Daily Coach Readiness Check-In] — 2026-04-10
- Added `CheckInFormView.swift` at `Views/DailyCoach/CheckInFormView.swift` — a `NavigationStack`-wrapped `Form` sheet for creating and editing a daily readiness check-in
- Form fields: Sleep Quality, Energy, Soreness, Stress (each 1–5 via tappable `RatingChips`), Available Time (Picker with 30/45/60/75/90/120 min options), Pain/Discomfort toggle, and a conditional free-text pain notes field
- `RatingChips` is a private `HStack` of five buttons with color-coded selection (green→red) and `.plain` button style to avoid nested-button conflicts in `Form`
- Save logic: if `existingCheckIn` is non-nil, mutates the existing record and sets `updatedAt`; otherwise inserts a new `DailyCoachCheckIn` with `date` and `dayStart` set to `Calendar.current.startOfDay(for: Date())`; all 1–5 values are clamped before write
- Numeric fields clamped to 1–5 on save; `painNotes` written as `nil` when pain toggle is off or text is empty
- Updated `DailyCoachView`: `readinessCard` now shows a filled blue "Check In" button when no same-day check-in exists, and a text "Edit Check-In" link when one does; both trigger a `.sheet` presenting `CheckInFormView(existingCheckIn: todayCheckIn)` — passing the existing record automatically switches the form to edit mode
- Same-day check-in lookup uses `Calendar.current.startOfDay` on `$0.date` matching today, consistent with the existing `todayCheckIn` computed property
- No recommendation logic introduced; placeholder Coach Recommendation card unchanged
- **Commit:** `feat: add daily coach readiness check-in flow`

#### Prompt 4 [Daily Coach Recommendation Engine] — 2026-04-10
- Added `DailyCoachRecommendationTypes.swift` at `Models/DailyCoachRecommendationTypes.swift` — non-persisted value types: `DailySuggestionType` enum (7 cases: `runAsPlanned`, `trimAccessories`, `trimOneBackoffSet`, `reduceWorkingLoadsSlightly`, `suggestManualVariationSwap`, `standaloneRecoverySession`, `standaloneShortStrengthSession`), `StandaloneSessionType` enum (fullBody / upper / lower / push / pull / recovery / cardio), `ReadinessTier` enum (strong / neutral / low / unknown), `DailyCoachSuggestionItem` struct, `NextProgramSessionInfo` struct, `DailyCoachRecommendation` struct
- Added `DailyCoachRecommendationService.swift` at `Services/Adaptive/DailyCoachRecommendationService.swift` — deterministic, purely in-memory service; no SwiftData writes
- `generate(checkIn:activeRun:latestAnalysis:pendingProposalCount:recentWorkouts:)` routes to program path or standalone fallback; `computeReadinessTier(from:)` derives a composite score from sleep + energy + (6−soreness) + (6−stress)
- Program path: `detectNextSession` finds the first uncompleted (week, session) pair by scanning logged workouts; looks up `sessionName` from `ProgramWeekTemplate → ProgramSessionTemplate`
- Five-tier priority rule chain (program and standalone): (1) pain/discomfort — no auto-swap, manual review surfaced; (2) severe time constraint < 30 min — primary lift + top set only; (3) moderate time + elevated fatigue — trim accessories; (4) low readiness — trim one backoff set, optionally trim accessories; (5) neutral / strong readiness — run as planned with pending-proposal note if applicable
- Standalone fallback: `inferStandaloneSessionType` infers fullBody / upper / lower / recovery from hasPain, fatigueStatus, readinessTier, and recent-workout history; `standaloneSuggestions` generates matching suggestion text
- Updated `DailyCoachView`: replaced placeholder Coach Recommendation card with an expandable card; shows a readiness-tier badge (Strong / Solid / Low / No Check-In), compact summary, primary suggestion chip with icon and color, and a "More detail / Less detail" toggle revealing full explanation and secondary suggestions; pain flag icon shown when `hasPainOrDiscomfort` is true; `LiftPerformanceTrend` query added for future use
- Removed "Recommendation coming soon" placeholder text from `activeProgramSummary`
- All recommendation objects are ephemeral; nothing new is persisted
- **Commit:** `feat: add daily coach recommendation engine`

#### Prompt 6 [Effort Capture and Latest Session Summary] — 2026-04-10
- Added `effortFeedback: WorkoutEffortFeedback?` and `topSetRPE: Double?` fields to `DraftExerciseEntry` in `DraftWorkoutTypes.swift` so effort state is held in the draft before being saved
- Added `Hashable` conformance to `WorkoutEffortFeedback` enum to support SwiftUI `ForEach(id: \.self)` usage
- Added effort capture section to `ExerciseEntryCard` in `WorkoutView.swift`:
  - Three-button `Too Easy / On Target / Too Hard` row using a custom segmented button group (tappable to deselect); only shown when a strength entry has at least one non-warmup set
  - Secondary "Top-set RPE" toggle row that reveals a `+/-` stepper for 1–10 RPE in 0.5 increments; hidden by default with state cleared on collapse
  - New `RPEStepperField` private subview and `WorkoutEffortFeedback` UI extensions (`.label`, `.tintColor`) added to the file
- Updated `WorkoutView.saveWorkout` to copy `effortFeedback` and `topSetRPE` from each draft entry to the persisted `ExerciseEntry`; both fields stay `nil` for cardio entries
- Added `DailyCoachSessionSummaryService.swift` at `Services/Adaptive/DailyCoachSessionSummaryService.swift`:
  - Pure in-memory service; no SwiftData writes
  - `latestSummary(recentWorkouts:latestCheckIn:)` returns a `SessionSummary` value type with `summaryText`, `workoutDate`, `hasEffortData`, and per-band counts (`tooEasyCount`, `onTargetCount`, `tooHardCount`)
  - Summary text is deterministic from the effort distribution, with a special-case message when the session-day check-in flagged low readiness and effort still came out on target
  - Example outputs: "Last session was on target overall." · "Primary work skewed too hard." · "Session matched the readiness-based trim well."
- Added "Last Session" card to `DailyCoachView`:
  - Always rendered; shows workout date, summary sentence, and colored count badges per effort band
  - Falls back to "No sessions logged yet" when no workouts exist
  - No new models; reads from existing `@Query` workout data
- No new SwiftData schema changes; `effortFeedback` and `topSetRPE` were already added as additive fields in Prompt 1

#### Prompt 5 [Daily Coach Prepared Workout Drafts] — 2026-04-10
- Extracted `DraftSet` and `DraftExerciseEntry` from `WorkoutView.swift` into a new shared file `Models/DraftWorkoutTypes.swift` so they can be referenced outside the view layer
- Added `PreparedWorkoutDraft` struct (ephemeral: `entries: [DraftExerciseEntry]`, `changeDescriptions: [String]`, `adjustmentType: DailySuggestionType`) in `Services/Adaptive/DailyCoachWorkoutPreparationService.swift`
- Added `DailyCoachWorkoutPreparationService` (`@MainActor` struct) with a single `prepare(exercises:suggestionType:) -> PreparedWorkoutDraft` entry point; never mutates any `ProgramSessionExercise` or `TrainingProgram` object; no SwiftData writes; no overlay or proposal creation
- Supported adjustments: `trimAccessories` (removes 1–2 lowest-priority accessory groups using `explainabilityPurpose` and `explainabilitySelectionReason` metadata; falls back to last unlabelled group), `trimOneBackoffSet` (removes the last backoff row from the largest backoff block identified by `topBackoffGroupID`; falls back to trimming the last set of the primary block), `reduceWorkingLoadsSlightly` (reduces all non-warmup prescribed weights by ~5% in the draft sets), `suggestManualVariationSwap` (loads the session as-planned and surfaces the primary lift name in plain-English change notes for manual review)
- Updated `WorkoutView` to accept an optional `preparedDraft: [DraftExerciseEntry]?` parameter; when set, `onAppear` loads the draft directly and starts the timer, bypassing the normal `buildDraftEntries` path; `programWorkout` is still required for save metadata (programRun / weekNumber / sessionNumber)
- Updated `DailyCoachView`: added `@Environment(\.modelContext)`, workout launch state (`navigatingToWorkout`, `pendingProgramWorkout`, `pendingDraft`, `showingDraftReview`, `confirmedDraftLaunch`); added `sessionLaunchButtons` sub-view to the Coach Recommendation card showing **Start As Planned** and **Review Suggested Version** (the review button only appears when `primarySuggestion.type != .runAsPlanned`); buttons are visible only when a program user has an identified next session
- Added private `DraftReviewSheet`: a `NavigationStack`-wrapped sheet that lists each change description with a type-appropriate icon; footer note confirms changes are today-only; "Start Suggested Session" toolbar button calls `onConfirm` then dismisses; `onDismiss` uses the same delayed-navigation pattern as the existing workout flows
- Launch helpers `launchAsPlanned()` and `prepareReviewSheet()` call `ProgramOverlayResolutionService.resolvedExercises` to get the session exercises, then either navigate directly or show the review sheet
- Base `TrainingProgram` data is never written to; standalone users see no action buttons (no prepared-draft logic applies to non-program sessions)
- **Commit:** `feat: add daily coach prepared workout drafts`

#### Prompt 7 [Weekly Coach Review and Feature 7 Hardening] — 2026-04-10
- Added `DailyCoachWeeklyReviewService.swift` at `Services/Adaptive/DailyCoachWeeklyReviewService.swift`:
  - `generateOrUpdate(from:context:)` upserts one `DailyCoachWeeklyReview` per `WeeklyTrainingAnalysis` (keyed on `sourceWeeklyAnalysisIDText = analysis.id.uuidString`); re-runs update text fields but never reset `hasBeenSeen`
  - Program-week reviews derive: headline from fatigue/adherence tier, win from improving lift trend or best top-set outcome, watchout from critical/high fatigue or declining trend, next action from pending proposals count or trend status
  - Standalone-week reviews use session count and fatigue for all four text fields, with deliberately simpler and lower-confidence tone
  - All text assembly is deterministic string interpolation — no randomised or model-generated output
- Integrated `DailyCoachWeeklyReviewService.generateOrUpdate` at the end of both `analyzeProgramWeek` and `analyzeStandaloneWeek` in `WeeklyTrainingAnalysisService`; runs after all Feature 6 proposal services so trend snapshots and proposals are available for text generation
- Updated `DailyCoachView` Latest Weekly Review card: `.onAppear` marks `hasBeenSeen = true` on the latest review the first time the card is displayed, clearing the "New" badge without any explicit user action
- Added `Feature7ValidationTests.swift` (`SuggestMeSomeTests/Feature7ValidationTests.swift`):
  - Check-in create-vs-update: same-day mutation keeps one record; different-day creates two
  - Recommendation engine: neutral readiness → `.runAsPlanned`; low readiness → `.trimOneBackoffSet`/`.reduceWorkingLoadsSlightly`; <30 min available → `.trimAccessories`; pain flagged → `.suggestManualVariationSwap`; no active program → standalone session type returned
  - Readiness tier computation: strong composite → `.strong`; nil check-in → `.unknown`
  - Draft-only guard: `DailyCoachWorkoutPreparationService.prepare` returns an in-memory `PreparedWorkoutDraft`; no `ProgramSessionExercise` rows written to the store; base exercise objects are not mutated
  - Effort feedback: all three `WorkoutEffortFeedback` variants and `topSetRPE` persist correctly on `ExerciseEntry`
  - Weekly review upsert: two calls on the same analysis produce one record with stable text; `hasBeenSeen` survives a re-generate; two distinct analyses produce two independent reviews
  - Workout-save regression guard (two variants): workout saves cleanly when `DailyCoachCheckIn` and `DailyCoachWeeklyReview` data exist; full pipeline (outcome inference + weekly analysis + review generation) saves cleanly and preserves effort feedback on entries
- `DailyCoachWeeklyReview` schema was introduced in Prompt 1; no new migrations required
- **Commit:** `feat: complete daily coach weekly review and hardening`

### Feature 8 — HealthKit Integration + Watch Foundation

**Status:** Complete

Foundation work for HealthKit-powered recovery data import, workout import/export support, and watch-related expansion in later prompts.

---

#### Prompt 1 [HealthKit Foundation and Workout Source Metadata] — 2026-04-10
- Added HealthKit app capability wiring in project settings by assigning `SuggestMeSome/SuggestMeSome.entitlements` to the app target (`CODE_SIGN_ENTITLEMENTS`) and adding `com.apple.developer.healthkit = true`
- Added generated Info.plist usage descriptions for HealthKit read/write prompts:
  - `NSHealthShareUsageDescription`: reads Health data to improve recovery/coaching
  - `NSHealthUpdateUsageDescription`: writes simple workout summaries back to Health
- Added `HealthKitTypeCatalog` (`Services/HealthKit/HealthKitTypeCatalog.swift`) to centralize HealthKit object/sample types needed later:
  - read scope includes sleep analysis, resting heart rate, HRV (SDNN), active energy, step count, body mass, and workouts
  - write scope includes limited workout writeback (`HKWorkoutType`)
- Added new persisted SwiftData model `HealthKitDailySummary` with daily recovery fields:
  - `id`, `dayStart`, `sleepDurationSeconds`, `timeInBedSeconds`, `restingHeartRateBPM`, `heartRateVariabilityMS`, `activeEnergyKilocalories`, `stepCount`, `bodyMassKilograms`, `sourceUpdatedAt`, `createdAt`, `updatedAt`
- Added `WorkoutSourceType` enum with `loggedInApp` and `healthKitImported`
- Added additive `Workout` source/import/export metadata fields:
  - `sourceType` (default `.loggedInApp` for backward compatibility)
  - `sourceExternalIdentifier`, `sourceDisplayName`, `sourceImportedAt`
  - `healthKitExportedAt`, `healthKitWritebackIdentifier`
- Registered `HealthKitDailySummary` in the shared SwiftData schema (`SuggestMeSomeApp`)
- No HealthKit query/sync logic, UI, settings screen, or watch bridge logic was added in this prompt

#### Prompt 2 [Health Data Settings and Permissions] — 2026-04-10
- Added `HealthKitAuthorizationService` (`Services/HealthKit/HealthKitAuthorizationService.swift`) with explicit HealthKit permission flow methods:
  - checks HealthKit availability (`HKHealthStore.isHealthDataAvailable()`)
  - requests authorization for Feature 8 read/write scopes from `HealthKitTypeCatalog`
  - refreshes current authorization/request status for user-facing connection state
- Added new `HealthDataSettingsView` (`Views/Settings/HealthDataSettingsView.swift`) with required user-facing sections:
  - `Connection Status`, `Daily Coach Usage`, `Workout Sync`, `Data Read`, `Data Write`, `Privacy Notes`
  - explicit `Unavailable`, `Denied`, `Disconnected`, and `Connected` state messaging
  - connect/request button and manual refresh button for authorization status
  - last sync row backed by `@AppStorage("healthkit.lastSyncTimestamp")` (shows `No sync yet` when unset)
- Added app-level HealthKit toggles backed by `@AppStorage`:
  - `healthkit.enabled`
  - `healthkit.dailyCoachEnabled`
  - `healthkit.importWorkouts`
  - `healthkit.writeWorkouts`
  - plus request tracking key `healthkit.permissionsRequested`
- Added a new `Health Data` navigation entry in `SettingsView` so users can open the screen from the existing settings area
- Included explicit privacy-forward copy that the app remains fully usable without HealthKit and that data access is optional/user-controlled
- No HealthKit data sync/import/export execution was implemented in this prompt

#### Prompt 3 [HealthKit Recovery Sync and 90-Day Daily Summaries] — 2026-04-10
- Added `HealthKitRecoverySyncService` (`Services/HealthKit/HealthKitRecoverySyncService.swift`) to import and persist objective recovery data into `HealthKitDailySummary` for the last 90 local calendar days
- Implemented deterministic daily-window sync keyed by `dayStart` with explicit upsert behavior:
  - fetches existing summaries for the 90-day range
  - updates matching day rows in place
  - inserts missing day rows
  - stores unavailable metrics as `nil` instead of creating placeholders/duplicates
- Implemented per-metric HealthKit queries with simple unit conversions and daily aggregation rules:
  - sleep analysis category samples aggregated into `sleepDurationSeconds` and `timeInBedSeconds` (seconds), including cross-midnight overlap splitting by local day
  - resting heart rate stored as BPM (`count/min`)
  - HRV (SDNN) stored as milliseconds
  - active energy stored as kilocalories
  - step count stored as `Double` count
  - body mass stored as kilograms
- Added partial-permission resilience in the sync service:
  - unavailable/denied metric types are skipped without aborting full sync
  - the app remains usable when HealthKit is unavailable or incomplete
- Wired manual recovery sync into `HealthDataSettingsView` via `HealthDataSettingsViewModel.syncRecoverySummaries(context:)`:
  - added a `Sync Recovery Data (Last 90 Days)` button
  - added simple sync state UI (`syncing`, `success`, `failed`) with inline status text
  - updates `@AppStorage("healthkit.lastSyncTimestamp")` only when sync succeeds so "Last Sync" reflects successful imports

#### Prompt 4 [Daily Coach HealthKit Recovery Blend and Attribution] — 2026-04-10
- Added `HealthKitRecoveryInsightService` (`Services/HealthKit/HealthKitRecoveryInsightService.swift`) to compute a deterministic objective recovery insight from `HealthKitDailySummary` rows using a 21-day rolling baseline (minimum 10 prior samples per metric)
- Implemented explicit caution/good/neutral signal rules for:
  - sleep duration below baseline
  - HRV below baseline
  - resting heart rate above baseline
  - active energy above baseline
- Added non-persisted Daily Coach value types in `DailyCoachRecommendationTypes.swift`:
  - `ObjectiveRecoveryStatus` (`good` / `neutral` / `caution`)
  - `ObjectiveRecoveryInsight` (compact + detailed explainability text)
  - `DailyCoachRecommendationSource` (`Manual Check-In`, `Health Data`, `Training History`)
- Updated `DailyCoachRecommendationService` to accept optional `objectiveRecoveryInsight` and blend it lightly:
  - manual pain/discomfort remains absolute priority and override
  - when manual readiness is strong but objective recovery is caution, recommendation shifts only slightly conservative (trim one backoff set) instead of a hard rewrite
  - when readiness is neutral and objective recovery is caution, session stays as planned with conservative pacing guidance
  - when HealthKit is unavailable/disabled/missing baseline data, objective insight is `nil` and recommendation behavior follows prior logic
  - recommendation now includes explicit source attribution and explainability text describing manual, training-history, and Health data influence
- Updated `DailyCoachView`:
  - reads HealthKit Daily Coach flags (`healthkit.enabled`, `healthkit.dailyCoachEnabled`)
  - computes optional objective insight from local summaries and passes it into recommendation generation
  - renders an `Objective Recovery` compact row (status badge + summary) when insight is available
  - renders visible recommendation source attribution pills and expanded source-influence detail text
- Updated `Feature7ValidationTests` call sites for the additive `DailyCoachRecommendationService.generate(... objectiveRecoveryInsight:)` parameter

#### Prompt 5 [HealthKit Workout Import, Source Badges, and Limited Edits] — 2026-04-10
- Added `HealthKitWorkoutImportService` (`Services/HealthKit/HealthKitWorkoutImportService.swift`) that manually imports the last 90 days of `HKWorkout` samples and filters import scope to:
  - cardio activity types (explicit allowlist)
  - `Traditional Strength Training`
- Implemented conservative upsert behavior keyed by HealthKit workout UUID (`sourceExternalIdentifier`) so repeated syncs do not create duplicate history rows
- Imported rows are created as first-class `Workout` records with source metadata:
  - `sourceType = .healthKitImported`
  - `sourceExternalIdentifier`
  - `sourceDisplayName` (e.g. Apple Watch/Health app source label)
  - `sourceImportedAt`
  - additive imported activity metadata fields on `Workout`: `sourceWorkoutTypeIdentifier`, `sourceWorkoutTypeDisplayName`
- Import keeps representation honest for HealthKit data:
  - no fabricated set-by-set structure for imported `Traditional Strength Training`
  - imported workouts can exist with zero native exercise entries
- Updated history and detail UI for imported workouts:
  - source badge chips in workout rows and detail header (e.g. `HealthKit`, `Apple Watch`, or source label)
  - imported workout activity label shown in rows/details when available
  - avoids awkward imported `0 exercises` presentation in history rows
  - added imported summary card in `WorkoutDetailView` (source, activity type, import timestamp) plus a clear no-set-details message when applicable
- Added limited edit behavior for imported workouts in `WorkoutEditView`:
  - allows editing only date, calories, and notes
  - blocks full exercise/set structure editing for imported entries
  - preserves existing full edit flow for native app-logged workouts
- Wired manual workout import into Health Data settings:
  - new `Import Workouts (Last 90 Days)` action in `HealthDataSettingsView`
  - status feedback for importing/success/failure
  - sync timestamp updated on successful workout import
  - writeback remains explicitly not implemented

#### Prompt 6 [HealthKit Workout Writeback] — 2026-04-10
- Added `HealthKitWorkoutWriteService` (`Services/HealthKit/HealthKitWorkoutWriteService.swift`) as an isolated writeback service for limited `HKWorkout` summary export
- Implemented strict writeback eligibility gates:
  - workout must be app-native (`sourceType == .loggedInApp`)
  - `healthkit.enabled` and `healthkit.writeWorkouts` must both be enabled
  - local workout must not already have `healthKitExportedAt` / `healthKitWritebackIdentifier`
  - HealthKit workout write authorization must be `.sharingAuthorized`
- Mapped writeback workout activity types conservatively:
  - cardio-only workouts map to a best-effort cardio `HKWorkoutActivityType` via exercise-name keyword matching
  - all other workouts default to `Traditional Strength Training`
- Limited exported payload to this prompt’s scope:
  - workout type
  - start/end timing and duration
  - optional active energy (`caloriesBurned`) when present
  - no set-by-set export and no rich strength metadata export
- Wired writeback into `WorkoutView.saveWorkout()` as non-fatal asynchronous post-save behavior:
  - local workout save still happens first and remains durable even if writeback fails
  - writeback failures are logged and do not interrupt dismiss/normal save flow
  - successful writeback stores `healthKitWritebackIdentifier` and `healthKitExportedAt` on the local `Workout`
- Added lightweight source/writeback UI metadata in `WorkoutDetailView`:
  - source row (`Logged in SuggestMeSome` vs imported source)
  - app-native writeback status (`Not exported` or exported timestamp) and HealthKit ID when available
- Updated `HealthDataSettingsView` workout sync note to reflect that limited workout writeback is now active in this version

#### Prompt 7 [Watch Groundwork and Feature 8 Hardening] — 2026-04-10
- Added non-persisted shared watch foundation types in `Models/WatchCompanionTypes.swift`:
  - `WatchWorkoutLaunchPayload`
  - `WatchWorkoutProgressSnapshot`
  - `WatchCompanionStatus` (+ `WatchCompanionAvailability`)
- Added additive watch bridge seam in `Services/Watch/WatchCompanionBridge.swift`:
  - `WatchCompanionBridge` protocol for future launch/progress payload transport
  - `DefaultWatchCompanionBridge` iOS implementation that safely availability-guards `WatchConnectivity`, supports no-watch/no-companion states, and refreshes status without requiring a watch target
- Updated `HealthDataSettingsView` with a new `Apple Watch` section:
  - optional status surfacing (`Unavailable`, `Not Paired`, `Paired`, `Companion Installed`, `Reachable`)
  - status message + last-checked timestamp + manual refresh action
  - explicit future-facing copy: "Watch companion coming soon" (groundwork only, no shipped watch app)
- Hardened Feature 8 service seams for deterministic behavior and testability:
  - extracted daily-summary upsert seam in `HealthKitRecoverySyncService.upsertDailySummaries(...)` and routed sync through it
  - extracted imported-workout upsert seam in `HealthKitWorkoutImportService.upsertImportedWorkouts(...)` and routed import through it
  - added `WorkoutSaveHealthKitWritebackCoordinator` + `HealthKitWorkoutWriting` seam so writeback remains non-fatal and isolated from local workout persistence
  - added `Workout.allowsFullStructureEditing` and wired `WorkoutEditView` to this guard for imported-workout limited edit behavior
- Added `Feature8ValidationTests` (`SuggestMeSomeTests/Feature8ValidationTests.swift`) covering:
  - `HealthKitDailySummary` day-keyed upsert behavior
  - Daily Coach recommendation fallback when objective HealthKit insight is unavailable
  - Daily Coach recommendation blending path when objective HealthKit insight exists
  - imported workout dedupe/upsert by `sourceExternalIdentifier`
  - imported workout limited-edit guard behavior
  - writeback guard that imported workouts are not rewritten
  - regression guard that workout persistence remains intact when writeback fails/unavailable
- Verification run for this prompt:
  - `/compile` not available in shell; used `xcodebuild ... build` equivalent and fixed prompt-introduced compile issues
  - ran `xcodebuild ... test -only-testing:SuggestMeSomeTests/Feature8ValidationTests` successfully

---

### Feature 9 — Shared Draft Builder + Grouping Extraction

**Status:** Complete

Incremental internal refactor to remove duplicate program-session-to-draft conversion logic while preserving existing behavior in program and Daily Coach workout launch flows.

---

#### Prompt 1 [Shared Draft Builder + Grouping Extraction] — 2026-04-10
- Added `ProgramSessionRowGroupingService` (`SuggestMeSome/Services/Adaptive/ProgramSessionRowGroupingService.swift`) to centralize contiguous row grouping and top/backoff group coalescing for ordered `ProgramSessionExercise` rows
- Added `ProgramWorkoutDraftBuilder` (`SuggestMeSome/Services/Adaptive/ProgramWorkoutDraftBuilder.swift`) to centralize conversion from grouped program rows into `DraftExerciseEntry`:
  - shared cardio-row detection and duration mapping
  - shared set expansion + merged set numbering across grouped rows
  - shared prescribed metadata snapshot preservation on draft entries (`sourceProgramSessionExerciseID`, prescribed sets/reps/load/effort fields)
- Refactored `WorkoutView` to replace local `buildDraftEntries`/grouping helpers with `ProgramWorkoutDraftBuilder.buildEntries(...)`, preserving personal-record unit lookup behavior via a call-site unit provider closure
- Refactored `DailyCoachWorkoutPreparationService` to use the same shared builder for all prepared-draft generation paths and to use `ProgramSessionRowGroupingService` for accessory/backoff trim grouping decisions
- No intended behavior changes: prepared Daily Coach drafts, program workout prefill, cardio handling, and warmup/top/backoff grouping behavior remain aligned with prior logic

#### Prompt 2 [Workout Save Coordinator + Shared Query Layer] — 2026-04-10
- Added `WorkoutSaveCoordinator` (`SuggestMeSome/Services/WorkoutSaveCoordinator.swift`) to own the non-UI workout save pipeline end-to-end:
  - build persisted `Workout` / `ExerciseEntry` / `SetEntry` records from `DraftExerciseEntry`
  - evaluate and persist PR updates
  - perform durable initial save before non-fatal side effects
  - trigger non-fatal HealthKit writeback
  - trigger Feature 6 session outcome inference and weekly analysis
  - perform final save
  - run program completion check and close the run when expected workout count is reached
- Added `TrainingContextQueryService` (`SuggestMeSome/Services/TrainingContextQueryService.swift`) as a shared training-context query layer for reusable filters/lookups:
  - recent workouts
  - active program runs
  - run-scoped workout counts
  - program session completion checks
  - PR lookup and preferred unit resolution
  - pending user proposal filtering and adaptation event counts
- Refactored `WorkoutView` to delegate save orchestration to `WorkoutSaveCoordinator`, keeping the view focused on UI state and draft editing
- Migrated repeated in-memory query/filter logic in touched surfaces to the shared query layer:
  - `TrainingProgramsTab` / `ProgramRunRow` / `ProgramRunExpandableRow`
  - `ProgramWorkoutViews`
  - `DailyCoachView`
- Preserved existing behavior guarantees:
  - workout persistence remains durable even if HealthKit/adaptive paths fail
  - Feature 6 and Feature 8 side paths remain non-fatal to local save flow
  - program completion behavior remains intact

#### Prompt 3 [SuggestMeSome Generator Service Split] — 2026-04-10
- Refactored daily workout generation into composable generator-domain services under `Services/Adaptive`:
  - `SuggestMeSomeGenerationService` façade (request-driven orchestration)
  - `SuggestMeSomeExercisePoolBuilder` (custom/full-body pool assembly)
  - `SuggestMeSomeExerciseSelectionService` (time-budgeted strength/full-body selection)
  - `SuggestMeSomeTimeBudgetService` (intensity time-factor and effective exercise time)
  - `SuggestMeSomeWorkoutPrescriptionService` (rep/set/weight prescription)
  - `SuggestMeSomePersonalRecordLookupService` (PR lookup path)
  - `SuggestMeSomeEquipmentCompatibilityService` scaffold (pass-through filter for now)
- Added formal daily-generation request/config type `SuggestMeSomeGenerationRequest` with current fields (mode, duration, intensity, selected muscle groups/exercises) plus future-ready goal and equipment slots
- Kept existing visible generator behavior intact:
  - custom and full-body generation flows
  - existing rep/intensity and set prescription behavior
  - current PR-based suggested weight path
  - cardio remainder-time handling
- Updated `GeneratorViews` to call the new request-based façade directly with minimal UI-surface changes
- Reduced `WorkoutGeneratorService` to a thin compatibility adapter to preserve existing external call compatibility while removing the oversized single-file implementation

#### Prompt 4 [Recommendation-First SuggestMeSome Flow] — 2026-04-10
- Replaced the direct generate-preview flow with a staged generator pipeline:
  - Step 1: configure session inputs
  - Step 2: receive an intermediate session recommendation
  - Step 3: optionally build the workout from that recommendation and start it
- Added explicit per-generation input value types and UI wiring for:
  - mode (`Full Body`, `Upper`, `Lower`, `Push`, `Pull`, `Arms/Shoulders`, `Recovery`, `Conditioning`, `Surprise Me`)
  - goal (`strength`, `hypertrophy`, `general fitness`, `fat loss`, `recovery`, `conditioning`)
  - equipment profile (`Full Gym`, `Home Gym`, `Dumbbells Only`, `Barbell + Rack Only`, `Hotel Gym`, `Bodyweight Only`)
  - duration and intensity
- Added `SuggestMeSomeSessionRecommendationService` as the recommendation-stage seam:
  - resolves mode-to-generation request mapping
  - applies lightweight goal/mode intensity adjustments
  - returns recommendation metadata + concrete `SuggestMeSomeGenerationRequest` used by build step
- Introduced `SuggestMeSomeGeneratorFlowViewModel` to own step state, persisted last-used values, recommendation generation, workout build, and shuffle behavior
- Refactored generator UI from one large file into modular step/components:
  - root flow coordinator (`GeneratorViews`)
  - configuration and recommendation screens (`GeneratorStepViews`)
  - reusable input controls (`GeneratorInputComponents`)
  - build preview screen (`GeneratorBuildStepView`)
- Updated home/workout and dashboard launch points to open the new staged generator flow directly (removing the old type-selection dialog entry path)

#### Prompt 5 [Conflict-Aware SuggestMeSome Recommendation Engine] — 2026-04-10
- Replaced the simple recommendation seam with a new dedicated `SuggestMeSomeRecommendationService` that computes deterministic, structured recommendation objects before workout building
- Expanded recommendation output to include:
  - title + summary + rationale
  - resolved mode and goal
  - recommended movement priorities
  - candidate exercise families
  - candidate anchor lifts
  - buildability flag + optional concrete generation request
- Implemented lightweight conflict-awareness using recent training context:
  - blocks recently hard-exposed canonical lift families (bench/squat/deadlift/OHP) from immediate heavy re-selection windows
  - detects near-term muscle overlap from recent sessions and biases recommendation mode/goal toward recovery/conditioning when overlap is obvious
  - optionally checks active-program next-session context only to avoid redundant overlap, without driving standalone SuggestMeSome programming
- Kept the architecture lightweight and reusable:
  - no adaptive proposal/overlay mechanics reused
  - no week/block periodization introduced
  - recommendation stage remains a deterministic pre-build filter, not a second full program generator
- Updated generator recommendation UI to surface intentional explainability:
  - concise recommendation summary + rationale
  - visible movement priorities, candidate families, and anchor lifts
  - build button gating when recommendation is marked non-buildable
- Added focused validation in `Feature9RecommendationEngineValidationTests` covering deterministic surprise-mode resolution, heavy-lift conflict avoidance, program-overlap recovery biasing, and non-buildable short-duration behavior

#### Prompt 6 [Build Workout from Recommendation + Validation] — 2026-04-10
- Implemented real equipment-compatibility filtering in `SuggestMeSomeEquipmentCompatibilityService` — replaced the stub pass-through with a tag-based resolver that maps each exercise's name to required equipment tags (`barbell`, `rack`, `dumbbell`, `cable`, `machine`, `bodyweight`, `cardio`) and tests them against `SuggestMeSomeEquipmentProfile.availableTags`; explicit catalogs cover all seeded exercises plus keyword-based fallback for unknowns
- Added variation load fallback to `SuggestMeSomePersonalRecordLookupService` via a new `bestAvailableWeight(for:repCount:)` method with three-stage resolution: (1) direct PR, (2) `FocusTemplateLibrary.loadMapping` source-lift × multiplier (e.g. Front Squat → Back Squats PR × 0.85), (3) canonical family primary variation with conservative 0.90 multiplier — exercises like `Pause Bench Press`, `Front Squat`, and `Romanian Deadlift` now receive weight suggestions when the parent lift has a PR even if the variation itself does not
- Added goal-aware prescription to `SuggestMeSomeWorkoutPrescriptionService`:
  - recovery goal: no warmup sets, 2 working sets, 65% load factor
  - conditioning/fat-loss goal: no warmup sets, 3 working sets, 85% load factor
  - accessory and isolation exercises: always skip warmups regardless of goal
  - compound exercises with hypertrophy/strength/general-fitness goal: retain full 3-warmup + 4-working structure
  - ramping working-set percentages (85% → 100%) computed generically across all working set counts
- Added `sessionMode: SuggestMeSomeSessionMode?` field to `SuggestMeSomeGenerationRequest` (additive, nil-backward-compatible); `SuggestMeSomeRecommendationService` now stamps the resolved final mode on every request so the generation service can apply mode-specific shaping
- Updated `SuggestMeSomeGenerationService` to:
  - pass `request.goal` through to `prescribeStrengthExercise` so all modes receive goal-aware prescription
  - apply mode/goal-specific time-budget splits: conditioning mode allocates only 30% of session time to strength circuits (leaving cardio dominant), recovery mode allocates 55%, other modes use the full budget
  - propagate the real `equipmentProfile` to both strength and cardio pools so filtering is applied consistently across the full generation pipeline
- Added `Feature9SuggestMeSomeBuildValidationTests.swift` with 17 validation tests covering:
  - equipment filtering: bodyweightOnly excludes barbell/cable, dumbbellsOnly excludes barbell/cable, homeGym excludes cable/machine, fullGym and nil pass all exercises, cardio exercises respect profile
  - variation load fallback: FocusTemplateLibrary mapping resolves correctly, direct PR takes priority over mapping, canonical family fallback fires when no direct/mapped PR exists
  - goal-aware prescription: recovery goal produces no warmups, recovery produces fewer working sets, accessory exercises always skip warmups, compound + normal goal retains warmups
  - recommendation-to-workout conversion: buildable full-body request produces non-empty workout, recovery mode exercises have no warmup sets, conditioning mode includes a cardio exercise, conditioning mode allocates more time to cardio than strength
  - mode routing: push mode selects chest/shoulder muscle groups, lower mode selects legs, surprise-me resolution remains deterministic for identical inputs
  - conflict avoidance: blocked bench anchor lift does not appear in recommendation anchor lifts after recent hard exposure

---

#### Prompt 7 [SuggestMeSome Polish + Explainability Pass] — 2026-04-11

Polished the end-to-end SuggestMeSome experience for coherence, trust, and clarity without redesigning the architecture.

**Explainability additions:**
- Added `reasonChips: [String]` and `wasRedirected: Bool` to `SuggestMeSomeSessionRecommendation` — structured metadata powering a new chip row in the recommendation UI
- `buildReasonChips` in `SuggestMeSomeRecommendationService` builds compact per-factor chips: equipment profile, duration, intensity, blocked lift names, high-overlap indicator, mode-adjusted indicator, program-aware indicator
- Conflict and redirect chips styled in an orange tint to distinguish them from neutral context chips

**Recommendation step polish:**
- Reason chips row (horizontal scroll) surfaces the key factors that shaped the recommendation at a glance
- Session plan section replaces the three overlapping bullet sections (Movement Priorities, Exercise Families, Anchor Lifts) with a consolidated anchor-lifts chip row + up to 3 movement priorities
- Redirect notice (orange callout) shown when mode was adjusted away from the user's configured choice, with the full rationale inline
- Not-buildable state replaced with a named notice card ("Duration too short") with actionable copy instead of a disabled button
- Build CTA changed from "Build Workout" to "Build This Session"

**Summary and rationale copy rewrites:**
- Removed the robotic "Inputs: mode X, goal Y, equipment Z, intensity N." opening from `rationaleText`
- `summaryText` now provides mode-specific descriptive copy when no conflicts are present (e.g., "A balanced session covering all major muscle groups" for Full Body), and leads with human-readable conflict explanation when conflicts are present
- Fixed "Recovery · Recovery" and "Conditioning · Conditioning" title duplication — `recommendationTitle` now deduplicates when mode and goal labels match

**Build step polish:**
- Session identity header added above the exercise list — shows the recommendation title and a duration/intensity/exercise-count stat row
- Exercise role labels replace the generic exerciseType capsule ("compound" → "Main Lift" or "Supporting", "isolation" → "Isolation", "accessory" → "Accessory") — role color-coded (blue for main, orange for supporting)
- Empty state copy differentiated by mode: recovery mode gets a recovery-specific message; conditioning gets a conditioning-specific message; default falls back to a generic suggestion
- Start CTA changed from "Start This Workout" to "Start Session"

**Navigation titles:**
- "Step 1: Configure" → "Session Setup"
- "Step 2: Recommendation" → "Your Session"
- "Step 3: Build Workout" → "Session Preview"

**Validation:**
- Added `Feature9Prompt7PolishValidationTests.swift` with 9 focused tests covering:
  - reason chips always include equipment, duration, and intensity
  - reason chips include an "avoided" chip when a canonical lift is blocked
  - "Mode adjusted" chip appears when wasRedirected is true
  - `wasRedirected` is false with no conflict, true when mode changes
  - Recovery and Conditioning title deduplication
  - Summary is always descriptive and never starts with "Inputs:"
  - Rationale no longer starts with the old "Inputs:" prefix
- Updated `recentHardBenchExposureAvoidsHeavyBenchRecommendation` test to match new summary copy (checks for "Bench Press" presence rather than exact old phrase)

**Files created:**
- `SuggestMeSomeTests/Feature9Prompt7PolishValidationTests.swift`

**Files edited:**
- `SuggestMeSome/Services/Adaptive/SuggestMeSomeGenerationModels.swift`
- `SuggestMeSome/Services/Adaptive/SuggestMeSomeRecommendationService.swift`
- `SuggestMeSome/ViewModels/SuggestMeSomeGeneratorFlowViewModel.swift`
- `SuggestMeSome/Views/Generator/GeneratorStepViews.swift`
- `SuggestMeSome/Views/Generator/GeneratorBuildStepView.swift`
- `SuggestMeSomeTests/Feature9RecommendationEngineValidationTests.swift`

---

#### Prompt 8 [Equipment-Aware Substitution + Fallback Session Generation] — 2026-04-11

Extended the SuggestMeSome generation pipeline to handle equipment-constrained profiles gracefully: instead of silently dropping exercises, the engine now substitutes compatible alternatives and surfaces the adaptation to the user.

**Substitution service:**
- Added `SuggestMeSomeExerciseSubstitutionService` with a hand-curated substitution table covering ~35 exercises across all major movement patterns: horizontal push (bench variants), vertical push (OHP variants), horizontal pull, vertical pull, squat variants, hinge (deadlift variants), and isolation/accessory work
- `rankedSubstitutes(for:equipmentProfile:availableExercises:)` returns candidates that are (a) in the substitution table for the removed exercise, (b) compatible with the active equipment profile, and (c) present in the seeded exercise database — preventing phantom exercises from entering the pool
- `adaptationNote(removedCompoundCount:substitutionCount:canBuildSession:equipmentProfile:mode:goal:)` generates mode-aware adaptation copy per equipment profile (bodyweight-only, dumbbells-only, hotel gym, home gym, barbell/rack-only) describing what was swapped and why

**Generation pipeline integration:**
- `SuggestMeSomeGenerationService` now calls `applySubstitutions` after equipment filtering in `generateCustomWorkout`: identifies removed compound exercises, finds compatible substitutes from the same selected-muscle-group pool, and augments the filtered pool with them
- Per-exercise substitution notes tracked in a `[PersistentIdentifier: String]` dictionary and re-attached after prescription
- `generateFullBodyWorkout` detects filtered compound count and attaches an adaptation note when equipment constraints materially reduce available compound movements
- Full-Gym profiles skip substitution entirely (no overhead)

**Output model extensions:**
- `GeneratedExercise` gained `substitutionNote: String?` (present when the exercise replaced a preferred exercise due to equipment constraints)
- `GeneratedWorkout` gained `adaptationNote: String?` (present when the session shape was adapted due to equipment constraints)
- Both fields default to `nil` so all existing call sites remain unchanged

**UI surfaces:**
- `GeneratorBuildStepView` shows a purple adaptation banner at the top of the exercise list when `adaptationNote` is set — wand-and-stars icon, purple tint, concise explanation
- Per-exercise substitution labels rendered as a small purple caption below the exercise name in the strength card header

**Validation:**
- Added `Feature9Prompt8EquipmentSubstitutionTests.swift` with 14 tests:
  - Substitution table coverage: bench press → dumbbell bench; barbell row → dumbbell row; OHP → dumbbell press; squat → goblet squat; deadlift → Romanian deadlift; cable fly → dumbbell fly; lat pulldown → bodyweight/TRX row
  - Adaptation note tests: bodyweight-only note contains "bodyweight", dumbbells-only note contains "dumbbell", hotel gym note is non-nil, full gym returns nil note
  - End-to-end tests: no substitution note in full gym, substitution note present in dumbbell profile for bench-focused session, session is still buildable (non-empty exercises) after equipment filtering with substitution

**Files created:**
- `SuggestMeSome/Services/Adaptive/SuggestMeSomeExerciseSubstitutionService.swift`
- `SuggestMeSomeTests/Feature9Prompt8EquipmentSubstitutionTests.swift`

**Files edited:**
- `SuggestMeSome/Services/Adaptive/WorkoutGeneratorService.swift`
- `SuggestMeSome/Services/Adaptive/SuggestMeSomeGenerationService.swift`
- `SuggestMeSome/Views/Generator/GeneratorBuildStepView.swift`

---

#### Prompt 9 [Settings Tab Migration + New Settings] — 2026-04-11

Migrated the settings menu from a gear-icon push inside the Workouts tab into a dedicated first-class Settings tab (rightmost in the tab bar). Redesigned the settings screen to be cleaner and less bloated, and added four new user-configurable preferences.

**Navigation changes:**
- Added `SettingsTab` as the 5th tab in `ContentView` with a `gear` icon; removed the gear icon toolbar button from `WorkoutsTab`
- Appearance color scheme preference (`@AppStorage("appColorScheme")`) wired up to `.preferredColorScheme()` on the root `TabView` so the setting takes effect app-wide immediately

**New settings:**
- **Appearance** — System / Light / Dark segmented picker stored in `@AppStorage("appColorScheme")`
- **Rest Timer Default** — navigation-link picker (Off, 30 s, 1 min, 90 s, 2 min, 3 min, 5 min) stored in `@AppStorage("defaultRestTimerSeconds")`; defaults to 90 seconds
- **Preferred Training Days** — day-of-week multi-select stored as a bitmask integer in `@AppStorage("coachPreferredDays")`; the Daily Coach can read this preference to prioritise workout suggestions; defaults to Mon/Wed/Fri
- **Export Workout Data** — generates a CSV file (date, duration, exercise, muscle group, set, weight, unit, reps, PR) and surfaces it via `ShareLink`

**Settings screen structure:**
- Preferences section: Default Weight Unit + Appearance
- Workout section: Rest Timer Default + Preferred Training Days
- Quick Links: Personal Records, Health Data, Manage Exercises, Export Workout Data
- Data Management: Delete by Date Range, Delete All (unchanged functionality)
- Card-like footer row with app icon, version `1.0`, and "Created by Alex Yao in partnership with Claude"

**De-bloat — exercise library collapsed:**
- The inline muscle-group CRUD sections that previously appeared directly in the settings list are now behind a single "Manage Exercises" NavigationLink
- Extracted into `ManageExercisesView.swift` (all CRUD state, dialogs, and helpers unchanged)

**New files:**
- `SuggestMeSome/Views/Settings/SettingsTab.swift` — main settings tab, `CoachScheduleView`, `DeleteByRangeSheet`
- `SuggestMeSome/Views/Settings/ManageExercisesView.swift` — exercise library CRUD (extracted from old SettingsView)
- `SuggestMeSome/Views/Settings/DataExportView.swift` — CSV export with `ShareLink`

**Files modified:**
- `ContentView.swift` — added Settings tab, removed gear icon toolbar, wired appearance preference
- `SettingsView.swift` — cleared (superseded by the above three files)

---

### Feature 10 — Sync-Ready Architecture Foundation

**Status:** Complete

Additive sync architecture groundwork so persisted training/coaching entities can be mapped into stable transport payloads for future cloud sync and Apple Watch data exchange, without introducing backend/network behavior.

---

#### Prompt 1 [Sync-Ready Contracts, IDs, and Conflict Policy] — 2026-04-11

- Added additive sync metadata to key persisted entities:
  - `Workout`, `ExerciseEntry`, `SetEntry`, `PersonalRecord`
  - `TrainingProgram`, `ProgramRun`, `ProgramSessionExercise`
  - `DailyCoachCheckIn`, `DailyCoachWeeklyReview`
  - `AdaptationProposal`, `AppliedProgramOverlay`, `AppliedOverlayAdjustment`
  - `HealthKitDailySummary`
- New additive fields include `syncStableID`, `syncVersion`, and `syncLastModifiedAt`; `Workout` also gained `syncDeletedAt` for future tombstone propagation
- Added shared sync metadata helper layer in `SyncContracts/SyncMetadataSupport.swift`:
  - `SyncTrackableModel` protocol + helpers for stable ID fallback, metadata initialization, update marking, and tombstone marking
  - explicit model conformances for all Feature 10 sync-scope entities
- Added transport-safe DTO contracts in `SyncContracts/SyncPayloadContracts.swift`:
  - explicit versioned payloads for workout logs, programs/prescriptions, daily coach records, adaptation proposals/overlays, and HealthKit daily summaries
  - separate watch-ready envelope type (`SyncEnvelopeDTO`) so the same contracts can be reused later for watch communication without duplicate representations
- Added model↔DTO mapper layer in `SyncMappers/SyncContractMappers.swift`:
  - mapping functions for all core sync entities and nested workout/overlay structures
  - payloads are SwiftData-runtime independent and encode only transport-safe fields
- Added deterministic conflict policy layer in `ConflictResolution/SyncConflictResolutionPolicy.swift`:
  - workout merge policy with nested exercise/set reconciliation
  - same-day check-in conflict policy (lastModified/version deterministic tiebreak)
  - adaptation proposal decision-state merge policy
  - overlay activation conflict policy (single active overlay per scope, older conflicts superseded)
  - program run progress merge policy (start/end/completion reconciliation)
- Added repository seam layer for local + future remote coexistence:
  - `Repositories/SyncRepositoryProtocols.swift` defines workout/program/daily-coach/adaptive/health-summary sync protocols
  - `Repositories/LocalSyncRepository.swift` provides local-only SwiftData implementation with nested upsert behavior and workout tombstone support
- Updated key mutation paths to keep sync metadata current in existing flows:
  - `WorkoutSaveCoordinator` (workout initialization, PR updates, run completion)
  - `HealthKitRecoverySyncService` and `HealthKitWorkoutImportService` (upsert updates)
  - `CheckInFormView` same-day check-in updates
- Validation coverage added in `SuggestMeSomeTests/Feature10SyncFoundationValidationTests.swift`:
  - DTO mapping round-trip checks
  - stable identifier fallback/normalization checks
  - conflict policy behavior checks
  - local repository upsert + tombstone behavior checks
- Verification runs for this prompt:
  - `xcodebuild test ... -only-testing:SuggestMeSomeTests/Feature10SyncFoundationValidationTests` (pass)
  - broader regression slice:
    - `Feature7ValidationTests` (pass)
    - `Feature8ValidationTests` (pass)
    - `Feature9RecommendationEngineValidationTests` (pass)
  - `xcodebuild build ...` on simulator destination (pass)

#### Prompt 2 [Repository and Query Layer Performance Hardening] — 2026-04-11

- Added focused read/query repository layer in `Repositories/ReadQueryRepository.swift` to centralize high-value scoped reads and remove repeated fetch-all/filter logic:
  - bounded recent workout reads (`fetchLimit` + date-sort)
  - active run-scoped overlay lookups
  - run-scoped pending proposal lookups
  - run-scoped completed session key projections
  - adaptation history snapshots with bounded proposal/overlay/event windows
- Refactored performance-sensitive adaptive and context services to use narrower predicates and bounded fetches:
  - `WeeklyTrainingAnalysisService` now performs date-window and run-scoped fetches for program/standalone workouts and outcomes instead of broad full-table reads
  - `ProgramOverlayResolutionService` now resolves overlays through run-scoped repository reads
  - `TrainingContextQueryService` now computes completed workout/session context from run-scoped reads instead of global workout scans
  - `SuggestMeSomeRecommendationService` recent workout path now uses explicit fetch limits
  - `AdaptationProposalConfirmationService` event-history upserts now avoid brittle enum predicate patterns that caused compile-time/type-check failures
- Improved read-path architecture for program/adaptive UI surfaces by moving data assembly out of views:
  - `AdaptationHistoryView` now consumes repository-built snapshot data instead of broad multi-`@Query` arrays
  - `AdaptationProposalReviewView` now loads run-scoped pending proposals via a deterministic reload path
  - program workout views/tabs tightened broad workout queries to program-scoped rows where applicable
- Resolved app-root behavior issues discovered during audit while preserving launch flow behavior:
  - removed forced dark-mode override in `SuggestMeSomeApp` so appearance follows persisted user preference
  - introduced `AppAppearancePreferenceService` and routed `ContentView` appearance resolution through it
  - replaced fixed-delay navigation timing hacks in `ContentView`, `DashboardView`, and `DailyCoachView` with `DeferredNavigationService` deferred-launch helper
- Added focused, deterministic test coverage in `SuggestMeSomeTests/Feature10Prompt2RepositoryQueryHardeningTests.swift`:
  - repository/query correctness for bounded/scoped reads
  - adaptation history snapshot behavior
  - appearance preference resolver behavior
  - deferred navigation launch behavior
- Verification runs for this prompt:
  - `xcodebuild test ... -only-testing:SuggestMeSomeTests/Feature10Prompt2RepositoryQueryHardeningTests` (pass)
  - broader regression slice:
    - `Feature6ValidationTests` (pass)
    - `Feature7ValidationTests` (pass)
    - `Feature9RecommendationEngineValidationTests` (pass)
  - `xcodebuild build ...` on simulator destination (pass)

#### Prompt 3 [Program Generator Decomposition and Safety Refactor] — 2026-04-11

- Refactored `ProgramGenerationService` into a façade/orchestrator while extracting internal policy collaborators under `Services/Adaptive/ProgramGeneration/`:
  - `ProgramGenerationProgressionResolver` (strategy/model/phase resolution, parameter computation, top-set/backoff policy)
  - `ProgramGenerationWeekScheduleBuilder` (deload cadence and advanced phase sequencing)
  - `ProgramGenerationLoadPrescriptionResolver` (%1RM mapping + load rounding policy)
  - `ProgramGenerationAccessoryPlanner` (volume/fatigue-aware accessory selection and guardrails)
  - `ProgramGenerationMovementCoverageHelper` (focus-aware movement coverage rejection + bodybuilding session muscle priorities)
  - `ProgramGenerationCardioPlanner` (cardio session typing, progression, deload step-back, and fatigue-per-minute policy)
  - `ProgramGenerationExplainabilityStamper` (session/row explainability reason and purpose stamping)
  - `ProgramGenerationWeeklySummaryReporter` (weekly/session fatigue-hardset reporting + planned fatigue stamping)
  - `ProgramGenerationLoadEstimator` and shared policy types in `ProgramGenerationPolicyTypes.swift` to reduce hidden coupling between planner components
- Preserved existing generator output semantics and public API while improving maintainability/scalability of internal generation logic.
- Added focused Prompt 3 validation coverage in `SuggestMeSomeTests/Feature10Prompt3ProgramGeneratorDecompositionTests.swift`:
  - collaborator policy mapping checks (progression resolver + schedule builder)
  - mapped-load rounding behavior validation
  - movement-coverage rejection guard validation
  - cardio progression + deload step-back policy validation
  - five-focus safety matrix validation (`powerlifting`, `bodybuilding`, `powerbuilding`, `generalFitness`, `fullBody`) for fatigue guardrails, explainability continuity, and top-set/backoff presence expectations
- Verification runs for this prompt:
  - targeted:
    - `xcodebuild test -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SuggestMeSomeTests/Feature10Prompt3ProgramGeneratorDecompositionTests` (pass)
  - broader Feature 4 regression slice:
    - `xcodebuild test -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SuggestMeSomeTests/Feature4GeneratorValidationTests` (pass)
  - compile validation:
    - `xcodebuild build -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17'` (pass)

#### Prompt 4 [Adaptive Coaching Pipeline Decomposition and Query Hardening] — 2026-04-11

- Refactored `WeeklyTrainingAnalysisService` into a public façade/orchestrator while extracting week-analysis collaborators under `Services/Adaptive/WeeklyAnalysis/`:
  - `WeeklyAnalysisWeekDataLoader` (week-scoped data loading and query coordination)
  - `WeeklyAnalysisDedupeHelper` (workout/outcome dedupe)
  - `WeeklyAnalysisAdherenceScorer` (adherence scoring)
  - `WeeklyAnalysisFatigueEvaluator` (observed fatigue scoring + status inference)
  - `WeeklyAnalysisVolumeAggregator` (completed/planned volume aggregation)
  - `WeeklyAnalysisAggregateScorer` (weekly aggregate signal scoring)
  - `WeeklyAnalysisPersistenceCoordinator` (analysis upsert, metric upsert, outcome attachment, finalize)
  - `WeeklyAnalysisEventHistoryWriter` (weekly analysis history event upsert)
  - `WeeklyAnalysisProposalPipelineCoordinator` (proposal generation + Daily Coach weekly review orchestration)
  - shared staging contracts in `WeeklyAnalysisTypes.swift`
- Preserved existing adaptive trust model and non-destructive overlay behavior:
  - user-confirmation-required proposals remain confirmation-gated
  - conservative variation swaps continue auto-applying through overlays where already designed
  - HealthKit-influenced readiness behavior remains unchanged and manual readiness remains authoritative except existing pain/discomfort priority paths
- Hardened query boundaries by keeping run/week-scoped fetches centralized in the loader and narrowing weekly history event upsert lookup to analysis-scoped reads.
- Hardened workout-save durability around adaptive side effects in `WorkoutSaveCoordinator` by introducing non-fatal injectable side-effect closures with guarded execution while preserving default behavior.
- Added focused Prompt 4 validation coverage in `SuggestMeSomeTests/Feature10Prompt4AdaptivePipelineDecompositionTests.swift`:
  - weekly aggregation correctness
  - dedupe behavior
  - fatigue/adherence scoring continuity
  - proposal pipeline orchestration with five-focus validation emphasis (`powerlifting`, `bodybuilding`, `powerbuilding`, `generalFitness`, `fullBody`)
  - non-fatal workout-save side-effect durability
- Verification runs for this prompt:
  - targeted:
    - `xcodebuild test -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SuggestMeSomeTests/Feature10Prompt4AdaptivePipelineDecompositionTests` (pass)
  - broader regression slice:
    - `xcodebuild test -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SuggestMeSomeTests/Feature6ValidationTests -only-testing:SuggestMeSomeTests/Feature7ValidationTests -only-testing:SuggestMeSomeTests/Feature10Prompt2RepositoryQueryHardeningTests` (pass)
  - compile validation:
    - `xcodebuild build -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17'` (pass)

#### Prompt 5 [Coach-Aware SuggestMeSome Fusion] — 2026-04-12

- Fused SuggestMeSome recommendation and generation stage with the coaching engine and active program state, making the daily session generator context-aware across fatigue, readiness, overlays, pending proposals, HealthKit recovery, and exercise preferences.
- Added `SuggestMeSomeCoachContext` and supporting value types (`SuggestMeSomeCoachContextProposal`, `SuggestMeSomeExercisePreferences`) to `SuggestMeSomeGenerationModels.swift` — carries all coaching signals into the recommendation stage without touching any persisted models.
- Added `SuggestMeSomePreferenceLearnerService` — learns user exercise preference tendencies from workout history:
  - counts exercise appearances across a configurable recency window (default 30 workouts, threshold 3)
  - identifies frequently-used exercises (appear 3+ times in window)
  - identifies underused exercises (in history but absent from last 8 sessions)
  - each session counts at most once per exercise to prevent duplication inflation
- Added `SuggestMeSomeCoachContextLoader` — assembles a `SuggestMeSomeCoachContext` snapshot from SwiftData on demand:
  - latest fatigue status from most recent finalized `WeeklyTrainingAnalysis`
  - readiness tier from today's `DailyCoachCheckIn` via `DailyCoachRecommendationService.computeReadinessTier`
  - active overlay summaries (fetched + in-memory filtered to avoid SwiftData enum predicate limitations)
  - pending proposals (`.pendingUserConfirmation` or `.pendingAutoApply`, in-memory filtered, priority-sorted)
  - learned preferences from recent workout history via `SuggestMeSomePreferenceLearnerService`
- Extended `SuggestMeSomeRecommendationService.recommendSession` with optional `coachContext: SuggestMeSomeCoachContext? = nil` parameter (backward compatible; all existing call sites unaffected):
  - **Pain/discomfort priority** (unchanged + extended): pain flag now propagates through coach context, forces mode to `.recovery` and caps intensity at 1 regardless of all other signals
  - **Fatigue-aware intensity caps** (new): critical → 1, high → 2, elevated → 3; applied before conflict analysis
  - **Readiness tier cap** (new): `ReadinessTier.low` caps intensity at 3
  - **HealthKit medium-influence nudge** (new): `.caution` status nudges intensity down by 1 step; cannot override a tighter manual/fatigue cap
  - **Recovery bias from coach signals** (new): elevated/high/critical fatigue, low readiness tier, deload overlay keyword, and pending deload proposals all independently trigger recovery bias (additive to existing overlap/conflict/blocked-lift signals)
  - **Overlay-aware candidate families** (new): active overlays inject "Coach-approved overlay in effect" into candidate exercise families; pending variation swap proposals inject "Variation swap candidate (pending proposal)"
  - **Preference-aware anchor selection** (new): `preferenceAwareAnchorName` biases anchor lift selection toward the user's frequently-used variation of each canonical lift family
  - **Underused variety hint** (new): underused exercises trigger "Variety rotation available" in candidate families
  - **Coach context explainability chips** (new): eight new chips per signal factor (Pain override, Critical/High/Elevated fatigue, Low readiness, Overlay active, Deload proposed, HealthKit nudge, Preference-biased)
  - **Extended rationale text** (new): all coach context factors append specific, readable sentences to the recommendation rationale
  - **Extended summary text** (new): pain, fatigue, readiness, overlay, and HealthKit signals each inject explicit, user-facing sentences into the recommendation summary
- Updated `SuggestMeSomeGeneratorFlowViewModel.makeRecommendation` to load and pass `SuggestMeSomeCoachContext` via `SuggestMeSomeCoachContextLoader`; accepts optional `todayCheckIn` and `objectiveRecoveryInsight` parameters; the existing call site in `GeneratorViews.swift` remains unchanged (defaults to nil context for incremental adoption).
- Preserved all prior recommendation behavior when `coachContext` is nil — no regressions in existing test suites.
- Added focused Prompt 5 validation coverage in `SuggestMeSomeTests/Feature10Prompt5CoachAwareFusionTests.swift` (36 tests):
  - pain override forces recovery mode and intensity 1 regardless of other signals
  - pain beats critical fatigue for mode determination
  - critical/high/elevated fatigue intensity caps
  - manageable fatigue produces no restriction chips
  - elevated fatigue biases session toward recovery
  - low readiness tier caps at intensity 3; strong readiness produces no chip
  - deload overlay summary biases recovery; non-deload overlay chips but does not force recovery
  - pending deload proposal biases recovery; pending variation swap surfaces in candidate families
  - frequently-used variation preferred over default canonical anchor
  - preference-biased chip present with frequent exercises; absent without preferences
  - underused exercises produce "Variety rotation available" family
  - HealthKit caution nudges intensity down; good status adds no nudge chip; caution cannot override lower manual cap
  - rationale has content for all 8 session modes
  - baseline chips (equipment/duration/intensity) always present; coach chips never appear with nil context
  - coach context rationale is cumulative (at least as long as base rationale)
  - focus matrix quality: strength/push produces pressing anchors, hypertrophy/arms-shoulders produces accessory families, full body/general fitness produces compound families, strength/lower produces squat-deadlift anchors, recovery produces low-impact priorities
  - active program next-session conflict biases recovery with Program-aware chip
  - preference learner: empty input, frequency detection, threshold non-triggering, underused detection, once-per-session counting
  - nil context backward compatibility: no coach chips present
- Verification runs for this prompt:
  - targeted:
    - `xcodebuild test -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SuggestMeSomeTests/Feature10Prompt5CoachAwareFusionTests` (36/36 pass)
  - broader regression slice:
    - `Feature9RecommendationEngineValidationTests` (pass)
    - `Feature9SuggestMeSomeBuildValidationTests` (pass)
    - `Feature9Prompt7PolishValidationTests` (pass)
    - `Feature7ValidationTests` (pass)
    - `Feature10Prompt4AdaptivePipelineDecompositionTests` (pass)
    - Note: `Feature9Prompt8EquipmentSubstitutionTests/generatedWorkoutHasSubstitutionNoteWhenBarbellUnavailable` fails non-deterministically in parallel runs due to random exercise selection — pre-existing issue confirmed by reproducing on clean main before this prompt's changes
  - compile validation:
    - `xcodebuild build -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17'` (pass)

#### Prompt 6 [Today Plan Engine, Confidence, and Adherence Rescue] — 2026-04-12

- Introduced `TodayPlanEngine` — a single, surface-agnostic orchestration entry point that assembles a `TodayPlan` from all available coaching signals (check-in, active program, weekly analysis, HealthKit, pending proposals). Replaces the direct `DailyCoachRecommendationService.generate()` call in `DailyCoachView` with a single `TodayPlanEngine.buildPlan()` call.
- Added new value types in `Services/Adaptive/TodayPlanTypes.swift`:
  - `TodayPlanConfidence` — deterministic `.high` / `.medium` / `.low` confidence band
  - `TodayPlanSourceAttribution` — explicit per-source influence descriptions (manual readiness, HealthKit, program prescription, adaptive overlays, training history)
  - `AdherenceStatus` — `.onTrack`, `.slightlyBehind(sessionsBehind:)`, `.significantlyBehind(sessionsBehind:)`, `.noProgramActive`
  - `AdherenceGuidanceType` — `.continueNormalSequence`, `.trimAndResume`, `.conservativeResume`
  - `AdherenceRescue` — adherence-aware rescue guidance struct with headline, details, and sessions-behind count
  - `TodayPlan` — complete plan output wrapping all above fields alongside the existing `DailyCoachRecommendation`
- Added `AdherenceRescueService` in `Services/Adaptive/AdherenceRescueService.swift`:
  - detects sessions-behind based on elapsed calendar days since `ProgramRun.startDate` vs. expected pace (`sessionsPerWeek`)
  - caps behind count at total program sessions to avoid over-reporting on completed programs
  - generates trim-and-resume guidance for 1 session behind; conservative-resume guidance for 2+ sessions behind
  - non-destructive — no program mutations, no overlay creation
- Added explicit confidence scoring in `TodayPlanEngine.computeConfidence`:
  - high: active program + program history (≥1 linked workout) + today check-in; OR active program + weekly analysis + today check-in
  - medium: new program run with no history + check-in; standalone with check-in + ≥3 recent workouts; program + analysis but no check-in
  - low: no check-in + no analysis; no check-in + fewer than 3 recent workouts
- Added explicit source attribution in `TodayPlanEngine.buildAttribution`:
  - per-source influence text for all five signal sources
  - `activeSourceLabels` list for compact UI display (replaces previous `[DailyCoachRecommendationSource]` pills)
- Added `whyToday` and `whatChangedToday` explainability outputs in `TodayPlanEngine`:
  - `whyToday` — paragraph explaining the core logic for today's plan, always populated
  - `whatChangedToday` — highlights notable departures from neutral baseline (pain flag, low/strong readiness, HealthKit caution, adherence alert, pending proposals); empty string when today is a normal session
- Updated `DailyCoachView` to use `TodayPlanEngine.buildPlan()` with minimal UI additions:
  - confidence badge (High/Medium/Low) in the recommendation card header
  - "What changed today" banner in the recommendation card (only shown when non-empty)
  - "Why Today" and "Confidence rationale" sections in the expanded recommendation detail
  - adherence rescue card surfaced below the recommendation card when the user is behind schedule
  - source pills now driven by `attribution.activeSourceLabels` (string-based, no breaking change to existing `DailyCoachRecommendation`)
- Behavioral constraints preserved:
  - HealthKit influence remains medium — nudges conservative, cannot override manual readiness
  - pain/discomfort flag remains the highest-priority override
  - adherence rescue is non-destructive — no program mutations or overlay creation
  - `DailyCoachRecommendationService` is unchanged and all existing signal rules are intact
- Added 32-test coverage in `SuggestMeSomeTests/Feature10Prompt6TodayPlanEngineTests.swift`:
  - confidence classification (high/medium/low) for all signal combinations
  - source attribution field population (check-in, pain flag, program, proposals, HealthKit)
  - adherence rescue outputs (onTrack, slightlyBehind, significantlyBehind, nil-when-no-program, cap-at-total-sessions)
  - `computeSessionsBehind` determinism (on-pace, behind, ahead, 200-day cap)
  - explanation generation (whyToday for pain/strong/low/HealthKit; whatChangedToday for neutral/pain/behind/proposals)
  - `TodayPlanEngine.buildPlan` integration (sparset case, never-surfaces-on-track, surfaces-when-behind, determinism)
  - `AdherenceStatus` equatability checks
- Verification runs for this prompt:
  - targeted:
    - `xcodebuild test -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SuggestMeSomeTests/Feature10Prompt6TodayPlanEngineTests` (32/32 pass)
  - broader regression slice:
    - `Feature7ValidationTests` (pass)
    - `Feature10Prompt5CoachAwareFusionTests` (pass)
    - `Feature9RecommendationEngineValidationTests` (pass)
  - compile validation:
    - `xcodebuild build -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17'` (pass)

#### Prompt 7 [Apple Watch Companion and Today Plan Transport Foundation] — 2026-04-12

- Made the Apple Watch companion seam substantially more real so that near-term watch work (remote launcher, live workout companion, Today Plan glance) can land on top of a shared, sync-aligned foundation without destabilising the iOS project.
- Added shared watch-safe contract layer in `Models/WatchPayloadContracts.swift`:
  - `WatchPayloadContractVersion` namespace mirroring `SyncContractVersion` (Feature 10 Prompt 1)
  - `WatchPayloadKind` discriminator enum (`workoutLaunch`, `workoutProgress`, `todayPlanSnapshot`, `currentSessionContext`, `liveWorkoutSnapshot`)
  - `WatchPayloadEnvelope<Payload>` versioned Codable wrapper (kind + schemaVersion + sentAt + payload); intentionally kept separate from `SyncEnvelopeDTO` so cloud sync and watch transport can evolve independently while sharing idioms
  - `WatchTodayPlanSnapshot` compact Today Plan summary for watch display (confidence, compact summary, primary suggestion text, readiness tier, pain flag, session label, program coordinates, active source labels, what-changed-today, adherence headline/guidance/sessions-behind, pending proposal count)
  - `WatchCurrentSessionContext` point-in-time view of the current exercise + set (exercise index, total sets, logged sets, next set number, next prescribed reps/weight/unit, cardio target seconds)
  - `WatchLiveWorkoutSnapshot` richer live-progress snapshot (elapsed, completed/total exercises, completed/total sets in current exercise, current exercise name, session label, program coordinates)
  - All payloads are `Codable + Equatable`, SwiftData-runtime independent, and explicitly additive-evolution so older watch builds remain forward compatible
- Added pure iPhone-side mapping layer in `Services/Watch/WatchSessionCoordinator.swift`:
  - `WatchPayloadMapper` — side-effect-free static mapping functions (Today Plan → snapshot, draft entries → current session context, draft entries → live snapshot, draft entries → progress snapshot, launch payload builder, completion helpers for draft sets/exercises including cardio)
  - `WatchSessionCoordinator` — `@MainActor` façade owning a `WatchCompanionBridge` that forwards typed broadcasts (`broadcastTodayPlan`, `broadcastWorkoutLaunch`, `broadcastLiveWorkout`, `broadcastCurrentSessionContext`); injection-friendly for tests
  - Current-session cursor logic: picks the first exercise whose sets are not all fully logged; honours explicit cursor override; falls back to the last entry when every exercise is complete
  - Prescribed-target fallback: when the next set has no live reps/weight, the context falls back to prescribed reps/weight/unit from the draft entry
- Extended `Services/Watch/WatchCompanionBridge.swift`:
  - `WatchCompanionBridge` protocol expanded with `sendTodayPlanSnapshot`, `sendLiveWorkoutSnapshot`, `sendCurrentSessionContext`
  - `DefaultWatchCompanionBridge` now JSON-encodes payloads via a shared `encodePayload` helper (`JSONEncoder` with `.secondsSince1970` dates and sorted keys for deterministic output) and routes them through two channels:
    - `transferUserInfo` for queued events (`workoutLaunch`, `workoutProgress`)
    - `updateApplicationContext` for latest-wins state (`todayPlanSnapshot`, `liveWorkoutSnapshot`, `currentSessionContext`)
  - Every bridge message now carries `schemaVersion`, `kind`, and `sentAt` alongside the JSON payload data so the future watch side can dispatch deterministically without peeking at the payload shape
  - Kept `#if canImport(WatchConnectivity)` and activation-state guards so the bridge stays safe on simulators/devices without a paired watch
- Coaching trust preserved:
  - the coordinator never synthesises its own plan — it maps verbatim from `TodayPlan` produced by `TodayPlanEngine` (Feature 10 Prompt 6), so watch surfaces stay faithful to the explainable iPhone output
  - confidence, readiness tier, pain flag, adherence rescue, active source labels, and what-changed-today all flow through unchanged
- Future cloud-sync compatibility:
  - watch DTOs avoid duplicating persisted model shapes and instead compose from the same Today Plan + draft entry value types the iPhone already uses
  - the envelope + schema-version discipline matches the sync-ready contract style from Prompt 1, so future cloud sync does not have to fight an ad hoc watch-only shape
- watchOS target scope decision: a net-new watchOS companion target would have required pbxproj structural changes outside the existing file-system-synchronized group setup. To protect project integrity, the watchOS target was deliberately deferred; the shared contracts, bridge layer, and iPhone-side coordination are fully implemented and tested so a subsequent prompt can add the watchOS target non-destructively against a stable foundation.
- Added focused Prompt 7 validation coverage in `SuggestMeSomeTests/Feature10Prompt7WatchFoundationTests.swift` (24 tests):
  - envelope versioning + Codable round-trip for Today Plan snapshot, live workout snapshot, and current session context
  - Today Plan snapshot mapping: program session label with week/session/name, standalone session type fallback, pain flag, adherence rescue headline/guidance/sessions-behind, what-changed and pending proposal propagation, readiness tier label mapping
  - launch payload generation: program coordinates carried through, standalone launch with nil coordinates
  - current session context mapping: first-incomplete picker, cursor override, nil-for-empty entries, prescribed target fallback, last-entry fallback when everything is logged
  - live workout snapshot mapping: completed exercise counts, current exercise name + set counts, negative-elapsed clamp, cardio completion detection
  - progress snapshot parity with live snapshot completed counts
  - coordinator broadcasts: launch + progress + live snapshot sent in a single `broadcastLiveWorkout` call, Today Plan broadcast, current session context broadcast, skip-when-empty guard
  - `MockWatchCompanionBridge` test double recording all five typed send paths
- Verification runs for this prompt:
  - targeted:
    - `xcodebuild test -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SuggestMeSomeTests/Feature10Prompt7WatchFoundationTests` (24/24 pass)
  - broader regression slice:
    - `Feature10SyncFoundationValidationTests` (pass)
    - `Feature10Prompt6TodayPlanEngineTests` (pass)
    - `Feature10Prompt5CoachAwareFusionTests` (pass)
    - `Feature7ValidationTests` (pass)
    - `Feature8ValidationTests` (pass)
  - compile validation:
    - `xcodebuild build -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17'` (pass)

#### Prompt 8 [Feature 10 Integration Hardening and Regression Pass] — 2026-04-12

- Completed a final Feature 10 integration hardening pass across sync contracts, repository/query seams, generator/adaptive boundaries, coach-aware SuggestMeSome logic, Today Plan output, and watch payload transport.
- Tightened SuggestMeSome coach-context loading so active overlays, pending user proposals, pending auto-apply proposals, and finalized fatigue status are scoped to the active program run through the read/query repository seam instead of broad global reads:
  - added `ReadQueryRepository.pendingCoachContextProposals(for:context:limit:)`
  - preserved standalone behavior by only surfacing nil-run pending proposals when no active run is in scope
  - kept non-destructive overlay behavior unchanged; base program prescriptions remain source-of-truth and overlays are still resolved at runtime
- Hardened Today Plan → watch payload source-of-truth mapping:
  - added additive `programRunStableID` to `WatchTodayPlanSnapshot`
  - wired `WatchPayloadMapper.makeTodayPlanSnapshot` and `WatchSessionCoordinator.broadcastTodayPlan` so watch snapshots can identify the active run while still deriving all coaching content verbatim from `TodayPlanEngine`
- Tightened async validation durability for `DeferredNavigationService` by replacing a brittle fixed-yield assertion with a bounded scheduler wait in the existing Prompt 2 test.
- Added focused Prompt 8 validation coverage in `SuggestMeSomeTests/Feature10Prompt8IntegrationHardeningTests.swift`:
  - run-scoped coach context excludes overlays/proposals/fatigue from unrelated runs
  - pending coach-context proposal query keeps active-run and standalone scopes separate
  - Today Plan engine output maps verbatim into the watch snapshot, including confidence, source labels, what-changed text, pending proposal count, program coordinates, and run stable ID
  - five-primary-focus matrix remains explicitly covered (`powerlifting`, `bodybuilding`, `powerbuilding`, `generalFitness`, `fullBody`)
- Verification runs for this prompt:
  - targeted:
    - `xcodebuild test -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SuggestMeSomeTests/Feature10Prompt8IntegrationHardeningTests` (pass)
  - impacted Feature 10 regression slice:
    - `Feature10Prompt2RepositoryQueryHardeningTests` (pass)
    - `Feature10Prompt5CoachAwareFusionTests` (pass)
    - `Feature10Prompt6TodayPlanEngineTests` (pass)
    - `Feature10Prompt7WatchFoundationTests` (pass)
    - `Feature10Prompt8IntegrationHardeningTests` (pass)
  - broader regression slice:
    - `Feature10SyncFoundationValidationTests` (pass)
    - `Feature10Prompt3ProgramGeneratorDecompositionTests` (pass)
    - `Feature10Prompt4AdaptivePipelineDecompositionTests` (pass)
    - `Feature6ValidationTests` (pass)
    - `Feature7ValidationTests` (pass)
    - `Feature8ValidationTests` (pass)
    - `Feature9RecommendationEngineValidationTests` (pass)
    - `Feature9SuggestMeSomeBuildValidationTests` (pass)
  - compile validation:
    - `xcodebuild build -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17'` (pass)

#### Prompt 9 UI Polish — Indigo Brand, Premium Moments, Micro-animations

- **Priority 1 — Single dominant accent:** All primary CTA buttons, tab bar, active filters, and interactive controls now use a single indigo brand color. Blue and purple are retired from brand usage; semantic colors (green/red/orange/yellow) are unchanged. Applied via `.tint(.indigo)` on ContentView plus targeted replacements across Dashboard, Workouts tab, DailyCoach, and all filter chips.

- **Priority 2 — Premium moment differentiation:** AI coaching cards (Dashboard coaching section, DailyCoach recommendation card) now display an indigo stroke border with a soft glow shadow, visually distinguishing them from standard data cards. PR feed rows receive a gold stroke ring, reinforcing the achievement identity.

- **Priority 3 — Smooth premium micro-animations:**
  - *Stat cards* count up from zero on appear using a staggered timer (0.8s ease-out), with SwiftUI `.contentTransition(.numericText())` for smooth digit changes.
  - *PR celebration overlay* — when a workout is saved and contains new PRs, a fullscreen celebration overlay springs in (star + count + "Tap to continue") before auto-dismissing and popping the view. Replaces the previous instant dismiss.
  - *Star glow on PR unlock* — `SetEntryRow` animates the star to 1.6× scale with a yellow shadow when `isPR` toggles true.
  - *Check-in confirmation* — saving a daily check-in shows a spring-in "Checked In" confirmation badge before the sheet dismisses with a soft fade.

---
---

### Feature 11 — Today Plan Polish and Execution Flow

**Status:** Complete

#### Prompt 1 [Today Plan Explanation and Proposal Awareness Polish] — 2026-04-12

- Polished the Daily Coach Today Plan surface to make daily intent, change attribution, and proposal impact clearer without changing core recommendation behavior.
- Added a dedicated explanation assembly layer in `Services/Adaptive/TodayPlanExplanationAssembler.swift` to separate source attribution and explainability text generation from `DailyCoachRecommendationService` logic:
  - explicit source attribution builder with machine-readable influence flags
  - structured "Why Today" composition for active-program and standalone paths
  - structured "What Changed Today" classification (`noChanges`, `runtimeOnlyAdjustment`, `approvedOverlayInfluence`, `pendingProposalRelevance`, `combinedInfluence`)
  - pending proposal impact-horizon classification (`affectsToday`, `affectsUpcomingSession`, `affectsLongHorizonProgramming`)
  - overlay influence context resolution (active overlays vs overlays applying to today's target session)
- Extended `TodayPlan` value types in `Services/Adaptive/TodayPlanTypes.swift`:
  - `TodayPlanInfluenceFlags`
  - `TodayPlanChangeType`
  - `TodayPlanChangeSummary`
  - `TodayPlanProposalImpact`
  - `TodayPlanProposalAwarenessItem`
  - Added `changeSummary` + `proposalAwareness` to `TodayPlan`
- Updated `TodayPlanEngine` orchestration in `Services/Adaptive/TodayPlanEngine.swift`:
  - accepts optional `pendingProposals` and `activeOverlays` inputs for richer explanation fidelity
  - uses `TodayPlanExplanationAssembler` for attribution, why-today, change-summary, and proposal-awareness assembly
  - preserves existing recommendation and confidence logic
  - keeps backward-compatible helper overloads where existing tests call legacy signatures
- Updated `DailyCoachView` Today Plan presentation in `Views/DailyCoach/DailyCoachView.swift`:
  - added structured "What Changed Today" block with explicit change type and concise detail lines
  - replaced plain attribution paragraph with a compact source-attribution section by source domain
  - replaced the old pending-proposals banner with a stronger `Proposal Awareness` card showing:
    - count by impact horizon (today / upcoming / long-horizon)
    - top pending proposal summaries with target window labels
  - wired active overlays into `TodayPlanEngine` so approved overlay influence is surfaced accurately
- Updated watch test plan factory in `SuggestMeSomeTests/Feature10Prompt7WatchFoundationTests.swift` for new `TodayPlan` fields.
- Expanded focused Today Plan validation in `SuggestMeSomeTests/Feature10Prompt6TodayPlanEngineTests.swift`:
  - source attribution flags correctness for program/overlay/proposal/runtime/HealthKit
  - change-summary type generation for runtime-only, approved-overlay, and pending-proposal-only scenarios
  - proposal-awareness impact classification (today/upcoming/long-horizon)
  - explicit standalone vs active-program why-today path checks
- Behavioral guardrails preserved:
  - no backend/cloud changes
  - no destructive program mutations
  - HealthKit remains medium influence and never overrides manual readiness priority rules
  - recommendation generation logic remains unchanged; only explanation/source assembly and presentation are refined
- Verification runs for this prompt:
  - targeted:
    - `xcodebuild test -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SuggestMeSomeTests/Feature10Prompt6TodayPlanEngineTests` (pass)
  - broader regression slice:
    - `xcodebuild test -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SuggestMeSomeTests/Feature7ValidationTests -only-testing:SuggestMeSomeTests/Feature10Prompt5CoachAwareFusionTests -only-testing:SuggestMeSomeTests/Feature10Prompt6TodayPlanEngineTests -only-testing:SuggestMeSomeTests/Feature10Prompt8IntegrationHardeningTests` (pass)
  - compile validation:
    - `xcodebuild build -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17'` (pass)

#### Prompt 2 [Today Plan Review, Proposal Confirmation, and Launch Flow] — 2026-04-13

- Expanded Today Plan into a decision-and-action surface so users can inspect relevant proposals, confirm approval/rejection with a compact confirmation step, and launch planned/adjusted sessions from the same card.
- Added `TodayPlanActionCoordinator` (`SuggestMeSome/Services/Adaptive/TodayPlanActionCoordinator.swift`) to keep execution logic out of raw view code:
  - run-scoped relevant-proposal selection using existing Today Plan proposal-awareness classification (today/upcoming prioritized)
  - staged (two-step) proposal decisions (`stageDecision` then `commitStagedDecision`) so approval/rejection is never single-tap
  - launch-path resolution for planned vs runtime-adjusted vs approved-overlay-adjusted session starts
  - explicit source-of-change labeling (`plannedPrescription`, `pendingProposal`, `approvedOverlay`, `runtimeCoachOnly`)
- Added `AdaptationProposalPresentationService` (`SuggestMeSome/Services/Adaptive/AdaptationProposalPresentationService.swift`) and reused it in multiple surfaces:
  - centralized proposal title/window/change/reason/detail mapping
  - removed duplicate proposal-display formatting logic from `AdaptationProposalReviewView`
- Updated `DailyCoachView` (`SuggestMeSome/Views/DailyCoach/DailyCoachView.swift`) for Today Plan execution flow:
  - pending proposals are now run-scoped and filtered through `AdaptationProposalConfirmationService.isPendingUserProposal`
  - added compact proposal review sheet directly from Today Plan (`TodayPlanProposalReviewSheet`)
  - added explicit confirm dialog before approve/reject commit
  - proposal decisions reuse existing `AdaptationProposalConfirmationService` (overlay-authoritative, non-destructive persistence unchanged)
  - launch actions now support same-surface paths:
    - `Start As Planned`
    - `Review Proposal` (when relevant pending proposal exists)
    - `Start Approved Version` (when an approved overlay is active for today's target session)
    - `Review Suggested Version` (runtime Daily Coach adjustment path)
  - added a compact `Change Layer` row clarifying whether today is driven by pending proposal, approved overlay, runtime-only adjustment, or base program prescription
- Added focused tests in `SuggestMeSomeTests/Feature11Prompt2TodayPlanExecutionFlowTests.swift`:
  - proposal relevance selection for Today Plan (today/upcoming/long-horizon prioritization)
  - compact staged confirmation behavior (no mutation before commit)
  - approve/reject action handling through confirmation service + overlay creation check
  - launch-path selection correctness
  - clear distinction coverage for planned/proposal/overlay/runtime source labeling
- Behavioral and architectural guardrails preserved:
  - no destructive mutation of `TrainingProgram` or base session templates
  - approved persistent adaptations still flow through overlays as authoritative runtime layer
  - runtime Daily Coach modifications remain draft-only and non-persistent
  - no backend/cloud changes
- Verification runs for this prompt:
  - targeted:
    - `xcodebuild test -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SuggestMeSomeTests/Feature11Prompt2TodayPlanExecutionFlowTests` (pass)
  - broader regression slice:
    - `xcodebuild test -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SuggestMeSomeTests/Feature7ValidationTests -only-testing:SuggestMeSomeTests/Feature6ValidationTests -only-testing:SuggestMeSomeTests/Feature10Prompt6TodayPlanEngineTests -only-testing:SuggestMeSomeTests/Feature10Prompt2RepositoryQueryHardeningTests` (pass)
  - compile validation:
    - `xcodebuild build -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17'` (pass)

#### Prompt 3 [Standalone Today Plan and SuggestMeSome Continuity Improvements] — 2026-04-13

- Improved standalone Daily Coach guidance through shared `TodayPlanEngine` orchestration (no forked product path):
  - added `TodayPlanContextMode` and `TodayPlanNextStepGuidance` in `Services/Adaptive/TodayPlanTypes.swift`
  - added `TodayPlanExplanationAssembler.buildNextStepGuidance(...)` to classify:
    - `Active Program`
    - `Standalone (History-Informed)`
    - `Standalone (Low-Confidence)`
  - wired `TodayPlanEngine.buildPlan(...)` to always attach utility-first next actions, making the distinction between "no active program" and "low-confidence baseline guess" explicit and testable.
- Updated `DailyCoachView` (`Views/DailyCoach/DailyCoachView.swift`) to surface standalone intent more clearly without changing recommendation authority:
  - standalone state now shows explicit context mode badge + context headline
  - recommendation card now includes a structured `What Next` section with actionable next steps
  - session summary card now includes `What Next` guidance derived from last session outcome.
- Improved standalone session-summary continuity in `DailyCoachSessionSummaryService`:
  - extended `SessionSummary` with `nextStepText`
  - added deterministic next-step guidance mapping from effort outcomes (`tooHard` / `onTarget` / `tooEasy`) and standalone vs program context.
- Improved SuggestMeSome standalone continuity in shared recommendation flow:
  - extended `SuggestMeSomeSessionRecommendation` with:
    - `continuitySummary`
    - `nextActionGuidance`
  - updated `SuggestMeSomeRecommendationService` to produce follow-through messaging that ties:
    - last standalone session recency
    - recent overlap / blocked lift context
    - fatigue/readiness influence
    - duration + equipment constraints
    - concrete next action after recommendation
  - surfaced these fields in `Views/Generator/GeneratorStepViews.swift` under a new `CONTINUITY` section.
- Compatibility and trust guardrails preserved:
  - no backend/cloud changes
  - no fake AI behavior
  - no destructive `TrainingProgram` mutation path changes
  - HealthKit remains medium influence only (nudges, not overrides)
  - active-program logic stays primary; standalone improvements reuse shared orchestration/services.
- Added focused tests:
  - `SuggestMeSomeTests/Feature11Prompt3StandaloneContinuityTests.swift`
    - standalone Today Plan explanation path classification
    - explicit no-program history-informed vs low-confidence distinction
    - standalone SuggestMeSome continuity narrative + next action
    - session-summary-to-next-step guidance for standalone completion
- Verification runs for this prompt:
  - targeted:
    - `xcodebuild test -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SuggestMeSomeTests/Feature11Prompt3StandaloneContinuityTests -only-testing:SuggestMeSomeTests/Feature10Prompt6TodayPlanEngineTests -only-testing:SuggestMeSomeTests/Feature9RecommendationEngineValidationTests -only-testing:SuggestMeSomeTests/Feature11Prompt2TodayPlanExecutionFlowTests` (pass)
  - broader regression slice:
    - `xcodebuild test -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SuggestMeSomeTests/Feature7ValidationTests -only-testing:SuggestMeSomeTests/Feature9RecommendationEngineValidationTests -only-testing:SuggestMeSomeTests/Feature9SuggestMeSomeBuildValidationTests -only-testing:SuggestMeSomeTests/Feature10Prompt5CoachAwareFusionTests -only-testing:SuggestMeSomeTests/Feature10Prompt6TodayPlanEngineTests -only-testing:SuggestMeSomeTests/Feature11Prompt2TodayPlanExecutionFlowTests -only-testing:SuggestMeSomeTests/Feature11Prompt3StandaloneContinuityTests` (pass)
  - compile validation:
    - `xcodebuild build -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17'` (pass)

#### Prompt 4 [Apple Watch Current Set Entry and Crown-First Logging] — 2026-04-13

- Advanced the watch execution foundation toward a real set-by-set companion flow by extending shared watch-safe state contracts and mapper logic around the default "current set entry" interaction.
- Updated `WatchCurrentSessionContext` in `SuggestMeSome/Models/WatchPayloadContracts.swift` with additive execution-focused fields (backward-compatible optional additions):
  - current set number + target summary
  - most recent completed set reps/weight snapshot
  - crown weight step hint + quick-complete flag
  - preferred interaction model (`digitalCrownFirst`)
  - session plan kind (`planned` / `coachAdjusted`)
- Extended `WatchPayloadMapper` in `SuggestMeSome/Services/Watch/WatchSessionCoordinator.swift` for crown-first execution behavior:
  - richer `makeCurrentSessionContext(...)` mapping to keep current exercise/set clear at a glance
  - deterministic digital-crown weight tick handling (`applyCrownTicksToWeight`, `applyCrownTicksToCurrentSet`) with unit-aware defaults and optional step override
  - one-tap set completion + advance transition helper (`completeCurrentSetAndAdvance`) returning updated draft entries and next set/exercise coordinates for fast watch progression
  - maintained shared source-of-truth behavior: watch state continues to derive from `DraftExerciseEntry` session drafts, avoiding watch-only decision logic
- Expanded focused coverage in `SuggestMeSomeTests/Feature10Prompt7WatchFoundationTests.swift` for:
  - current-set payload/state generation (summary, completed set snapshot, crown defaults, quick-complete affordance)
  - crown-oriented weight-entry updates
  - set completion and advance behavior (same exercise, next exercise, session completion)
  - planned vs coach-adjusted session compatibility in current context payload mapping
- Guardrails preserved:
  - no backend/cloud sync implementation
  - no complex watch-side structural editing/reordering flows
  - watch mapping remains additive and sync-safe via shared transport contracts
  - project build/test integrity preserved
- Verification runs for this prompt:
  - targeted:
    - `xcodebuild test -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SuggestMeSomeTests/Feature10Prompt7WatchFoundationTests` (pass)
  - broader regression slice:
    - `xcodebuild test -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SuggestMeSomeTests/Feature10Prompt7WatchFoundationTests -only-testing:SuggestMeSomeTests/Feature10Prompt8IntegrationHardeningTests -only-testing:SuggestMeSomeTests/Feature11Prompt2TodayPlanExecutionFlowTests -only-testing:SuggestMeSomeTests/Feature7ValidationTests` (pass)
  - compile validation:
    - `xcodebuild build -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17'` (pass)

#### Prompt 5 [Watch-to-Phone Continuity and Adjusted Session Execution] — 2026-04-13

- Closed the continuity gap between Today Plan launch on iPhone and session execution on Apple Watch so planned / approved-overlay / runtime-adjusted versions flow cleanly to watch state with correct source attribution.
- Extended shared watch-safe transport contracts in `SuggestMeSome/Models/WatchPayloadContracts.swift` and `SuggestMeSome/Models/WatchCompanionTypes.swift` (all additive / optional for sync compatibility):
  - rewrote `WatchSessionPlanKind` to `{ planned, overlayAdjusted, runtimeAdjusted }` so watch classification mirrors `TodayPlanLaunchPath` one-for-one
  - added `sessionSourceLabels` + `sessionVersionStableID` to `WatchCurrentSessionContext`, `WatchLiveWorkoutSnapshot`, and `WatchWorkoutLaunchPayload`
  - added `WatchSessionCompletionPayload` (counts, PR attribution, plan kind, source labels, stable version id) and wired it through `WatchPayloadKind.sessionCompletion`
- Extended `WatchPayloadMapper` + `WatchSessionCoordinator` in `SuggestMeSome/Services/Watch/WatchSessionCoordinator.swift`:
  - `makeLaunchPayload`, `makeLiveWorkoutSnapshot`, `makeCurrentSessionContext` now carry `sessionPlanKind` / `sessionSourceLabels` / `sessionVersionStableID`
  - new `makeSessionCompletionPayload(...)` with correct completed vs total counts (strength + cardio), negative-elapsed clamping, and PR count passthrough
  - `normalizeSourceLabels` helper trims blanks and collapses empty lists to `nil`
  - added `broadcastSessionCompletion(...)` to the coordinator façade; added `sendSessionCompletion(_:)` to `WatchCompanionBridge` using `transferUserInfo`
- Added pure, deterministic mapping helpers in `SuggestMeSome/Services/Adaptive/TodayPlanActionCoordinator.swift`:
  - `watchSessionPlanKind(for:)` — single call site owning planned / overlay / runtime classification
  - `watchSessionVersionStableID(runStableID:path:weekNumber:sessionNumber:)` — deterministic `run::wXsY::planned|overlay|runtime` stable id so watch can detect mid-session version swaps, with a standalone/free fallback when no program run is active
- Wired the first real UI consumer in `SuggestMeSome/Views/DailyCoach/DailyCoachView.swift`:
  - Today Plan launch now fires `WatchSessionCoordinator.broadcastWorkoutLaunch` + `broadcastTodayPlan` + `broadcastLiveWorkout` with the mapped plan kind, source labels, and stable session version id, so watch state reflects the exact version the iPhone launched
- Guardrails preserved:
  - no backend/cloud sync implementation
  - no destructive `TrainingProgram` mutation path changes
  - watch contracts remain additive and sync-safe
  - coaching source-of-truth logic lives on iPhone only; watch payloads are derived projections
  - local-first architecture and Today Plan proposal/approval flow untouched
- Added focused tests:
  - `SuggestMeSomeTests/Feature11Prompt5WatchContinuityTests.swift`
    - launch-path ↔ watch plan kind mapping (planned / overlayAdjusted / runtimeAdjusted)
    - `sessionVersionStableID` differentiation across launch paths + standalone fallback
    - launch payload + live snapshot + current session context continuity fields
    - source label normalization (blanks → `nil`)
    - session completion counts (strength + cardio) and negative-elapsed clamping
    - `WatchPayloadEnvelope` round-trip for session completion payload
    - end-to-end coordinator broadcast for planned and runtime-adjusted launches
  - updated `SuggestMeSomeTests/Feature10Prompt7WatchFoundationTests.swift` to the renamed `runtimeAdjusted` kind and added `sessionCompletion` support in the mock bridge
- Verification runs for this prompt:
  - targeted:
    - `xcodebuild test -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SuggestMeSomeTests/Feature11Prompt5WatchContinuityTests` (pass)
  - broader regression slice:
    - `xcodebuild test -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SuggestMeSomeTests/Feature11Prompt5WatchContinuityTests -only-testing:SuggestMeSomeTests/Feature10Prompt7WatchFoundationTests -only-testing:SuggestMeSomeTests/Feature10Prompt8IntegrationHardeningTests -only-testing:SuggestMeSomeTests/Feature11Prompt2TodayPlanExecutionFlowTests -only-testing:SuggestMeSomeTests/Feature11Prompt3StandaloneContinuityTests -only-testing:SuggestMeSomeTests/Feature7ValidationTests` (pass)
  - compile validation:
    - `xcodebuild build -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17'` (pass)

#### Prompt 6 [Dashboard Rename and Navigation Clarity Pass] — 2026-04-13

- Renamed the Home tab to Dashboard so the primary tab bar reflects the post–Feature 11 reality where Daily Coach / Today Plan is the central daily action surface.
- Introduced a `MainTab` enum in `SuggestMeSome/ContentView.swift` as the single source of truth for the root tab bar:
  - `dailyCoach` (tag 0), `dashboard` (tag 1), `workouts` (tag 2), `programs` (tag 3), `settings` (tag 4)
  - each case owns its user-facing `label` and SF Symbol `systemImage`
  - `ContentView`'s `TabView` now binds every `tabItem` / `tag` to `MainTab`, eliminating magic numbers and string literals at the root navigation level
- Updated `DashboardView` (`SuggestMeSome/Views/Dashboard/DashboardView.swift`):
  - `navigationTitle("Home")` → `navigationTitle("Dashboard")`
  - tab icon updated to `square.grid.2x2.fill` so it reads as an analytics/overview surface and stops competing visually with the brain-icon Daily Coach tab
- Fixed a latent navigation bug surfaced by the clarity pass:
  - Dashboard's "Program" quick-start and "Browse Programs" fallback button both used a hard-coded `selectedTab = 2`, which originally pointed at Training Programs but silently shifted to the Workouts tab after `Daily Coach` was added as the new first tab.
  - both call sites now route through `MainTab.programs.rawValue`, restoring the intended destination.
- Added focused regression coverage in `SuggestMeSomeTests/Feature11Prompt6DashboardRenameTests.swift`:
  - `MainTab.dashboard.label` is `"Dashboard"` and never `"Home"`
  - full label/icon/index snapshot for all five main tabs
  - Daily Coach remains tag 0 (asserting Today Plan centrality)
  - `MainTab.programs.rawValue == 3` and `MainTab.workouts.rawValue == 2` to pin the tab-index drift fix
  - uniqueness guarantees on labels, icons, and indexes
- Tab IA guardrails preserved:
  - no destructive navigation rewrites, no tab additions/removals, no reordering of existing tabs
  - Dashboard's analytics sections (quick start, coaching tiles, stats, PR feed, charts, program section) are unchanged — they remain utility-first summaries and do not duplicate Today Plan's recommendation surface
  - Daily Coach (Today Plan) continues to be the authoritative today-action surface
- Verification runs for this prompt:
  - targeted:
    - `xcodebuild test -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SuggestMeSomeTests/Feature11Prompt6DashboardRenameTests` (pass)
  - broader regression slice:
    - `xcodebuild test -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SuggestMeSomeTests/Feature11Prompt6DashboardRenameTests -only-testing:SuggestMeSomeTests/Feature11Prompt2TodayPlanExecutionFlowTests -only-testing:SuggestMeSomeTests/Feature11Prompt3StandaloneContinuityTests -only-testing:SuggestMeSomeTests/Feature11Prompt5WatchContinuityTests -only-testing:SuggestMeSomeTests/Feature10Prompt6TodayPlanEngineTests -only-testing:SuggestMeSomeTests/Feature7ValidationTests` (pass)
  - compile validation:
    - `xcodebuild build -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17'` (pass)

#### Prompt 7 [Feature 11 Integration Hardening and Regression Pass] — 2026-04-13

- Completed a final Feature 11 integration hardening pass across Today Plan explanation flow, proposal-aware launch semantics, standalone continuity, watch execution payloads, and Dashboard/tab clarity.
- Tightened Today Plan continuity:
  - `DailyCoachView` now passes run-scoped completed session keys into `TodayPlanEngine`, so the next-session recommendation does not drift when recent-workout display limits omit older completed program sessions.
  - latest weekly analysis selection now routes through `TrainingContextQueryService.latestWeeklyAnalysis(for:in:)`, keeping active-program fatigue/readiness context scoped to the active run and standalone context scoped to standalone analyses.
- Hardened adjusted-session launch integrity:
  - added `ProgramOverlayResolutionService.baseExercises(for:week:session:)` so "Start As Planned" can launch base prescription rows while "Start Approved Version" launches overlay-resolved rows.
  - `TodayPlanActionCoordinator.resolveLaunch` now keeps `.startAsPlanned` classified as `.planned` / `.plannedPrescription` even when an approved overlay exists; approved overlays are only classified as `.approvedOverlayAdjusted` when the user chooses the approved version path.
  - runtime Daily Coach draft review no longer broadcasts a watch launch when the user only opens the review sheet; the watch launch is sent after the user confirms "Start Suggested Session."
- Hardened source attribution:
  - added `TodayPlanActionCoordinator.executionSourceLabels(...)` to separate plan-level awareness from execution-level provenance.
  - watch execution labels now distinguish `Base Program`, `Approved Overlay`, `Daily Coach Runtime`, and `Pending Proposal Not Applied` instead of reusing broad Today Plan source labels that could imply a proposal or overlay was applied when it was only visible.
- Improved watch execution parity:
  - Today Plan launch now broadcasts launch + Today Plan snapshot + live workout snapshot + current-session context using the actual draft entries that the phone is launching.
  - initial watch live/current-set state now carries the same plan kind, source labels, and stable session-version id as the launch payload.
- Removed integration drift in overlay row cloning:
  - overlay resolution now preserves `syncStableID`, `syncVersion`, `syncLastModifiedAt`, `explainabilityPurpose`, and `explainabilitySelectionReason` when cloning program rows for non-destructive resolution.
  - this keeps Daily Coach draft preparation and accessory trimming aligned with generator explainability metadata.
- Guardrails preserved:
  - no backend/cloud implementation
  - no broad UI redesign
  - no destructive base-program mutation
  - HealthKit remains a medium, behind-the-scenes nudge surfaced through attribution only
  - standalone behavior remains supported through shared Today Plan orchestration rather than a forked path
- Added focused regression coverage in `SuggestMeSomeTests/Feature11Prompt7IntegrationHardeningTests.swift`:
  - planned vs approved-overlay launch classification when overlays are active
  - execution source labels for base-plan, pending-proposal-not-applied, and approved-overlay paths
  - base rows remain unchanged while overlay-resolved rows apply adjustments
  - overlay row cloning preserves sync and explainability metadata
  - completed-session keys drive Today Plan next-session continuity
  - weekly analysis selection does not bleed across active-program and standalone contexts
  - watch launch/live/current-context payloads carry the same execution version id and current-set truth
- Verification runs for this prompt:
  - targeted:
    - `xcodebuild test -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SuggestMeSomeTests/Feature11Prompt7IntegrationHardeningTests` (pass)
  - broader regression slice:
    - `xcodebuild test -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SuggestMeSomeTests/Feature11Prompt7IntegrationHardeningTests -only-testing:SuggestMeSomeTests/Feature11Prompt6DashboardRenameTests -only-testing:SuggestMeSomeTests/Feature11Prompt5WatchContinuityTests -only-testing:SuggestMeSomeTests/Feature11Prompt3StandaloneContinuityTests -only-testing:SuggestMeSomeTests/Feature11Prompt2TodayPlanExecutionFlowTests -only-testing:SuggestMeSomeTests/Feature10Prompt7WatchFoundationTests -only-testing:SuggestMeSomeTests/Feature10Prompt6TodayPlanEngineTests -only-testing:SuggestMeSomeTests/Feature10Prompt8IntegrationHardeningTests -only-testing:SuggestMeSomeTests/Feature7ValidationTests -only-testing:SuggestMeSomeTests/Feature6ValidationTests` (pass)
  - compile validation:
    - `xcodebuild build -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17'` (pass)

---

### Feature 12 — Apple Watch Workout Execution Companion

**Status:** Complete

#### Prompt 1 [watchOS Target and Companion Shell] — 2026-04-13

- Added the first installable watchOS companion target:
  - `SuggestMeSomeWatch` target and shared scheme `SuggestMeSomeWatch`
  - watch bundle identifier `com.alexyao.SuggestMeSome.watch`
  - iOS app now embeds `SuggestMeSomeWatch.app` through an `Embed Watch Content` build phase
- Created watch app shell files:
  - `SuggestMeSomeWatch/SuggestMeSomeWatchApp.swift`
  - `SuggestMeSomeWatch/WatchCompanionContainer.swift`
  - `SuggestMeSomeWatch/WatchCompanionSessionStore.swift`
  - `SuggestMeSomeWatch/WatchRootView.swift`
  - `SuggestMeSomeWatch/Assets.xcassets`
  - `SuggestMeSome.xcodeproj/xcshareddata/xcschemes/SuggestMeSomeWatch.xcscheme`
  - updated `SuggestMeSome.xcodeproj/project.pbxproj`
- User-visible behavior:
  - watch app opens directly into active workout progress when live workout/current-set payloads exist
  - otherwise it shows Today Plan or a clear "sync from iPhone" empty state
  - active strength sets expose two stacked Digital Crown-focused controls: reps first, weight second
  - completion handoff clears live workout state and returns the shell to Today Plan
- Architecture and guardrails:
  - iPhone remains source of truth for workout state, persistence, coaching, and proposal approval
  - watch target only shares transport-safe DTOs from `WatchPayloadContracts.swift` and `WatchCompanionTypes.swift`
  - no SwiftData models, iPhone services, coaching engines, cloud/backend concepts, proposal review UI, history dashboard, or broad watch surfaces were added
  - root state priority matches the Feature 12 Smart Stack direction: active workout progress first, Today Plan when idle
  - watch companion is scoped to all active workouts, not just program sessions
- Validation/build steps run:
  - `xcodebuild -list -project SuggestMeSome.xcodeproj` (pass; schemes include `SuggestMeSome` and `SuggestMeSomeWatch`)
  - `xcodebuild build -project SuggestMeSome.xcodeproj -scheme SuggestMeSomeWatch -destination 'generic/platform=watchOS Simulator'` (pass)
  - `xcodebuild build -project SuggestMeSome.xcodeproj -scheme SuggestMeSomeWatch -destination 'generic/platform=watchOS'` (blocked by missing local provisioning profile for `com.alexyao.SuggestMeSome.watch`)
  - `xcodebuild build -project SuggestMeSome.xcodeproj -scheme SuggestMeSomeWatch -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO` (pass; device-architecture compile)
  - `xcodebuild build -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17'` (pass; includes embedded watch app validation)
- Watch scheme/target used: `SuggestMeSomeWatch` / `SuggestMeSomeWatch`

---

#### Prompt 2 [Bridge Codec and Watch Session Store] — 2026-04-13

- Created a shared pure watch bridge codec:
  - `SuggestMeSome/Models/WatchBridgeMessageCodec.swift`
  - added the codec to the watch target's shared source list in `SuggestMeSome.xcodeproj/project.pbxproj`
  - centralized dictionary encode/decode for `schemaVersion`, `kind`, `sentAt`, and `payloadJSON`
  - preserved `.secondsSince1970` date coding and sorted JSON payload encoding for deterministic transport payloads
- Refactored the iPhone bridge:
  - `SuggestMeSome/Services/Watch/WatchCompanionBridge.swift`
  - `DefaultWatchCompanionBridge` now builds both `transferUserInfo` and `updateApplicationContext` messages through the shared codec while keeping the existing wire shape and channel semantics intact
- Rebuilt the watch-side receive/state foundation:
  - `SuggestMeSomeWatch/WatchCompanionSessionStore.swift`
  - decodes and stores `todayPlanSnapshot`, `workoutLaunch`, `workoutProgress`, `currentSessionContext`, `liveWorkoutSnapshot`, and `sessionCompletion`
  - keeps application-context payloads latest-wins by kind
  - queues transferred user-info events before applying them on the main actor
  - exposes watch session support, activation, iPhone install, reachability, pending-content, and sync message status for SwiftUI
- Wired the watch root to real observable state:
  - `SuggestMeSomeWatch/WatchRootView.swift`
  - active workout state still wins over Today Plan, including all workouts rather than program-only sessions
  - completion handoff clears live workout state and returns the watch shell to the idle Today Plan surface
  - the watch UI now surfaces iPhone reachability/sync status in both live workout and idle states
- Added focused codec coverage:
  - `SuggestMeSomeTests/Feature12Prompt2WatchBridgeCodecTests.swift`
  - verifies current transport keys, payload round-trip decoding, malformed dictionary rejection, future schema detection, and payload decode failures
- Architecture and guardrails:
  - phone remains the source of truth for workout state, persistence, coaching, and proposal approval
  - no watch-to-phone action sending was added
  - no SwiftData/runtime model coupling was introduced into shared watch transport code
  - watch-side state remains derived from existing DTOs only
  - real-device quality is covered by the watchOS device-architecture compile command below; simulator behavior is not treated as sufficient on its own
- Validation/build steps run:
  - `xcodebuild -list -project SuggestMeSome.xcodeproj` (pass; schemes include `SuggestMeSome` and `SuggestMeSomeWatch`)
  - `xcodebuild test -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SuggestMeSomeTests/Feature12Prompt2WatchBridgeCodecTests` (pass; 4/4 tests)
  - `xcodebuild build -project SuggestMeSome.xcodeproj -scheme SuggestMeSomeWatch -destination 'generic/platform=watchOS Simulator'` (pass)
  - `xcodebuild build -project SuggestMeSome.xcodeproj -scheme SuggestMeSomeWatch -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO` (pass; device-architecture compile)
  - `xcodebuild build -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17'` (pass; includes embedded watch app validation)
- Watch scheme/target used: `SuggestMeSomeWatch` / `SuggestMeSomeWatch`

---

#### Prompt 3 [Watch Root and Today Plan UI] — 2026-04-13

- Rebuilt the watch root flow as a thin, native switcher:
  - `SuggestMeSomeWatch/WatchRootView.swift`
  - active live workout wins the root when any of `liveWorkout`, `currentContext`, `progressSnapshot`, or `workoutLaunch` is present; otherwise Today Plan fills the surface
  - navigation stays minimal — single `NavigationStack`, no tab bar, no proposal review, no history drill-in
  - companion app now tints with the shared `WatchPalette.primary` indigo token
- Added a premium Today Plan watch surface:
  - `SuggestMeSomeWatch/WatchTodayPlanView.swift`
  - compact header with "Today" label, program session title, and program name
  - indigo-tinted primary suggestion card with compact summary subtitle
  - side-by-side readiness and confidence pills with color tiers
  - standalone pain-flag pill when the iPhone plan is pain-gated
  - "What Changed" block appears only when the iPhone plan actually reports a change
  - adherence rescue block surfaces headline, sessions-behind count, and guidance type when present
  - compact source label strip for trust without clutter
  - strong empty state when no plan has synced yet, with reconnect hint
  - "Resume Workout" live CTA when both a Today Plan and a live workout snapshot are staged
  - completion celebration block with exercise count, elapsed time, and PR count when `completion` is present
  - all content stays faithful to iPhone-produced state — watch never synthesises its own coaching text
- Extracted the active workout execution surface into its own file:
  - `SuggestMeSomeWatch/WatchActiveWorkoutView.swift`
  - prominent elapsed-time hero, linear indigo progress bar, exercise count subtitle
  - current exercise card with two stacked crown-first focused controls: reps on top, weight below
  - focus highlighting tints the active row indigo so the Digital Crown target is glanceable
  - dedicated cardio panel reuses the shared duration formatter and falls back to "Open on iPhone" when no target
  - reps focus auto-activates on first appear so users can log immediately without tapping
- Introduced a reusable watch UI helper layer:
  - `SuggestMeSomeWatch/WatchUIComponents.swift`
  - `WatchPalette` primary/surface/positive/warning/danger color tokens
  - `watchCard(emphasized:tint:)` view modifier with subtle stroke + rounded background
  - `WatchPillBadge`, `WatchReadinessBadge`, `WatchConfidenceBadge`, `WatchPainFlagBadge`
  - `WatchAdherenceBlock`, `WatchWhatChangedBlock`, `WatchSourceLabelsStrip`
  - `WatchEmptyStatePanel`, `WatchConnectionDot`
  - `WatchDurationFormatter` for `mm:ss` / `h:mm:ss` elapsed rendering shared across surfaces
- Added mock state fixtures and SwiftUI previews for the key watch screens:
  - `SuggestMeSomeWatch/WatchPreviewFixtures.swift` (guarded by `#if DEBUG`)
  - `WatchTodayPlanView` previews: normal plan, pain-flagged plan, adherence rescue, empty state, active-workout CTA, completion celebration
  - `WatchActiveWorkoutView` previews: strength session, cardio session, idle connection status
- User-visible behavior:
  - glanceable Today Plan that now looks and reads like a premium watch app, not a debug dump of DTO fields
  - pain-flagged days are visually distinct and never hide behind a generic caption
  - adherence rescue surfaces with an explicit rescue headline and session-behind count
  - live workout state keeps its execution-first hero layout with crown-first logging intact
  - empty state tells the user exactly how to unblock themselves ("Open SuggestMeSome on iPhone")
- Architecture and guardrails:
  - iPhone remains the source of truth for workout state, persistence, coaching, and proposal approval
  - no plan/coaching/analytics logic moved onto the watch target
  - no proposal review/approval, dashboard, history, or settings surfaces added on watch
  - iPhone Today Plan UI was not redesigned — the phone surface is untouched
  - watch companion continues to support all active workouts, not just program sessions
  - companion app uses the shared transport DTOs only; no SwiftData imports, no coaching engines, no runtime model coupling
  - root mode still prioritises active live workout, matching the Feature 12 Smart Stack direction
- Files created/edited:
  - created: `SuggestMeSomeWatch/WatchUIComponents.swift`
  - created: `SuggestMeSomeWatch/WatchTodayPlanView.swift`
  - created: `SuggestMeSomeWatch/WatchActiveWorkoutView.swift`
  - created: `SuggestMeSomeWatch/WatchPreviewFixtures.swift`
  - edited: `SuggestMeSomeWatch/WatchRootView.swift`
  - edited: `README.md` (Feature 12 Prompt 3 entry)
- Validation/build/previews run:
  - `xcodebuild build -project SuggestMeSome.xcodeproj -scheme SuggestMeSomeWatch -destination 'generic/platform=watchOS Simulator'` (pass; BUILD SUCCEEDED)
  - `xcodebuild build -project SuggestMeSome.xcodeproj -scheme SuggestMeSomeWatch -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO` (pass; device-architecture compile, BUILD SUCCEEDED)
  - `xcodebuild build -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17'` (pass; includes embedded watch app validation)
  - SwiftUI previews compile into `__preview.dylib` as part of the watch simulator build, exercising every fixture in `WatchPreviewFixtures`
  - state coverage wired through the preview macros: no-plan, normal plan, pain-flagged plan, adherence rescue, active live workout (strength and cardio), idle connection status, and completion celebration
- Watch scheme/target used: `SuggestMeSomeWatch` / `SuggestMeSomeWatch`

---

#### Prompt 4 [Watch Actions and Phone Workout Control] — 2026-04-13

- Added shared watch action contracts:
  - edited `SuggestMeSome/Models/WatchPayloadContracts.swift`
  - added `WatchWorkoutExecutionActionDTO` with explicit `actionSchemaVersion`, `actionID`, `workoutID`, optional cursor fields, optional `sessionVersionStableID`, and `createdAt`
  - added narrow action kinds for current-set weight ticks, current-set reps ticks, complete current set, and complete cardio block
  - kept the existing iPhone-to-watch payload kinds intact and added only the new `workoutExecutionAction` kind
- Extended bridge transport in both directions:
  - edited `SuggestMeSome/Services/Watch/WatchCompanionBridge.swift`
  - `DefaultWatchCompanionBridge.shared` now receives `workoutExecutionAction` payloads from `sendMessage` and queued `transferUserInfo`
  - inbound action decoding goes through `WatchBridgeMessageCodec` and ignores malformed, unsupported-schema, or non-action payloads
  - edited `SuggestMeSomeWatch/WatchCompanionSessionStore.swift`
  - watch actions send immediately when the iPhone is reachable and fall back to queued `transferUserInfo` when not reachable
- Wired phone-side application into the active draft owner:
  - edited `SuggestMeSome/Services/ActiveWorkoutSessionStore.swift`
  - actions apply only to the current `ActiveWorkoutSession.exerciseEntries`
  - saved/completed `Workout`, `ExerciseEntry`, and `SetEntry` records are never mutated by watch actions
  - mismatched workout IDs, duplicate action IDs, stale cursor actions, unsupported schemas, and incompatible action shapes are ignored
  - edited `SuggestMeSome/Models/DraftWorkoutTypes.swift` to add optional `cardioCompletionLogged` for watch-cardio completion without inventing duration values
- Added pure action helpers and rebroadcasts:
  - edited `SuggestMeSome/Services/Watch/WatchSessionCoordinator.swift`
  - added pure helpers for reps ticks, cardio completion, and DTO-driven action application alongside the existing weight and set-completion helpers
  - `WatchSessionCoordinator.shared` installs the iPhone action handler at app launch and rebroadcasts updated live workout + current-session context after an action applies
  - edited `SuggestMeSome/SuggestMeSomeApp.swift` to install the handler against the shared `ActiveWorkoutSessionStore`
  - edited `SuggestMeSome/Views/Workout/WorkoutView.swift` so all active workout paths broadcast live/current state and sync visible draft state when watch actions update the store
  - edited `SuggestMeSome/Views/Settings/HealthDataSettingsView.swift` to reuse the shared watch bridge instead of creating a competing `WCSession` delegate
- Updated watch execution controls:
  - edited `SuggestMeSomeWatch/WatchActiveWorkoutView.swift`
  - edited `SuggestMeSomeWatch/WatchRootView.swift`
  - reps and weight remain two stacked Digital Crown-focused controls
  - crown changes emit versioned watch action DTOs instead of local-only state changes
  - strength sessions add a narrow `Complete Set` action
  - cardio sessions add a narrow `Mark Complete` action
- Added focused tests:
  - created `SuggestMeSomeTests/Feature12Prompt4WatchActionsTests.swift`
  - edited `SuggestMeSomeTests/Feature10Prompt7WatchFoundationTests.swift` to keep the existing mock bridge conforming to the extended bridge protocol
  - coverage includes action DTO encode/decode, pure reps/weight/complete/cardio helpers, stale cursor ignore, and no-active-workout ignore
- User-visible behavior:
  - during any active workout, the watch can send current-set reps ticks, current-set weight ticks, complete-set actions, and cardio-complete actions to the iPhone
  - the iPhone remains the state and persistence authority; the watch only requests narrow live-workout actions
  - after an accepted action, the watch receives refreshed live progress and current-session context
  - active workout state is broadcast from empty/manual workouts, SuggestMeSome generated workouts, program workouts, Daily Coach prepared workouts, and resumed in-progress sessions
- Architecture and guardrails:
  - no proposal review/approval moved to watch
  - no save logic moved to watch
  - no broad free-form watch editing was introduced
  - no backend/cloud concepts were introduced
  - watch-originated actions mutate only the active in-progress draft through `ActiveWorkoutSessionStore`
  - stale or mismatched actions are ignored instead of creating duplicate or race-prone state
  - real-device quality was checked with a generic watchOS device-architecture compile, not simulator-only validation
- Validation/build/tests run:
  - `xcodebuild test -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SuggestMeSomeTests/Feature12Prompt4WatchActionsTests` (initially failed on a Swift precedence compile issue, fixed)
  - `xcodebuild test -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SuggestMeSomeTests/Feature12Prompt4WatchActionsTests` (initially failed on a test assumption about existing draft logging semantics, fixed)
  - `xcodebuild build -project SuggestMeSome.xcodeproj -scheme SuggestMeSomeWatch -destination 'generic/platform=watchOS Simulator'` (pass)
  - `xcodebuild build -project SuggestMeSome.xcodeproj -scheme SuggestMeSomeWatch -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO` (initially failed after warning cleanup because a `some View` helper needed an explicit return, fixed)
  - `xcodebuild build -project SuggestMeSome.xcodeproj -scheme SuggestMeSomeWatch -destination 'generic/platform=watchOS Simulator'` (pass, final)
  - `xcodebuild build -project SuggestMeSome.xcodeproj -scheme SuggestMeSomeWatch -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO` (pass, final device-architecture compile)
  - `xcodebuild build -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17'` (pass; includes embedded watch app validation)
  - `xcodebuild test -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SuggestMeSomeTests/Feature12Prompt4WatchActionsTests` (pass, final; 5/5 tests)
- Watch scheme/target used: `SuggestMeSomeWatch` / `SuggestMeSomeWatch`

---

#### Prompt 5 [Live Watch Workout UI and Rest Timer] — 2026-04-13

- Rebuilt the watch live-workout execution surface:
  - edited `SuggestMeSomeWatch/WatchActiveWorkoutView.swift`
  - session header now surfaces plan kind as a compact "Planned / Adjusted / Live" chip derived from the iPhone-produced snapshot — no watch-side attribution invented
  - progress card shows elapsed time, linear indigo progress bar, and `Ex n/total` counter derived from the current context cursor
  - current exercise card keeps two stacked crown-first focused controls (reps on top, weight below), the explicit `Complete Set` primary action, and unit-aware weight stepping tied to `crownWeightStep`
  - added a "Warming Up" card for the window where an active workout has launched but no current context has synced yet so the watch never shows a blank panel
  - added an "awaiting iPhone" empty state for the unusual case where the root mode enters active workout without any live/progress/context payload
  - crown changes still emit versioned `WatchWorkoutExecutionActionDTO`s; phone remains source of truth for persistence
- Added a watch-local rest timer experience:
  - created `SuggestMeSomeWatch/WatchRestTimerController.swift`
  - `@MainActor` observable controller with 1-second tick cadence, remaining/total seconds, progress, and an explicit skip path
  - haptic cues for start, 3-second next-set pre-cue, completion, and skip via `WKInterfaceDevice`, all guarded behind `#if canImport(WatchKit)` so the shared contracts keep compiling against non-watch targets
  - added `WatchRestTimerPanel` inside `WatchActiveWorkoutView.swift` — countdown hero, linear progress, next-set hint, and a `Skip Rest` bordered button
  - `Complete Set` on strength exercises now kicks off a 90-second rest timer locally and replaces the crown rows with the rest panel so the user sees only one focused state at a time
  - rest timer stops automatically when the current set cursor changes (e.g. next set syncs from iPhone), keeping wrist state honest vs phone state
- Added a dedicated polished session completion state:
  - created `SuggestMeSomeWatch/WatchSessionCompletionView.swift`
  - large "Total time" hero, side-by-side exercise/set metric tiles, optional PR banner, source-label strip, and a "Back to Today" dismiss action
  - added `WatchCompanionRootMode.sessionCompletion` and a `dismissCompletion()` method in `SuggestMeSomeWatch/WatchCompanionSessionStore.swift`
  - edited `SuggestMeSomeWatch/WatchRootView.swift` to pick completion as its own root mode when present, falling back to Today Plan after dismissal
  - Today Plan celebration card still renders when a completion is available alongside a plan, so the wrist has a premium moment whether the user dismisses or not
- Extended preview fixtures for the new states:
  - edited `SuggestMeSomeWatch/WatchPreviewFixtures.swift`
  - added `adjustedLiveWorkout` + `adjustedCurrentContext` pair for the runtime-adjusted plan kind preview
  - added `completionPayloadNoPR` for the non-PR completion preview
  - wired previews: "Active — Strength", "Active — Cardio", "Active — Adjusted Session", "Active — Pending Context", "Active — Idle Connection", "Completion — With PRs", "Completion — No PRs"
- User-visible behavior:
  - glanceable live-workout hero with elapsed time, exercise counter, and plan-kind chip
  - two stacked crown-first controls for reps and weight — no shared mode toggle, no tiny controls
  - tapping `Complete Set` kicks off a visible rest countdown with haptic cues and a next-set hint; the user can skip any time
  - cardio sessions keep their dedicated target card and `Mark Complete` action
  - when a workout finishes, the wrist switches into a premium completion moment with totals, elapsed time, and PR count
  - when the context hasn't arrived yet, the wrist shows a clear "Warming Up" state instead of an empty card
- Architecture and guardrails:
  - iPhone remains source of truth for workout state, persistence, coaching, and proposal approval
  - no proposal review/approval, no history, no dashboard added to the watch target
  - rest timer is watch-local UX state only and never mutates iPhone-owned draft entries
  - phone-owned `WatchWorkoutExecutionActionDTO` path is unchanged — `Complete Set` still emits the same versioned action the phone already understands
  - real-device quality validated with a generic watchOS device-architecture compile, not only simulator
  - no SwiftData model types pulled into the watch target; `WKInterfaceDevice` is guarded behind `#if canImport(WatchKit)`
- Files created/edited:
  - created: `SuggestMeSomeWatch/WatchRestTimerController.swift`
  - created: `SuggestMeSomeWatch/WatchSessionCompletionView.swift`
  - edited: `SuggestMeSomeWatch/WatchActiveWorkoutView.swift`
  - edited: `SuggestMeSomeWatch/WatchRootView.swift`
  - edited: `SuggestMeSomeWatch/WatchCompanionSessionStore.swift`
  - edited: `SuggestMeSomeWatch/WatchPreviewFixtures.swift`
  - edited: `README.md` (Feature 12 Prompt 5 entry)
- Validation/build/previews/tests run:
  - `xcodebuild build -project SuggestMeSome.xcodeproj -scheme SuggestMeSomeWatch -destination 'generic/platform=watchOS Simulator'` (pass; BUILD SUCCEEDED, watch simulator compile)
  - `xcodebuild build -project SuggestMeSome.xcodeproj -scheme SuggestMeSomeWatch -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO` (pass; device-architecture compile, BUILD SUCCEEDED)
  - `xcodebuild build -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17'` (pass; iOS build + embedded watch app validation)
  - `xcodebuild test -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SuggestMeSomeTests/Feature12Prompt4WatchActionsTests -only-testing:SuggestMeSomeTests/Feature12Prompt2WatchBridgeCodecTests` (pass; 9/9 tests)
  - SwiftUI previews compile into `__preview.dylib` as part of the watch simulator build, exercising the new strength, cardio, adjusted, pending-context, idle-connection, with-PR, and no-PR fixtures
  - state coverage exercised in previews: manual/empty workout analogue (awaiting iPhone empty state), SuggestMeSome workout (strength), program workout (strength + planned), runtime-adjusted program workout, cardio block, resumed in-progress workout (warming-up/pending context), rest timer flow (kicks off on complete), session completion (with PRs and no PRs)
- Watch scheme/target used: `SuggestMeSomeWatch` / `SuggestMeSomeWatch`

---

#### Prompt 6 [Smart Stack, Hardening, and Final Validation] — 2026-04-13

- Added Smart Stack support through a narrow watch widget extension:
  - created `SuggestMeSomeWatchWidget` target, shared scheme `SuggestMeSomeWatchWidget`, widget product `SuggestMeSomeWatchWidget.appex`, and app-group entitlements for the watch app/widget
  - created `SuggestMeSome/Models/WatchWidgetSnapshot.swift` as the shared phone/watch/widget snapshot contract
  - created `SuggestMeSomeWatchWidget/Sources/SuggestMeSomeWatchWidget.swift`, `SuggestMeSomeWatchWidget/Info.plist`, `SuggestMeSomeWatchWidget/SuggestMeSomeWatchWidget.entitlements`, and `SuggestMeSome.xcodeproj/xcshareddata/xcschemes/SuggestMeSomeWatchWidget.xcscheme`
  - rectangular, circular, and inline widget families prefer live workout progress while a non-stale session is active and fall back to Today Plan only when idle
- Hardened live workout continuity and source attribution:
  - edited `ActiveWorkoutSessionStore`, `WatchSessionCoordinator`, `DailyCoachView`, `ProgramWorkoutViews`, and `WorkoutView` so manual/empty, SuggestMeSome generated, program, prepared draft, and resumed sessions keep stable workout IDs, session plan kind, source labels, and version IDs
  - rejected stale or mismatched watch actions/current-context payloads instead of applying them to the wrong active session
  - completion handoff now carries phone-owned session attribution and counts before clearing active state
  - planned vs approved-overlay vs runtime-adjusted labels remain phone-derived; proposal review/approval stays off-watch
- Added final watch accessibility and interaction polish:
  - edited `WatchActiveWorkoutView`, `WatchCompanionSessionStore`, `WatchTodayPlanView`, and `WatchUIComponents`
  - added VoiceOver labels/values/hints for progress, cardio targets, complete actions, connection state, source badges, and the stacked reps/weight Crown controls
  - added guarded success haptics for completed set/cardio actions and safe widget reloads when live, Today Plan, current-context, or completion payloads arrive
  - color is paired with labels, chips, progress text, or explicit status copy instead of being the only signal
- Added focused regression coverage in `SuggestMeSomeTests/Feature12Prompt6WatchSmartStackHardeningTests.swift`:
  - Smart Stack idle vs active-session switching, stale live fallback, mismatched current-context version rejection, mismatched action rejection, and coordinator attribution propagation
- Files edited:
  - `SuggestMeSome.xcodeproj/project.pbxproj`
  - `SuggestMeSome/Services/ActiveWorkoutSessionStore.swift`
  - `SuggestMeSome/Services/Watch/WatchSessionCoordinator.swift`
  - `SuggestMeSome/Views/DailyCoach/DailyCoachView.swift`
  - `SuggestMeSome/Views/Programs/ProgramWorkoutViews.swift`
  - `SuggestMeSome/Views/Workout/WorkoutView.swift`
  - `SuggestMeSomeWatch/WatchActiveWorkoutView.swift`
  - `SuggestMeSomeWatch/WatchCompanionSessionStore.swift`
  - `SuggestMeSomeWatch/WatchTodayPlanView.swift`
  - `SuggestMeSomeWatch/WatchUIComponents.swift`
  - `README.md`
- Validation/build/tests run:
  - `xcodebuild -list -project SuggestMeSome.xcodeproj` (pass; schemes include `SuggestMeSome`, `SuggestMeSomeWatch`, and `SuggestMeSomeWatchWidget`)
  - `xcodebuild build -project SuggestMeSome.xcodeproj -scheme SuggestMeSomeWatchWidget -destination generic/platform=watchOS -derivedDataPath /tmp/SuggestMeSomeDerivedData CODE_SIGNING_ALLOWED=NO` (pass; widget device-architecture compile)
  - `xcodebuild build -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination generic/platform=iOS -derivedDataPath /tmp/SuggestMeSomeDerivedData CODE_SIGNING_ALLOWED=NO` (pass; iOS device-architecture compile with embedded watch content)
  - `xcodebuild build -project SuggestMeSome.xcodeproj -scheme SuggestMeSomeWatch -destination generic/platform=watchOS -derivedDataPath /tmp/SuggestMeSomeDerivedData CODE_SIGNING_ALLOWED=NO` (pass; watch device-architecture compile with embedded widget extension)
  - `xcodebuild test -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/SuggestMeSomeDerivedData -only-testing:SuggestMeSomeTests/Feature10Prompt7WatchFoundationTests -only-testing:SuggestMeSomeTests/Feature10Prompt8IntegrationHardeningTests -only-testing:SuggestMeSomeTests/Feature11Prompt5WatchContinuityTests -only-testing:SuggestMeSomeTests/Feature11Prompt7IntegrationHardeningTests -only-testing:SuggestMeSomeTests/Feature12Prompt4WatchActionsTests -only-testing:SuggestMeSomeTests/Feature12Prompt6WatchSmartStackHardeningTests` (pass; focused watch regression slice)
- Watch/widget schemes and targets used: `SuggestMeSomeWatch` / `SuggestMeSomeWatch`, `SuggestMeSomeWatchWidget` / `SuggestMeSomeWatchWidget`
- Bug fixes:
  - reviewed post-Prompt 6 watch-fix follow-up work in `a5ae20a`, `8f7734e`, `8ef77e7`, and `0c74c9b`
  - locked in the rule that the iPhone remains source of truth for persisted workout state, while the watch may render an optimistic next-set UI only as a temporary presentation layer
  - made watch set editing watch-local until explicit `Complete Set`; delayed or stale Crown tick actions are ignored on iPhone so they cannot mutate the wrong set after progression
  - introduced `WatchCurrentSetPresentationPolicy` in `SuggestMeSome/Models/WatchPayloadContracts.swift` so the watch keeps a stable displayed set cursor, ignores same-set refresh regressions, detects when phone progress has actually caught up, and suppresses stale behind-phone contexts when a fresher live snapshot exists
  - updated `SuggestMeSomeWatch/WatchActiveWorkoutView.swift` so `Complete Set` creates an optimistic next-set card, shows an explicit syncing state while the phone saves, waits for phone confirmation before unlocking the next controls, and clears end-of-exercise waiting when the next exercise truly arrives
  - taught the watch UI to use `WatchLiveWorkoutSnapshot` as a valid catch-up signal when `currentSessionContext` lags, which fixes the "iPhone is saving the last set" dead-end caused by live progress arriving ahead of the context payload
  - fixed the "Preparing first set…" regression by ensuring the watch never blanks its only usable `currentContext` while filtering stale refreshes; stale phone context can no longer overwrite a better displayed state, but the only interactive context is still rendered
  - hardened watch-to-phone execution transport in `SuggestMeSomeWatch/WatchCompanionSessionStore.swift` so execution actions are always queued durably with `transferUserInfo`, even when reachability is currently live
  - hardened phone-to-watch transport in `SuggestMeSome/Services/Watch/WatchCompanionBridge.swift` by mirroring live workout, current-session, and completion payloads over `sendMessage` when reachable while still keeping `updateApplicationContext` as the durable latest-state channel
  - cached and replayed the latest launch, progress, live workout, current-session context, Today Plan, and completion payloads on the iPhone bridge so watch reactivation/reachability changes can rebuild the active screen instead of falling back to stale or incomplete state
  - updated `SuggestMeSome/Services/Watch/WatchSessionCoordinator.swift` to rebroadcast authoritative active-session state even after ignored/stale watch actions, letting the watch recover cleanly from optimistic divergence
  - updated `SuggestMeSome/Views/DailyCoach/DailyCoachView.swift` to republish Today Plan snapshots only when the watch-facing signature changes, keeping the watch surface warm without spamming duplicate payloads
  - expanded focused regression coverage in `SuggestMeSomeTests/Feature12Prompt4WatchActionsTests.swift` and `SuggestMeSomeTests/Feature12Prompt6WatchSmartStackHardeningTests.swift` for delayed tick rejection, optimistic-vs-phone catch-up, live-snapshot catch-up, stale-context suppression, and post-ignore rebroadcast recovery
  - files edited across the follow-up fixes:
    - `SuggestMeSome/Models/WatchPayloadContracts.swift`
    - `SuggestMeSome/Services/ActiveWorkoutSessionStore.swift`
    - `SuggestMeSome/Services/Watch/WatchCompanionBridge.swift`
    - `SuggestMeSome/Services/Watch/WatchSessionCoordinator.swift`
    - `SuggestMeSome/Views/DailyCoach/DailyCoachView.swift`
    - `SuggestMeSomeWatch/WatchActiveWorkoutView.swift`
    - `SuggestMeSomeWatch/WatchCompanionSessionStore.swift`
    - `SuggestMeSomeTests/Feature12Prompt4WatchActionsTests.swift`
    - `SuggestMeSomeTests/Feature12Prompt6WatchSmartStackHardeningTests.swift`
  - focused validation/build/tests run during the bug-fix follow-up:
    - `xcodebuild test -project SuggestMeSome.xcodeproj -scheme SuggestMeSome -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SuggestMeSomeTests/Feature10Prompt7WatchFoundationTests -only-testing:SuggestMeSomeTests/Feature11Prompt5WatchContinuityTests -only-testing:SuggestMeSomeTests/Feature12Prompt6WatchSmartStackHardeningTests CODE_SIGNING_ALLOWED=NO` (pass)

---



### Feature 13 — Structured Block Payoff Layer

**Status:** Complete

---

#### Prompt 1 [Mesocycle Review Domain Foundation] — 2026-04-16

- Added non-persisted completed-block payoff types in `MesocycleReviewTypes.swift` so the app can represent:
  - mesocycle review snapshots with stable IDs
  - headline metrics for planned vs completed sessions, adherence, workout totals, PRs, and exercise consistency
  - performance highlights, friction signals, phase recap rows, ranked next-block recommendations, and editable next-block prefill payloads
  - recommendation decision placeholders (`pending`, `accepted`, `declined`) without introducing new mutable cross-object persistence
- Added `MesocycleReviewService.swift` as a deterministic, pure analytics builder for completed `ProgramRun`s:
  - builds a review from finished run data, linked program workouts, relevant standalone workouts inside the block window, and PR history
  - exposes explainable helpers for planned vs completed sessions, adherence percentage, workout duration totals, PR summary, exercise consistency, standalone-workout influence, movement-pattern counts, and simple lift highlights
  - keeps standalone workouts conservative by counting them toward continuity/workload context while explicitly excluding them from planned-session adherence
  - generates a coaching-style narrative summary plus a ranked recommendation list with editable prefilled generator inputs
- Extended shared seams without shipping new UI:
  - `TrainingContextQueryService` now exposes completed-run mesocycle review eligibility, relevant standalone workout lookup, and a review snapshot builder for later Today Plan / Training Programs surfaces
  - `AIProgramGeneratorView` now accepts an optional Feature 13 prefill so later prompts can start next-block generation from editable ranked-recommendation context instead of an instant one-tap generate path
- Added focused validation in `Feature13Prompt1MesocycleReviewTests.swift` covering:
  - completed-run review construction
  - duplicate-session adherence handling
  - conservative standalone influence behavior
  - empty-data completed-run edge cases

**Commit:** `feat: add mesocycle review domain foundation`

---

#### Prompt 2 [Mesocycle Review UI] — 2026-04-16

- Added `MesocycleReviewView.swift` with all required post-block review sections:
  - header: block name, date range, completion/focus/level/model capsule badges
  - headline metrics row: four `MesocycleMetricTile` tiles (adherence %, sessions ratio, new PRs, avg session duration)
  - "What Improved" section: icon-led highlight rows (hidden when empty)
  - "What Held You Back" section: icon-led friction rows with severity badges (hidden when empty)
  - expandable phase breakdown with chevron animation, per-phase completion ratio badges
  - coach-tone narrative summary card
  - ranked next-block recommendation card with rationale bullets; reserved "View Next Block" CTA stub-opens `AIProgramGeneratorView`
  - bottom CTA bar (Close + View Next Block) matching `ProgramReviewView`'s action bar pattern
  - `MesocycleReviewSnapshot.mock` static property for previews and stubs
- Added manual navigation hook in `ProgramRunExpandableRow.expandedContent` — "Block Review" row appears only for completed runs, matching `adaptationHistoryRow` visual style
- Added auto-present hook in `WorkoutView`:
  - captures `wasAlreadyComplete` before save; after `WorkoutSaveCoordinator` returns, detects newly-completed blocks via `!wasAlreadyComplete && run.isCompleted`
  - presents `MesocycleReviewView` as a sheet with `onDismiss: { dismiss() }` — no change to the PR celebration path; `dismissCelebration()` routes through the block review when the block just completed

**Commit:** `feat: add mesocycle review UI with auto and manual presentation hooks`

---

#### Prompt 3 [Ranked Next Block Recommendations and Prefill Context] — 2026-04-16

- Added `NextBlockRecommendationEngine.swift` as a deterministic backend for post-block follow-up planning:
  - returns a ranked list of 2–3 next-block recommendations instead of a single answer
  - marks one primary recommendation explicitly and keeps all recommendations in a `pending` state until the user chooses to generate from the editable defaults
  - scores continuity, productive pivots, consistency rebuilds, and conditioning-biased options from explainable inputs including adherence, missed sessions, PR/lift progress, current focus family, and conservative standalone-workout influence
  - degrades gracefully to broader focuses such as `generalFitness` or `fullBody` when the completed block does not provide enough specific signal
- Expanded Feature 13 payoff-layer types in `MesocycleReviewTypes.swift`:
  - replaced the narrow next-block prefill payload with `NextBlockPrefillContext` while preserving `MesocycleNextBlockPrefill` compatibility
  - added editable carry-forward context for suggested focus/style, duration, sessions/week, level, notable exercises to preserve, rationale text, carried 1RM/intensity context, and per-field provenance metadata (`recommendation` vs `carryForwardHistory`)
  - added recommendation fit metadata (`isPrimaryRecommendation`, `fitScore`, `fitNote`, `requiresExplicitAcceptance`) so later UI can explain and confirm choices before applying anything
- Integrated the richer prefill into existing generation seams without breaking current flows:
  - `ProgramGenerationInput` now accepts optional `carryForwardContext`
  - `AIProgramGeneratorView` passes the carried recommendation context into the existing program-generation flow
  - `MesocycleReviewService` now builds ranked recommendations through the dedicated engine and uses the engine’s richer primary prefill as the default next-block handoff
  - `MesocycleReviewView` now opens `AIProgramGeneratorView` with the primary editable prefill instead of a blank generator state
- Added focused validation in `Feature13Prompt3NextBlockRecommendationEngineTests.swift` covering:
  - strong hypertrophy-style outcomes ranking a strength-oriented follow-up first
  - low-adherence cases rebuilding consistency with mapped carry-forward generator context
  - standalone conditioning influence adding a ranked option conservatively without displacing stronger continuity recommendations

**Commit:** `feat: add next block recommendation engine and prefill context`

---

#### Prompt 4 [Ranked Recommendations and Editable Prefill UI] — 2026-04-16

- Added `NextBlockRecommendationCard.swift` as a reusable card component with two styles:
  - `.primary`: featured top-rank card with "Recommended" capsule, title, summary, fit-score chip ("Strong fit" / "Good fit" / "Alt path"), focus/duration/sessions/level badge row, and bulleted rationale
  - `.secondary`: compact row with rank badge (`#2`, `#3`), title, summary, focus pill, and fit chip — tappable to reveal the same editable prefill sheet
  - conforms `MesocycleNextBlockRecommendation` to `Identifiable` via its existing `stableID`
- Added `NextBlockPrefillReviewSheet.swift` for explicit-confirmation entry into generation:
  - "Why this is recommended" header with the recommendation title, summary, and rationale bullets
  - "Carried Forward" section rendering style / intensity / notable PR lifts / preserved exercise-name badges via a lightweight `FlowLayout`, plus the carry-forward rationale text
  - "Program Shape" editable rows: focus menu, level segmented picker, duration pills (6/8/10/12 w), sessions/week pills (2–6, honoring `FocusTemplateLibrary.minimumFrequency`)
  - "Starting 1RMs" list: per-exercise numeric TextField + unit segmented picker, seeded from `NextBlockPrefillContext.oneRepMaxSuggestions`, with the original `sourceSummary` shown as helper copy
  - right-aligned "Recommended" vs "Edited" capsule on every editable row so the user can see at a glance which defaults they have diverged from
  - safe decline ("Not now" + "Cancel") and explicit "Continue" CTA bar styled after `MesocycleReviewView`'s bottom actions — only "Continue" advances into generation
  - rebuilds a `NextBlockPrefillContext` on confirm that preserves the original source / recommendation IDs, rationale, value-source audit trail, intensity context, preserved exercise names, and notes so the carry-forward provenance is not lost during edits
- Integrated into `MesocycleReviewView`:
  - `MesocycleNextBlockSection` now renders the full ranked list — primary card first, then a "More options" subheader with the rest as `.secondary` cards; each card's tap bubbles up through an `onSelect` closure
  - added `@State selectedRecommendation` / `confirmedPrefill` and presents `NextBlockPrefillReviewSheet` via `.sheet(item:)` when a card is selected
  - the existing bottom "View Next Block" CTA now seeds `selectedRecommendation = recommendations.first` so both entry points funnel through the editable review sheet; the empty-recommendation case still falls back to the generator with `defaultNextBlockPrefill`
  - `.fullScreenCover` for `AIProgramGeneratorView` is now only presented after confirm, passing `confirmedPrefill ?? snapshot.defaultNextBlockPrefill`
  - decline path (sheet Cancel / "Not now") clears the selection without starting generation — `MesocycleRecommendationDecision` persistence is stubbed with an inline `// TODO` for a later prompt so accepted/declined paths remain representable in the UI without half-shipping a logger
- No changes to the `AIProgramGeneratorView.init(prefill:)` seam — the sheet reuses the existing injection contract, so the editable flow is purely additive and the current AI generation / program-review flow still works unchanged from `TrainingProgramsTab`.

**Commit:** `feat: add ranked next-block recommendation picker and editable prefill sheet`

---

#### Prompt 5 [Block Continuity Logging and Long-Horizon Summaries] — 2026-04-16

- Extended `ProgramRun` with additive continuity storage:
  - `previousProgramRunStableID` to link the next block back to the completed source block using a stable ID instead of a fragile object reference
  - `recommendationDecisionHistoryJSON` to persist the completed block's recommendation catalog plus accepted/declined decision events without mutating the underlying review snapshot types
  - `continuitySnapshotJSON` to copy the accepted continuity payload onto the next `ProgramRun` so block-to-block context survives after generation and remains sync-friendly
- Added `ProgramRunContinuityTypes.swift` with JSON-backed Codable snapshots for:
  - ranked recommendation snapshots
  - additive decision events with deterministic stable IDs (`recommendation::decision`)
  - carried-forward context, edited prefill snapshots, and edited-field tracking for future Today Plan / Daily Coach consumers
  - long-horizon summary payloads and insight rows
- Added `ProgramRunContinuityService.swift`:
  - records both declined and accepted next-block recommendation decisions on the completed source run
  - preserves the accepted carry-forward context and any edited fields from `NextBlockPrefillReviewSheet`
  - materializes the accepted continuity snapshot onto the new `ProgramRun` created from `ProgramReviewView`, including the previous-run stable ID link
- Added `LongHorizonAdaptationSummaryService.swift` and exposed it through `TrainingContextQueryService.longHorizonAdaptationSummary(...)`:
  - builds deterministic, readable insights across recent completed blocks
  - summarizes adherence trend, key-lift or movement continuity, tolerated weekly frequency, repeated missed-session patterns, and standalone-workout influence
  - degrades gracefully when there is only one completed block or no completed blocks yet
- Wired the smallest possible view hooks:
  - `MesocycleReviewView` now persists explicit accept/decline decisions when the user confirms or dismisses a recommendation
  - `ProgramReviewView.startProgram()` now copies accepted continuity into the newly created run when generation came from a carried-forward next-block prefill
- Updated sync-safe transport and merge behavior:
  - `ProgramRunSyncDTO`, sync mappers, local repository upsert logic, and conflict resolution now carry and merge the additive continuity JSON alongside existing run progress fields
  - continuity merge path unions recommendation events/catalog snapshots by stable ID instead of blindly overwriting the entire JSON blob
- Added focused tests in `Feature13Prompt5ContinuityAndLongHorizonTests.swift` covering:
  - declined + accepted decision logging on a completed block
  - continuity linking into the next run
  - multi-block readable summary generation with standalone conditioning influence
  - graceful single-block fallback behavior

**Commit:** `feat: add block continuity logging and long-horizon summaries`

---

### Feature 13 Prompt 6 — Continuity and Long-Horizon UI Surfaces

Exposed block continuity and multi-block trend information in Daily Coach as the primary home, with a lighter contextual card in the same view when the user is between blocks.

**New views:**
- `BlockContinuityCard` — horizontal strip showing up to 3 recent completed blocks → active block (or between-blocks state) → next block placeholder; "Review Last Block" CTA; teal accent for current block
- `LongHorizonSummaryCard` — multi-block headline from `LongHorizonAdaptationSummaryService`, up to 3 insight bullet rows (adherence trend, movement continuity, tolerated frequency, etc.), dual CTA bar ("Review Block" / "Generate Next Block"); indigo accent; hidden when no completed blocks exist

**DailyCoachView changes:**
- Added `@Query` for `completedRuns` (isCompleted == true) and `personalRecords`
- Added `isBetweenBlocks` and `longHorizonSummary` computed properties
- `betweenBlocksContextCard` — lighter contextual surface shown immediately after `todayTrainingCard` when user has no active program but has at least one completed block; orange accent; CTAs into review and generation flows
- `BlockContinuityCard` and `LongHorizonSummaryCard` inserted after `latestWeeklyReviewCard` as the primary Daily Coach long-horizon section
- Two new sheet states: `showingBlockReview` (presents `MesocycleReviewView(snapshot: .mock)` — wirable) and `showingNextBlockGenerator` (presents `AIProgramGeneratorView()`)

**Wired:** card layout, insight rendering, empty-state guards, between-blocks detection, sheet presentation for both review and generator flows
**Stubbed:** `MesocycleReviewView` still uses `.mock` snapshot — replace with `MesocycleReviewService.buildReview(for:)` when backend is ready

**Commit:** `feat: expose continuity and long-horizon trend UI in Daily Coach`

---

#### Prompt 7 [Feature 13 Integration Hardening and Regression Pass] — 2026-04-16

- Replaced the remaining Feature 13 `.mock` review seams with real completed-block analytics:
  - `WorkoutView` now auto-presents a real `MesocycleReviewView` snapshot after a program-ending workout
  - `TrainingProgramsTab` now opens manual block review with full workout + PR context, including standalone-workout influence
  - `DailyCoachView` now routes "Review Last Block" and long-horizon review actions through the latest completed real snapshot instead of placeholder data
- Hardened the end-of-block completion path:
  - resumed or restored program workouts now still detect newly completed runs correctly when saved
  - PR celebration flow keeps the existing UX, then presents the real block review only after the celebration dismisses
- Tightened next-block continuity handoff in Daily Coach:
  - between-block and long-horizon "Generate Next Block" entry now opens `AIProgramGeneratorView(prefill:)` with the latest completed block's default carry-forward context instead of a blank generator
  - long-horizon summary selection now routes through `TrainingContextQueryService.longHorizonAdaptationSummary(...)` to reduce glue duplication
- Added focused query helpers and regression coverage:
  - `TrainingContextQueryService` now exposes latest-completed-run review helpers plus a shared workout fetch helper
  - `Feature13Prompt5ContinuityAndLongHorizonTests.swift` now verifies latest completed block selection and review construction
- This hardening pass builds directly on:
  - Feature 10's sync-stable run identity, which keeps review and continuity linking deterministic
  - Feature 11's Daily Coach / Today Plan surfaces, which now behave as a coherent handoff into Feature 13 payoff flows

**Commit:** `fix: harden feature 13 review and continuity flows`

---

#### Prompt 8 [Backend Scalability Hardening Pass] — 2026-04-16

- Added backend persistence and compatibility guardrails:
  - `PersistenceMaintenanceCoordinator` now records schema version state at startup and runs sync-metadata audits before deeper backend expansion
  - continuity and watch payload storage now decode through version-aware envelopes while preserving legacy payload compatibility
- Unified backend read seams behind typed snapshots:
  - `TrainingReadRepository` now serves shared history, coach, recommendation, and adaptive proposal snapshots so continuity, recommendation, and adaptive services stop re-fetching overlapping context independently
  - adaptive weekly proposal services now work from one run-scoped snapshot instead of repeated full-table fetches
- Hardened non-UI write and session boundaries:
  - `WorkoutSaveCoordinator` now separates primary persistence from post-save side effects and returns structured non-fatal failure reporting for adaptive analysis, completion updates, and HealthKit writeback scheduling
  - active workout session persistence now uses a dedicated versioned store, and watch execution replay runs through a pure reducer with duplicate-action protection
- Added focused backend regression coverage for:
  - persistence/schema maintenance and sync-metadata repair
  - continuity/watch codec compatibility
  - read snapshot scoping and bounded adaptive history loading
  - workout save durability and HealthKit writeback scheduling
  - active session restore and duplicate watch-action handling
- This pass builds directly on:
  - Feature 10's sync-ready contracts and query-layer hardening
  - Feature 11's execution-flow foundation, which now rides on a safer workout save pipeline
  - Feature 12's watch execution transport seams, which now sit behind stronger persistence and replay boundaries

**Commits:** `refactor: add persistence maintenance safeguards`, `refactor: unify training read snapshots`, `refactor: harden workout save and session persistence`, `refactor: consolidate adaptive read snapshots`

---

#### Prompt 9 [Backend Scalability Domain Extractions] — 2026-04-16

- Split the next backend growth seams behind stable public APIs:
  - `SessionOutcomeInferenceService` now acts as a thin orchestration layer while history loading, score/input building, and scoring math live in focused helpers
  - standalone outcome inference now loads only prior workouts for baseline history instead of fetching all `ExerciseEntry` rows and filtering in memory
  - `LiftTrendTrackingService` now delegates scoped analysis loading, trend-point normalization, metric computation, and persistence to focused helpers instead of one monolithic file
  - `LocalSyncRepository` now stays as the facade while workout, program, coach, adaptive, and HealthKit summary sync logic live in domain-specific stores backed by shared sync-store utilities
  - `HealthKitWorkoutImportService` now separates HealthKit workout querying, sample-to-snapshot mapping, and imported-workout persistence
  - `HealthKitRecoverySyncService` now separates windowing, concurrent HealthKit metric fetching, daily snapshot assembly, and summary upsert persistence
- Added focused regression coverage for the new backend boundaries:
  - session outcome inference now verifies future workouts cannot leak into standalone baseline scoring
  - lift-trend tracking now proves scoped program-run isolation
  - sync repository tests now cover program/adaptive graph linking plus coach and HealthKit summary upserts
  - HealthKit import tests now verify re-import preserves the original import timestamp while still marking sync updates
  - HealthKit recovery tests now verify the latest source-update timestamp is persisted across updates
- This extraction pass keeps current app behavior intact while making future backend scaling safer:
  - outcome inference now scales with workout history more safely and is easier to evolve without touching persistence, history loading, and scoring rules together
  - adaptive history reads are more intentionally scoped
  - sync growth no longer funnels through one all-purpose repository file
  - HealthKit import and recovery rules can evolve without bloating their service entrypoints

**Commits:** `refactor: split session outcome inference service`, `refactor: split lift trend tracking service`, `refactor: split local sync repository`, `refactor: split healthkit workout import service`, `refactor: split healthkit recovery sync service`

---

#### Prompt 10 [History Deletion and Personal Record Cleanup] — 2026-04-16

- Hardened deletion flows so personal records stay consistent with the remaining workout history:
  - workout deletion now routes through `PersonalRecordMaintenanceService`, which rebuilds affected PR rows from the surviving workouts instead of leaving deleted-workout records behind
  - the main workout history delete flow and Settings date-range deletion now share the same PR rebuild path
  - full PR wipe support is now available from `PersonalRecordsView`, clearing both `PersonalRecord` rows and any `SetEntry.isPR` markers
- Added completed program history deletion for structured blocks:
  - completed runs in `TrainingProgramsTab` can now be deleted from history
  - `TrainingHistoryDeletionService` removes the completed run, its linked workouts, and run-scoped adaptive and Daily Coach artifacts before rebuilding affected PRs
- Added focused backend regression coverage for:
  - deleting a workout and falling back to the next-valid PR
  - deleting completed program history while removing run-scoped artifacts
  - wiping all PR data and resetting saved-set PR flags

**Commit:** `fix: harden history deletion and PR cleanup`

---

#### Prompt 11 [HealthKit Refresh and Watch Companion Stability] — 2026-04-17

- Stabilized Daily Coach HealthKit recovery refresh behavior:
  - added a guarded foreground/Daily Coach auto-refresh coordinator that bootstraps the first 90-day sync, refreshes the last 30 days on app activation, and retries later in the day when current-day comparable metrics are still missing
  - split recovery sync timestamps from workout import timestamps, added a legacy recovery timestamp migration path, and updated Daily Coach explanation text so baseline mode now distinguishes disabled, not-yet-synced, insufficient-baseline, and awaiting-current-day-metrics states
  - refreshed Health Data settings copy to reflect recovery sync state and the new auto-refresh behavior without removing the manual 90-day sync fallback
- Hardened Apple Watch companion presence and replay handling:
  - made phone-side watch status activation-aware, added a pending/connecting state, and preserved last confirmed companion evidence during transient `WCSession` churn
  - added a lightweight `watchPresenceHeartbeat` payload so the watch confirms presence on activation and when the watch app becomes active, allowing the phone to record last watch contact and replay the latest Today Plan/live workout payloads even after a stale “not installed” read
  - removed the stale “coming soon” copy from Health Data settings and replaced it with live watch status messaging plus debug transport details for activation, pairing, install, reachability, last contact, and last replay
- Added focused regression coverage for:
  - HealthKit auto-refresh policy decisions and objective recovery evaluation states
  - watch heartbeat payload round-trips, pending/inactive status resolution, evidence retention, and replay fallback after transient install-state misreads

**Commit:** `fix: stabilize healthkit refresh and watch companion status`

---

#### Prompt 12 [Backend Read-Path Derisking and Incremental Sync Optimization] — 2026-04-17

- Reduced backend maintenance cost at startup:
  - `PersistenceMaintenanceCoordinator` now gates the sync-metadata audit so it still runs on first launch, after schema changes, or once per day, instead of paying a full-table audit on every app start
  - added debug-only startup maintenance timing logs so device validation can confirm when the audit runs, how long it took, and how many rows were touched
- Made incremental sync exports actually incremental:
  - workout, program, adaptive, Daily Coach, and HealthKit summary sync stores now fetch with typed SwiftData `since` predicates and descriptor sort order instead of loading whole tables and filtering/sorting in memory
  - added debug-only export timing/count logs for each sync domain so we can measure payload size and elapsed time during device sync validation
- Tightened remaining backend full-table lookup paths without changing behavior:
  - HealthKit imported-workout upserts now prefilter to rows that already carry external identifiers before building the dedupe map
  - weekly review upserts now look up an existing review by `sourceWeeklyAnalysisIDText` with a targeted predicate instead of scanning every review row
- Added focused regression coverage for:
  - startup audit gating and once-per-day rerun behavior
  - incremental `since` fetches across workout, program, adaptive, Daily Coach, and HealthKit sync domains
  - preserved imported-workout dedupe/update behavior and weekly review upsert stability

**Commits:** `refactor: gate startup sync audit`, `refactor: optimize incremental sync exports`

---

### Feature 14 — Compliance and updates for monetization

**Status:** In Progress

#### Prompt 1 [Paid App Compliance and Monetization Hardening] — 2026-04-17

- Added a paid-app compliance and monetization foundation:
  - introduced a dedicated `Compliance` module with centralized placeholder-backed legal configuration, versioned in-app documents, onboarding acceptance tracking, and a reusable legal/privacy center
  - added StoreKit 2 support for a one-time `Premium Unlock` purchase with cached entitlement reads, restore purchases, and a single feature-access policy used across premium routes
- Hardened premium gating without breaking the free logger:
  - gated Daily Coach, Dashboard analytics, smart generation, training programs, Apple Health, and Apple Watch continuity behind polished paywall shells instead of dead-end screens
  - preserved free access to manual workout logging, editing, history, export, delete-local-data flows, legal/privacy surfaces, support, and Restore Purchases
  - added Apple Health pre-permission disclosure, an “About This Guidance” surface, premium-aware watch messaging, and user-facing copy updates that replace unsupported AI wording with smart/adaptive guidance language
- Added focused compliance validation:
  - covered entitlement resolution, onboarding completion requirements, persisted legal-document acceptance, cached Premium Unlock restoration, and Apple Health disclosure/copy expectations
  - re-ran the Feature 14 monetization suite plus targeted Feature 8/11/12/13 regression coverage, followed by a full iOS build with the embedded watch target

**Commits:** `feat: add paid compliance and premium gating`, `fix: harden paid compliance messaging and validation`

---

#### Prompt 2 [Offer Code Redemption and Developer Premium Toggle] — 2026-04-17

- Added in-app premium redemption support that stays inside Apple’s purchase flow:
  - surfaced a `Redeem Offer Code` action on the premium paywall and in Settings so testers and future customers can open Apple’s system redemption sheet directly from the app
  - refreshed premium status after the redemption sheet closes so a successful code redemption can activate `Premium Unlock` without requiring users to hunt for a separate restore step
- Added a debug-only premium override for local development builds:
  - `PurchaseManager` now supports a persistent debug entitlement override that survives app relaunches on Xcode-installed builds without pretending to be a real App Store purchase
  - Settings now exposes a developer-only toggle that lets local builds switch cleanly between free and premium behavior on device for testing gated flows
- Added focused validation for:
  - the debug premium override lifecycle, including persistence across relaunch and clean fallback to the free tier when the override is turned back off

**Commit:** `feat: add premium redemption and debug override`

---

#### Prompt 3 [Onboarding Age Disclosure Tone Refinement] — 2026-04-17

- Softened the onboarding age-confirmation slide so it reads like a standard fitness-app eligibility note instead of an adult-content gate:
  - replaced the `Adults 18+` title with `Training eligibility`
  - updated the slide body to frame the requirement as independent adult training use while still clearly confirming that the user is `18 or older`
- Preserved the stricter legal language in the formal Terms content:
  - kept the exact `intended for adults age 18 and older` wording in the legal document copy so the user-facing onboarding tone can improve without weakening the compliance posture
- Added focused regression coverage for:
  - distinct onboarding-versus-legal age copy so future compliance edits do not accidentally collapse the softer intro wording back into the stricter legal phrasing

**Commit:** `refactor: soften onboarding age disclosure`

---

#### Prompt 4 [Individual Seller Readiness] — 2026-04-17

- Switched the compliance/release posture from `organization required` to `individual seller ready`:
  - removed the built-in release gate that required converting the Apple Developer membership to an organization account before launch
  - updated the compliance configuration to use an individual seller placeholder instead of an LLC-style legal-entity placeholder
- Refined the legal and support copy to match the individual-publisher route:
  - privacy, support, and placeholder warnings now refer to the app’s `seller` rather than a `company`
  - the support document now previews `Seller` details instead of `Company` details
- Updated the release checklist for the individual route:
  - added explicit reminders that the App Store seller name will be the developer’s legal personal name
  - added an EU-focused DSA reminder so individual distribution decisions are reviewed before launch
- Added regression coverage for:
  - the individual-seller configuration default and the new release-checklist language

**Commit:** `refactor: make compliance individual-seller ready`

---

#### Prompt 5 [Seller Placeholder Personalization] — 2026-04-17

- Replaced the individual-seller name placeholder with `Alexander Yao`:
  - compliance-generated privacy, support, and legal previews now use `Alexander Yao` anywhere the seller name placeholder is interpolated
- Added focused regression coverage for:
  - the shared compliance configuration continuing to expose `Alexander Yao` as the seller placeholder value

**Commit:** `refactor: personalize seller placeholder name`

---

#### Prompt 6 [Watch App Icon Adoption] — 2026-04-17

- Added a Watch app icon that matches the iPhone app branding:
  - created a dedicated watchOS `AppIcon` asset set in the Watch target and reused the existing 1024px phone artwork so the companion app now has an icon in Xcode and builds with a valid watch icon source
  - updated the `SuggestMeSomeWatch` target build settings so both Debug and Release configurations use the new Watch asset catalog icon

**Commit:** `feat: add watch app icon`

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
