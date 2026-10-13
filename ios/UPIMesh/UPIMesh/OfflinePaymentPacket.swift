import Foundation

/// Represents the lifecycle status of a locally stored offline payment packet.
///
/// Under the prototype architecture:
/// - `queued`: The packet has been locally signed, validated, and persisted on the device.
///   It is stored in durable device storage awaiting mesh propagation or bridge upload.
///   NOTE: `QUEUED` DOES NOT mean or imply that the payment has settled, nor does it guarantee
///   settlement or prevent offline double-spending. The authoritative backend ledger remains the
///   sole arbiter of balance validation, replay detection, and final settlement.
public enum OfflinePacketStatus: String, Sendable, Codable, Equatable {
    case queued = "QUEUED"
    case received = "RECEIVED"
    case settled = "SETTLED"
}

/// Persistent reconciliation status for an offline payment packet in a recipient's inbox.
///
/// Under the prototype architecture:
/// - `received`: The packet was transferred over peer transport and stored in the local inbox.
///   It is awaiting submission to the backend bridge when network connectivity is available.
/// - `settling`: Submission to the backend bridge is actively in progress.
/// - `settled`: Backend settlement on the authoritative ledger is confirmed.
/// - `failed`: Terminal rejection was confirmed by the backend (e.g. insufficient funds, expired, unauthorized).
public enum ReceivedReconciliationStatus: String, Sendable, Codable, Equatable, CaseIterable {
    case received = "RECEIVED"
    case settling = "SETTLING"
    case settled = "SETTLED"
    case failed = "FAILED"

    public var displayName: String {
        switch self {
        case .received: return "RECEIVED"
        case .settling: return "SETTLING"
        case .settled: return "SETTLED"
        case .failed: return "FAILED"
        }
    }
}

/// Errors occurring during `OfflinePaymentPacket` validation.
public enum OfflinePaymentPacketError: LocalizedError, Equatable {
    case blankField(String)
    case invalidAccounts(String)
    case invalidAmount(String)
    case missingSignature
    case mismatchedInstructionField(String)
    case invalidStatus(String)

    public var errorDescription: String? {
        switch self {
        case .blankField(let field):
            return "\(field) must not be blank"
        case .invalidAccounts(let msg):
            return msg
        case .invalidAmount(let msg):
            return msg
        case .missingSignature:
            return "Offline payment packet requires a non-empty digital signature"
        case .mismatchedInstructionField(let field):
            return "Offline packet field '\(field)' does not match embedded PaymentInstruction"
        case .invalidStatus(let msg):
            return msg
        }
    }
}

/// A locally stored, cryptographically signed offline payment packet.
///
/// Implements the foundational Stage 6 offline packet schema:
/// - Self-contained offline payment payload containing the canonical instruction and device signature.
/// - Persisted in durable local storage on iOS.
/// - Contains NO private keys, symmetric credentials, or sensitive secrets.
/// - Status is initialized to `.queued`.
public struct OfflinePaymentPacket: Sendable, Codable, Equatable, Identifiable {

    /// Schema version for packet serialization compatibility.
    public let schemaVersion: Int

    /// Unique RFC-4122 v4 UUID identifying the payment transaction.
    public let paymentId: String

    /// Cryptographic single-use nonce for replay protection.
    public let nonce: String

    /// The debtor funding account identifier (e.g. "alice").
    public let fromAccount: String

    /// The creditor receiving account identifier (e.g. "bob").
    public let toAccount: String

    /// The monetary transfer amount.
    public let amount: Decimal

    /// Nanosecond-precision UTC creation timestamp matching OpenJDK's `Instant.toString()`.
    public let createdAt: PaymentInstant

    /// The hardware/Keychain installation UUID of the signing device.
    public let deviceId: String

    /// The embedded canonical `PaymentInstruction` record.
    public let instruction: PaymentInstruction

    /// The Base64-encoded RSASSA-PSS SHA-256 digital signature.
    public let signature: String

    /// The local packet status (initially `.queued`).
    public let status: OfflinePacketStatus

    /// Identifiable conformance using unique `paymentId`.
    public var id: String {
        paymentId
    }

    /// The deterministic length-prefixed canonical UTF-8 bytes to be verified by recipient or bridge.
    public var canonicalBytes: Data {
        instruction.toCanonicalBytes()
    }

    /// The canonical string representation matching Java's `PaymentInstruction.toCanonicalBytes()`.
    public var canonicalString: String {
        instruction.toCanonicalString()
    }

