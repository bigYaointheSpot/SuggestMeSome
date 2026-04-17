//
//  HealthDataSettingsView.swift
//  SuggestMeSome
//
//  Feature 8 — User-facing Health Data settings and authorization controls.
//

import SwiftUI
import HealthKit
import Combine
import SwiftData

enum HealthDataSyncStatus: Equatable {
    case idle
    case syncing
    case success(Date)
    case failed(String)
}

enum HealthWorkoutImportStatus: Equatable {
    case idle
    case importing
    case success(String)
    case failed(String)
}

@MainActor
final class HealthDataSettingsViewModel: ObservableObject {
    @Published private(set) var snapshot = HealthKitAuthorizationSnapshot(
        availability: .unavailable,
        readStatuses: [],
        workoutWriteStatus: .notDetermined,
        requestStatus: nil,
        hasRequestedAuthorization: false
    )
    @Published private(set) var isLoading = false
    @Published private(set) var syncStatus: HealthDataSyncStatus = .idle
    @Published private(set) var workoutImportStatus: HealthWorkoutImportStatus = .idle
    @Published private(set) var watchStatus: WatchCompanionStatus = .unsupported()

    private let authorizationService = HealthKitAuthorizationService()
    private let recoverySyncService = HealthKitRecoverySyncService()
    private let workoutImportService = HealthKitWorkoutImportService()
    private let recoveryAutoRefreshCoordinator = HealthKitRecoveryAutoRefreshCoordinator.shared
    private let watchBridge: WatchCompanionBridge

    init(watchBridge: WatchCompanionBridge? = nil) {
        self.watchBridge = watchBridge ?? DefaultWatchCompanionBridge.shared
    }

    func refreshStatus(hasRequestedAuthorization: Bool) async {
        isLoading = true
        snapshot = await authorizationService.refreshAuthorizationStatus(
            hasRequestedAuthorization: hasRequestedAuthorization
        )
        isLoading = false
    }

    func refreshWatchStatus() async {
        watchStatus = await watchBridge.refreshStatus()
    }

    func requestAuthorization(hasRequestedAuthorization: Bool) async {
        isLoading = true
        snapshot = await authorizationService.requestAuthorization(
            hasRequestedAuthorization: hasRequestedAuthorization
        )
        isLoading = false
    }

    func syncRecoverySummaries(context: ModelContext) async -> Bool {
        syncStatus = .syncing
        do {
            try await recoverySyncService.syncLast90Days(context: context)
            let now = Date()
            HealthKitSettingsStorage.setDate(now, forKey: HealthKitSettingsStorage.recoveryLastSyncTimestampKey)
            syncStatus = .success(now)
            return true
        } catch let error as HealthKitRecoverySyncError {
            switch error {
            case .healthDataUnavailable:
                syncStatus = .failed("Apple Health data is unavailable on this device.")
            }
            return false
        } catch {
            syncStatus = .failed("Recovery sync failed. Check Apple Health permissions and try again.")
            return false
        }
    }

    func autoRefreshRecoveryIfNeeded(
        context: ModelContext,
        trigger: HealthKitRecoveryRefreshTrigger
    ) async {
        syncStatus = .syncing
        let outcome = await recoveryAutoRefreshCoordinator.refreshIfNeeded(
            trigger: trigger,
            context: context
        )
        switch outcome {
        case .skipped:
            syncStatus = .idle
        case .synced(dayCount: _, syncedAt: let syncedAt):
            syncStatus = .success(syncedAt)
        case .failed:
            syncStatus = .failed("Automatic recovery refresh failed. Check Apple Health permissions and try again.")
        }
    }

    func syncImportedWorkouts(context: ModelContext) async -> Bool {
        workoutImportStatus = .importing
        do {
            let result = try await workoutImportService.importLast90Days(context: context)
            HealthKitSettingsStorage.setDate(
                Date(),
                forKey: HealthKitSettingsStorage.workoutImportLastSyncTimestampKey
            )
            workoutImportStatus = .success(result.summaryText)
            return true
        } catch let error as HealthKitWorkoutImportError {
            switch error {
            case .healthDataUnavailable:
                workoutImportStatus = .failed("Apple Health data is unavailable on this device.")
            case .workoutReadDenied:
                workoutImportStatus = .failed("Workout read access is denied. Enable workout read permissions in Apple Health settings.")
            }
            return false
        } catch {
            workoutImportStatus = .failed("Workout import failed. Check Apple Health permissions and try again.")
            return false
        }
    }
}

