# SuggestMeSome - Workout Tracker

## Architecture
- SwiftUI + SwiftData

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

## Release Notes
After each completed feature prompt, append a summary entry 
to README.md under a "## Changelog" section using this format:

### [Feature Name] — [Date]
- What was built
- New models/files added
- Any known limitations