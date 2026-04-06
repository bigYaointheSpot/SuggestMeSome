# SuggestMeSome - Workout Tracker

## Architecture
- SwiftUI + SwiftData
- Models: MuscleGroup → Exercise → Workout → ExerciseEntry → SetEntry
- PersonalRecord is a separate table (one per exercise per rep count)

## Key Decisions
- Duration stored as seconds, displayed as hh:mm:ss
- Weight unit (lbs/kg) set per ExerciseEntry, not global
- PR detection is automatic on save (compares by exercise + rep count)
- Timer uses stored startTime, not a background counter
- Cascade delete on Workout → ExerciseEntry → SetEntry

## Conventions
- Use conventional commits: feat:, fix:, refactor:, docs:
- Commit after completing each logical unit of work
- Do not push to remote unless asked