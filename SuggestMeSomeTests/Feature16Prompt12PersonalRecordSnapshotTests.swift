import Foundation
import Testing
@testable import SuggestMeSome

struct Feature16Prompt12PersonalRecordSnapshotTests {

    @Test func personalRecordSnapshotBuildsExerciseGroupsAndRepSortedRows() {
        let records = [
            makeRecord(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                exerciseName: "Bench Press",
                repCount: 5,
                weight: 225,
                dateAchieved: day(-2)
            ),
            makeRecord(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                exerciseName: "Back Squat",
                repCount: 3,
                weight: 315,
                dateAchieved: day(-1)
            ),
            makeRecord(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                exerciseName: "Bench Press",
                repCount: 1,
                weight: 255,
                dateAchieved: day(-3)
            ),
        ]

        let snapshot = PersonalRecordListSnapshot.build(records: records)

        #expect(snapshot.groups.map(\.exerciseName) == ["Back Squat", "Bench Press"])
        #expect(snapshot.groups[0].records.map(\.repCount) == [3])
        #expect(snapshot.groups[1].records.map(\.repCount) == [1, 5])
    }

    @Test func personalRecordRefreshTokenChangesOnlyWhenVisibleRecordDataChanges() {
        let referenceDate = day(-1)
        let baseline = makeRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            exerciseName: "Deadlift",
            repCount: 3,
            weight: 405,
            dateAchieved: referenceDate
        )
        let sameValueCopy = makeRecord(
            id: baseline.id,
            exerciseName: "Deadlift",
            repCount: 3,
            weight: 405,
            dateAchieved: referenceDate
        )
        let changedWeight = makeRecord(
            id: baseline.id,
            exerciseName: "Deadlift",
            repCount: 3,
            weight: 415,
            dateAchieved: referenceDate
        )

        let baselineToken = PersonalRecordListSnapshot.refreshToken(for: [baseline])
        let sameToken = PersonalRecordListSnapshot.refreshToken(for: [sameValueCopy])
        let changedToken = PersonalRecordListSnapshot.refreshToken(for: [changedWeight])

        #expect(baselineToken == sameToken)
        #expect(baselineToken != changedToken)
    }

    private func makeRecord(
        id: UUID,
        exerciseName: String,
        repCount: Int,
        weight: Double,
        dateAchieved: Date
    ) -> PersonalRecord {
        PersonalRecord(
            id: id,
            exerciseName: exerciseName,
            repCount: repCount,
            weight: weight,
            unit: .lbs,
            dateAchieved: dateAchieved
        )
    }

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
    }
}
