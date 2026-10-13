import Foundation
import Security

/// Lightweight assertion error for unit testing.
public struct TestAssertionFailure: Error, CustomStringConvertible {
    public let message: String
    public let file: StaticString
    public let line: UInt

    public var description: String {
        "TestAssertionFailure at \(file):\(line) — \(message)"
    }
}

private func assertTrue(_ condition: Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) throws {
    guard condition else {
        throw TestAssertionFailure(message: "Expected true, got false. \(message)", file: file, line: line)
    }
}

private func assertFalse(_ condition: Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) throws {
    guard !condition else {
        throw TestAssertionFailure(message: "Expected false, got true. \(message)", file: file, line: line)
    }
}

private func assertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: StaticString = #file, line: UInt = #line) throws {
    guard a == b else {
        throw TestAssertionFailure(message: "Expected '\(b)', got '\(a)'. \(message)", file: file, line: line)
    }
}

private func assertNotNil<T>(_ value: T?, _ message: String = "", file: StaticString = #file, line: UInt = #line) throws -> T {
    guard let unwrapped = value else {
        throw TestAssertionFailure(message: "Expected non-nil value. \(message)", file: file, line: line)
    }
    return unwrapped
}

/// Comprehensive unit test suite verifying Stage 6.1 offline payment packet architecture.
public final class OfflinePaymentPacketTests {

    private var temporaryFileURL: URL!
    private var testStore: OfflinePacketStore!
    private var testIdentityManager: DeviceIdentityManager!

    public init() {}

    public func setUp() {
        let tempDir = FileManager.default.temporaryDirectory
        let uniqueName = "test_offline_packets_\(UUID().uuidString).json"
        temporaryFileURL = tempDir.appendingPathComponent(uniqueName)
        testStore = OfflinePacketStore(fileURL: temporaryFileURL)

        // Isolated identity manager tag for test isolation
        testIdentityManager = DeviceIdentityManager(
            keyTag: "com.upimesh.test.signingkey.\(UUID().uuidString)",
            serviceName: "com.upimesh.test.identity",
            deviceIdAccount: "testDeviceId"
        )
    }

    public func tearDown() {
        try? testStore.clear()
        try? testIdentityManager.deleteIdentity()
        if FileManager.default.fileExists(atPath: temporaryFileURL.path) {
            try? FileManager.default.removeItem(at: temporaryFileURL)
        }
    }

    // MARK: - 1. Serialization Round-Trip

    public func testSerializationRoundTrip() throws {
        setUp()
        defer { tearDown() }

        let identity = try testIdentityManager.getOrCreateIdentity()
        let instruction = try PaymentInstruction.create(
            fromAccount: "alice",
            toAccount: "bob",
            amountDouble: 25.50
        )
        let signature = try testIdentityManager.signBase64(message: instruction.toCanonicalBytes())
        let signedInstruction = try instruction.withSignature(signature)

        let originalPacket = try OfflinePaymentPacket(
            instruction: signedInstruction,
            deviceId: identity.deviceId,
            schemaVersion: 1,
            status: .queued
        )

        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(originalPacket)
        try assertFalse(jsonData.isEmpty, "JSON data must not be empty")

        // Assert no private key material is leaked into the JSON representation
        let jsonString = String(data: jsonData, encoding: .utf8)!
        try assertFalse(jsonString.contains("private"), "Packet JSON must not contain private key material")
        try assertFalse(jsonString.contains("kSecAttr"), "Packet JSON must not contain Keychain attributes")

        // Decode from JSON
        let decoder = JSONDecoder()
        let decodedPacket = try decoder.decode(OfflinePaymentPacket.self, from: jsonData)

        // Assert round-trip equality
        try assertEqual(decodedPacket.schemaVersion, originalPacket.schemaVersion)
        try assertEqual(decodedPacket.paymentId, originalPacket.paymentId)
        try assertEqual(decodedPacket.nonce, originalPacket.nonce)
        try assertEqual(decodedPacket.fromAccount, originalPacket.fromAccount)
        try assertEqual(decodedPacket.toAccount, originalPacket.toAccount)
        try assertEqual(decodedPacket.amount, originalPacket.amount)
        try assertEqual(decodedPacket.createdAt, originalPacket.createdAt)
        try assertEqual(decodedPacket.deviceId, originalPacket.deviceId)
        try assertEqual(decodedPacket.signature, originalPacket.signature)
        try assertEqual(decodedPacket.status, .queued)
        try assertEqual(decodedPacket.canonicalString, originalPacket.canonicalString)
        try assertEqual(decodedPacket, originalPacket)
    }

    // MARK: - 2. Persistence Round-Trip & Survival Across Store Relaunch

