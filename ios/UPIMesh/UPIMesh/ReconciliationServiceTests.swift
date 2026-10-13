import Foundation
import Security
import CryptoKit

/// Comprehensive test suite validating OfflineReconciliationService behavior,
/// lifecycle state transitions, concurrency guards, payload invariance, and idempotency handling.
public final class ReconciliationServiceTests {

    public static func runAllTests() async throws {
        print("=== Running ReconciliationServiceTests (14 tests) ===")
        try await testValidReceivedPacketSubmittedWithOriginalSignerDeviceId()
        try await testSuccessfulResultTransitionsToSettled()
        try await testDefinitiveInsufficientFundsRejectionTransitionsToFailed()
        try await testNetworkTimeoutLeavesRetryableState()
        try await testDuplicateAmbiguousResponseNotMarkedSettled()
        try await testInvalidStatusCannotBeSubmitted()
        try await testConcurrentDuplicateAttemptsPrevented()
        try await testOriginalSignedInstructionAndSignatureUnchanged()

        // Stage 6.4B.3 UI Reconciliation Workflow Tests
        try await testUIReconciliationSuccessOutcomeAndState()
        try await testUIDefinitiveRejectionOutcomeAndReason()
        try await testUINetworkTimeoutLeavesRetryableForUIRetry()
        try await testUIAmbiguousDuplicateLeavesRetryable()
        try await testUIRetrySettlingPacketAllowed()
        try await testUIInFlightConcurrencyGuard()
        print("=== ReconciliationServiceTests: All 14 passed cleanly! ===")
    }

