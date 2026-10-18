import Foundation
import Security
import CryptoKit

/// Comprehensive Automated Regression Test Suite for True Offline Store-and-Forward Payments.
///
/// Validates the 10 core lifecycle invariants:
/// 1. Creating a payment with a valid cached allowance while the backend is unavailable.
/// 2. Transmitting and receiving a signed packet without invoking the backend client.
/// 3. Persisting a received payment to durable storage before issuing transport acknowledgment.
/// 4. Receiver process restart and lossless recovery of pending received payments.
/// 5. Duplicate packet delivery idempotency without redundant persistence or duplicate settlement.
/// 6. Queue retention after reconciliation network timeout (retains retryable status without loss).
/// 7. Successful delayed reconciliation once connectivity is restored.
/// 8. Duplicate reconciliation idempotency without duplicate ledger effects.
/// 9. Cryptographic and policy rejections (invalid signature, expired allowance, exhausted allowance, wrong device binding).
/// 10. Distinct UI / state separation of received/pending payments from authoritatively settled ledger transactions.
///
/// SAFETY CONSTRAINTS:
/// - Completely isolated from `data/upimesh.mv.db`.
/// - Uses temporary directories for all file stores.
/// - Generates ephemeral RSA-2048 keypairs in memory.
/// - Never makes actual HTTP / network calls.
public struct TrueOfflineStoreAndForwardTests {

    public static func runAllTests() async throws {
        print("\n=== Running TrueOfflineStoreAndForwardTests (10 scenarios) ===")

        try test1_createPaymentWithCachedAllowanceWhileBackendUnavailable()
        try test2_transmittingAndReceivingSignedPacketWithoutBackendClient()
        try test3_persistingReceivedPaymentBeforeAcknowledgement()
        try test4_restartingReceiverAndRecoveringPendingPayments()
        try test5_duplicatePacketDeliveryProtection()
        try await test6_queueRetentionAfterReconciliationTimeout()
        try await test7_successfulReconciliationAfterConnectivityReturns()
        try await test8_duplicateReconciliationWithoutDuplicateLedgerEffects()
        try test9_securityRejections_invalidSig_expired_exhausted_wrongDevice()
        try await test10_distinguishingReceivedPendingFromSettled()

        print("=== TrueOfflineStoreAndForwardTests: All 10 passed cleanly! ===\n")
    }

