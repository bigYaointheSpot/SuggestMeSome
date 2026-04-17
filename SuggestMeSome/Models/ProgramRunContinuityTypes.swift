//
//  ProgramRunContinuityTypes.swift
//  SuggestMeSome
//
//  Feature 13 Prompt 5 — Additive continuity and long-horizon summary types.
//

import Foundation

enum ProgramRunContinuityContractVersion {
    static let v1 = 1
    static let v2 = 2
    static let v3 = 3
    static let current = v3
}

struct ProgramRunContinuityEnvelope<Payload: Codable>: Codable {
    let schemaVersion: Int
    let payload: Payload

    init(
        payload: Payload,
        schemaVersion: Int = ProgramRunContinuityContractVersion.current
    ) {
        self.schemaVersion = schemaVersion
        self.payload = payload
    }
}

private struct ProgramRunContinuityDecodingEnvelope<Payload: Decodable>: Decodable {
    let schemaVersion: Int
    let payload: Payload
}

struct ProgramRunRecommendationSnapshot: Codable, Equatable {
    let stableID: String
    let rank: Int
    let kind: MesocycleNextBlockRecommendationKind
    let title: String
    let summary: String
    let rationale: [String]
    let targetFocus: ProgramFocus
    let targetFocusDisplayName: String
    let suggestedLevel: ProgramLevel
    let suggestedDurationWeeks: Int
    let suggestedSessionsPerWeek: Int
    let fitScore: Int
    let fitNote: String?
    let isPrimaryRecommendation: Bool
    let explanationBundle: AdaptiveExplanationBundle?

    nonisolated init(recommendation: MesocycleNextBlockRecommendation) {
        self.stableID = recommendation.stableID
        self.rank = recommendation.rank
        self.kind = recommendation.kind
        self.title = recommendation.title
        self.summary = recommendation.summary
        self.rationale = recommendation.rationale
        self.targetFocus = recommendation.targetFocus
        self.targetFocusDisplayName = recommendation.targetFocusDisplayName
        self.suggestedLevel = recommendation.suggestedLevel
        self.suggestedDurationWeeks = recommendation.suggestedDurationWeeks
        self.suggestedSessionsPerWeek = recommendation.suggestedSessionsPerWeek
        self.fitScore = recommendation.fitScore
        self.fitNote = recommendation.fitNote
        self.isPrimaryRecommendation = recommendation.isPrimaryRecommendation
        self.explanationBundle = recommendation.explanationBundle
    }
}

struct ProgramRunRecommendationDecisionEvent: Codable, Equatable {
    let stableID: String
    let recommendationStableID: String
    let decision: MesocycleRecommendationDecision
    let decidedAt: Date
    let userEditedFields: [NextBlockPrefillField]
    let confirmedSteeringProfile: AdaptiveSteeringProfile?
    let editedAdjustmentSnapshot: [AdaptiveAdjustment]?

    init(
        recommendationStableID: String,
        decision: MesocycleRecommendationDecision,
        decidedAt: Date,
        userEditedFields: [NextBlockPrefillField] = [],
        confirmedSteeringProfile: AdaptiveSteeringProfile? = nil,
        editedAdjustmentSnapshot: [AdaptiveAdjustment]? = nil
    ) {
        self.stableID = "\(recommendationStableID)::\(decision.rawValue)"
        self.recommendationStableID = recommendationStableID
        self.decision = decision
        self.decidedAt = decidedAt
        self.userEditedFields = userEditedFields.sorted { $0.rawValue < $1.rawValue }
        self.confirmedSteeringProfile = confirmedSteeringProfile
        self.editedAdjustmentSnapshot = editedAdjustmentSnapshot
    }
}

struct ProgramBlockContinuitySnapshot: Codable, Equatable {
    let sourceProgramRunStableID: String
    let sourceTrainingProgramStableID: String?
    let reviewStableID: String
    let sourceProgramName: String
    let snapshotRecordedAt: Date
    let recommendationSnapshots: [ProgramRunRecommendationSnapshot]
    let selectedRecommendationStableID: String?
    let selectedRecommendationSnapshot: ProgramRunRecommendationSnapshot?
    let declinedRecommendationStableIDs: [String]
    let decisionEvents: [ProgramRunRecommendationDecisionEvent]
    let carriedForwardContext: ProgramGenerationCarryForwardContext?
    let editedPrefillSnapshot: NextBlockPrefillContext?
    let userEditedFields: [NextBlockPrefillField]
    let latestConfirmedSteeringProfile: AdaptiveSteeringProfile?
    let latestEditedAdjustments: [AdaptiveAdjustment]?

