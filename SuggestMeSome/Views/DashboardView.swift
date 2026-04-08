//
//  DashboardView.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/7/26.
//

import SwiftUI
import SwiftData
import Charts

// MARK: - Time Window

enum DashboardTimeWindow: String, CaseIterable {
    case fourWeeks  = "4W"
    case threeMonths = "3M"
    case oneYear    = "1Y"
    case all        = "All"

    var startDate: Date? {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .fourWeeks:   return cal.date(byAdding: .weekOfYear, value: -4, to: now)
        case .threeMonths: return cal.date(byAdding: .month, value: -3, to: now)
        case .oneYear:     return cal.date(byAdding: .year, value: -1, to: now)
        case .all:         return nil
        }
    }
}

// MARK: - WeekBucket

private struct WeekBucket: Identifiable {
    var id: Date { monday }
    let monday: Date
    let count: Int
}

// MARK: - DashboardView

struct DashboardView: View {
    @Binding var selectedTab: Int

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Workout.date, order: .reverse) private var allWorkouts: [Workout]
    @Query(filter: #Predicate<ProgramRun> { run in run.isCompleted == false })
    private var activeProgramRuns: [ProgramRun]
    @Query(sort: \PersonalRecord.dateAchieved, order: .reverse) private var allPRs: [PersonalRecord]

    // MARK: Time window
    @State private var timeWindow: DashboardTimeWindow = .fourWeeks

    // MARK: Start workout dialog
    @State private var showingStartDialog = false

    // MARK: Empty workout navigation
    @State private var navigateToEmptyWorkout = false

    // MARK: Generator flow
    @State private var showingGeneratorSheet   = false
    @State private var generatorSheetType: WorkoutGenerationType = .fullBody
    @State private var pendingGeneratedWorkout: GeneratedWorkout?
    @State private var showingGeneratedWorkout = false

    // MARK: Program workout flow
    @State private var showingCompleteProgramSheet = false
    @State private var pendingProgramWorkout: ProgramWorkoutContext?
    @State private var showingProgramWorkout = false

    // MARK: Strength chart
    @State private var selectedLifts: Set<String> = ["Bench Press", "Squat", "Deadlift"]

    private let liftOptions: [(name: String, color: Color)] = [
        ("Bench Press",    .blue),
        ("Squat",          .green),
        ("Deadlift",       .orange),
        ("Overhead Press", .purple),
    ]

    // MARK: - Computed stats

    var filteredWorkouts: [Workout] {
        guard let cutoff = timeWindow.startDate else { return allWorkouts }
        return allWorkouts.filter { $0.date >= cutoff }
    }

    var workoutCount: Int { filteredWorkouts.count }

    var timeTrainedLabel: String {
        let total = filteredWorkouts.reduce(0) { $0 + $1.durationSeconds }
        let h = total / 3600
        let m = (total % 3600) / 60
        return "\(h)h \(m)m"
    }

    var prCount: Int {
        filteredWorkouts.reduce(0) { count, workout in
            count + workout.exerciseEntries.reduce(0) { $0 + $1.sets.filter(\.isPR).count }
        }
    }

    var streakWeeks: Int {
        let cal = Calendar.current
        guard var weekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start else { return 0 }
        var streak = 0
        for _ in 0..<200 {
            let weekEnd = cal.date(byAdding: .weekOfYear, value: 1, to: weekStart)!
            let hasWorkout = allWorkouts.contains { $0.date >= weekStart && $0.date < weekEnd }
            guard hasWorkout else { break }
            streak += 1
            weekStart = cal.date(byAdding: .weekOfYear, value: -1, to: weekStart)!
        }
        return streak
    }

    // MARK: - Chart data (strength)

    var strengthChartData: [ChartPoint] {
        StrengthAnalytics.chartPoints(
            for: Array(selectedLifts),
            from: allWorkouts,
            since: timeWindow.startDate
        )
    }

    var activeLiftData: [(lift: (name: String, color: Color), points: [ChartPoint])] {
        let data = strengthChartData
        return liftOptions
            .filter { selectedLifts.contains($0.name) }
            .map { lift in (lift: lift, points: data.filter { $0.exerciseName == lift.name }) }
    }

    // MARK: - Frequency chart data

    var workoutFrequencyBuckets: [WeekBucket] {
        let cal = Calendar.current
        let now = Date()

        let windowStart: Date
        if let c = timeWindow.startDate {
            windowStart = c
        } else if let earliest = allWorkouts.map(\.date).min() {
            windowStart = earliest
        } else {
            return []
        }

        let firstMonday = mondayOf(windowStart)
        let thisMonday  = mondayOf(now)

        var buckets: [WeekBucket] = []
        var weekStart = firstMonday
        while weekStart <= thisMonday {
            let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart)!
            let count = filteredWorkouts.filter { $0.date >= weekStart && $0.date < weekEnd }.count
            buckets.append(WeekBucket(monday: weekStart, count: count))
            weekStart = weekEnd
        }
        return buckets
    }

    var frequencyTarget: Double {
        let sortedRuns = activeProgramRuns.sorted { $0.startDate > $1.startDate }
        if let run = sortedRuns.first, let program = run.program {
            return Double(program.sessionsPerWeek)
        }
        let buckets = workoutFrequencyBuckets
        guard !buckets.isEmpty else { return 3 }
        let total = buckets.reduce(0) { $0 + $1.count }
        return Double(total) / Double(buckets.count)
    }

    private func mondayOf(_ date: Date) -> Date {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)  // 1=Sun, 2=Mon, …, 7=Sat
        let daysToMonday = (weekday + 5) % 7
        return cal.startOfDay(for: cal.date(byAdding: .day, value: -daysToMonday, to: date)!)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    startButton
                    timeWindowPicker
                    statsBar
                    prFeedSection
                    strengthChartSection
                    workoutFrequencySection
                    activeProgramSection
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
            // Empty workout destination
            .navigationDestination(isPresented: $navigateToEmptyWorkout) {
                WorkoutView()
            }
            // Generated workout destination
            .navigationDestination(isPresented: $showingGeneratedWorkout) {
                WorkoutView(generatedWorkout: pendingGeneratedWorkout)
            }
            // Program workout destination
            .navigationDestination(isPresented: $showingProgramWorkout) {
                if let pw = pendingProgramWorkout {
                    WorkoutView(programWorkout: pw)
                }
            }
            .confirmationDialog("Start Workout", isPresented: $showingStartDialog, titleVisibility: .visible) {
                Button("Start Empty Workout") {
                    navigateToEmptyWorkout = true
                }
                Button("SuggestMeSome") {
                    generatorSheetType = .fullBody
                    showingGeneratorSheet = true
                }
                if !activeProgramRuns.isEmpty {
                    Button("Program Workout") {
                        showingCompleteProgramSheet = true
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showingGeneratorSheet, onDismiss: {
                if pendingGeneratedWorkout != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showingGeneratedWorkout = true
                    }
                }
            }) {
                GeneratorSheetRootView(type: generatorSheetType) { gw in
                    pendingGeneratedWorkout = gw
                    showingGeneratorSheet = false
                }
            }
            .sheet(isPresented: $showingCompleteProgramSheet, onDismiss: {
                if pendingProgramWorkout != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showingProgramWorkout = true
                    }
                }
            }) {
                CompleteProgramWorkoutSheet(activeRuns: Array(activeProgramRuns)) { ctx in
                    pendingProgramWorkout = ctx
                    showingCompleteProgramSheet = false
                }
            }
        }
    }

    // MARK: - Start Button

    private var startButton: some View {
        Button {
            showingStartDialog = true
        } label: {
            Label("Start Workout", systemImage: "play.fill")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Time Window Picker

    private var timeWindowPicker: some View {
        Picker("Time Window", selection: $timeWindow) {
            ForEach(DashboardTimeWindow.allCases, id: \.self) { w in
                Text(w.rawValue).tag(w)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack(spacing: 12) {
            StatCard(
                icon: "figure.strengthtraining.traditional",
                iconColor: .blue,
                value: "\(workoutCount)",
                label: "Workouts"
            )
            StatCard(
                icon: "clock.fill",
                iconColor: .blue,
                value: timeTrainedLabel,
                label: "Time Trained"
            )
            StatCard(
                icon: "star.fill",
                iconColor: .yellow,
                value: "\(prCount)",
                label: "PRs Hit"
            )
            StatCard(
                icon: "flame.fill",
                iconColor: .orange,
                value: "\(streakWeeks)wk",
                label: "Streak"
            )
        }
    }

    // MARK: - PR Feed Section

    private var prFeedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                Text("Recent PRs")
                    .font(.headline)
                Spacer()
                NavigationLink("See All") {
                    PersonalRecordsView()
                }
                .font(.subheadline)
            }

            if allPRs.isEmpty {
                Text("No PRs yet — log workouts to start tracking!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(allPRs.prefix(5)) { pr in
                    let delta = StrengthAnalytics.previousBest(
                        exerciseName: pr.exerciseName,
                        repCount: pr.repCount,
                        unit: pr.unit,
                        before: pr.dateAchieved,
                        workouts: allWorkouts
                    ).map { pr.weight - $0 }
                    PRFeedRow(pr: pr, delta: delta)
                }
            }
        }
    }

    // MARK: - Strength Chart Section

    private var strengthChartSection: some View {
        let liftData = activeLiftData
        let plotData = liftData.filter { $0.points.count >= 2 }
        let sparseNames = liftData.filter { $0.points.count < 2 }.map { $0.lift.name }

        return VStack(alignment: .leading, spacing: 12) {
            Text("Strength Trends")
                .font(.headline)

            // Lift pill selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(liftOptions, id: \.name) { lift in
                        let isActive = selectedLifts.contains(lift.name)
                        Button {
                            if isActive {
                                if selectedLifts.count > 1 {
                                    selectedLifts.remove(lift.name)
                                }
                            } else if selectedLifts.count < 3 {
                                selectedLifts.insert(lift.name)
                            }
                        } label: {
                            Text(lift.name)
                                .font(.subheadline.weight(isActive ? .semibold : .regular))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(isActive ? lift.color : Color(.secondarySystemBackground))
                                .foregroundStyle(isActive ? Color.white : lift.color)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(lift.color.opacity(isActive ? 0 : 0.5), lineWidth: 1)
                                )
                        }
                    }
                }
                .padding(.horizontal, 1)
            }

            // Chart or placeholder
            if plotData.isEmpty {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
                    .frame(height: 250)
                    .overlay {
                        Text("Not enough data")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
            } else {
                Chart {
                    ForEach(plotData, id: \.lift.name) { pair in
                        ForEach(pair.points) { point in
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("e1RM (lbs)", point.e1RM)
                            )
                            .foregroundStyle(pair.lift.color)
                            .interpolationMethod(.catmullRom)

                            PointMark(
                                x: .value("Date", point.date),
                                y: .value("e1RM (lbs)", point.e1RM)
                            )
                            .foregroundStyle(pair.lift.color)
                            .symbolSize(40)
                        }
                    }
                }
                .frame(height: 250)

                if !sparseNames.isEmpty {
                    Text("Not enough data for: \(sparseNames.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Workout Frequency Section

    private var workoutFrequencySection: some View {
        let buckets = workoutFrequencyBuckets
        let target  = frequencyTarget

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .foregroundStyle(.blue)
                Text("Workout Frequency")
                    .font(.headline)
            }

            if buckets.isEmpty {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
                    .frame(height: 200)
                    .overlay {
                        Text("No workouts in this window")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
            } else {
                Chart {
                    ForEach(buckets) { bucket in
                        BarMark(
                            x: .value("Week", bucket.monday, unit: .weekOfYear),
                            y: .value("Workouts", bucket.count)
                        )
                        .foregroundStyle(
                            Double(bucket.count) >= target
                                ? Color.blue
                                : Color.blue.opacity(0.4)
                        )
                        .cornerRadius(4)
                    }
                    RuleMark(y: .value("Target", target))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4]))
                        .foregroundStyle(Color.blue.opacity(0.7))
                        .annotation(position: .top, alignment: .leading) {
                            Text("Target")
                                .font(.caption2)
                                .foregroundStyle(Color.blue.opacity(0.8))
                        }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear)) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(date, format: .dateTime.month(.abbreviated).day())
                                    .font(.caption2)
                            }
                        }
                        AxisGridLine()
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .frame(height: 200)
            }
        }
    }

    // MARK: - Active Program Section

    private var activeProgramSection: some View {
        let sortedRuns = activeProgramRuns.sorted { $0.startDate > $1.startDate }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "list.clipboard")
                    .foregroundStyle(.blue)
                Text("Active Program")
                    .font(.headline)
            }

            if let run = sortedRuns.first, let program = run.program {
                ActiveProgramCard(
                    run: run,
                    program: program,
                    allWorkouts: allWorkouts,
                    onContinue: { showingCompleteProgramSheet = true }
                )
            } else {
                HStack {
                    Text("No active program")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Browse Programs") {
                        selectedTab = 2
                    }
                    .font(.subheadline)
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

// MARK: - ActiveProgramCard

private struct ActiveProgramCard: View {
    let run: ProgramRun
    let program: TrainingProgram
    let allWorkouts: [Workout]
    let onContinue: () -> Void

    private var currentWeek: Int {
        let weeks = Int(Date().timeIntervalSince(run.startDate) / (7 * 86400)) + 1
        return min(max(weeks, 1), program.lengthInWeeks)
    }

    private var programWorkouts: [Workout] {
        allWorkouts.filter { $0.programRun?.id == run.id }
    }

    private var completedCount: Int { programWorkouts.count }

    private var totalSessions: Int { program.lengthInWeeks * program.sessionsPerWeek }

    private var progress: Double {
        guard totalSessions > 0 else { return 0 }
        return min(Double(completedCount) / Double(totalSessions), 1.0)
    }

    private var thisWeekCompletedCount: Int {
        programWorkouts.filter { $0.programWeekNumber == currentWeek }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Progress ring + info
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Color.blue.opacity(0.2), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(progress * 100))%")
                        .font(.caption.weight(.semibold))
                }
                .frame(width: 60, height: 60)

                VStack(alignment: .leading, spacing: 4) {
                    Text(program.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Text("Week \(currentWeek) of \(program.lengthInWeeks)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(completedCount) of \(totalSessions) sessions complete")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            // This week session dots
            VStack(alignment: .leading, spacing: 6) {
                Text("This Week")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach(1...max(program.sessionsPerWeek, 1), id: \.self) { i in
                        Image(systemName: i <= thisWeekCompletedCount ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(i <= thisWeekCompletedCount ? Color.green : Color(.systemGray3))
                    }
                }
            }

            // Continue button
            Button(action: onContinue) {
                Text("Continue Program")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - PRFeedRow

private struct PRFeedRow: View {
    let pr: PersonalRecord
    let delta: Double?  // nil = first PR, positive = improvement over previous best

    private var formattedWeight: String {
        let w = pr.weight
        let num = w.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(w))"
            : String(format: "%.1f", w)
        return "\(num) \(pr.unit.rawValue)"
    }

    private var formattedDelta: String? {
        guard let d = delta, d > 0 else { return nil }
        let num = d.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(d))"
            : String(format: "%.1f", d)
        return "+\(num) \(pr.unit.rawValue)"
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(pr.exerciseName)
                        .font(.subheadline.weight(.semibold))
                    Text("×\(pr.repCount)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(pr.dateAchieved, format: .dateTime.month(.abbreviated).day().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(formattedWeight)
                    .font(.headline)
                if let deltaStr = formattedDelta {
                    Text(deltaStr)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    Text("First PR")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - StatCard

private struct StatCard: View {
    let icon: String
    let iconColor: Color
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconColor)
            Text(value)
                .font(.title2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 6)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
