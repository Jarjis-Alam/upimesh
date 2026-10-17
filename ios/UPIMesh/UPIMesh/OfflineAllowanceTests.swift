import Foundation
import Security
import CryptoKit

/// Comprehensive test suite validating Phase 2B iOS/macOS client integration
/// for allowance-backed offline payments, byte-level canonical serialization parity,
/// cryptographic signing, voucher verification, monotonic sequence tracking,
/// overspend prevention, duplicate protection, and bridge reconciliation.
public final class OfflineAllowanceTests {

    public static func runAllTests() async throws {
        print("=== Running OfflineAllowanceTests (13 tests) ===")
        try testCanonicalVoucherAndSpend_byteParityWithJavaTestVector()
        try testPayerSignature_signAndVerify()
        try testBankAuthorityVoucherSignature_trustedKeyVsUntrustedKey()
        try testAllowanceMonotonicSequenceAndCumulativeProgression()
        try testAllowanceExhaustion_preventOverspend()
        try testAllowanceExpiry_blocksNewSpends()
        try testAllowancePacketCreationAndStorageInvariance()
        try testDuplicatePacketDeliveryProtection()
        try testMalformedAllowancePacketRejection()
        try await testAllowanceReconciliation_settlementSuccess()
        try await testAllowanceReconciliation_terminalSecurityRejection()
        try await testAllowanceReconciliation_networkFailureLeavesRetryable()
        try await testMacCompanion_allowancePacketVerificationAndReconciliation()
        print("=== OfflineAllowanceTests: All 13 passed cleanly! ===")
    }

