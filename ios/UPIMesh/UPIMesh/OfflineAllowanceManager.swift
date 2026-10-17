import Foundation
import Security
import CryptoKit

/// Errors that can occur during offline allowance operations.
public enum OfflineAllowanceError: LocalizedError, Equatable {
    case noActiveAllowance
    case allowanceExpired(String)
    case insufficientAllowance(remaining: Decimal, requested: Decimal)
    case invalidAmount(String)
    case invalidAccount(String)
    case voucherSignatureInvalid(String)
    case untrustedBankKey(String)
    case bankKeyMismatch
    case deviceMismatch(String)
    case identityError(String)
    case signingError(String)
    case storageError(String)
    case apiError(String)

    public var errorDescription: String? {
        switch self {
        case .noActiveAllowance:
            return "No active offline allowance voucher is available on this device."
        case .allowanceExpired(let expiresAt):
            return "Offline allowance voucher expired at \(expiresAt). Cannot issue new offline spends."
        case .insufficientAllowance(let remaining, let requested):
            return "Requested spend (₹\(requested)) exceeds remaining allowance balance (₹\(remaining))."
        case .invalidAmount(let msg):
            return "Invalid allowance amount: \(msg)"
        case .invalidAccount(let msg):
            return "Invalid account: \(msg)"
        case .voucherSignatureInvalid(let msg):
            return "Bank voucher cryptographic signature verification failed: \(msg)"
        case .untrustedBankKey(let msg):
            return "Untrusted bank authority public key: \(msg)"
        case .bankKeyMismatch:
            return "Bank public key supplied in voucher does not match pinned bank authority key."
        case .deviceMismatch(let msg):
            return "Device binding mismatch: \(msg)"
        case .identityError(let msg):
            return "Device identity error: \(msg)"
        case .signingError(let msg):
            return "Failed to sign spend record: \(msg)"
        case .storageError(let msg):
            return "Storage operation failed: \(msg)"
        case .apiError(let msg):
            return "Bridge allowance API call failed: \(msg)"
        }
    }
}

/// Notification posted when the active offline allowance changes.
public extension Notification.Name {
    static let offlineAllowanceUpdated = Notification.Name("com.upimesh.offlineAllowanceUpdated")
}

/// Service managing the client-side lifecycle of pre-allocated offline spending allowances.
///
/// Under the Phase 2B architecture:
/// 1. Requests allowance issuance from the authoritative banking backend (`POST /api/allowance/issue`).
/// 2. Validates bank authority signatures against a trusted pinned public key.
/// 3. Locally enforces monotonic spending sequences, cumulative spending evidence, and remaining limits.
/// 4. Generates signed `OfflineSpendRecord` payloads matching the backend's deterministic canonical bytes.
/// 5. Durably tracks local allowance consumption without exposing private keys.
public final class OfflineAllowanceManager: @unchecked Sendable {

    public static let shared = OfflineAllowanceManager()

    private let lock = NSLock()
    private var cachedVoucher: OfflineAllowanceVoucher? = nil
    private var pinnedBankKey: String? = nil

    private var storageDirectory: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let dir = paths.first!.appendingPathComponent("UPIMesh", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var voucherFileURL: URL {
        storageDirectory.appendingPathComponent("active_allowance_voucher.json")
    }

    private var pinnedKeyFileURL: URL {
        storageDirectory.appendingPathComponent("pinned_bank_authority_key.txt")
    }

    public init() {
        self.pinnedBankKey = loadPinnedKeyInternal()
        self.cachedVoucher = loadVoucherInternal()
    }

    // MARK: - Bank Authority Public Key Pinning

    /// Pins the authoritative Bank Authority public key.
    /// Never blindly trust an arbitrary public key supplied inside an unauthenticated payload.
    public func pinBankAuthorityPublicKey(_ keyBase64: String) throws {
        lock.lock()
        defer { lock.unlock() }

        let trimmed = keyBase64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw OfflineAllowanceError.untrustedBankKey("Bank authority public key must not be blank")
        }
        guard Data(base64Encoded: trimmed) != nil else {
            throw OfflineAllowanceError.untrustedBankKey("Bank authority public key is not valid Base64")
        }

        self.pinnedBankKey = trimmed
        try trimmed.write(to: pinnedKeyFileURL, atomically: true, encoding: .utf8)
    }

