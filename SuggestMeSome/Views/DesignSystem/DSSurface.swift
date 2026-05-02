//
//  DSSurface.swift
//  SuggestMeSome
//
//  Typed background surfaces introduced in Feature 22 Prompt 2 so views
//  stop reading raw `Color(.systemGroupedBackground)` and friends inline.
//

import SwiftUI

enum DSSurface {
    /// Page background under tab content (the body of every tab view).
    static var primary: Color { Color(.systemGroupedBackground) }
    /// Standard card / list-row fill above `primary`.
    static var secondary: Color { Color(.secondarySystemBackground) }
    /// Elevated surface used for popovers, sheets, hero callouts.
    static var elevated: Color { Color(.tertiarySystemBackground) }
    /// Sunken inset used for input wells, code-style chips, etc.
    static var sunken: Color { Color(.quaternarySystemFill) }
}