    private static func assert(_ condition: Bool, _ message: String) throws {
        if !condition {
            print("  ✗ FAIL: \(message)")
            throw NSError(domain: "ReconciliationServiceTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private static func createSampleSignedPacket(
        paymentId: String = UUID().uuidString.lowercased(),
        fromAccount: String = "alice",
        toAccount: String = "bob",
        amount: Decimal = 50.00,
        deviceId: String = "alice-hardware-keychain-device"
    ) throws -> (packet: OfflinePaymentPacket, keyBase64: String) {
        let keyAttrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048
        ]
        var error: Unmanaged<CFError>?
        guard let priv = SecKeyCreateRandomKey(keyAttrs as CFDictionary, &error),
              let pub = SecKeyCopyPublicKey(priv),
              let pkcs1 = SecKeyCopyExternalRepresentation(pub, &error) as Data? else {
            throw NSError(domain: "KeyGen", code: 1, userInfo: nil)
        }

        let header = Data([
            0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09,
            0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01,
            0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0f, 0x00
        ])
        var x509 = Data()
        x509.append(header)
        x509.append(pkcs1)
        let keyBase64 = x509.base64EncodedString()

        let instruction = try PaymentInstruction(
            paymentId: paymentId,
            fromAccount: fromAccount,
            toAccount: toAccount,
            amount: amount,
            createdAt: PaymentInstant.now(),
            nonce: UUID().uuidString.lowercased()
        )

        let canonical = instruction.toCanonicalBytes()
        guard let sigData = SecKeyCreateSignature(
            priv,
            .rsaSignatureMessagePSSSHA256,
            canonical as CFData,
            &error
        ) as Data? else {
            throw NSError(domain: "Signing", code: 1, userInfo: nil)
        }

        let signedInstruction = try instruction.withSignature(sigData.base64EncodedString())
        let packet = try OfflinePaymentPacket(
            instruction: signedInstruction,
            deviceId: deviceId,
            status: .received
        )
        return (packet, keyBase64)
    }

    private static func sampleSettledResult(paymentId: String) -> MeshPaymentResultDTO {
        MeshPaymentResultDTO(
            success: true,
            paymentId: paymentId,
            packetId: UUID().uuidString,
            fromAccount: "alice",
            toAccount: "bob",
            amount: 50.00,
            roundsRun: 2,
            hopsTaken: 2,
            remainingTtl: 3,
            routeTrace: ["alice", "bridge"],
            encryptedKeySnippet: nil,
            ivHex: nil,
            ciphertextSnippet: nil,
            status: "SETTLED",
            message: "Payment instruction verified and settled on ledger"
        )
    }

    // MARK: - Test Doubles

    private final class MockMeshPaymentSubmitter: MeshPaymentSubmitting, @unchecked Sendable {
        var resultToReturn: MeshPaymentResultDTO?
        var errorToThrow: Error?
        var delayNanoseconds: UInt64?

        var lastInstruction: PaymentInstruction?
        var lastDeviceId: String?
        var callCount = 0
        private let lock = NSLock()

        private func syncRecordCall(instruction: PaymentInstruction, deviceId: String) -> (Error?, MeshPaymentResultDTO?, UInt64?) {
            lock.lock()
            defer { lock.unlock() }
            callCount += 1
            lastInstruction = instruction
            lastDeviceId = deviceId
            return (errorToThrow, resultToReturn, delayNanoseconds)
        }

        func submitSignedMeshPayment(
            instruction: PaymentInstruction,
            deviceId: String
        ) async throws -> MeshPaymentResultDTO {
            let (err, res, delay) = syncRecordCall(instruction: instruction, deviceId: deviceId)

            if let delay = delay {
                try await Task.sleep(nanoseconds: delay)
            }

            if let err = err {
                throw err
            }
            if let res = res {
                return res
            }
            throw APIError.invalidResponse(500)
        }
    }

    // MARK: - Test 1: Original Signer Device ID Submission
    public static func testValidReceivedPacketSubmittedWithOriginalSignerDeviceId() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = ReceivedPacketStore(fileURL: tempDir.appendingPathComponent("test1.json"))
        let originalSignerDeviceId = "alice-unique-phone-uuid"
        let (packet, _) = try createSampleSignedPacket(deviceId: originalSignerDeviceId)
        let record = try ReceivedPacketRecord(
            packet: packet,
            receivedFromPeer: "Bob-iPhone",
            isSignatureMathematicallyValid: true,
            trustStatusNote: "Test 1 Note"
        )
        try store.save(record)

        let mock = MockMeshPaymentSubmitter()
        mock.resultToReturn = sampleSettledResult(paymentId: packet.paymentId)

        let service = OfflineReconciliationService(packetStore: store, apiClient: mock)
        let outcome = await service.reconcile(paymentId: packet.paymentId)

        // Must submit Alice's original deviceId, NOT Bob's receiver ID
        try assert(mock.lastDeviceId == originalSignerDeviceId, "Must submit original signer's device ID")
        try assert(mock.lastInstruction?.paymentId == packet.paymentId, "Payment ID must match original")
        try assert(mock.lastInstruction?.signature == packet.signature, "Signature must match original")
        try assert(mock.callCount == 1, "API submitter must be called exactly once")

        if case .settled(let pid, _) = outcome {
            try assert(pid == packet.paymentId, "Outcome payment ID must match")
        } else {
            try assert(false, "Outcome must be .settled")
        }

        print("  ✓ PASS: testValidReceivedPacketSubmittedWithOriginalSignerDeviceId")
    }

    // MARK: - Test 2: Successful Result Transitions to SETTLED
    public static func testSuccessfulResultTransitionsToSettled() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = ReceivedPacketStore(fileURL: tempDir.appendingPathComponent("test2.json"))
        let (packet, _) = try createSampleSignedPacket()
        try store.save(ReceivedPacketRecord(
            packet: packet,
            receivedFromPeer: "Peer",
            isSignatureMathematicallyValid: true,
            trustStatusNote: "Note"
        ))

        let mock = MockMeshPaymentSubmitter()
        mock.resultToReturn = sampleSettledResult(paymentId: packet.paymentId)

        let service = OfflineReconciliationService(packetStore: store, apiClient: mock)
        let outcome = await service.reconcile(paymentId: packet.paymentId)

        guard case .settled = outcome else {
            try assert(false, "Outcome must be .settled")
            return
        }

        // Store must be durably updated to SETTLED
        let updatedRecord = store.get(paymentId: packet.paymentId)
        try assert(updatedRecord?.reconciliationStatus == .settled, "Store must reflect SETTLED")
        try assert(updatedRecord?.failureReason == nil, "failureReason must be nil")
        try assert(updatedRecord?.updatedAt != nil, "updatedAt must be recorded")