struct HealthDataSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PurchaseManager.self) private var purchaseManager
    @StateObject private var viewModel = HealthDataSettingsViewModel()
    @State private var showingPreflight = false
    @State private var showingAboutGuidance = false

    @AppStorage("healthkit.enabled") private var healthKitEnabled = false
    @AppStorage("healthkit.dailyCoachEnabled") private var useHealthKitInDailyCoach = false
    @AppStorage("healthkit.importWorkouts") private var importHealthKitWorkouts = false
    @AppStorage("healthkit.writeWorkouts") private var writeAppWorkoutsToHealthKit = false
    @AppStorage("healthkit.permissionsRequested") private var healthKitPermissionsRequested = false
    @AppStorage(HealthKitSettingsStorage.recoveryLastSyncTimestampKey)
    private var recoveryLastSyncTimestamp: Double = 0
    @AppStorage(HealthKitSettingsStorage.workoutImportLastSyncTimestampKey)
    private var workoutImportLastSyncTimestamp: Double = 0

    private var recoveryLastSyncDate: Date? {
        guard recoveryLastSyncTimestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: recoveryLastSyncTimestamp)
    }

    private var workoutImportLastSyncDate: Date? {
        guard workoutImportLastSyncTimestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: workoutImportLastSyncTimestamp)
    }

    private var isUnavailable: Bool {
        viewModel.snapshot.availability == .unavailable
    }

    private var isConnected: Bool {
        viewModel.snapshot.isConnected
    }

    private var isDenied: Bool {
        viewModel.snapshot.isDenied
    }

    private var isSyncing: Bool {
        if case .syncing = viewModel.syncStatus {
            return true
        }
        return false
    }

    private var isImportingWorkouts: Bool {
        if case .importing = viewModel.workoutImportStatus {
            return true
        }
        return false
    }

    var body: some View {
        Group {
            if FeatureAccessPolicy.isAccessible(.healthData, entitlementState: purchaseManager.entitlementState) {
                List {
                    connectionStatusSection
                    appleWatchSection
                    dailyCoachUsageSection
                    workoutSyncSection
                    dataReadSection
                    dataWriteSection
                    privacyNotesSection
                }
                .listStyle(.insetGrouped)
                .navigationTitle("Apple Health")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("About") {
                            showingAboutGuidance = true
                        }
                    }
                }
                .task {
                    await viewModel.refreshStatus(hasRequestedAuthorization: healthKitPermissionsRequested)
                    await viewModel.refreshWatchStatus()
                }
                .sheet(isPresented: $showingPreflight) {
                    NavigationStack {
                        HealthDataPreflightView {
                            Task {
                                healthKitPermissionsRequested = true
                                await viewModel.requestAuthorization(hasRequestedAuthorization: true)
                                await viewModel.autoRefreshRecoveryIfNeeded(
                                    context: modelContext,
                                    trigger: .authorizationStatusUpdated
                                )
                            }
                        }
                    }
                }
                .sheet(isPresented: $showingAboutGuidance) {
                    NavigationStack {
                        AboutThisGuidanceView()
                    }
                }
            } else {
                PremiumGateView(feature: .healthData)
            }
        }
    }

    private var connectionStatusSection: some View {
        Section("Connection Status") {
            Toggle("Enable Apple Health", isOn: $healthKitEnabled)
                .disabled(isUnavailable)

            HStack {
                Text("Status")
                Spacer()
                Text(statusTitle)
                    .foregroundStyle(statusColor)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let recoveryLastSyncDate {
                HStack {
                    Text("Recovery Sync")
                    Spacer()
                    Text(recoveryLastSyncDate, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack {
                    Text("Recovery Sync")
                    Spacer()
                    Text("No sync yet")
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.isLoading {
                ProgressView("Checking Apple Health…")
            }

            Button(connectButtonTitle) {
                Task {
                    if viewModel.snapshot.canPresentAuthorizationPrompt {
                        showingPreflight = true
                    } else {
                        await viewModel.refreshStatus(hasRequestedAuthorization: healthKitPermissionsRequested)
                        await viewModel.autoRefreshRecoveryIfNeeded(
                            context: modelContext,
                            trigger: .authorizationStatusUpdated
                        )
                    }
                }
            }
            .disabled(!healthKitEnabled || isUnavailable || viewModel.isLoading)

            Button("Refresh Status") {
                Task {
                    await viewModel.refreshStatus(hasRequestedAuthorization: healthKitPermissionsRequested)
                    await viewModel.autoRefreshRecoveryIfNeeded(
                        context: modelContext,
                        trigger: .authorizationStatusUpdated
                    )
                }
            }
            .disabled(isUnavailable || viewModel.isLoading)

            Button("Sync Recovery Data (Last 90 Days)") {
                Task {
                    _ = await viewModel.syncRecoverySummaries(context: modelContext)
                }
            }
            .disabled(!healthKitEnabled || isUnavailable || viewModel.isLoading || isSyncing)

            syncStatusMessage
        }
    }

    private var dailyCoachUsageSection: some View {
        Section("Daily Coach Usage") {
            Toggle("Use Apple Health in Daily Coach", isOn: $useHealthKitInDailyCoach)
                .disabled(!healthKitEnabled || isUnavailable)

            Text("The app reads optional Apple Health recovery data to lightly assist Daily Coach readiness decisions.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("Daily Coach stays in baseline mode until recovery data has synced at least once and today's comparable Apple Health signals are available.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var appleWatchSection: some View {
        Section("Apple Watch") {
            HStack {
                Text("Status")
                Spacer()
                Text(watchStatusTitle)
                    .foregroundStyle(watchStatusColor)
            }

            Text(viewModel.watchStatus.message)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("Opening the watch app refreshes companion presence and replays the latest Today Plan or live workout state when the bridge reconnects.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if viewModel.watchStatus.checkedAt.timeIntervalSince1970 > 0 {
                HStack {
                    Text("Last Checked")
                    Spacer()
                    Text(
                        viewModel.watchStatus.checkedAt,
                        format: .dateTime.month(.abbreviated).day().year().hour().minute()
                    )
                    .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("Last Watch Contact")
                Spacer()
                if let lastWatchContactAt = viewModel.watchStatus.lastWatchContactAt {
                    Text(
                        lastWatchContactAt,
                        format: .dateTime.month(.abbreviated).day().year().hour().minute()
                    )
                    .foregroundStyle(.secondary)
                } else {
                    Text("No contact yet")
                        .foregroundStyle(.secondary)
                }
            }

#if DEBUG
            HStack {
                Text("Activation State")
                Spacer()
                Text(viewModel.watchStatus.activationState.rawValue)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Paired")
                Spacer()
                Text(yesNoText(viewModel.watchStatus.isPaired))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Companion Installed")
                Spacer()
                Text(yesNoText(viewModel.watchStatus.isCompanionAppInstalled))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Reachable")
                Spacer()
                Text(yesNoText(viewModel.watchStatus.isReachable))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Last Payload Replay")
                Spacer()
                if let lastPayloadReplayAt = viewModel.watchStatus.lastPayloadReplayAt {
                    Text(
                        lastPayloadReplayAt,
                        format: .dateTime.month(.abbreviated).day().year().hour().minute()
                    )
                    .foregroundStyle(.secondary)
                } else {
                    Text("No replay yet")
                        .foregroundStyle(.secondary)
                }
            }
#endif

            Button("Refresh Watch Status") {
                Task {
                    await viewModel.refreshWatchStatus()
                }
            }
            .disabled(viewModel.isLoading)
        }
    }

    private var workoutSyncSection: some View {
        Section("Workout Sync") {
            Toggle("Import Apple Health Workouts", isOn: $importHealthKitWorkouts)
                .disabled(!healthKitEnabled || isUnavailable)

            Toggle("Write App Workouts to Apple Health", isOn: $writeAppWorkoutsToHealthKit)
                .disabled(!healthKitEnabled || isUnavailable)

            Button("Import Workouts (Last 90 Days)") {
                Task {
                    _ = await viewModel.syncImportedWorkouts(context: modelContext)
                }
            }
            .disabled(
                !healthKitEnabled ||
                isUnavailable ||
                viewModel.isLoading ||
                isImportingWorkouts ||
                !importHealthKitWorkouts
            )

            Text("Imported workouts are labeled as Apple Health imports so source attribution stays clear.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("Imported workouts include source and activity metadata; set-by-set strength detail is not fabricated during import.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("Workout writeback is limited to workout type, timing, duration, and optional active energy.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let workoutImportLastSyncDate {
                HStack {
                    Text("Last Workout Import")
                    Spacer()
                    Text(workoutImportLastSyncDate, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack {
                    Text("Last Workout Import")
                    Spacer()
                    Text("No import yet")
                        .foregroundStyle(.secondary)
                }
            }

            workoutImportStatusMessage
        }
    }

    private var dataReadSection: some View {
        Section("Data Read") {
            Text("Sleep Analysis")
            Text("Resting Heart Rate")
            Text("Heart Rate Variability (SDNN)")
            Text("Active Energy")
            Text("Step Count")
            Text("Body Mass")
            Text("Workouts (for import)")
        }
    }

    private var dataWriteSection: some View {
        Section("Data Write") {
            Text("Workout summaries created in SuggestMeSome")
        }
    }

    private var privacyNotesSection: some View {
        Section("Privacy Notes") {
            Text("Apple Health access is optional and user-controlled.")
            Text("SuggestMeSome still works fully without Apple Health.")
            Text("You can change these permissions at any time in Apple Health or in Settings > Privacy & Security > Health.")
            Text(ComplianceConfiguration.premiumUnlockDisclosure)
            Text(ComplianceConfiguration.appleHealthDisclosure)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private var statusTitle: String {
        if isUnavailable { return "Unavailable" }
        if isDenied { return "Denied" }
        if isConnected { return "Connected" }
        return "Disconnected"
    }

    private var statusColor: Color {
        if isUnavailable || isDenied { return .red }
        if isConnected { return .green }
        return .secondary
    }

    private var statusMessage: String? {
        if isUnavailable {
            return "Apple Health data is unavailable on this device."
        }
        if isDenied {
            return "Apple Health access is denied. Enable access in Apple Health or iOS Privacy settings."
        }
        if isConnected {
            if viewModel.snapshot.isWorkoutWriteDenied {
                return "Apple Health permissions are configured. Workout writeback is off; enable workout write access in Apple Health settings if you want SuggestMeSome to write saved workouts."
            }
            return "Apple Health permissions are active."
        }
        return "Apple Health is not connected yet."
    }

    private var connectButtonTitle: String {
        if !viewModel.snapshot.canPresentAuthorizationPrompt {
            return "Refresh Permission Status"
        }
        return "Connect Apple Health"
    }

    private var watchStatusTitle: String {
        switch viewModel.watchStatus.availability {
        case .unsupported:
            return "Unavailable"
        case .statusPending:
            return "Connecting"
        case .notPaired:
            return "Not Paired"
        case .pairedNoCompanionApp:
            return "Paired"
        case .companionInstalled:
            return "Companion Installed"
        case .reachable:
            return "Reachable"
        }
    }

    private var watchStatusColor: Color {
        switch viewModel.watchStatus.availability {
        case .unsupported:
            return .secondary
        case .statusPending:
            return .secondary
        case .notPaired, .pairedNoCompanionApp:
            return .orange
        case .companionInstalled:
            return .green
        case .reachable:
            return .green
        }
    }

    private func yesNoText(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }

    @ViewBuilder
    private var syncStatusMessage: some View {
        switch viewModel.syncStatus {
        case .idle:
            EmptyView()
        case .syncing:
            ProgressView("Syncing recovery data…")
        case .success(let date):
            Text("Recovery sync completed \(date, format: .dateTime.hour().minute().second()).")
                .font(.footnote)
                .foregroundStyle(.green)
        case .failed(let message):
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var workoutImportStatusMessage: some View {
        switch viewModel.workoutImportStatus {
        case .idle:
            EmptyView()
        case .importing:
            ProgressView("Importing workouts…")
        case .success(let summary):
            Text("Workout import completed. \(summary)")
                .font(.footnote)
                .foregroundStyle(.green)
        case .failed(let message):
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }
}