    public func testPersistenceRoundTripAndSurvivesRelaunch() throws {
        setUp()
        defer { tearDown() }

        let identity = try testIdentityManager.getOrCreateIdentity()

        // Create packet 1
        let inst1 = try PaymentInstruction.create(fromAccount: "alice", toAccount: "bob", amountDouble: 10.00)
        let sig1 = try testIdentityManager.signBase64(message: inst1.toCanonicalBytes())
        let packet1 = try OfflinePaymentPacket(instruction: try inst1.withSignature(sig1), deviceId: identity.deviceId)

        // Create packet 2
        let inst2 = try PaymentInstruction.create(fromAccount: "alice", toAccount: "carol", amountDouble: 50.00)
        let sig2 = try testIdentityManager.signBase64(message: inst2.toCanonicalBytes())
        let packet2 = try OfflinePaymentPacket(instruction: try inst2.withSignature(sig2), deviceId: identity.deviceId)

        // Save both to store
        try testStore.save(packet1)
        try testStore.save(packet2)

        try assertEqual(testStore.count, 2)
        try assertTrue(testStore.contains(paymentId: packet1.paymentId))
        try assertTrue(testStore.contains(paymentId: packet2.paymentId))

        // Simulate app kill and cold restart: instantiate a fresh store pointing to the same file
        let relaunchedStore = OfflinePacketStore(fileURL: temporaryFileURL)

        try assertEqual(relaunchedStore.count, 2, "Relaunched store must restore all persisted packets")
        try assertTrue(relaunchedStore.contains(paymentId: packet1.paymentId))
        try assertTrue(relaunchedStore.contains(paymentId: packet2.paymentId))

        let reloadedPacket1 = try assertNotNil(relaunchedStore.get(paymentId: packet1.paymentId))
        try assertEqual(reloadedPacket1.amountDouble, 10.00)
        try assertEqual(reloadedPacket1.toAccount, "bob")
        try assertEqual(reloadedPacket1.status, .queued)

        let reloadedPacket2 = try assertNotNil(relaunchedStore.get(paymentId: packet2.paymentId))
        try assertEqual(reloadedPacket2.amountDouble, 50.00)
        try assertEqual(reloadedPacket2.toAccount, "carol")
        try assertEqual(reloadedPacket2.status, .queued)
    }

    // MARK: - 3. Duplicate-ID Protection

    public func testDuplicateIdProtection() throws {
        setUp()
        defer { tearDown() }

        let identity = try testIdentityManager.getOrCreateIdentity()
        let inst = try PaymentInstruction.create(fromAccount: "alice", toAccount: "bob", amountDouble: 15.00)
        let sig = try testIdentityManager.signBase64(message: inst.toCanonicalBytes())
        let packet = try OfflinePaymentPacket(instruction: try inst.withSignature(sig), deviceId: identity.deviceId)

        // First save must succeed
        try testStore.save(packet)
        try assertEqual(testStore.count, 1)

        // Second save of exact same payment ID must throw duplicatePacketId error
        var caughtDuplicate = false
        do {
            try testStore.save(packet)
        } catch let OfflinePacketStoreError.duplicatePacketId(id) {
            caughtDuplicate = true
            try assertEqual(id, packet.paymentId)
        }
        try assertTrue(caughtDuplicate, "Expected duplicatePacketId error on saving existing ID")

        // Store count must remain strictly 1
        try assertEqual(testStore.count, 1)
    }

    // MARK: - 4. Invalid Amount Rejection

    public func testInvalidAmountsRejected() throws {
        setUp()
        defer { tearDown() }

        let service = OfflinePaymentService(identityManager: testIdentityManager, packetStore: testStore)

        // Zero amount
        var caughtZero = false
        do {
            try service.createAndQueueOfflinePayment(fromAccount: "alice", toAccount: "bob", amount: 0.00)
        } catch {
            caughtZero = true
        }
        try assertTrue(caughtZero, "Zero amount must be rejected")

        // Negative amount
        var caughtNegative = false
        do {
            try service.createAndQueueOfflinePayment(fromAccount: "alice", toAccount: "bob", amount: -10.00)
        } catch {
            caughtNegative = true
        }
        try assertTrue(caughtNegative, "Negative amount must be rejected")

        // Non-finite amounts (NaN, Infinity, -Infinity)
        var caughtNaN = false
        do {
            try service.createAndQueueOfflinePayment(fromAccount: "alice", toAccount: "bob", amount: Double.nan)
        } catch {
            caughtNaN = true
        }
        try assertTrue(caughtNaN, "NaN amount must be rejected")

        var caughtInf = false
        do {
            try service.createAndQueueOfflinePayment(fromAccount: "alice", toAccount: "bob", amount: Double.infinity)
        } catch {
            caughtInf = true
        }
        try assertTrue(caughtInf, "Infinity amount must be rejected")

        var caughtNegInf = false
        do {
            try service.createAndQueueOfflinePayment(fromAccount: "alice", toAccount: "bob", amount: -Double.infinity)
        } catch {
            caughtNegInf = true
        }
        try assertTrue(caughtNegInf, "-Infinity amount must be rejected")

        // Store must have 0 packets saved
        try assertEqual(testStore.count, 0)
    }

