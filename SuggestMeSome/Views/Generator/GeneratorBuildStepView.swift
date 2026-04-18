import SwiftUI

struct SuggestMeSomeBuildStepView: View {
    @Bindable var viewModel: SuggestMeSomeGeneratorFlowViewModel
    let onStart: (GeneratedWorkout) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sessionIdentityHeader
                AdaptiveSteeringControlsCard(
                    profile: viewModel.steeringProfile,
                    title: "Session Steering",
                    subtitle: "Changing these controls rebuilds the preview inside the same guardrails."
                ) { viewModel.updateSteering($0) }

                if let workout = viewModel.generatedWorkout {
                    if let note = workout.adaptationNote {
                        adaptationBanner(note)
                    }
                    if let recommendation = viewModel.recommendation {
                        CoachPresentationSummaryCard(
                            copy: CoachPresentationService.builtSession(
                                recommendation: recommendation,
                                workout: workout
                            ),
                            eyebrow: "Coach Call",
                            accent: .purple,
                            supportLimit: 1
                        )
                    }
                    if let bundle = workout.explanationBundle {
                        AdaptiveExplanationCard(
                            bundle: bundle,
                            title: "Coach Notes",
                            compact: true
                        )
                    }

                    if workout.exercises.isEmpty {
                        emptyState(for: viewModel.recommendation?.mode)
                            .padding(.top, 40)
                    } else {
                        ForEach(workout.exercises.indices, id: \.self) { index in
                            exerciseCard(workout.exercises[index], role: exerciseRole(at: index, in: workout.exercises))
                        }
                        startButton(workout)
                    }
                } else {
                    ProgressView("Building session…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }
            }
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    viewModel.reshuffleWorkout()
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                }
                .disabled(viewModel.generatedWorkout == nil)
            }
        }
    }

    // MARK: - Session identity header

    private var sessionIdentityHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let recommendation = viewModel.recommendation {
                Text(recommendation.title)
                    .font(.title3.weight(.semibold))
            }

            HStack(spacing: 10) {
                let request = viewModel.recommendation?.request
                let duration = Int(request?.durationMinutes ?? Double(viewModel.configuration.durationMinutes))
                let intensity = request?.intensity ?? viewModel.configuration.intensity
                let count = viewModel.generatedWorkout?.exercises.count ?? 0

                Label("\(duration) min", systemImage: "clock")
                Text("·").foregroundStyle(.tertiary)
                Label("Intensity \(intensity)", systemImage: "bolt.fill")
                Text("·").foregroundStyle(.tertiary)
                Label("\(count) \(count == 1 ? "exercise" : "exercises")", systemImage: "dumbbell")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Adaptation banner

    private func adaptationBanner(_ note: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "wand.and.stars")
                .font(.subheadline)
                .foregroundStyle(.purple)
                .padding(.top, 1)
            Text(note)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.purple.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.purple.opacity(0.2), lineWidth: 0.5)
        )
    }

    // MARK: - Exercise role

    private func exerciseRole(at index: Int, in exercises: [GeneratedExercise]) -> String {
        let exercise = exercises[index]
        switch exercise.exercise.exerciseType {
        case .cardio:
            return "Cardio"
        case .compound:
            let firstCompoundIndex = exercises.firstIndex { $0.exercise.exerciseType == .compound }
            return firstCompoundIndex == index ? "Main Lift" : "Supporting"
        case .isolation:
            return "Isolation"
        case .accessory:
            return "Accessory"
        }
    }

    private func roleColor(_ role: String) -> Color {
        switch role {
        case "Main Lift": return .blue
        case "Supporting": return .orange
        case "Cardio": return .red
        default: return Color(.systemGray2)
        }
    }

    // MARK: - Exercise cards

    @ViewBuilder
    private func exerciseCard(_ exercise: GeneratedExercise, role: String) -> some View {
        if exercise.exercise.exerciseType == .cardio {
            cardioCard(exercise, role: role)
        } else {
            strengthCard(exercise, role: role)
        }
    }

    private func cardioCard(_ exercise: GeneratedExercise, role: String) -> some View {
        let totalSeconds = Int(exercise.effectiveTimeMinutes * 60)
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        let durationText = secs > 0
            ? String(format: "%d min %02d sec", mins, secs)
            : "\(mins) min"

        return HStack(spacing: 12) {
            Image(systemName: "heart.fill")
                .foregroundStyle(.red)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.exercise.name).font(.headline)
                Text(durationText).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            roleLabel(role)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func strengthCard(_ exercise: GeneratedExercise, role: String) -> some View {
        let warmupSets = exercise.sets.filter(\.isWarmup)
        let workingSets = exercise.sets.filter { !$0.isWarmup }
        let unit = exercise.sets.first?.unit ?? .lbs

        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(exercise.exercise.name).font(.headline)
                    Spacer()
                    roleLabel(role)
                }
                if let note = exercise.substitutionNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.purple.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))

            HStack(spacing: 8) {
                Text("SET").frame(width: 40, alignment: .center)
                Text("REPS").frame(maxWidth: .infinity)
                Text("WEIGHT (\(unit.rawValue))").frame(maxWidth: .infinity)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.tertiarySystemBackground))

            if !warmupSets.isEmpty {
                sectionLabel("WARMUP")
                ForEach(warmupSets.indices, id: \.self) { index in
                    setRow(warmupSets[index], isWarmup: true)
                    if index < warmupSets.count - 1 {
                        Divider().padding(.leading, 12)
                    }
                }
            }

            if !workingSets.isEmpty {
                sectionLabel("WORKING")
                ForEach(workingSets.indices, id: \.self) { index in
                    setRow(workingSets[index], isWarmup: false)
                    if index < workingSets.count - 1 {
                        Divider().padding(.leading, 12)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
    }

    private func roleLabel(_ role: String) -> some View {
        Text(role)
            .font(.caption.weight(.semibold))
            .foregroundStyle(roleColor(role))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(roleColor(role).opacity(0.12))
            .clipShape(Capsule())
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
    }

    private func setRow(_ set: GeneratedSet, isWarmup: Bool) -> some View {
        HStack(spacing: 8) {
            Text(isWarmup ? "W\(set.setNumber)" : "\(set.setNumber)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isWarmup ? Color(.systemGray3) : .secondary)
                .frame(width: 40, alignment: .center)

            Text("\(set.suggestedReps)")
                .frame(maxWidth: .infinity, alignment: .center)

            Text(set.suggestedWeight.map { formatWeight($0) } ?? "—")
                .frame(maxWidth: .infinity, alignment: .center)
                .foregroundStyle(set.suggestedWeight == nil ? Color(.systemGray3) : .primary)
        }
        .font(.subheadline)
        .foregroundStyle(isWarmup ? .secondary : .primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    // MARK: - Empty states

    @ViewBuilder
    private func emptyState(for mode: SuggestMeSomeSessionMode?) -> some View {
        switch mode {
        case .recovery:
            ContentUnavailableView(
                "No Recovery Exercises",
                systemImage: "arrow.counterclockwise.heart",
                description: Text("No recovery-compatible exercises matched your equipment profile. Try Full Gym or Home Gym.")
            )
        case .conditioning:
            ContentUnavailableView(
                "No Conditioning Exercises",
                systemImage: "heart.circle",
                description: Text("No cardio or conditioning exercises matched your equipment profile. Try Full Gym or Home Gym.")
            )
        default:
            ContentUnavailableView(
                "No Exercises Generated",
                systemImage: "dumbbell",
                description: Text("Try a different mode, equipment profile, or increase the duration.")
            )
        }
    }

    // MARK: - Start button

    private func startButton(_ workout: GeneratedWorkout) -> some View {
        Button {
            onStart(workout)
        } label: {
            Label("Start Session", systemImage: "play.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.green)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.top, 4)
    }

    private func formatWeight(_ weight: Double) -> String {
        weight.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(weight))
            : String(format: "%.1f", weight)
    }
}
