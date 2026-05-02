//
//  DashboardTimeWindow.swift
//  SuggestMeSome
//
//  Time-window picker enum extracted from DashboardView in Feature 22 Prompt 1.
//

import Foundation

enum DashboardTimeWindow: String, CaseIterable {
    case fourWeeks  = "4W"
    case threeMonths = "3M"
    case oneYear    = "1Y"
    case all        = "All"

    var startDate: Date? {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .fourWeeks:   return cal.date(byAdding: .weekOfYear, value: -4, to: now)
        case .threeMonths: return cal.date(byAdding: .month, value: -3, to: now)
        case .oneYear:     return cal.date(byAdding: .year, value: -1, to: now)
        case .all:         return nil
        }
    }

    var icon: String {
        switch self {
        case .fourWeeks:   return "calendar"
        case .threeMonths: return "calendar.badge.clock"
        case .oneYear:     return "calendar.circle"
        case .all:         return "infinity"
        }
    }
}
