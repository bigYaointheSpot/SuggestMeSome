import SwiftData
import SwiftUI

struct TrainingProgramsTab: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator
    @Environment(AppRouteCoordinator.self) private var appRouteCoordinator
    @Query private var programRuns: [ProgramRun]
    @Query(sort: \Workout.date, order: .reverse) private var allWorkouts: [Workout]
    @Query private var allProposals: [AdaptationProposal]
    @Query private var allEvents: [AdaptationEventHistory]
    @Query(sort: \AppliedProgramOverlay.appliedAt, order: .reverse) private var allOverlays: [AppliedProgramOverlay]
    @State private var showingAIGenerator = false
    @State private var listSnapshot = ProgramRunListSnapshot.placeholder
    @State private var plannedSessionPreviewCache: [ProgramRunSessionPreviewKey: ProgramSessionPreviewSnapshot] = [:]
    @State private var loadingSessionPreviewKeys: Set<ProgramRunSessionPreviewKey> = []

    private var programsRefreshToken: Int {
        ProgramRunListSnapshot.refreshToken(
            programRuns: programRuns,
            workouts: allWorkouts,
            proposals: allProposals,
            events: allEvents
        )
    }

    private var previewCacheRefreshToken: Int {
        ProgramRunListSnapshot.previewCacheRefreshToken(
            overlays: allOverlays
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                programButtonRow
                collaborationButtonRow
                Divider()
                programRunList
            }
            .navigationTitle("Training Programs")
            .navigationBarTitleDisplayMode(.large)
            .fullScreenCover(isPresented: $showingAIGenerator) {
                AIProgramGeneratorView()
            }
            .task(id: programsRefreshToken) {
                refreshListSnapshot()
            }
            .task(id: previewCacheRefreshToken) {
                clearPlannedSessionPreviewCache()
            }
            .sheet(
                item: Binding(
                    get: {
                        guard let route = appRouteCoordinator.activeRoute,
                              route.targetTab == .programs else {
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
    }

    private var programButtonRow: some View {
        HStack(spacing: 8) {
            NavigationLink {
                CreateProgramView()
            } label: {
                programButtonLabel("Create Program", systemImage: "plus.rectangle")
            }

            NavigationLink {
                SelectProgramView()
            } label: {
                programButtonLabel("Use Template", systemImage: "list.bullet.rectangle")
            }

            Button(action: { showingAIGenerator = true }) {
                programButtonLabel("Smart Generate", systemImage: "wand.and.stars")
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var collaborationButtonRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                NavigationLink {
                    AssignmentInboxView()
                } label: {
                    collaborationPill(
                        "Assignments",
                        systemImage: "tray.full",
                        detail: "\(collaborationCoordinator.inboxAssignments.count) pending"
                    )
                }

                NavigationLink {
                    BlueprintLibraryView()
                } label: {
                    collaborationPill(
                        "Blueprints",
                        systemImage: "square.stack.3d.up.fill",
                        detail: "\(collaborationCoordinator.blueprints.count) saved"
                    )
                }

                NavigationLink {
                    CollaborationHubView()
                } label: {
                    collaborationPill(
                        "Coach Hub",
                        systemImage: "person.2.wave.2.fill",
                        detail: "\(collaborationCoordinator.relationships.count) linked"
                    )
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    private func programButtonLabel(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .frame(height: 24)
            Text(title)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.indigo.gradient)
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func collaborationPill(_ title: String, systemImage: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var programRunList: some View {
        if listSnapshot.orderedRuns.isEmpty {
            if programRuns.isEmpty {
                ContentUnavailableView(
                    "No Programs Yet",
                    systemImage: "list.clipboard",
                    description: Text("Create or start a program above to track your progress.")
                )
                .frame(maxHeight: .infinity)
            } else {
                ProgressView("Loading Programs...")
                    .frame(maxHeight: .infinity)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(listSnapshot.orderedRuns) { run in
                        ProgramRunExpandableRow(
                            run: run,
                            snapshot: listSnapshot.snapshot(for: run),
                            plannedSessionPreview: { key in
                                plannedSessionPreviewCache[key]
                            },
                            isLoadingSessionPreview: { key in
                                loadingSessionPreviewKeys.contains(key)
                            },
                            loadSessionPreview: { key in
                                loadSessionPreviewIfNeeded(for: key, run: run)
                            }
                        )
                        Divider()
                    }
                }
            }
        }
    }

    private func refreshListSnapshot() {
        listSnapshot = ProgramRunListSnapshot.build(
            programRuns: programRuns,
            workouts: allWorkouts,
            proposals: allProposals,
            events: allEvents
        )
        clearPlannedSessionPreviewCache()
    }

    private func clearPlannedSessionPreviewCache() {
        plannedSessionPreviewCache = [:]
        loadingSessionPreviewKeys = []
    }

    private func loadSessionPreviewIfNeeded(
        for key: ProgramRunSessionPreviewKey,
        run: ProgramRun
    ) {
        guard plannedSessionPreviewCache[key] == nil else { return }
        guard !loadingSessionPreviewKeys.contains(key) else { return }

        loadingSessionPreviewKeys.insert(key)
        plannedSessionPreviewCache[key] = ProgramSessionPreviewSnapshot.load(
            for: run,
            weekNumber: key.weekNumber,
            sessionNumber: key.sessionNumber,
            context: modelContext
        )
        loadingSessionPreviewKeys.remove(key)
    }
}

struct ProgramRunRow: View {
    let run: ProgramRun
    let snapshot: ProgramRunRowSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(run.program?.name ?? "Unknown Program")
                    .font(.headline)
                Spacer()
                Text(run.isCompleted ? "Completed" : "Active")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(run.isCompleted ? Color.gray.opacity(0.25) : Color.green.opacity(0.25))
                    .foregroundStyle(run.isCompleted ? Color.secondary : Color.green)
                    .clipShape(Capsule())
            }
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.caption)
                Text(run.startDate.formatted(date: .abbreviated, time: .omitted))
                Text("·")
                Text("\(snapshot.completedWorkoutCount)/\(snapshot.totalWorkoutCount) workouts")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct ProgramRunExpandableRow: View {
    @Bindable var run: ProgramRun
    let snapshot: ProgramRunRowSnapshot
    let plannedSessionPreview: (ProgramRunSessionPreviewKey) -> ProgramSessionPreviewSnapshot?
    let isLoadingSessionPreview: (ProgramRunSessionPreviewKey) -> Bool
    let loadSessionPreview: (ProgramRunSessionPreviewKey) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var isExpanded = false
    @State private var selectedWeek = 1
    @State private var expandedSessions: Set<Int> = []
    @State private var showingEndConfirmation = false
    @State private var showingDeleteHistoryConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rowHeader
            if isExpanded {
                expandedContent
                    .transition(.opacity)
            }
        }
        .confirmationDialog("End Program?", isPresented: $showingEndConfirmation, titleVisibility: .visible) {
            Button("End Program", role: .destructive) {
                let completedAt = Date.now
                run.isCompleted = true
                run.endDate = completedAt
                run.markSyncUpdated(at: completedAt)
                try? modelContext.save()
                CloudSyncManager.shared.notifyLocalMutation("Completed program run")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will mark the program as completed.")
        }
        .confirmationDialog("Delete Program History?", isPresented: $showingDeleteHistoryConfirmation, titleVisibility: .visible) {
            Button("Delete from History", role: .destructive) {
                try? TrainingHistoryDeletionService.deleteProgramRunHistory(run, context: modelContext)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the completed run, its linked workouts, and its adaptive history. Personal records will be rebuilt from any remaining workouts.")
        }
    }

    private var rowHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(alignment: .center, spacing: 8) {
                ProgramRunRow(run: run, snapshot: snapshot)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.2), value: isExpanded)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            infoSection
            Divider()
            adaptationHistoryRow
            Divider()
            adaptiveProposalRow
            if run.isCompleted {
                Divider()
                blockReviewRow
                Divider()
                deleteHistoryRow
            }
            if !run.isCompleted {
                Divider()
                endProgramRow
            }
            Divider()
            weekPickerSection
            Divider()
            sessionSection
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(snapshot.sourceLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.12))
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 5) {
                infoRow(label: "Status") {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(run.isCompleted ? Color.gray : Color.green)
                            .frame(width: 7, height: 7)
                        Text(run.isCompleted ? "Completed" : "Active")
                            .foregroundStyle(run.isCompleted ? Color.secondary : Color.green)
                    }
                }
                infoRow(label: "Started") {
                    Text(run.startDate.formatted(date: .abbreviated, time: .omitted))
                }
                if let endDate = run.endDate {
                    infoRow(label: "Ended") {
                        Text(endDate.formatted(date: .abbreviated, time: .omitted))
                    }
                }
                infoRow(label: "Length") {
                    Text("\(run.program?.lengthInWeeks ?? 0) weeks")
                }
                infoRow(label: "Progress") {
                    Text("\(snapshot.completedWorkoutCount) of \(snapshot.totalWorkoutCount) workouts completed")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
    }

    private var adaptationHistoryRow: some View {
        NavigationLink {
            AdaptationHistoryView(run: run)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.teal)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Adaptation History")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(
                        snapshot.adaptationEventCount == 0
                            ? "No adaptation events yet"
                            : "\(snapshot.adaptationEventCount) recorded event\(snapshot.adaptationEventCount == 1 ? "" : "s")"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color(.secondarySystemBackground))
    }

    private var adaptiveProposalRow: some View {
        NavigationLink {
            AdaptationProposalReviewView(run: run)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "brain.head.profile")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Adaptive Proposals")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(
                        snapshot.pendingProposalCount == 0
                            ? "No pending confirmations"
                            : "\(snapshot.pendingProposalCount) pending confirmation\(snapshot.pendingProposalCount == 1 ? "" : "s")"
                    )
                    .font(.caption)
                    .foregroundStyle(snapshot.pendingProposalCount == 0 ? Color.secondary : Color.orange)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color(.secondarySystemBackground))
    }

    @ViewBuilder
    private func infoRow<V: View>(label: String, @ViewBuilder value: () -> V) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            value()
        }
        .font(.subheadline)
    }

    private var blockReviewRow: some View {
        Group {
            if snapshot.blockReviewAvailable {
                NavigationLink {
                    ProgramRunBlockReviewScreen(run: run)
                } label: {
                    blockReviewRowLabel
                }
                .buttonStyle(.plain)
            } else {
                blockReviewRowLabel
                    .opacity(0.6)
            }
        }
        .background(Color(.secondarySystemBackground))
    }

    private var blockReviewRowLabel: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.teal)
            VStack(alignment: .leading, spacing: 2) {
                Text("Block Review")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("See what happened and what's next")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var endProgramRow: some View {
        Button {
            showingEndConfirmation = true
        } label: {
            Text("End Program")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color(.secondarySystemBackground))
    }

    private var deleteHistoryRow: some View {
        Button {
            showingDeleteHistoryConfirmation = true
        } label: {
            Text("Delete from History")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color(.secondarySystemBackground))
    }

    private var weekPickerSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(1...(run.program?.lengthInWeeks ?? 1), id: \.self) { week in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedWeek = week
                            expandedSessions = []
                        }
                    } label: {
                        Text("Week \(week)")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(selectedWeek == week ? Color.blue : Color(.tertiarySystemBackground))
                            .foregroundStyle(selectedWeek == week ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(.secondarySystemBackground))
    }

    @ViewBuilder
    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let sessionsPerWeek = run.program?.sessionsPerWeek, sessionsPerWeek > 0 {
                ForEach(1...sessionsPerWeek, id: \.self) { sessionNumber in
                    sessionCard(sessionNumber: sessionNumber)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private func sessionCard(sessionNumber: Int) -> some View {
        let previewKey = ProgramRunSessionPreviewKey(
            runID: run.id,
            weekNumber: selectedWeek,
            sessionNumber: sessionNumber
        )
        let workout = snapshot.completedWorkout(
            weekNumber: selectedWeek,
            sessionNumber: sessionNumber,
            runID: run.id
        )
        let isCompleted = workout != nil
        let isSessionExpanded = expandedSessions.contains(sessionNumber)

        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isSessionExpanded {
                        expandedSessions.remove(sessionNumber)
                    } else {
                        expandedSessions.insert(sessionNumber)
                    }
                }
            } label: {
                HStack {
                    Text("Session \(sessionNumber)")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if isCompleted {
                        Label("Completed", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    } else {
                        Text("Not completed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isSessionExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.15), value: isSessionExpanded)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isSessionExpanded {
                Divider().padding(.leading, 14)
                if let workout {
                    sessionWorkoutDetail(workout: workout)
                } else {
                    sessionPlannedDetail(previewKey: previewKey)
                }
            }
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator), lineWidth: 0.5))
    }

    @ViewBuilder
    private func sessionWorkoutDetail(workout: Workout) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink {
                WorkoutDetailView(workout: workout)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workout.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(workout.formattedDuration)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label("View Full Workout", systemImage: "arrow.right.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.blue)
                }
                .padding(12)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.3), lineWidth: 1))
            }

            ForEach(workout.exerciseEntries.sorted { $0.orderIndex < $1.orderIndex }) { entry in
                ExerciseDetailCard(entry: entry)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private func sessionPlannedDetail(previewKey: ProgramRunSessionPreviewKey) -> some View {
        if let preview = plannedSessionPreview(previewKey) {
            if preview.isEmpty {
                Text("No exercises planned for this session.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(14)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(preview.workingExercises) { exercise in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(exercise.exerciseName)
                                    .font(.subheadline)
                                Text(exercise.detailText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if exercise.warmupCount > 0 {
                                Text("\(exercise.warmupCount) warmup sets")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                    .padding(.top, 2)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        if exercise.id != preview.workingExercises.last?.id {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
            }
        } else {
            HStack(spacing: 10) {
                ProgressView()
                Text(isLoadingSessionPreview(previewKey) ? "Loading session preview..." : "Preparing session preview...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .task(id: previewKey) {
                loadSessionPreview(previewKey)
            }
        }
    }
}

private struct ProgramRunBlockReviewScreen: View {
    let run: ProgramRun

    @Environment(\.modelContext) private var modelContext
    @State private var snapshot: MesocycleReviewSnapshot?
    @State private var hasLoadedSnapshot = false

    var body: some View {
        Group {
            if let snapshot {
                MesocycleReviewView(snapshot: snapshot)
            } else if hasLoadedSnapshot {
                ContentUnavailableView(
                    "Block Review Unavailable",
                    systemImage: "chart.bar.doc.horizontal",
                    description: Text("This block review could not be loaded right now.")
                )
            } else {
                ProgressView("Loading Block Review...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: run.id) {
            snapshot = TrainingReadRepository.mesocycleReviewSnapshot(
                for: run,
                context: modelContext
            )
            hasLoadedSnapshot = true
        }
    }
}
