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
            recentWorkouts: Array(recentWorkouts.prefix(20))
        )
    }

    private var todayCheckIn: DailyCoachCheckIn? {
        let today = Calendar.current.startOfDay(for: Date())
        return checkIns.first { Calendar.current.startOfDay(for: $0.date) == today }
    }

    // MARK: Sheet state

    @State private var showingCheckInSheet = false
    @State private var recommendationExpanded = false

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
                    latestWeeklyReviewCard
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .navigationTitle("Daily Coach")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(isPresented: $showingCheckInSheet) {
            CheckInFormView(existingCheckIn: todayCheckIn)
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