    private static func assert(_ condition: Bool, _ message: String) throws {
        if !condition {
            print("  ✗ FAIL: \(message)")
            throw NSError(domain: "OfflineAllowanceTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    // MARK: - Helpers

    private static func generateTestRSAKeyPair() throws -> (privateKey: SecKey, publicKeyBase64X509: String, fingerprint: String) {
        let keyAttrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048
        ]
        var error: Unmanaged<CFError>?
        guard let priv = SecKeyCreateRandomKey(keyAttrs as CFDictionary, &error),
              let pub = SecKeyCopyPublicKey(priv),
              let pkcs1 = SecKeyCopyExternalRepresentation(pub, &error) as Data? else {
            let desc = error?.takeRetainedValue().localizedDescription ?? "Key generation failed"
            throw NSError(domain: "KeyGen", code: 1, userInfo: [NSLocalizedDescriptionKey: desc])
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

    // MARK: - Test 1: Byte-For-Byte Parity with Java Shared Test Vector
    public static func testCanonicalVoucherAndSpend_byteParityWithJavaTestVector() throws {
        // 1. Voucher Canonical Vector
        let voucherBytes = OfflineAllowanceVoucher.buildCanonicalVoucherBytes(
            allowanceId: "alw-test-voucher-001",
            accountId: "alice",
            deviceId: "iphone-test-device",
            deviceFingerprint: "sha256:abc123def456",
            currency: "INR",
            allocatedAmount: Decimal(500.00),
            issuedAt: "2026-10-15T10:00:00Z",
            expiresAt: "2026-10-16T10:00:00Z",
            protocolVersion: 1
        )

        let expectedVoucherCanonicalString =
            "UPI-MESH-ALLOWANCE-V1\n" +
            "allowanceId:20:alw-test-voucher-001\n" +
            "accountId:5:alice\n" +
            "deviceId:18:iphone-test-device\n" +
            "deviceFingerprint:19:sha256:abc123def456\n" +
            "currency:3:INR\n" +
            "allocatedAmount:6:500.00\n" +
            "issuedAt:20:2026-10-15T10:00:00Z\n" +
            "expiresAt:20:2026-10-16T10:00:00Z\n" +
            "version:1:1\n"

        let actualVoucherString = String(data: voucherBytes, encoding: .utf8)
        try assert(actualVoucherString == expectedVoucherCanonicalString, "Voucher canonical string must match Java shared vector exactly")
        try assert(voucherBytes.count == expectedVoucherCanonicalString.utf8.count, "Voucher byte length must match Java byte-for-byte")

        // 2. Spend Canonical Vector
        let spendBytes = OfflineSpendRecord.buildCanonicalSpendBytes(
            allowanceId: "alw-test-voucher-001",
            paymentId: "pay-test-spend-999",
            payerAccountId: "alice",
            payerDeviceId: "iphone-test-device",
            recipientAccountId: "bob",
            amount: Decimal(75.50),
            currency: "INR",
            sequenceNumber: 1,
            cumulativeSpentAmount: Decimal(75.50),
            createdAt: "2026-10-15T11:30:00Z",
            voucherSignature: "VOUCHER_SIG_BASE64_PLACEHOLDER",
            protocolVersion: 1
        )

        let expectedSpendCanonicalString =
            "UPI-MESH-SPEND-V1\n" +
            "allowanceId:20:alw-test-voucher-001\n" +
            "paymentId:18:pay-test-spend-999\n" +
            "payerAccountId:5:alice\n" +
            "payerDeviceId:18:iphone-test-device\n" +
            "recipientAccountId:3:bob\n" +
            "currency:3:INR\n" +
            "amount:5:75.50\n" +
            "sequenceNumber:1:1\n" +
            "cumulativeSpentAmount:5:75.50\n" +
            "createdAt:20:2026-10-15T11:30:00Z\n" +
            "voucherSignature:30:VOUCHER_SIG_BASE64_PLACEHOLDER\n" +
            "version:1:1\n"

        let actualSpendString = String(data: spendBytes, encoding: .utf8)
        try assert(actualSpendString == expectedSpendCanonicalString, "Spend canonical string must match Java shared vector exactly")
        try assert(spendBytes.count == expectedSpendCanonicalString.utf8.count, "Spend byte length must match Java byte-for-byte")

        print("  ✓ PASS: testCanonicalVoucherAndSpend_byteParityWithJavaTestVector")
    }

    // MARK: - Test 2: Payer Signature Generation and Mathematical Verification
    public static func testPayerSignature_signAndVerify() throws {
        let (payerPriv, payerPubBase64, _) = try generateTestRSAKeyPair()

        let canonicalBytes = OfflineSpendRecord.buildCanonicalSpendBytes(
            allowanceId: "alw-123",
            paymentId: "pay-456",
            payerAccountId: "alice",
            payerDeviceId: "alice-device",
            recipientAccountId: "bob",
            amount: Decimal(50.00),
            currency: "INR",
            sequenceNumber: 1,
            cumulativeSpentAmount: Decimal(50.00),
            createdAt: "2026-10-15T12:00:00Z",
            voucherSignature: "mock-voucher-sig",
            protocolVersion: 1
        )

        let payerSig = try signBytes(privateKey: payerPriv, data: canonicalBytes)

        let record = OfflineSpendRecord(
            allowanceId: "alw-123",
            paymentId: "pay-456",
            payerAccountId: "alice",
            payerDeviceId: "alice-device",
            recipientAccountId: "bob",
            amount: Decimal(50.00),
            currency: "INR",
            sequenceNumber: 1,
            cumulativeSpentAmount: Decimal(50.00),
            createdAt: "2026-10-15T12:00:00Z",
            voucherSignature: "mock-voucher-sig",
            payerSignature: payerSig,
            protocolVersion: 1
        )

        // Mathematical verification against genuine key
        let (valid, err) = record.verifyPayerSignature(payerPublicKeyBase64X509: payerPubBase64)
        try assert(valid, "Payer signature must verify mathematically: \(err ?? "")")

        // Verification against wrong key must fail
        let (_, wrongPubBase64, _) = try generateTestRSAKeyPair()
        let (wrongValid, _) = record.verifyPayerSignature(payerPublicKeyBase64X509: wrongPubBase64)
        try assert(!wrongValid, "Payer signature verification against mismatched key must fail")

        print("  ✓ PASS: testPayerSignature_signAndVerify")
    }

    // MARK: - Test 3: Bank Authority Voucher Signature & Untrusted Key Protection
    public static func testBankAuthorityVoucherSignature_trustedKeyVsUntrustedKey() throws {
        let (bankPriv, bankPubBase64, _) = try generateTestRSAKeyPair()
        let (attackerPriv, attackerPubBase64, _) = try generateTestRSAKeyPair()

        let voucherCanonicalBytes = OfflineAllowanceVoucher.buildCanonicalVoucherBytes(
            allowanceId: "alw-bank-001",
            accountId: "alice",
            deviceId: "alice-device",
            deviceFingerprint: "sha256:fingerprint",
            currency: "INR",
            allocatedAmount: Decimal(1000.00),
            issuedAt: "2026-10-15T10:00:00Z",
            expiresAt: "2026-10-16T10:00:00Z",
            protocolVersion: 1
        )

        let bankSignature = try signBytes(privateKey: bankPriv, data: voucherCanonicalBytes)

        let voucher = OfflineAllowanceVoucher(
            allowanceId: "alw-bank-001",
            accountId: "alice",
            deviceId: "alice-device",
            devicePublicKeyFingerprint: "sha256:fingerprint",
            currency: "INR",
            allocatedAmount: Decimal(1000.00),
            issuedAt: "2026-10-15T10:00:00Z",
            expiresAt: "2026-10-16T10:00:00Z",
            protocolVersion: 1,
            status: "ACTIVE",
            voucherSignature: bankSignature,
            bankPublicKeyBase64: bankPubBase64
        )

        // 1. Verify against trusted pinned bank key -> SUCCESS
        let (trustedValid, err) = voucher.verifyBankSignature(trustedBankPublicKeyBase64: bankPubBase64)
        try assert(trustedValid, "Trusted bank key verification must succeed: \(err ?? "")")

        // 2. Untrusted key check: attacker key cannot verify genuine bank signature
        let (attackerValid, _) = voucher.verifyBankSignature(trustedBankPublicKeyBase64: attackerPubBase64)
        try assert(!attackerValid, "Untrusted attacker public key must be rejected")

        // 3. Forged voucher signed with attacker key rejected by trusted bank key
        let attackerSignature = try signBytes(privateKey: attackerPriv, data: voucherCanonicalBytes)
        let forgedVoucher = OfflineAllowanceVoucher(
            allowanceId: "alw-bank-001",
            accountId: "alice",
            deviceId: "alice-device",
            devicePublicKeyFingerprint: "sha256:fingerprint",
            currency: "INR",
            allocatedAmount: Decimal(1000.00),
            issuedAt: "2026-10-15T10:00:00Z",
            expiresAt: "2026-10-16T10:00:00Z",
            protocolVersion: 1,
            status: "ACTIVE",
            voucherSignature: attackerSignature,
            bankPublicKeyBase64: attackerPubBase64
        )
        let (forgedValid, _) = forgedVoucher.verifyBankSignature(trustedBankPublicKeyBase64: bankPubBase64)
        try assert(!forgedValid, "Voucher signed by untrusted attacker must not verify against trusted bank authority key")

        print("  ✓ PASS: testBankAuthorityVoucherSignature_trustedKeyVsUntrustedKey")
    }

    // MARK: - Test 4: Monotonic Sequence & Cumulative Spent Progression
    public static func testAllowanceMonotonicSequenceAndCumulativeProgression() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let packetStore = OfflinePacketStore(fileURL: tempDir.appendingPathComponent("packets.json"))
        let identityManager = DeviceIdentityManager(
            keyTag: "test.allowance.\(UUID().uuidString)",
            serviceName: "test.service.\(UUID().uuidString)",
            deviceIdAccount: "testDev"
        )
        defer { try? identityManager.deleteIdentity() }
        let identity = try identityManager.getOrCreateIdentity()

        let (bankPriv, bankPub, _) = try generateTestRSAKeyPair()
        let canonicalVoucher = OfflineAllowanceVoucher.buildCanonicalVoucherBytes(
            allowanceId: "alw-seq-test",
            accountId: "alice",
            deviceId: identity.deviceId,
            deviceFingerprint: identity.publicKeyFingerprint,
            currency: "INR",
            allocatedAmount: Decimal(1000.00),
            issuedAt: "2026-10-15T10:00:00Z",
            expiresAt: "2026-10-30T10:00:00Z",
            protocolVersion: 1
        )
        let bankSig = try signBytes(privateKey: bankPriv, data: canonicalVoucher)

        let voucher = OfflineAllowanceVoucher(
            allowanceId: "alw-seq-test",
            accountId: "alice",
            deviceId: identity.deviceId,
            devicePublicKeyFingerprint: identity.publicKeyFingerprint,
            currency: "INR",
            allocatedAmount: Decimal(1000.00),
            spentAmount: Decimal.zero,
            lastSequenceNumber: 0,
            issuedAt: "2026-10-15T10:00:00Z",
            expiresAt: "2026-10-30T10:00:00Z",
            protocolVersion: 1,
            status: "ACTIVE",
            voucherSignature: bankSig,
            bankPublicKeyBase64: bankPub
        )

        let manager = OfflineAllowanceManager.shared
        try manager.saveActiveVoucher(voucher)
        defer { try? manager.clearActiveVoucher() }

        // Spend 1: ₹100.00 -> Seq 1, Cumulative 100.00, Remaining 900.00
        let p1 = try manager.createAndQueueAllowanceSpend(
            toAccount: "bob",
            amount: Decimal(100.00),
            packetStore: packetStore,
            identityManager: identityManager
        )
        try assert(p1.allowanceSpend?.sequenceNumber == 1, "Spend 1 must have sequence 1")
        try assert(p1.allowanceSpend?.cumulativeSpentAmount == Decimal(100.00), "Cumulative spend 1 must be 100.00")
        try assert(manager.getActiveVoucher()?.remainingAmount == Decimal(900.00), "Remaining must be 900.00")

        // Spend 2: ₹250.00 -> Seq 2, Cumulative 350.00, Remaining 650.00
        let p2 = try manager.createAndQueueAllowanceSpend(
            toAccount: "carol",
            amount: Decimal(250.00),
            packetStore: packetStore,
            identityManager: identityManager
        )
        try assert(p2.allowanceSpend?.sequenceNumber == 2, "Spend 2 must have sequence 2")
        try assert(p2.allowanceSpend?.cumulativeSpentAmount == Decimal(350.00), "Cumulative spend 2 must be 350.00")
        try assert(manager.getActiveVoucher()?.remainingAmount == Decimal(650.00), "Remaining must be 650.00")

        // Spend 3: ₹150.00 -> Seq 3, Cumulative 500.00, Remaining 500.00
        let p3 = try manager.createAndQueueAllowanceSpend(
            toAccount: "bob",
            amount: Decimal(150.00),
            packetStore: packetStore,
            identityManager: identityManager
        )
        try assert(p3.allowanceSpend?.sequenceNumber == 3, "Spend 3 must have sequence 3")
        try assert(p3.allowanceSpend?.cumulativeSpentAmount == Decimal(500.00), "Cumulative spend 3 must be 500.00")
        try assert(manager.getActiveVoucher()?.remainingAmount == Decimal(500.00), "Remaining must be 500.00")

        // Assert all 3 packets are stored in local store
        let storedPackets = packetStore.getAll()
        try assert(storedPackets.count == 3, "Packet store must have exactly 3 packets")

        print("  ✓ PASS: testAllowanceMonotonicSequenceAndCumulativeProgression")
    }

    // MARK: - Test 5: Overspend Prevention (Allowance Exhaustion)
    public static func testAllowanceExhaustion_preventOverspend() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let packetStore = OfflinePacketStore(fileURL: tempDir.appendingPathComponent("packets.json"))
        let identityManager = DeviceIdentityManager(
            keyTag: "test.exhaustion.\(UUID().uuidString)",
            serviceName: "test.service.\(UUID().uuidString)",
            deviceIdAccount: "testDev"
        )
        defer { try? identityManager.deleteIdentity() }
        let identity = try identityManager.getOrCreateIdentity()

        let voucher = OfflineAllowanceVoucher(
            allowanceId: "alw-exhaust-test",
            accountId: "alice",
            deviceId: identity.deviceId,
            devicePublicKeyFingerprint: identity.publicKeyFingerprint,
            currency: "INR",
            allocatedAmount: Decimal(100.00),
            spentAmount: Decimal(80.00),
            lastSequenceNumber: 2,
            issuedAt: "2026-10-15T10:00:00Z",
            expiresAt: "2026-10-30T10:00:00Z",
            protocolVersion: 1,
            status: "ACTIVE",
            voucherSignature: "mock-sig"
        )

        let manager = OfflineAllowanceManager.shared
        try manager.saveActiveVoucher(voucher)
        defer { try? manager.clearActiveVoucher() }

        // Attempting to spend ₹25.00 against remaining ₹20.00 -> BLOCKED
        do {
            _ = try manager.createAndQueueAllowanceSpend(
                toAccount: "bob",
                amount: Decimal(25.00),
                packetStore: packetStore,
                identityManager: identityManager
            )
            try assert(false, "Should have thrown insufficientAllowance")
        } catch OfflineAllowanceError.insufficientAllowance(let remaining, let requested) {
            try assert(remaining == Decimal(20.00), "Remaining should be 20.00")
            try assert(requested == Decimal(25.00), "Requested should be 25.00")
        }

        // Sequence number and cumulative spend MUST NOT be advanced on rejection
        let currentVoucher = manager.getActiveVoucher()
        try assert(currentVoucher?.lastSequenceNumber == 2, "Sequence number must remain 2")
        try assert(currentVoucher?.spentAmount == Decimal(80.00), "Spent amount must remain 80.00")
        try assert(packetStore.getAll().isEmpty, "No packet should be stored on rejected overspend")

        print("  ✓ PASS: testAllowanceExhaustion_preventOverspend")
    }

    // MARK: - Test 6: Expiry Detection
    public static func testAllowanceExpiry_blocksNewSpends() throws {
        let voucher = OfflineAllowanceVoucher(
            allowanceId: "alw-exp-test",
            accountId: "alice",
            deviceId: "dev-1",
            devicePublicKeyFingerprint: "fp-1",
            currency: "INR",
            allocatedAmount: Decimal(500.00),
            spentAmount: Decimal.zero,
            lastSequenceNumber: 0,
            issuedAt: "2026-10-14T10:00:00Z",
            expiresAt: "2026-10-15T10:00:00Z",
            protocolVersion: 1,
            status: "ACTIVE",
            voucherSignature: "sig"
        )

        let beforeExpiry = ISO8601DateFormatter().date(from: "2026-10-15T09:59:59Z")!
        let afterExpiry = ISO8601DateFormatter().date(from: "2026-10-15T10:00:01Z")!

        try assert(!voucher.isExpired(at: beforeExpiry), "Voucher must not be expired before expiry timestamp")
        try assert(voucher.isExpired(at: afterExpiry), "Voucher must be expired after expiry timestamp")

        print("  ✓ PASS: testAllowanceExpiry_blocksNewSpends")
    }

    // MARK: - Test 7: Packet Invariance & No Private Key Leakage
    public static func testAllowancePacketCreationAndStorageInvariance() throws {
        _ = try generateTestRSAKeyPair()
        let spend = OfflineSpendRecord(
            allowanceId: "alw-invar-01",
            paymentId: "pay-invar-01",
            payerAccountId: "alice",
            payerDeviceId: "dev-invar-01",
            recipientAccountId: "bob",
            amount: Decimal(150.00),
            currency: "INR",
            sequenceNumber: 1,
            cumulativeSpentAmount: Decimal(150.00),
            createdAt: "2026-10-15T12:00:00Z",
            voucherSignature: "voucher-sig-mock",
            payerSignature: "payer-sig-mock",
            protocolVersion: 1
        )

        let instruction = try PaymentInstruction(
            paymentId: "pay-invar-01",
            fromAccount: "alice",
            toAccount: "bob",
            amount: Decimal(150.00),
            createdAt: PaymentInstant.now(),
            nonce: "nonce-123",
            signature: "sig-123"
        )

        let packet = try OfflinePaymentPacket(
            instruction: instruction,
            deviceId: "dev-invar-01",
            status: .queued,
            allowanceSpend: spend
        )

        try assert(packet.isAllowanceBacked, "Packet must identify as allowance-backed")
        try assert(packet.allowanceSpend?.paymentId == packet.paymentId, "Spend paymentId must match packet")

        // JSON Serialization Round-Trip
        let encoder = JSONEncoder()
        let data = try encoder.encode(packet)
        let jsonStr = String(data: data, encoding: .utf8)!

        try assert(!jsonStr.contains("private"), "JSON must never expose private key materials")
        try assert(!jsonStr.contains("kSecAttr"), "JSON must never expose keychain attributes")

        let decoded = try JSONDecoder().decode(OfflinePaymentPacket.self, from: data)
        try assert(decoded.isAllowanceBacked, "Decoded packet must remain allowance-backed")
        try assert(decoded.allowanceSpend == spend, "Decoded spend record must match original")

        print("  ✓ PASS: testAllowancePacketCreationAndStorageInvariance")
    }

    // MARK: - Test 8: Duplicate Packet Delivery Protection
    public static func testDuplicatePacketDeliveryProtection() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = ReceivedPacketStore(fileURL: tempDir.appendingPathComponent("received.json"))
        let instruction = try PaymentInstruction(
            paymentId: "dup-test-001",
            fromAccount: "alice",
            toAccount: "bob",
            amount: Decimal(100.00),
            createdAt: PaymentInstant.now(),
            nonce: "nonce-1"
        )
        let signedInst = try instruction.withSignature("sig-1")
        let packet = try OfflinePaymentPacket(instruction: signedInst, deviceId: "dev-1", status: .received)

        let record = try ReceivedPacketRecord(
            packet: packet,
            receivedFromPeer: "Alice iPhone",
            isSignatureMathematicallyValid: true,
            isSenderIdentityAuthenticated: false,
            trustStatusNote: "Verified"
        )

        try store.save(record)
        try assert(store.count == 1, "Store count should be 1")

        // Duplicate delivery rejected
        do {
            try store.save(record)
            try assert(false, "Duplicate packet save must throw error")
        } catch ReceivedPacketStoreError.duplicatePacketId(let id) {
            try assert(id == "dup-test-001", "Duplicate error must match paymentId")
        }

        print("  ✓ PASS: testDuplicatePacketDeliveryProtection")
    }

    // MARK: - Test 9: Malformed Packet Rejection
    public static func testMalformedAllowancePacketRejection() throws {
        let instruction = try PaymentInstruction(
            paymentId: "id-alpha",
            fromAccount: "alice",
            toAccount: "bob",
            amount: Decimal(100.00),
            createdAt: PaymentInstant.now(),
            nonce: "nonce"
        )
        let signedInst = try instruction.withSignature("sig")

        // 1. Mismatched paymentId between instruction and spend record
        let mismatchedSpendId = OfflineSpendRecord(
            allowanceId: "alw-1",
            paymentId: "id-beta", // DIFFERENT
            payerAccountId: "alice",
            payerDeviceId: "dev-1",
            recipientAccountId: "bob",
            amount: Decimal(100.00),
            currency: "INR",
            sequenceNumber: 1,
            cumulativeSpentAmount: Decimal(100.00),
            createdAt: "2026-10-15T10:00:00Z",
            voucherSignature: "vsig",
            payerSignature: "psig"
        )

        do {
            _ = try OfflinePaymentPacket(
                instruction: signedInst,
                deviceId: "dev-1",
                allowanceSpend: mismatchedSpendId
            )
            try assert(false, "Mismatched paymentId must be rejected")
        } catch OfflinePaymentPacketError.mismatchedInstructionField {
            // Expected
        }

        // 2. Mismatched amount
        let mismatchedSpendAmount = OfflineSpendRecord(
            allowanceId: "alw-1",
            paymentId: "id-alpha",
            payerAccountId: "alice",
            payerDeviceId: "dev-1",
            recipientAccountId: "bob",
            amount: Decimal(200.00), // DIFFERENT FROM 100.00
            currency: "INR",
            sequenceNumber: 1,
            cumulativeSpentAmount: Decimal(200.00),
            createdAt: "2026-10-15T10:00:00Z",
            voucherSignature: "vsig",
            payerSignature: "psig"
        )

        do {
            _ = try OfflinePaymentPacket(
                instruction: signedInst,
                deviceId: "dev-1",
                allowanceSpend: mismatchedSpendAmount
            )
            try assert(false, "Mismatched spend amount must be rejected")
        } catch OfflinePaymentPacketError.mismatchedInstructionField {
            // Expected
        }

        print("  ✓ PASS: testMalformedAllowancePacketRejection")
    }

    // MARK: - Test 10: Reconciliation Settlement Success
    public static func testAllowanceReconciliation_settlementSuccess() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = ReceivedPacketStore(fileURL: tempDir.appendingPathComponent("received.json"))
        let paymentId = "recon-success-01"

        let spend = OfflineSpendRecord(
            allowanceId: "alw-recon-01",
            paymentId: paymentId,
            payerAccountId: "alice",
            payerDeviceId: "dev-01",
            recipientAccountId: "bob",
            amount: Decimal(50.00),
            sequenceNumber: 1,
            cumulativeSpentAmount: Decimal(50.00),
            createdAt: "2026-10-15T10:00:00Z",
            voucherSignature: "vsig",
            payerSignature: "psig"
        )

        let instruction = try PaymentInstruction(
            paymentId: paymentId,
            fromAccount: "alice",
            toAccount: "bob",
            amount: Decimal(50.00),
            createdAt: PaymentInstant.now(),
            nonce: "nonce"
        )
        let signedInst = try instruction.withSignature("sig")
        let packet = try OfflinePaymentPacket(instruction: signedInst, deviceId: "dev-01", status: .received, allowanceSpend: spend)
        let record = try ReceivedPacketRecord(
            packet: packet,
            receivedFromPeer: "Peer",
            isSignatureMathematicallyValid: true,
            isSenderIdentityAuthenticated: false,
            trustStatusNote: "Valid"
        )
        try store.save(record)

        let mockApi = MockAllowancePaymentSubmitter(
            spendResponseToReturn: OfflineSpendPaymentDTO(
                paymentId: paymentId,
                allowanceId: "alw-recon-01",
                payerAccountId: "alice",
                payerDeviceId: "dev-01",
                recipientAccountId: "bob",
                amount: Decimal(50.00),
                currency: "INR",
                sequenceNumber: 1,
                cumulativeSpentAmount: Decimal(50.00),
                status: "SETTLED"
            )
        )

        let service = OfflineReconciliationService(packetStore: store, apiClient: mockApi)
        let outcome = await service.reconcile(paymentId: paymentId)

        switch outcome {
        case .settled(let id, _):
            try assert(id == paymentId, "Settled ID must match")
        default:
            try assert(false, "Expected .settled outcome, got \(outcome)")
        }

        let updatedRecord = store.get(paymentId: paymentId)
        try assert(updatedRecord?.reconciliationStatus == .settled, "Record reconciliationStatus must be settled")

        print("  ✓ PASS: testAllowanceReconciliation_settlementSuccess")
    }

