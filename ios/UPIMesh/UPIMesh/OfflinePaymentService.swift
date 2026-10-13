import Foundation

/// Errors that can occur during offline payment packet creation.
public enum OfflinePaymentServiceError: LocalizedError, Equatable {
    case invalidAmount(String)
    case invalidAccounts(String)
    case identityError(String)
    case signingError(String)
    case storageError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidAmount(let msg):
            return "Invalid payment amount: \(msg)"
        case .invalidAccounts(let msg):
            return "Invalid account configuration: \(msg)"
        case .identityError(let msg):
            return "Failed to acquire device identity: \(msg)"
        case .signingError(let msg):
            return "Failed to cryptographically sign payment instruction: \(msg)"
        case .storageError(let msg):
            return "Failed to store offline payment packet: \(msg)"
        }
    }
}

/// Local-only service for creating and queuing cryptographically signed offline payment packets.
///
/// Architectural Guarantees:
/// 1. **Completely Local & Offline**: This service NEVER invokes `UPIMeshAPIClient`, makes HTTP requests,
///    or relies on backend bridge connectivity. It functions entirely on-device in zero-connectivity environments.
/// 2. **Reuses Existing Cryptographic Primitives**: Reuses `PaymentInstruction.create(...)`,
///    canonical byte formatting, and `DeviceIdentityManager.signBase64(...)` (RSA-PSS with SHA-256).
/// 3. **Strict Invariant Validation**: Rejects non-finite, negative, or zero amounts. Enforces canonical 2-decimal scale.
/// 4. **Queued Status**: Newly created packets are stored strictly with status `.queued`. They are NEVER marked
///    settled locally; the backend ledger remains the authoritative arbiter of settlement upon eventual bridge ingestion.
/// 5. **Private Key Protection**: Private keys never leave the iOS Keychain. Packets contain only public metadata,
///    instruction payload, and the RSA-PSS digital signature.
public final class OfflinePaymentService: Sendable {

    /// Shared default singleton instance.
    public static let shared = OfflinePaymentService()

    private let identityManager: DeviceIdentityManager
    private let packetStore: OfflinePacketStore

    /// Initializes the service with specific identity and storage managers.
    ///
    /// Allows dependency injection for isolated unit testing.
    public init(
        identityManager: DeviceIdentityManager = .shared,
        packetStore: OfflinePacketStore = .shared
    ) {
        self.identityManager = identityManager
        self.packetStore = packetStore
    }

    /// Creates and locally stores a signed offline payment packet.
    ///
    /// - Parameters:
    ///   - fromAccount: The funding sender account identifier (e.g. "alice").
    ///   - toAccount: The receiving payee account identifier (e.g. "bob").
    ///   - amount: The payment amount as `Double`.
    ///   - memo: Optional user memo for display / tracking.
    /// - Returns: The newly created and locally queued `OfflinePaymentPacket`.
    /// - Throws: `OfflinePaymentServiceError` if validation, signing, or persistence fails.
    @discardableResult
    public func createAndQueueOfflinePayment(
        fromAccount: String,
        toAccount: String,
        amount: Double,
        memo: String? = nil
    ) throws -> OfflinePaymentPacket {
        // 1. Validate Amount
        guard !amount.isNaN, amount.isFinite else {
            throw OfflinePaymentServiceError.invalidAmount("Amount must be a finite numerical value")
        }
        guard amount > 0 else {
            throw OfflinePaymentServiceError.invalidAmount("Transfer amount must be strictly greater than zero")
        }

        // Convert Double to Decimal matching standard 2-decimal currency formatting
        let amountStr = String(format: "%.2f", amount)
        guard let decimalAmount = Decimal(string: amountStr), decimalAmount > 0 else {
            throw OfflinePaymentServiceError.invalidAmount("Amount could not be parsed to valid decimal currency")
        }

        return try createAndQueueOfflinePayment(
            fromAccount: fromAccount,
            toAccount: toAccount,
            amount: decimalAmount,
            memo: memo
        )
    }

