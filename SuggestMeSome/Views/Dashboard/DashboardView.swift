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

// MARK: - FatigueStatus display helpers

private extension FatigueStatus {
    var displayName: String {
        switch self {
        case .low:        return "Low"
        case .manageable: return "Manageable"
        case .elevated:   return "Elevated"
        case .high:       return "High"
        case .critical:   return "Critical"
        }
    }
    var accentColor: Color {
        switch self {
        case .low:        return .green
        case .manageable: return .blue
        case .elevated:   return .yellow
        case .high:       return .orange
        case .critical:   return .red
        }
    }
}

// MARK: - LiftTrendStatus display helpers

private extension LiftTrendStatus {
    var trendIcon: String {
        switch self {
        case .improving:       return "arrow.up.right"
        case .stable:          return "equal"
        case .declining:       return "arrow.down.right"
        case .volatile:        return "waveform"
        case .insufficientData: return "minus"
        }
    }
    var trendColor: Color {
        switch self {
        case .improving:       return .green
        case .stable:          return .blue
        case .declining:       return .red
        case .volatile:        return .orange
        case .insufficientData: return .gray
        }
    }
}

// MARK: - DashboardView

struct DashboardView: View {
    @Binding var selectedTab: Int

    @Environment(\.modelContext) private var modelContext
    @Environment(ActiveWorkoutSessionStore.self) private var activeWorkoutSessionStore
    @Query(sort: \Workout.date, order: .reverse) private var allWorkouts: [Workout]
    @Query(filter: #Predicate<ProgramRun> { run in run.isCompleted == false })
    private var activeProgramRuns: [ProgramRun]
    @Query(sort: \PersonalRecord.dateAchieved, order: .reverse) private var allPRs: [PersonalRecord]
    @Query private var allExercises: [Exercise]
    @Query(sort: \WeeklyTrainingAnalysis.weekStartDate, order: .reverse)
    private var weeklyAnalyses: [WeeklyTrainingAnalysis]
    @Query(sort: \LiftPerformanceTrend.updatedAt, order: .reverse)
    private var liftTrends: [LiftPerformanceTrend]
    @Query private var allProposals: [AdaptationProposal]

    @State private var viewModel = DashboardViewModel()
    @State private var pendingWorkoutStart: PendingWorkoutStart?

    private enum PendingWorkoutStart {
        case empty
        case generatedWorkout
        case programWorkout
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    quickStartSection
                    if viewModel.hasCoachingData {
                        coachingInsightsSection
                    }
                    if !viewModel.activeProgramRuns.isEmpty {
                        activeProgramSection
                    }
                    timeWindowPicker
                    statsBar
                    prFeedSection
                    strengthChartSection
                    workoutFrequencySection
                    volumeMuscleGroupSection
                    if viewModel.activeProgramRuns.isEmpty {
                        activeProgramSection
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(isPresented: $viewModel.navigateToEmptyWorkout) {
                WorkoutView()
            }
            .navigationDestination(isPresented: $viewModel.showingGeneratedWorkout) {
                WorkoutView(generatedWorkout: viewModel.pendingGeneratedWorkout)
            }
            .navigationDestination(isPresented: $viewModel.showingProgramWorkout) {
                if let pw = viewModel.pendingProgramWorkout {
                    WorkoutView(programWorkout: pw)
                }
            }
            .navigationDestination(isPresented: $viewModel.showingProposalReview) {
                if let run = viewModel.activeProgramRuns.sorted(by: { $0.startDate > $1.startDate }).first {
                    AdaptationProposalReviewView(run: run)
                }
            }
            .sheet(isPresented: $viewModel.showingGeneratorSheet, onDismiss: {
                DeferredNavigationService.launchAfterSheetDismissIfNeeded(
                    hasPendingDestination: viewModel.pendingGeneratedWorkout != nil
                ) {
                    if activeWorkoutSessionStore.hasActiveSession {
                        pendingWorkoutStart = .generatedWorkout
                    } else {
                        viewModel.showingGeneratedWorkout = true
                    }
                }
            }) {
                GeneratorSheetRootView { gw in
                    viewModel.pendingGeneratedWorkout = gw
                    viewModel.showingGeneratorSheet = false
                }
            }
            .sheet(isPresented: $viewModel.showingCompleteProgramSheet, onDismiss: {
                DeferredNavigationService.launchAfterSheetDismissIfNeeded(
                    hasPendingDestination: viewModel.pendingProgramWorkout != nil
                ) {
                    if activeWorkoutSessionStore.hasActiveSession {
                        pendingWorkoutStart = .programWorkout
                    } else {
                        viewModel.showingProgramWorkout = true
                    }
                }
            }) {
                CompleteProgramWorkoutSheet(activeRuns: Array(viewModel.activeProgramRuns)) { ctx in
                    viewModel.pendingProgramWorkout = ctx
                    viewModel.showingCompleteProgramSheet = false
                }
            }
            .confirmationDialog(
                "Discard Active Workout?",
                isPresented: .init(
                    get: { pendingWorkoutStart != nil },
                    set: {
                        if !$0 {
                            discardPendingReplacement(start: pendingWorkoutStart)
                            pendingWorkoutStart = nil
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                Button("Discard Active Workout", role: .destructive) {
                    let start = pendingWorkoutStart
                    pendingWorkoutStart = nil
                    activeWorkoutSessionStore.discardSession()
                    if let start {
                        performWorkoutStart(start)
                    }
                }
                Button("Cancel", role: .cancel) {
                    discardPendingReplacement(start: pendingWorkoutStart)
                    pendingWorkoutStart = nil
                }
            } message: {
                Text("Starting a new workout will delete the in-progress draft.")
            }
        }
        .onAppear {
            viewModel.workouts = allWorkouts
            viewModel.activeProgramRuns = activeProgramRuns
            viewModel.allPRs = allPRs
            viewModel.exercises = allExercises
            viewModel.weeklyAnalyses = weeklyAnalyses
            viewModel.liftTrends = liftTrends
            viewModel.allProposals = allProposals
        }
        .onChange(of: allWorkouts) { viewModel.workouts = allWorkouts }
        .onChange(of: activeProgramRuns) { viewModel.activeProgramRuns = activeProgramRuns }
        .onChange(of: allPRs) { viewModel.allPRs = allPRs }
        .onChange(of: allExercises) { viewModel.exercises = allExercises }
        .onChange(of: weeklyAnalyses) { viewModel.weeklyAnalyses = weeklyAnalyses }
        .onChange(of: liftTrends) { viewModel.liftTrends = liftTrends }
        .onChange(of: allProposals) { viewModel.allProposals = allProposals }
    }

    // MARK: - Quick Start Section

    private var quickStartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Start Workout")
                .font(.title3.weight(.bold))
            HStack(spacing: 10) {
                quickStartButton(icon: "play.fill", label: "Empty", color: .indigo) {
                    requestWorkoutStart(.empty)
                }
                quickStartButton(icon: "wand.and.stars", label: "Suggest", color: .indigo) {
                    viewModel.pendingGeneratedWorkout = nil
                    viewModel.showingGeneratorSheet = true
                }
                quickStartButton(
                    icon: "list.clipboard.fill",
                    label: "Program",
                    color: .indigo,
                    badge: viewModel.pendingProposals.isEmpty ? nil : "\(viewModel.pendingProposals.count)"
                ) {
                    if viewModel.activeProgramRuns.isEmpty {
                        selectedTab = MainTab.programs.rawValue
                    } else {
                        viewModel.pendingProgramWorkout = nil
                        viewModel.showingCompleteProgramSheet = true
                    }
                }
            }
        }
    }

    private func requestWorkoutStart(_ start: PendingWorkoutStart) {
        if activeWorkoutSessionStore.hasActiveSession {
            pendingWorkoutStart = start
        } else {
            performWorkoutStart(start)
        }
    }

    private func performWorkoutStart(_ start: PendingWorkoutStart) {
        switch start {
        case .empty:
            viewModel.navigateToEmptyWorkout = true
        case .generatedWorkout:
            viewModel.showingGeneratedWorkout = true
        case .programWorkout:
            viewModel.showingProgramWorkout = true
        }
    }

    private func discardPendingReplacement(start: PendingWorkoutStart?) {
        switch start {
        case .generatedWorkout:
            viewModel.pendingGeneratedWorkout = nil
        case .programWorkout:
            viewModel.pendingProgramWorkout = nil
        case .empty, nil:
            break
        }
    }

    private func quickStartButton(
        icon: String,
        label: String,
        color: Color,
        badge: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 7) {
                    Image(systemName: icon)
                        .font(.title2.weight(.semibold))
                        .frame(height: 26)
                    Text(label)
                        .font(.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .frame(maxHeight: .infinity)
                .background(color.gradient)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .clipShape(Capsule())
                        .offset(x: 6, y: -6)
                }
            }
        }
    }