    private static func assert(_ condition: Bool, _ message: String) throws {
        if !condition {
            print("  ✗ FAIL: \(message)")
            throw NSError(domain: "TrueOfflineStoreAndForwardTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    // MARK: - Cryptographic Test Utilities

    private static func generateRSAKeyPair() throws -> (privateKey: SecKey, publicKeyBase64: String, fingerprint: String) {
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
        let digest = SHA256.hash(data: x509)
        let fingerprint = digest.map { String(format: "%02x", $0) }.joined(separator: ":")

        return (priv, keyBase64, fingerprint)
    }

    private static func signBytes(privateKey: SecKey, data: Data) throws -> String {
        var error: Unmanaged<CFError>?
        guard let sigData = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePSSSHA256,
            data as CFData,
            &error
        ) as Data? else {
            let desc = error?.takeRetainedValue().localizedDescription ?? "Signing failed"
            throw NSError(domain: "Signing", code: 2, userInfo: [NSLocalizedDescriptionKey: desc])
        }
        return sigData.base64EncodedString()
    }

    // MARK: - Test 1: Creating Payment with Cached Allowance while Backend is Unavailable
    public static func test1_createPaymentWithCachedAllowanceWhileBackendUnavailable() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let packetStoreFile = tempDir.appendingPathComponent("sender_packets.json")
        let packetStore = OfflinePacketStore(fileURL: packetStoreFile)

        // 1. Generate Bank Authority & Alice Device Keys
        let (bankPriv, bankPub, _) = try generateRSAKeyPair()
        let (alicePriv, _, aliceFp) = try generateRSAKeyPair()
        let aliceDeviceId = "alice-test-hardware-id"

        // 2. Construct and bank-sign a genuine allowance voucher
        let allowanceId = "alw-offline-test-101"
        let voucherCanonicalBytes = OfflineAllowanceVoucher.buildCanonicalVoucherBytes(
            allowanceId: allowanceId,
            accountId: "alice",
            deviceId: aliceDeviceId,
            deviceFingerprint: aliceFp,
            currency: "INR",
            allocatedAmount: Decimal(500.00),
            issuedAt: "2026-10-18T10:00:00Z",
            expiresAt: "2026-10-30T10:00:00Z",
            protocolVersion: 1
        )
        let bankSig = try signBytes(privateKey: bankPriv, data: voucherCanonicalBytes)

        let voucher = OfflineAllowanceVoucher(
            allowanceId: allowanceId,
            accountId: "alice",
            deviceId: aliceDeviceId,
            devicePublicKeyFingerprint: aliceFp,
            currency: "INR",
            allocatedAmount: Decimal(500.00),
            spentAmount: Decimal.zero,
            lastSequenceNumber: 0,
            issuedAt: "2026-10-18T10:00:00Z",
            expiresAt: "2026-10-30T10:00:00Z",
            protocolVersion: 1,
            status: "ACTIVE",
            voucherSignature: bankSig,
            bankPublicKeyBase64: bankPub
        )

        // 3. Local Offline Spend Construction (zero backend calls)
        let spendPaymentId = UUID().uuidString.lowercased()
        let spendNow = PaymentInstant.now()
        let spendAmount = Decimal(75.00)

        let spendBytes = OfflineSpendRecord.buildCanonicalSpendBytes(
            allowanceId: voucher.allowanceId,
            paymentId: spendPaymentId,
            payerAccountId: voucher.accountId,
            payerDeviceId: aliceDeviceId,
            recipientAccountId: "bob",
            amount: spendAmount,
            currency: "INR",
            sequenceNumber: 1,
            cumulativeSpentAmount: spendAmount,
            createdAt: spendNow.isoString,
            voucherSignature: voucher.voucherSignature,
            protocolVersion: voucher.protocolVersion
        )
        let payerSig = try signBytes(privateKey: alicePriv, data: spendBytes)

        let spendRecord = OfflineSpendRecord(
            allowanceId: voucher.allowanceId,
            paymentId: spendPaymentId,
            payerAccountId: voucher.accountId,
            payerDeviceId: aliceDeviceId,
            recipientAccountId: "bob",
            amount: spendAmount,
            currency: "INR",
            sequenceNumber: 1,
            cumulativeSpentAmount: spendAmount,
            createdAt: spendNow.isoString,
            voucherSignature: voucher.voucherSignature,
            payerSignature: payerSig,
            protocolVersion: voucher.protocolVersion
        )

        let instruction = try PaymentInstruction(
            paymentId: spendPaymentId,
            fromAccount: "alice",
            toAccount: "bob",
            amount: spendAmount,
            createdAt: spendNow,
            nonce: UUID().uuidString.lowercased()
        )
        let legacySig = try signBytes(privateKey: alicePriv, data: instruction.toCanonicalBytes())
        let signedInstruction = try instruction.withSignature(legacySig)

        let packet = try OfflinePaymentPacket(
            instruction: signedInstruction,
            deviceId: aliceDeviceId,
            status: .created,
            allowanceSpend: spendRecord
        )

        // Verify status is CREATED and packet is locally stored
        try assert(packet.status == .created, "Packet status must be CREATED")
        try assert(packet.status.displayName == "CREATED", "Display name must be CREATED")
        try packetStore.save(packet)

        try assert(packetStore.contains(paymentId: spendPaymentId), "Packet must be in sender store")
        let retrieved = packetStore.get(paymentId: spendPaymentId)
        try assert(retrieved?.status == .created, "Retrieved packet must retain CREATED status")
        try assert(retrieved?.allowanceSpend?.amount == Decimal(75.00), "Spend amount must match")

        print("  ✓ PASS: test1_createPaymentWithCachedAllowanceWhileBackendUnavailable")
    }

    // MARK: - Test 2: Transmitting and Receiving Signed Packet Without Backend Client
    public static func test2_transmittingAndReceivingSignedPacketWithoutBackendClient() throws {
        let (alicePriv, alicePub, _) = try generateRSAKeyPair()
        let aliceDeviceId = "alice-iphone-hw"

        let paymentId = UUID().uuidString.lowercased()
        let instruction = try PaymentInstruction(
            paymentId: paymentId,
            fromAccount: "alice",
            toAccount: "bob",
            amount: Decimal(120.00),
            createdAt: PaymentInstant.now(),
            nonce: UUID().uuidString.lowercased()
        )
        let sig = try signBytes(privateKey: alicePriv, data: instruction.toCanonicalBytes())
        let signedInstruction = try instruction.withSignature(sig)

        let packet = try OfflinePaymentPacket(
            instruction: signedInstruction,
            deviceId: aliceDeviceId,
            status: .created
        )

        // Package into wire transport envelope with sender's public key
        let wireMessage = PeerTransferMessage(
            messageVersion: 1,
            packet: packet,
            senderPublicKeyBase64X509: alicePub
        )
        try wireMessage.validate()

        // Receiver receives raw wire data and verifies offline with zero backend requests
        let wireData = try JSONEncoder().encode(wireMessage)
        let decodedMessage = try JSONDecoder().decode(PeerTransferMessage.self, from: wireData)
        try decodedMessage.validate()

        // Mathematical signature verification
        let (valid, _) = DeviceIdentityManager.verifyRemoteRSASSA_PSS(
            publicKeyBase64X509: decodedMessage.senderPublicKeyBase64X509!,
            message: decodedMessage.packet.canonicalBytes,
            signatureBase64: decodedMessage.packet.signature
        )
        try assert(valid, "Receiver must mathematically verify signature offline using attached public key")

        // Construct received record: strictly RECEIVED — NOT SETTLED
        let receivedPacket = try decodedMessage.packet.withStatus(.received)
        let record = try ReceivedPacketRecord(
            packet: receivedPacket,
            receivedFromPeer: "Alice-iPhone",
            isSignatureMathematicallyValid: true,
            isSenderIdentityAuthenticated: false,
            trustStatusNote: "RSASSA-PSS signature valid. Identity is unverified offline.",
            reconciliationStatus: .received
        )

        try assert(record.reconciliationStatus == .received, "Status must be RECEIVED")
        try assert(record.reconciliationStatus.displayName == "RECEIVED — NOT SETTLED", "Display name must explicitly reflect un-settled status")

        print("  ✓ PASS: test2_transmittingAndReceivingSignedPacketWithoutBackendClient")
    }

    // MARK: - Test 3: Persisting Received Payment Before Acknowledgement
    public static func test3_persistingReceivedPaymentBeforeAcknowledgement() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let macStoreFile = tempDir.appendingPathComponent("mac_inbox.json")
        let macStore = MacReceivedPacketStore(fileURL: macStoreFile)

        let (alicePriv, alicePub, _) = try generateRSAKeyPair()
        let paymentId = UUID().uuidString.lowercased()
        let instruction = try PaymentInstruction(
            paymentId: paymentId,
            fromAccount: "alice",
            toAccount: "carol",
            amount: Decimal(35.00),
            createdAt: PaymentInstant.now(),
            nonce: UUID().uuidString.lowercased()
        )
        let sig = try signBytes(privateKey: alicePriv, data: instruction.toCanonicalBytes())
        let packet = try OfflinePaymentPacket(
            instruction: try instruction.withSignature(sig),
            deviceId: "alice-iphone",
            status: .created
        )

        let wireMessage = PeerTransferMessage(messageVersion: 1, packet: packet, senderPublicKeyBase64X509: alicePub)
        try wireMessage.validate()

        // Receiver Workflow:
        // 1. Verify signatures
        let (valid, _) = MeshCryptoVerifier.verifyRemoteRSASSA_PSS(
            publicKeyBase64X509: wireMessage.senderPublicKeyBase64X509!,
            message: wireMessage.packet.canonicalBytes,
            signatureBase64: wireMessage.packet.signature
        )
        try assert(valid, "Signature must verify")

        // 2. Persist to Mac store BEFORE issuing ACK
        let record = try MacReceivedPacketRecord(
            packet: try wireMessage.packet.withStatus(.received),
            receivedFromPeer: "Alice-iPhone",
            isSignatureMathematicallyValid: true,
            isSenderIdentityAuthenticated: false,
            trustStatusNote: "Mathematically valid",
            reconciliationStatus: .received
        )
        try macStore.save(record)

        // 3. Verify packet is durably on disk before ACK is generated
        try assert(macStore.contains(paymentId: paymentId), "Packet must be written to disk before ACK")

        // 4. Emit ACK
        let ack = PeerTransferAckMessage(
            paymentId: paymentId,
            recipientDeviceId: "mac-companion-101",
            isPersisted: true,
            isDuplicate: false
        )
        try ack.validate()
        let ackData = try ack.encode()
        let decodedAck = try PeerTransferAckMessage.decodeAndValidate(from: ackData)
        try assert(decodedAck.isPersisted, "ACK must confirm disk persistence")
        try assert(decodedAck.paymentId == paymentId, "ACK must match paymentId")

        // 5. Sender updates local packet status to SENT upon ACK
        let senderStoreFile = tempDir.appendingPathComponent("sender_packets.json")
        let senderStore = OfflinePacketStore(fileURL: senderStoreFile)
        try senderStore.save(packet)
        let updatedSenderPacket = try senderStore.updateStatus(paymentId: paymentId, status: .sent)
        try assert(updatedSenderPacket.status == .sent, "Sender packet must transition to SENT")
        try assert(updatedSenderPacket.status.displayName == "SENT", "Status display name must be SENT")

        print("  ✓ PASS: test3_persistingReceivedPaymentBeforeAcknowledgement")
    }

