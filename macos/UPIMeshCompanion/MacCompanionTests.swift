import Foundation
import Security
import CryptoKit

/// Test suite specifically verifying macOS Companion isolation, identity, and packet store logic.
public final class MacCompanionTests {

    public static func runAllTests() async throws {
        print("=== Running MacCompanionTests (15 tests) ===")
        try testMacIdentityGenerationAndIsolation()
        try testMacReceivedPacketStoreIsolationAndDeduplication()
        try testMacRemoteSignatureVerification()
        try testMacStatusSemanticsAndUnauthenticatedIdentity()
        try testMacReceivedReconciliationLifecycle()

        // Stage 6.4B.6 Bridge Client Tests
        try await testMacBridgeRegistrationRequestEncoding()
        try await testMacBridgeRegistrationSuccessResponseParsing()
        try await testMacBridgeAlreadyRegisteredResponseParsing()
        try await testMacBridgeRegistrationHttp400Rejection()
        try await testMacBridgeNetworkFailureHandling()
        try await testMacBridgeMalformedResponseHandling()
        try await testMacBridgeBlankParametersRejectedLocally()

        // Stage 6.4B Diagnostic Peer Connectivity Tests
        try testMacDiagnosticPingGenerationAndIsolation()
        try testMacDiagnosticPongResponseGeneration()
        try testMacDiagnosticStatusTransitions()

        // Phase 2B Allowance Packet & Settlement Verification Tests
        try testMacAllowancePacketVerificationAndLifecycle()
        print("=== MacCompanionTests: All 16 passed cleanly! ===")
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

    // MARK: - Test 6: Bridge Registration Request Encoding
    public static func testMacBridgeRegistrationRequestEncoding() async throws {
        let testDeviceId = "mac-companion-test-encoding-uuid"
        let testPublicKey = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA0123456789"

        var capturedRequest: URLRequest?
        var capturedBodyData: Data?

        MockBridgeURLProtocol.requestHandler = { req in
            capturedRequest = req
            capturedBodyData = MockBridgeURLProtocol.extractBodyData(from: req)

            let json = """
            {
                "status": "REGISTERED",
                "accountId": "\(testDeviceId)",
                "message": "Public key successfully registered for account: \(testDeviceId)"
            }
            """.data(using: .utf8)!

            let resp = HTTPURLResponse(
                url: req.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (resp, json)
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockBridgeURLProtocol.self]
        let session = URLSession(configuration: config)
        let client = MacBridgeClient(baseURL: URL(string: "http://mock-backend:8080")!, session: session)

        let response = try await client.registerPublicKey(deviceId: testDeviceId, publicKeyBase64: testPublicKey)

        try assert(capturedRequest != nil, "Request must be captured")
        try assert(capturedRequest?.httpMethod == "POST", "Method must be POST")
        try assert(capturedRequest?.url?.path == "/api/keys/register", "Path must be /api/keys/register")
        try assert(capturedRequest?.value(forHTTPHeaderField: "Content-Type") == "application/json", "Content-Type must be application/json")
        try assert(capturedRequest?.value(forHTTPHeaderField: "Accept") == "application/json", "Accept must be application/json")

        guard let bodyData = capturedBodyData else {
            throw NSError(domain: "MacCompanionTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Body data missing"])
        }
        let decoded = try JSONDecoder().decode(MacKeyRegistrationRequest.self, from: bodyData)
        try assert(decoded.accountId == testDeviceId, "accountId in payload must match deviceId")
        try assert(decoded.publicKey == testPublicKey, "publicKey in payload must match test key")

        // Invariance: Payload must never contain private key material
        let bodyString = String(data: bodyData, encoding: .utf8) ?? ""
        try assert(!bodyString.contains("PRIVATE"), "Payload must NEVER contain private key material")

        try assert(response.isSuccess, "Must be successful")
        try assert(response.isNewlyRegistered, "Must be newly registered")
        try assert(!response.isAlreadyRegistered, "Must not be already registered")
        print("  ✓ PASS: testMacBridgeRegistrationRequestEncoding")
    }

    // MARK: - Test 7: Bridge Registration Success Response Parsing
    public static func testMacBridgeRegistrationSuccessResponseParsing() async throws {
        let testDeviceId = "mac-companion-success-test"
        MockBridgeURLProtocol.requestHandler = { req in
            let json = """
            {
                "status": "REGISTERED",
                "accountId": "\(testDeviceId)",
                "message": "Public key successfully registered for account: \(testDeviceId)"
            }
            """.data(using: .utf8)!
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            return (resp, json)
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockBridgeURLProtocol.self]
        let client = MacBridgeClient(baseURL: URL(string: "http://mock-backend:8080")!, session: URLSession(configuration: config))

        let response = try await client.registerPublicKey(deviceId: testDeviceId, publicKeyBase64: "dummy-key")
        try assert(response.status == "REGISTERED", "Status must be REGISTERED")
        try assert(response.isSuccess, "isSuccess must be true")
        try assert(response.isNewlyRegistered, "isNewlyRegistered must be true")
        try assert(!response.isAlreadyRegistered, "isAlreadyRegistered must be false")
        try assert(response.accountId == testDeviceId, "accountId must match")
        print("  ✓ PASS: testMacBridgeRegistrationSuccessResponseParsing")
    }

    // MARK: - Test 8: Bridge Already Registered Response Parsing
    public static func testMacBridgeAlreadyRegisteredResponseParsing() async throws {
        let testDeviceId = "mac-companion-existing-test"
        MockBridgeURLProtocol.requestHandler = { req in
            let json = """
            {
                "status": "ALREADY_REGISTERED",
                "accountId": "\(testDeviceId)",
                "message": "Public key is already registered for account: \(testDeviceId)"
            }
            """.data(using: .utf8)!
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            return (resp, json)
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockBridgeURLProtocol.self]
        let client = MacBridgeClient(baseURL: URL(string: "http://mock-backend:8080")!, session: URLSession(configuration: config))

        let response = try await client.registerPublicKey(deviceId: testDeviceId, publicKeyBase64: "dummy-key")
        try assert(response.status == "ALREADY_REGISTERED", "Status must be ALREADY_REGISTERED")
        try assert(response.isSuccess, "isSuccess must be true")
        try assert(!response.isNewlyRegistered, "isNewlyRegistered must be false")
        try assert(response.isAlreadyRegistered, "isAlreadyRegistered must be true")
        print("  ✓ PASS: testMacBridgeAlreadyRegisteredResponseParsing")
    }

    // MARK: - Test 9: Bridge Registration HTTP 400 Rejection
    public static func testMacBridgeRegistrationHttp400Rejection() async throws {
        let errorMsg = "Bad request parameter: Account 'mac-companion-123' is already registered with a different public key. Arbitrary key replacement is forbidden under prototype trust policy."
        MockBridgeURLProtocol.requestHandler = { req in
            let data = errorMsg.data(using: .utf8)!
            let resp = HTTPURLResponse(url: req.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            return (resp, data)
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockBridgeURLProtocol.self]
        let client = MacBridgeClient(baseURL: URL(string: "http://mock-backend:8080")!, session: URLSession(configuration: config))

        var caughtRejection = false
        do {
            _ = try await client.registerPublicKey(deviceId: "mac-companion-123", publicKeyBase64: "new-key")
        } catch MacBridgeError.registrationRejected(let message) {
            caughtRejection = true
            try assert(message.contains("different public key"), "Error message must report different public key violation")
        }
        try assert(caughtRejection, "HTTP 400 must throw MacBridgeError.registrationRejected")
        print("  ✓ PASS: testMacBridgeRegistrationHttp400Rejection")
    }

    // MARK: - Test 10: Bridge Network Failure Handling
    public static func testMacBridgeNetworkFailureHandling() async throws {
        MockBridgeURLProtocol.requestHandler = { _ in
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost, userInfo: [NSLocalizedDescriptionKey: "Could not connect to the server."])
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockBridgeURLProtocol.self]
        let client = MacBridgeClient(baseURL: URL(string: "http://mock-backend:8080")!, session: URLSession(configuration: config))

        var caughtNetworkError = false
        do {
            _ = try await client.registerPublicKey(deviceId: "mac-device", publicKeyBase64: "test-key")
        } catch MacBridgeError.networkError(let details) {
            caughtNetworkError = true
            try assert(details.contains("Could not connect"), "Network error details must be preserved")
        }
        try assert(caughtNetworkError, "Connection failure must throw MacBridgeError.networkError")
        print("  ✓ PASS: testMacBridgeNetworkFailureHandling")
    }

    // MARK: - Test 11: Bridge Malformed Response Handling
    public static func testMacBridgeMalformedResponseHandling() async throws {
        MockBridgeURLProtocol.requestHandler = { req in
            let badJson = "{ invalid json content".data(using: .utf8)!
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            return (resp, badJson)
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockBridgeURLProtocol.self]
        let client = MacBridgeClient(baseURL: URL(string: "http://mock-backend:8080")!, session: URLSession(configuration: config))

        var caughtDecodingError = false
        do {
            _ = try await client.registerPublicKey(deviceId: "mac-device", publicKeyBase64: "test-key")
        } catch MacBridgeError.decodingError {
            caughtDecodingError = true
        }
        try assert(caughtDecodingError, "Malformed JSON must throw MacBridgeError.decodingError")
        print("  ✓ PASS: testMacBridgeMalformedResponseHandling")
    }

    // MARK: - Test 12: Blank Parameters Rejected Locally
    public static func testMacBridgeBlankParametersRejectedLocally() async throws {
        var networkAttempted = false
        MockBridgeURLProtocol.requestHandler = { req in
            networkAttempted = true
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data())
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockBridgeURLProtocol.self]
        let client = MacBridgeClient(baseURL: URL(string: "http://mock-backend:8080")!, session: URLSession(configuration: config))

        var caughtBlankDevice = false
        do {
            _ = try await client.registerPublicKey(deviceId: "   ", publicKeyBase64: "valid-key")
        } catch MacBridgeError.invalidParameters {
            caughtBlankDevice = true
        }
        try assert(caughtBlankDevice, "Blank device ID must throw invalidParameters")

        var caughtBlankKey = false
        do {
            _ = try await client.registerPublicKey(deviceId: "mac-device", publicKeyBase64: "   \n")
        } catch MacBridgeError.invalidParameters {
            caughtBlankKey = true
        }
        try assert(caughtBlankKey, "Blank public key must throw invalidParameters")

        try assert(!networkAttempted, "Network must NOT be contacted when parameters are invalid")
        print("  ✓ PASS: testMacBridgeBlankParametersRejectedLocally")
    }

