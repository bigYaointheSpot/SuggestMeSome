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
    private let watchBridge: WatchCompanionBridge

    init(watchBridge: WatchCompanionBridge? = nil) {
        self.watchBridge = watchBridge ?? DefaultWatchCompanionBridge()
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
            syncStatus = .success(now)
            return true
        } catch let error as HealthKitRecoverySyncError {
            switch error {
            case .healthDataUnavailable:
                syncStatus = .failed("Health data is unavailable on this device.")
            }
            return false
        } catch {
            syncStatus = .failed("Recovery sync failed. Check Health permissions and try again.")
            return false
        }
    }

    func syncImportedWorkouts(context: ModelContext) async -> Bool {
        workoutImportStatus = .importing
        do {
            let result = try await workoutImportService.importLast90Days(context: context)
            workoutImportStatus = .success(result.summaryText)
            return true
        } catch let error as HealthKitWorkoutImportError {
            switch error {
            case .healthDataUnavailable:
                workoutImportStatus = .failed("Health data is unavailable on this device.")
            case .workoutReadDenied:
                workoutImportStatus = .failed("Workout read access is denied. Enable workout read permissions in Health settings.")
            }
            return false
        } catch {
            workoutImportStatus = .failed("Workout import failed. Check Health permissions and try again.")
            return false
        }
    }
}

struct HealthDataSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = HealthDataSettingsViewModel()

    @AppStorage("healthkit.enabled") private var healthKitEnabled = false
    @AppStorage("healthkit.dailyCoachEnabled") private var useHealthKitInDailyCoach = false
    @AppStorage("healthkit.importWorkouts") private var importHealthKitWorkouts = false
    @AppStorage("healthkit.writeWorkouts") private var writeAppWorkoutsToHealthKit = false
    @AppStorage("healthkit.permissionsRequested") private var healthKitPermissionsRequested = false
    @AppStorage("healthkit.lastSyncTimestamp") private var healthKitLastSyncTimestamp: Double = 0

    private var lastSyncDate: Date? {
        guard healthKitLastSyncTimestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: healthKitLastSyncTimestamp)
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
        .navigationTitle("Health Data")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.refreshStatus(hasRequestedAuthorization: healthKitPermissionsRequested)
            await viewModel.refreshWatchStatus()
        }
    }

    private var connectionStatusSection: some View {
        Section("Connection Status") {
            Toggle("Enable HealthKit", isOn: $healthKitEnabled)
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

            if let lastSyncDate {
                HStack {
                    Text("Last Sync")
                    Spacer()
                    Text(lastSyncDate, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack {
                    Text("Last Sync")
                    Spacer()
                    Text("No sync yet")
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.isLoading {
                ProgressView("Checking HealthKit…")
            }

            Button(connectButtonTitle) {
                Task {
                    healthKitPermissionsRequested = true
                    await viewModel.requestAuthorization(hasRequestedAuthorization: true)
                }
            }
            .disabled(!healthKitEnabled || isUnavailable || viewModel.isLoading)

            Button("Refresh Status") {
                Task {
                    await viewModel.refreshStatus(hasRequestedAuthorization: healthKitPermissionsRequested)
                }
            }
            .disabled(isUnavailable || viewModel.isLoading)

            Button("Sync Recovery Data (Last 90 Days)") {
                Task {
                    let didSync = await viewModel.syncRecoverySummaries(context: modelContext)
                    if didSync {
                        healthKitLastSyncTimestamp = Date().timeIntervalSince1970
                    }
                }
            }
            .disabled(!healthKitEnabled || isUnavailable || viewModel.isLoading || isSyncing)

            syncStatusMessage
        }
    }

    private var dailyCoachUsageSection: some View {
        Section("Daily Coach Usage") {
            Toggle("Use HealthKit in Daily Coach", isOn: $useHealthKitInDailyCoach)
                .disabled(!healthKitEnabled || isUnavailable)

            Text("The app reads objective recovery data to lightly assist Daily Coach readiness decisions.")
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

            Text("Watch companion coming soon. This release only adds connection groundwork and shared payload seams.")
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
            Toggle("Import HealthKit Workouts", isOn: $importHealthKitWorkouts)
                .disabled(!healthKitEnabled || isUnavailable)

            Toggle("Write App Workouts to HealthKit", isOn: $writeAppWorkoutsToHealthKit)
                .disabled(!healthKitEnabled || isUnavailable)

            Button("Import Workouts (Last 90 Days)") {
                Task {
                    let didSync = await viewModel.syncImportedWorkouts(context: modelContext)
                    if didSync {
                        healthKitLastSyncTimestamp = Date().timeIntervalSince1970
                    }
                }
            }
            .disabled(
                !healthKitEnabled ||
                isUnavailable ||
                viewModel.isLoading ||
                isImportingWorkouts ||
                !importHealthKitWorkouts
            )

            Text("Imported workouts are labeled as HealthKit imports so source attribution stays clear.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("Imported workouts include source and activity metadata; set-by-set strength detail is not fabricated during import.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("Workout writeback is limited to workout type, timing, duration, and optional active energy.")
                .font(.footnote)
                .foregroundStyle(.secondary)

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
            Text("Health data is optional and user-controlled.")
            Text("SuggestMeSome still works fully without HealthKit.")
            Text("You can change these permissions at any time in the Health app or in Settings > Privacy & Security > Health.")
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
            return "Health data is unavailable on this device."
        }
        if isDenied {
            return "HealthKit access is denied. Enable access in the Health app or iOS Privacy settings."
        }
        if isConnected {
            return "HealthKit permissions are active."
        }
        return "HealthKit is not connected yet."
    }

    private var connectButtonTitle: String {
        if isDenied { return "Request Access Again" }
        if isConnected { return "Review Permissions" }
        return "Connect HealthKit"
    }

    private var watchStatusTitle: String {
        switch viewModel.watchStatus.availability {
        case .unsupported:
            return "Unavailable"
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
        case .notPaired, .pairedNoCompanionApp:
            return .orange
        case .companionInstalled:
            return .green
        case .reachable:
            return .green
        }
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
