//
//  HealthDataSettingsView.swift
//  SuggestMeSome
//
//  Feature 8 — User-facing Health Data settings and authorization controls.
//

import SwiftUI
import HealthKit
import Combine

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

    private let authorizationService = HealthKitAuthorizationService()

    func refreshStatus(hasRequestedAuthorization: Bool) async {
        isLoading = true
        snapshot = await authorizationService.refreshAuthorizationStatus(
            hasRequestedAuthorization: hasRequestedAuthorization
        )
        isLoading = false
    }

    func requestAuthorization(hasRequestedAuthorization: Bool) async {
        isLoading = true
        snapshot = await authorizationService.requestAuthorization(
            hasRequestedAuthorization: hasRequestedAuthorization
        )
        isLoading = false
    }
}

struct HealthDataSettingsView: View {
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

    var body: some View {
        List {
            connectionStatusSection
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

    private var workoutSyncSection: some View {
        Section("Workout Sync") {
            Toggle("Import HealthKit Workouts", isOn: $importHealthKitWorkouts)
                .disabled(!healthKitEnabled || isUnavailable)

            Toggle("Write App Workouts to HealthKit", isOn: $writeAppWorkoutsToHealthKit)
                .disabled(!healthKitEnabled || isUnavailable)

            Text("Imported workouts are labeled as HealthKit imports so source attribution stays clear.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("Workout import/export sync is not active yet in this version.")
                .font(.footnote)
                .foregroundStyle(.secondary)
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
}