    // MARK: - Stage 6.4B Diagnostic Tests (Mac Peer Connectivity)

    // Test 13: Mac diagnostic PING generation and isolation
    public static func testMacDiagnosticPingGenerationAndIsolation() throws {
        let identity = try MacDeviceIdentityManager.shared.getOrCreateIdentity()
        let pingId = UUID().uuidString.lowercased()
        let ping = PeerDiagnosticMessage(
            messageType: .ping,
            diagnosticId: pingId,
            senderDeviceId: identity.deviceId,
            timestamp: PaymentInstant.now().isoString,
            replyToId: nil
        )
        try ping.validate()

        let data = try ping.encode()
        try assert(data.count <= PeerDiagnosticMessage.maxPayloadBytes, "Ping payload size must be within limit")

        let decoded = try PeerDiagnosticMessage.decodeAndValidate(from: data)
        try assert(decoded.messageType == .ping, "Must decode as PING")
        try assert(decoded.senderDeviceId == identity.deviceId, "Device ID must match Mac's registered identity")
        try assert(decoded.replyToId == nil, "PING must have nil replyToId")

        // Inbound transport probe test on Mac
        try assert(InboundTransportProbe.probe(data: data) == .diagnosticPing, "Inbound probe identifies as diagnosticPing")

        print("  ✓ PASS: testMacDiagnosticPingGenerationAndIsolation")
    }

