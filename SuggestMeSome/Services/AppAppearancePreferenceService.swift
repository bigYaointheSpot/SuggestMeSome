import SwiftUI

enum AppAppearancePreferenceService {
    static func preferredColorScheme(for storedValue: String) -> ColorScheme? {
        switch storedValue {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil
        }
    }
}