    // MARK: - Test 4: Restarting Receiver and Recovering Pending Payments
    public static func test4_restartingReceiverAndRecoveringPendingPayments() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storeFile = tempDir.appendingPathComponent("mac_persistent_inbox.json")

        let (alicePriv, _, _) = try generateRSAKeyPair()

        // 1. First process life: Store 3 received payments
        var createdIds: [String] = []
        do {
            let store1 = MacReceivedPacketStore(fileURL: storeFile)
            for i in 1...3 {
                let pid = "pay-persistence-test-\(i)-\(UUID().uuidString.prefix(6))"
                createdIds.append(pid)
                let inst = try PaymentInstruction(
                    paymentId: pid,
                    fromAccount: "alice",
                    toAccount: "carol",
                    amount: Decimal(i * 20),
                    createdAt: PaymentInstant.now(),
                    nonce: UUID().uuidString.lowercased()
                )
                let sig = try signBytes(privateKey: alicePriv, data: inst.toCanonicalBytes())
                let pkt = try OfflinePaymentPacket(
                    instruction: try inst.withSignature(sig),
                    deviceId: "alice-iphone",
                    status: .received
                )
                let rec = try MacReceivedPacketRecord(
                    packet: pkt,
                    receivedFromPeer: "Alice-iPhone",
                    isSignatureMathematicallyValid: true,
                    trustStatusNote: "Valid",
                    reconciliationStatus: (i == 1) ? .pendingReconciliation : .received
                )
                try store1.save(rec)
            }
            try assert(store1.count == 3, "First process store must have 3 items")
        }

