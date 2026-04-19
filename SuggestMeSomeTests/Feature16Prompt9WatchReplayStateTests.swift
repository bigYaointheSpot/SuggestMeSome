import Foundation
import Testing
@testable import SuggestMeSome

@MainActor
struct Feature16Prompt9WatchReplayStateTests {

    @Test func replayStateDedupesIdenticalNonCriticalFingerprints() throws {
        var replayState = WatchReplayState()
        let snapshot = makeTodayPlanSnapshot(label: "Recovery")
        let fingerprint = try #require(
            WatchPayloadFingerprint(kind: .todayPlanSnapshot, payload: snapshot)
        )

        let firstSend = replayState.shouldSend(fingerprint, dedupeIdentical: true)
        let secondSend = replayState.shouldSend(fingerprint, dedupeIdentical: true)

        #expect(firstSend)
        #expect(!secondSend)
    }

    @Test func replayStateForcesOneReplayWhenPeerNeedsStateAgain() throws {
        var replayState = WatchReplayState()
        let snapshot = makeTodayPlanSnapshot(label: "Heavy Day")
        let fingerprint = try #require(
            WatchPayloadFingerprint(kind: .todayPlanSnapshot, payload: snapshot)
        )

        let firstSend = replayState.shouldSend(fingerprint, dedupeIdentical: true)
        replayState.markPeerMissing([.todayPlanSnapshot, .liveWorkoutSnapshot])
        let replaySend = replayState.shouldSend(fingerprint, dedupeIdentical: true)
        let dedupedAgain = replayState.shouldSend(fingerprint, dedupeIdentical: true)

        #expect(firstSend)
        #expect(replaySend)
        #expect(!dedupedAgain)
    }

    @Test func replayStateKeepsImmediateChannelsSendable() throws {
        var replayState = WatchReplayState()
        let payload = WatchWorkoutLaunchPayload(
            workoutID: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_800_500_000),
            sessionPlanKind: .planned,
            lifecycleState: .running,
            sessionSourceLabels: ["Program"],
            sessionVersionStableID: "launch-1"
        )
        let fingerprint = try #require(
            WatchPayloadFingerprint(kind: .workoutLaunch, payload: payload)
        )

        let firstSend = replayState.shouldSend(fingerprint, dedupeIdentical: false)
        let secondSend = replayState.shouldSend(fingerprint, dedupeIdentical: false)

        #expect(firstSend)
        #expect(secondSend)
    }

    @Test func payloadFingerprintMatchesEquivalentBridgeMessages() throws {
        let payload = makeTodayPlanSnapshot(label: "Deload")
        let firstMessage = try WatchBridgeMessageCodec.makeMessage(
            kind: .todayPlanSnapshot,
            payload: payload,
            sentAt: Date(timeIntervalSince1970: 1_800_500_100)
        )
        let secondMessage = try WatchBridgeMessageCodec.makeMessage(
            kind: .todayPlanSnapshot,
            payload: payload,
            sentAt: Date(timeIntervalSince1970: 1_800_500_200)
        )

        let firstFingerprint = WatchPayloadFingerprint(
            message: try WatchBridgeMessageCodec.decodeMessage(from: firstMessage)
        )
        let secondFingerprint = WatchPayloadFingerprint(
            message: try WatchBridgeMessageCodec.decodeMessage(from: secondMessage)
        )

        #expect(firstFingerprint == secondFingerprint)
    }

    private func makeTodayPlanSnapshot(label: String) -> WatchTodayPlanSnapshot {
        WatchTodayPlanSnapshot(
            confidence: "High",
            compactSummary: "Stay on plan.",
            primarySuggestionText: "Train as scheduled.",
            readinessTier: "Strong",
            hasPainFlag: false,
            sessionLabel: label,
            programName: "Peak Block",
            programRunStableID: "run-1",
            programWeekNumber: 3,
            programSessionNumber: 2,
            activeSourceLabels: ["Program"],
            whatChangedToday: "",
            adherenceHeadline: nil,
            adherenceGuidanceType: nil,
            sessionsBehindCount: 0,
            pendingProposalCount: 0,
            generatedAt: Date(timeIntervalSince1970: 1_800_500_000)
        )
    }
}
