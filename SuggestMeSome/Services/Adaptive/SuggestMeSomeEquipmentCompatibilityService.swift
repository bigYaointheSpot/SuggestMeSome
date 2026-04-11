import Foundation

/// Scaffold service for future equipment-compatibility filtering.
/// Current behavior intentionally preserves all exercises to avoid UX changes.
struct SuggestMeSomeEquipmentCompatibilityService {
    func filterExercises(
        _ exercises: [Exercise],
        equipmentProfile: SuggestMeSomeEquipmentProfile?
    ) -> [Exercise] {
        _ = equipmentProfile
        return exercises
    }
}
