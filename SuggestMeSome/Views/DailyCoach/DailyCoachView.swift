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

    @Query(sort: \DailyCoachCheckIn.date, order: .reverse)
    private var checkIns: [DailyCoachCheckIn]

    @Query(sort: \DailyCoachWeeklyReview.weekStart, order: .reverse)
    private var weeklyReviews: [DailyCoachWeeklyReview]

    @Query(sort: \LiftPerformanceTrend.updatedAt, order: .reverse)
    private var liftTrends: [LiftPerformanceTrend]

    @Query(sort: \HealthKitDailySummary.dayStart, order: .reverse)
    private var healthKitDailySummaries: [HealthKitDailySummary]

    @AppStorage("healthkit.enabled") private var healthKitEnabled = false
    @AppStorage("healthkit.dailyCoachEnabled") private var useHealthKitInDailyCoach = false

    // MARK: Computed helpers

    private var focusRun: ProgramRun? { activeRuns.first }

    private var pendingProposals: [AdaptationProposal] {
        allProposals.filter { $0.proposalStatus == .pendingUserConfirmation }
    }

    private var latestAnalysis: WeeklyTrainingAnalysis? { weeklyAnalyses.first }

    private var latestReview: DailyCoachWeeklyReview? { weeklyReviews.first }

    private var todayRecommendation: DailyCoachRecommendation {
        DailyCoachRecommendationService.generate(
            checkIn: todayCheckIn,
            activeRun: focusRun,
            latestAnalysis: latestAnalysis,
            pendingProposalCount: pendingProposals.count,
            recentWorkouts: Array(recentWorkouts.prefix(20)),
            objectiveRecoveryInsight: objectiveRecoveryInsight
        )
    }

    private var objectiveRecoveryInsight: ObjectiveRecoveryInsight? {
        guard healthKitEnabled, useHealthKitInDailyCoach else { return nil }
        return HealthKitRecoveryInsightService.computeInsight(
            from: Array(healthKitDailySummaries.prefix(90))
        )
    }

    private var todayCheckIn: DailyCoachCheckIn? {
        let today = Calendar.current.startOfDay(for: Date())
        return checkIns.first { Calendar.current.startOfDay(for: $0.date) == today }
    }

    // MARK: Sheet / navigation state

    @State private var showingCheckInSheet = false
    @State private var recommendationExpanded = false

    // Workout launch
    @State private var navigatingToWorkout = false
    @State private var pendingProgramWorkout: ProgramWorkoutContext?
    @State private var pendingDraft: PreparedWorkoutDraft?
    @State private var showingDraftReview = false
    @State private var confirmedDraftLaunch = false

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    todayTrainingCard
                    readinessCard
                    coachRecommendationCard
                    if !pendingProposals.isEmpty {
                        pendingProposalsRow
                    }
                    latestSessionSummaryCard
                    latestWeeklyReviewCard
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .navigationTitle("Daily Coach")
            .navigationBarTitleDisplayMode(.large)
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    navigatingToWorkout = true
                }
            }
        }) {
            if let draft = pendingDraft {
                DraftReviewSheet(
                    draft: draft,
                    sessionLabel: nextSessionLabel(for: todayRecommendation.nextProgramSession)
                ) {
                    confirmedDraftLaunch = true
                    showingDraftReview = false
                }
            }
        }
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
        VStack(alignment: .leading, spacing: 6) {
            Text("No active program")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Daily Coach works without a program. Log workouts and check in daily to get personalized recommendations.")
                .font(.caption)
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
        let rec = todayRecommendation
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Coach Recommendation", systemImage: "brain.head.profile")
                    .font(.headline)
                Spacer()
                if rec.hasPainFlag {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                }
                readinessTierBadge(rec.readinessTier)
            }

            Divider()

            if let insight = rec.objectiveRecoveryInsight {
                objectiveRecoveryRow(insight)
            }

            recommendationSourcesRow(rec.recommendationSources)

            // Compact summary
            Text(rec.compactSummary)
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)

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

                Text(rec.expandedDetails)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(rec.sourceAttributionDetails)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if let insight = rec.objectiveRecoveryInsight {
                    Text(insight.detailSummary)
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

    private func objectiveRecoveryBadge(_ status: ObjectiveRecoveryStatus) -> some View {
        let (label, color): (String, Color) = switch status {
        case .good: ("Good", .green)
        case .neutral: ("Neutral", .blue)
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

    private func recommendationSourcesRow(_ sources: [DailyCoachRecommendationSource]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Recommendation Sources")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(sources, id: \.rawValue) { source in
                    sourcePill(source.rawValue)
                }
                Spacer()
            }
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
        case .standaloneShortStrengthSession:return .blue
        }
    }

    // MARK: - Pending Proposals Row

    private var pendingProposalsRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.badge")
                .foregroundStyle(.orange)
            Text("\(pendingProposals.count) pending proposal\(pendingProposals.count == 1 ? "" : "s")")
                .font(.subheadline)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
                        .background(Color.blue.opacity(0.2))
                        .foregroundStyle(.blue)
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
        let canPrepareDraft = rec.primarySuggestion.type != .runAsPlanned
        if canPrepareDraft {
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

    private func launchAsPlanned() {
        guard let run = focusRun,
              let session = todayRecommendation.nextProgramSession else { return }
        let exercises = ProgramOverlayResolutionService.resolvedExercises(
            for: run, week: session.weekNumber, session: session.sessionNumber, context: modelContext
        )
        pendingProgramWorkout = ProgramWorkoutContext(
            programRun: run,
            weekNumber: session.weekNumber,
            sessionNumber: session.sessionNumber,
            exercises: exercises
        )
        pendingDraft = nil
        navigatingToWorkout = true
    }

    private func prepareReviewSheet() {
        guard let run = focusRun,
              let session = todayRecommendation.nextProgramSession else { return }
        let exercises = ProgramOverlayResolutionService.resolvedExercises(
            for: run, week: session.weekNumber, session: session.sessionNumber, context: modelContext
        )
        let draft = DailyCoachWorkoutPreparationService.prepare(
            exercises: exercises,
            suggestionType: todayRecommendation.primarySuggestion.type
        )
        pendingProgramWorkout = ProgramWorkoutContext(
            programRun: run,
            weekNumber: session.weekNumber,
            sessionNumber: session.sessionNumber,
            exercises: exercises
        )
        pendingDraft = draft
        showingDraftReview = true
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