    init(
        sourceProgramRunStableID: String,
        sourceTrainingProgramStableID: String?,
        reviewStableID: String,
        sourceProgramName: String,
        snapshotRecordedAt: Date,
        recommendationSnapshots: [ProgramRunRecommendationSnapshot],
        selectedRecommendationStableID: String?,
        selectedRecommendationSnapshot: ProgramRunRecommendationSnapshot?,
        declinedRecommendationStableIDs: [String],
        decisionEvents: [ProgramRunRecommendationDecisionEvent],
        carriedForwardContext: ProgramGenerationCarryForwardContext?,
        editedPrefillSnapshot: NextBlockPrefillContext?,
        userEditedFields: [NextBlockPrefillField],
        latestConfirmedSteeringProfile: AdaptiveSteeringProfile? = nil,
        latestEditedAdjustments: [AdaptiveAdjustment]? = nil
    ) {
        self.sourceProgramRunStableID = sourceProgramRunStableID
        self.sourceTrainingProgramStableID = sourceTrainingProgramStableID
        self.reviewStableID = reviewStableID
        self.sourceProgramName = sourceProgramName
        self.snapshotRecordedAt = snapshotRecordedAt
        self.recommendationSnapshots = recommendationSnapshots
        self.selectedRecommendationStableID = selectedRecommendationStableID
        self.selectedRecommendationSnapshot = selectedRecommendationSnapshot
        self.declinedRecommendationStableIDs = declinedRecommendationStableIDs
        self.decisionEvents = decisionEvents
        self.carriedForwardContext = carriedForwardContext
        self.editedPrefillSnapshot = editedPrefillSnapshot
        self.userEditedFields = userEditedFields
        self.latestConfirmedSteeringProfile = latestConfirmedSteeringProfile
        self.latestEditedAdjustments = latestEditedAdjustments
    }

    func merged(with other: ProgramBlockContinuitySnapshot) -> ProgramBlockContinuitySnapshot {
        let newest = snapshotRecordedAt >= other.snapshotRecordedAt ? self : other
        let oldest = snapshotRecordedAt >= other.snapshotRecordedAt ? other : self

        let mergedRecommendationSnapshots = mergedRecommendationSnapshots(
            recommendationSnapshots + other.recommendationSnapshots
        )
        let mergedDecisionEvents = mergedDecisionEvents(decisionEvents + other.decisionEvents)
        let acceptedRecommendation = mergedDecisionEvents
            .filter { $0.decision == .accepted }
            .max { lhs, rhs in
                if lhs.decidedAt != rhs.decidedAt {
                    return lhs.decidedAt < rhs.decidedAt
                }
                return lhs.stableID < rhs.stableID
            }

        let selectedRecommendationStableID = acceptedRecommendation?.recommendationStableID ??
            newest.selectedRecommendationStableID ??
            oldest.selectedRecommendationStableID
        let selectedRecommendationSnapshot = selectedRecommendationStableID.flatMap { stableID in
            mergedRecommendationSnapshots.first(where: { $0.stableID == stableID })
        } ?? newest.selectedRecommendationSnapshot ?? oldest.selectedRecommendationSnapshot

        let declinedRecommendationStableIDs = orderedUniqueStrings(
            newest.declinedRecommendationStableIDs +
            oldest.declinedRecommendationStableIDs +
            mergedDecisionEvents
                .filter { $0.decision == .declined }
                .map(\.recommendationStableID)
        )
        let userEditedFields = orderedUniqueFields(
            newest.userEditedFields +
            oldest.userEditedFields +
            mergedDecisionEvents.flatMap(\.userEditedFields)
        )

        return ProgramBlockContinuitySnapshot(
            sourceProgramRunStableID: newest.sourceProgramRunStableID,
            sourceTrainingProgramStableID: newest.sourceTrainingProgramStableID ?? oldest.sourceTrainingProgramStableID,
            reviewStableID: newest.reviewStableID,
            sourceProgramName: newest.sourceProgramName.isEmpty ? oldest.sourceProgramName : newest.sourceProgramName,
            snapshotRecordedAt: max(snapshotRecordedAt, other.snapshotRecordedAt),
            recommendationSnapshots: mergedRecommendationSnapshots,
            selectedRecommendationStableID: selectedRecommendationStableID,
            selectedRecommendationSnapshot: selectedRecommendationSnapshot,
            declinedRecommendationStableIDs: declinedRecommendationStableIDs,
            decisionEvents: mergedDecisionEvents,
            carriedForwardContext: newest.carriedForwardContext ?? oldest.carriedForwardContext,
            editedPrefillSnapshot: newest.editedPrefillSnapshot ?? oldest.editedPrefillSnapshot,
            userEditedFields: userEditedFields,
            latestConfirmedSteeringProfile: newest.latestConfirmedSteeringProfile ?? oldest.latestConfirmedSteeringProfile,
            latestEditedAdjustments: newest.latestEditedAdjustments ?? oldest.latestEditedAdjustments
        )
    }
}

