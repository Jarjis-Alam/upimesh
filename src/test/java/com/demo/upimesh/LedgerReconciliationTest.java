package com.demo.upimesh;

import com.demo.upimesh.model.Account;
import com.demo.upimesh.model.AccountRepository;
import com.demo.upimesh.model.MeshPacket;
import com.demo.upimesh.model.PaymentInstruction;
import com.demo.upimesh.model.ProcessedPacketRepository;
import com.demo.upimesh.model.ReconciliationReport;
import com.demo.upimesh.model.ReconciliationReport.AccountReconciliationEntry;
import com.demo.upimesh.model.ReconciliationReport.AccountStatus;
import com.demo.upimesh.model.ReconciliationReport.BalanceStatus;
import com.demo.upimesh.model.ReconciliationReport.StructuralStatus;
import com.demo.upimesh.model.TransactionRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import java.math.BigDecimal;
import java.security.GeneralSecurityException;
import java.security.KeyPair;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Test suite verifying ledger integrity, mathematical reconciliation correctness,
 * and decoupling of structural checks from balance verification (Stage 11.5).
 */
@SpringBootTest
class LedgerReconciliationTest {

    @Autowired
    private SettlementService settlementService;

    @Autowired
    private ReconciliationService reconciliationService;

    @Autowired
    private BridgeIngestionService bridgeIngestionService;

    @Autowired
    private CryptoService cryptoService;

    @Autowired
    private AccountRepository accountRepository;

    @Autowired
    private TransactionRepository transactionRepository;

    @Autowired
    private ProcessedPacketRepository processedPacketRepository;

    @Autowired
    private MeshSimulatorService meshSimulatorService;

    private KeyPair bridgeKeyPair;
    private KeyPair aliceKeyPair;
    private KeyPair bobKeyPair;

    @BeforeEach
    void setUp() throws GeneralSecurityException {
        processedPacketRepository.deleteAll();
        transactionRepository.deleteAll();
        accountRepository.deleteAll();

        // Baseline seed balances: Alice: 5000, Bob: 1000, Carol: 2000
        accountRepository.saveAll(List.of(
                new Account("alice", new BigDecimal("5000.00")),
                new Account("bob", new BigDecimal("1000.00")),
                new Account("carol", new BigDecimal("2000.00"))
        ));

        meshSimulatorService.reset();
        meshSimulatorService.initDefaultTopology();

        bridgeKeyPair = meshSimulatorService.getBridgeKeyPair();
        if (bridgeKeyPair == null) {
            bridgeKeyPair = cryptoService.generateRsaKeyPair();
            meshSimulatorService.setBridgeKeyPair(bridgeKeyPair);
        }

        aliceKeyPair = cryptoService.generateRsaKeyPair();
        bobKeyPair = cryptoService.generateRsaKeyPair();

        meshSimulatorService.registerSenderKeyPair("alice", aliceKeyPair);
        meshSimulatorService.registerSenderKeyPair("bob", bobKeyPair);
    }

    private MeshPacket createSignedMeshPacket(String from, String to, BigDecimal amount, KeyPair signerKey) throws GeneralSecurityException {
        PaymentInstruction unsigned = PaymentInstruction.create(from, to, amount);
        String signature = cryptoService.signBase64(unsigned.toCanonicalBytes(), signerKey.getPrivate());
        PaymentInstruction signed = unsigned.withSignature(signature);

        String json = bridgeIngestionService.serializeInstruction(signed);
        EncryptedPacket encryptedPacket = cryptoService.encrypt(json, bridgeKeyPair.getPublic());
        return MeshPacket.create("node_test_sender", "BRIDGE", 5, encryptedPacket);
    }

