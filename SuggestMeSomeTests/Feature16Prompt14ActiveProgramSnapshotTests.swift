import Foundation
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature16Prompt14ActiveProgramSnapshotTests {

    @Test func dashboardRefreshCachesScopedProgramProgressForActiveRun() throws {
        let viewModel = DashboardViewModel()
        let program = TrainingProgram(
            name: "Active Block",
            lengthInWeeks: 4,
            sessionsPerWeek: 2,
            createdDate: Date(),
            source: .aiGenerated
        )
        let run = ProgramRun(startDate: Date())
        run.program = program

        viewModel.refresh(
            workouts: [
                makeWorkout(run: run, date: daysAgo(3), weekNumber: 1, sessionNumber: 1),
                makeWorkout(run: run, date: daysAgo(2), weekNumber: 1, sessionNumber: 2),
                makeWorkout(run: run, date: daysAgo(1), weekNumber: 2, sessionNumber: 1),
                makeWorkout(run: nil, date: daysAgo(1), weekNumber: nil, sessionNumber: nil),
            ],
            activeProgramRuns: [run],
            allPRs: [],
            exercises: [],
            weeklyAnalyses: [],
            liftTrends: [],
            allProposals: [],
            trainingStateSnapshot: nil,
            healthKitInsight: nil
        )

        let snapshot = try #require(viewModel.activeProgramProgressSnapshot(for: run))
        #expect(snapshot.completedWorkoutCount == 3)
        #expect(snapshot.totalSessions == 8)
        #expect(snapshot.completedWorkoutCount(inWeek: 1) == 2)
        #expect(snapshot.completedWorkoutCount(inWeek: 2) == 1)
        #expect(snapshot.nextIncompleteSession == ProgramNextSessionReadSnapshot(
            weekNumber: 2,
            sessionNumber: 2
        ))
    }

    @Test func dashboardRefreshDoesNotCreateProgramProgressForInactiveRuns() {
        let viewModel = DashboardViewModel()
        let activeRun = makeRun(name: "Active", weeks: 3, sessionsPerWeek: 2)
        let inactiveRun = makeRun(name: "Inactive", weeks: 3, sessionsPerWeek: 2)

        viewModel.refresh(
            workouts: [makeWorkout(run: activeRun, date: daysAgo(1), weekNumber: 1, sessionNumber: 1)],
            activeProgramRuns: [activeRun],
            allPRs: [],
            exercises: [],
            weeklyAnalyses: [],
            liftTrends: [],
            allProposals: [],
            trainingStateSnapshot: nil,
            healthKitInsight: nil
        )

        #expect(viewModel.activeProgramProgressSnapshot(for: activeRun)?.completedWorkoutCount == 1)
        #expect(viewModel.activeProgramProgressSnapshot(for: inactiveRun) == nil)
    }

    private func makeRun(
        name: String,
        weeks: Int,
        sessionsPerWeek: Int
    ) -> ProgramRun {
        let program = TrainingProgram(
            name: name,
            lengthInWeeks: weeks,
            sessionsPerWeek: sessionsPerWeek,
            createdDate: Date(),
            source: .aiGenerated
        )
        let run = ProgramRun(startDate: Date())
        run.program = program
        return run
    }

    private func makeWorkout(
        run: ProgramRun?,
        date: Date,
        weekNumber: Int?,
        sessionNumber: Int?
    ) -> Workout {
        Workout(
            date: date,
            startTime: date,
            durationSeconds: 1_800,
            programRun: run,
            programWeekNumber: weekNumber,
            programSessionNumber: sessionNumber
        )
    }

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    }
}
