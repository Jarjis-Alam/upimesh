import Foundation
import Security
import CryptoKit

/// Test suite specifically verifying macOS Companion isolation, identity, and packet store logic.
public final class MacCompanionTests {

    public static func runAllTests() throws {
        print("=== Running MacCompanionTests (5 tests) ===")
        try testMacIdentityGenerationAndIsolation()
        try testMacReceivedPacketStoreIsolationAndDeduplication()
        try testMacRemoteSignatureVerification()
        try testMacStatusSemanticsAndUnauthenticatedIdentity()
        try testMacReceivedReconciliationLifecycle()
        print("=== MacCompanionTests: All passed cleanly! ===")
    }

    private static func assert(_ condition: Bool, _ message: String) throws {
        if !condition {
            print("  ✗ FAIL: \(message)")
            throw NSError(domain: "MacCompanionTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    // MARK: - Test 1: Mac Identity Generation & Isolation
    public static func testMacIdentityGenerationAndIsolation() throws {
        let identity = try MacDeviceIdentityManager.shared.getOrCreateIdentity()
        try assert(identity.deviceId.hasPrefix("mac-companion-"), "Mac device ID must have 'mac-companion-' prefix")
        try assert(!identity.publicKeyBase64X509.isEmpty, "Public key must be non-empty")
        try assert(!identity.publicKeyFingerprint.isEmpty, "Fingerprint must be non-empty")

        // Test signing canonical data
        let message = "Canonical bytes test".data(using: .utf8)!
        let sigBase64 = try MacDeviceIdentityManager.shared.signBase64(message: message)
        try assert(!sigBase64.isEmpty, "Signature must be non-empty")

        // Test mathematical verification against exported public key
        let (isValid, err) = MacDeviceIdentityManager.verifyRemoteRSASSA_PSS(
            publicKeyBase64X509: identity.publicKeyBase64X509,
            message: message,
            signatureBase64: sigBase64
        )
        try assert(isValid, "Mac's own signature must verify mathematically: \(err ?? "")")
        print("  ✓ PASS: testMacIdentityGenerationAndIsolation")
    }

    // MARK: - Test 2: Mac Received Packet Store Isolation & Deduplication
    public static func testMacReceivedPacketStoreIsolationAndDeduplication() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testFile = tempDir.appendingPathComponent("mac_received_test.json")
        let store = MacReceivedPacketStore(fileURL: testFile)

        // Create sample packet
        _ = try MacDeviceIdentityManager.shared.getOrCreateIdentity()
        let instruction = try PaymentInstruction(
            paymentId: UUID().uuidString.lowercased(),
            fromAccount: "alice",
            toAccount: "bob",
            amount: Decimal(20.00),
            createdAt: PaymentInstant.now(),
            nonce: UUID().uuidString.lowercased()
        )
        let sig = try MacDeviceIdentityManager.shared.signBase64(message: instruction.toCanonicalBytes())
        let signedInstruction = try instruction.withSignature(sig)
        let packet = try OfflinePaymentPacket(
            instruction: signedInstruction,
            deviceId: "iphone-test-device",
            status: .received
        )

        let record = try MacReceivedPacketRecord(
            packet: packet,
            receivedFromPeer: "iPhone 14",
            isSignatureMathematicallyValid: true,
            isSenderIdentityAuthenticated: false,
            trustStatusNote: "Test note"
        )

        try store.save(record)
        try assert(store.count == 1, "Count should be 1")
        try assert(store.contains(paymentId: packet.paymentId), "Should contain payment ID")

        // Duplicate save must be rejected
        var caughtDuplicate = false
        do {
            try store.save(record)
        } catch MacReceivedPacketStoreError.duplicatePacketId {
            caughtDuplicate = true
        }
        try assert(caughtDuplicate, "Duplicate packetId must be rejected")
        print("  ✓ PASS: testMacReceivedPacketStoreIsolationAndDeduplication")
    }

    // MARK: - Test 3: Remote Signature Verification
    public static func testMacRemoteSignatureVerification() throws {
        let identity = try MacDeviceIdentityManager.shared.getOrCreateIdentity()
        let canonical = "UPI-MESH-INSTRUCTION-V1:TEST".data(using: .utf8)!
        let sig = try MacDeviceIdentityManager.shared.signBase64(message: canonical)

        let (valid, _) = MacDeviceIdentityManager.verifyRemoteRSASSA_PSS(
            publicKeyBase64X509: identity.publicKeyBase64X509,
            message: canonical,
            signatureBase64: sig
        )
        try assert(valid, "Signature should be valid")

        let (invalid, _) = MacDeviceIdentityManager.verifyRemoteRSASSA_PSS(
            publicKeyBase64X509: identity.publicKeyBase64X509,
            message: "corrupted message".data(using: .utf8)!,
            signatureBase64: sig
        )
        try assert(!invalid, "Signature should fail on corrupted message")
        print("  ✓ PASS: testMacRemoteSignatureVerification")
    }

    // MARK: - Test 4: Status Semantics & Unauthenticated Identity
    public static func testMacStatusSemanticsAndUnauthenticatedIdentity() throws {
        let instruction = try PaymentInstruction(
            paymentId: UUID().uuidString.lowercased(),
            fromAccount: "alice",
            toAccount: "bob",
            amount: Decimal(10.00),
            createdAt: PaymentInstant.now(),
            nonce: UUID().uuidString.lowercased()
        )
        let sig = try MacDeviceIdentityManager.shared.signBase64(message: instruction.toCanonicalBytes())
        let signedInstruction = try instruction.withSignature(sig)

        // Try saving with QUEUED status
        let queuedPacket = try OfflinePaymentPacket(
            instruction: signedInstruction,
            deviceId: "iphone-14",
            status: .queued
        )

        var caughtInvalid = false
        do {
            _ = try MacReceivedPacketRecord(
                packet: queuedPacket,
                receivedFromPeer: "iPhone",
                isSignatureMathematicallyValid: true,
                isSenderIdentityAuthenticated: false,
                trustStatusNote: "Note"
            )
        } catch MacReceivedPacketStoreError.invalidStatus {
            caughtInvalid = true
        }
        try assert(caughtInvalid, "Must reject packet with status QUEUED in Mac inbox")

        // With status RECEIVED
        let receivedPacket = try queuedPacket.withStatus(.received)
        let record = try MacReceivedPacketRecord(
            packet: receivedPacket,
            receivedFromPeer: "iPhone 14",
            isSignatureMathematicallyValid: true,
            isSenderIdentityAuthenticated: false,
            trustStatusNote: "Offline unverified"
        )
        try assert(record.packet.status == .received, "Status must be RECEIVED")
        try assert(!record.isSenderIdentityAuthenticated, "Identity must be unauthenticated")
        print("  ✓ PASS: testMacStatusSemanticsAndUnauthenticatedIdentity")
    }

    // MARK: - Test 5: Mac Received Packet Reconciliation Lifecycle
    public static func testMacReceivedReconciliationLifecycle() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storeFile = tempDir.appendingPathComponent("mac_lifecycle_test.json")
        let store = MacReceivedPacketStore(fileURL: storeFile)

        // 1. Create and sign sample packet
        let identity = try MacDeviceIdentityManager.shared.getOrCreateIdentity()
        let instruction = try PaymentInstruction(
            paymentId: UUID().uuidString.lowercased(),
            fromAccount: "alice",
            toAccount: "bob",
            amount: Decimal(35.00),
            createdAt: PaymentInstant.now(),
            nonce: UUID().uuidString.lowercased()
        )
        let sig = try MacDeviceIdentityManager.shared.signBase64(message: instruction.toCanonicalBytes())
        let signedInstruction = try instruction.withSignature(sig)
        let packet = try OfflinePaymentPacket(
            instruction: signedInstruction,
            deviceId: identity.deviceId,
            status: .received
        )

        let record = try MacReceivedPacketRecord(
            packet: packet,
            receivedFromPeer: "iPhone-Peer",
            isSignatureMathematicallyValid: true,
            isSenderIdentityAuthenticated: false,
            trustStatusNote: "Lifecycle test"
        )
        try store.save(record)

        // Initial status must be RECEIVED
        try assert(store.get(paymentId: packet.paymentId)?.reconciliationStatus == .received, "Initial Mac status must be RECEIVED")

        // 2. Transition RECEIVED -> SETTLING
        let settling = try store.updateStatus(paymentId: packet.paymentId, status: .settling)
        try assert(settling.reconciliationStatus == .settling, "Mac status must be SETTLING")
        try assert(settling.failureReason == nil, "Settling failureReason must be nil")
        try assert(settling.updatedAt != nil, "Settling updatedAt must be set")

        // 3. Transition SETTLING -> FAILED
        let failed = try store.updateStatus(paymentId: packet.paymentId, status: .failed, failureReason: "Ledger check rejected")
        try assert(failed.reconciliationStatus == .failed, "Mac status must be FAILED")
        try assert(failed.failureReason == "Ledger check rejected", "Mac failureReason must match")

        // 4. Transition FAILED -> SETTLING -> SETTLED
        _ = try store.updateStatus(paymentId: packet.paymentId, status: .settling)
        let settled = try store.updateStatus(paymentId: packet.paymentId, status: .settled)
        try assert(settled.reconciliationStatus == .settled, "Mac status must be SETTLED")
        try assert(settled.failureReason == nil, "Settled failureReason must be nil")

        // 5. Test Persistence Across Reload
        let reloadedStore = MacReceivedPacketStore(fileURL: storeFile)
        let reloadedRecord = reloadedStore.get(paymentId: packet.paymentId)
        try assert(reloadedRecord?.reconciliationStatus == .settled, "Reloaded Mac record must remain SETTLED")

        // 6. Test Unknown Payment ID Handling
        var caughtNotFound = false
        do {
            _ = try store.updateStatus(paymentId: "unknown-payment-id", status: .settling)
        } catch MacReceivedPacketStoreError.packetNotFound(let id) {
            try assert(id == "unknown-payment-id", "Error ID must match")
            caughtNotFound = true
        }
        try assert(caughtNotFound, "Updating unknown payment ID on Mac must throw packetNotFound")

        // 7. Duplicate Save Protection Maintained
        var caughtDuplicate = false
        do {
            try store.save(record)
        } catch MacReceivedPacketStoreError.duplicatePacketId {
            caughtDuplicate = true
        }
        try assert(caughtDuplicate, "Duplicate save on Mac must be rejected")

        // 8. Cryptographic Invariance
        try assert(settled.packet.signature == packet.signature, "Mac signature must be strictly invariant")
        try assert(settled.packet.canonicalBytes == packet.canonicalBytes, "Mac canonical bytes must be strictly invariant")
        try assert(settled.packet.instruction == packet.instruction, "Mac instruction must be strictly invariant")

        // 9. Legacy JSON Compatibility
        let legacyFile = tempDir.appendingPathComponent("mac_legacy.json")
        let realMacRecord = try MacReceivedPacketRecord(
            packet: packet,
            receivedFromPeer: "iPhone-Peer",
            isSignatureMathematicallyValid: true,
            isSenderIdentityAuthenticated: false,
            trustStatusNote: "Legacy Mac Note"
        )
        let macEncoder = JSONEncoder()
        let macEncoded = try macEncoder.encode([realMacRecord])
        var macJsonArray = try JSONSerialization.jsonObject(with: macEncoded) as! [[String: Any]]
        macJsonArray[0].removeValue(forKey: "reconciliationStatus")
        macJsonArray[0].removeValue(forKey: "failureReason")
        macJsonArray[0].removeValue(forKey: "updatedAt")
        let macLegacyData = try JSONSerialization.data(withJSONObject: macJsonArray, options: [.prettyPrinted, .sortedKeys])
        try macLegacyData.write(to: legacyFile)

        let legacyStore = MacReceivedPacketStore(fileURL: legacyFile)
        try assert(legacyStore.count == 1, "Legacy Mac record must load cleanly")
        try assert(legacyStore.get(paymentId: packet.paymentId)?.reconciliationStatus == .received, "Legacy Mac record must default to RECEIVED")

        print("  ✓ PASS: testMacReceivedReconciliationLifecycle")
    }
}
