//
//  DashboardView.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/7/26.
//

import SwiftUI
import SwiftData

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
        // Start of the current week (Mon-Sun, locale aware)
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

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    startButton
                    timeWindowPicker
                    statsBar
                    placeholders
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

    // MARK: - Placeholder sections

    private var placeholders: some View {
        VStack(spacing: 16) {
            placeholderSection("PR Feed")
            placeholderSection("Strength Chart")
            placeholderSection("Volume Trend")
            placeholderSection("Recent Workouts")
        }
    }

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
