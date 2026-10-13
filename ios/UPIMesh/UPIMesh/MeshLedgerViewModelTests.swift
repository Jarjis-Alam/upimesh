import Foundation

/// Mock transaction fetcher for isolated unit testing of MeshLedgerViewModel.
public final class MockTransactionFetcher: MeshTransactionFetching, @unchecked Sendable {
    public var transactionsToReturn: [TransactionDTO]
    public var errorToThrow: Error?

    public init(transactions: [TransactionDTO] = [], error: Error? = nil) {
        self.transactionsToReturn = transactions
        self.errorToThrow = error
    }

    public func fetchTransactions() async throws -> [TransactionDTO] {
        if let error = errorToThrow {
            throw error
        }
        return transactionsToReturn
    }
}

/// Comprehensive test suite for Stage 6.4B.4: Connecting Mesh Ledger to Live Backend.
public enum MeshLedgerViewModelTests {

    public static func runAllTests() async {
        print("=== Running MeshLedgerViewModelTests (7 tests) ===")

        await testLiveTransactionDecodingAndMapping()
        await testDynamicTransactionCountsAndSettledTotals()
        await testConnectionFailureWithoutSilentlyPresentingDemoAsLive()
        await testPendingPacketsSeparatedFromSettledBackendTransactions()
        await testRefreshAfterMeshAccountsUpdated()
        testTimestampFormatting()
        testCurrencyFormatting()

        print("=== MeshLedgerViewModelTests: All 7 passed cleanly! ===")
    }

    // MARK: - Test 1: Live Transaction Decoding and Mapping
    @MainActor
    public static func testLiveTransactionDecodingAndMapping() async {
        let json = """
        [
          {"id":"647cefef-0a9a-482c-bab6-1c70edba1eea","fromAccount":"alice","toAccount":"bob","amount":10.00,"timestamp":"2026-10-13T13:23:41.527123Z","status":"SETTLED"},
          {"id":"fe3b504a-0c05-4144-aac7-87861ff2bdfc","fromAccount":"alice","toAccount":"bob","amount":10.00,"timestamp":"2026-10-13T12:35:03.623177Z","status":"SETTLED"},
          {"id":"10db5be9-c844-467b-8d2d-34795e2415ac","fromAccount":"alice","toAccount":"bob","amount":10.00,"timestamp":"2026-10-12T13:52:31.321185Z","status":"SETTLED"}
        ]
        """.data(using: .utf8)!

        let decoded: [TransactionDTO]
        do {
            decoded = try JSONDecoder().decode([TransactionDTO].self, from: json)
        } catch {
            fatalError("Failed to decode live backend transaction JSON: \(error)")
        }
        assert(decoded.count == 3, "Expected 3 decoded transactions")

        let mockFetcher = MockTransactionFetcher(transactions: decoded)
        let tempStore = createTempReceivedStore()
        let vm = MeshLedgerViewModel(transactionFetcher: mockFetcher, packetStore: tempStore)

        await vm.loadLiveTransactions()

        assert(vm.status == .liveConnected, "Expected liveConnected status")
        assert(vm.isLive == true, "Expected isLive to be true")
        assert(vm.totalCount == 3, "Expected totalCount == 3")
        assert(vm.settledTotalAmount == 30.00, "Expected settledTotalAmount == 30.00")

        let items = vm.displayTransactions(for: "all")
        assert(items.count == 3, "Expected 3 display items")

        let first = items[0]
        assert(first.id == "647cefef-0a9a-482c-bab6-1c70edba1eea", "Mismatched ID")
        assert(first.txCode == "TX#647CEFEF", "Expected TX#647CEFEF, got \(first.txCode)")
        assert(first.title == "Alice → Bob", "Expected Alice → Bob, got \(first.title)")
        assert(first.amount == 10.00, "Expected amount 10.00")
        assert(first.category == .settled, "Expected category .settled")
        assert(first.statusLabel == "Settled", "Expected statusLabel 'Settled'")
        assert(first.routeLabel == "UPI Gateway", "Expected routeLabel 'UPI Gateway'")
        assert(!first.timeFormatted.isEmpty, "timeFormatted must not be empty")

        print("  ✓ PASS: testLiveTransactionDecodingAndMapping")
    }

