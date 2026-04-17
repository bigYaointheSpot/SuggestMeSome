//
//  DailyCoachView.swift
//  SuggestMeSome
//
//  Feature 7 — Daily Coach first-tab shell.
//  Presentational skeleton only; readiness form and recommendation engine
//  are deferred to later prompts.
//

import SwiftUI
import SwiftData

// MARK: - DailyCoachView

struct DailyCoachView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(ActiveWorkoutSessionStore.self) private var activeWorkoutSessionStore
    @Environment(PurchaseManager.self) private var purchaseManager

    // MARK: Queries

    @Query(filter: #Predicate<ProgramRun> { run in run.isCompleted == false },
           sort: \ProgramRun.startDate, order: .reverse)
    private var activeRuns: [ProgramRun]

    @Query(sort: \Workout.date, order: .reverse)
    private var recentWorkouts: [Workout]

    @Query(sort: \WeeklyTrainingAnalysis.weekStartDate, order: .reverse)
    private var weeklyAnalyses: [WeeklyTrainingAnalysis]

    @Query(sort: \AdaptationProposal.priority, order: .reverse)
    private var allProposals: [AdaptationProposal]

    @Query(sort: \AppliedProgramOverlay.appliedAt, order: .reverse)
    private var allOverlays: [AppliedProgramOverlay]

    @Query(sort: \DailyCoachCheckIn.date, order: .reverse)
    private var checkIns: [DailyCoachCheckIn]

    @Query(sort: \DailyCoachWeeklyReview.weekStart, order: .reverse)
    private var weeklyReviews: [DailyCoachWeeklyReview]

    @Query(sort: \LiftPerformanceTrend.updatedAt, order: .reverse)
    private var liftTrends: [LiftPerformanceTrend]

    @Query(sort: \HealthKitDailySummary.dayStart, order: .reverse)
    private var healthKitDailySummaries: [HealthKitDailySummary]

    @Query(filter: #Predicate<ProgramRun> { run in run.isCompleted == true },
           sort: \ProgramRun.startDate, order: .reverse)
    private var completedRuns: [ProgramRun]

    @Query(sort: \PersonalRecord.dateAchieved, order: .reverse)
    private var personalRecords: [PersonalRecord]

    @AppStorage("healthkit.enabled") private var healthKitEnabled = false
    @AppStorage("healthkit.dailyCoachEnabled") private var useHealthKitInDailyCoach = false
    @AppStorage(HealthKitSettingsStorage.recoveryLastSyncTimestampKey)
    private var recoveryLastSyncTimestamp: Double = 0

    // MARK: Computed helpers

    private var focusRun: ProgramRun? {
        TrainingContextQueryService.activeProgramRuns(from: activeRuns).first
    }

    private var pendingProposals: [AdaptationProposal] {
        TrainingContextQueryService.pendingUserProposals(
            for: focusRun,
            proposals: allProposals
        )
        .filter { AdaptationProposalConfirmationService.isPendingUserProposal($0) }
    }

    private var latestAnalysis: WeeklyTrainingAnalysis? {
        TrainingContextQueryService.latestWeeklyAnalysis(
            for: focusRun,
            in: Array(weeklyAnalyses)
        )
    }

    private var latestReview: DailyCoachWeeklyReview? { weeklyReviews.first }

    private var activeOverlaysForRun: [AppliedProgramOverlay] {
        guard let run = focusRun else { return [] }
        return allOverlays.filter { $0.programRun?.id == run.id && $0.overlayStatus == .active }
    }

    private var completedWorkoutCountForRun: Int {
        guard let run = focusRun else { return 0 }
        return TrainingContextQueryService.completedWorkoutCount(for: run, in: Array(recentWorkouts))
    }

    private var completedSessionKeysForRun: Set<ProgramSessionCompletionKey>? {
        guard let run = focusRun else { return nil }
        return TrainingContextQueryService.completedSessionKeys(
            for: run,
            context: modelContext
        )
    }

    private var todayPlan: TodayPlan {
        TodayPlanEngine.buildPlan(
            checkIn: todayCheckIn,
            activeRun: focusRun,
            latestAnalysis: latestAnalysis,
            pendingProposalCount: pendingProposals.count,
            pendingProposals: pendingProposals,
            activeOverlays: activeOverlaysForRun,
            recentWorkouts: TrainingContextQueryService.recentWorkouts(from: recentWorkouts, limit: 20),
            objectiveRecoveryEvaluation: objectiveRecoveryEvaluation,
            completedSessions: completedSessionKeysForRun,
            completedWorkoutCountForRun: completedWorkoutCountForRun
        )
    }

    private var relevantProposalForTodayPlan: AdaptationProposal? {
        TodayPlanActionCoordinator.relevantProposalForTodayPlan(
            pendingProposals: pendingProposals,
            plan: todayPlan
        )
    }

    private var overlaysAffectTodaySession: Bool {
        guard let session = todayPlan.recommendation.nextProgramSession else { return false }
        let context = TodayPlanExplanationAssembler.overlayContext(
            activeRun: focusRun,
            activeOverlays: activeOverlaysForRun,
            nextSession: session
        )
        return context.overlaysAffectingTodayCount > 0
    }

    private var objectiveRecoveryEvaluation: ObjectiveRecoveryEvaluation {
        HealthKitRecoveryInsightService.evaluate(
            from: Array(healthKitDailySummaries.prefix(90)),
            healthKitEnabled: healthKitEnabled,
            useHealthKitInDailyCoach: useHealthKitInDailyCoach,
            hasSuccessfulRecoverySync: recoveryLastSyncTimestamp > 0
        )
    }

    private var todayCheckIn: DailyCoachCheckIn? {
        let today = Calendar.current.startOfDay(for: Date())
        return checkIns.first { Calendar.current.startOfDay(for: $0.date) == today }
    }

    private var latestCompletedRun: ProgramRun? {
        TrainingContextQueryService.latestCompletedRun(from: completedRuns)
    }

    private var latestCompletedReviewSnapshot: MesocycleReviewSnapshot? {
        TrainingContextQueryService.latestCompletedMesocycleReview(
            from: completedRuns,
            workouts: Array(recentWorkouts),
            personalRecords: Array(personalRecords)
        )
    }

    private var isBetweenBlocks: Bool {
        focusRun == nil && latestCompletedRun != nil
    }

    private var longHorizonSummary: LongHorizonAdaptationSummary? {
        guard latestCompletedRun != nil else { return nil }
        let summary = TrainingContextQueryService.longHorizonAdaptationSummary(
            endingWith: latestCompletedRun,
            allRuns: Array(completedRuns),
            workouts: Array(recentWorkouts),
            personalRecords: Array(personalRecords),
            maxBlocks: 3
        )
        return summary.blockCount > 0 ? summary : nil
    }

    // MARK: Sheet / navigation state

    @State private var showingCheckInSheet = false
    @State private var recommendationExpanded = false

    // Workout launch
    @State private var navigatingToWorkout = false
    @State private var pendingProgramWorkout: ProgramWorkoutContext?
    @State private var pendingDraft: PreparedWorkoutDraft?
    @State private var pendingLaunchResolution: TodayPlanLaunchResolution?
    @State private var showingDraftReview = false
    @State private var confirmedDraftLaunch = false
    @State private var launchRequestPendingDiscard: TodayPlanLaunchRequest?

    // Block review / next block generation
    @State private var blockReviewSnapshot: MesocycleReviewSnapshot?
    @State private var showingNextBlockGenerator = false

    // Proposal review/confirmation
    @State private var showingProposalReview = false
    @State private var stagedProposalDecision: StagedTodayPlanProposalDecision?
    @State private var proposalActionErrorMessage: String?
    @State private var showingAboutGuidance = false

    // Watch continuity — lazily initialised on first launch broadcast to keep
    // `DefaultWatchCompanionBridge` off the view's init path.
    @State private var watchSessionCoordinator: WatchSessionCoordinator?
    @State private var lastPublishedWatchTodayPlanSignature: String?

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    todayTrainingCard
                    if isBetweenBlocks {
                        betweenBlocksContextCard
                    }
                    readinessCard
                    coachRecommendationCard
                    if let rescue = todayPlan.adherenceRescue {
                        adherenceRescueCard(rescue: rescue)
                    }
                    if !todayPlan.proposalAwareness.isEmpty {
                        proposalAwarenessCard(plan: todayPlan)
                    }
                    latestSessionSummaryCard
                    latestWeeklyReviewCard
                    if !completedRuns.isEmpty {
                        BlockContinuityCard(
                            completedRuns: Array(completedRuns),
                            activeRun: focusRun,
                            onReviewLastBlock: presentLatestCompletedReview
                        )
                    }
                    if let summary = longHorizonSummary {
                        LongHorizonSummaryCard(
                            summary: summary,
                            onReviewBlock: presentLatestCompletedReview,
                            onGenerateNextBlock: { showingNextBlockGenerator = true }
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .navigationTitle("Daily Coach")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("About") {
                        showingAboutGuidance = true
                    }
                }
            }
            .navigationDestination(isPresented: $navigatingToWorkout) {
                if let pw = pendingProgramWorkout {
                    WorkoutView(programWorkout: pw, preparedDraft: pendingDraft?.entries)
                }
            }
        }
        .sheet(isPresented: $showingCheckInSheet) {
            CheckInFormView(existingCheckIn: todayCheckIn)
        }
        .sheet(isPresented: $showingDraftReview, onDismiss: {
            if confirmedDraftLaunch {
                confirmedDraftLaunch = false
                if let resolution = pendingLaunchResolution,
                   let context = pendingProgramWorkout {
                    broadcastWatchLaunch(
                        resolution: resolution,
                        context: context,
                        entries: pendingDraft?.entries ?? draftEntries(for: context.exercises)
                    )
                }
                DeferredNavigationService.launchAfterSheetDismissIfNeeded(
                    hasPendingDestination: true
                ) {
                    navigatingToWorkout = true
                }
            }
        }) {
            if let draft = pendingDraft {
                DraftReviewSheet(
                    draft: draft,
                    sessionLabel: nextSessionLabel(for: todayPlan.recommendation.nextProgramSession)
                ) {
                    confirmedDraftLaunch = true
                    showingDraftReview = false
                }
            }
        }
        .sheet(isPresented: $showingProposalReview) {
            if let proposal = relevantProposalForTodayPlan {
                TodayPlanProposalReviewSheet(
                    proposal: proposal,
                    program: focusRun?.program,
                    onApprove: {
                        showingProposalReview = false
                        stagedProposalDecision = TodayPlanActionCoordinator.stageDecision(
                            action: .approve,
                            proposal: proposal
                        )
                    },
                    onReject: {
                        showingProposalReview = false
                        stagedProposalDecision = TodayPlanActionCoordinator.stageDecision(
                            action: .reject,
                            proposal: proposal
                        )
                    }
                )
            }
        }
        .confirmationDialog(
            "Discard Active Workout?",
            isPresented: Binding(
                get: { launchRequestPendingDiscard != nil },
                set: { if !$0 { launchRequestPendingDiscard = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Discard Active Workout", role: .destructive) {
                let request = launchRequestPendingDiscard
                launchRequestPendingDiscard = nil
                activeWorkoutSessionStore.discardSession()
                if let request {
                    launch(request: request)
                }
            }
            Button("Cancel", role: .cancel) {
                launchRequestPendingDiscard = nil
            }
        } message: {
            Text("Starting a new workout will delete the in-progress draft.")
        }
        .confirmationDialog(
            stagedProposalDecision?.title ?? "Confirm Decision",
            isPresented: Binding(
                get: { stagedProposalDecision != nil },
                set: { if !$0 { stagedProposalDecision = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let staged = stagedProposalDecision {
                switch staged.action {
                case .approve:
                    Button("Confirm Approve") {
                        commitStagedProposalDecision(staged)
                    }
                case .reject:
                    Button("Confirm Reject", role: .destructive) {
                        commitStagedProposalDecision(staged)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(stagedProposalDecision?.message ?? "")
        }
        .alert(
            "Couldn’t Update Proposal",
            isPresented: Binding(
                get: { proposalActionErrorMessage != nil },
                set: { if !$0 { proposalActionErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(proposalActionErrorMessage ?? "Unknown error")
        }
        .sheet(item: $blockReviewSnapshot) { snapshot in
            MesocycleReviewView(snapshot: snapshot)
        }
        .sheet(isPresented: $showingNextBlockGenerator) {
            AIProgramGeneratorView(prefill: latestCompletedReviewSnapshot?.defaultNextBlockPrefill)
        }
        .sheet(isPresented: $showingAboutGuidance) {
            NavigationStack {
                AboutThisGuidanceView()
            }
        }
        .onAppear {
            if purchaseManager.isPremiumUnlocked {
                Task {
                    _ = await HealthKitRecoveryAutoRefreshCoordinator.shared.refreshIfNeeded(
                        trigger: .dailyCoachOpened,
                        context: modelContext
                    )
                }
            }
            publishTodayPlanToWatchIfNeeded(force: true)
        }
        .onChange(of: watchTodayPlanSignature) { _, _ in
            publishTodayPlanToWatchIfNeeded()
        }
    }

    // MARK: - Between Blocks Contextual Card

    private var betweenBlocksContextCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "pause.circle")
                    .foregroundStyle(.orange)
                Text("Between Blocks")
                    .font(.headline)
            }

            Divider()

            Text("Your last block is complete. Review how it went or generate your next training block when you're ready.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    presentLatestCompletedReview()
                } label: {
                    Text("Review Last Block")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(.tertiarySystemBackground))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Button {
                    showingNextBlockGenerator = true
                } label: {
                    Text("Generate Next Block")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.orange)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.3), lineWidth: 1))
    }

    // MARK: - Today's Training Card

    private var todayTrainingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Today's Training", systemImage: "figure.strengthtraining.traditional")
                .font(.headline)

            Divider()

            if let run = focusRun {
                activeProgramSummary(run: run)
            } else {
                standaloneState
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func activeProgramSummary(run: ProgramRun) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let program = run.program {
                Text(program.name)
                    .font(.subheadline.weight(.semibold))
                programProgressLine(run: run, program: program)
            } else {
                Text("Active Program Run")
                    .font(.subheadline.weight(.semibold))
            }

            if let analysis = latestAnalysis {
                fatigueStatusLine(analysis: analysis)
            }
        }
    }

    private func programProgressLine(run: ProgramRun, program: TrainingProgram) -> some View {
        let weeksElapsed = Calendar.current.dateComponents(
            [.weekOfYear], from: run.startDate, to: Date()
        ).weekOfYear ?? 0
        let currentWeek = min(weeksElapsed + 1, program.lengthInWeeks)

        return Text("Week \(currentWeek) of \(program.lengthInWeeks) · \(program.sessionsPerWeek)×/week")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func fatigueStatusLine(analysis: WeeklyTrainingAnalysis) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(fatigueColor(analysis.fatigueStatus))
                .frame(width: 7, height: 7)
            Text("Fatigue: \(analysis.fatigueStatus.rawValue.capitalized)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var standaloneState: some View {
        let guidance = todayPlan.nextStepGuidance
        let contextColor: Color = switch guidance.contextMode {
        case .activeProgram: .secondary
        case .standaloneHistoryInformed: .indigo
        case .standaloneLowConfidence: .orange
        }

        return VStack(alignment: .leading, spacing: 6) {
            Text("No active program")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(guidance.contextMode.rawValue)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(contextColor.opacity(0.12))
                .foregroundStyle(contextColor)
                .clipShape(Capsule())
            Text("Daily Coach works without a program. Log workouts and check in daily to get personalized recommendations.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(guidance.headline)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Readiness Card

    private var readinessCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Readiness", systemImage: "heart.text.square")
                .font(.headline)

            Divider()

            if let checkIn = todayCheckIn {
                todayCheckInSummary(checkIn: checkIn)
                Divider()
                Button("Edit Check-In") {
                    showingCheckInSheet = true
                }
                .font(.subheadline)
            } else {
                Text("No check-in yet for today.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    showingCheckInSheet = true
                } label: {
                    Text("Check In")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func todayCheckInSummary(checkIn: DailyCoachCheckIn) -> some View {
        HStack(spacing: 16) {
            readinessStatPill(label: "Sleep", value: checkIn.sleepQuality)
            readinessStatPill(label: "Energy", value: checkIn.energy)
            readinessStatPill(label: "Soreness", value: checkIn.soreness)
            readinessStatPill(label: "Stress", value: checkIn.stress)
            Spacer()
        }
    }

    private func readinessStatPill(label: String, value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.headline)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Coach Recommendation Card

    private var coachRecommendationCard: some View {
        let plan = todayPlan
        let rec = plan.recommendation
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .foregroundStyle(.indigo)
                    Text("Coach Recommendation")
                        .font(.headline)
                        .lineLimit(1)
                        .allowsTightening(true)
                    Spacer()
                    if rec.hasPainFlag {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.subheadline)
                    }
                }

                HStack(spacing: 6) {
                    confidenceBadge(plan.confidence)
                    readinessTierBadge(rec.readinessTier)
                    Spacer()
                }
            }

            Divider()

            if let insight = plan.objectiveRecoveryEvaluation.insight {
                objectiveRecoveryRow(insight)
            } else if plan.objectiveRecoveryEvaluation.state != .disabled {
                objectiveRecoveryBaselineRow(plan.objectiveRecoveryEvaluation)
            }

            recommendationSourcesRow(plan.attribution.activeSourceLabels)

            // Compact summary
            Text(rec.compactSummary)
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)

            whatChangedTodaySection(plan.changeSummary)
            nextStepGuidanceSection(plan.nextStepGuidance)

            // Primary suggestion chip
            HStack(spacing: 6) {
                Image(systemName: suggestionIcon(rec.primarySuggestion.type))
                    .font(.caption)
                    .foregroundStyle(suggestionColor(rec.primarySuggestion.type))
                Text(rec.primarySuggestion.compactText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            guidanceSafetyRow

            launchSourceRow(
                source: currentLaunchSource(for: rec),
                hasRelevantPendingProposal: relevantProposalForTodayPlan != nil
            )

            // Expand / collapse toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    recommendationExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Text(recommendationExpanded ? "Less detail" : "More detail")
                        .font(.caption)
                    Image(systemName: recommendationExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)

            // Expanded detail section
            if recommendationExpanded {
                Divider()

                // Why Today
                if !plan.whyToday.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Why Today")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(plan.whyToday)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Text(rec.expandedDetails)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                attributionSection(plan.attribution)

                // Confidence rationale
                Text("Confidence (\(plan.confidence.rawValue)): \(plan.confidenceRationale)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if let insight = plan.objectiveRecoveryEvaluation.insight {
                    Text(insight.detailSummary)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if plan.objectiveRecoveryEvaluation.state != .disabled {
                    Text(TodayPlanExplanationAssembler.healthKitInfluenceText(for: plan.objectiveRecoveryEvaluation))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !rec.primarySuggestion.expandedText.isEmpty {
                    recommendationDetailRow(rec.primarySuggestion)
                }

                ForEach(Array(rec.secondarySuggestions.enumerated()), id: \.offset) { _, item in
                    recommendationDetailRow(item)
                }

                if let session = rec.nextProgramSession {
                    Divider()
                    HStack(spacing: 6) {
                        Image(systemName: "list.bullet.clipboard")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(session.programName) · Wk \(session.weekNumber), Sess \(session.sessionNumber)" + (session.sessionName.map { " — \($0)" } ?? ""))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Session launch actions — only for program users with an identified next session.
            if rec.nextProgramSession != nil, focusRun != nil {
                Divider()
                sessionLaunchButtons(rec: rec)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.indigo.opacity(0.4), lineWidth: 1.5))
        .shadow(color: Color.indigo.opacity(0.12), radius: 10, x: 0, y: 2)
    }

    private var guidanceSafetyRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Safety Note")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(ComplianceConfiguration.doctorCheckDisclosure)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
    }

    private func recommendationDetailRow(_ item: DailyCoachSuggestionItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: suggestionIcon(item.type))
                    .font(.caption2)
                    .foregroundStyle(suggestionColor(item.type))
                Text(item.compactText)
                    .font(.caption.weight(.medium))
            }
            if !item.expandedText.isEmpty {
                Text(item.expandedText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 17)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func objectiveRecoveryRow(_ insight: ObjectiveRecoveryInsight) -> some View {
        HStack(spacing: 8) {
            Text("Objective Recovery")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            objectiveRecoveryBadge(insight.status)
            Text(insight.compactSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
        }
    }

    private func objectiveRecoveryBaselineRow(_ evaluation: ObjectiveRecoveryEvaluation) -> some View {
        HStack(spacing: 8) {
            Text("Objective Recovery")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            objectiveRecoveryStateBadge(evaluation.state)
            Text(objectiveRecoveryBaselineSummary(for: evaluation.state))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
        }
    }

    private func objectiveRecoveryBadge(_ status: ObjectiveRecoveryStatus) -> some View {
        let (label, color): (String, Color) = switch status {
        case .good: ("Good", .green)
        case .neutral: ("Neutral", .indigo)
        case .caution: ("Caution", .orange)
        }

        return Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func objectiveRecoveryStateBadge(_ state: ObjectiveRecoveryEvaluationState) -> some View {
        let (label, color): (String, Color) = switch state {
        case .disabled:
            ("Off", .secondary)
        case .notYetSynced:
            ("Sync Needed", .orange)
        case .insufficientBaseline:
            ("Building Baseline", .orange)
        case .awaitingCurrentDayMetrics:
            ("Waiting", .indigo)
        case .ready:
            ("Ready", .green)
        }

        return Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func objectiveRecoveryBaselineSummary(for state: ObjectiveRecoveryEvaluationState) -> String {
        switch state {
        case .disabled:
            return "Apple Health recovery support is off."
        case .notYetSynced:
            return "Recovery data has not synced into SuggestMeSome yet."
        case .insufficientBaseline:
            return "More Apple Health history is needed before Daily Coach can score recovery."
        case .awaitingCurrentDayMetrics:
            return "Today's comparable recovery signals have not landed yet."
        case .ready:
            return "Objective recovery is ready."
        }
    }

    private func recommendationSourcesRow(_ labels: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Recommendation Sources")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(labels, id: \.self) { label in
                    sourcePill(label)
                }
                Spacer()
            }
        }
    }

    private func whatChangedTodaySection(_ summary: TodayPlanChangeSummary) -> some View {
        let hasDetails = !summary.details.isEmpty
        let accent: Color = hasDetails ? .orange : .secondary
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: hasDetails ? "arrow.triangle.2.circlepath.circle.fill" : "checkmark.circle")
                    .font(.caption2)
                    .foregroundStyle(accent)
                Text("What Changed Today")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(summary.changeType.rawValue)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(accent.opacity(0.12))
                    .foregroundStyle(accent)
                    .clipShape(Capsule())
            }
            Text(summary.headline)
                .font(.caption)
                .foregroundStyle(.secondary)
            if hasDetails {
                ForEach(summary.details, id: \.self) { detail in
                    Text("- \(detail)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background((hasDetails ? Color.orange : Color(.tertiarySystemBackground)).opacity(hasDetails ? 0.08 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func attributionSection(_ attribution: TodayPlanSourceAttribution) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Attribution")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            attributionRow("Manual Readiness", attribution.manualReadinessInfluence)
            attributionRow("Program / Session", attribution.programPrescriptionInfluence)
            attributionRow("Overlays / Proposals", attribution.adaptiveOverlayInfluence)
            attributionRow("Recent History", attribution.recentHistoryInfluence)
            attributionRow("Apple Health", attribution.healthKitInfluence)
        }
    }

    private func nextStepGuidanceSection(_ guidance: TodayPlanNextStepGuidance) -> some View {
        let accent: Color = switch guidance.contextMode {
        case .activeProgram: .secondary
        case .standaloneHistoryInformed: .indigo
        case .standaloneLowConfidence: .orange
        }

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "point.forward.to.point.capsulepath")
                    .font(.caption2)
                    .foregroundStyle(accent)
                Text("What Next")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(guidance.contextMode.rawValue)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(accent.opacity(0.12))
                    .foregroundStyle(accent)
                    .clipShape(Capsule())
            }
            Text(guidance.headline)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(guidance.actions, id: \.self) { action in
                Text("- \(action)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func attributionRow(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sourcePill(_ label: String) -> some View {
        Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color(.tertiarySystemBackground))
            .clipShape(Capsule())
    }

    private func confidenceBadge(_ confidence: TodayPlanConfidence) -> some View {
        let (label, color): (String, Color) = switch confidence {
        case .high:   ("High Confidence", .green)
        case .medium: ("Medium Confidence", .indigo)
        case .low:    ("Low Confidence", .secondary)
        }
        return Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Adherence Rescue Card

    private func adherenceRescueCard(rescue: AdherenceRescue) -> some View {
        let (icon, accentColor): (String, Color) = switch rescue.guidanceType {
        case .continueNormalSequence: ("checkmark.circle", .green)
        case .trimAndResume:          ("calendar.badge.exclamationmark", .orange)
        case .conservativeResume:     ("exclamationmark.triangle", .red)
        }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(accentColor)
                Text("Adherence")
                    .font(.headline)
                Spacer()
                Text(rescue.guidanceType.rawValue)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(accentColor.opacity(0.12))
                    .foregroundStyle(accentColor)
                    .clipShape(Capsule())
            }
            Divider()
            Text(rescue.headline)
                .font(.subheadline.weight(.medium))
            Text(rescue.details)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func readinessTierBadge(_ tier: ReadinessTier) -> some View {
        let (label, color): (String, Color) = switch tier {
        case .strong:  ("Strong", .green)
        case .neutral: ("Solid", .blue)
        case .low:     ("Low", .orange)
        case .unknown: ("No Check-In", .secondary)
        }
        return Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func suggestionIcon(_ type: DailySuggestionType) -> String {
        switch type {
        case .runAsPlanned:                  return "checkmark.circle.fill"
        case .trimAccessories:               return "minus.circle"
        case .trimOneBackoffSet:             return "arrow.down.circle"
        case .reduceWorkingLoadsSlightly:    return "scalemass"
        case .suggestManualVariationSwap:    return "exclamationmark.triangle"
        case .standaloneRecoverySession:     return "leaf.fill"
        case .standaloneShortStrengthSession:return "bolt.fill"
        }
    }

    private func suggestionColor(_ type: DailySuggestionType) -> Color {
        switch type {
        case .runAsPlanned:                  return .green
        case .trimAccessories:               return .orange
        case .trimOneBackoffSet:             return .yellow
        case .reduceWorkingLoadsSlightly:    return .orange
        case .suggestManualVariationSwap:    return .red
        case .standaloneRecoverySession:     return .teal
        case .standaloneShortStrengthSession:return .indigo
        }
    }

    // MARK: - Proposal Awareness

    private func proposalAwarenessCard(plan: TodayPlan) -> some View {
        let todayCount = plan.proposalAwareness.filter { $0.impact == .affectsToday }.count
        let upcomingCount = plan.proposalAwareness.filter { $0.impact == .affectsUpcomingSession }.count
        let longCount = plan.proposalAwareness.filter { $0.impact == .affectsLongHorizonProgramming }.count

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Proposal Awareness", systemImage: "bell.badge")
                    .font(.headline)
                Spacer()
                Text("\(plan.proposalAwareness.count) pending")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            Divider()
            HStack(spacing: 6) {
                proposalImpactBadge("Today: \(todayCount)", color: todayCount > 0 ? .orange : .secondary)
                proposalImpactBadge("Upcoming: \(upcomingCount)", color: upcomingCount > 0 ? .indigo : .secondary)
                proposalImpactBadge("Long Horizon: \(longCount)", color: longCount > 0 ? .secondary : .gray)
                Spacer()
            }
            ForEach(Array(plan.proposalAwareness.prefix(3)), id: \.proposalID) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text(item.impact.rawValue)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(item.impact == .affectsToday ? 0.16 : 0.08))
                        .foregroundStyle(item.impact == .affectsToday ? .orange : .secondary)
                        .clipShape(Capsule())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.summaryText)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(item.targetDescription)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.4), lineWidth: 1))
    }

    private func proposalImpactBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func currentLaunchSource(for rec: DailyCoachRecommendation) -> TodayPlanChangeSource {
        if relevantProposalForTodayPlan != nil {
            return .pendingProposal
        }
        if overlaysAffectTodaySession {
            return .approvedOverlay
        }
        if rec.primarySuggestion.type != .runAsPlanned {
            return .runtimeCoachOnly
        }
        return .plannedPrescription
    }

    private func launchSourceRow(
        source: TodayPlanChangeSource,
        hasRelevantPendingProposal: Bool
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: sourceIcon(source))
                .font(.caption)
                .foregroundStyle(sourceColor(source))
            Text("Change Layer:")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(TodayPlanActionCoordinator.sourceDescription(
                source: source,
                hasRelevantPendingProposal: hasRelevantPendingProposal
            ))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    private func sourceIcon(_ source: TodayPlanChangeSource) -> String {
        switch source {
        case .pendingProposal: return "clock.badge.exclamationmark"
        case .approvedOverlay: return "checkmark.seal.fill"
        case .runtimeCoachOnly: return "bolt.heart"
        case .plannedPrescription: return "list.bullet.clipboard"
        }
    }

    private func sourceColor(_ source: TodayPlanChangeSource) -> Color {
        switch source {
        case .pendingProposal: return .orange
        case .approvedOverlay: return .green
        case .runtimeCoachOnly: return .indigo
        case .plannedPrescription: return .secondary
        }
    }

    // MARK: - Latest Session Summary Card

    private var latestSummary: SessionSummary? {
        DailyCoachSessionSummaryService.latestSummary(
            recentWorkouts: Array(recentWorkouts.prefix(1)),
            latestCheckIn: checkIns.first
        )
    }

    private var latestSessionSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Last Session", systemImage: "checkmark.seal")
                .font(.headline)

            Divider()

            if let summary = latestSummary {
                sessionSummaryContent(summary: summary)
            } else {
                Text("No sessions logged yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func sessionSummaryContent(summary: SessionSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(summary.workoutDate, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if summary.hasEffortData {
                    effortDistributionBadges(summary: summary)
                }
            }

            Text(summary.summaryText)
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)

            Divider()
            Text("What Next")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(summary.nextStepText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func effortDistributionBadges(summary: SessionSummary) -> some View {
        HStack(spacing: 5) {
            if summary.tooEasyCount > 0 {
                effortBadge(count: summary.tooEasyCount, color: .blue)
            }
            if summary.onTargetCount > 0 {
                effortBadge(count: summary.onTargetCount, color: .green)
            }
            if summary.tooHardCount > 0 {
                effortBadge(count: summary.tooHardCount, color: .orange)
            }
        }
    }

    private func effortBadge(count: Int, color: Color) -> some View {
        Text("\(count)")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Latest Weekly Review Card

    private var latestWeeklyReviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Latest Weekly Review", systemImage: "chart.bar.doc.horizontal")
                .font(.headline)

            Divider()

            if let review = latestReview {
                weeklyReviewSummary(review: review)
            } else {
                Text("No weekly review yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Reviews are generated after your first full week of tracked training.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            if let review = latestReview, !review.hasBeenSeen {
                review.hasBeenSeen = true
            }
        }
    }

    private func weeklyReviewSummary(review: DailyCoachWeeklyReview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(review.weekStart, format: .dateTime.month(.abbreviated).day())
                Text("–")
                Text(review.weekEnd, format: .dateTime.month(.abbreviated).day())
                Spacer()
                if !review.hasBeenSeen {
                    Text("New")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.indigo.opacity(0.2))
                        .foregroundStyle(.indigo)
                        .clipShape(Capsule())
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !review.headline.isEmpty {
                Text(review.headline)
                    .font(.subheadline.weight(.semibold))
            }

            if !review.winText.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(review.winText).font(.caption)
                }
            }

            if !review.watchoutText.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    Text(review.watchoutText).font(.caption)
                }
            }
        }
    }

    // MARK: - Session Launch Buttons

    @ViewBuilder
    private func sessionLaunchButtons(rec: DailyCoachRecommendation) -> some View {
        let hasRuntimeAdjustment = rec.primarySuggestion.type != .runAsPlanned
        let hasRelevantProposal = relevantProposalForTodayPlan != nil
        let hasApprovedOverlayPath = overlaysAffectTodaySession

        if hasRelevantProposal {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Button("Start As Planned") {
                        launchAsPlanned()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(.tertiarySystemBackground))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .buttonStyle(.plain)

                    Button("Review Proposal") {
                        showingProposalReview = true
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .buttonStyle(.plain)
                }
                if hasApprovedOverlayPath {
                    Button("Start Approved Version") {
                        launchApprovedVersion()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.green)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .buttonStyle(.plain)
                }
            }
            .font(.subheadline.weight(.medium))
        } else if hasApprovedOverlayPath {
            HStack(spacing: 10) {
                Button("Start As Planned") {
                    launchAsPlanned()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemBackground))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .buttonStyle(.plain)

                Button("Start Approved Version") {
                    launchApprovedVersion()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.green)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .buttonStyle(.plain)
            }
            .font(.subheadline.weight(.medium))
        } else if hasRuntimeAdjustment {
            HStack(spacing: 10) {
                Button("Start As Planned") {
                    launchAsPlanned()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemBackground))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .buttonStyle(.plain)

                Button("Review Suggested Version") {
                    prepareReviewSheet()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .buttonStyle(.plain)
            }
            .font(.subheadline.weight(.medium))
        } else {
            Button("Start As Planned") {
                launchAsPlanned()
            }
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .buttonStyle(.plain)
        }
    }

    // MARK: - Session Launch Helpers

    private var watchTodayPlanSignature: String {
        let plan = todayPlan
        let session = plan.recommendation.nextProgramSession
        return [
            focusRun?.syncStableID ?? "standalone",
            focusRun?.program?.name ?? "",
            "\(session?.weekNumber ?? 0)",
            "\(session?.sessionNumber ?? 0)",
            plan.confidence.rawValue,
            plan.recommendation.compactSummary,
            plan.recommendation.primarySuggestion.type.rawValue,
            plan.recommendation.primarySuggestion.compactText,
            "\(plan.recommendation.hasPainFlag)",
            "\(plan.recommendation.pendingProposalCount)",
            plan.recommendation.readinessTier.watchSignatureLabel,
            plan.attribution.activeSourceLabels.joined(separator: ","),
            plan.whatChangedToday,
            plan.adherenceRescue?.headline ?? "",
            "\(plan.adherenceRescue?.sessionsBehindCount ?? 0)"
        ].joined(separator: "|")
    }

    private func publishTodayPlanToWatchIfNeeded(force: Bool = false) {
        let signature = watchTodayPlanSignature
        guard force || signature != lastPublishedWatchTodayPlanSignature else { return }

        lastPublishedWatchTodayPlanSignature = signature
        let coordinator = watchSessionCoordinator ?? WatchSessionCoordinator()
        watchSessionCoordinator = coordinator
        let plan = todayPlan
        let programName = focusRun?.program?.name
        let programRunStableID = focusRun?.syncStableID

        Task { @MainActor in
            await coordinator.broadcastTodayPlan(
                plan,
                programName: programName,
                programRunStableID: programRunStableID
            )
        }
    }

    private func launchApprovedVersion() {
        launch(request: .startApprovedVersion)
    }

    private func launchAsPlanned() {
        launch(request: .startAsPlanned)
    }

    private func launch(request: TodayPlanLaunchRequest) {
        if activeWorkoutSessionStore.hasActiveSession {
            launchRequestPendingDiscard = request
            return
        }

        guard let run = focusRun,
              let session = todayPlan.recommendation.nextProgramSession else { return }
        let resolution = TodayPlanActionCoordinator.resolveLaunch(
            request: request,
            recommendation: todayPlan.recommendation,
            hasOverlayAffectingToday: overlaysAffectTodaySession
        )
        let exercises = launchExercises(
            for: run,
            week: session.weekNumber,
            session: session.sessionNumber,
            resolution: resolution
        )
        let workoutID = UUID()
        let kind = TodayPlanActionCoordinator.watchSessionPlanKind(for: resolution.path)
        let sessionVersionStableID = TodayPlanActionCoordinator.watchSessionVersionStableID(
            runStableID: run.syncStableID,
            path: resolution.path,
            weekNumber: session.weekNumber,
            sessionNumber: session.sessionNumber
        )
        let sourceLabels = TodayPlanActionCoordinator.executionSourceLabels(
            plan: todayPlan,
            resolution: resolution,
            hasRelevantPendingProposal: relevantProposalForTodayPlan != nil
        )
        pendingProgramWorkout = ProgramWorkoutContext(
            workoutID: workoutID,
            programRun: run,
            weekNumber: session.weekNumber,
            sessionNumber: session.sessionNumber,
            exercises: exercises,
            watchSessionPlanKind: kind,
            watchSessionSourceLabels: sourceLabels,
            watchSessionVersionStableID: sessionVersionStableID
        )
        pendingDraft = nil
        pendingLaunchResolution = resolution
        if resolution.usesPreparedDraft {
            let draft = DailyCoachWorkoutPreparationService.prepare(
                exercises: exercises,
                suggestionType: todayPlan.recommendation.primarySuggestion.type
            )
            pendingDraft = draft
            showingDraftReview = true
        } else {
            navigatingToWorkout = true
            broadcastWatchLaunch(
                resolution: resolution,
                run: run,
                session: session,
                entries: draftEntries(for: exercises),
                workoutID: workoutID,
                kind: kind,
                sourceLabels: sourceLabels,
                sessionVersionStableID: sessionVersionStableID
            )
        }
    }

    private func launchExercises(
        for run: ProgramRun,
        week: Int,
        session: Int,
        resolution: TodayPlanLaunchResolution
    ) -> [ProgramSessionExercise] {
        switch resolution.path {
        case .approvedOverlayAdjusted:
            return ProgramOverlayResolutionService.resolvedExercises(
                for: run,
                week: week,
                session: session,
                context: modelContext
            )
        case .planned, .runtimeAdjusted:
            return ProgramOverlayResolutionService.baseExercises(
                for: run,
                week: week,
                session: session
            )
        }
    }

    /// Prompt 5 — publish a watch-safe launch snapshot so a paired companion
    /// app immediately reflects which version of the session the user is
    /// executing (planned vs approved-overlay vs runtime-adjusted). Swallows
    /// all transport errors; the iPhone remains authoritative if the watch is
    /// offline or uninstalled.
    private func broadcastWatchLaunch(
        resolution: TodayPlanLaunchResolution,
        run: ProgramRun,
        session: NextProgramSessionInfo,
        entries: [DraftExerciseEntry],
        workoutID: UUID = UUID(),
        kind: WatchSessionPlanKind? = nil,
        sourceLabels: [String]? = nil,
        sessionVersionStableID: String? = nil
    ) {
        let coordinator = watchSessionCoordinator ?? WatchSessionCoordinator()
        watchSessionCoordinator = coordinator
        let plan = todayPlan
        let resolvedKind = kind ?? TodayPlanActionCoordinator.watchSessionPlanKind(for: resolution.path)
        let resolvedVersionStableID = sessionVersionStableID ?? TodayPlanActionCoordinator.watchSessionVersionStableID(
            runStableID: run.syncStableID,
            path: resolution.path,
            weekNumber: session.weekNumber,
            sessionNumber: session.sessionNumber
        )
        let startedAt = Date()
        let resolvedSourceLabels = sourceLabels ?? TodayPlanActionCoordinator.executionSourceLabels(
            plan: plan,
            resolution: resolution,
            hasRelevantPendingProposal: relevantProposalForTodayPlan != nil
        )
        let sessionLabel = nextSessionLabel(for: session)
        Task { @MainActor in
            await coordinator.broadcastWorkoutLaunch(
                workoutID: workoutID,
                startedAt: startedAt,
                programRunID: run.id,
                programWeekNumber: session.weekNumber,
                programSessionNumber: session.sessionNumber,
                sessionPlanKind: resolvedKind,
                sessionSourceLabels: resolvedSourceLabels,
                sessionVersionStableID: resolvedVersionStableID
            )
            await coordinator.broadcastTodayPlan(
                plan,
                programName: run.program?.name,
                programRunStableID: run.syncStableID
            )
            await coordinator.broadcastLiveWorkout(
                workoutID: workoutID,
                elapsedSeconds: 0,
                entries: entries,
                sessionLabel: sessionLabel,
                programRunStableID: run.syncStableID,
                programWeekNumber: session.weekNumber,
                programSessionNumber: session.sessionNumber,
                sessionPlanKind: resolvedKind,
                sessionSourceLabels: resolvedSourceLabels,
                sessionVersionStableID: resolvedVersionStableID
            )
            await coordinator.broadcastCurrentSessionContext(
                workoutID: workoutID,
                entries: entries,
                sessionPlanKind: resolvedKind,
                sessionSourceLabels: resolvedSourceLabels,
                sessionVersionStableID: resolvedVersionStableID
            )
        }
    }

    private func broadcastWatchLaunch(
        resolution: TodayPlanLaunchResolution,
        context: ProgramWorkoutContext,
        entries: [DraftExerciseEntry]
    ) {
        let currentSession = todayPlan.recommendation.nextProgramSession
        let session = NextProgramSessionInfo(
            weekNumber: context.weekNumber,
            sessionNumber: context.sessionNumber,
            sessionName: currentSession?.sessionName,
            programName: context.programRun.program?.name ?? currentSession?.programName ?? "Program"
        )
        broadcastWatchLaunch(
            resolution: resolution,
            run: context.programRun,
            session: session,
            entries: entries,
            workoutID: context.workoutID,
            kind: context.watchSessionPlanKind,
            sourceLabels: context.watchSessionSourceLabels,
            sessionVersionStableID: context.watchSessionVersionStableID
        )
    }

    private func draftEntries(for exercises: [ProgramSessionExercise]) -> [DraftExerciseEntry] {
        let allPersonalRecords = TrainingContextQueryService.fetchPersonalRecords(context: modelContext)
        return ProgramWorkoutDraftBuilder.buildEntries(from: exercises) { anchor in
            TrainingContextQueryService.preferredUnit(
                for: anchor.exerciseName,
                in: allPersonalRecords
            )
        }
    }

    private func prepareReviewSheet() {
        launch(request: .startRuntimeAdjusted)
    }

    private func presentLatestCompletedReview() {
        blockReviewSnapshot = latestCompletedReviewSnapshot
    }

    private func commitStagedProposalDecision(_ staged: StagedTodayPlanProposalDecision) {
        guard let proposal = relevantProposalForTodayPlan else { return }
        do {
            try TodayPlanActionCoordinator.commitStagedDecision(
                staged,
                proposal: proposal,
                context: modelContext
            )
            stagedProposalDecision = nil
        } catch {
            proposalActionErrorMessage = error.localizedDescription
        }
    }

    private func nextSessionLabel(for session: NextProgramSessionInfo?) -> String {
        guard let s = session else { return "Next Session" }
        let base = "Week \(s.weekNumber), Session \(s.sessionNumber)"
        if let name = s.sessionName, !name.isEmpty { return "\(base) — \(name)" }
        return base
    }

    // MARK: - Helpers

    private func fatigueColor(_ status: FatigueStatus) -> Color {
        switch status {
        case .low:        return .green
        case .manageable: return .blue
        case .elevated:   return .yellow
        case .high:       return .orange
        case .critical:   return .red
        }
    }
}

