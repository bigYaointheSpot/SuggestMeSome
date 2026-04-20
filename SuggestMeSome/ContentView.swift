//
//  ContentView.swift
//  SuggestMeSome
//
//  Root tab shell with an isolated active-workout banner host.
//

import SwiftUI

// MARK: - Main Tab Identity

/// Single source of truth for the root tab bar. Keeping identity, labels, and
/// icons here lets tests validate tab copy without instantiating SwiftUI views
/// and keeps `ContentView` free of magic numbers.
enum MainTab: Int, CaseIterable {
    case dailyCoach = 0
    case dashboard  = 1
    case workouts   = 2
    case programs   = 3
    case settings   = 4

    var label: String {
        switch self {
        case .dailyCoach: return "Daily Coach"
        case .dashboard:  return "Dashboard"
        case .workouts:   return "Workouts"
        case .programs:   return "Training Programs"
        case .settings:   return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dailyCoach: return "brain.head.profile"
        case .dashboard:  return "square.grid.2x2.fill"
        case .workouts:   return "dumbbell"
        case .programs:   return "list.clipboard"
        case .settings:   return "gear"
        }
    }
}

// MARK: - ContentView

struct ContentView: View {
    @Environment(AppRouteCoordinator.self) private var appRouteCoordinator
    @State private var selectedTab: Int = MainTab.dailyCoach.rawValue
    @State private var showingActiveWorkout = false
    @AppStorage("appColorScheme") private var appColorScheme: String = "system"

    private var preferredColorScheme: ColorScheme? {
        AppAppearancePreferenceService.preferredColorScheme(for: appColorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            ActiveWorkoutBannerHost {
                showingActiveWorkout = true
            }

            TabView(selection: $selectedTab) {
                PremiumFeatureGate(feature: .dailyCoach) {
                    DailyCoachView()
                }
                    .tabItem {
                        Label(MainTab.dailyCoach.label, systemImage: MainTab.dailyCoach.systemImage)
                    }
                    .tag(MainTab.dailyCoach.rawValue)
                PremiumFeatureGate(feature: .dashboardAnalytics) {
                    DashboardView(selectedTab: $selectedTab)
                }
                    .tabItem {
                        Label(MainTab.dashboard.label, systemImage: MainTab.dashboard.systemImage)
                    }
                    .tag(MainTab.dashboard.rawValue)
                WorkoutsTab()
                    .tabItem {
                        Label(MainTab.workouts.label, systemImage: MainTab.workouts.systemImage)
                    }
                    .tag(MainTab.workouts.rawValue)
                PremiumFeatureGate(feature: .trainingPrograms) {
                    TrainingProgramsTab()
                }
                    .tabItem {
                        Label(MainTab.programs.label, systemImage: MainTab.programs.systemImage)
                    }
                    .tag(MainTab.programs.rawValue)
                SettingsTab()
                    .tabItem {
                        Label(MainTab.settings.label, systemImage: MainTab.settings.systemImage)
                    }
                    .tag(MainTab.settings.rawValue)
            }
        }
        .tint(.indigo)
        .preferredColorScheme(preferredColorScheme)
        .sheet(isPresented: $showingActiveWorkout) {
            NavigationStack {
                WorkoutView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                showingActiveWorkout = false
                            }
                        }
                    }
            }
        }
        .onChange(of: appRouteCoordinator.activeRoute) { _, route in
            guard let route else { return }
            selectedTab = route.targetTab.rawValue
        }
    }
}

// MARK: - Active Workout Banner

private struct ActiveWorkoutBannerHost: View {
    @Environment(ActiveWorkoutSessionStore.self) private var activeWorkoutSessionStore

    let onResume: () -> Void

    var body: some View {
        if let session = activeWorkoutSessionStore.session {
            ActiveWorkoutBanner(
                presentation: ActiveWorkoutBannerPresentation(
                    elapsedTimer: WorkoutElapsedTimerPresentation(
                        isActive: true,
                        startTime: session.startTime,
                        session: session
                    ),
                    exerciseCount: session.exerciseEntries.count
                ),
                onResume: onResume
            )
        }
    }
}

struct ActiveWorkoutBanner: View {
    let presentation: ActiveWorkoutBannerPresentation
    let onResume: () -> Void

    var body: some View {
        Button(action: onResume) {
            HStack(spacing: 10) {
                Image(systemName: "timer")
                    .font(.headline)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Workout in Progress")
                        .font(.subheadline.weight(.semibold))
                    ActiveWorkoutBannerTimerLine(presentation: presentation)
                }
                Spacer()
                Text("Resume")
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .foregroundStyle(.white)
            .background(Color.indigo)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Double tap to resume your active workout.")
    }
}

private struct ActiveWorkoutBannerTimerLine: View {
    let presentation: ActiveWorkoutBannerPresentation

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text("\(presentation.elapsedTimer.formattedElapsed(at: context.date)) · \(presentation.exerciseCountText)")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

#Preview {
    ContentView()
}
