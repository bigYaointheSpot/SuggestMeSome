import SwiftUI

struct ExerciseFilterSheet: View {
    let muscleGroups: [MuscleGroup]
    @Binding var selectedGroupNames: Set<String>
    @Binding var selectedExerciseNames: Set<String>

    @Environment(\.dismiss) private var dismiss
    @State private var expandedGroups: Set<String> = []

    private var totalSelected: Int {
        selectedGroupNames.count + selectedExerciseNames.count
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(muscleGroups) { group in
                    Section {
                        if expandedGroups.contains(group.name) {
                            ForEach(group.exercises.sorted { $0.name < $1.name }) { exercise in
                                exerciseRow(exercise)
                            }
                        }
                    } header: {
                        groupHeader(group)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(totalSelected == 0 ? "Filter by Exercise" : "\(totalSelected) selected")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if totalSelected > 0 {
                        Button("Clear All") {
                            selectedGroupNames = []
                            selectedExerciseNames = []
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func groupHeader(_ group: MuscleGroup) -> some View {
        let groupSelected = selectedGroupNames.contains(group.name)
        let isExpanded = expandedGroups.contains(group.name)

        return HStack(spacing: 0) {
            Button {
                if groupSelected {
                    selectedGroupNames.remove(group.name)
                } else {
                    selectedGroupNames.insert(group.name)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: groupSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(groupSelected ? .indigo : Color(.systemGray3))
                        .font(.title3)
                    Text(group.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .textCase(nil)
                }
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedGroups.remove(group.name)
                    } else {
                        expandedGroups.insert(group.name)
                    }
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.2), value: isExpanded)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
        }
        .padding(.vertical, 2)
    }

    private func exerciseRow(_ exercise: Exercise) -> some View {
        let isSelected = selectedExerciseNames.contains(exercise.name)

        return Button {
            if isSelected {
                selectedExerciseNames.remove(exercise.name)
            } else {
                selectedExerciseNames.insert(exercise.name)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .indigo : Color(.systemGray3))
                    .font(.title3)
                Text(exercise.name)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.leading, 8)
        }
    }
}
