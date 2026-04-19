import Foundation
import SwiftData
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature16Prompt13ProgramRunProgressTests {

    @Test func progressSnapshotBuildsTotalsNextSessionAndLookupFromScopedWorkouts() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let run = makeRun(
            stableID: "prompt-13-run",
            startOffset: 0,
            weeks: 2,
            sessionsPerWeek: 2
        )
        context.insert(run.program!)
        context.insert(run)

        let initialSession = makeWorkout(
            run: run,
            date: day(0),
            weekNumber: 1,
            sessionNumber: 1
        )
        let repeatedSession = makeWorkout(
            run: run,
            date: day(1),
            weekNumber: 1,
            sessionNumber: 1
        )
        let laterSession = makeWorkout(
            run: run,
            date: day(2),
            weekNumber: 2,
            sessionNumber: 1
        )

        context.insert(initialSession)
        context.insert(repeatedSession)
        context.insert(laterSession)
        try context.save()

        let snapshot = TrainingReadRepository.programRunProgressSnapshot(
            for: run,
            context: context
        )

        #expect(snapshot.completedWorkoutCount == 3)
        #expect(snapshot.totalSessions == 4)
        #expect(snapshot.completedSessionKeys == Set([
            ProgramSessionCompletionKey(weekNumber: 1, sessionNumber: 1),
            ProgramSessionCompletionKey(weekNumber: 2, sessionNumber: 1),
        ]))
        #expect(snapshot.nextIncompleteSession == ProgramNextSessionReadSnapshot(
            weekNumber: 1,
            sessionNumber: 2
        ))
        #expect(snapshot.workout(weekNumber: 1, sessionNumber: 1)?.id == repeatedSession.id)
        #expect(snapshot.isCompleted(weekNumber: 2, sessionNumber: 1))
        #expect(!snapshot.isCompleted(weekNumber: 2, sessionNumber: 2))
    }

    @Test func progressSnapshotClearsNextSessionWhenRunIsFullyCompleted() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let run = makeRun(
            stableID: "prompt-13-complete",
            startOffset: -7,
            weeks: 1,
            sessionsPerWeek: 2
        )
        context.insert(run.program!)
        context.insert(run)

        context.insert(makeWorkout(
            run: run,
            date: day(-6),
            weekNumber: 1,
            sessionNumber: 1
        ))
        context.insert(makeWorkout(
            run: run,
            date: day(-4),
            weekNumber: 1,
            sessionNumber: 2
        ))
        try context.save()

        let snapshot = TrainingReadRepository.programRunProgressSnapshot(
            for: run,
            context: context
        )

        #expect(snapshot.totalSessions == 2)
        #expect(snapshot.nextIncompleteSession == nil)
    }

    private func makeRun(
        stableID: String,
        startOffset: Int,
        weeks: Int,
        sessionsPerWeek: Int
    ) -> ProgramRun {
        let program = TrainingProgram(
            name: "Block \(stableID)",
            lengthInWeeks: weeks,
            sessionsPerWeek: sessionsPerWeek
        )
        let run = ProgramRun(syncStableID: stableID, startDate: day(startOffset))
        run.program = program
        return run
    }

    private func makeWorkout(
        run: ProgramRun,
        date: Date,
        weekNumber: Int,
        sessionNumber: Int
    ) -> Workout {
        Workout(
            date: date,
            startTime: date,
            durationSeconds: 1_500,
            programRun: run,
            programWeekNumber: weekNumber,
            programSessionNumber: sessionNumber
        )
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            Workout.self,
            ProgramRun.self,
            TrainingProgram.self,
            ProgramWeekTemplate.self,
            ProgramSessionTemplate.self,
            ProgramSessionExercise.self,
            ExerciseEntry.self,
            SetEntry.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func day(_ offset: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let anchor = calendar.date(
            from: DateComponents(year: 2026, month: 1, day: 5, hour: 12, minute: 0, second: 0)
        ) ?? Date()
        return calendar.date(byAdding: .day, value: offset, to: anchor) ?? anchor
    }
}