    /// Convenience accessor for Double representations.
    public var amountDouble: Double {
        NSDecimalNumber(decimal: amount).doubleValue
    }

    /// Canonical constructor validating all packet invariants.
    public init(
        schemaVersion: Int = 1,
        paymentId: String,
        nonce: String,
        fromAccount: String,
        toAccount: String,
        amount: Decimal,
        createdAt: PaymentInstant,
        deviceId: String,
        instruction: PaymentInstruction,
        signature: String,
        status: OfflinePacketStatus = .queued
    ) throws {
        let trimmedPaymentId = paymentId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPaymentId.isEmpty else {
            throw OfflinePaymentPacketError.blankField("paymentId")
        }

        let trimmedNonce = nonce.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNonce.isEmpty else {
            throw OfflinePaymentPacketError.blankField("nonce")
        }

        let trimmedFrom = fromAccount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFrom.isEmpty else {
            throw OfflinePaymentPacketError.blankField("fromAccount")
        }

        let trimmedTo = toAccount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTo.isEmpty else {
            throw OfflinePaymentPacketError.blankField("toAccount")
        }

        guard trimmedFrom.caseInsensitiveCompare(trimmedTo) != .orderedSame else {
            throw OfflinePaymentPacketError.invalidAccounts("Sender and recipient accounts must be different")
        }

        guard amount > 0, !amount.isNaN else {
            throw OfflinePaymentPacketError.invalidAmount("Transfer amount must be strictly greater than zero and finite")
        }

        let trimmedDeviceId = deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDeviceId.isEmpty else {
            throw OfflinePaymentPacketError.blankField("deviceId")
        }

        let trimmedSig = signature.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSig.isEmpty else {
            throw OfflinePaymentPacketError.missingSignature
        }

        // Validate consistency between top-level fields and embedded instruction
        guard instruction.paymentId == trimmedPaymentId else {
            throw OfflinePaymentPacketError.mismatchedInstructionField("paymentId")
        }
        guard instruction.fromAccount.caseInsensitiveCompare(trimmedFrom) == .orderedSame else {
            throw OfflinePaymentPacketError.mismatchedInstructionField("fromAccount")
        }
        guard instruction.toAccount.caseInsensitiveCompare(trimmedTo) == .orderedSame else {
            throw OfflinePaymentPacketError.mismatchedInstructionField("toAccount")
        }
        guard instruction.amount == amount else {
            throw OfflinePaymentPacketError.mismatchedInstructionField("amount")
        }
        guard instruction.nonce == trimmedNonce else {
            throw OfflinePaymentPacketError.mismatchedInstructionField("nonce")
        }
        guard instruction.signature == trimmedSig else {
            throw OfflinePaymentPacketError.mismatchedInstructionField("signature")
        }

        self.schemaVersion = schemaVersion
        self.paymentId = trimmedPaymentId
        self.nonce = trimmedNonce
        self.fromAccount = trimmedFrom
        self.toAccount = trimmedTo
        self.amount = amount
        self.createdAt = createdAt
        self.deviceId = trimmedDeviceId
        self.instruction = instruction
        self.signature = trimmedSig
        self.status = status
    }

    /// Convenience initializer constructing an `OfflinePaymentPacket` directly from a signed `PaymentInstruction`.
    public init(
        instruction: PaymentInstruction,
        deviceId: String,
        schemaVersion: Int = 1,
        status: OfflinePacketStatus = .queued
    ) throws {
        guard let sig = instruction.signature, !sig.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OfflinePaymentPacketError.missingSignature
        }

        try self.init(
            schemaVersion: schemaVersion,
            paymentId: instruction.paymentId,
            nonce: instruction.nonce,
            fromAccount: instruction.fromAccount,
            toAccount: instruction.toAccount,
            amount: instruction.amount,
            createdAt: instruction.createdAt,
            deviceId: deviceId,
            instruction: instruction,
            signature: sig,
            status: status
        )
    }

    /// Returns a copy of this offline packet with a new lifecycle status.
    /// Invariants and signatures remain unchanged.
    public func withStatus(_ newStatus: OfflinePacketStatus) throws -> OfflinePaymentPacket {
        try OfflinePaymentPacket(
            schemaVersion: schemaVersion,
            paymentId: paymentId,
            nonce: nonce,
            fromAccount: fromAccount,
            toAccount: toAccount,
            amount: amount,
            createdAt: createdAt,
            deviceId: deviceId,
            instruction: instruction,
            signature: signature,
            status: newStatus
        )
    }
}
