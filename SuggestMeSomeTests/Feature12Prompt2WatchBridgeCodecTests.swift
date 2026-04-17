//
//  Feature12Prompt2WatchBridgeCodecTests.swift
//  SuggestMeSomeTests
//
//  Feature 12 Prompt 2 — shared watch bridge codec validation.
//

import Foundation
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature12Prompt2WatchBridgeCodecTests {

    @Test func codecBuildsCurrentWireShapeAndDecodesPayload() throws {
        let workoutID = UUID()
        let capturedAt = Date(timeIntervalSince1970: 1_700_500_000)
        let sentAt = Date(timeIntervalSince1970: 1_700_500_100)
        let progress = WatchWorkoutProgressSnapshot(
            workoutID: workoutID,
            elapsedSeconds: 420,
            completedExercises: 2,
            totalExercises: 5,
            capturedAt: capturedAt
        )

        let dictionary = try WatchBridgeMessageCodec.makeMessage(
            kind: .workoutProgress,
            payload: progress,
            sentAt: sentAt
        )

        #expect(Set(dictionary.keys) == Set(["schemaVersion", "kind", "sentAt", "payloadJSON"]))
        #expect(dictionary["schemaVersion"] as? Int == WatchPayloadContractVersion.current)
        #expect(dictionary["kind"] as? String == WatchPayloadKind.workoutProgress.rawValue)
        #expect(dictionary["sentAt"] as? TimeInterval == sentAt.timeIntervalSince1970)
        #expect(dictionary["payloadJSON"] is Data)

        let message = try WatchBridgeMessageCodec.decodeMessage(from: dictionary)
        let decoded = try WatchBridgeMessageCodec.decodePayload(
            WatchWorkoutProgressSnapshot.self,
            from: message
        )

        #expect(message.schemaVersion == WatchPayloadContractVersion.current)
        #expect(message.kind == .workoutProgress)
        #expect(message.sentAt == sentAt)
        #expect(message.isSupportedSchemaVersion)
        #expect(decoded == progress)
    }

    @Test func codecRejectsMalformedTransportDictionaries() throws {
        do {
            _ = try WatchBridgeMessageCodec.decodeMessage(from: [
                "schemaVersion": WatchPayloadContractVersion.current,
                "kind": WatchPayloadKind.todayPlanSnapshot.rawValue,
                "sentAt": Date().timeIntervalSince1970
            ])
            Issue.record("Expected missing payloadJSON to fail decoding")
        } catch let error as WatchBridgeMessageCodecError {
            #expect(error == .missingOrInvalidValue("payloadJSON"))
        }

        do {
            _ = try WatchBridgeMessageCodec.decodeMessage(from: [
                "schemaVersion": WatchPayloadContractVersion.current,
                "kind": "unknownPayload",
                "sentAt": Date().timeIntervalSince1970,
                "payloadJSON": Data()
            ])
            Issue.record("Expected unknown kind to fail decoding")
        } catch let error as WatchBridgeMessageCodecError {
            #expect(error == .unsupportedKind("unknownPayload"))
        }
    }

    @Test func codecSurfacesFutureSchemaWithoutApplyingPolicy() throws {
        let payload = WatchWorkoutLaunchPayload(
            workoutID: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_700_600_000)
        )
        var dictionary = try WatchBridgeMessageCodec.makeMessage(
            kind: .workoutLaunch,
            payload: payload,
            sentAt: Date(timeIntervalSince1970: 1_700_600_010)
        )
        dictionary["schemaVersion"] = WatchPayloadContractVersion.current + 1

        let message = try WatchBridgeMessageCodec.decodeMessage(from: dictionary)
        let decoded = try WatchBridgeMessageCodec.decodePayload(
            WatchWorkoutLaunchPayload.self,
            from: message
        )

        #expect(message.schemaVersion == WatchPayloadContractVersion.current + 1)
        #expect(!message.isSupportedSchemaVersion)
        #expect(decoded == payload)
    }

    @Test func codecReportsPayloadDecodeFailures() {
        let message = WatchBridgeMessage(
            schemaVersion: WatchPayloadContractVersion.current,
            kind: .workoutProgress,
            sentAt: Date(timeIntervalSince1970: 1_700_700_000),
            payloadJSON: Data([0x7b])
        )

        do {
            _ = try WatchBridgeMessageCodec.decodePayload(
                WatchWorkoutProgressSnapshot.self,
                from: message
            )
            Issue.record("Expected invalid JSON payload to fail decoding")
        } catch let error as WatchBridgeMessageCodecError {
            #expect(error == .payloadDecodingFailed)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func codecDecodesEnvelopeWrappedPayloadsForForwardCompatibility() throws {
        let payload = WatchWorkoutLaunchPayload(
            workoutID: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_700_800_000)
        )
        let payloadData = try WatchBridgeMessageCodec.encodeEnvelopePayload(
            kind: .workoutLaunch,
            payload: payload,
            sentAt: Date(timeIntervalSince1970: 1_700_800_010)
        )
        let message = WatchBridgeMessage(
            schemaVersion: WatchPayloadContractVersion.current,
            kind: .workoutLaunch,
            sentAt: Date(timeIntervalSince1970: 1_700_800_010),
            payloadJSON: payloadData
        )

        let decoded = try WatchBridgeMessageCodec.decodePayload(
            WatchWorkoutLaunchPayload.self,
            from: message
        )

        #expect(decoded == payload)
    }
}