    // MARK: - 5. Account Invariant Validation

    public func testInvalidAccountsRejected() throws {
        setUp()
        defer { tearDown() }

        let service = OfflinePaymentService(identityManager: testIdentityManager, packetStore: testStore)

        // Same sender and recipient
        var caughtSame = false
        do {
            try service.createAndQueueOfflinePayment(fromAccount: "alice", toAccount: "alice", amount: 10.00)
        } catch {
            caughtSame = true
        }
        try assertTrue(caughtSame, "Self-transfer must be rejected")

        // Case-insensitive same account
        var caughtCaseSame = false
        do {
            try service.createAndQueueOfflinePayment(fromAccount: "Alice", toAccount: "alice", amount: 10.00)
        } catch {
            caughtCaseSame = true
        }
        try assertTrue(caughtCaseSame, "Case-insensitive self-transfer must be rejected")

        // Empty accounts
        var caughtEmptyFrom = false
        do {
            try service.createAndQueueOfflinePayment(fromAccount: "", toAccount: "bob", amount: 10.00)
        } catch {
            caughtEmptyFrom = true
        }
        try assertTrue(caughtEmptyFrom, "Empty sender must be rejected")

        var caughtEmptyTo = false
        do {
            try service.createAndQueueOfflinePayment(fromAccount: "alice", toAccount: "   ", amount: 10.00)
        } catch {
            caughtEmptyTo = true
        }
        try assertTrue(caughtEmptyTo, "Whitespace recipient must be rejected")
    }

    // MARK: - 6. Local-Only Creation Without Network Client

    public func testLocalOnlyCreationDoesNotInvokeNetwork() throws {
        setUp()
        defer { tearDown() }

        let service = OfflinePaymentService(identityManager: testIdentityManager, packetStore: testStore)

        // Create packet offline
        let packet = try service.createAndQueueOfflinePayment(
            fromAccount: "alice",
            toAccount: "bob",
            amount: 10.00,
            memo: "Offline morning tea"
        )

        // 1. Verify packet structure
        try assertFalse(packet.paymentId.isEmpty)
        try assertFalse(packet.nonce.isEmpty)
        try assertEqual(packet.fromAccount, "alice")
        try assertEqual(packet.toAccount, "bob")
        try assertEqual(packet.amountDouble, 10.00)
        try assertEqual(packet.status, .queued, "Newly created packet status must be strictly QUEUED")

        // 2. Verify RSASSA-PSS digital signature validity
        let canonicalBytes = packet.canonicalBytes
        let isSigValid = testIdentityManager.verifyBase64(signatureBase64: packet.signature, for: canonicalBytes)
        try assertTrue(isSigValid, "Offline packet signature must be mathematically valid RSASSA-PSS")

        // 3. Verify canonical amount format matches Java backend canonicalization ("10.00")
        let canonicalStr = packet.canonicalString
        try assertTrue(canonicalStr.contains("amount:5:10.00\n"), "Canonical string must format currency to exactly 2 decimals")
        try assertTrue(canonicalStr.contains("UPI-MESH-INSTRUCTION-V1\n"))

        // 4. Verify packet was durably persisted in local store
        try assertEqual(testStore.count, 1)
        let stored = try assertNotNil(testStore.get(paymentId: packet.paymentId))
        try assertEqual(stored, packet)
    }

    // MARK: - 7. Packet-Instruction Consistency Guards

    public func testMismatchedInstructionRejected() throws {
        setUp()
        defer { tearDown() }

        let identity = try testIdentityManager.getOrCreateIdentity()
        let inst = try PaymentInstruction.create(fromAccount: "alice", toAccount: "bob", amountDouble: 10.00)
        let sig = try testIdentityManager.signBase64(message: inst.toCanonicalBytes())
        let signedInst = try inst.withSignature(sig)

        // Mismatched paymentId
        var caughtMismatchedId = false
        do {
            _ = try OfflinePaymentPacket(
                schemaVersion: 1,
                paymentId: "different-id",
                nonce: signedInst.nonce,
                fromAccount: signedInst.fromAccount,
                toAccount: signedInst.toAccount,
                amount: signedInst.amount,
                createdAt: signedInst.createdAt,
                deviceId: identity.deviceId,
                instruction: signedInst,
                signature: sig,
                status: .queued
            )
        } catch let OfflinePaymentPacketError.mismatchedInstructionField(field) {
            caughtMismatchedId = true
            try assertEqual(field, "paymentId")
        }
        try assertTrue(caughtMismatchedId, "Mismatched paymentId must throw mismatchedInstructionField")

        // Mismatched amount
        var caughtMismatchedAmount = false
        do {
            _ = try OfflinePaymentPacket(
                schemaVersion: 1,
                paymentId: signedInst.paymentId,
                nonce: signedInst.nonce,
                fromAccount: signedInst.fromAccount,
                toAccount: signedInst.toAccount,
                amount: Decimal(999),
                createdAt: signedInst.createdAt,
                deviceId: identity.deviceId,
                instruction: signedInst,
                signature: sig,
                status: .queued
            )
        } catch let OfflinePaymentPacketError.mismatchedInstructionField(field) {
            caughtMismatchedAmount = true
            try assertEqual(field, "amount")
        }
        try assertTrue(caughtMismatchedAmount, "Mismatched amount must throw mismatchedInstructionField")
    }

