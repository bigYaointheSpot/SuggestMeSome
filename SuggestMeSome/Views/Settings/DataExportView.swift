//
//  DataExportView.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/5/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DataExportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AccountManager.self) private var accountManager
    @Environment(ComplianceStateStore.self) private var complianceStateStore

    @State private var backupViewModel = PortableBackupViewModel()
    @State private var summarySnapshot = DataExportSummarySnapshot.placeholder
    @State private var summaryRefreshTrigger = 0
    @State private var csvExportURL: URL?
    @State private var isGeneratingCSV = false
    @State private var csvStatusMessage: String?
    @State private var csvErrorMessage: String?

    private var backupFeedbackItems: [(String, Color)] {
        var items: [(String, Color)] = []
        if let message = backupViewModel.statusMessage {
            items.append((message, .secondary))
        }
        if let message = backupViewModel.errorMessage {
            items.append((message, .red))
        }
        if let message = csvStatusMessage {
            items.append((message, .secondary))
        }
        if let message = csvErrorMessage {
            items.append((message, .red))
        }
        return items
    }

    var body: some View {
        List {
            Section {
                LabeledContent(
                    "Exercise Library",
                    value: "\(summarySnapshot.muscleGroupCount) groups / \(summarySnapshot.exerciseCount) exercises"
                )
                LabeledContent(
                    "Workout History",
                    value: "\(summarySnapshot.workoutCount) workouts / \(summarySnapshot.personalRecordCount) PRs"
                )
                LabeledContent(
                    "Programs",
                    value: "\(summarySnapshot.trainingProgramCount) programs / \(summarySnapshot.programRunCount) runs"
                )
                LabeledContent(
                    "Coach & Adaptive",
                    value: "\(summarySnapshot.coachAndAdaptiveCount) records"
                )
                LabeledContent(
                    "Apple Health Cache",
                    value: "\(summarySnapshot.healthKitDailySummaryCount) days"
                )
                LabeledContent(
                    "Local Account State",
                    value: "\(accountManager.knownAccounts.count) accounts / \(accountManager.privacyRequests.count) requests"
                )
                LabeledContent(
                    "Compliance Onboarding",
                    value: complianceStateStore.hasCompletedRequiredOnboarding ? "Complete" : "Incomplete"
                )
            } header: {
                Text("Backup Summary")
            } footer: {
                Text("Portable backup includes local app records, settings, local account/privacy state, and cached Apple Health summaries stored inside SuggestMeSome.")
            }

            Section {
                Button {
                    csvStatusMessage = nil
                    csvErrorMessage = nil
                    backupViewModel.generateBackup(context: modelContext)
                } label: {
                    if backupViewModel.isGeneratingBackup {
                        HStack(spacing: 10) {
                            ProgressView().scaleEffect(0.85)
                            Text("Generating Backup…")
                                .foregroundStyle(.primary)
                        }
                    } else {
                        Label(
                            backupViewModel.backupExportURL == nil ? "Export Device Backup" : "Re-generate Device Backup",
                            systemImage: "externaldrive.badge.icloud"
                        )
                    }
                }
                .disabled(backupViewModel.isGeneratingBackup)

                if let url = backupViewModel.backupExportURL {
                    ShareLink(
                        item: url,
                        subject: Text("SuggestMeSome Device Backup"),
                        message: Text("Portable backup exported from SuggestMeSome.")
                    ) {
                        Label("Share Backup File", systemImage: "square.and.arrow.up")
                    }
                }

                Button {
                    csvStatusMessage = nil
                    csvErrorMessage = nil
                    backupViewModel.openImporter()
                } label: {
                    Label("Import Device Backup", systemImage: "square.and.arrow.down")
                }
                .disabled(backupViewModel.isRestoringBackup)
            } header: {
                Text("Device Backup")
            } footer: {
                Text("Portable backup is a single unencrypted JSON file for device-to-device migration. Import replaces all local data on this device. Apple Health data outside SuggestMeSome, active live workout state, purchase cache, and watch widget cache are not included.")
            }

            Section {
                LabeledContent("Workouts", value: "\(summarySnapshot.workoutCount)")
                LabeledContent("Exercise Entries", value: "\(summarySnapshot.exerciseEntryCount)")
                LabeledContent("Total Sets", value: "\(summarySnapshot.setCount)")

                Button {
                    generateCSV()
                } label: {
                    if isGeneratingCSV {
                        HStack(spacing: 10) {
                            ProgressView().scaleEffect(0.85)
                            Text("Generating CSV…")
                                .foregroundStyle(.primary)
                        }
                    } else {
                        Label(
                            csvExportURL == nil ? "Generate Workout CSV" : "Re-generate Workout CSV",
                            systemImage: "doc.text"
                        )
                    }
                }
                .disabled(isGeneratingCSV || summarySnapshot.workoutCount == 0)

                if let url = csvExportURL {
                    ShareLink(
                        item: url,
                        subject: Text("SuggestMeSome Workout Data"),
                        message: Text("Workout history exported from SuggestMeSome.")
                    ) {
                        Label("Share CSV File", systemImage: "square.and.arrow.up")
                    }
                }
            } header: {
                Text("Workout CSV Export")
            } footer: {
                if summarySnapshot.workoutCount == 0 {
                    Text("No workout data is available for CSV export yet.")
                } else {
                    Text("CSV remains a human-readable workout export. Use Device Backup when you want to move all local app data to another device.")
                }
            }

            if !backupFeedbackItems.isEmpty {
                Section {
                    ForEach(Array(backupFeedbackItems.enumerated()), id: \.offset) { _, item in
                        Text(item.0)
                            .foregroundStyle(item.1)
                    }
                } header: {
                    Text("Status")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Backup & Export")
        .navigationBarTitleDisplayMode(.large)
        .task(id: summaryRefreshTrigger) {
            refreshSummary()
        }
        .onChange(of: backupViewModel.statusMessage) { _, _ in
            requestSummaryRefresh()
        }
        .onChange(of: backupViewModel.errorMessage) { _, _ in
            requestSummaryRefresh()
        }
        .fileImporter(
            isPresented: $backupViewModel.isPresentingImporter,
            allowedContentTypes: [.suggestMeSomeBackup, .json]
        ) { result in
            backupViewModel.handleImportSelection(result)
        }
        .sheet(item: $backupViewModel.importPreview) { preview in
            BackupImportPreviewSheet(
                preview: preview,
                isRestoring: backupViewModel.isRestoringBackup,
                onConfirm: {
                    backupViewModel.restoreImport(
                        context: modelContext,
                        accountManager: accountManager,
                        complianceStateStore: complianceStateStore
                    )
                },
                onCancel: {
                    backupViewModel.dismissImportPreview()
                }
            )
        }
    }

    private func buildCSV(from exportData: WorkoutCSVExportData) -> String {
        var rows: [String] = ["Date,Duration,Exercise,Muscle Group,Set,Weight,Unit,Reps,PR"]
        for row in exportData.rows {
            rows.append(
                "\(row.dateString),\(row.duration),\(csvEscape(row.exerciseName)),\(csvEscape(row.muscleGroupName)),\(row.setNumber),\(row.weightValue),\(row.unitValue),\(row.repsValue),\(row.isPersonalRecord ? "true" : "false")"
            )
        }
        return rows.joined(separator: "\n")
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private func generateCSV() {
        isGeneratingCSV = true
        defer { isGeneratingCSV = false }

        let exportData = DataExportReadRepository.workoutCSVExportData(context: modelContext)
        let csv = buildCSV(from: exportData)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SuggestMeSome_Workouts.csv")

        do {
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)
            csvExportURL = fileURL
            csvErrorMessage = nil
            csvStatusMessage = "Workout CSV is ready to share."
        } catch {
            csvExportURL = nil
            csvStatusMessage = nil
            csvErrorMessage = "The workout CSV could not be written."
        }
    }

    private func refreshSummary() {
        summarySnapshot = DataExportReadRepository.summarySnapshot(context: modelContext)
    }

    private func requestSummaryRefresh() {
        summaryRefreshTrigger += 1
    }
}

private struct BackupImportPreviewSheet: View {
    let preview: PortableBackupImportPreview
    let isRestoring: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private static let previewDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private var manifest: PortableBackupManifest {
        preview.envelope.manifest
    }

    private var createdAtText: String {
        Self.previewDateFormatter.string(from: preview.envelope.generatedAt)
    }

    private var sourceVersionText: String {
        "\(preview.envelope.source.appVersion) (\(preview.envelope.source.buildNumber))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("File", value: preview.fileName)
                    LabeledContent("Created", value: createdAtText)
                    LabeledContent("App", value: preview.envelope.source.appName)
                    LabeledContent("Version", value: sourceVersionText)
                    LabeledContent("Backup Format", value: "v\(preview.envelope.backupVersion)")
                } header: {
                    Text("Backup")
                }

                Section {
                    LabeledContent(
                        "Exercise Library",
                        value: "\(manifest.muscleGroupCount) groups / \(manifest.exerciseLibraryCount) exercises"
                    )
                    LabeledContent(
                        "Workout History",
                        value: "\(manifest.workoutCount) workouts / \(manifest.workoutExerciseEntryCount) entries / \(manifest.workoutSetCount) sets"
                    )
                    LabeledContent(
                        "Programs",
                        value: "\(manifest.trainingProgramCount) programs / \(manifest.programRunCount) runs / \(manifest.programSessionExerciseCount) session rows"
                    )
                    LabeledContent(
                        "Daily Coach",
                        value: "\(manifest.dailyCoachCheckInCount) check-ins / \(manifest.dailyCoachWeeklyReviewCount) weekly reviews"
                    )
                    LabeledContent(
                        "Adaptive History",
                        value: "\(manifest.weeklyTrainingAnalysisCount) analyses / \(manifest.adaptationProposalCount) proposals / \(manifest.appliedProgramOverlayCount) overlays"
                    )
                    LabeledContent(
                        "Apple Health Cache",
                        value: "\(manifest.healthKitDailySummaryCount) days"
                    )
                    LabeledContent(
                        "Total SwiftData Records",
                        value: "\(manifest.totalSwiftDataRecordCount)"
                    )
                } header: {
                    Text("Contents")
                }

                Section {
                    LabeledContent("Accounts", value: "\(manifest.knownAccountCount)")
                    LabeledContent("Privacy Requests", value: "\(manifest.privacyRequestCount)")
                    LabeledContent("Health Consents", value: "\(manifest.consumerHealthConsentCount)")
                } header: {
                    Text("Local State")
                }

                Section {
                    Text("Import replaces all local SuggestMeSome data on this device with the contents of this backup.")
                    Text("The backup file is unencrypted JSON. Keep it in a secure location while sharing or storing it.")
                    Text("Apple Health data outside SuggestMeSome is not transferred. Only the Health summaries already cached inside the app are restored.")
                } header: {
                    Text("Before You Import")
                }

                Section {
                    Button(role: .destructive) {
                        onConfirm()
                    } label: {
                        if isRestoring {
                            HStack(spacing: 10) {
                                ProgressView().scaleEffect(0.85)
                                Text("Restoring Backup…")
                                    .foregroundStyle(.primary)
                            }
                        } else {
                            Label("Replace Local Data", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(isRestoring)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Import Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .disabled(isRestoring)
                }
            }
        }
    }
}
