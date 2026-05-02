//
//  SuggestMeSomeApp.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/5/26.
//

import SwiftUI
import SwiftData

@main
struct SuggestMeSomeApp: App {
    @UIApplicationDelegateAdaptor(CollaborationPushAppDelegate.self) private var pushAppDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var activeWorkoutSessionStore = ActiveWorkoutSessionStore()
    @State private var purchaseManager = PurchaseManager.shared
    @State private var complianceStateStore = ComplianceStateStore.shared
    @State private var accountManager = AccountManager.shared
    @State private var cloudSyncManager = CloudSyncManager.shared
    @State private var collaborationCoordinator = CollaborationCoordinator.shared
    @State private var pushNotificationManager = PushNotificationManager.shared
    @State private var appRouteCoordinator = AppRouteCoordinator.shared
    @State private var hasPerformedStartupMaintenance = false

    private static let sharedSchema = Schema([
            MuscleGroup.self,
            Exercise.self,
            Workout.self,
            ExerciseEntry.self,
            SetEntry.self,
            PersonalRecord.self,
            TrainingProgram.self,
            ProgramWeekTemplate.self,
            ProgramSessionTemplate.self,
            ProgramSessionExercise.self,
            ProgramRun.self,
            ExercisePerformanceOutcome.self,
            WeeklyTrainingAnalysis.self,
            WeeklyVolumeMetric.self,
            LiftPerformanceTrend.self,
            LiftTrendSnapshot.self,
            AdaptationProposal.self,
            AppliedProgramOverlay.self,
            AppliedOverlayAdjustment.self,
            AdaptationEventHistory.self,
            // Feature 7 — Daily Coach
            DailyCoachCheckIn.self,
            DailyCoachWeeklyReview.self,
            // Feature 8 — HealthKit foundation
            HealthKitDailySummary.self,
            // Feature 19 — Collaboration, insight, and sharing caches
            CoachRelationship.self,
            CoachInvite.self,
            ProgramAssignment.self,
            CoachNote.self,
            NotificationPreference.self,
            DevicePushRegistration.self,
            InsightSnapshot.self,
            WeeklyDigest.self,
            SavedProgramBlueprint.self,
            ProgramShareGrant.self,
            ProgressShareCard.self,
        ])

    var sharedModelContainer: ModelContainer = {
        let persistentConfiguration = ModelConfiguration(
            schema: sharedSchema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(for: sharedSchema, configurations: [persistentConfiguration])
        } catch {
            // Recovery path for incompatible/corrupted stores after schema updates.
            deleteSwiftDataStoreFiles()
            do {
                return try ModelContainer(for: sharedSchema, configurations: [persistentConfiguration])
            } catch {
                // Last-resort fallback to keep the app launchable instead of crashing.
                let inMemoryConfiguration = ModelConfiguration(
                    schema: sharedSchema,
                    isStoredInMemoryOnly: true
                )
                do {
                    return try ModelContainer(for: sharedSchema, configurations: [inMemoryConfiguration])
                } catch {
                    fatalError("Could not create ModelContainer: \(error)")
                }
            }
        }
    }()

    private static func deleteSwiftDataStoreFiles() {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        guard let contents = try? fileManager.contentsOfDirectory(
            at: appSupportURL,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        let sqliteExtensions: Set<String> = ["sqlite", "sqlite-wal", "sqlite-shm"]
        for url in contents where sqliteExtensions.contains(url.pathExtension) {
            try? fileManager.removeItem(at: url)
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if complianceStateStore.hasCompletedRequiredOnboarding {
                    ContentView()
                } else {
                    ComplianceOnboardingFlow()
                }
            }
                .environment(activeWorkoutSessionStore)
                .environment(purchaseManager)
                .environment(complianceStateStore)
                .environment(accountManager)
                .environment(cloudSyncManager)
                .environment(collaborationCoordinator)
                .environment(pushNotificationManager)
                .environment(appRouteCoordinator)
                .environment(\.uiRefreshV2, FeatureFlag.uiRefreshV2.isEnabled)
                .onAppear {
                    guard !hasPerformedStartupMaintenance else { return }
                    hasPerformedStartupMaintenance = true

                    let maintenanceReport = PersistenceMaintenanceCoordinator.runBlockingStartupMaintenance(
                        context: sharedModelContainer.mainContext
                    )
                    _ = CollaborationCacheMigrator.dedupIfNeeded(
                        context: sharedModelContainer.mainContext
                    )
                    HealthKitSettingsStorage.migrateLegacyRecoverySyncTimestampIfNeeded(
                        context: sharedModelContainer.mainContext
                    )
                    cloudSyncManager.configure(
                        modelContext: sharedModelContainer.mainContext
                    )
                    collaborationCoordinator.configure(
                        modelContext: sharedModelContainer.mainContext
                    )
                    accountManager.configureCloudSyncManager(cloudSyncManager)
                    accountManager.configureCollaborationCoordinator(collaborationCoordinator)
                    collaborationCoordinator.configure(cloudSyncManager: cloudSyncManager)
                    pushNotificationManager.configure(
                        collaborationCoordinator: collaborationCoordinator,
                        routeCoordinator: appRouteCoordinator
                    )
                    WatchSessionCoordinator.shared.installCompanionHandlers(
                        activeWorkoutSessionStore: activeWorkoutSessionStore,
                        modelContext: sharedModelContainer.mainContext
                    )
                    Task { @MainActor in
                        await accountManager.restoreSessionIfNeeded()
                        await purchaseManager.bootstrap()
                        await cloudSyncManager.syncOnAppDidBecomeActive()
                    }
                    if maintenanceReport.shouldRunDeferredSyncMetadataAudit {
                        let modelContainer = sharedModelContainer
                        Task.detached(priority: .utility) {
                            _ = PersistenceMaintenanceCoordinator.runDeferredStartupSyncAuditIfNeeded(
                                container: modelContainer,
                                shouldRunSyncAudit: true
                            )
                        }
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    Task { @MainActor in
                        await accountManager.restoreSessionIfNeeded()
                        await cloudSyncManager.syncOnAppDidBecomeActive()
                        await collaborationCoordinator.refreshOnAppDidBecomeActive()
                        await purchaseManager.refreshEntitlements()
                        guard purchaseManager.isPremiumUnlocked else { return }
                        _ = await HealthKitRecoveryAutoRefreshCoordinator.shared.refreshIfNeeded(
                            trigger: .appDidBecomeActive,
                            context: sharedModelContainer.mainContext
                        )
                    }
                }
                .onOpenURL { url in
                    guard let route = AppDeepLinkRoute(url: url) else { return }
                    appRouteCoordinator.present(route)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