private extension ReadinessTier {
    var watchSignatureLabel: String {
        switch self {
        case .strong: return "Strong"
        case .neutral: return "Neutral"
        case .low: return "Low"
        case .unknown: return "Unknown"
        }
    }
}

// MARK: - TodayPlanProposalReviewSheet

private struct TodayPlanProposalReviewSheet: View {
    let proposal: AdaptationProposal
    let program: TrainingProgram?
    let onApprove: () -> Void
    let onReject: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let summary = AdaptationProposalPresentationService.makeDisplaySummary(
            for: proposal,
            program: program
        )
        NavigationStack {
            List {
                Section("Proposal") {
                    Text(summary.title)
                        .font(.subheadline.weight(.semibold))
                    Text(summary.changeSummary)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(summary.affectedWindowText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Why") {
                    Text(summary.reasonText)
                        .font(.subheadline)
                    if let detail = summary.detailText, !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section {
                    Text("Approve/reject requires one more confirmation. Base program rows are never mutated.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Review Proposal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button("Reject", role: .destructive) {
                        onReject()
                    }
                    Button("Approve") {
                        onApprove()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - DraftReviewSheet

private struct DraftReviewSheet: View {
    let draft: PreparedWorkoutDraft
    let sessionLabel: String
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(sessionLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Session")
                }

                Section {
                    if draft.changeDescriptions.isEmpty {
                        Text("No changes — session will run as planned.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(draft.changeDescriptions.enumerated()), id: \.offset) { _, desc in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: changeIcon)
                                    .font(.subheadline)
                                    .foregroundStyle(changeColor)
                                    .frame(width: 20)
                                Text(desc)
                                    .font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    Text("Suggested Changes")
                } footer: {
                    Text("These changes apply only to today's session. Your program is not modified.")
                        .font(.caption)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Review Suggested Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start Suggested Session") {
                        onConfirm()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var changeIcon: String {
        switch draft.adjustmentType {
        case .trimAccessories:            return "minus.circle"
        case .trimOneBackoffSet:          return "arrow.down.circle"
        case .reduceWorkingLoadsSlightly: return "scalemass"
        case .suggestManualVariationSwap: return "exclamationmark.triangle"
        default:                          return "checkmark.circle"
        }
    }

    private var changeColor: Color {
        switch draft.adjustmentType {
        case .trimAccessories:            return .orange
        case .trimOneBackoffSet:          return .yellow
        case .reduceWorkingLoadsSlightly: return .orange
        case .suggestManualVariationSwap: return .red
        default:                          return .green
        }
    }
}