    /// Creates and locally stores a signed offline payment packet accepting `Decimal` amount.
    ///
    /// - Parameters:
    ///   - fromAccount: The funding sender account identifier (e.g. "alice").
    ///   - toAccount: The receiving payee account identifier (e.g. "bob").
    ///   - amount: The payment amount as `Decimal`.
    ///   - memo: Optional user memo for display / tracking.
    /// - Returns: The newly created and locally queued `OfflinePaymentPacket`.
    /// - Throws: `OfflinePaymentServiceError` if validation, signing, or persistence fails.
    @discardableResult
    public func createAndQueueOfflinePayment(
        fromAccount: String,
        toAccount: String,
        amount: Decimal,
        memo: String? = nil
    ) throws -> OfflinePaymentPacket {
        let trimmedFrom = fromAccount.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTo = toAccount.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Account Invariant Validation
        guard !trimmedFrom.isEmpty else {
            throw OfflinePaymentServiceError.invalidAccounts("Sender account must not be blank")
        }
        guard !trimmedTo.isEmpty else {
            throw OfflinePaymentServiceError.invalidAccounts("Recipient account must not be blank")
        }
        guard trimmedFrom.caseInsensitiveCompare(trimmedTo) != .orderedSame else {
            throw OfflinePaymentServiceError.invalidAccounts("Sender and recipient accounts must be different")
        }

        // 2. Amount Invariant Validation
        guard !amount.isNaN, amount > 0 else {
            throw OfflinePaymentServiceError.invalidAmount("Transfer amount must be strictly greater than zero and finite")
        }

        // 3. Acquire Device Identity (Local Keychain Operation, Zero Network)
        let identity: DeviceIdentity
        do {
            identity = try identityManager.getOrCreateIdentity()
        } catch {
            throw OfflinePaymentServiceError.identityError(error.localizedDescription)
        }

        // 4. Construct Canonical PaymentInstruction
        let unsignedInstruction: PaymentInstruction
        do {
            unsignedInstruction = try PaymentInstruction.create(
                fromAccount: trimmedFrom,
                toAccount: trimmedTo,
                amount: amount
            )
        } catch {
            throw OfflinePaymentServiceError.invalidAmount(error.localizedDescription)
        }

        // 5. Cryptographically Sign Canonical Instruction Bytes via Keychain SecKey
        let canonicalBytes = unsignedInstruction.toCanonicalBytes()
        let signatureBase64: String
        do {
            signatureBase64 = try identityManager.signBase64(message: canonicalBytes)
        } catch {
            throw OfflinePaymentServiceError.signingError(error.localizedDescription)
        }

        // 6. Attach Signature to Instruction
        let signedInstruction: PaymentInstruction
        do {
            signedInstruction = try unsignedInstruction.withSignature(signatureBase64)
        } catch {
            throw OfflinePaymentServiceError.signingError("Failed to attach signature: \(error.localizedDescription)")
        }

        // 7. Assemble OfflinePaymentPacket (Status strictly QUEUED)
        let packet: OfflinePaymentPacket
        do {
            packet = try OfflinePaymentPacket(
                instruction: signedInstruction,
                deviceId: identity.deviceId,
                status: .queued
            )
        } catch {
            throw OfflinePaymentServiceError.signingError("Failed to construct packet: \(error.localizedDescription)")
        }

        // 8. Durably Persist Packet to Local Offline Packet Store
        do {
            try packetStore.save(packet)
        } catch {
            throw OfflinePaymentServiceError.storageError(error.localizedDescription)
        }

        return packet
    }

    /// Retrieves all locally queued offline payment packets.
    public func getQueuedPackets() -> [OfflinePaymentPacket] {
        packetStore.getPackets(withStatus: .queued)
    }

    /// Retrieves all stored offline payment packets.
    public func getAllPackets() -> [OfflinePaymentPacket] {
        packetStore.getAll()
    }
}