    public func getPinnedBankAuthorityPublicKey() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return pinnedBankKey
    }

    private func loadPinnedKeyInternal() -> String? {
        if let str = try? String(contentsOf: pinnedKeyFileURL, encoding: .utf8) {
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    // MARK: - Active Allowance Voucher Management

    public func getActiveVoucher() -> OfflineAllowanceVoucher? {
        lock.lock()
        defer { lock.unlock() }
        return cachedVoucher
    }

    public func saveActiveVoucher(_ voucher: OfflineAllowanceVoucher) throws {
        lock.lock()
        defer { lock.unlock() }

        self.cachedVoucher = voucher
        let data = try JSONEncoder().encode(voucher)
        try data.write(to: voucherFileURL, options: .atomic)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .offlineAllowanceUpdated, object: voucher)
        }
    }

    public func clearActiveVoucher() throws {
        lock.lock()
        defer { lock.unlock() }

        self.cachedVoucher = nil
        try? FileManager.default.removeItem(at: voucherFileURL)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .offlineAllowanceUpdated, object: nil)
        }
    }

    private func loadVoucherInternal() -> OfflineAllowanceVoucher? {
        guard let data = try? Data(contentsOf: voucherFileURL) else {
            return nil
        }
        return try? JSONDecoder().decode(OfflineAllowanceVoucher.self, from: data)
    }

    // MARK: - Allowance Spending Workflow

    /// Creates and queues an allowance-backed offline payment packet.
    ///
    /// - Parameters:
    ///   - toAccount: The creditor receiving account (e.g. "bob").
    ///   - amount: The payment amount as `Decimal`.
    ///   - memo: Optional user memo.
    /// - Returns: Newly constructed `OfflinePaymentPacket` containing the embedded `OfflineSpendRecord`.
    @discardableResult
    public func createAndQueueAllowanceSpend(
        toAccount: String,
        amount: Decimal,
        memo: String? = nil,
        packetStore: OfflinePacketStore = .shared,
        identityManager: DeviceIdentityManager = .shared
    ) throws -> OfflinePaymentPacket {
        lock.lock()
        defer { lock.unlock() }

        guard var voucher = cachedVoucher else {
            throw OfflineAllowanceError.noActiveAllowance
        }

        // 1. Enforce Expiry
        if voucher.isExpired() {
            throw OfflineAllowanceError.allowanceExpired(voucher.expiresAt)
        }

        // 2. Validate Amount
        guard amount > 0, !amount.isNaN else {
            throw OfflineAllowanceError.invalidAmount("Transfer amount must be strictly greater than zero")
        }

        // 3. Enforce Allowance Limit
        let remaining = voucher.remainingAmount
        guard amount <= remaining else {
            throw OfflineAllowanceError.insufficientAllowance(remaining: remaining, requested: amount)
        }

        let cleanTo = toAccount.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanTo.isEmpty else {
            throw OfflineAllowanceError.invalidAccount("Recipient account must not be blank")
        }
        guard cleanTo.caseInsensitiveCompare(voucher.accountId) != .orderedSame else {
            throw OfflineAllowanceError.invalidAccount("Sender and recipient accounts cannot be identical")
        }

        // 4. Acquire Signing Device Identity
        let identity: DeviceIdentity
        do {
            identity = try identityManager.getOrCreateIdentity()
        } catch {
            throw OfflineAllowanceError.identityError(error.localizedDescription)
        }

        guard identity.deviceId == voucher.deviceId else {
            throw OfflineAllowanceError.deviceMismatch("Voucher is bound to device \(voucher.deviceId), but local device ID is \(identity.deviceId)")
        }

        // 5. Advance Monotonic Spending Sequence & Cumulative Evidence
        let nextSeq = voucher.lastSequenceNumber + 1
        let nextCumulative = voucher.spentAmount + amount
        let paymentId = UUID().uuidString.lowercased()
        let nowInstant = PaymentInstant.now()

        // 6. Build Canonical Spend Bytes & Sign via Keychain SecKey
        let canonicalSpendBytes = OfflineSpendRecord.buildCanonicalSpendBytes(
            allowanceId: voucher.allowanceId,
            paymentId: paymentId,
            payerAccountId: voucher.accountId,
            payerDeviceId: identity.deviceId,
            recipientAccountId: cleanTo,
            amount: amount,
            currency: voucher.currency,
            sequenceNumber: nextSeq,
            cumulativeSpentAmount: nextCumulative,
            createdAt: nowInstant.isoString,
            voucherSignature: voucher.voucherSignature,
            protocolVersion: voucher.protocolVersion
        )

        let payerSig: String
        do {
            payerSig = try identityManager.signBase64(message: canonicalSpendBytes)
        } catch {
            throw OfflineAllowanceError.signingError(error.localizedDescription)
        }

        let spendRecord = OfflineSpendRecord(
            allowanceId: voucher.allowanceId,
            paymentId: paymentId,
            payerAccountId: voucher.accountId,
            payerDeviceId: identity.deviceId,
            recipientAccountId: cleanTo,
            amount: amount,
            currency: voucher.currency,
            sequenceNumber: nextSeq,
            cumulativeSpentAmount: nextCumulative,
            createdAt: nowInstant.isoString,
            voucherSignature: voucher.voucherSignature,
            payerSignature: payerSig,
            protocolVersion: voucher.protocolVersion
        )

        // 7. Create Embedded Canonical PaymentInstruction for transport compatibility
        let unsignedInstruction: PaymentInstruction
        do {
            unsignedInstruction = try PaymentInstruction(
                paymentId: paymentId,
                fromAccount: voucher.accountId,
                toAccount: cleanTo,
                amount: amount,
                createdAt: nowInstant,
                nonce: UUID().uuidString.lowercased(),
                signature: nil
            )
        } catch {
            throw OfflineAllowanceError.invalidAmount(error.localizedDescription)
        }

        let signedInstruction: PaymentInstruction
        do {
            let legacySig = try identityManager.signBase64(message: unsignedInstruction.toCanonicalBytes())
            signedInstruction = try unsignedInstruction.withSignature(legacySig)
        } catch {
            throw OfflineAllowanceError.signingError(error.localizedDescription)
        }

        // 8. Assemble OfflinePaymentPacket with embedded allowance spend
        let packet: OfflinePaymentPacket
        do {
            packet = try OfflinePaymentPacket(
                instruction: signedInstruction,
                deviceId: identity.deviceId,
                status: .queued,
                allowanceSpend: spendRecord
            )
        } catch {
            throw OfflineAllowanceError.signingError("Packet assembly failed: \(error.localizedDescription)")
        }

        // 9. Durably Persist Updated Voucher Counters & Packet
        voucher.spentAmount = nextCumulative
        voucher.lastSequenceNumber = nextSeq
        self.cachedVoucher = voucher

        do {
            let vData = try JSONEncoder().encode(voucher)
            try vData.write(to: voucherFileURL, options: .atomic)
        } catch {
            throw OfflineAllowanceError.storageError("Failed to update voucher state on disk: \(error.localizedDescription)")
        }

        do {
            try packetStore.save(packet)
        } catch {
            throw OfflineAllowanceError.storageError("Failed to store payment packet: \(error.localizedDescription)")
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .offlineAllowanceUpdated, object: voucher)
        }

        return packet
    }
}
