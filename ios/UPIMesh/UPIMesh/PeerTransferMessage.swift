import Foundation

/// Errors that can occur during peer-to-peer offline packet transport and ingestion.
public enum PeerTransferError: LocalizedError, Equatable {
    case payloadTooLarge(Int)
    case unsupportedMessageVersion(Int)
    case unsupportedSchemaVersion(Int)
    case malformedPayload(String)
    case duplicatePacket(String)
    case signatureVerificationFailed(String)
    case missingPublicKey
    case transferFailed(String)
    case notConnected
    case peerDisconnected

    public var errorDescription: String? {
        switch self {
        case .payloadTooLarge(let bytes):
            return "Payload exceeds maximum allowable size (\(bytes) > \(PeerTransferMessage.maxPayloadBytes) bytes)."
        case .unsupportedMessageVersion(let v):
            return "Unsupported transport message version (\(v))."
        case .unsupportedSchemaVersion(let v):
            return "Unsupported packet schema version (\(v))."
        case .malformedPayload(let msg):
            return "Malformed transport message: \(msg)"
        case .duplicatePacket(let id):
            return "Payment packet '\(id)' has already been imported or queued on this device."
        case .signatureVerificationFailed(let msg):
            return "Cryptographic signature verification failed: \(msg)"
        case .missingPublicKey:
            return "Sender public key is required for offline signature verification."
        case .transferFailed(let msg):
            return "Direct peer transport failed: \(msg)"
        case .notConnected:
            return "No connected peer device available for transport."
        case .peerDisconnected:
            return "Peer disconnected unexpectedly during transport."
        }
    }
}

/// The transport message envelope exchanged between nearby devices over Multipeer Connectivity.
///
/// Under the prototype trust boundary:
/// - Contains the self-contained `OfflinePaymentPacket`.
/// - Optionally contains the sender's Base64 X.509 RSA public key for mathematical verification.
/// - Does NOT contain any private keys, Keychain secrets, or credentials.
public struct PeerTransferMessage: Sendable, Codable, Equatable {

    /// Current transport message version.
    public static let currentVersion = 1

    /// Maximum allowable message size (64 KB) to prevent memory exhaustion and buffer overflows.
    public static let maxPayloadBytes = 64 * 1024

    /// The version of the peer transport wire envelope.
    public let messageVersion: Int

    /// The signed offline payment packet.
    public let packet: OfflinePaymentPacket

    /// The sender's exported X.509 SubjectPublicKeyInfo public key (Base64).
    public let senderPublicKeyBase64X509: String?

    public init(
        messageVersion: Int = 1,
        packet: OfflinePaymentPacket,
        senderPublicKeyBase64X509: String? = nil
    ) {
        self.messageVersion = messageVersion
        self.packet = packet
        self.senderPublicKeyBase64X509 = senderPublicKeyBase64X509
    }

    /// Validates the message envelope and packet invariants before accepting.
    public func validate() throws {
        guard messageVersion == Self.currentVersion else {
            throw PeerTransferError.unsupportedMessageVersion(messageVersion)
        }
        guard packet.schemaVersion == 1 else {
            throw PeerTransferError.unsupportedSchemaVersion(packet.schemaVersion)
        }
        guard packet.amount > 0, !packet.amount.isNaN else {
            throw PeerTransferError.malformedPayload("Transfer amount must be strictly greater than zero.")
        }
        guard packet.fromAccount.caseInsensitiveCompare(packet.toAccount) != .orderedSame else {
            throw PeerTransferError.malformedPayload("Sender and recipient accounts cannot be identical.")
        }
        guard !packet.paymentId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PeerTransferError.malformedPayload("Payment ID must not be blank.")
        }
        guard !packet.deviceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PeerTransferError.malformedPayload("Signer device ID must not be blank.")
        }
        guard !packet.signature.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PeerTransferError.malformedPayload("Digital signature must not be blank.")
        }
        // Validate consistency between top-level fields and embedded instruction
        guard packet.instruction.paymentId == packet.paymentId,
              packet.instruction.fromAccount.caseInsensitiveCompare(packet.fromAccount) == .orderedSame,
              packet.instruction.toAccount.caseInsensitiveCompare(packet.toAccount) == .orderedSame,
              packet.instruction.amount == packet.amount,
              packet.instruction.nonce == packet.nonce,
              packet.instruction.signature == packet.signature else {
            throw PeerTransferError.malformedPayload("Embedded PaymentInstruction does not match packet header fields.")
        }
    }
}