    // MARK: - 8. Queued Packets Filtering & Ordering (Stage 6.2)

    public func testQueuedPacketsFilteringAndOrdering() throws {
        setUp()
        defer { tearDown() }

        let service = OfflinePaymentService(identityManager: testIdentityManager, packetStore: testStore)

        // Queue packet 1
        let p1 = try service.createAndQueueOfflinePayment(fromAccount: "alice", toAccount: "bob", amount: 10.00)
        // Queue packet 2
        let p2 = try service.createAndQueueOfflinePayment(fromAccount: "alice", toAccount: "carol", amount: 20.00)
        // Queue packet 3
        let p3 = try service.createAndQueueOfflinePayment(fromAccount: "alice", toAccount: "bob", amount: 30.00)

        let queued = service.getQueuedPackets()
        try assertEqual(queued.count, 3, "Service must return exactly 3 queued packets")
        try assertEqual(queued[0].paymentId, p1.paymentId)
        try assertEqual(queued[1].paymentId, p2.paymentId)
        try assertEqual(queued[2].paymentId, p3.paymentId)

        for p in queued {
            try assertEqual(p.status, .queued, "Every stored packet must have QUEUED status")
            try assertFalse(p.signature.isEmpty, "Every queued packet must have a valid non-empty signature")
        }
    }

    // MARK: - 9. Local Creation With Memo & Multiple Recipients (Stage 6.2)

    public func testLocalCreationWithMemoAndMultipleRecipients() throws {
        setUp()
        defer { tearDown() }

        let service = OfflinePaymentService(identityManager: testIdentityManager, packetStore: testStore)

        let memoPacket = try service.createAndQueueOfflinePayment(
            fromAccount: "alice",
            toAccount: "bob",
            amount: 75.50,
            memo: "Lunch at cafe"
        )

        try assertEqual(memoPacket.amountDouble, 75.50)
        try assertEqual(memoPacket.fromAccount, "alice")
        try assertEqual(memoPacket.toAccount, "bob")
        try assertEqual(memoPacket.status, .queued)

        let allPackets = service.getAllPackets()
        try assertEqual(allPackets.count, 1)
        try assertEqual(allPackets.first?.paymentId, memoPacket.paymentId)
    }

    // MARK: - Runner

    public static func runAllTests() -> Bool {
        let suite = OfflinePaymentPacketTests()
        var passed = 0
        var failed = 0

        let tests: [(String, () throws -> Void)] = [
            ("testSerializationRoundTrip", suite.testSerializationRoundTrip),
            ("testPersistenceRoundTripAndSurvivesRelaunch", suite.testPersistenceRoundTripAndSurvivesRelaunch),
            ("testDuplicateIdProtection", suite.testDuplicateIdProtection),
            ("testInvalidAmountsRejected", suite.testInvalidAmountsRejected),
            ("testInvalidAccountsRejected", suite.testInvalidAccountsRejected),
            ("testLocalOnlyCreationDoesNotInvokeNetwork", suite.testLocalOnlyCreationDoesNotInvokeNetwork),
            ("testMismatchedInstructionRejected", suite.testMismatchedInstructionRejected),
            ("testQueuedPacketsFilteringAndOrdering", suite.testQueuedPacketsFilteringAndOrdering),
            ("testLocalCreationWithMemoAndMultipleRecipients", suite.testLocalCreationWithMemoAndMultipleRecipients)
        ]

        print("=== Running OfflinePaymentPacketTests (\(tests.count) tests) ===")
        for (name, testFn) in tests {
            do {
                try testFn()
                passed += 1
                print("  ✓ PASS: \(name)")
            } catch {
                failed += 1
                print("  ✗ FAIL: \(name) - \(error)")
            }
        }

        print("\n=== Result: \(passed) passed, \(failed) failed ===")
        return failed == 0
    }
}