    // MARK: - Coaching Insights Section

    private var coachingInsightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(.indigo)
                Text("Smart Coaching")
                    .font(.headline.weight(.bold))
                Spacer()
                if !viewModel.pendingProposals.isEmpty {
                    Text("\(viewModel.pendingProposals.count) pending")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.indigo)
                }
            }

            HStack(spacing: 10) {
                // Fatigue status tile
                if let analysis = viewModel.recentAnalysis {
                    fatigueStatusTile(analysis)
                }

                // Proposals tile
                if !viewModel.pendingProposals.isEmpty, !viewModel.activeProgramRuns.isEmpty {
                    proposalsTile(viewModel.pendingProposals)
                } else if let analysis = viewModel.recentAnalysis {
                    performanceTile(analysis)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.indigo.opacity(0.4), lineWidth: 1.5))
        .shadow(color: Color.indigo.opacity(0.12), radius: 10, x: 0, y: 2)
    }

    private func fatigueStatusTile(_ analysis: WeeklyTrainingAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FATIGUE")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 5) {
                Circle()
                    .fill(analysis.fatigueStatus.accentColor)
                    .frame(width: 8, height: 8)
                Text(analysis.fatigueStatus.displayName)
                    .font(.subheadline.weight(.semibold))
            }
            if let weekNum = analysis.programWeekNumber {
                Text("Program week \(weekNum)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(analysis.weekStartDate, format: .dateTime.month(.abbreviated).day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(analysis.fatigueStatus.accentColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func performanceTile(_ analysis: WeeklyTrainingAnalysis) -> some View {
        let score = analysis.weightedPerformanceScore
        let scoreLabel: String
        let scoreColor: Color
        if score >= 4 {
            scoreLabel = "Above Target"
            scoreColor = .green
        } else if score <= -4 {
            scoreLabel = "Below Target"
            scoreColor = .orange
        } else {
            scoreLabel = "On Target"
            scoreColor = .blue
        }

        return VStack(alignment: .leading, spacing: 6) {
            Text("PERFORMANCE")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(scoreLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(scoreColor)
            Text(String(format: "%.0f%% adherence", min(analysis.adherenceScore, 1.0) * 100))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(scoreColor.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func proposalsTile(_ proposals: [AdaptationProposal]) -> some View {
        Button {
            viewModel.showingProposalReview = true
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text("RECOMMENDATIONS")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(proposals.first?.summaryText ?? "View proposals")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.indigo)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 3) {
                    Text("Review \(proposals.count) proposal\(proposals.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.indigo.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Time Window Picker

    private var timeWindowPicker: some View {
        Picker("Time Window", selection: $viewModel.timeWindow) {
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
                iconColor: .indigo,
                value: "\(viewModel.workoutCount)",
                label: "Workouts"
            )
            StatCard(
                icon: "clock.fill",
                iconColor: .indigo,
                value: viewModel.timeTrainedLabel,
                label: "Time Trained"
            )
            StatCard(
                icon: "star.fill",
                iconColor: .yellow,
                value: "\(viewModel.prCount)",
                label: "PRs Hit"
            )
            StatCard(
                icon: "flame.fill",
                iconColor: .orange,
                value: "\(viewModel.streakWeeks)wk",
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

            if viewModel.allPRs.isEmpty {
                Text("Complete your first workout to start tracking PRs")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(viewModel.allPRs.prefix(5)) { pr in
                    let delta = StrengthAnalytics.previousBest(
                        exerciseName: pr.exerciseName,
                        repCount: pr.repCount,
                        unit: pr.unit,
                        before: pr.dateAchieved,
                        workouts: viewModel.workouts
                    ).map { pr.weight - $0 }
                    PRFeedRow(pr: pr, delta: delta)
                }
            }
        }
    }

    // MARK: - Strength Chart Section

    private var strengthChartSection: some View {
        let liftData = viewModel.activeLiftData
        let plotData = liftData.filter { $0.points.count >= 2 }
        let sparseNames = liftData.filter { $0.points.count < 2 }.map { $0.lift.name }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(.indigo)
                Text("Strength Trends")
                    .font(.headline.weight(.bold))
            }

            // Lift trend badges from Feature 6 LiftPerformanceTrend
            if !viewModel.significantLiftTrends.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.significantLiftTrends) { trend in
                            LiftTrendBadge(trend: trend)
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }

            // Lift pill selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.liftOptions, id: \.name) { lift in
                        let isActive = viewModel.selectedLifts.contains(lift.name)
                        Button {
                            if isActive {
                                if viewModel.selectedLifts.count > 1 {
                                    viewModel.selectedLifts.remove(lift.name)
                                }
                            } else if viewModel.selectedLifts.count < 3 {
                                viewModel.selectedLifts.insert(lift.name)
                            }
                        } label: {
                            Text(lift.name)
                                .font(.subheadline.weight(isActive ? .semibold : .regular))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(isActive ? lift.color : Color(.tertiarySystemBackground))
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
                Text("Log workouts to see strength trends")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200, alignment: .center)
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
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Workout Frequency Section

    private var workoutFrequencySection: some View {
        let buckets = viewModel.workoutFrequencyBuckets
        let target  = viewModel.frequencyTarget

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .foregroundStyle(.indigo)
                Text("Workout Frequency")
                    .font(.headline.weight(.bold))
            }

            if buckets.isEmpty {
                Text("Start logging workouts to see your frequency")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
            } else {
                Chart {
                    ForEach(buckets) { bucket in
                        BarMark(
                            x: .value("Week", bucket.monday, unit: .weekOfYear),
                            y: .value("Workouts", bucket.count)
                        )
                        .foregroundStyle(
                            Double(bucket.count) >= target
                                ? Color.indigo
                                : Color.indigo.opacity(0.4)
                        )
                        .cornerRadius(4)
                    }
                    RuleMark(y: .value("Target", target))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4]))
                        .foregroundStyle(Color.indigo.opacity(0.7))
                        .annotation(position: .top, alignment: .leading) {
                            Text("Target")
                                .font(.caption2)
                                .foregroundStyle(Color.indigo.opacity(0.8))
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
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Volume by Muscle Group Section

    private var volumeMuscleGroupSection: some View {
        let data = viewModel.volumeByMuscleGroup

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "figure.arms.open")
                    .foregroundStyle(.indigo)
                Text("Volume by Muscle Group")
                    .font(.headline.weight(.bold))
            }

            if data.isEmpty {
                Text("No workout data yet — log some sets to see volume breakdown")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
            } else {
                Chart {
                    ForEach(data, id: \.group) { item in
                        BarMark(
                            x: .value("Sets", item.sets),
                            y: .value("Muscle Group", item.group)
                        )
                        .foregroundStyle(item.color)
                        .cornerRadius(4)
                        .annotation(position: .trailing, alignment: .leading) {
                            Text("\(item.sets)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                    }
                }
                .frame(height: 220)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Active Program Section

    private var activeProgramSection: some View {
        let sortedRuns = viewModel.activeProgramRuns.sorted { $0.startDate > $1.startDate }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "list.clipboard")
                    .foregroundStyle(.indigo)
                Text("Active Program")
                    .font(.headline)
            }

            if let run = sortedRuns.first, let program = run.program {
                let latestAnalysis = viewModel.weeklyAnalyses.first {
                    $0.programRun?.id == run.id && $0.isFinalized
                }
                ActiveProgramCard(
                    run: run,
                    program: program,
                    allWorkouts: viewModel.workouts,
                    latestAnalysis: latestAnalysis,
                    onContinue: { viewModel.showingCompleteProgramSheet = true },
                    onReviewProposals: !viewModel.pendingProposals.isEmpty ? { viewModel.showingProposalReview = true } : nil
                )
            } else {
                HStack {
                    Text("No active program")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Browse Programs") {
                        selectedTab = MainTab.programs.rawValue
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

// MARK: - LiftTrendBadge

private struct LiftTrendBadge: View {
    let trend: LiftPerformanceTrend

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: trend.trendStatus.trendIcon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(trend.trendStatus.trendColor)

            Text(trend.liftDisplayName)
                .font(.caption.weight(.semibold))

            if let changePercent = trend.fourWeekChangePercent {
                Text(String(format: "%+.1f%%", changePercent))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(changePercent >= 0 ? Color.green : Color.red)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(trend.trendStatus.trendColor.opacity(0.10))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(trend.trendStatus.trendColor.opacity(0.25), lineWidth: 1))
    }
}

// MARK: - ActiveProgramCard

private struct ActiveProgramCard: View {
    let run: ProgramRun
    let program: TrainingProgram
    let allWorkouts: [Workout]
    let latestAnalysis: WeeklyTrainingAnalysis?
    let onContinue: () -> Void
    let onReviewProposals: (() -> Void)?

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
        VStack(alignment: .leading, spacing: 14) {
            // Progress ring + info
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Color.indigo.opacity(0.2), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.indigo, style: StrokeStyle(lineWidth: 8, lineCap: .round))
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

                // Latest analysis stats
                if let analysis = latestAnalysis {
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(analysis.fatigueStatus.accentColor)
                                .frame(width: 7, height: 7)
                            Text(analysis.fatigueStatus.displayName)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(analysis.fatigueStatus.accentColor)
                        }
                        Text(String(format: "%.0f%% adherence", min(analysis.adherenceScore, 1.0) * 100))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
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

            // Action buttons
            HStack(spacing: 10) {
                Button(action: onContinue) {
                    Text("Continue Program")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.indigo)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                if let reviewAction = onReviewProposals {
                    Button(action: reviewAction) {
                        Image(systemName: "brain.head.profile")
                            .font(.subheadline.weight(.semibold))
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(Color.indigo.opacity(0.15))
                            .foregroundStyle(.indigo)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
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
    let delta: Double?

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
                        .background(Color.yellow.opacity(0.2))
                        .foregroundStyle(Color.orange)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.yellow.opacity(0.5), lineWidth: 1.5))
        .shadow(color: Color.yellow.opacity(0.08), radius: 6, x: 0, y: 1)
    }
}

// MARK: - StatCard

private struct StatCard: View {
    let icon: String
    let iconColor: Color
    let value: String
    let label: String

    @State private var displayedInt: Int = 0

    private var targetInt: Int? { Int(value) }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconColor)
            Group {
                if targetInt != nil {
                    Text("\(displayedInt)")
                } else {
                    Text(value)
                }
            }
            .font(.title2.weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .contentTransition(.numericText())
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
        .onAppear {
            if let target = targetInt {
                animateCount(to: target)
            }
        }
        .onChange(of: value) { _, _ in
            if let target = targetInt {
                animateCount(to: target)
            }
        }
    }

    private func animateCount(to target: Int) {
        displayedInt = 0
        guard target > 0 else { return }
        let steps = min(target, 24)
        let duration = 0.8
        for i in 1...steps {
            let delay = duration * Double(i) / Double(steps)
            let stepValue = Int(Double(target) * Double(i) / Double(steps))
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeOut(duration: 0.05)) {
                    displayedInt = stepValue
                }
            }
        }
    }
}