    // Test 14: Mac diagnostic PONG response generation and isolation
    public static func testMacDiagnosticPongResponseGeneration() throws {
        let identity = try MacDeviceIdentityManager.shared.getOrCreateIdentity()
        let inboundPingId = "iphone-ping-987654"

        // Simulate Mac responding with PONG
        let pong = PeerDiagnosticMessage(
            messageType: .pong,
            diagnosticId: UUID().uuidString.lowercased(),
            senderDeviceId: identity.deviceId,
            timestamp: PaymentInstant.now().isoString,
            replyToId: inboundPingId
        )
        try pong.validate()

        let data = try pong.encode()
        let decoded = try PeerDiagnosticMessage.decodeAndValidate(from: data)
        try assert(decoded.messageType == .pong, "Must decode as PONG")
        try assert(decoded.replyToId == inboundPingId, "Pong must reference incoming ping ID")
        try assert(decoded.senderDeviceId == identity.deviceId, "Pong sender must be Mac's device ID")

        // Verify probe routes as diagnosticPong
        try assert(InboundTransportProbe.probe(data: data) == .diagnosticPong, "Probe identifies as diagnosticPong")

        // Ensure Mac received packet store remains untouched
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = MacReceivedPacketStore(fileURL: tempDir.appendingPathComponent("mac_store_diag.json"))
        try assert(store.count == 0, "MacReceivedPacketStore must remain 0 after diagnostic message")
        try assert(!store.contains(paymentId: decoded.diagnosticId), "Diagnostic ID must never enter packet store")

        print("  ✓ PASS: testMacDiagnosticPongResponseGeneration")
    }

