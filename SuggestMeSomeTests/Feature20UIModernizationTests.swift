//
//  Feature20UIModernizationTests.swift
//  SuggestMeSomeTests
//
//  Pure-function coverage for the UI modernization pass —
//  SetEntryRow's numeric sanitizers (paste-guard, decimal handling) and
//  ExerciseDisplayFormatter's golden outputs so the extracted helpers
//  remain behavior-identical to the inline ProgramReviewView versions.
//

import Foundation
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature20UIModernizationTests {

    // MARK: - Reps sanitizer

    @Test func repsSanitizerStripsNonDigits() {
        #expect(SetEntryRow.sanitizeReps("12abc") == "12")
        #expect(SetEntryRow.sanitizeReps("1.5") == "15")
        #expect(SetEntryRow.sanitizeReps("-3") == "3")
        #expect(SetEntryRow.sanitizeReps("") == "")
    }

    @Test func repsSanitizerCapsAtFourDigits() {
        #expect(SetEntryRow.sanitizeReps("12345") == "1234")
        #expect(SetEntryRow.sanitizeReps("99999999") == "9999")
    }

    @Test func repsSanitizerIsIdempotent() {
        let valid = "42"
        #expect(SetEntryRow.sanitizeReps(valid) == valid)
    }

    // MARK: - Weight sanitizer

    @Test func weightSanitizerAllowsSingleDot() {
        #expect(SetEntryRow.sanitizeWeight("185.5") == "185.5")
        #expect(SetEntryRow.sanitizeWeight("0.5") == "0.5")
    }

    @Test func weightSanitizerPreservesLocalizedComma() {
        #expect(SetEntryRow.sanitizeWeight("82,5") == "82,5")
    }

    @Test func weightSanitizerCollapsesExtraSeparators() {
        #expect(SetEntryRow.sanitizeWeight("1.2.3") == "1.23")
        #expect(SetEntryRow.sanitizeWeight("1,2,3") == "1,23")
    }

    @Test func weightSanitizerStripsNonNumericGarbage() {
        #expect(SetEntryRow.sanitizeWeight("abc42.5xyz") == "42.5")
        #expect(SetEntryRow.sanitizeWeight("(185lbs)") == "185")
    }

    @Test func weightSanitizerCapsLength() {
        #expect(SetEntryRow.sanitizeWeight("1234567890") == "123456")
        #expect(SetEntryRow.sanitizeWeight("12.34567") == "12.345")
    }

    // MARK: - DraftSet round-trip under sanitizer

    @Test func draftSetPreservesSanitizedStringsExactly() throws {
        var draft = DraftSet(setNumber: 1, repsText: "", weightText: "")
        draft.repsText = SetEntryRow.sanitizeReps("12abc")
        draft.weightText = SetEntryRow.sanitizeWeight("185.5xyz")

        let encoded = try JSONEncoder().encode(draft)
        let decoded = try JSONDecoder().decode(DraftSet.self, from: encoded)

        #expect(decoded.repsText == "12")
        #expect(decoded.weightText == "185.5")
        #expect(decoded.setNumber == 1)
    }

    // MARK: - ExerciseDisplayFormatter extracted helpers

    @Test func workingSetStyleLabelPicksCardioWhenTargetSetsNil() {
        let cardio = ProgramSessionExercise(exerciseName: "Run", orderIndex: 0)
        cardio.targetSets = nil
        #expect(ExerciseDisplayFormatter.workingSetStyleLabel(for: cardio) == "Cardio")
    }

    @Test func workingSetStyleLabelCoversAllStrengthVariants() {
        let exercise = ProgramSessionExercise(exerciseName: "Bench Press", orderIndex: 0)
        exercise.targetSets = 3

        exercise.workingSetStyle = .topSet
        #expect(ExerciseDisplayFormatter.workingSetStyleLabel(for: exercise) == "Top Set")

        exercise.workingSetStyle = .backoff
        #expect(ExerciseDisplayFormatter.workingSetStyleLabel(for: exercise) == "Backoff")

        exercise.workingSetStyle = .straight
        #expect(ExerciseDisplayFormatter.workingSetStyleLabel(for: exercise) == "Straight Sets")

        exercise.workingSetStyle = nil
        #expect(ExerciseDisplayFormatter.workingSetStyleLabel(for: exercise) == "Straight Sets")
    }

    @Test func exercisePurposeAndSelectionReasonLabelsForwardShortLabel() {
        let exercise = ProgramSessionExercise(exerciseName: "Seated Row", orderIndex: 0)
        exercise.explainabilityPurpose = .specificity
        exercise.explainabilitySelectionReason = .sessionSpecificity

        #expect(ExerciseDisplayFormatter.exercisePurposeLabel(for: exercise) == ProgramExercisePurposeCode.specificity.shortLabel)
        #expect(ExerciseDisplayFormatter.exerciseSelectionReasonLabel(for: exercise) == ProgramAccessorySelectionReason.sessionSpecificity.shortLabel)
    }

    @Test func exercisePurposeAndSelectionReasonReturnNilWhenUntagged() {
        let exercise = ProgramSessionExercise(exerciseName: "Curl", orderIndex: 0)
        #expect(ExerciseDisplayFormatter.exercisePurposeLabel(for: exercise) == nil)
        #expect(ExerciseDisplayFormatter.exerciseSelectionReasonLabel(for: exercise) == nil)
    }
}