        print("  ✓ PASS: testSuccessfulResultTransitionsToSettled")
    }

    // MARK: - Test 3: Definitive Insufficient Funds Rejection Transitions to FAILED
    public static func testDefinitiveInsufficientFundsRejectionTransitionsToFailed() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = ReceivedPacketStore(fileURL: tempDir.appendingPathComponent("test3.json"))
        let (packet, _) = try createSampleSignedPacket()
        try store.save(ReceivedPacketRecord(
            packet: packet,
            receivedFromPeer: "Peer",
            isSignatureMathematicallyValid: true,
            trustStatusNote: "Note"
        ))

        let mock = MockMeshPaymentSubmitter()
        mock.errorToThrow = APIError.paymentFailed("Insufficient funds on debtor account alice")

        let service = OfflineReconciliationService(packetStore: store, apiClient: mock)
        let outcome = await service.reconcile(paymentId: packet.paymentId)

        guard case .rejected(let pid, let reason) = outcome else {
            try assert(false, "Outcome must be .rejected")
            return
        }
        try assert(pid == packet.paymentId, "Rejected payment ID must match")
        try assert(reason.contains("Insufficient funds"), "Rejection reason must contain 'Insufficient funds'")

        // Store must be durably updated to FAILED
        let updatedRecord = store.get(paymentId: packet.paymentId)
        try assert(updatedRecord?.reconciliationStatus == .failed, "Store must reflect FAILED")
        try assert(updatedRecord?.failureReason?.contains("Insufficient funds") == true, "failureReason must be persisted")

        print("  ✓ PASS: testDefinitiveInsufficientFundsRejectionTransitionsToFailed")
    }

    // MARK: - Test 4: Network Timeout Leaves Retryable State
    public static func testNetworkTimeoutLeavesRetryableState() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = ReceivedPacketStore(fileURL: tempDir.appendingPathComponent("test4.json"))
        let (packet, _) = try createSampleSignedPacket()
        try store.save(ReceivedPacketRecord(
            packet: packet,
            receivedFromPeer: "Peer",
            isSignatureMathematicallyValid: true,
            trustStatusNote: "Note"
        ))

        let mock = MockMeshPaymentSubmitter()
        mock.errorToThrow = APIError.networkError("The request timed out (NSURLErrorTimedOut).")

        let service = OfflineReconciliationService(packetStore: store, apiClient: mock)
        let outcome = await service.reconcile(paymentId: packet.paymentId)

        guard case .retryable(let pid, let reason) = outcome else {
            try assert(false, "Outcome must be .retryable on network timeout")
            return
        }
        try assert(pid == packet.paymentId, "Payment ID must match")
        try assert(reason.contains("Network connection failure"), "Reason must cite connection failure")

        // Record must NOT be marked SETTLED or FAILED. It remains in retryable SETTLING state.
        let storedRecord = store.get(paymentId: packet.paymentId)
        try assert(storedRecord?.reconciliationStatus == .settling, "Record must remain in retryable SETTLING state")
        try assert(storedRecord?.reconciliationStatus != .settled, "Record must NOT be marked SETTLED")
        try assert(storedRecord?.reconciliationStatus != .failed, "Record must NOT be marked FAILED")

        print("  ✓ PASS: testNetworkTimeoutLeavesRetryableState")
    }

    // MARK: - Test 5: Duplicate / Ambiguous Response Not Marked Settled
    public static func testDuplicateAmbiguousResponseNotMarkedSettled() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = ReceivedPacketStore(fileURL: tempDir.appendingPathComponent("test5.json"))
        let (packet, _) = try createSampleSignedPacket()
        try store.save(ReceivedPacketRecord(
            packet: packet,
            receivedFromPeer: "Peer",
            isSignatureMathematicallyValid: true,
            trustStatusNote: "Note"
        ))

        // Backend reports duplicate paymentId
        let mock = MockMeshPaymentSubmitter()
        mock.errorToThrow = APIError.paymentFailed("Duplicate payment rejected (paymentId already settled): \(packet.paymentId)")

        let service = OfflineReconciliationService(packetStore: store, apiClient: mock)
        let outcome = await service.reconcile(paymentId: packet.paymentId)

        guard case .retryable(let pid, let reason) = outcome else {
            try assert(false, "Ambiguous duplicate response must yield .retryable outcome, not assumed success")
            return
        }
        try assert(pid == packet.paymentId, "Payment ID must match")
        try assert(reason.contains("Ambiguous duplicate response"), "Reason must explain duplicate ambiguity")

        // Crucial safety invariant: Must NEVER mark SETTLED merely because of an HTTP 400 duplicate error
        let storedRecord = store.get(paymentId: packet.paymentId)
        try assert(storedRecord?.reconciliationStatus != .settled, "Record must NOT be assumed settled without authoritative proof")
        try assert(storedRecord?.reconciliationStatus != .failed, "Record must NOT be marked FAILED on ambiguous duplicate")
        try assert(storedRecord?.reconciliationStatus == .settling, "Record must remain in retryable SETTLING state")

        print("  ✓ PASS: testDuplicateAmbiguousResponseNotMarkedSettled")
    }

    // MARK: - Test 6: Invalid Status Cannot Be Submitted
    public static func testInvalidStatusCannotBeSubmitted() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = ReceivedPacketStore(fileURL: tempDir.appendingPathComponent("test6.json"))
        let (packet1, _) = try createSampleSignedPacket()
        let (packet2, _) = try createSampleSignedPacket()

        try store.save(ReceivedPacketRecord(
            packet: packet1,
            receivedFromPeer: "Peer",
            isSignatureMathematicallyValid: true,
            trustStatusNote: "Note 1"
        ))
        try store.save(ReceivedPacketRecord(
            packet: packet2,
            receivedFromPeer: "Peer",
            isSignatureMathematicallyValid: true,
            trustStatusNote: "Note 2"
        ))

        // Pre-advance packet1 to SETTLED and packet2 to FAILED
        _ = try store.updateStatus(paymentId: packet1.paymentId, status: .settled)
        _ = try store.updateStatus(paymentId: packet2.paymentId, status: .failed, failureReason: "Already failed")

        let mock = MockMeshPaymentSubmitter()
        let service = OfflineReconciliationService(packetStore: store, apiClient: mock)

        // Attempting to reconcile already SETTLED packet
        let outcome1 = await service.reconcile(paymentId: packet1.paymentId)
        if case .invalidState(let pid, let status, _) = outcome1 {
            try assert(pid == packet1.paymentId, "Payment ID must match")
            try assert(status == .settled, "Reported status must be SETTLED")
        } else {
            try assert(false, "Reconciling SETTLED record must return .invalidState")
        }

        // Attempting to reconcile already FAILED packet
        let outcome2 = await service.reconcile(paymentId: packet2.paymentId)
        if case .invalidState(let pid, let status, _) = outcome2 {
            try assert(pid == packet2.paymentId, "Payment ID must match")
            try assert(status == .failed, "Reported status must be FAILED")
        } else {
            try assert(false, "Reconciling FAILED record must return .invalidState")
        }

        try assert(mock.callCount == 0, "Submitter must never be called for invalid state records")
        print("  ✓ PASS: testInvalidStatusCannotBeSubmitted")
    }

    // MARK: - Test 7: Concurrent Duplicate Attempts Prevented
    public static func testConcurrentDuplicateAttemptsPrevented() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = ReceivedPacketStore(fileURL: tempDir.appendingPathComponent("test7.json"))
        let (packet, _) = try createSampleSignedPacket()
        try store.save(ReceivedPacketRecord(
            packet: packet,
            receivedFromPeer: "Peer",
            isSignatureMathematicallyValid: true,
            trustStatusNote: "Note"
        ))

        let mock = MockMeshPaymentSubmitter()
        // Delay response by 200 milliseconds to allow concurrency race
        mock.delayNanoseconds = 200_000_000
        mock.resultToReturn = sampleSettledResult(paymentId: packet.paymentId)

        let service = OfflineReconciliationService(packetStore: store, apiClient: mock)

        // Launch task 1
        async let task1 = service.reconcile(paymentId: packet.paymentId)

        // Wait a tiny fraction (15ms) to ensure task1 acquired the lock and registered in-flight
        try await Task.sleep(nanoseconds: 15_000_000)

        // Launch task 2 immediately on the exact same payment ID
        let outcome2 = await service.reconcile(paymentId: packet.paymentId)
        let outcome1 = await task1

        // Task 2 must be rejected with invalidState due to in-flight concurrency
        if case .invalidState(let pid, _, let reason) = outcome2 {
            try assert(pid == packet.paymentId, "Payment ID must match")
            try assert(reason.contains("already in progress"), "Reason must cite in-progress concurrency")
        } else {
            try assert(false, "Concurrent second attempt must be rejected with invalidState")
        }

        // Task 1 must complete successfully
        guard case .settled = outcome1 else {
            try assert(false, "First task must settle cleanly")
            return
        }

        try assert(mock.callCount == 1, "API submitter must only be invoked once despite concurrent calls")
        print("  ✓ PASS: testConcurrentDuplicateAttemptsPrevented")
    }

    // MARK: - Test 8: Original Signed Instruction & Signature Unchanged
    public static func testOriginalSignedInstructionAndSignatureUnchanged() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = ReceivedPacketStore(fileURL: tempDir.appendingPathComponent("test8.json"))
        let (packet, keyBase64) = try createSampleSignedPacket()
        try store.save(ReceivedPacketRecord(
            packet: packet,
            receivedFromPeer: "Peer",
            isSignatureMathematicallyValid: true,
            trustStatusNote: "Note"
        ))

        // Record initial attributes
        let origSignature = packet.signature
        let origCanonicalBytes = packet.canonicalBytes
        let origInstruction = packet.instruction
        let origDeviceId = packet.deviceId
        let origNonce = packet.nonce
        let origCreatedAt = packet.createdAt

        let mock = MockMeshPaymentSubmitter()
        mock.resultToReturn = sampleSettledResult(paymentId: packet.paymentId)

        let service = OfflineReconciliationService(packetStore: store, apiClient: mock)
        _ = await service.reconcile(paymentId: packet.paymentId)

        // Retrieve settled record
        guard let finalRecord = store.get(paymentId: packet.paymentId) else {
            try assert(false, "Record must exist")
            return
        }

        // Assert strictly zero bytes changed
        try assert(finalRecord.packet.signature == origSignature, "Signature must remain identical")
        try assert(finalRecord.packet.canonicalBytes == origCanonicalBytes, "Canonical bytes must remain identical")
        try assert(finalRecord.packet.instruction == origInstruction, "Instruction must remain identical")
        try assert(finalRecord.packet.deviceId == origDeviceId, "Device ID must remain identical")
        try assert(finalRecord.packet.nonce == origNonce, "Nonce must remain identical")
        try assert(finalRecord.packet.createdAt == origCreatedAt, "CreatedAt must remain identical")

        // Assert signature remains cryptographically verifiable
        let (valid, _) = DeviceIdentityManager.verifyRemoteRSASSA_PSS(
            publicKeyBase64X509: keyBase64,
            message: finalRecord.packet.canonicalBytes,
            signatureBase64: finalRecord.packet.signature
        )
        try assert(valid, "Signature must remain mathematically valid after reconciliation")

        print("  ✓ PASS: testOriginalSignedInstructionAndSignatureUnchanged")
    }

    // MARK: - Stage 6.4B.3 UI Reconciliation Workflow Integration Tests

    public static func testUIReconciliationSuccessOutcomeAndState() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = ReceivedPacketStore(fileURL: tempDir.appendingPathComponent("ui1.json"))
        let (packet, _) = try createSampleSignedPacket(amount: 75.00)
        let record = try ReceivedPacketRecord(
            packet: packet,
            receivedFromPeer: "Alice-iPhone",
            isSignatureMathematicallyValid: true,
            trustStatusNote: "Held in local inbox"
        )
        try store.save(record)

        let mock = MockMeshPaymentSubmitter()
        mock.resultToReturn = sampleSettledResult(paymentId: packet.paymentId)

        let service = OfflineReconciliationService(packetStore: store, apiClient: mock)
        let outcome = await service.reconcile(paymentId: packet.paymentId)

        guard case .settled(let id, let result) = outcome else {
            try assert(false, "Outcome must be settled, was \(outcome)")
            return
        }
        try assert(id == packet.paymentId, "Payment ID must match")
        try assert(result.status.uppercased() == "SETTLED", "Result status must be SETTLED")

        // Assert record is now SETTLED in store
        let stored = store.get(paymentId: packet.paymentId)
        try assert(stored?.reconciliationStatus == .settled, "Stored status must be SETTLED")
        try assert(stored?.failureReason == nil, "Failure reason must be nil")

        print("  ✓ PASS: testUIReconciliationSuccessOutcomeAndState")
    }

    public static func testUIDefinitiveRejectionOutcomeAndReason() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = ReceivedPacketStore(fileURL: tempDir.appendingPathComponent("ui2.json"))
        let (packet, _) = try createSampleSignedPacket(amount: 5000.00)
        let record = try ReceivedPacketRecord(
            packet: packet,
            receivedFromPeer: "Alice-iPhone",
            isSignatureMathematicallyValid: true,
            trustStatusNote: "Held in local inbox"
        )
        try store.save(record)

        let mock = MockMeshPaymentSubmitter()
        mock.errorToThrow = APIError.paymentFailed("Insufficient funds for account alice: required 5000.00, available 4970.00")

        let service = OfflineReconciliationService(packetStore: store, apiClient: mock)
        let outcome = await service.reconcile(paymentId: packet.paymentId)

        guard case .rejected(let id, let reason) = outcome else {
            try assert(false, "Outcome must be rejected, was \(outcome)")
            return
        }
        try assert(id == packet.paymentId, "Payment ID must match")
        try assert(reason.contains("Insufficient funds"), "Rejection reason must contain 'Insufficient funds'")

        // Assert record is now FAILED in store and failureReason is preserved for UI rendering
        let stored = store.get(paymentId: packet.paymentId)
        try assert(stored?.reconciliationStatus == .failed, "Stored status must be FAILED")
        try assert(stored?.failureReason?.contains("Insufficient funds") == true, "Failure reason must be stored for UI")

        print("  ✓ PASS: testUIDefinitiveRejectionOutcomeAndReason")
    }

    public static func testUINetworkTimeoutLeavesRetryableForUIRetry() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = ReceivedPacketStore(fileURL: tempDir.appendingPathComponent("ui3.json"))
        let (packet, _) = try createSampleSignedPacket(amount: 10.00)
        let record = try ReceivedPacketRecord(
            packet: packet,
            receivedFromPeer: "Alice-iPhone",
            isSignatureMathematicallyValid: true,
            trustStatusNote: "Held in local inbox"
        )
        try store.save(record)

        let mock = MockMeshPaymentSubmitter()
        mock.errorToThrow = APIError.networkError("The request timed out.")

        let service = OfflineReconciliationService(packetStore: store, apiClient: mock)
        let outcome = await service.reconcile(paymentId: packet.paymentId)

        guard case .retryable(let id, let reason) = outcome else {
            try assert(false, "Outcome must be retryable on network timeout, was \(outcome)")
            return
        }
        try assert(id == packet.paymentId, "Payment ID must match")
        try assert(reason.contains("Network connection failure"), "Reason must note network connection failure")

        // Assert record remains in SETTLING on disk (retryable), not FAILED or SETTLED
        let stored = store.get(paymentId: packet.paymentId)
        try assert(stored?.reconciliationStatus == .settling, "Stored status must remain SETTLING on timeout")
        try assert(stored?.failureReason == nil, "Must not set terminal failureReason on timeout")

        print("  ✓ PASS: testUINetworkTimeoutLeavesRetryableForUIRetry")
    }

    public static func testUIAmbiguousDuplicateLeavesRetryable() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = ReceivedPacketStore(fileURL: tempDir.appendingPathComponent("ui4.json"))
        let (packet, _) = try createSampleSignedPacket(amount: 15.00)
        let record = try ReceivedPacketRecord(
            packet: packet,
            receivedFromPeer: "Alice-iPhone",
            isSignatureMathematicallyValid: true,
            trustStatusNote: "Held in local inbox"
        )
        try store.save(record)

        let mock = MockMeshPaymentSubmitter()
        mock.errorToThrow = APIError.paymentFailed("Duplicate payment rejected (paymentId already settled): \(packet.paymentId)")

        let service = OfflineReconciliationService(packetStore: store, apiClient: mock)
        let outcome = await service.reconcile(paymentId: packet.paymentId)

        guard case .retryable(let id, let reason) = outcome else {
            try assert(false, "Outcome must be retryable on duplicate response, was \(outcome)")
            return
        }
        try assert(id == packet.paymentId, "Payment ID must match")
        try assert(reason.contains("Ambiguous duplicate"), "Reason must explain duplicate ambiguity")

        // Record must remain in SETTLING
        let stored = store.get(paymentId: packet.paymentId)
        try assert(stored?.reconciliationStatus == .settling, "Stored status must remain SETTLING for ambiguous duplicate")

        print("  ✓ PASS: testUIAmbiguousDuplicateLeavesRetryable")
    }

    public static func testUIRetrySettlingPacketAllowed() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = ReceivedPacketStore(fileURL: tempDir.appendingPathComponent("ui5.json"))
        let (packet, _) = try createSampleSignedPacket(amount: 25.00)
        // Record is already in SETTLING from a previous interrupted request
        let record = try ReceivedPacketRecord(
            packet: packet,
            receivedFromPeer: "Alice-iPhone",
            isSignatureMathematicallyValid: true,
            trustStatusNote: "Held in local inbox",
            reconciliationStatus: .settling
        )
        try store.save(record)

        let mock = MockMeshPaymentSubmitter()
        mock.resultToReturn = sampleSettledResult(paymentId: packet.paymentId)

        let service = OfflineReconciliationService(packetStore: store, apiClient: mock)
        // User taps Retry Settlement Verification in UI
        let outcome = await service.reconcile(paymentId: packet.paymentId)

        guard case .settled(let id, _) = outcome else {
            try assert(false, "Outcome must be settled when retrying SETTLING packet, was \(outcome)")
            return
        }
        try assert(id == packet.paymentId, "Payment ID must match")

        let stored = store.get(paymentId: packet.paymentId)
        try assert(stored?.reconciliationStatus == .settled, "Stored status must transition from SETTLING to SETTLED")

        print("  ✓ PASS: testUIRetrySettlingPacketAllowed")
    }

    public static func testUIInFlightConcurrencyGuard() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = ReceivedPacketStore(fileURL: tempDir.appendingPathComponent("ui6.json"))
        let (packet, _) = try createSampleSignedPacket(amount: 30.00)
        let record = try ReceivedPacketRecord(
            packet: packet,
            receivedFromPeer: "Alice-iPhone",
            isSignatureMathematicallyValid: true,
            trustStatusNote: "Held in local inbox"
        )
        try store.save(record)

        let mock = MockMeshPaymentSubmitter()
        mock.delayNanoseconds = 200_000_000 // 200ms
        mock.resultToReturn = sampleSettledResult(paymentId: packet.paymentId)

        let service = OfflineReconciliationService(packetStore: store, apiClient: mock)

        async let firstCall = service.reconcile(paymentId: packet.paymentId)
        try await Task.sleep(nanoseconds: 20_000_000) // 20ms
        let secondCall = await service.reconcile(paymentId: packet.paymentId)

        let firstOutcome = await firstCall

        guard case .settled = firstOutcome else {
            try assert(false, "First call must settle")
            return
        }

        guard case .invalidState(_, let currentStatus, let reason) = secondCall else {
            try assert(false, "Second call must be rejected as invalidState due to in-flight lock, was \(secondCall)")
            return
        }
        try assert(currentStatus == .settling, "Current status must be settling")
        try assert(reason.contains("already in progress"), "Reason must mention already in progress")

        print("  ✓ PASS: testUIInFlightConcurrencyGuard")
    }
}
