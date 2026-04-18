//
//  ActiveProgramCard.swift
//  SuggestMeSome
//
//  Snapshot of the currently running program with progress ring + actions.
//

import SwiftUI

struct ActiveProgramCard: View {
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
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            HStack(spacing: DSSpacing.l) {
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

                if let analysis = latestAnalysis {
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(analysis.fatigueStatus.dsAccentColor)
                                .frame(width: 7, height: 7)
                            Text(analysis.fatigueStatus.dsDisplayName)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(analysis.fatigueStatus.dsAccentColor)
                        }
                        Text(String(format: "%.0f%% adherence", min(analysis.adherenceScore, 1.0) * 100))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

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

            HStack(spacing: DSSpacing.s) {
                Button(action: onContinue) {
                    Text("Continue Program")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.indigo)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous))
                }

                if let reviewAction = onReviewProposals {
                    Button(action: reviewAction) {
                        Image(systemName: "brain.head.profile")
                            .font(.subheadline.weight(.semibold))
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(Color.indigo.opacity(0.15))
                            .foregroundStyle(.indigo)
                            .clipShape(RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous))
                    }
                }
            }
        }
        .dsCardStyle()
    }
}
