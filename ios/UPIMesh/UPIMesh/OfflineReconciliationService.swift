import Foundation

/// Clear, typed outcome of an explicit offline reconciliation attempt.
public enum ReconciliationOutcome: Sendable, Equatable {
    /// Authoritative backend settlement confirmed on ledger (status changed to SETTLED).
    case settled(paymentId: String, result: MeshPaymentResultDTO)

    /// Definitive terminal rejection confirmed by backend (status changed to FAILED with reason).
    case rejected(paymentId: String, reason: String)

    /// Ambiguous outcome (network timeout, lost connection, 5xx error, or unconfirmed duplicate response).
    /// The record remains in a retryable state (SETTLING).
    case retryable(paymentId: String, reason: String)

    /// The packet cannot be submitted because its state is ineligible or another attempt is already in-flight.
    case invalidState(paymentId: String, currentStatus: ReceivedReconciliationStatus, reason: String)
}

/// Service responsible for reconciling received offline payment packets with the authoritative backend bridge.
///
/// Security & Trust Constraints:
/// - Submits the original signed instruction and the original sender's device ID from the packet.
/// - Never passes the receiver's device ID.
/// - Never re-signs or alters the payment instruction.
/// - Enforces that received packets are NOT marked SETTLED until the backend bridge authoritatively settles them.
/// - Requires explicit invocation; does NOT perform automated background submissions or silent retries.
/// - Prevents concurrent reconciliation attempts for the same payment ID.
public final class OfflineReconciliationService: @unchecked Sendable {

    /// Shared singleton instance for production iOS use.
    public static let shared = OfflineReconciliationService()

    private let packetStore: ReceivedPacketStore
    private let apiClient: MeshPaymentSubmitting
    private let lock = NSLock()
    private var inFlightPaymentIds = Set<String>()

    public init(
        packetStore: ReceivedPacketStore = .shared,
        apiClient: MeshPaymentSubmitting = UPIMeshAPIClient.shared
    ) {
        self.packetStore = packetStore
        self.apiClient = apiClient
    }

    private func registerInFlight(paymentId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if inFlightPaymentIds.contains(paymentId) {
            return false
        }
        inFlightPaymentIds.insert(paymentId)
        return true
    }

    private func unregisterInFlight(paymentId: String) {
        lock.lock()
        defer { lock.unlock() }
        inFlightPaymentIds.remove(paymentId)
    }