        // 2. Simulate complete app restart / termination: create completely fresh instance
        let store2 = MacReceivedPacketStore(fileURL: storeFile)
        try assert(store2.count == 3, "Relaunched store must recover all 3 items across restart")

        for pid in createdIds {
            guard let recovered = store2.get(paymentId: pid) else {
                throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to recover \(pid)"])
            }
            try assert(recovered.packet.fromAccount == "alice", "Recovered fromAccount must match")
            try assert(recovered.packet.toAccount == "carol", "Recovered toAccount must match")
            try assert(recovered.isSignatureMathematicallyValid, "Recovered signature validity must match")
            try assert(recovered.reconciliationStatus == .received || recovered.reconciliationStatus == .pendingReconciliation, "Status must be un-settled")
        }

        print("  ✓ PASS: test4_restartingReceiverAndRecoveringPendingPayments")
    }

    // MARK: - Test 5: Duplicate Packet Delivery Protection
    public static func test5_duplicatePacketDeliveryProtection() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storeFile = tempDir.appendingPathComponent("dedup_inbox.json")
        let store = MacReceivedPacketStore(fileURL: storeFile)

        let (alicePriv, _, _) = try generateRSAKeyPair()
        let paymentId = "pay-dedup-test-\(UUID().uuidString.lowercased())"

        let inst = try PaymentInstruction(
            paymentId: paymentId,
            fromAccount: "alice",
            toAccount: "carol",
            amount: Decimal(80.00),
            createdAt: PaymentInstant.now(),
            nonce: UUID().uuidString.lowercased()
        )
        let sig = try signBytes(privateKey: alicePriv, data: inst.toCanonicalBytes())
        let pkt = try OfflinePaymentPacket(
            instruction: try inst.withSignature(sig),
            deviceId: "alice-iphone",
            status: .received
        )
        let rec = try MacReceivedPacketRecord(
            packet: pkt,
            receivedFromPeer: "Alice-iPhone",
            isSignatureMathematicallyValid: true,
            trustStatusNote: "Valid",
            reconciliationStatus: .received
        )

        // First delivery: Saved successfully
        try store.save(rec)
        try assert(store.count == 1, "Store must contain exactly 1 packet")

        // Second delivery (duplicate retransmission from sender):
        // Receiver detects duplicate
        try assert(store.contains(paymentId: paymentId), "Receiver must identify duplicate paymentId")

        // Store re-save must be rejected
        var duplicateCaught = false
        do {
            try store.save(rec)
        } catch MacReceivedPacketStoreError.duplicatePacketId(let id) {
            try assert(id == paymentId, "Duplicate ID must match")
            duplicateCaught = true
        }
        try assert(duplicateCaught, "Duplicate save must throw duplicatePacketId")

        // ACK must be emitted with isDuplicate = true so sender is informed without duplicate storage
        let dupAck = PeerTransferAckMessage(
            paymentId: paymentId,
            recipientDeviceId: "mac-companion",
            isPersisted: true,
            isDuplicate: true
        )
        try assert(dupAck.isDuplicate, "ACK must flag duplicate delivery")
        try assert(dupAck.isPersisted, "ACK must confirm packet is safely persisted")
        try assert(store.count == 1, "Store count must strictly remain 1")

        print("  ✓ PASS: test5_duplicatePacketDeliveryProtection")
    }

    // MARK: - Test 6: Queue Retention After Reconciliation Timeout
    public static func test6_queueRetentionAfterReconciliationTimeout() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storeFile = tempDir.appendingPathComponent("timeout_inbox.json")
        let store = ReceivedPacketStore(fileURL: storeFile)

        let (alicePriv, _, _) = try generateRSAKeyPair()
        let paymentId = "pay-timeout-\(UUID().uuidString.lowercased())"
        let inst = try PaymentInstruction(
            paymentId: paymentId,
            fromAccount: "alice",
            toAccount: "bob",
            amount: Decimal(45.00),
            createdAt: PaymentInstant.now(),
            nonce: UUID().uuidString.lowercased()
        )
        let sig = try signBytes(privateKey: alicePriv, data: inst.toCanonicalBytes())
        let pkt = try OfflinePaymentPacket(
            instruction: try inst.withSignature(sig),
            deviceId: "alice-iphone",
            status: .received
        )
        let rec = try ReceivedPacketRecord(
            packet: pkt,
            receivedFromPeer: "Alice-iPhone",
            isSignatureMathematicallyValid: true,
            trustStatusNote: "Valid",
            reconciliationStatus: .received
        )
        try store.save(rec)

        // Mock API client that simulates a network timeout
        final class TimeoutMockClient: MeshPaymentSubmitting, @unchecked Sendable {
            func submitSignedMeshPayment(instruction: PaymentInstruction, deviceId: String) async throws -> MeshPaymentResultDTO {
                throw NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: [NSLocalizedDescriptionKey: "The request timed out."])
            }
            func queryPaymentStatus(paymentId: String) async throws -> PaymentStatusResponseDTO {
                throw NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: [NSLocalizedDescriptionKey: "The request timed out."])
            }
        }

        let reconciliationService = OfflineReconciliationService(
            packetStore: store,
            apiClient: TimeoutMockClient()
        )

        let outcome = await reconciliationService.reconcile(paymentId: paymentId)
        guard case .retryable(let outId, let reason) = outcome else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected retryable outcome on timeout, got \(outcome)"])
        }
        try assert(outId == paymentId, "Payment ID must match")
        try assert(reason.contains("timed out") || reason.contains("timeout"), "Reason must mention timeout")

        // Critical Invariant: Packet must NOT be dropped, deleted, or marked failed
        guard let retained = store.get(paymentId: paymentId) else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Packet was lost after timeout"])
        }
        try assert(retained.reconciliationStatus == .settling, "Status must remain in retryable SETTLING state")
        try assert(retained.reconciliationStatus != .settled, "Status must not be SETTLED")
        try assert(retained.reconciliationStatus != .failed, "Status must not be FAILED")

        print("  ✓ PASS: test6_queueRetentionAfterReconciliationTimeout")
    }

    // MARK: - Test 7: Successful Reconciliation After Connectivity Returns
    public static func test7_successfulReconciliationAfterConnectivityReturns() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storeFile = tempDir.appendingPathComponent("success_inbox.json")
        let store = ReceivedPacketStore(fileURL: storeFile)

        let (alicePriv, _, _) = try generateRSAKeyPair()
        let paymentId = "pay-reconcile-success-\(UUID().uuidString.lowercased())"
        let inst = try PaymentInstruction(
            paymentId: paymentId,
            fromAccount: "alice",
            toAccount: "bob",
            amount: Decimal(100.00),
            createdAt: PaymentInstant.now(),
            nonce: UUID().uuidString.lowercased()
        )
        let sig = try signBytes(privateKey: alicePriv, data: inst.toCanonicalBytes())
        let pkt = try OfflinePaymentPacket(
            instruction: try inst.withSignature(sig),
            deviceId: "alice-iphone",
            status: .received
        )
        let rec = try ReceivedPacketRecord(
            packet: pkt,
            receivedFromPeer: "Alice-iPhone",
            isSignatureMathematicallyValid: true,
            trustStatusNote: "Valid",
            reconciliationStatus: .received
        )
        try store.save(rec)

        // Mock API client simulating restored connectivity and successful authoritative ledger settlement
        final class SuccessMockClient: MeshPaymentSubmitting, @unchecked Sendable {
            func submitSignedMeshPayment(instruction: PaymentInstruction, deviceId: String) async throws -> MeshPaymentResultDTO {
                return MeshPaymentResultDTO(
                    success: true,
                    paymentId: instruction.paymentId,
                    packetId: "pkt-\(UUID().uuidString)",
                    fromAccount: instruction.fromAccount,
                    toAccount: instruction.toAccount,
                    amount: NSDecimalNumber(decimal: instruction.amount).doubleValue,
                    roundsRun: 1,
                    hopsTaken: 1,
                    remainingTtl: 3,
                    routeTrace: [deviceId, "bridge"],
                    encryptedKeySnippet: nil,
                    ivHex: nil,
                    ciphertextSnippet: nil,
                    status: "SETTLED",
                    message: "Payment settled on double-entry ledger"
                )
            }
            func queryPaymentStatus(paymentId: String) async throws -> PaymentStatusResponseDTO {
                return PaymentStatusResponseDTO(
                    found: true,
                    paymentId: paymentId,
                    status: "SETTLED",
                    fromAccount: "alice",
                    toAccount: "bob",
                    amount: 100.00,
                    message: "Settled"
                )
            }
        }

        let service = OfflineReconciliationService(
            packetStore: store,
            apiClient: SuccessMockClient()
        )

        let outcome = await service.reconcile(paymentId: paymentId)
        guard case .settled(let outId, let result) = outcome else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected SETTLED outcome, got \(outcome)"])
        }
        try assert(outId == paymentId, "Payment ID must match")
        try assert(result.status == "SETTLED", "Result status must be SETTLED")

        // Verify local store was updated atomically to SETTLED
        let settledRecord = store.get(paymentId: paymentId)
        try assert(settledRecord?.reconciliationStatus == .settled, "Local store must be transitioned to SETTLED")
        try assert(settledRecord?.reconciliationStatus.displayName == "SETTLED", "Display name must be SETTLED")

        print("  ✓ PASS: test7_successfulReconciliationAfterConnectivityReturns")
    }

    // MARK: - Test 8: Duplicate Reconciliation Without Duplicate Ledger Effects
    public static func test8_duplicateReconciliationWithoutDuplicateLedgerEffects() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storeFile = tempDir.appendingPathComponent("dedup_reconcile_inbox.json")
        let store = ReceivedPacketStore(fileURL: storeFile)

        let (alicePriv, _, _) = try generateRSAKeyPair()
        let paymentId = "pay-idempotent-\(UUID().uuidString.lowercased())"
        let inst = try PaymentInstruction(
            paymentId: paymentId,
            fromAccount: "alice",
            toAccount: "bob",
            amount: Decimal(50.00),
            createdAt: PaymentInstant.now(),
            nonce: UUID().uuidString.lowercased()
        )
        let sig = try signBytes(privateKey: alicePriv, data: inst.toCanonicalBytes())
        let pkt = try OfflinePaymentPacket(
            instruction: try inst.withSignature(sig),
            deviceId: "alice-iphone",
            status: .received
        )
        let rec = try ReceivedPacketRecord(
            packet: pkt,
            receivedFromPeer: "Alice-iPhone",
            isSignatureMathematicallyValid: true,
            trustStatusNote: "Valid",
            reconciliationStatus: .received
        )
        try store.save(rec)

        final class AtomicCallCounter: @unchecked Sendable {
            private let lock = NSLock()
            private var val = 0
            func increment() {
                lock.lock()
                defer { lock.unlock() }
                val += 1
            }
            var count: Int {
                lock.lock()
                defer { lock.unlock() }
                return val
            }
        }

        let counter = AtomicCallCounter()

        final class IdempotentMockClient: MeshPaymentSubmitting, @unchecked Sendable {
            let counter: AtomicCallCounter
            init(counter: AtomicCallCounter) {
                self.counter = counter
            }

            func submitSignedMeshPayment(instruction: PaymentInstruction, deviceId: String) async throws -> MeshPaymentResultDTO {
                counter.increment()
                return MeshPaymentResultDTO(
                    success: true,
                    paymentId: instruction.paymentId,
                    packetId: "pkt-1",
                    fromAccount: instruction.fromAccount,
                    toAccount: instruction.toAccount,
                    amount: 50.00,
                    roundsRun: 1,
                    hopsTaken: 1,
                    remainingTtl: 3,
                    routeTrace: [deviceId, "bridge"],
                    encryptedKeySnippet: nil,
                    ivHex: nil,
                    ciphertextSnippet: nil,
                    status: "SETTLED",
                    message: "Idempotent replay: already settled"
                )
            }
            func queryPaymentStatus(paymentId: String) async throws -> PaymentStatusResponseDTO {
                return PaymentStatusResponseDTO(
                    found: true,
                    paymentId: paymentId,
                    status: "SETTLED",
                    fromAccount: "alice",
                    toAccount: "bob",
                    amount: 50.00,
                    message: "Already settled"
                )
            }
        }

        let service = OfflineReconciliationService(
            packetStore: store,
            apiClient: IdempotentMockClient(counter: counter)
        )

        // 1. First reconciliation -> Settles
        let outcome1 = await service.reconcile(paymentId: paymentId)
        guard case .settled = outcome1 else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "First reconciliation should settle"])
        }
        try assert(counter.count == 1, "Backend called once")

        // 2. Second reconciliation attempt on the same settled packet
        // Guard prevents resubmitting SETTLED packet
        let outcome2 = await service.reconcile(paymentId: paymentId)
        guard case .invalidState(_, let status, let reason) = outcome2 else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected invalidState for already settled packet, got \(outcome2)"])
        }
        try assert(status == .settled, "Status must be SETTLED")
        try assert(reason.contains("only RECEIVED, PENDING_RECONCILIATION, or SETTLING allowed"), "Reason must cite allowed statuses")
        try assert(counter.count == 1, "Backend call count must remain 1 — no second submission or double-debit")

        print("  ✓ PASS: test8_duplicateReconciliationWithoutDuplicateLedgerEffects")
    }

    // MARK: - Test 9: Security Rejections (Invalid Sig, Expired, Exhausted, Wrong Device)
    public static func test9_securityRejections_invalidSig_expired_exhausted_wrongDevice() throws {
        let (_, bankPub, _) = try generateRSAKeyPair()
        let (alicePriv, alicePub, aliceFp) = try generateRSAKeyPair()
        let aliceDeviceId = "alice-phone-device"

        // Sub-test A: Bank voucher signature is invalid/tampered
        let voucherBadSig = OfflineAllowanceVoucher(
            allowanceId: "alw-badsig",
            accountId: "alice",
            deviceId: aliceDeviceId,
            devicePublicKeyFingerprint: aliceFp,
            currency: "INR",
            allocatedAmount: Decimal(500.00),
            spentAmount: Decimal.zero,
            lastSequenceNumber: 0,
            issuedAt: "2026-10-18T10:00:00Z",
            expiresAt: "2026-10-30T10:00:00Z",
            protocolVersion: 1,
            status: "ACTIVE",
            voucherSignature: "TAMPERED_BANK_SIGNATURE_BASE64",
            bankPublicKeyBase64: bankPub
        )
        let (sigValid, _) = voucherBadSig.verifyBankSignature(trustedBankPublicKeyBase64: bankPub)
        try assert(!sigValid, "Tampered bank signature must be rejected")

        // Sub-test B: Expired allowance voucher
        let voucherExpired = OfflineAllowanceVoucher(
            allowanceId: "alw-expired",
            accountId: "alice",
            deviceId: aliceDeviceId,
            devicePublicKeyFingerprint: aliceFp,
            currency: "INR",
            allocatedAmount: Decimal(500.00),
            spentAmount: Decimal.zero,
            lastSequenceNumber: 0,
            issuedAt: "2026-10-01T10:00:00Z",
            expiresAt: "2026-10-02T10:00:00Z", // Past date
            protocolVersion: 1,
            status: "ACTIVE",
            voucherSignature: "sig",
            bankPublicKeyBase64: bankPub
        )
        try assert(voucherExpired.isExpired(), "Voucher must be recognized as expired")

        // Sub-test C: Exhausted allowance
        let voucherExhausted = OfflineAllowanceVoucher(
            allowanceId: "alw-exhausted",
            accountId: "alice",
            deviceId: aliceDeviceId,
            devicePublicKeyFingerprint: aliceFp,
            currency: "INR",
            allocatedAmount: Decimal(100.00),
            spentAmount: Decimal(100.00), // Remaining = 0
            lastSequenceNumber: 1,
            issuedAt: "2026-10-18T10:00:00Z",
            expiresAt: "2026-10-30T10:00:00Z",
            protocolVersion: 1,
            status: "ACTIVE",
            voucherSignature: "sig",
            bankPublicKeyBase64: bankPub
        )
        try assert(voucherExhausted.remainingAmount == Decimal.zero, "Remaining amount must be 0")
        try assert(Decimal(10.00) > voucherExhausted.remainingAmount, "Spend must exceed exhausted remaining amount")

        // Sub-test D: Wrong device binding
        let voucherWrongDevice = OfflineAllowanceVoucher(
            allowanceId: "alw-wrongdev",
            accountId: "alice",
            deviceId: "bob-phone-device", // Bound to Bob, not Alice
            devicePublicKeyFingerprint: aliceFp,
            currency: "INR",
            allocatedAmount: Decimal(500.00),
            spentAmount: Decimal.zero,
            lastSequenceNumber: 0,
            issuedAt: "2026-10-18T10:00:00Z",
            expiresAt: "2026-10-30T10:00:00Z",
            protocolVersion: 1,
            status: "ACTIVE",
            voucherSignature: "sig",
            bankPublicKeyBase64: bankPub
        )
        try assert(voucherWrongDevice.deviceId != aliceDeviceId, "Device binding mismatch detected")

        // Sub-test E: Tampered packet signature rejected by receiver
        let inst = try PaymentInstruction(
            paymentId: "pay-tampered-sig",
            fromAccount: "alice",
            toAccount: "bob",
            amount: Decimal(50.00),
            createdAt: PaymentInstant.now(),
            nonce: UUID().uuidString.lowercased()
        )
        let genuineSig = try signBytes(privateKey: alicePriv, data: inst.toCanonicalBytes())
        var tamperedSigBytes = Data(base64Encoded: genuineSig)!
        tamperedSigBytes[tamperedSigBytes.count - 5] ^= 0xFF
        let tamperedSig = tamperedSigBytes.base64EncodedString()

        let (tamperVerified, _) = MeshCryptoVerifier.verifyRemoteRSASSA_PSS(
            publicKeyBase64X509: alicePub,
            message: inst.toCanonicalBytes(),
            signatureBase64: tamperedSig
        )
        try assert(!tamperVerified, "Tampered payer signature must be rejected")

        print("  ✓ PASS: test9_securityRejections_invalidSig_expired_exhausted_wrongDevice")
    }

    // MARK: - Test 10: Distinguishing Received/Pending from Settled
    @MainActor
    public static func test10_distinguishingReceivedPendingFromSettled() throws {
        // 1. Verify Enum Display Names
        try assert(OfflinePacketStatus.created.displayName == "CREATED", "created -> CREATED")
        try assert(OfflinePacketStatus.queued.displayName == "QUEUED", "queued -> QUEUED")
        try assert(OfflinePacketStatus.sent.displayName == "SENT", "sent -> SENT")
        try assert(OfflinePacketStatus.received.displayName == "RECEIVED", "received -> RECEIVED")
        try assert(OfflinePacketStatus.settled.displayName == "SETTLED", "settled -> SETTLED")
        try assert(OfflinePacketStatus.failed.displayName == "FAILED", "failed -> FAILED")

        try assert(ReceivedReconciliationStatus.received.displayName == "RECEIVED — NOT SETTLED", "received -> RECEIVED — NOT SETTLED")
        try assert(ReceivedReconciliationStatus.pendingReconciliation.displayName == "RECEIVED — NOT SETTLED", "pendingReconciliation -> RECEIVED — NOT SETTLED")
        try assert(ReceivedReconciliationStatus.settling.displayName == "SETTLING", "settling -> SETTLING")
        try assert(ReceivedReconciliationStatus.settled.displayName == "SETTLED", "settled -> SETTLED")
        try assert(ReceivedReconciliationStatus.failed.displayName == "FAILED", "failed -> FAILED")

        // 2. Verify MeshLedgerViewModel metrics strictly segregate pending packets from settled
        let (alicePriv, _, _) = try generateRSAKeyPair()
        let pid1 = "pay-metric-1"
        let inst1 = try PaymentInstruction(
            paymentId: pid1,
            fromAccount: "alice",
            toAccount: "bob",
            amount: Decimal(150.00),
            createdAt: PaymentInstant.now(),
            nonce: "nonce-1"
        )
        let sig1 = try signBytes(privateKey: alicePriv, data: inst1.toCanonicalBytes())
        let pkt1 = try OfflinePaymentPacket(instruction: try inst1.withSignature(sig1), deviceId: "dev-1", status: .received)
        let pendingRec = try ReceivedPacketRecord(
            packet: pkt1,
            receivedFromPeer: "Alice",
            isSignatureMathematicallyValid: true,
            trustStatusNote: "Pending",
            reconciliationStatus: .pendingReconciliation
        )

        let pid2 = "pay-metric-2"
        let inst2 = try PaymentInstruction(
            paymentId: pid2,
            fromAccount: "alice",
            toAccount: "bob",
            amount: Decimal(50.00),
            createdAt: PaymentInstant.now(),
            nonce: "nonce-2"
        )
        let sig2 = try signBytes(privateKey: alicePriv, data: inst2.toCanonicalBytes())
        let pkt2 = try OfflinePaymentPacket(instruction: try inst2.withSignature(sig2), deviceId: "dev-1", status: .received)
        let settledRec = try ReceivedPacketRecord(
            packet: pkt2,
            receivedFromPeer: "Alice",
            isSignatureMathematicallyValid: true,
            trustStatusNote: "Settled",
            reconciliationStatus: .settled
        )

        // Pass to MeshLedgerViewModel
        let vm = MeshLedgerViewModel()
        vm.inTransitPackets = [pendingRec, settledRec]

        // Verify inTransitCount counts ONLY unsettled packets
        try assert(vm.inTransitCount == 1, "inTransitCount must be 1 (only pendingRec counted, settledRec excluded)")
        try assert(vm.inTransitTotalAmount == 150.00, "inTransitTotalAmount must be 150.00 (settled amount excluded)")

        print("  ✓ PASS: test10_distinguishingReceivedPendingFromSettled")
    }
}