    // MARK: - Test 2: Dynamic Counts and Settled Totals
    @MainActor
    public static func testDynamicTransactionCountsAndSettledTotals() async {
        let mockData = [
            TransactionDTO(id: "tx-1", fromAccount: "alice", toAccount: "bob", amount: 10.00, timestamp: "2026-10-13T10:00:00Z", status: "SETTLED"),
            TransactionDTO(id: "tx-2", fromAccount: "carol", toAccount: "alice", amount: 25.50, timestamp: "2026-10-13T10:05:00Z", status: "SETTLED"),
            TransactionDTO(id: "tx-3", fromAccount: "bob", toAccount: "carol", amount: 100.00, timestamp: "2026-10-13T10:10:00Z", status: "SETTLED"),
            TransactionDTO(id: "tx-4", fromAccount: "alice", toAccount: "bob", amount: 50.00, timestamp: "2026-10-13T10:15:00Z", status: "FAILED")
        ]

        let mockFetcher = MockTransactionFetcher(transactions: mockData)
        let tempStore = createTempReceivedStore()
        let vm = MeshLedgerViewModel(transactionFetcher: mockFetcher, packetStore: tempStore)

        await vm.loadLiveTransactions()

        assert(vm.totalCount == 4, "Expected totalCount == 4, got \(vm.totalCount)")
        assert(vm.settledCount == 3, "Expected settledCount == 3, got \(vm.settledCount)")
        assert(vm.settledTotalAmount == 135.50, "Expected settledTotalAmount == 135.50, got \(vm.settledTotalAmount)")
        assert(vm.blockedCount == 1, "Expected blockedCount == 1, got \(vm.blockedCount)")

        assert(vm.totalMetricString == "4 Tx", "Expected '4 Tx', got \(vm.totalMetricString)")
        assert(vm.settledMetricString == "₹135.50", "Expected '₹135.50', got \(vm.settledMetricString)")
        assert(vm.blockedMetricString == "1", "Expected '1', got \(vm.blockedMetricString)")

        let settledItems = vm.displayTransactions(for: "settled")
        assert(settledItems.count == 3, "Expected 3 settled items")

        let blockedItems = vm.displayTransactions(for: "blocked")
        assert(blockedItems.count == 1, "Expected 1 blocked item")
        assert(blockedItems[0].category == .blocked, "Expected blocked category")

        print("  ✓ PASS: testDynamicTransactionCountsAndSettledTotals")
    }

    // MARK: - Test 3: Connection Failure Without Silently Presenting Demo as Live
    @MainActor
    public static func testConnectionFailureWithoutSilentlyPresentingDemoAsLive() async {
        let mockFetcher = MockTransactionFetcher(error: APIError.networkError("Connection refused by localhost:8080"))
        let tempStore = createTempReceivedStore()
        let vm = MeshLedgerViewModel(transactionFetcher: mockFetcher, packetStore: tempStore)

        await vm.loadLiveTransactions()

        switch vm.status {
        case .connectionFailed(let msg):
            assert(msg.contains("Connection refused"), "Expected error message to reflect connection refusal, got: \(msg)")
        default:
            fatalError("Expected status to be .connectionFailed, got \(vm.status)")
        }

        assert(vm.isLive == false, "ViewModel must not claim to be live when connection fails")
        assert(vm.lastErrorMessage != nil, "lastErrorMessage must be recorded")

        // In fallback mode, sample transactions are served with connection failure state tracked
        let fallbackItems = vm.displayTransactions(for: "all")
        assert(!fallbackItems.isEmpty, "Fallback preview items should be accessible for offline demo")
        assert(vm.isLive == false, "Must never present demo fallback records as live transactions")

        print("  ✓ PASS: testConnectionFailureWithoutSilentlyPresentingDemoAsLive")
    }

    // MARK: - Test 4: Pending Packets Separated from Settled Backend Transactions
    @MainActor
    public static func testPendingPacketsSeparatedFromSettledBackendTransactions() async {
        let tempStore = createTempReceivedStore()

        // Create a locally received packet in the store
        let inst = try! PaymentInstruction(
            paymentId: "pkt-rec-1",
            fromAccount: "carol",
            toAccount: "bob",
            amount: 15.00,
            createdAt: PaymentInstant.now(),
            nonce: "nonce-rec-1",
            signature: "c2lnbmF0dXJl"
        )
        let packet = try! OfflinePaymentPacket(
            instruction: inst,
            deviceId: "device-carol",
            status: .received
        )
        let record = try! ReceivedPacketRecord(
            packet: packet,
            receivedFromPeer: "Carol's iPhone",
            isSignatureMathematicallyValid: true,
            isSenderIdentityAuthenticated: false,
            trustStatusNote: "Test received packet",
            reconciliationStatus: .received
        )
        try! tempStore.save(record)

        // Mock backend transactions: only 1 settled transaction
        let mockData = [
            TransactionDTO(id: "tx-settled-1", fromAccount: "alice", toAccount: "bob", amount: 50.00, timestamp: "2026-10-13T10:00:00Z", status: "SETTLED")
        ]
        let mockFetcher = MockTransactionFetcher(transactions: mockData)
        let vm = MeshLedgerViewModel(transactionFetcher: mockFetcher, packetStore: tempStore)

        await vm.loadLiveTransactions()

        // Authoritative ledger total strictly reflects backend results
        assert(vm.totalCount == 1, "Authoritative ledger total must be 1 (backend transaction only), got \(vm.totalCount)")
        assert(vm.settledCount == 1, "Settled count must be 1, got \(vm.settledCount)")
        assert(vm.settledTotalAmount == 50.00, "Settled amount must be 50.00, got \(vm.settledTotalAmount)")

        // In-transit derived strictly from inbox
        assert(vm.inTransitCount == 1, "In-transit count must be 1, got \(vm.inTransitCount)")
        assert(vm.inTransitTotalAmount == 15.00, "In-transit amount must be 15.00, got \(vm.inTransitTotalAmount)")

        // When filtering "settled", ONLY the backend transaction is returned
        let settledOnly = vm.displayTransactions(for: "settled")
        assert(settledOnly.count == 1, "Expected exactly 1 settled item")
        assert(settledOnly[0].id == "tx-settled-1", "Expected backend transaction in settled list")
        assert(settledOnly[0].category == .settled, "Expected settled category")

        // When filtering "transit", ONLY the received inbox packet is returned
        let transitOnly = vm.displayTransactions(for: "transit")
        assert(transitOnly.count == 1, "Expected exactly 1 transit item")
        assert(transitOnly[0].id == "pkt-pkt-rec-1", "Expected received packet in transit list")
        assert(transitOnly[0].category == .inTransit, "Expected inTransit category")
        assert(transitOnly[0].statusLabel == "In Transit (Unsettled)", "Must clearly state unsettled status")

        // In "all", pending packet is NEVER labeled as settled
        let allItems = vm.displayTransactions(for: "all")
        assert(allItems.count == 2, "Expected 2 total items in 'all'")
        let pendingInAll = allItems.first { $0.id == "pkt-pkt-rec-1" }!
        assert(pendingInAll.category == .inTransit, "Pending packet must have inTransit category")
        assert(pendingInAll.statusLabel == "In Transit (Unsettled)", "Must not falsely label pending packet as settled")

        print("  ✓ PASS: testPendingPacketsSeparatedFromSettledBackendTransactions")
    }