    // MARK: - Test 11: Reconciliation Terminal Security Rejection
    public static func testAllowanceReconciliation_terminalSecurityRejection() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = ReceivedPacketStore(fileURL: tempDir.appendingPathComponent("received.json"))
        let paymentId = "recon-reject-01"

        let spend = OfflineSpendRecord(
            allowanceId: "alw-recon-01",
            paymentId: paymentId,
            payerAccountId: "alice",
            payerDeviceId: "dev-01",
            recipientAccountId: "bob",
            amount: Decimal(50.00),
            sequenceNumber: 1,
            cumulativeSpentAmount: Decimal(50.00),
            createdAt: "2026-10-15T10:00:00Z",
            voucherSignature: "vsig",
            payerSignature: "psig"
        )

        let instruction = try PaymentInstruction(
            paymentId: paymentId,
            fromAccount: "alice",
            toAccount: "bob",
            amount: Decimal(50.00),
            createdAt: PaymentInstant.now(),
            nonce: "nonce"
        )
        let signedInst = try instruction.withSignature("sig")
        let packet = try OfflinePaymentPacket(instruction: signedInst, deviceId: "dev-01", status: .received, allowanceSpend: spend)
        let record = try ReceivedPacketRecord(
            packet: packet,
            receivedFromPeer: "Peer",
            isSignatureMathematicallyValid: true,
            isSenderIdentityAuthenticated: false,
            trustStatusNote: "Valid"
        )
        try store.save(record)

