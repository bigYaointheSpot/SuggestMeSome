import Foundation
import SwiftData

struct SuggestMeSomePersonalRecordLookupService {
    let context: ModelContext

    func personalRecord(for exercise: Exercise, repCount: Int) -> PersonalRecord? {
        let name = exercise.name
        let descriptor = FetchDescriptor<PersonalRecord>(
            predicate: #Predicate { $0.exerciseName == name && $0.repCount == repCount }
        )
        return try? context.fetch(descriptor).first
    }
}