    @Test
    @DisplayName("1. Successful single transfer reconciles debit, credit, and closing balances")
    void successfulDebitCreditReconciliation_singleTransfer() {
        settlementService.transfer("alice", "bob", new BigDecimal("350.00"));

        ReconciliationReport report = reconciliationService.reconcile();

        assertTrue(report.isReconciled(), "Report should indicate clean overall reconciliation");
        assertTrue(report.isLedgerBalanced(), "Structural ledger must be balanced");
        assertTrue(report.isBalancesReconciled(), "Account balances must agree with opening + movements");
        assertEquals(StructuralStatus.BALANCED, report.structuralStatus());
        assertEquals(BalanceStatus.RECONCILED, report.balanceStatus());
        assertTrue(report.systemZeroSumMaintained(), "Total debits must equal total credits");
        assertEquals(1, report.totalTransactionsChecked());
        assertEquals(new BigDecimal("350.00"), report.totalLedgerDebits());
        assertEquals(new BigDecimal("350.00"), report.totalLedgerCredits());
        assertTrue(report.discrepancies().isEmpty(), "No discrepancies should be reported");
        assertTrue(report.unverifiableAccounts().isEmpty());

        // Verify Alice details
        AccountReconciliationEntry alice = report.accountResults().stream()
                .filter(a -> a.accountId().equalsIgnoreCase("alice")).findFirst().orElseThrow();
        assertEquals(new BigDecimal("5000.00"), alice.openingBalance());
        assertEquals(0, alice.totalCredits().compareTo(BigDecimal.ZERO));
        assertEquals(new BigDecimal("350.00"), alice.totalDebits());
        assertEquals(new BigDecimal("-350.00"), alice.netMovement());
        assertEquals(new BigDecimal("4650.00"), alice.expectedBalance());
        assertEquals(new BigDecimal("4650.00"), alice.actualBalance());
        assertEquals(0, alice.discrepancy().compareTo(BigDecimal.ZERO));
        assertEquals(AccountStatus.RECONCILED, alice.status());
        assertTrue(alice.matches());

        // Verify Bob details
        AccountReconciliationEntry bob = report.accountResults().stream()
                .filter(a -> a.accountId().equalsIgnoreCase("bob")).findFirst().orElseThrow();
        assertEquals(new BigDecimal("1000.00"), bob.openingBalance());
        assertEquals(new BigDecimal("350.00"), bob.totalCredits());
        assertEquals(0, bob.totalDebits().compareTo(BigDecimal.ZERO));
        assertEquals(new BigDecimal("350.00"), bob.netMovement());
        assertEquals(new BigDecimal("1350.00"), bob.expectedBalance());
        assertEquals(new BigDecimal("1350.00"), bob.actualBalance());
        assertEquals(0, bob.discrepancy().compareTo(BigDecimal.ZERO));
        assertEquals(AccountStatus.RECONCILED, bob.status());
        assertTrue(bob.matches());
    }

