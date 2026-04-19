//
//  SettingsTab.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/11/26.
//

import SwiftUI
import SwiftData

// MARK: - SettingsTab

struct SettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PurchaseManager.self) private var purchaseManager
    @Environment(AccountManager.self) private var accountManager
    @Environment(CloudSyncManager.self) private var cloudSyncManager
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator
    @Environment(AppRouteCoordinator.self) private var appRouteCoordinator

    // MARK: Preferences
    @AppStorage("globalWeightUnit") private var globalWeightUnit: String = WeightUnit.lbs.rawValue
    @AppStorage("appColorScheme") private var appColorScheme: String = "system"
    @AppStorage("defaultRestTimerSeconds") private var defaultRestTimerSeconds: Int = 90
    @AppStorage("coachPreferredDays") private var coachPreferredDays: Int = 42 // Mon + Wed + Fri

    private var weightUnitBinding: Binding<WeightUnit> {
        Binding(
            get: { WeightUnit(rawValue: globalWeightUnit) ?? .lbs },
            set: { globalWeightUnit = $0.rawValue }
        )
    }

    // MARK: Data management state
    @State private var showingDeleteAllConfirm = false
    @State private var showingDeleteRangeSheet = false
    @State private var workoutCount = 0
    @State private var showingCollaborationInfo = false

    // MARK: - Helpers

    private func deleteAllTitle() -> String {
        let n = workoutCount
        return "Delete \(n) Workout\(n == 1 ? "" : "s") and All PRs"
    }

    private func deleteAllMessage() -> String {
        let n = workoutCount
        return "All \(n) workout\(n == 1 ? "" : "s") and every personal record will be permanently deleted. Your exercise library is kept."
    }

    private var preferredDaysSummary: String {
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let selected = (0..<7).filter { coachPreferredDays & (1 << $0) != 0 }.map { names[$0] }
        if selected.isEmpty { return "None" }
        if selected.count == 7 { return "Every day" }
        return selected.joined(separator: ", ")
    }

    private var restTimerLabel: String {
        switch defaultRestTimerSeconds {
        case 0:   return "Off"
        case 30:  return "30 sec"
        case 60:  return "1 min"
        case 90:  return "90 sec"
        case 120: return "2 min"
        case 180: return "3 min"
        case 300: return "5 min"
        default:  return "\(defaultRestTimerSeconds)s"
        }
    }

    private var appVersionLabel: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let shortVersion = (info["CFBundleShortVersionString"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let buildNumber = (info["CFBundleVersion"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch (shortVersion, buildNumber) {
        case let (short?, build?) where !short.isEmpty && !build.isEmpty:
            return "Version \(short) (\(build))"
        case let (short?, _) where !short.isEmpty:
            return "Version \(short)"
        case let (_, build?) where !build.isEmpty:
            return "Build \(build)"
        default:
            return "Version unavailable"
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                preferencesSection
                workoutSection
                cloudSyncSection
                collaborationSection
                quickLinksSection
                accountSection
                premiumSection
                legalPrivacySection
                dataManagementSection
                footerSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingDeleteRangeSheet, onDismiss: refreshWorkoutCount) {
                DeleteByRangeSheet { start, end in
                    deleteWorkoutsInRange(from: start, to: end)
                }
            }
            .task {
                refreshWorkoutCount()
            }
            .onChange(of: globalWeightUnit) { _, _ in
                markTrainingPreferencesUpdated(reason: "Updated default weight unit")
            }
            .onChange(of: defaultRestTimerSeconds) { _, _ in
                markTrainingPreferencesUpdated(reason: "Updated rest timer preference")
            }
            .onChange(of: coachPreferredDays) { _, _ in
                markTrainingPreferencesUpdated(reason: "Updated preferred training days")
            }
            .onChange(of: showingDeleteAllConfirm) { _, isPresented in
                guard isPresented else { return }
                refreshWorkoutCount()
            }
            .confirmationDialog(
                "Delete All Workout Data?",
                isPresented: $showingDeleteAllConfirm,
                titleVisibility: .visible
            ) {
                Button(deleteAllTitle(), role: .destructive) {
                    deleteAllData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(deleteAllMessage())
            }
            .sheet(
                item: Binding(
                    get: {
                        guard let route = appRouteCoordinator.activeRoute,
                              route.targetTab == .settings else {
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
            .sheet(isPresented: $showingCollaborationInfo) {
                collaborationInfoSheet
            }
        }
    }

    // MARK: - Sections

    private var preferencesSection: some View {
        Section("Preferences") {
            Picker("Default Weight Unit", selection: weightUnitBinding) {
                ForEach(WeightUnit.allCases, id: \.self) {
                    Text($0.rawValue).tag($0)
                }
            }
            .pickerStyle(.segmented)

            Picker("Appearance", selection: $appColorScheme) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .pickerStyle(.segmented)
        }
    }

    private var workoutSection: some View {
        Section("Workout") {
            NavigationLink {
                restTimerPickerView
            } label: {
                HStack {
                    Label("Rest Timer Default", systemImage: "timer")
                    Spacer()
                    Text(restTimerLabel)
                        .foregroundStyle(.secondary)
                }
            }

            NavigationLink {
                CoachScheduleView(coachPreferredDays: $coachPreferredDays)
            } label: {
                HStack {
                    Label("Preferred Training Days", systemImage: "calendar")
                    Spacer()
                    Text(preferredDaysSummary)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var quickLinksSection: some View {
        Section {
            NavigationLink {
                PersonalRecordsView()
            } label: {
                Label("Personal Records", systemImage: "trophy.fill")
                    .foregroundStyle(.yellow)
            }

            NavigationLink {
                HealthDataSettingsView()
            } label: {
                Label("Apple Health", systemImage: "heart.text.square.fill")
                    .foregroundStyle(.red)
            }

            NavigationLink {
                ManageExercisesView()
            } label: {
                Label("Manage Exercises", systemImage: "list.bullet.clipboard.fill")
                    .foregroundStyle(.blue)
            }
        }
    }

    private var cloudSyncSection: some View {
        Section {
            NavigationLink {
                CloudSyncSettingsView()
            } label: {
                HStack {
                    Label("Cloud Sync", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(cloudSyncManager.phase.title)
                            .foregroundStyle(.secondary)
                        if let email = cloudSyncManager.currentAccountEmail {
                            Text(email)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        } header: {
            Text("Cloud Sync")
        } footer: {
            Text("Cloud sync keeps workouts, programs, daily coaching, adaptive history, and key training preferences aligned across signed-in devices. Apple Health-derived recovery data stays on this device in Feature 18.")
        }
    }

    private var collaborationSection: some View {
        Section {
            NavigationLink {
                CollaborationHubView()
            } label: {
                HStack {
                    Label("Coach Collaboration", systemImage: "person.2.wave.2.fill")
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(collaborationCoordinator.phase.title)
                            .foregroundStyle(.secondary)
                        Text("\(collaborationCoordinator.relationships.count) relationship(s)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            NavigationLink {
                NotificationPreferencesView()
            } label: {
                HStack {
                    Label("Notifications", systemImage: "bell.badge.fill")
                    Spacer()
                    Text(PushNotificationManager.shared.authorizationState.title)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            HStack {
                Text("Coach Collaboration")
                Spacer()
                Button {
                    showingCollaborationInfo = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("About Coach Collaboration")
            }
        } footer: {
            Text("Invite-only sharing with coaches. Tap the ? above to learn more.")
        }
    }

    private var collaborationInfoSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label("What's included", systemImage: "sparkles")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 10) {
                        infoBullet("Invite coaches by email — no accounts needed on their side until they accept.")
                        infoBullet("Share programs or progress read-only, and pull it back whenever you want.")
                        infoBullet("Get weekly summaries and smart nudges based on what you actually trained.")
                        infoBullet("We only use push notifications — no email or SMS.")
                    }

                    Label("Your privacy", systemImage: "lock.shield")
                        .font(.headline)
                        .padding(.top, 8)
                    VStack(alignment: .leading, spacing: 10) {
                        infoBullet("Every share is explicit — we don't broadcast anything without your tap.")
                        infoBullet("Coaches see only what you choose: programs, runs, notes, or summaries.")
                        infoBullet("Apple Health recovery data stays on your device and is never shared.")
                    }
                }
                .padding()
            }
            .navigationTitle("Coach Collaboration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingCollaborationInfo = false }
                }
            }
        }
    }

    private func infoBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundStyle(.indigo)
                .padding(.top, 7)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var premiumSection: some View {
        Section {
            NavigationLink {
                PaywallView()
            } label: {
                Label(
                    purchaseManager.isPremiumUnlocked ? "Manage Premium" : "Unlock Premium",
                    systemImage: purchaseManager.isPremiumUnlocked ? "checkmark.seal.fill" : "star.circle.fill"
                )
                .foregroundStyle(purchaseManager.isPremiumUnlocked ? .green : .indigo)
            }

            Button {
                Task {
                    _ = await purchaseManager.restorePurchases()
                }
            } label: {
                Label("Restore Purchases", systemImage: "arrow.clockwise.circle")
            }

#if canImport(StoreKit)
            OfferCodeRedemptionButton(
                title: "Redeem Offer Code",
                systemImage: "ticket"
            )
#endif

#if DEBUG
            Toggle(
                isOn: Binding(
                    get: { purchaseManager.debugPremiumOverrideEnabled },
                    set: { purchaseManager.setDebugPremiumOverride($0) }
                )
            ) {
                Label("Developer Premium Override", systemImage: "hammer.circle")
            }

            Text("Debug builds only. Toggle between free and premium on your own Xcode-installed app without affecting release behavior or real App Store purchases.")
                .font(.footnote)
                .foregroundStyle(.secondary)
#endif

            if let statusMessage = purchaseManager.statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = purchaseManager.lastErrorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Premium")
        } footer: {
            Text(ComplianceConfiguration.premiumUnlockDisclosure)
        }
    }

    private var accountSection: some View {
        Section {
            NavigationLink {
                AccountSettingsView()
            } label: {
                HStack {
                    Label("Account & Cloud", systemImage: "person.crop.circle.badge.checkmark")
                    Spacer()
                    Text(accountSummaryText)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Account")
        } footer: {
            Text(ComplianceConfiguration.accountLaunchModeDisclosure)
        }
    }

    private var legalPrivacySection: some View {
        Section {
            NavigationLink {
                LegalPrivacyCenterView()
            } label: {
                Label("Open Legal & Privacy Center", systemImage: "shield.lefthalf.filled")
            }

            NavigationLink {
                LegalDocumentView(kind: .privacyPolicy)
            } label: {
                Label("Privacy Policy", systemImage: "lock.doc")
            }

            NavigationLink {
                LegalDocumentView(kind: .termsOfUse)
            } label: {
                Label("Terms of Use", systemImage: "doc.text")
            }

            NavigationLink {
                LegalDocumentView(kind: .consumerHealthNotice)
            } label: {
                Label("Consumer Health Data Notice", systemImage: "heart.text.square.fill")
            }

            NavigationLink {
                LegalDocumentView(kind: .automationDisclosure)
            } label: {
                Label("Smart Guidance Disclosure", systemImage: "wand.and.stars")
            }

            NavigationLink {
                LegalDocumentView(kind: .wellnessDisclaimer)
            } label: {
                Label("Wellness Disclaimer", systemImage: "cross.case")
            }

            NavigationLink {
                SupportInfoView()
            } label: {
                Label("Support", systemImage: "questionmark.circle")
            }

            NavigationLink {
                DataExportView()
            } label: {
                Label("Backup & Export Data", systemImage: "externaldrive.badge.icloud")
                    .foregroundStyle(.green)
            }

            NavigationLink {
                LocalDataInfoView()
            } label: {
                Label("Delete Local Data", systemImage: "trash")
            }
        } header: {
            Text("Legal & Privacy")
        }
    }

    private var accountSummaryText: String {
        if let currentUser = accountManager.currentUser {
            return currentUser.email
        }
        return accountManager.launchMode.title
    }

    private var dataManagementSection: some View {
        Section {
            Button(role: .destructive) {
                showingDeleteRangeSheet = true
            } label: {
                Label("Delete Workouts by Date Range…", systemImage: "calendar.badge.minus")
            }
            Button(role: .destructive) {
                showingDeleteAllConfirm = true
            } label: {
                Label("Delete All Workout Data", systemImage: "trash.fill")
            }
        } header: {
            Text("Data Management")
        } footer: {
            Text("Deleting workouts permanently removes all associated exercises and sets. Personal records are recalculated automatically. Your exercise library is not affected.")
        }
    }

    private var footerSection: some View {
        Section {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.blue)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("SuggestMeSome")
                        .font(.subheadline.weight(.semibold))
                    Text(appVersionLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Built by Alex Yao assisted by Codex and Claude")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Rest timer inline picker view

    private var restTimerPickerView: some View {
        List {
            Section {
                ForEach([0, 30, 60, 90, 120, 180, 300], id: \.self) { seconds in
                    Button {
                        defaultRestTimerSeconds = seconds
                    } label: {
                        HStack {
                            Text(labelFor(seconds: seconds))
                                .foregroundStyle(.primary)
                            Spacer()
                            if defaultRestTimerSeconds == seconds {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            } footer: {
                Text("A rest timer will appear automatically after each logged set when a default is set.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Rest Timer Default")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func labelFor(seconds: Int) -> String {
        switch seconds {
        case 0:   return "Off"
        case 30:  return "30 seconds"
        case 60:  return "1 minute"
        case 90:  return "90 seconds"
        case 120: return "2 minutes"
        case 180: return "3 minutes"
        case 300: return "5 minutes"
        default:  return "\(seconds)s"
        }
    }

    // MARK: - Data deletion

    private func deleteAllData() {
        let workouts = TrainingReadRepository.fetchWorkouts(context: modelContext)
        workoutCount = workouts.count
        try? PersonalRecordMaintenanceService.deleteWorkouts(workouts, context: modelContext)
        try? PersonalRecordMaintenanceService.clearAllPRData(context: modelContext)
        refreshWorkoutCount()
    }

    private func deleteWorkoutsInRange(from start: Date, to end: Date) {
        let dayStart = Calendar.current.startOfDay(for: start)
        let dayEnd   = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: end)!
        let workouts = TrainingReadRepository.fetchWorkouts(
            from: dayStart,
            to: dayEnd,
            context: modelContext
        )
        try? PersonalRecordMaintenanceService.deleteWorkouts(workouts, context: modelContext)
        refreshWorkoutCount()
    }

    private func refreshWorkoutCount() {
        workoutCount = TrainingReadRepository.workoutCount(context: modelContext)
    }

    private func markTrainingPreferencesUpdated(reason: String) {
        TrainingPreferencesStore.markUpdated()
        cloudSyncManager.notifyLocalMutation(reason)
    }
}

// MARK: - CoachScheduleView

private struct CoachScheduleView: View {
    @Binding var coachPreferredDays: Int

    private let days: [(name: String, full: String)] = [
        ("Sun", "Sunday"),
        ("Mon", "Monday"),
        ("Tue", "Tuesday"),
        ("Wed", "Wednesday"),
        ("Thu", "Thursday"),
        ("Fri", "Friday"),
        ("Sat", "Saturday")
    ]

    var body: some View {
        List {
            Section {
                ForEach(days.indices, id: \.self) { index in
                    let isOn = coachPreferredDays & (1 << index) != 0
                    Button {
                        if isOn {
                            coachPreferredDays &= ~(1 << index)
                        } else {
                            coachPreferredDays |= (1 << index)
                        }
                    } label: {
                        HStack {
                            Text(days[index].full)
                                .foregroundStyle(.primary)
                            Spacer()
                            if isOn {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                }
            } footer: {
                Text("The Daily Coach uses your preferred training days to prioritise workout suggestions and avoid recommending rest-day sessions.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Training Days")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - DeleteByRangeSheet

struct DeleteByRangeSheet: View {
    let onDelete: (Date, Date) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var showingConfirm = false
    @State private var summary = WorkoutDeleteRangeSummary.empty

    private var previewToken: Int {
        let dayStart = Calendar.current.startOfDay(for: startDate)
        let dayEnd   = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: endDate) ?? endDate
        var hasher = Hasher()
        hasher.combine(dayStart)
        hasher.combine(dayEnd)
        return hasher.finalize()
    }

    private var rangeCount: Int { summary.count }
    private var earliestInRange: Date? { summary.earliestDate }
    private var latestInRange: Date? { summary.latestDate }

    private var deleteButtonLabel: String {
        rangeCount == 0 ? "No Workouts in Range" : "Delete \(rangeCount) Workout\(rangeCount == 1 ? "" : "s")"
    }

    private var confirmDialogTitle: String {
        "Delete \(rangeCount) Workout\(rangeCount == 1 ? "" : "s")?"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Date Range") {
                    DatePicker("From", selection: $startDate,
                               in: ...endDate,
                               displayedComponents: .date)
                    DatePicker("To", selection: $endDate,
                               in: startDate...,
                               displayedComponents: .date)
                }

                Section {
                    previewCountRow
                    previewDatesRow
                } header: {
                    Text("Preview")
                }

                Section {
                    Button(role: .destructive) {
                        showingConfirm = true
                    } label: {
                        Text(deleteButtonLabel)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .disabled(rangeCount == 0)
                }
            }
            .navigationTitle("Delete by Date Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task(id: previewToken) {
                refreshPreview()
            }
            .confirmationDialog(confirmDialogTitle,
                                isPresented: $showingConfirm,
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    onDelete(startDate, endDate)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("These workouts will be permanently deleted and personal records will be recalculated.")
            }
        }
    }

    private func refreshPreview() {
        let dayStart = Calendar.current.startOfDay(for: startDate)
        let dayEnd = Calendar.current.date(
            bySettingHour: 23,
            minute: 59,
            second: 59,
            of: endDate
        ) ?? endDate
        summary = TrainingReadRepository.workoutDeleteRangeSummary(
            from: dayStart,
            to: dayEnd,
            context: modelContext
        )
    }

    private var previewCountRow: some View {
        HStack {
            Text("Workouts in range")
            Spacer()
            Text("\(rangeCount)")
                .fontWeight(rangeCount > 0 ? .semibold : .regular)
                .foregroundStyle(rangeCount > 0 ? .red : .secondary)
        }
    }

    @ViewBuilder
    private var previewDatesRow: some View {
        if let first = earliestInRange {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.left").foregroundStyle(.secondary)
                Text(first, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if let last = latestInRange, last != earliestInRange {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.right").foregroundStyle(.secondary)
                Text(last, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
