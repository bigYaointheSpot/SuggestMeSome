import Foundation

struct ProgramGenerationWeeklySummaryReporter {
    private let loadEstimator = ProgramGenerationLoadEstimator()

    func weeklySummary(for program: TrainingProgram) -> [ProgramGeneratedWeekSummary] {
        program.weeks
            .sorted(by: { $0.weekNumber < $1.weekNumber })
            .map { week in
                var totalMuscleSets = loadEstimator.emptyMuscleTotals()
                var totalFatigue = 0.0

                let sessionSummaries = week.sessions
                    .sorted(by: { $0.sessionNumber < $1.sessionNumber })
                    .map { session -> ProgramGeneratedSessionSummary in
                        var sessionMuscleSets = loadEstimator.emptyMuscleTotals()
                        var sessionFatigue = 0.0

                        for exercise in session.exercises.sorted(by: { $0.orderIndex < $1.orderIndex }) where !exercise.isWarmup {
                            let estimate = loadEstimator.estimateLoad(for: exercise)
                            loadEstimator.addMuscleSets(estimate.hardSetsByMuscle, into: &sessionMuscleSets)
                            sessionFatigue += estimate.fatigueScore
                        }

                        loadEstimator.addMuscleSets(sessionMuscleSets, into: &totalMuscleSets)
                        totalFatigue += sessionFatigue

                        return ProgramGeneratedSessionSummary(
                            sessionNumber: session.sessionNumber,
                            sessionName: session.sessionName,
                            hardSetsByMuscle: sessionMuscleSets,
                            fatigueScore: sessionFatigue
                        )
                    }

                return ProgramGeneratedWeekSummary(
                    weekNumber: week.weekNumber,
                    sessionSummaries: sessionSummaries,
                    totalHardSetsByMuscle: totalMuscleSets,
                    totalFatigueScore: totalFatigue
                )
            }
    }

    func debugWeeklySummary(for program: TrainingProgram) -> String {
        let weeks = weeklySummary(for: program)
        guard !weeks.isEmpty else { return "No weeks found." }

        return weeks.map { week in
            var lines: [String] = []
            lines.append("Week \(week.weekNumber) — total fatigue \(formatOneDecimal(week.totalFatigueScore))")
            for session in week.sessionSummaries {
                let nameSuffix = session.sessionName.map { " (\($0))" } ?? ""
                lines.append("  Session \(session.sessionNumber)\(nameSuffix): fatigue \(formatOneDecimal(session.fatigueScore))")
                for muscle in ProgramVolumeMuscle.allCases {
                    let sets = session.hardSetsByMuscle[muscle] ?? 0
                    guard sets > 0 else { continue }
                    lines.append("    \(muscle.displayName): \(formatOneDecimal(sets)) hard sets")
                }
            }
            lines.append("  Weekly totals:")
            for muscle in ProgramVolumeMuscle.allCases {
                let total = week.totalHardSetsByMuscle[muscle] ?? 0
                guard total > 0 else { continue }
                lines.append("    \(muscle.displayName): \(formatOneDecimal(total))")
            }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    func stampPlannedFatigueSummaries(on program: TrainingProgram) {
        let byWeek = Dictionary(uniqueKeysWithValues: weeklySummary(for: program).map { ($0.weekNumber, $0) })
        for week in program.weeks {
            guard let summary = byWeek[week.weekNumber] else { continue }
            week.plannedFatigueScore = summary.totalFatigueScore
            let bySession = Dictionary(uniqueKeysWithValues: summary.sessionSummaries.map { ($0.sessionNumber, $0) })
            for session in week.sessions {
                session.plannedFatigueScore = bySession[session.sessionNumber]?.fatigueScore
            }
        }
    }

    private func formatOneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
