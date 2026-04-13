//
//  Feature11Prompt6DashboardRenameTests.swift
//  SuggestMeSomeTests
//
//  Feature 11 Prompt 6 — Dashboard rename and navigation clarity pass.
//
//  Covers:
//  - MainTab identity: labels, icons, and raw-value ordering
//  - Dashboard replaces Home in the primary tab surface
//  - Daily Coach stays the first (most-central) tab
//  - No stale tab-index drift (Training Programs is tag 3, not 2)
//

import Testing
@testable import SuggestMeSome

@Suite(.serialized)
struct Feature11Prompt6DashboardRenameTests {

    // MARK: - Tab labels

    @Test func dashboardTabLabelIsDashboardNotHome() {
        #expect(MainTab.dashboard.label == "Dashboard")
        #expect(MainTab.dashboard.label != "Home")
    }

    @Test func allMainTabLabelsMatchExpectedCopy() {
        #expect(MainTab.dailyCoach.label == "Daily Coach")
        #expect(MainTab.dashboard.label  == "Dashboard")
        #expect(MainTab.workouts.label   == "Workouts")
        #expect(MainTab.programs.label   == "Training Programs")
        #expect(MainTab.settings.label   == "Settings")
    }

    @Test func noMainTabUsesStaleHomeLabel() {
        for tab in MainTab.allCases {
            #expect(tab.label != "Home", "Tab \(tab) should not be labelled 'Home'")
        }
    }

    // MARK: - Tab icons

    @Test func dashboardUsesGridIconNotHouse() {
        #expect(MainTab.dashboard.systemImage == "square.grid.2x2.fill")
        #expect(MainTab.dashboard.systemImage != "house.fill")
    }

    @Test func dailyCoachKeepsBrainIcon() {
        #expect(MainTab.dailyCoach.systemImage == "brain.head.profile")
    }

    // MARK: - Tab ordering / indexes

    @Test func dailyCoachIsFirstTabForTodayPlanCentrality() {
        #expect(MainTab.dailyCoach.rawValue == 0)
    }

    @Test func dashboardIsSecondTab() {
        #expect(MainTab.dashboard.rawValue == 1)
    }

    @Test func programsTabIndexMatchesTrainingProgramsSlot() {
        // Guards against the previous bug where Dashboard's "Browse Programs"
        // button used a hard-coded `2`, which silently shifted to the Workouts
        // tab after Daily Coach was inserted as the new first tab.
        #expect(MainTab.programs.rawValue == 3)
        #expect(MainTab.workouts.rawValue == 2)
        #expect(MainTab.programs.rawValue != MainTab.workouts.rawValue)
    }

    @Test func allMainTabsHaveDistinctIndexesAndLabels() {
        let indexes = MainTab.allCases.map(\.rawValue)
        #expect(Set(indexes).count == MainTab.allCases.count)

        let labels = MainTab.allCases.map(\.label)
        #expect(Set(labels).count == MainTab.allCases.count)

        let icons = MainTab.allCases.map(\.systemImage)
        #expect(Set(icons).count == MainTab.allCases.count)
    }
}