    /// Explicitly reconciles a single received packet by payment ID with the backend bridge.
    ///
    /// - Parameter paymentId: The unique payment ID of the received packet.
    /// - Returns: A `ReconciliationOutcome` indicating settled, rejected, retryable, or invalidState.
    public func reconcile(paymentId: String) async -> ReconciliationOutcome {
        let cleanId = paymentId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty else {
            return .invalidState(paymentId: "", currentStatus: .received, reason: "Payment ID must not be blank")
        }

        // 1. Prevent concurrent duplicate attempts on the same payment ID
        guard registerInFlight(paymentId: cleanId) else {
            return .invalidState(
                paymentId: cleanId,
                currentStatus: .settling,
                reason: "Reconciliation is already in progress for payment ID '\(cleanId)'"
            )
        }

        defer {
            unregisterInFlight(paymentId: cleanId)
        }

        // 2. Retrieve record from store
        guard let record = packetStore.get(paymentId: cleanId) else {
            return .invalidState(
                paymentId: cleanId,
                currentStatus: .received,
                reason: "Received packet with payment ID '\(cleanId)' was not found in ReceivedPacketStore"
            )
        }

        // 3. State validation: allow only RECEIVED or safely recoverable SETTLING
        guard record.reconciliationStatus == .received || record.reconciliationStatus == .settling else {
            return .invalidState(
                paymentId: cleanId,
                currentStatus: record.reconciliationStatus,
                reason: "Record with payment ID '\(cleanId)' has status '\(record.reconciliationStatus.rawValue)' and cannot be reconciled (only RECEIVED or SETTLING allowed)"
            )
        }

        let instruction = record.packet.instruction
        let senderDeviceId = record.packet.deviceId

        // 4. If record is already in SETTLING, query authoritative status first to see if previous attempt committed
        if record.reconciliationStatus == .settling {
            if let statusResult = try? await apiClient.queryPaymentStatus(paymentId: cleanId),
               statusResult.found,
               statusResult.status.uppercased() == "SETTLED" {
                let matchesSender = statusResult.fromAccount?.lowercased() == instruction.fromAccount.lowercased()
                let expectedAmount = NSDecimalNumber(decimal: instruction.amount).doubleValue
                let matchesAmount = statusResult.amount == nil || abs(statusResult.amount! - expectedAmount) < 0.01
                if matchesSender && matchesAmount {
                    do {
                        try packetStore.updateStatus(paymentId: cleanId, status: .settled)
                    } catch {}
                    let resultDTO = MeshPaymentResultDTO(
                        success: true,
                        paymentId: cleanId,
                        packetId: UUID().uuidString,
                        fromAccount: instruction.fromAccount,
                        toAccount: instruction.toAccount,
                        amount: expectedAmount,
                        roundsRun: 1,
                        hopsTaken: 1,
                        remainingTtl: 3,
                        routeTrace: [senderDeviceId, "bridge"],
                        encryptedKeySnippet: nil,
                        ivHex: nil,
                        ciphertextSnippet: nil,
                        status: "SETTLED",
                        message: statusResult.message
                    )
                    return .settled(paymentId: cleanId, result: resultDTO)
                }
            }
        }

        // 5. Persist SETTLING before making the request
        do {
            try packetStore.updateStatus(paymentId: cleanId, status: .settling)
        } catch {
            return .retryable(
                paymentId: cleanId,
                reason: "Failed to persist SETTLING status to disk: \(error.localizedDescription)"
            )
        }

        // 6. Execute submission via API client
        if let spend = record.packet.allowanceSpend {
            do {
                let spendResult = try await apiClient.submitAllowanceSpend(record: spend)
                if spendResult.status.uppercased() == "SETTLED" {
                    do {
                        try packetStore.updateStatus(paymentId: cleanId, status: .settled)
                    } catch {}
                    let resultDTO = MeshPaymentResultDTO(
                        success: true,
                        paymentId: cleanId,
                        packetId: UUID().uuidString,
                        fromAccount: spend.payerAccountId,
                        toAccount: spend.recipientAccountId,
                        amount: spend.amountDouble,
                        roundsRun: 1,
                        hopsTaken: 1,
                        remainingTtl: 3,
                        routeTrace: [senderDeviceId, "system-escrow", "bridge"],
                        encryptedKeySnippet: nil,
                        ivHex: nil,
                        ciphertextSnippet: nil,
                        status: "SETTLED",
                        message: "Allowance spend settled successfully against escrow"
                    )
                    return .settled(paymentId: cleanId, result: resultDTO)
                } else {
                    return .retryable(
                        paymentId: cleanId,
                        reason: "Allowance spend returned non-settled status: \(spendResult.status)"
                    )
                }
            } catch let apiError as APIError {
                return await handleAPIError(apiError, paymentId: cleanId, instruction: instruction, deviceId: senderDeviceId)
            } catch {
                return .retryable(
                    paymentId: cleanId,
                    reason: "Allowance spend submission failed with error: \(error.localizedDescription)"
                )
            }
        }

        do {
            let result = try await apiClient.submitSignedMeshPayment(
                instruction: instruction,
                deviceId: senderDeviceId
            )

            // Confirm definitive success from authoritative backend
            if result.success && result.status.uppercased() == "SETTLED" {
                do {
                    try packetStore.updateStatus(paymentId: cleanId, status: .settled)
                } catch {
                    // Disk persistence issue, but backend definitively settled
                }
                return .settled(paymentId: cleanId, result: result)
            } else {
                // Ambiguous or non-settled response
                return .retryable(
                    paymentId: cleanId,
                    reason: "Backend returned non-settled status: \(result.status), message: \(result.message)"
                )
            }
        } catch let apiError as APIError {
            return await handleAPIError(apiError, paymentId: cleanId, instruction: instruction, deviceId: senderDeviceId)
        } catch {
            // General network / unexpected error: preserve retryable SETTLING state
            return .retryable(
                paymentId: cleanId,
                reason: "Submission failed with unexpected error: \(error.localizedDescription)"
            )
        }
    }

