//
//  ContentView.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/5/26.
//

import SwiftUI
import SwiftData

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
    @Environment(ActiveWorkoutSessionStore.self) private var activeWorkoutSessionStore
    @State private var selectedTab: Int = MainTab.dailyCoach.rawValue
    @State private var showingActiveWorkout = false
    @AppStorage("appColorScheme") private var appColorScheme: String = "system"

    private var preferredColorScheme: ColorScheme? {
        AppAppearancePreferenceService.preferredColorScheme(for: appColorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            if activeWorkoutSessionStore.hasActiveSession {
                ActiveWorkoutBanner {
                    showingActiveWorkout = true
                }
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
    }
}

// MARK: - Active Workout Banner

struct ActiveWorkoutBanner: View {
    @Environment(ActiveWorkoutSessionStore.self) private var activeWorkoutSessionStore

    let onResume: () -> Void

    var body: some View {
        if let session = activeWorkoutSessionStore.session {
            Button(action: onResume) {
                HStack(spacing: 10) {
                    Image(systemName: "timer")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Workout in Progress")
                            .font(.subheadline.weight(.semibold))
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text("\(formattedElapsed(for: session, at: context.date)) · \(exerciseCountLabel(session.exerciseEntries.count))")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    Spacer()
                    Text("Resume")
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .foregroundStyle(.white)
                .background(Color.indigo)
            }
            .buttonStyle(.plain)
        }
    }

    private func formattedElapsed(for session: ActiveWorkoutSession, at date: Date) -> String {
        let elapsedSeconds = session.elapsedSeconds(at: date)
        let h = elapsedSeconds / 3600
        let m = (elapsedSeconds % 3600) / 60
        let s = elapsedSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    private func exerciseCountLabel(_ count: Int) -> String {
        count == 1 ? "1 exercise" : "\(count) exercises"
    }
}

#Preview {
    ContentView()
}