    @Test
    @DisplayName("2. Multiple transfers across different accounts reconcile correctly")
    void multipleTransfers_allAccountsReconcileAccurately() {
        // T1: Alice -> Bob 300.00
        settlementService.transfer("alice", "bob", new BigDecimal("300.00"));
        // T2: Bob -> Carol 150.00
        settlementService.transfer("bob", "carol", new BigDecimal("150.00"));
        // T3: Carol -> Alice 50.00
        settlementService.transfer("carol", "alice", new BigDecimal("50.00"));

        ReconciliationReport report = reconciliationService.reconcile();

        assertTrue(report.isReconciled());
        assertTrue(report.isLedgerBalanced());
        assertTrue(report.isBalancesReconciled());
        assertEquals(StructuralStatus.BALANCED, report.structuralStatus());
        assertEquals(BalanceStatus.RECONCILED, report.balanceStatus());
        assertEquals(3, report.totalTransactionsChecked());
        assertEquals(new BigDecimal("500.00"), report.totalLedgerDebits());
        assertEquals(new BigDecimal("500.00"), report.totalLedgerCredits());
        assertTrue(report.discrepancies().isEmpty());

        // Alice: 5000 - 300 + 50 = 4750.00
        assertEquals(new BigDecimal("4750.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        // Bob: 1000 + 300 - 150 = 1150.00
        assertEquals(new BigDecimal("1150.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        // Carol: 2000 + 150 - 50 = 2100.00
        assertEquals(new BigDecimal("2100.00"), accountRepository.findById("carol").orElseThrow().getBalance());
    }

    @Test
    @DisplayName("3. Altered account balance is detected and reported without silent mutation")
    void alteredAccountBalance_isDetectedAndReportedWithoutSilentMutation() {
        settlementService.transfer("alice", "bob", new BigDecimal("200.00"));

        // Intentionally tamper with Alice's balance in the database
        Account alice = accountRepository.findById("alice").orElseThrow();
        alice.setBalance(new BigDecimal("9999.00"));
        accountRepository.save(alice);

        // Run reconciliation audit
        ReconciliationReport report = reconciliationService.reconcile();

        assertFalse(report.isReconciled(), "Report must flag detected discrepancy");
        assertFalse(report.isBalancesReconciled());
        assertEquals(BalanceStatus.DISCREPANCY, report.balanceStatus());
        assertFalse(report.discrepancies().isEmpty(), "Must list discrepancy details");
        assertTrue(report.discrepancies().get(0).contains("alice"));

        AccountReconciliationEntry aliceEntry = report.accountResults().stream()
                .filter(a -> a.accountId().equalsIgnoreCase("alice")).findFirst().orElseThrow();
        assertEquals(AccountStatus.DISCREPANCY, aliceEntry.status());
        assertFalse(aliceEntry.matches());
        assertEquals(new BigDecimal("4800.00"), aliceEntry.expectedBalance());
        assertEquals(new BigDecimal("9999.00"), aliceEntry.actualBalance());
        assertEquals(new BigDecimal("5199.00"), aliceEntry.discrepancy());

        // CRITICAL: Ensure reconciliation did NOT silently modify Alice's balance or ledger
        assertEquals(new BigDecimal("9999.00"), accountRepository.findById("alice").orElseThrow().getBalance(),
                "Reconciliation must be strictly read-only and never silently mutate balances");
        assertEquals(1, transactionRepository.count(), "Ledger history must remain unaltered");
    }

    @Test
    @DisplayName("4. A balanced ledger can still disagree with account balances")
    void balancedLedger_canStillDisagreeWithAccountBalances() {
        settlementService.transfer("alice", "bob", new BigDecimal("100.00"));

        // Tamper Bob's balance directly
        Account bob = accountRepository.findById("bob").orElseThrow();
        bob.setBalance(new BigDecimal("8888.00"));
        accountRepository.save(bob);

        ReconciliationReport report = reconciliationService.reconcile();

        // Structural ledger check passes (journal is internally balanced)
        assertTrue(report.isLedgerBalanced(), "Ledger entries are internally balanced");
        assertTrue(report.systemZeroSumMaintained());
        assertEquals(StructuralStatus.BALANCED, report.structuralStatus());
        assertEquals(new BigDecimal("100.00"), report.totalLedgerDebits());
        assertEquals(new BigDecimal("100.00"), report.totalLedgerCredits());

        // BUT account balance reconciliation fails
        assertFalse(report.isBalancesReconciled(), "Balanced ledger does not prove account balances are correct");
        assertEquals(BalanceStatus.DISCREPANCY, report.balanceStatus());
        assertFalse(report.isReconciled());

        AccountReconciliationEntry bobEntry = report.accountResults().stream()
                .filter(a -> a.accountId().equalsIgnoreCase("bob")).findFirst().orElseThrow();
        assertEquals(AccountStatus.DISCREPANCY, bobEntry.status());
        assertFalse(bobEntry.matches());
        assertEquals(new BigDecimal("1100.00"), bobEntry.expectedBalance());
        assertEquals(new BigDecimal("8888.00"), bobEntry.actualBalance());
    }

    @Test
    @DisplayName("5. Missing or unknown opening balances are explicitly reported as unverifiable")
    void missingOrUnknownOpeningBalances_reportedAsUnverifiable() {
        settlementService.transfer("alice", "bob", new BigDecimal("100.00"));

        // Supply opening balance only for Alice, leaving Bob and Carol without opening balances
        Map<String, BigDecimal> partialOpeningBalances = Map.of(
                "alice", new BigDecimal("5000.00")
        );

        ReconciliationReport report = reconciliationService.reconcile(partialOpeningBalances);

        // Structural check is balanced
        assertTrue(report.isLedgerBalanced());
        assertEquals(StructuralStatus.BALANCED, report.structuralStatus());

        // But balance reconciliation cannot verify unseeded accounts
        assertFalse(report.isBalancesReconciled());
        assertEquals(BalanceStatus.UNVERIFIABLE, report.balanceStatus());
        assertFalse(report.isReconciled());

        // Check unverifiable accounts list
        assertTrue(report.unverifiableAccounts().contains("bob"));
        assertTrue(report.unverifiableAccounts().contains("carol"));

        // Alice is verified
        AccountReconciliationEntry aliceEntry = report.accountResults().stream()
                .filter(a -> a.accountId().equalsIgnoreCase("alice")).findFirst().orElseThrow();
        assertEquals(AccountStatus.RECONCILED, aliceEntry.status());
        assertTrue(aliceEntry.matches());

        // Bob is unverifiable
        AccountReconciliationEntry bobEntry = report.accountResults().stream()
                .filter(a -> a.accountId().equalsIgnoreCase("bob")).findFirst().orElseThrow();
        assertEquals(AccountStatus.UNVERIFIABLE, bobEntry.status());
        assertFalse(bobEntry.matches());
        assertNull(bobEntry.openingBalance());
        assertNull(bobEntry.expectedBalance());
        assertNull(bobEntry.discrepancy());

        // Report contains clear explanation
        assertTrue(report.discrepancies().stream().anyMatch(d -> d.contains("bob") && d.contains("cannot be fully reconciled")));
    }

    @Test
    @DisplayName("6. Failed transfers do not affect reconciliation")
    void failedTransfers_doNotAffectReconciliation() throws GeneralSecurityException {
        // Successful transfer first
        settlementService.transfer("alice", "bob", new BigDecimal("100.00"));

        // 1. Failed transfer: insufficient funds
        assertThrows(IllegalStateException.class, () ->
                settlementService.transfer("alice", "bob", new BigDecimal("10000.00"))
        );

        // 2. Failed transfer: self-transfer
        assertThrows(IllegalArgumentException.class, () ->
                settlementService.transfer("alice", "alice", new BigDecimal("50.00"))
        );

        // 3. Failed transfer: negative amount
        assertThrows(IllegalArgumentException.class, () ->
                settlementService.transfer("alice", "bob", new BigDecimal("-50.00"))
        );

        // 4. Failed transfer: invalid signature
        PaymentInstruction unsigned = PaymentInstruction.create("alice", "bob", new BigDecimal("50.00"));
        PaymentInstruction signedWithBogusSig = unsigned.withSignature("AAAA");
        String json = bridgeIngestionService.serializeInstruction(signedWithBogusSig);
        EncryptedPacket encryptedPacket = cryptoService.encrypt(json, bridgeKeyPair.getPublic());
        MeshPacket bogusPacket = MeshPacket.create("node_test", "BRIDGE", 5, encryptedPacket);
        assertThrows(GeneralSecurityException.class, () ->
                bridgeIngestionService.ingest(bogusPacket, bridgeKeyPair.getPrivate())
        );

        // Ledger must contain ONLY the 1 successful transfer
        assertEquals(1, transactionRepository.count());

        // Reconciliation passes cleanly
        ReconciliationReport report = reconciliationService.reconcile();
        assertTrue(report.isReconciled());
        assertTrue(report.isLedgerBalanced());
        assertTrue(report.isBalancesReconciled());
        assertEquals(1, report.totalTransactionsChecked());
        assertEquals(new BigDecimal("100.00"), report.totalLedgerDebits());
        assertEquals(new BigDecimal("100.00"), report.totalLedgerCredits());
    }

    @Test
    @DisplayName("7. Structural ledger checks and account-balance reconciliation have distinct, accurate statuses")
    void structuralLedgerChecks_andAccountBalanceReconciliation_haveDistinctAccurateStatuses() {
        settlementService.transfer("alice", "bob", new BigDecimal("100.00"));
        settlementService.transfer("bob", "carol", new BigDecimal("40.00"));

        // Call read-only consistency check without opening balances
        ReconciliationReport report = reconciliationService.reconcileConsistencyOnly();

        // Structural ledger invariants are proven balanced
        assertTrue(report.isLedgerBalanced(), "Structural check must pass for balanced transactions");
        assertTrue(report.systemZeroSumMaintained(), "Zero-sum invariant maintained");
        assertEquals(StructuralStatus.BALANCED, report.structuralStatus());
        assertEquals(2, report.totalTransactionsChecked());
        assertEquals(new BigDecimal("140.00"), report.totalLedgerDebits());
        assertEquals(new BigDecimal("140.00"), report.totalLedgerCredits());

        // But account balances are NOT claimed to be verified/reconciled
        assertFalse(report.isBalancesReconciled(), "Balances must not be claimed verified without opening balances");
        assertEquals(BalanceStatus.UNVERIFIABLE, report.balanceStatus());
        assertFalse(report.isReconciled(), "Report must not be marked fully reconciled without opening balances");

        // All accounts are reported as unverifiable
        assertEquals(3, report.unverifiableAccounts().size());
        for (AccountReconciliationEntry entry : report.accountResults()) {
            assertEquals(AccountStatus.UNVERIFIABLE, entry.status());
            assertFalse(entry.matches());
            assertNull(entry.openingBalance());
            assertNull(entry.expectedBalance());
            assertNull(entry.discrepancy());
        }
    }

    @Test
    @DisplayName("8. Duplicate packet replay leaves ledger and balances unchanged")
    void duplicatePacket_leavesLedgerAndBalancesUnchanged() throws GeneralSecurityException {
        MeshPacket packet = createSignedMeshPacket("alice", "bob", new BigDecimal("120.00"), aliceKeyPair);

        // First ingestion succeeds
        assertNotNull(bridgeIngestionService.ingest(packet, bridgeKeyPair.getPrivate()));
        assertEquals(1, transactionRepository.count());

        // Duplicate ingestion attempt
        assertThrows(DuplicatePacketException.class, () ->
                bridgeIngestionService.ingest(packet, bridgeKeyPair.getPrivate())
        );

        assertEquals(1, transactionRepository.count(), "Duplicate packet must not create additional ledger entry");
        assertEquals(new BigDecimal("4880.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1120.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertTrue(reconciliationService.reconcile().isReconciled());
    }

    @Test
    @DisplayName("9. Concurrent transfers remain safe under optimistic locking and reconcile cleanly")
    void concurrentTransfers_safelyHandledWithOptimisticLockingAndReconciliation() throws Exception {
        int threadCount = 10;
        BigDecimal transferAmount = new BigDecimal("20.00");
        ExecutorService executor = Executors.newFixedThreadPool(threadCount);
        CountDownLatch startLatch = new CountDownLatch(1);
        AtomicInteger successCount = new AtomicInteger(0);
        List<Future<?>> futures = new ArrayList<>();

        for (int i = 0; i < threadCount; i++) {
            futures.add(executor.submit(() -> {
                try {
                    startLatch.await();
                    settlementService.transfer("alice", "bob", transferAmount);
                    successCount.incrementAndGet();
                } catch (Exception e) {
                    // Optimistic locking or lock acquisition collisions safely roll back
                }
            }));
        }

        startLatch.countDown();
        for (Future<?> f : futures) {
            f.get();
        }
        executor.shutdown();

        int successes = successCount.get();
        assertTrue(successes >= 1, "At least one concurrent transfer must succeed");
        assertEquals(successes, transactionRepository.count(), "Ledger count must match exactly the number of committed transfers");

        BigDecimal totalTransferred = transferAmount.multiply(new BigDecimal(successes));
        assertEquals(new BigDecimal("5000.00").subtract(totalTransferred),
                accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1000.00").add(totalTransferred),
                accountRepository.findById("bob").orElseThrow().getBalance());

        // Full reconciliation must pass with 0 discrepancies
        ReconciliationReport report = reconciliationService.reconcile();
        assertTrue(report.isReconciled());
        assertTrue(report.isLedgerBalanced());
        assertTrue(report.isBalancesReconciled());
        assertTrue(report.discrepancies().isEmpty());
    }
}