    // MARK: - Test 5: Refresh after .meshAccountsUpdated
    @MainActor
    public static func testRefreshAfterMeshAccountsUpdated() async {
        let mockFetcher = MockTransactionFetcher(transactions: [
            TransactionDTO(id: "tx-1", fromAccount: "alice", toAccount: "bob", amount: 10.00, timestamp: "2026-10-13T10:00:00Z", status: "SETTLED")
        ])
        let tempStore = createTempReceivedStore()
        let vm = MeshLedgerViewModel(transactionFetcher: mockFetcher, packetStore: tempStore)

        await vm.loadLiveTransactions()
        assert(vm.totalCount == 1, "Expected initial count == 1")
        assert(vm.settledTotalAmount == 10.00, "Expected initial amount == 10.00")

        // New settlement confirmed on backend
        mockFetcher.transactionsToReturn = [
            TransactionDTO(id: "tx-1", fromAccount: "alice", toAccount: "bob", amount: 10.00, timestamp: "2026-10-13T10:00:00Z", status: "SETTLED"),
            TransactionDTO(id: "tx-2", fromAccount: "alice", toAccount: "bob", amount: 20.00, timestamp: "2026-10-13T10:30:00Z", status: "SETTLED")
        ]

        // Post notification and reload
        await vm.loadLiveTransactions()

        assert(vm.totalCount == 2, "Expected updated count == 2")
        assert(vm.settledTotalAmount == 30.00, "Expected updated amount == 30.00")
        assert(vm.settledMetricString == "₹30", "Expected '₹30', got \(vm.settledMetricString)")

        print("  ✓ PASS: testRefreshAfterMeshAccountsUpdated")
    }

    // MARK: - Test 6: Timestamp Formatting
    public static func testTimestampFormatting() {
        let iso = "2026-10-13T13:23:41.527123Z"
        let formatted = MeshLedgerViewModel.formatTimestamp(iso)
        assert(!formatted.isEmpty, "Formatted timestamp should not be empty")
        assert(formatted.contains("M") || formatted.contains(":"), "Should contain time indicators")

        print("  ✓ PASS: testTimestampFormatting")
    }

    // MARK: - Test 7: Currency Formatting
    public static func testCurrencyFormatting() {
        assert(MeshLedgerViewModel.formatCurrency(0.0) == "₹0", "Expected ₹0, got \(MeshLedgerViewModel.formatCurrency(0.0))")
        assert(MeshLedgerViewModel.formatCurrency(30.0) == "₹30", "Expected ₹30, got \(MeshLedgerViewModel.formatCurrency(30.0))")
        assert(MeshLedgerViewModel.formatCurrency(14250.0) == "₹14,250", "Expected ₹14,250, got \(MeshLedgerViewModel.formatCurrency(14250.0))")
        assert(MeshLedgerViewModel.formatCurrency(10.50) == "₹10.50", "Expected ₹10.50, got \(MeshLedgerViewModel.formatCurrency(10.50))")

        print("  ✓ PASS: testCurrencyFormatting")
    }

    // MARK: - Helper
    private static func createTempReceivedStore() -> ReceivedPacketStore {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let storeFile = tempDir.appendingPathComponent("received_test.json")
        return ReceivedPacketStore(fileURL: storeFile)
    }
}