enum LongHorizonAdaptationInsightKind: String, Codable {
    case insufficientData
    case adherenceTrend
    case movementContinuity
    case toleratedFrequency
    case missedSessionPattern
    case standaloneInfluence
}

struct LongHorizonAdaptationInsight: Codable, Equatable {
    let kind: LongHorizonAdaptationInsightKind
    let title: String
    let detail: String
}

struct LongHorizonAdaptationSummary: Codable, Equatable {
    let anchorProgramRunStableID: String?
    let includedProgramRunStableIDs: [String]
    let blockCount: Int
    let includedStandaloneWorkoutCount: Int
    let headline: String
    let insights: [LongHorizonAdaptationInsight]
}

enum ProgramRunContinuityCodec {
    static func encode<T: Codable>(_ value: T?) -> String? {
        guard let value else { return nil }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(
            ProgramRunContinuityEnvelope(payload: value)
        ) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode<T: Decodable>(_ value: String?) -> T? {
        guard
            let value,
            let data = value.data(using: .utf8)
        else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        if let wrapped = try? decoder.decode(ProgramRunContinuityDecodingEnvelope<T>.self, from: data) {
            return wrapped.payload
        }
        return try? decoder.decode(T.self, from: data)
    }
}

extension ProgramRun {
    var recommendationDecisionHistorySnapshot: ProgramBlockContinuitySnapshot? {
        get { ProgramRunContinuityCodec.decode(recommendationDecisionHistoryJSON) }
        set { recommendationDecisionHistoryJSON = ProgramRunContinuityCodec.encode(newValue) }
    }

    var continuitySnapshot: ProgramBlockContinuitySnapshot? {
        get { ProgramRunContinuityCodec.decode(continuitySnapshotJSON) }
        set { continuitySnapshotJSON = ProgramRunContinuityCodec.encode(newValue) }
    }
}

func mergedRecommendationSnapshots(
    _ snapshots: [ProgramRunRecommendationSnapshot]
) -> [ProgramRunRecommendationSnapshot] {
    var byStableID: [String: ProgramRunRecommendationSnapshot] = [:]

    for snapshot in snapshots {
        if let existing = byStableID[snapshot.stableID] {
            if snapshot.rank < existing.rank || (snapshot.rank == existing.rank && snapshot.fitScore > existing.fitScore) {
                byStableID[snapshot.stableID] = snapshot
            }
        } else {
            byStableID[snapshot.stableID] = snapshot
        }
    }

    return byStableID.values.sorted { lhs, rhs in
        if lhs.rank != rhs.rank {
            return lhs.rank < rhs.rank
        }
        return lhs.stableID < rhs.stableID
    }
}

func mergedDecisionEvents(
    _ events: [ProgramRunRecommendationDecisionEvent]
) -> [ProgramRunRecommendationDecisionEvent] {
    var byStableID: [String: ProgramRunRecommendationDecisionEvent] = [:]

    for event in events {
        if let existing = byStableID[event.stableID] {
            if event.decidedAt > existing.decidedAt ||
                (event.decidedAt == existing.decidedAt && event.userEditedFields.count > existing.userEditedFields.count) {
                byStableID[event.stableID] = event
            }
        } else {
            byStableID[event.stableID] = event
        }
    }

    return byStableID.values.sorted { lhs, rhs in
        if lhs.decidedAt != rhs.decidedAt {
            return lhs.decidedAt < rhs.decidedAt
        }
        return lhs.stableID < rhs.stableID
    }
}

func orderedUniqueStrings(_ values: [String]) -> [String] {
    Array(Set(values)).sorted()
}

func orderedUniqueFields(_ values: [NextBlockPrefillField]) -> [NextBlockPrefillField] {
    Array(Set(values)).sorted { $0.rawValue < $1.rawValue }
}
