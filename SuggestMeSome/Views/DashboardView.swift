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

// MARK: - DashboardView

struct DashboardView: View {
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

    // MARK: - Chart data

    var strengthChartData: [ChartPoint] {
        StrengthAnalytics.chartPoints(
            for: Array(selectedLifts),
            from: allWorkouts,
            since: timeWindow.startDate
        )
    }

    // (lift option, data points for that lift in the current window)
    var activeLiftData: [(lift: (name: String, color: Color), points: [ChartPoint])] {
        let data = strengthChartData
        return liftOptions
            .filter { selectedLifts.contains($0.name) }
            .map { lift in (lift: lift, points: data.filter { $0.exerciseName == lift.name }) }
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
                    placeholderSection("Volume Trend")
                    placeholderSection("Recent Workouts")
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

    // MARK: - Remaining placeholder sections

    private func placeholderSection(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
                .frame(height: 80)
                .overlay {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
        }
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
