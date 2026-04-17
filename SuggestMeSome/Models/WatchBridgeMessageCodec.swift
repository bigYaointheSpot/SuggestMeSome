//
//  WatchBridgeMessageCodec.swift
//  SuggestMeSome
//
//  Pure dictionary codec for WatchConnectivity payload messages.
//

import Foundation

private struct WatchPayloadDecodingEnvelope<Payload: Decodable>: Decodable {
    let schemaVersion: Int
    let kind: WatchPayloadKind
    let sentAt: Date
    let payload: Payload
}

struct WatchBridgeMessage: Equatable {
    let schemaVersion: Int
    let kind: WatchPayloadKind
    let sentAt: Date
    let payloadJSON: Data

    var isSupportedSchemaVersion: Bool {
        schemaVersion <= WatchPayloadContractVersion.current
    }
}

enum WatchBridgeMessageCodecError: Error, Equatable {
    case missingOrInvalidValue(String)
    case unsupportedKind(String)
    case payloadEncodingFailed
    case payloadDecodingFailed
}

enum WatchBridgeMessageCodec {
    static let schemaVersionKey = "schemaVersion"
    static let kindKey = "kind"
    static let sentAtKey = "sentAt"
    static let payloadJSONKey = "payloadJSON"

    static func makeMessage<Payload: Encodable>(
        kind: WatchPayloadKind,
        payload: Payload,
        sentAt: Date = Date(),
        schemaVersion: Int = WatchPayloadContractVersion.current
    ) throws -> [String: Any] {
        [
            schemaVersionKey: schemaVersion,
            kindKey: kind.rawValue,
            sentAtKey: sentAt.timeIntervalSince1970,
            payloadJSONKey: try encodePayload(payload)
        ]
    }

    static func makeMessageIfPossible<Payload: Encodable>(
        kind: WatchPayloadKind,
        payload: Payload,
        sentAt: Date = Date(),
        schemaVersion: Int = WatchPayloadContractVersion.current
    ) -> [String: Any]? {
        try? makeMessage(
            kind: kind,
            payload: payload,
            sentAt: sentAt,
            schemaVersion: schemaVersion
        )
    }

    static func decodeMessage(from dictionary: [String: Any]) throws -> WatchBridgeMessage {
        guard let schemaVersion = dictionary[schemaVersionKey] as? Int else {
            throw WatchBridgeMessageCodecError.missingOrInvalidValue(schemaVersionKey)
        }
        guard let kindValue = dictionary[kindKey] as? String else {
            throw WatchBridgeMessageCodecError.missingOrInvalidValue(kindKey)
        }
        guard let kind = WatchPayloadKind(rawValue: kindValue) else {
            throw WatchBridgeMessageCodecError.unsupportedKind(kindValue)
        }
        guard let sentAt = decodeSentAt(dictionary[sentAtKey]) else {
            throw WatchBridgeMessageCodecError.missingOrInvalidValue(sentAtKey)
        }
        guard let payloadJSON = dictionary[payloadJSONKey] as? Data else {
            throw WatchBridgeMessageCodecError.missingOrInvalidValue(payloadJSONKey)
        }

        return WatchBridgeMessage(
            schemaVersion: schemaVersion,
            kind: kind,
            sentAt: sentAt,
            payloadJSON: payloadJSON
        )
    }

    static func encodePayload<Payload: Encodable>(_ payload: Payload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        do {
            return try encoder.encode(payload)
        } catch {
            throw WatchBridgeMessageCodecError.payloadEncodingFailed
        }
    }

    static func encodeEnvelopePayload<Payload: Codable & Equatable>(
        kind: WatchPayloadKind,
        payload: Payload,
        sentAt: Date = Date(),
        schemaVersion: Int = WatchPayloadContractVersion.current
    ) throws -> Data {
        try encodePayload(
            WatchPayloadEnvelope(
                kind: kind,
                payload: payload,
                sentAt: sentAt,
                schemaVersion: schemaVersion
            )
        )
    }

    static func decodePayload<Payload: Decodable>(
        _ type: Payload.Type,
        from message: WatchBridgeMessage
    ) throws -> Payload {
        try decodePayload(type, from: message.payloadJSON)
    }

    static func decodePayload<Payload: Decodable>(
        _ type: Payload.Type,
        from data: Data
    ) throws -> Payload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        if let wrapped = try? decoder.decode(WatchPayloadDecodingEnvelope<Payload>.self, from: data) {
            return wrapped.payload
        }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw WatchBridgeMessageCodecError.payloadDecodingFailed
        }
    }

    private static func decodeSentAt(_ value: Any?) -> Date? {
        switch value {
        case let date as Date:
            return date
        case let timeInterval as TimeInterval:
            return Date(timeIntervalSince1970: timeInterval)
        case let intValue as Int:
            return Date(timeIntervalSince1970: TimeInterval(intValue))
        case let stringValue as String:
            guard let timeInterval = TimeInterval(stringValue) else { return nil }
            return Date(timeIntervalSince1970: timeInterval)
        default:
            return nil
        }
    }
}