        let mockApi = MockAllowancePaymentSubmitter(
            errorToThrow: APIError.allowanceError("Security Event: sequence fork detected for allowance alw-recon-01")
        )

        let service = OfflineReconciliationService(packetStore: store, apiClient: mockApi)
        let outcome = await service.reconcile(paymentId: paymentId)

        switch outcome {
        case .rejected(let id, let reason):
            try assert(id == paymentId, "Rejected payment ID must match")
            try assert(reason.contains("sequence fork detected"), "Reason must identify sequence fork")
        default:
            try assert(false, "Expected .rejected outcome, got \(outcome)")
        }

        let updatedRecord = store.get(paymentId: paymentId)
        try assert(updatedRecord?.reconciliationStatus == .failed, "Store record must be updated to .failed")
        try assert(updatedRecord?.failureReason?.contains("sequence fork") == true, "Failure reason must be persisted")

        print("  ✓ PASS: testAllowanceReconciliation_terminalSecurityRejection")
    }

    // MARK: - Test 12: Network Failure Leaves Retryable State
    public static func testAllowanceReconciliation_networkFailureLeavesRetryable() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = ReceivedPacketStore(fileURL: tempDir.appendingPathComponent("received.json"))
        let paymentId = "recon-netfail-01"

        let spend = OfflineSpendRecord(
            allowanceId: "alw-recon-01",
            paymentId: paymentId,
            payerAccountId: "alice",
            payerDeviceId: "dev-01",
            recipientAccountId: "bob",
            amount: Decimal(50.00),
            sequenceNumber: 1,
            cumulativeSpentAmount: Decimal(50.00),
            createdAt: "2026-10-15T10:00:00Z",
            voucherSignature: "vsig",
            payerSignature: "psig"
        )

        let instruction = try PaymentInstruction(
            paymentId: paymentId,
            fromAccount: "alice",
            toAccount: "bob",
            amount: Decimal(50.00),
            createdAt: PaymentInstant.now(),
            nonce: "nonce"
        )
        let signedInst = try instruction.withSignature("sig")
        let packet = try OfflinePaymentPacket(instruction: signedInst, deviceId: "dev-01", status: .received, allowanceSpend: spend)
        let record = try ReceivedPacketRecord(
            packet: packet,
            receivedFromPeer: "Peer",
            isSignatureMathematicallyValid: true,
            isSenderIdentityAuthenticated: false,
            trustStatusNote: "Valid"
        )
        try store.save(record)

        let mockApi = MockAllowancePaymentSubmitter(
            errorToThrow: APIError.networkError("The request timed out.")
        )

        let service = OfflineReconciliationService(packetStore: store, apiClient: mockApi)
        let outcome = await service.reconcile(paymentId: paymentId)

        switch outcome {
        case .retryable(let id, let reason):
            try assert(id == paymentId, "Retryable payment ID must match")
            try assert(reason.contains("timed out"), "Reason must mention timeout")
        default:
            try assert(false, "Expected .retryable outcome, got \(outcome)")
        }

        let updatedRecord = store.get(paymentId: paymentId)
        try assert(updatedRecord?.reconciliationStatus == .settling, "Network timeout must leave packet in retryable settling state, not failed")

        print("  ✓ PASS: testAllowanceReconciliation_networkFailureLeavesRetryable")
    }

    // MARK: - Test 13: Received Store Allowance Packet Lifecycle
    public static func testMacCompanion_allowancePacketVerificationAndReconciliation() async throws {
        let (payerPriv, payerPub, _) = try generateTestRSAKeyPair()
        let paymentId = "mac-test-alw-01"

        let canonicalSpend = OfflineSpendRecord.buildCanonicalSpendBytes(
            allowanceId: "alw-mac-01",
            paymentId: paymentId,
            payerAccountId: "alice",
            payerDeviceId: "iphone-peer",
            recipientAccountId: "carol",
            amount: Decimal(120.00),
            currency: "INR",
            sequenceNumber: 1,
            cumulativeSpentAmount: Decimal(120.00),
            createdAt: "2026-10-15T10:00:00Z",
            voucherSignature: "voucher-sig-mock",
            protocolVersion: 1
        )
        let payerSig = try signBytes(privateKey: payerPriv, data: canonicalSpend)

        let spend = OfflineSpendRecord(
            allowanceId: "alw-mac-01",
            paymentId: paymentId,
            payerAccountId: "alice",
            payerDeviceId: "iphone-peer",
            recipientAccountId: "carol",
            amount: Decimal(120.00),
            currency: "INR",
            sequenceNumber: 1,
            cumulativeSpentAmount: Decimal(120.00),
            createdAt: "2026-10-15T10:00:00Z",
            voucherSignature: "voucher-sig-mock",
            payerSignature: payerSig,
            protocolVersion: 1
        )

        let instruction = try PaymentInstruction(
            paymentId: paymentId,
            fromAccount: "alice",
            toAccount: "carol",
            amount: Decimal(120.00),
            createdAt: PaymentInstant.now(),
            nonce: "nonce"
        )
        let signedInst = try instruction.withSignature("sig")
        let packet = try OfflinePaymentPacket(
            instruction: signedInst,
            deviceId: "iphone-peer",
            status: .received,
            allowanceSpend: spend
        )

        // Mathematical verification
        let (mathValid, err) = spend.verifyPayerSignature(payerPublicKeyBase64X509: payerPub)
        try assert(mathValid, "Mathematical verification must pass: \(err ?? "")")

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = ReceivedPacketStore(fileURL: tempDir.appendingPathComponent("received_inbox.json"))
        let record = try ReceivedPacketRecord(
            packet: packet,
            receivedFromPeer: "Alice's iPhone 15",
            isSignatureMathematicallyValid: mathValid,
            isSenderIdentityAuthenticated: false,
            trustStatusNote: "RSASSA-PSS Verified",
            reconciliationStatus: .received
        )
        try store.save(record)

        try assert(store.count == 1, "Inbox must contain 1 packet")
        let retrieved = store.get(paymentId: paymentId)
        try assert(retrieved?.reconciliationStatus == .received, "Initial status must be .received, not settled")

        // Settle transition
        try store.updateStatus(paymentId: paymentId, status: .settling)
        try assert(store.get(paymentId: paymentId)?.reconciliationStatus == .settling, "Status must transition to .settling")

        try store.updateStatus(paymentId: paymentId, status: .settled)
        try assert(store.get(paymentId: paymentId)?.reconciliationStatus == .settled, "Status must transition to .settled upon bridge confirmation")

        print("  ✓ PASS: testMacCompanion_allowancePacketVerificationAndReconciliation")
    }
}

// MARK: - Mock Submitter for Allowance Spend Testing
private final class MockAllowancePaymentSubmitter: MeshPaymentSubmitting, @unchecked Sendable {
    var spendResponseToReturn: OfflineSpendPaymentDTO?
    var errorToThrow: Error?

    init(spendResponseToReturn: OfflineSpendPaymentDTO? = nil, errorToThrow: Error? = nil) {
        self.spendResponseToReturn = spendResponseToReturn
        self.errorToThrow = errorToThrow
    }

    func submitSignedMeshPayment(
        instruction: PaymentInstruction,
        deviceId: String
    ) async throws -> MeshPaymentResultDTO {
        throw APIError.invalidResponse(500)
    }

    func submitAllowanceSpend(
        record: OfflineSpendRecord
    ) async throws -> OfflineSpendPaymentDTO {
        if let err = errorToThrow {
            throw err
        }
        if let resp = spendResponseToReturn {
            return resp
        }
        throw APIError.invalidResponse(500)
    }

    func queryPaymentStatus(
        paymentId: String
    ) async throws -> PaymentStatusResponseDTO {
        throw APIError.invalidResponse(500)
    }
}


