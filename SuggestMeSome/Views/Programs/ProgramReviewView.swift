//
//  ProgramReviewView.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/7/26.
//

import SwiftUI
import SwiftData

// The five inline helpers that used to live here (exerciseDisplayText,
// workingSetStyleLabel, workingSetStyleColor, exercisePurposeLabel,
// exerciseSelectionReasonLabel) moved into ExerciseDisplayFormatter +
// its SwiftUI sibling so Daily Coach previews, coach-facing views, and
// headless tests can reuse them without reaching into a view file.

// MARK: - ProgramReviewView

struct ProgramReviewView: View {
    let program: TrainingProgram
    let input: ProgramGenerationInput
    let onStartProgram: () -> Void
    let onRegenerate: () -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var editableName: String = ""
    @State private var isEditingName = false
    @State private var expandedPhaseIDs: Set<String> = []
    @State private var expandedWeeks: Set<Int> = []
    @State private var expandedSessions: Set<String> = []
    @State private var derivedState = ProgramReviewDerivedState.placeholder

    @State private var editingExercise: ProgramSessionExercise?
    @State private var addingToSession: ProgramSessionTemplate?
    @State private var showRegenerateAlert = false
    @State private var showAdditionalInfo = false

    private var reviewRefreshToken: Int {
        ProgramReviewDerivedState.refreshToken(program: program, input: input)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                summaryHeaderView
                    .padding()
                Divider()
                phaseListView
                    .padding(.bottom, 96)
            }
        }
        .safeAreaInset(edge: .bottom) { actionBarView }
        .onAppear { editableName = program.name }
        .task(id: reviewRefreshToken) {
            refreshDerivedState()
        }
        .alert("Regenerate Program?", isPresented: $showRegenerateAlert) {
            Button("Regenerate", role: .destructive) { onRegenerate() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will discard your edits. Regenerate?")
        }
        .sheet(item: $editingExercise) { exercise in
            ExerciseEditSheet(exercise: exercise, input: input)
        }
        .sheet(item: $addingToSession) { session in
            ReviewExercisePickerSheet { exerciseName in
                addExercise(named: exerciseName, to: session)
            }
        }
    }

    // MARK: Summary Header

    @ViewBuilder
    private var summaryHeaderView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Program name (editable)
            HStack(alignment: .center, spacing: 8) {
                if isEditingName {
                    TextField("Program Name", text: $editableName)
                        .font(.title2.weight(.bold))
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.done)
                        .onSubmit { commitName() }
                } else {
                    Text(editableName.isEmpty ? program.name : editableName)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                }
                Button(action: {
                    if isEditingName { commitName() } else { isEditingName = true }
                }) {
                    Image(systemName: isEditingName ? "checkmark.circle.fill" : "pencil")
                        .foregroundStyle(.teal)
                        .font(.subheadline)
                }
            }

            // Metadata badges
            HStack(spacing: 8) {
                levelBadge
                Text("\(input.durationWeeks) weeks")
                    .badgeStyle()
                Text("\(program.sessionsPerWeek)/week")
                    .badgeStyle()
            }

            HStack(spacing: 8) {
                Text("Show Additional Info")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("", isOn: $showAdditionalInfo)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .scaleEffect(0.85)
            }

            if showAdditionalInfo {
                programLogicSection
            }

            if let adaptiveExplanationBundle = derivedState.adaptiveExplanationBundle {
                AdaptiveExplanationCard(
                    bundle: adaptiveExplanationBundle,
                    title: "Coach Notes",
                    compact: false
                )
            }

            // Periodization description
            if let desc = program.descriptionText {
                Text(desc)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Block phase breakdown
            if input.level == .advanced {
                Text(blockBreakdownText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var programLogicSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Program Logic")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                logicRow("Progression", value: derivedState.programLogic.progressionModel)
                logicRow("Lift Mapping", value: boolLabel(derivedState.programLogic.usedLiftMapping))
                logicRow("Volume Balance", value: boolLabel(derivedState.programLogic.usedVolumeBalancing))
                logicRow("Fatigue Balance", value: boolLabel(derivedState.programLogic.usedFatigueBalancing))
                logicRow("Top+Backoff", value: boolLabel(derivedState.programLogic.usedTopSetBackoff))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func logicRow(_ label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }

    private func boolLabel(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }

    private var levelBadge: some View {
        let (label, color): (String, Color) = {
            switch input.level {
            case .beginner:     return ("Beginner", .green)
            case .intermediate: return ("Intermediate", .orange)
            case .advanced:     return ("Advanced", .purple)
            }
        }()
        return Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var blockBreakdownText: String {
        let sequence: [(String?, Int)]
        switch input.durationWeeks {
        case 6:  sequence = [("Hypertrophy", 2), (nil, 1), ("Strength", 2), ("Peaking", 1)]
        case 8:  sequence = [("Hypertrophy", 3), (nil, 1), ("Strength", 2), ("Peaking", 1), (nil, 1)]
        case 10: sequence = [("Hypertrophy", 3), (nil, 1), ("Strength", 3), (nil, 1), ("Peaking", 2)]
        case 12: sequence = [("Hypertrophy", 4), (nil, 1), ("Strength", 3), (nil, 1), ("Peaking", 2), (nil, 1)]
        default: sequence = [("Hypertrophy", 4), (nil, 1), ("Strength", 3), (nil, 1), ("Peaking", 2), (nil, 1)]
        }
        var parts: [String] = []
        var w = 1
        for (name, count) in sequence {
            let range = count == 1 ? "Week \(w)" : "Weeks \(w)–\(w + count - 1)"
            parts.append("\(range): \(name ?? "Deload")")
            w += count
        }
        return parts.joined(separator: " → ")
    }

    // MARK: Phase List

    private var phaseListView: some View {
        VStack(spacing: 0) {
            ForEach(derivedState.phaseGroups) { group in
                PhaseCardView(
                    group: group,
                    isExpanded: expandedPhaseIDs.contains(group.id),
                    showAdditionalInfo: showAdditionalInfo,
                    expandedWeeks: $expandedWeeks,
                    expandedSessions: $expandedSessions,
                    editingExercise: $editingExercise,
                    addingToSession: $addingToSession,
                    weeklySummariesByWeek: derivedState.weeklySummariesByWeek,
                    input: input,
                    onTogglePhase: { togglePhase(id: group.id) },
                    onDeleteExercise: deleteExercise
                )
                Divider()
            }
        }
    }

    // MARK: Action Bar

    private var actionBarView: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Button(action: { showRegenerateAlert = true }) {
                    Text("Regenerate")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.secondarySystemBackground))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator), lineWidth: 0.5))
                }

                Button(action: startProgram) {
                    Text("Start Program")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.teal)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal)
            .padding(.top, 10)
            .padding(.bottom, 20)
            .background(Color(.systemBackground))
        }
    }

    // MARK: Actions

    private func commitName() {
        program.name = editableName.isEmpty ? program.name : editableName
        isEditingName = false
    }

    private func togglePhase(id: String) {
        if expandedPhaseIDs.contains(id) { expandedPhaseIDs.remove(id) }
        else { expandedPhaseIDs.insert(id) }
    }

    private func startProgram() {
        commitName()
        let startDate = Date.now
        let run = ProgramRun(startDate: startDate)
        run.program = program

        if let sourceStableID = input.carryForwardContext?.sourceProgramRunStableID {
            let sourceRun = ProgramRunContinuityService.sourceRun(
                matching: sourceStableID,
                context: modelContext
            )
            ProgramRunContinuityService.applyAcceptedContinuity(
                to: run,
                sourceRun: sourceRun,
                input: input,
                startedAt: startDate
            )
        }

        modelContext.insert(run)
        try? modelContext.save()
        CloudSyncManager.shared.notifyLocalMutation("Started program run")
        onStartProgram()
    }

    private func addExercise(named name: String, to session: ProgramSessionTemplate) {
        let nextOrder = (session.exercises.map(\.orderIndex).max() ?? -1) + 1
        let ex = ProgramSessionExercise(
            exerciseName: name,
            orderIndex: nextOrder,
            targetSets: 3,
            targetReps: 8,
            targetRPE: 7.0,
            targetEffortType: .rpe
        )
        modelContext.insert(ex)
        ex.session = session
    }

    private func deleteExercise(_ exercise: ProgramSessionExercise) {
        modelContext.delete(exercise)
    }

    private func refreshDerivedState() {
        derivedState = ProgramReviewDerivedState.build(
            program: program,
            input: input,
            context: modelContext,
            previous: derivedState
        )
    }
}

// MARK: - Badge Style Helper

private extension Text {
    func badgeStyle() -> some View {
        self
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(.tertiarySystemBackground))
            .clipShape(Capsule())
    }
}

// MARK: - PhaseCardView

