import SwiftUI
import SwiftData

struct GeneratorSheetRootView: View {
    let onStart: (GeneratedWorkout) -> Void

    @Query(sort: \MuscleGroup.name) private var allMuscleGroups: [MuscleGroup]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(PurchaseManager.self) private var purchaseManager

    @State private var viewModel: SuggestMeSomeGeneratorFlowViewModel?

    var body: some View {
        Group {
            if FeatureAccessPolicy.isAccessible(
                .smartWorkoutGeneration,
                entitlementState: purchaseManager.entitlementState
            ) {
                NavigationStack {
                    Group {
                        if let viewModel {
                            GeneratorFlowContainerView(
                                viewModel: viewModel,
                                allMuscleGroups: allMuscleGroups,
                                onStart: onStart,
                                onClose: { dismiss() }
                            )
                        } else {
                            ProgressView("Loading Generator...")
                        }
                    }
                }
                .onAppear {
                    if viewModel == nil {
                        viewModel = SuggestMeSomeGeneratorFlowViewModel(context: modelContext)
                    }
                }
            } else {
                NavigationStack {
                    PremiumGateView(feature: .smartWorkoutGeneration)
                }
            }
        }
    }
}

private struct GeneratorFlowContainerView: View {
    @Bindable var viewModel: SuggestMeSomeGeneratorFlowViewModel
    let allMuscleGroups: [MuscleGroup]
    let onStart: (GeneratedWorkout) -> Void
    let onClose: () -> Void

    var body: some View {
        Group {
            switch viewModel.step {
            case .configure:
                SuggestMeSomeConfigurationStepView(viewModel: viewModel) {
                    viewModel.makeRecommendation(allMuscleGroups: allMuscleGroups)
                }
            case .recommendation:
                SuggestMeSomeRecommendationStepView(viewModel: viewModel) {
                    viewModel.buildWorkoutFromRecommendation()
                }
            case .build:
                SuggestMeSomeBuildStepView(viewModel: viewModel) { workout in
                    onStart(workout)
                }
            }
        }
        .navigationTitle(viewModel.currentStepTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(viewModel.step == .configure ? "Cancel" : "Back") {
                    if viewModel.step == .configure {
                        onClose()
                    } else {
                        viewModel.moveBack()
                    }
                }
            }
        }
    }
}
