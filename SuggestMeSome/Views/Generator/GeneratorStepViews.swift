import SwiftUI

struct SuggestMeSomeConfigurationStepView: View {
    @Bindable var viewModel: SuggestMeSomeGeneratorFlowViewModel
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                modeSection
                goalSection
                equipmentSection
                DurationPickerView(duration: viewModel.configuration.durationMinutes) {
                    viewModel.updateDuration($0)
                }
                IntensitySelectorView(intensity: viewModel.configuration.intensity) {
                    viewModel.updateIntensity($0)
                }
                continueButton
            }
            .padding()
        }
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Mode", systemImage: "dial.high")
                .font(.headline)

            let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(SuggestMeSomeSessionMode.allCases) { mode in
                    selectionChip(
                        title: mode.title,
                        isSelected: viewModel.configuration.mode == mode
                    ) {
                        viewModel.configuration.mode = mode
                    }
                }
            }
        }
    }

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Goal", systemImage: "target")
                .font(.headline)

            let columns = [GridItem(.adaptive(minimum: 130), spacing: 8)]
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(SuggestMeSomeGenerationGoal.allCases) { goal in
                    selectionChip(
                        title: goal.title,
                        isSelected: viewModel.configuration.goal == goal
                    ) {
                        viewModel.configuration.goal = goal
                    }
                }
            }
        }
    }

    private var equipmentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Equipment Profile", systemImage: "dumbbell")
                .font(.headline)

            Picker("Equipment", selection: $viewModel.configuration.equipmentProfile) {
                ForEach(SuggestMeSomeEquipmentProfile.allCases) { profile in
                    Text(profile.title).tag(profile)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var continueButton: some View {
        Button {
            onContinue()
        } label: {
            Label("Get Recommendation", systemImage: "sparkles")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.purple)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.top, 4)
    }

    private func selectionChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 42)
                .padding(.horizontal, 8)
                .background(isSelected ? Color.blue : Color(.secondarySystemBackground))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct SuggestMeSomeRecommendationStepView: View {
    @Bindable var viewModel: SuggestMeSomeGeneratorFlowViewModel
    let onBuildWorkout: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                recommendationCard
                inputsSummaryCard

                Button {
                    onBuildWorkout()
                } label: {
                    Label("Build Workout", systemImage: "hammer.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!(viewModel.recommendation?.isBuildableIntoWorkout ?? false))
            }
            .padding()
        }
    }

    @ViewBuilder
    private var recommendationCard: some View {
        if let recommendation = viewModel.recommendation {
            VStack(alignment: .leading, spacing: 10) {
                Label("Recommended Session", systemImage: "lightbulb.max.fill")
                    .font(.headline)
                Text(recommendation.title)
                    .font(.title3.weight(.semibold))
                Text(recommendation.summary)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(recommendation.rationale)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                recommendationListSection(
                    title: "Movement Priorities",
                    values: recommendation.recommendedMovementPriorities
                )
                recommendationListSection(
                    title: "Exercise Families",
                    values: recommendation.candidateExerciseFamilies
                )
                recommendationListSection(
                    title: "Anchor Lifts",
                    values: recommendation.candidateAnchorLifts
                )
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            ContentUnavailableView(
                "Recommendation Unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text("Go back and re-run the session recommendation.")
            )
        }
    }

    private var inputsSummaryCard: some View {
        let config = viewModel.configuration

        return VStack(alignment: .leading, spacing: 8) {
            Label("Session Inputs", systemImage: "slider.horizontal.3")
                .font(.headline)

            summaryRow("Mode", config.mode.title)
            summaryRow("Goal", config.goal.title)
            summaryRow("Equipment", config.equipmentProfile.title)
            summaryRow("Duration", "\(config.durationMinutes) min")
            summaryRow("Intensity", "\(config.intensity)")
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
    }

    private func recommendationListSection(title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if values.isEmpty {
                Text("No specific targets.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(values, id: \.self) { value in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(value)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