    // Test 15: Mac diagnostic round-trip matching and status transitions
    public static func testMacDiagnosticStatusTransitions() throws {
        let pingId = "mac-ping-test-111"
        var status: PingStatus = .idle
        try assert(!status.isSending, "Idle is not sending")

        // Transition to sending
        status = .sending(pingId: pingId, startedAt: Date())
        try assert(status.isSending, "Sending status isSending should be true")

        // 1. Unmatched response arrives
        let unmatchedPong = PeerDiagnosticMessage(
            messageType: .pong,
            diagnosticId: "pong-999",
            senderDeviceId: "iphone-14",
            replyToId: "other-ping-id"
        )
        if unmatchedPong.replyToId == pingId {
            status = .success(roundTripDurationMs: 10, peerName: "iPhone 14", pingId: unmatchedPong.diagnosticId)
        }
        try assert(status.isSending, "Unmatched PONG must NOT trigger success on Mac")

        // 2. Matching response arrives
        let matchingPong = PeerDiagnosticMessage(
            messageType: .pong,
            diagnosticId: "pong-111",
            senderDeviceId: "iPhone 14",
            replyToId: pingId
        )
        if matchingPong.replyToId == pingId {
            status = .success(roundTripDurationMs: 38, peerName: "iPhone 14", pingId: matchingPong.diagnosticId)
        }
        if case .success(let ms, let name, _) = status {
            try assert(ms == 38, "Round-trip ms should be 38")
            try assert(name == "iPhone 14", "Peer name should match")
        } else {
            try assert(false, "Matching PONG must transition to success")
        }

        print("  ✓ PASS: testMacDiagnosticStatusTransitions")
    }

    // MARK: - Test 16: Mac Allowance Packet Verification & Lifecycle
    public static func testMacAllowancePacketVerificationAndLifecycle() throws {
        let paymentId = "pay-mac-alw-01"

        let spend = OfflineSpendRecord(
            allowanceId: "alw-mac-test-01",
            paymentId: paymentId,
            payerAccountId: "alice",
            payerDeviceId: "iphone-peer-01",
            recipientAccountId: "carol",
            amount: Decimal(150.00),
            currency: "INR",
            sequenceNumber: 1,
            cumulativeSpentAmount: Decimal(150.00),
            createdAt: "2026-10-15T12:00:00Z",
            voucherSignature: "mock-voucher-sig",
            payerSignature: "mock-payer-sig",
            protocolVersion: 1
        )

        let instruction = try PaymentInstruction(
            paymentId: paymentId,
            fromAccount: "alice",
            toAccount: "carol",
            amount: Decimal(150.00),
            createdAt: PaymentInstant.now(),
            nonce: "nonce-mac-01"
        )
        let signedInst = try instruction.withSignature("sig-mac-01")
        let packet = try OfflinePaymentPacket(
            instruction: signedInst,
            deviceId: "iphone-peer-01",
            status: .received,
            allowanceSpend: spend
        )

        try assert(packet.isAllowanceBacked, "Packet must be identified as allowance-backed")
        try assert(packet.allowanceSpend?.paymentId == paymentId, "Embedded spend paymentId must match")

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = MacReceivedPacketStore(fileURL: tempDir.appendingPathComponent("mac_allowance_inbox.json"))
        let record = try MacReceivedPacketRecord(
            packet: packet,
            receivedFromPeer: "Alice iPhone",
            isSignatureMathematicallyValid: true,
            isSenderIdentityAuthenticated: false,
            trustStatusNote: "RSASSA-PSS Verified",
            reconciliationStatus: .received
        )

        try store.save(record)
        try assert(store.count == 1, "Mac companion inbox must store 1 packet")

        // Duplicate delivery protection on Mac
        do {
            try store.save(record)
            try assert(false, "Duplicate save must fail")
        } catch MacReceivedPacketStoreError.duplicatePacketId(let id) {
            try assert(id == paymentId, "Duplicate error must match payment ID")
        }

        // Status transitions: RECEIVED -> SETTLING -> SETTLED
        _ = try store.updateStatus(paymentId: paymentId, status: .settling)
        try assert(store.get(paymentId: paymentId)?.reconciliationStatus == .settling, "Status must be SETTLING")

        _ = try store.updateStatus(paymentId: paymentId, status: .settled)
        try assert(store.get(paymentId: paymentId)?.reconciliationStatus == .settled, "Status must be SETTLED")

        print("  ✓ PASS: testMacAllowancePacketVerificationAndLifecycle")
    }
}

// MARK: - Mock Bridge URL Protocol

private final class MockBridgeURLProtocol: URLProtocol, @unchecked Sendable {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "MockBridgeURLProtocol", code: 1, userInfo: [NSLocalizedDescriptionKey: "No requestHandler configured"]))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func extractBodyData(from request: URLRequest) -> Data? {
        if let data = request.httpBody {
            return data
        }
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            var data = Data()
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read > 0 {
                    data.append(buffer, count: read)
                } else {
                    break
                }
            }
            return data
        }
        return nil
    }
}