    private func handleAPIError(
        _ error: APIError,
        paymentId: String,
        instruction: PaymentInstruction,
        deviceId: String
    ) async -> ReconciliationOutcome {
        switch error {
        case .paymentFailed(let message), .allowanceError(let message):
            if isDefinitiveTerminalRejection(message: message) {
                // Definitive terminal rejection (e.g. insufficient funds, expired, unauthorized, conflicting)
                do {
                    try packetStore.updateStatus(paymentId: paymentId, status: .failed, failureReason: message)
                } catch {}
                return .rejected(paymentId: paymentId, reason: message)
            } else if isDuplicateOrAmbiguous(message: message) {
                // Check authoritative status on backend before treating as permanently ambiguous
                if let statusResult = try? await apiClient.queryPaymentStatus(paymentId: paymentId),
                   statusResult.found,
                   statusResult.status.uppercased() == "SETTLED" {
                    let matchesSender = statusResult.fromAccount?.lowercased() == instruction.fromAccount.lowercased()
                    let expectedAmount = NSDecimalNumber(decimal: instruction.amount).doubleValue
                    let matchesAmount = statusResult.amount == nil || abs(statusResult.amount! - expectedAmount) < 0.01
                    if matchesSender && matchesAmount {
                        do {
                            try packetStore.updateStatus(paymentId: paymentId, status: .settled)
                        } catch {}
                        let resultDTO = MeshPaymentResultDTO(
                            success: true,
                            paymentId: paymentId,
                            packetId: UUID().uuidString,
                            fromAccount: instruction.fromAccount,
                            toAccount: instruction.toAccount,
                            amount: expectedAmount,
                            roundsRun: 1,
                            hopsTaken: 1,
                            remainingTtl: 3,
                            routeTrace: [deviceId, "bridge"],
                            encryptedKeySnippet: nil,
                            ivHex: nil,
                            ciphertextSnippet: nil,
                            status: "SETTLED",
                            message: statusResult.message
                        )
                        return .settled(paymentId: paymentId, result: resultDTO)
                    }
                }
                return .retryable(
                    paymentId: paymentId,
                    reason: "Ambiguous duplicate response from backend: '\(message)'. Ledger settlement cannot be assumed without verification; preserved in retryable state."
                )
            } else {
                // Ambiguous payment error
                return .retryable(
                    paymentId: paymentId,
                    reason: "Ambiguous rejection from bridge: \(message)"
                )
            }

        case .networkError(let details):
            // Timeout, lost response, DNS or connection reset: preserve retryable state
            return .retryable(
                paymentId: paymentId,
                reason: "Network connection failure: \(details)"
            )

        case .invalidResponse(let code):
            // HTTP 5xx or unexpected status
            return .retryable(
                paymentId: paymentId,
                reason: "Bridge returned HTTP status: \(code)"
            )

        case .decodingError(let details):
            return .retryable(
                paymentId: paymentId,
                reason: "Failed to decode bridge response: \(details)"
            )

        case .invalidParameters(let details):
            return .retryable(
                paymentId: paymentId,
                reason: "Invalid request parameters: \(details)"
            )

        case .invalidURL, .registrationFailed, .authorizationFailed, .encodingError:
            return .retryable(
                paymentId: paymentId,
                reason: error.localizedDescription
            )
        }
    }

    /// Evaluates whether a backend error message represents a definitive terminal rejection.
    private func isDefinitiveTerminalRejection(message: String) -> Bool {
        let terminalKeywords = [
            "insufficient funds",
            "expired",
            "timestamp is too far in the future",
            "unregistered device",
            "invalid digital signature",
            "is not authorized to debit",
            "sender and receiver must be different",
            "amount must be greater than zero",
            "digital signature is missing",
            "no account:",
            "conflicting payment instruction",
            "pending account-owner consent",
            "account-owner consent",
            "has been revoked",
            "fingerprint mismatch",
            "exceeds authorized spending limit",
            "blocked",
            "exceeds remaining allowance",
            "allowance is not active",
            "allowance is expired",
            "voucher signature",
            "payer signature",
            "sequence fork",
            "out of order sequence",
            "tampered"
        ]
        let lower = message.lowercased()
        return terminalKeywords.contains { lower.contains($0) }
    }

    /// Evaluates whether a backend error message represents an ambiguous duplicate condition.
    private func isDuplicateOrAmbiguous(message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("duplicate") || lower.contains("already settled") || lower.contains("replayed")
    }
}
