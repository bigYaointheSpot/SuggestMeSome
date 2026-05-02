//
//  DashboardView.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/7/26.
//

import SwiftUI
import SwiftData
import Charts


// MARK: - DashboardView

struct DashboardView: View {
    @Binding var selectedTab: Int

    @Environment(\.modelContext) private var modelContext
    @Environment(ActiveWorkoutSessionStore.self) private var activeWorkoutSessionStore
    @Environment(AppRouteCoordinator.self) private var appRouteCoordinator
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
    @Query(sort: \HealthKitDailySummary.dayStart, order: .reverse)
    private var healthKitSummaries: [HealthKitDailySummary]

    @State private var viewModel = DashboardViewModel()
    @State private var pendingWorkoutStart: PendingWorkoutStart?

    private enum PendingWorkoutStart {
        case empty
        case generatedWorkout
        case programWorkout
    }

    /// Full metadata fingerprint for every source array the dashboard reads.
    ///
    /// Prompt 1's `count + first` token improved render cost but could miss
    /// in-place edits on non-leading rows and on unsorted collections. The
    /// fingerprint is intentionally correctness-first for Feature 20 audit
    /// remediation: it hashes only per-row identity plus change-driving fields,
    /// but it touches every row so existing edits always retrigger the refresh.
    private var dashboardRefreshToken: DashboardRefreshFingerprint {
        DashboardRefreshFingerprint(
            activeProgramRuns: activeProgramRuns,
            workouts: allWorkouts,
            prs: allPRs,
            exercises: allExercises,
            weeklyAnalyses: weeklyAnalyses,
            liftTrends: liftTrends,
            proposals: allProposals,
            healthSummaries: healthKitSummaries
        )
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DSSpacing.xl) {
                    quickStartSection
                    timeWindowPicker
                    statsBar
                    CollaborationInsightSummaryCard()
                    strengthTrendsCard
                    if viewModel.hasAdaptiveSignals || viewModel.snapshotFatigueStatus != nil {
                        adaptiveSignalsRow
                    }
                    workoutFrequencyCard
                    volumeMuscleGroupCard
                    prFeedCard
                    activeProgramSection
                    if !viewModel.pendingProposals.isEmpty {
                        coachingFooterCard
                    }
                }
                .padding(.horizontal)
                .padding(.top, DSSpacing.m)
                .padding(.bottom, DSSpacing.xxl)
            }
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(isPresented: $viewModel.navigateToEmptyWorkout) {
                WorkoutView()
            }
            .navigationDestination(isPresented: $viewModel.showingGeneratedWorkout) {
                WorkoutView(generatedWorkout: viewModel.pendingGeneratedWorkout)
                    .onDisappear {
                        viewModel.pendingGeneratedWorkout = nil
                    }
            }
            .navigationDestination(isPresented: $viewModel.showingProgramWorkout) {
                if let pw = viewModel.pendingProgramWorkout {
                    WorkoutView(programWorkout: pw)
                }
            }
            .navigationDestination(isPresented: $viewModel.showingProposalReview) {
                if let run = viewModel.sortedActiveProgramRuns.first {
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
            .sheet(
                item: Binding(
                    get: {
                        guard let route = appRouteCoordinator.activeRoute,
                              route.targetTab == .dashboard else {
                            return nil
                        }
                        return route
                    },
                    set: { (_: AppDeepLinkRoute?) in
                        appRouteCoordinator.clear()
                    }
                )
            ) { route in
                CollaborationRouteSheetView(route: route)
            }
        }
        .task(id: dashboardRefreshToken) {
            refreshDashboard()
        }
    }

    // MARK: - Data sync

    private func refreshDashboard() {
        let engine = AdaptiveTrainingStateEngine(context: modelContext)
        viewModel.refresh(
            workouts: allWorkouts,
            activeProgramRuns: activeProgramRuns,
            allPRs: allPRs,
            exercises: allExercises,
            weeklyAnalyses: weeklyAnalyses,
            liftTrends: liftTrends,
            allProposals: allProposals,
            trainingStateSnapshot: engine.buildSnapshot(),
            healthKitInsight: HealthKitRecoveryInsightService.computeInsight(from: healthKitSummaries)
        )
    }

    // MARK: - Quick Start Section

    private var quickStartSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            Text("Start Workout")
                .font(.title3.weight(.bold))
            HStack(spacing: DSSpacing.s) {
                quickStartButton(icon: "play.fill", label: "Empty", color: DSColor.primaryAction) {
                    requestWorkoutStart(.empty)
                }
                quickStartButton(icon: "wand.and.stars", label: "Suggest", color: DSColor.primaryAction) {
                    viewModel.pendingGeneratedWorkout = nil
                    viewModel.showingGeneratorSheet = true
                }
                quickStartButton(
                    icon: "list.clipboard.fill",
                    label: "Program",
                    color: DSColor.primaryAction,
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
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.l, style: .continuous))

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

    // MARK: - Time Window Picker

    private var timeWindowPicker: some View {
        HStack(spacing: DSSpacing.xs) {
            ForEach(DashboardTimeWindow.allCases, id: \.self) { w in
                let isActive = viewModel.timeWindow == w
                Button {
                    withAnimation(.dsSnap) {
                        viewModel.timeWindow = w
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: w.icon)
                            .font(.caption2.weight(.semibold))
                        Text(w.rawValue)
                            .font(.footnote.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DSSpacing.s)
                    .background(isActive ? DSColor.primaryAction : Color.clear)
                    .foregroundStyle(isActive ? Color.white : DSColor.primaryAction)
                    .clipShape(RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous))
                }
            }
        }
        .padding(DSSpacing.xs)
        .background(DSColor.primaryAction.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous))
        .sensoryFeedback(.selection, trigger: viewModel.timeWindow)
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack(spacing: DSSpacing.s) {
            DashboardStatCard(
                icon: "figure.strengthtraining.traditional",
                iconColor: DSColor.primaryAction,
                value: "\(viewModel.workoutCount)",
                label: "Workouts",
                sparkline: viewModel.workoutsSparkline
            )
            DashboardStatCard(
                icon: "clock.fill",
                iconColor: DSColor.primaryAction,
                value: viewModel.timeTrainedLabel,
                label: "Trained",
                sparkline: viewModel.timeTrainedSparkline
            )
            DashboardStatCard(
                icon: "star.fill",
                iconColor: .yellow,
                value: "\(viewModel.prCount)",
                label: "PRs",
                sparkline: viewModel.prSparkline
            )
            DashboardStatCard(
                icon: "flame.fill",
                iconColor: .orange,
                value: "\(viewModel.streakWeeks)wk",
                label: "Streak",
                sparkline: viewModel.streakSparkline
            )
        }
    }

    // MARK: - Strength Trends Card

    private var strengthTrendsCard: some View {
        let liftData = viewModel.activeLiftData
        let plotData = liftData.filter { $0.points.count >= 2 }
        let sparseNames = liftData.filter { $0.points.count < 2 }.map { $0.lift.name }

        return ExpandableCard {
            VStack(alignment: .leading, spacing: DSSpacing.m) {
                DSSectionHeader(icon: "chart.line.uptrend.xyaxis", title: "Strength Trends")

                if !viewModel.significantLiftTrends.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DSSpacing.s) {
                            ForEach(viewModel.significantLiftTrends) { trend in
                                LiftTrendBadge(trend: trend)
                            }
                        }
                        .padding(.horizontal, 1)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSSpacing.s) {
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
                                    .font(.footnote.weight(isActive ? .semibold : .regular))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(isActive ? lift.color : DSColor.surfaceElevated)
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

                if plotData.isEmpty {
                    DashboardEmptyState(
                        icon: "chart.xyaxis.line",
                        title: "Not enough data",
                        message: "Log at least two workouts on your tracked lifts to see the trend line."
                    )
                    .frame(minHeight: 180)
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
                    .frame(height: 220)

                    if !sparseNames.isEmpty {
                        Text("Not enough data for: \(sparseNames.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } expanded: {
            VStack(alignment: .leading, spacing: DSSpacing.s) {
                Text("Lift confidence & momentum")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(viewModel.significantLiftTrends) { trend in
                    strengthTrendDetailRow(trend)
                }
                if viewModel.significantLiftTrends.isEmpty {
                    Text("Trend details appear here once the coach has enough data per lift (about four weeks).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func strengthTrendDetailRow(_ trend: LiftPerformanceTrend) -> some View {
        HStack(alignment: .top, spacing: DSSpacing.s) {
            Image(systemName: trend.trendStatus.dsTrendIcon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(trend.trendStatus.dsTrendColor)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(trend.liftDisplayName)
                        .font(.caption.weight(.semibold))
                    if let change = trend.fourWeekChangePercent {
                        Text(String(format: "%+.1f%%", change))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(change >= 0 ? Color.green : Color.red)
                    }
                }
                Text(String(format: "Confidence %.0f%% · %d data points",
                            trend.confidenceScore * 100,
                            trend.totalDataPoints))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Adaptive Signals Row

    private var adaptiveSignalsRow: some View {
        VStack(spacing: DSSpacing.m) {
            RecoveryPressureCard(
                pressure: viewModel.recoveryPressure,
                fatigueStatus: viewModel.snapshotFatigueStatus,
                healthKitInsight: viewModel.healthKitInsight
            )
            bodyHeatmapCard
        }
    }

    private var bodyHeatmapCard: some View {
        ExpandableCard {
            VStack(alignment: .leading, spacing: DSSpacing.m) {
                DSSectionHeader(
                    icon: "figure.arms.open",
                    title: "Muscle Load",
                    iconColor: DSColor.signalCaution
                )
                if viewModel.perMuscleSaturation.isEmpty {
                    DashboardEmptyState(
                        icon: "figure.run",
                        title: "Not enough recent training",
                        message: "Log a few workouts this week to see per-muscle stress distribution."
                    )
                } else {
                    BodyHeatmapView(saturation: viewModel.perMuscleSaturation)
                }
            }
        } expanded: {
            VStack(alignment: .leading, spacing: DSSpacing.s) {
                Text("Saturation is calculated from hard sets over the past 7 days, compared against your weekly target range.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let topMuscle = topLoadedMuscle {
                    Text("Most loaded: **\(topMuscle.displayName)** at \(percentString(viewModel.perMuscleSaturation[topMuscle] ?? 0)) of target.")
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
                if let underloaded = leastLoadedMuscle {
                    Text("Undertrained: **\(underloaded.displayName)** at \(percentString(viewModel.perMuscleSaturation[underloaded] ?? 0)). Consider adding volume.")
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    private var topLoadedMuscle: ProgramVolumeMuscle? {
        viewModel.perMuscleSaturation.max { $0.value < $1.value }?.key
    }

    private var leastLoadedMuscle: ProgramVolumeMuscle? {
        viewModel.perMuscleSaturation.min { $0.value < $1.value }?.key
    }

    private func percentString(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    // MARK: - Workout Frequency Card

    private var workoutFrequencyCard: some View {
        let buckets = viewModel.workoutFrequencyBuckets
        let target  = viewModel.frequencyTarget
        let hits    = buckets.filter { Double($0.count) >= target }.count
        let adherencePct = buckets.isEmpty ? 0 : Int((Double(hits) / Double(buckets.count) * 100).rounded())

        return ExpandableCard {
            VStack(alignment: .leading, spacing: DSSpacing.m) {
                DSSectionHeader(
                    icon: "calendar",
                    title: "Workout Frequency",
                    trailing: AnyView(
                        Text("\(adherencePct)% weeks on target")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    )
                )

                if buckets.isEmpty {
                    DashboardEmptyState(
                        icon: "calendar.badge.plus",
                        title: "No workouts yet",
                        message: "Start logging workouts to see your weekly cadence."
                    )
                    .frame(minHeight: 160)
                } else {
                    Chart {
                        ForEach(buckets) { bucket in
                            BarMark(
                                x: .value("Week", bucket.monday, unit: .weekOfYear),
                                y: .value("Workouts", bucket.count)
                            )
                            .foregroundStyle(
                                Double(bucket.count) >= target
                                    ? DSColor.primaryAction
                                    : DSColor.primaryAction.opacity(0.35)
                            )
                            .cornerRadius(4)
                        }
                        RuleMark(y: .value("Target", target))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                            .foregroundStyle(DSColor.signalPositive)
                            .annotation(position: .top, alignment: .leading) {
                                Text("Target \(Int(target))")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(DSColor.signalPositive.opacity(0.15))
                                    .foregroundStyle(DSColor.signalPositive)
                                    .clipShape(Capsule())
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
                    .frame(height: 180)
                }
            }
        } expanded: {
            VStack(alignment: .leading, spacing: DSSpacing.s) {
                Text("You hit your target **\(hits) of \(buckets.count) weeks** in this window.")
                    .font(.caption)
                Text("Target is pulled from your active program's sessions-per-week, or the rolling average when you're training without one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Volume by Muscle Group Card

    private var volumeMuscleGroupCard: some View {
        let data = viewModel.volumeByMuscleGroup

        return ExpandableCard {
            VStack(alignment: .leading, spacing: DSSpacing.m) {
                DSSectionHeader(icon: "figure.strengthtraining.functional", title: "Volume by Muscle Group")

                if data.isEmpty {
                    DashboardEmptyState(
                        icon: "chart.bar.fill",
                        title: "No logged sets yet",
                        message: "Once you log working sets, the breakdown appears here."
                    )
                    .frame(minHeight: 160)
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
                        AxisMarks { _ in AxisValueLabel() }
                    }
                    .frame(height: 200)
                }
            }
        } expanded: {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text("Total hard sets per muscle group in this window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let top = data.first {
                    Text("Heaviest: **\(top.group)** with \(top.sets) sets.")
                        .font(.caption)
                }
                if let light = data.last, data.count > 1 {
                    Text("Lightest: **\(light.group)** with \(light.sets) sets.")
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - PR Feed Card

    private var prFeedCard: some View {
        ExpandableCard {
            VStack(alignment: .leading, spacing: DSSpacing.m) {
                DSSectionHeader(
                    icon: "star.fill",
                    title: "Recent PRs",
                    iconColor: .yellow,
                    trailing: AnyView(
                        NavigationLink("See All") {
                            PersonalRecordsView()
                        }
                        .font(.caption.weight(.semibold))
                    )
                )

                if viewModel.allPRs.isEmpty {
                    DashboardEmptyState(
                        icon: "trophy.fill",
                        title: "No PRs yet",
                        message: "Complete a working set to bag your first personal record.",
                        iconColor: .yellow
                    )
                } else {
                    VStack(spacing: DSSpacing.s) {
                        ForEach(viewModel.allPRs.prefix(5)) { pr in
                            PRFeedRow(pr: pr, delta: viewModel.recentPRDeltas[pr.id])
                        }
                    }
                }
            }
        } expanded: {
            Text("Showing your five most recent personal records. Tap \"See All\" for the full history, including the workout each PR came from.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Active Program Section

    private var activeProgramSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            DSSectionHeader(icon: "list.clipboard", title: "Active Program")

            if let run = viewModel.sortedActiveProgramRuns.first, let program = run.program {
                let latestAnalysis = viewModel.weeklyAnalyses.first {
                    $0.programRun?.id == run.id && $0.isFinalized
                }
                let progressSnapshot = viewModel.activeProgramProgressSnapshot(for: run)
                    ?? ProgramRunProgressReadSnapshot.build(for: run, workouts: [])
                ActiveProgramCard(
                    run: run,
                    program: program,
                    progressSnapshot: progressSnapshot,
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
                .dsCardStyle()
            }
        }
    }

    // MARK: - Coaching Footer Card

    private var coachingFooterCard: some View {
        let proposals = viewModel.pendingProposals

        return ExpandableCard(tint: DSColor.primaryAction) {
            VStack(alignment: .leading, spacing: DSSpacing.s) {
                DSSectionHeader(
                    icon: "brain.head.profile",
                    title: "Smart Coaching",
                    trailing: AnyView(
                        Text("\(proposals.count) pending")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DSColor.primaryAction)
                    )
                )
                if let first = proposals.first {
                    Text(first.summaryText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DSColor.primaryAction)
                        .lineLimit(2)
                }
                Button {
                    viewModel.showingProposalReview = true
                } label: {
                    HStack(spacing: 4) {
                        Text("Review \(proposals.count) proposal\(proposals.count == 1 ? "" : "s")")
                            .font(.caption.weight(.semibold))
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(DSColor.primaryAction)
                }
                .buttonStyle(.plain)
            }
        } expanded: {
            VStack(alignment: .leading, spacing: DSSpacing.s) {
                ForEach(proposals.prefix(4)) { proposal in
                    HStack(alignment: .top, spacing: DSSpacing.s) {
                        Image(systemName: "circle.fill")
                            .font(.caption2)
                            .foregroundStyle(DSColor.primaryAction.opacity(0.7))
                            .padding(.top, 4)
                        Text(proposal.summaryText)
                            .font(.caption)
                    }
                }
                if proposals.count > 4 {
                    Text("+ \(proposals.count - 4) more…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
