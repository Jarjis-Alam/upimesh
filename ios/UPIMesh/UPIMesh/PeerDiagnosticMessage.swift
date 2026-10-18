import Foundation

/// Errors specifically related to diagnostic peer messages and connectivity testing.
public enum PeerDiagnosticError: LocalizedError, Equatable {
    case payloadTooLarge(Int)
    case malformedPayload(String)
    case unsupportedMessageType(String)
    case invalidReplyToId(String)
    case paymentFieldsForbidden
    case timeout
    case peerDisconnected
    case notConnected
    case sendFailed(String)
    case unmatchedResponse(String)

    public var errorDescription: String? {
        switch self {
        case .payloadTooLarge(let bytes):
            return "Diagnostic payload exceeds maximum allowable size (\(bytes) > \(PeerDiagnosticMessage.maxPayloadBytes) bytes)."
        case .malformedPayload(let msg):
            return "Malformed diagnostic message: \(msg)"
        case .unsupportedMessageType(let type):
            return "Unsupported diagnostic message type: '\(type)'. Only 'PING' and 'PONG' are supported."
        case .invalidReplyToId(let msg):
            return "Invalid replyToId in diagnostic message: \(msg)"
        case .paymentFieldsForbidden:
            return "Diagnostic message must not contain financial or payment fields."
        case .timeout:
            return "Diagnostic ping timed out waiting for peer response."
        case .peerDisconnected:
            return "Peer disconnected unexpectedly during diagnostic round-trip."
        case .notConnected:
            return "No connected peer device available for diagnostic ping."
        case .sendFailed(let msg):
            return "Failed to send diagnostic message: \(msg)"
        case .unmatchedResponse(let msg):
            return "Received unmatched diagnostic response: \(msg)"
        }
    }
}

/// Represents the round-trip state of a diagnostic ping test.
public enum PingStatus: Equatable, Sendable {
    case idle
    case sending(pingId: String, startedAt: Date)
    case success(roundTripDurationMs: Int, peerName: String, pingId: String)
    case failed(String)

    public var isSending: Bool {
        if case .sending = self { return true }
        return false
    }
}

/// A strictly non-financial diagnostic wire message exchanged over Multipeer Connectivity.
///
/// Features & Invariants:
/// - Verifies peer-to-peer connectivity and round-trip transport latency.
/// - Completely decoupled from payment packets, ledger accounts, and settlement.
/// - Contains NO payment amount, NO debit/credit accounts, NO nonces, NO payment IDs.
/// - Rejects any payload containing forbidden financial keys.
/// - Enforces maximum payload size limit of 16 KB.
public struct PeerDiagnosticMessage: Sendable, Codable, Equatable {

    public enum MessageType: String, Sendable, Codable, Equatable {
        case ping = "PING"
        case pong = "PONG"
    }

    /// Maximum allowable payload size (16 KB) for harmless diagnostic messages.
    public static let maxPayloadBytes: Int = 16 * 1024

    /// Keys strictly prohibited in diagnostic payloads to prevent payment data masquerading.
    public static let forbiddenPaymentKeys: Set<String> = [
        "amount", "paymentid", "fromaccount", "toaccount",
        "nonce", "signature", "instruction", "packet", "settlement"
    ]

    /// Message type: "PING" or "PONG".
    public let messageType: MessageType

    /// Unique identifier for this diagnostic message.
    public let diagnosticId: String

    /// Device ID of the transmitting node.
    public let senderDeviceId: String

    /// ISO-8601 creation timestamp.
    public let timestamp: String

    /// The diagnostic ID of the original ping being answered (required for PONG, nil for PING).
    public let replyToId: String?

    public init(
        messageType: MessageType,
        diagnosticId: String = UUID().uuidString.lowercased(),
        senderDeviceId: String,
        timestamp: String = PaymentInstant.now().isoString,
        replyToId: String? = nil
    ) {
        self.messageType = messageType
        self.diagnosticId = diagnosticId
        self.senderDeviceId = senderDeviceId
        self.timestamp = timestamp
        self.replyToId = replyToId
    }

    /// Validates message invariants before sending or accepting.
    public func validate() throws {
        guard !diagnosticId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PeerDiagnosticError.malformedPayload("Diagnostic ID must not be blank.")
        }
        guard !senderDeviceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PeerDiagnosticError.malformedPayload("Sender device ID must not be blank.")
        }
        guard !timestamp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PeerDiagnosticError.malformedPayload("Timestamp must not be blank.")
        }

        switch messageType {
        case .ping:
            if let replyTo = replyToId, !replyTo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw PeerDiagnosticError.invalidReplyToId("PING message must not contain a replyToId.")
            }
        case .pong:
            guard let replyTo = replyToId, !replyTo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PeerDiagnosticError.invalidReplyToId("PONG message must contain a valid replyToId referencing the original ping.")
            }
        }
    }

    /// Encodes this message to JSON Data, enforcing the maximum payload limit.
    public func encode() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maxPayloadBytes else {
            throw PeerDiagnosticError.payloadTooLarge(data.count)
        }
        return data
    }

    /// Decodes and strictly validates a diagnostic message from raw wire data.
    public static func decodeAndValidate(from data: Data) throws -> PeerDiagnosticMessage {
        guard data.count <= maxPayloadBytes else {
            throw PeerDiagnosticError.payloadTooLarge(data.count)
        }

        // Verify no forbidden payment keys exist in top-level JSON dictionary
        if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let lowercasedKeys = Set(jsonObject.keys.map { $0.lowercased() })
            let forbiddenFound = lowercasedKeys.intersection(forbiddenPaymentKeys)
            if !forbiddenFound.isEmpty {
                throw PeerDiagnosticError.paymentFieldsForbidden
            }
        }

        let decoder = JSONDecoder()
        let message: PeerDiagnosticMessage
        do {
            message = try decoder.decode(PeerDiagnosticMessage.self, from: data)
        } catch {
            throw PeerDiagnosticError.malformedPayload(error.localizedDescription)
        }

        try message.validate()
        return message
    }
}

/// Lightweight probe to inspect raw inbound Multipeer Connectivity data
/// and route safely to either diagnostic or payment pipelines without data leakage.
public struct InboundTransportProbe: Decodable {
    public let messageType: String?
    public let messageVersion: Int?

    public enum Route: Equatable {
        case diagnosticPing
        case diagnosticPong
        case paymentAck
        case invalidDiagnostic(String)
        case paymentTransfer
        case unknown
    }

    public static func probe(data: Data) -> Route {
        guard let probe = try? JSONDecoder().decode(InboundTransportProbe.self, from: data) else {
            return .unknown
        }

        if let type = probe.messageType {
            switch type.uppercased() {
            case "PING":
                return .diagnosticPing
            case "PONG":
                return .diagnosticPong
            case "PAYMENT_ACK":
                return .paymentAck
            default:
                return .invalidDiagnostic(type)
            }
        }

        if probe.messageVersion != nil {
            return .paymentTransfer
        }

        return .unknown
    }
}
