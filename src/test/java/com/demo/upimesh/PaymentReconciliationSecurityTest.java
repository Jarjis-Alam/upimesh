package com.demo.upimesh;

import com.demo.upimesh.model.Account;
import com.demo.upimesh.model.AccountRepository;
import com.demo.upimesh.model.DeviceAuthorizationRequest;
import com.demo.upimesh.model.KeyRegistrationRequest;
import com.demo.upimesh.model.MeshPaymentResult;
import com.demo.upimesh.model.PaymentInstruction;
import com.demo.upimesh.model.PaymentStatusResponse;
import com.demo.upimesh.model.ProcessedPacketRepository;
import com.demo.upimesh.model.ReconciliationReport;
import com.demo.upimesh.model.SignedPaymentRequest;
import com.demo.upimesh.model.TransactionRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import java.math.BigDecimal;
import java.security.GeneralSecurityException;
import java.security.KeyPair;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Targeted security and reconciliation tests verifying:
 * - Authoritative status query (GET /api/mesh/status/{paymentId})
 * - Conflicting paymentId reuse rejection
 * - Nonce replay rejection
 * - Idempotent replay without duplicate debit
 * - Timeout recovery simulation
 * - Safe concurrent submission handling
 * - Zero balance mutation on rejected or duplicate requests
 */
@SpringBootTest
class PaymentReconciliationSecurityTest {

    @Autowired
    private ApiController apiController;

    @Autowired
    private CryptoService cryptoService;

    @Autowired
    private AccountRepository accountRepository;

    @Autowired
    private TransactionRepository transactionRepository;

    @Autowired
    private ProcessedPacketRepository processedPacketRepository;

    @Autowired
    private DeviceAuthorizationRegistry deviceAuthorizationRegistry;

    @Autowired
    private SenderKeyRegistry senderKeyRegistry;

    @Autowired
    private ReconciliationService reconciliationService;

    private KeyPair aliceDeviceKeyPair;
    private final String aliceDeviceId = "test-sec-alice-device";

    @BeforeEach
    void setUp() throws GeneralSecurityException {
        // Clear repositories to deterministic test baseline
        processedPacketRepository.deleteAll();
        transactionRepository.deleteAll();
        accountRepository.deleteAll();
        senderKeyRegistry.clearForTesting();
        deviceAuthorizationRegistry.clearForTesting();

        accountRepository.save(new Account("alice", new BigDecimal("5000.00")));
        accountRepository.save(new Account("bob", new BigDecimal("1000.00")));
        accountRepository.save(new Account("carol", new BigDecimal("2000.00")));

        aliceDeviceKeyPair = cryptoService.generateRsaKeyPair();
        String alicePubKeyBase64 = Base64.getEncoder().encodeToString(aliceDeviceKeyPair.getPublic().getEncoded());
        apiController.registerSenderKey(new KeyRegistrationRequest(aliceDeviceId, alicePubKeyBase64), null, null);

        apiController.setConfiguredAdminToken("test-admin-secret-token");
        apiController.authorizeDevice(
                new DeviceAuthorizationRequest(aliceDeviceId, "alice"),
                "test-admin-secret-token",
                null
        );
    }

    private PaymentInstruction createSignedInstruction(String paymentId, String from, String to, BigDecimal amount, String nonce, KeyPair signerKey) throws GeneralSecurityException {
        PaymentInstruction unsigned = new PaymentInstruction(
                paymentId,
                from,
                to,
                amount,
                Instant.now(),
                nonce,
                null
        );
        String signature = cryptoService.signBase64(unsigned.toCanonicalBytes(), signerKey.getPrivate());
        return unsigned.withSignature(signature);
    }

    private PaymentInstruction createSignedInstruction(String paymentId, String from, String to, BigDecimal amount, String nonce) throws GeneralSecurityException {
        return createSignedInstruction(paymentId, from, to, amount, nonce, aliceDeviceKeyPair);
    }

    @Test
    @DisplayName("1. Authoritative status query returns 404 for unsettled payment")
    void getPaymentStatus_notFound_returns404() {
        ResponseEntity<PaymentStatusResponse> response = apiController.getPaymentStatus("unknown-pay-id-12345");
        assertEquals(HttpStatus.NOT_FOUND, response.getStatusCode());
        assertNotNull(response.getBody());
        assertFalse(response.getBody().found());
        assertEquals("NOT_FOUND", response.getBody().status());
    }

    @Test
    @DisplayName("2. Authoritative status query returns 200 with details after committed settlement")
    void getPaymentStatus_afterSettlement_returns200WithAccurateDetails() throws Exception {
        String paymentId = "pay-status-test-" + UUID.randomUUID();
        PaymentInstruction signed = createSignedInstruction(paymentId, "alice", "bob", new BigDecimal("75.00"), "nonce-st-1");

        ResponseEntity<MeshPaymentResult> submitResp = apiController.submitSignedMeshPayment(new SignedPaymentRequest(aliceDeviceId, signed));
        assertEquals(HttpStatus.OK, submitResp.getStatusCode());

        ResponseEntity<PaymentStatusResponse> statusResp = apiController.getPaymentStatus(paymentId);
        assertEquals(HttpStatus.OK, statusResp.getStatusCode());
        assertNotNull(statusResp.getBody());
        assertTrue(statusResp.getBody().found());
        assertEquals("SETTLED", statusResp.getBody().status());
        assertEquals("alice", statusResp.getBody().fromAccount());
        assertEquals("bob", statusResp.getBody().toAccount());
        assertEquals(new BigDecimal("75.00"), statusResp.getBody().amount());
        assertNotNull(statusResp.getBody().packetHash());
    }

    @Test
    @DisplayName("3. Same payment ID with conflicting instruction data is rejected without altering balances")
    void submit_samePaymentIdConflictingData_rejected() throws Exception {
        String paymentId = "pay-conflict-" + UUID.randomUUID();
        PaymentInstruction first = createSignedInstruction(paymentId, "alice", "bob", new BigDecimal("100.00"), "nonce-orig");
        apiController.submitSignedMeshPayment(new SignedPaymentRequest(aliceDeviceId, first));

        assertEquals(new BigDecimal("4900.00"), accountRepository.findById("alice").orElseThrow().getBalance());

        // Attacker attempts to reuse the same paymentId for a larger transfer of 900.00
        PaymentInstruction conflicting = createSignedInstruction(paymentId, "alice", "bob", new BigDecimal("900.00"), "nonce-diff");

        DuplicatePacketException ex = assertThrows(DuplicatePacketException.class, () ->
                apiController.submitSignedMeshPayment(new SignedPaymentRequest(aliceDeviceId, conflicting))
        );
        assertTrue(ex.getMessage().contains("Conflicting payment instruction rejected"));

        // Balances and transaction counts unaltered
        assertEquals(new BigDecimal("4900.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1100.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(1, transactionRepository.count());
    }

    @Test
    @DisplayName("4. Retrying settled payment with explicit idempotent replay returns SETTLED without second debit")
    void submit_idempotentReplay_returnsSettledWithoutSecondDebit() throws Exception {
        String paymentId = "pay-idemp-" + UUID.randomUUID();
        PaymentInstruction signed = createSignedInstruction(paymentId, "alice", "bob", new BigDecimal("200.00"), "nonce-idemp-1");
        SignedPaymentRequest request = new SignedPaymentRequest(aliceDeviceId, signed);

        // First attempt succeeds
        ResponseEntity<MeshPaymentResult> firstResp = apiController.submitSignedMeshPayment(request);
        assertEquals(HttpStatus.OK, firstResp.getStatusCode());
        assertEquals(new BigDecimal("4800.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(1, transactionRepository.count());

        // Client retry simulating network recovery with X-Idempotent-Replay header
        ResponseEntity<MeshPaymentResult> retryResp = apiController.submitSignedMeshPayment(request, "true", false);
        assertEquals(HttpStatus.OK, retryResp.getStatusCode());
        assertNotNull(retryResp.getBody());
        assertEquals("SETTLED", retryResp.getBody().status());
        assertTrue(retryResp.getBody().message().contains("idempotent"));

        // CRITICAL: Balances and transactions remain exactly 1 transfer
        assertEquals(new BigDecimal("4800.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1200.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(1, transactionRepository.count());
        assertEquals(1, processedPacketRepository.count());
    }

    @Test
    @DisplayName("5. Client timeout recovery: query status confirms settlement and allows idempotent retry")
    void timeoutRecovery_queryStatusConfirmsSettlement() throws Exception {
        String paymentId = "pay-timeout-sim-" + UUID.randomUUID();
        PaymentInstruction signed = createSignedInstruction(paymentId, "alice", "bob", new BigDecimal("150.00"), "nonce-to-1");
        SignedPaymentRequest request = new SignedPaymentRequest(aliceDeviceId, signed);

        // Backend commits payment
        apiController.submitSignedMeshPayment(request);

        // Simulate client that timed out and queries authoritative status
        ResponseEntity<PaymentStatusResponse> query = apiController.getPaymentStatus(paymentId);
        assertEquals(HttpStatus.OK, query.getStatusCode());
        assertTrue(query.getBody().found());
        assertEquals("SETTLED", query.getBody().status());

        // Client also performs idempotent retry
        ResponseEntity<MeshPaymentResult> retry = apiController.submitSignedMeshPayment(request, "true", false);
        assertEquals(HttpStatus.OK, retry.getStatusCode());
        assertEquals("SETTLED", retry.getBody().status());

        // Exactly one debit occurs
        assertEquals(new BigDecimal("4850.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1150.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(1, transactionRepository.count());
    }

    @Test
    @DisplayName("6. Concurrent submissions of the same payment result in exactly one debit")
    void concurrentSubmissions_exactOneDebit() throws Exception {
        String paymentId = "pay-conc-" + UUID.randomUUID();
        PaymentInstruction signed = createSignedInstruction(paymentId, "alice", "bob", new BigDecimal("300.00"), "nonce-conc-1");
        SignedPaymentRequest request = new SignedPaymentRequest(aliceDeviceId, signed);

        int threads = 8;
        ExecutorService executor = Executors.newFixedThreadPool(threads);
        CountDownLatch latch = new CountDownLatch(1);
        AtomicInteger settledCount = new AtomicInteger(0);
        AtomicInteger duplicateCount = new AtomicInteger(0);
        List<Future<?>> futures = new ArrayList<>();

        for (int i = 0; i < threads; i++) {
            futures.add(executor.submit(() -> {
                try {
                    latch.await();
                    // Each thread requests idempotent submission
                    ResponseEntity<MeshPaymentResult> res = apiController.submitSignedMeshPayment(request, "true", false);
                    if (res.getStatusCode() == HttpStatus.OK && "SETTLED".equalsIgnoreCase(res.getBody().status())) {
                        settledCount.incrementAndGet();
                    }
                } catch (DuplicatePacketException e) {
                    duplicateCount.incrementAndGet();
                } catch (Exception e) {
                    // unexpected error
                }
            }));
        }

        latch.countDown();
        for (Future<?> f : futures) {
            f.get();
        }
        executor.shutdown();

        // All threads either receive confirmed SETTLED or clean duplicate rejection
        assertEquals(threads, settledCount.get() + duplicateCount.get());
        assertTrue(settledCount.get() >= 1, "At least one thread must settle the payment");

        // CRITICAL INVARIANT: Balances debited exactly ONCE
        assertEquals(new BigDecimal("4700.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1300.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(1, transactionRepository.count());
        assertEquals(1, processedPacketRepository.count());
    }

    @Test
    @DisplayName("7. Nonce reuse for same sender across different payments is rejected without altering balances")
    void submit_replayedNonceDifferentPaymentId_rejected() throws Exception {
        String nonce = "shared-nonce-sec-" + UUID.randomUUID();
        PaymentInstruction p1 = createSignedInstruction("pay-nonce-a-" + UUID.randomUUID(), "alice", "bob", new BigDecimal("50.00"), nonce);
        apiController.submitSignedMeshPayment(new SignedPaymentRequest(aliceDeviceId, p1));

        assertEquals(new BigDecimal("4950.00"), accountRepository.findById("alice").orElseThrow().getBalance());

        // Second instruction with different payment ID but SAME nonce
        PaymentInstruction p2 = createSignedInstruction("pay-nonce-b-" + UUID.randomUUID(), "alice", "bob", new BigDecimal("75.00"), nonce);

        DuplicatePacketException ex = assertThrows(DuplicatePacketException.class, () ->
                apiController.submitSignedMeshPayment(new SignedPaymentRequest(aliceDeviceId, p2))
        );
        assertTrue(ex.getMessage().contains("nonce already used for sender alice"));

        // Balances debited only once
        assertEquals(new BigDecimal("4950.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1050.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(1, transactionRepository.count());
    }

    @Test
    @DisplayName("8. Unauthorized device attempting debit is rejected fail-closed without altering balances")
    void submit_unauthorizedDevice_rejectedWithoutAlteringBalances() throws Exception {
        KeyPair rogueKey = cryptoService.generateRsaKeyPair();
        String rogueDeviceId = "rogue-dev-" + UUID.randomUUID();
        String roguePubB64 = Base64.getEncoder().encodeToString(rogueKey.getPublic().getEncoded());
        apiController.registerSenderKey(new KeyRegistrationRequest(rogueDeviceId, roguePubB64), null, null);

        // Rogue device creates instruction claiming to debit alice
        PaymentInstruction unsigned = new PaymentInstruction(
                "pay-unauth-" + UUID.randomUUID(),
                "alice",
                "carol",
                new BigDecimal("500.00"),
                Instant.now(),
                "nonce-unauth",
                null
        );
        String sig = cryptoService.signBase64(unsigned.toCanonicalBytes(), rogueKey.getPrivate());
        SignedPaymentRequest request = new SignedPaymentRequest(rogueDeviceId, unsigned.withSignature(sig));

        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () ->
                apiController.submitSignedMeshPayment(request)
        );
        assertTrue(ex.getMessage().contains("is not authorized to debit account 'alice'"));

        // Zero balance mutation
        assertEquals(new BigDecimal("5000.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("2000.00"), accountRepository.findById("carol").orElseThrow().getBalance());
        assertEquals(0, transactionRepository.count());
    }

    @Test
    @DisplayName("9. Tampered payment instruction is rejected without altering balances")
    void submit_tamperedInstruction_rejectedWithoutAlteringBalances() throws Exception {
        PaymentInstruction genuine = createSignedInstruction("pay-tamp-" + UUID.randomUUID(), "alice", "bob", new BigDecimal("100.00"), "nonce-tamp");

        // Tamper with amount while keeping original signature
        PaymentInstruction tampered = new PaymentInstruction(
                genuine.paymentId(),
                genuine.fromAccount(),
                genuine.toAccount(),
                new BigDecimal("999.00"), // altered!
                genuine.createdAt(),
                genuine.nonce(),
                genuine.signature()
        );

        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () ->
                apiController.submitSignedMeshPayment(new SignedPaymentRequest(aliceDeviceId, tampered))
        );
        assertTrue(ex.getMessage().contains("Invalid digital signature for device: " + aliceDeviceId));

        assertEquals(new BigDecimal("5000.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(0, transactionRepository.count());
    }

    @Test
    @DisplayName("10. Offline double-spending: Distinct offline signed packets exceeding balance serialize at ledger; first settles, second fails insufficient funds")
    void offlineDoubleSpending_firstSettles_secondFailsInsufficientFunds() throws Exception {
        // Set Alice balance to exactly ₹100.00
        Account alice = accountRepository.findById("alice").orElseThrow();
        alice.setBalance(new BigDecimal("100.00"));
        accountRepository.save(alice);

        // Alice creates two distinct offline signed instructions, each for ₹100.00 (total ₹200.00 > ₹100.00)
        String paymentId1 = "offline-double-spend-1-" + UUID.randomUUID();
        String paymentId2 = "offline-double-spend-2-" + UUID.randomUUID();
        PaymentInstruction packet1 = createSignedInstruction(paymentId1, "alice", "bob", new BigDecimal("100.00"), "nonce-ds-1");
        PaymentInstruction packet2 = createSignedInstruction(paymentId2, "alice", "bob", new BigDecimal("100.00"), "nonce-ds-2");

        // 1. First recipient submits Packet 1 for reconciliation
        ResponseEntity<MeshPaymentResult> res1 = apiController.submitSignedMeshPayment(new SignedPaymentRequest(aliceDeviceId, packet1));
        assertEquals(HttpStatus.OK, res1.getStatusCode());
        assertEquals("SETTLED", res1.getBody().status());

        // Alice balance is now ₹0.00
        assertEquals(new BigDecimal("0.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1100.00"), accountRepository.findById("bob").orElseThrow().getBalance());

        // 2. Second recipient attempts to reconcile Packet 2: must fail with Insufficient funds
        IllegalStateException ex = assertThrows(IllegalStateException.class, () ->
                apiController.submitSignedMeshPayment(new SignedPaymentRequest(aliceDeviceId, packet2))
        );
        assertTrue(ex.getMessage().contains("Insufficient funds"));

        // 3. Balance never goes negative; exactly 1 transaction recorded
        assertEquals(new BigDecimal("0.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1100.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(1, transactionRepository.count());

        // 4. Authoritative status check: Packet 1 is SETTLED, Packet 2 is NOT_FOUND
        ResponseEntity<PaymentStatusResponse> status1 = apiController.getPaymentStatus(paymentId1);
        assertEquals(HttpStatus.OK, status1.getStatusCode());
        assertEquals("SETTLED", status1.getBody().status());

        ResponseEntity<PaymentStatusResponse> status2 = apiController.getPaymentStatus(paymentId2);
        assertEquals(HttpStatus.NOT_FOUND, status2.getStatusCode());
        assertEquals("NOT_FOUND", status2.getBody().status());
    }

    @Test
    @DisplayName("11. Concurrent offline double-spending race: Two distinct ₹100 payments competing for ₹100 balance settle at most once")
    void offlineDoubleSpending_concurrentRace_onlyOneSettlesAndZeroSumPreserved() throws Exception {
        // Set Alice balance to exactly ₹100.00
        Account alice = accountRepository.findById("alice").orElseThrow();
        alice.setBalance(new BigDecimal("100.00"));
        accountRepository.save(alice);

        // Alice creates two distinct offline signed instructions, each for ₹100.00 to different recipients
        String paymentId1 = "offline-double-race-1-" + UUID.randomUUID();
        String paymentId2 = "offline-double-race-2-" + UUID.randomUUID();
        PaymentInstruction packet1 = createSignedInstruction(paymentId1, "alice", "bob", new BigDecimal("100.00"), "nonce-race-1");
        PaymentInstruction packet2 = createSignedInstruction(paymentId2, "alice", "carol", new BigDecimal("100.00"), "nonce-race-2");

        ExecutorService executor = Executors.newFixedThreadPool(2);
        CountDownLatch latch = new CountDownLatch(1);
        AtomicInteger settledCount = new AtomicInteger(0);
        AtomicInteger rejectedCount = new AtomicInteger(0);
        List<Future<?>> futures = new ArrayList<>();

        futures.add(executor.submit(() -> {
            try {
                latch.await();
                ResponseEntity<MeshPaymentResult> res = apiController.submitSignedMeshPayment(new SignedPaymentRequest(aliceDeviceId, packet1));
                if (res.getStatusCode() == HttpStatus.OK && "SETTLED".equalsIgnoreCase(res.getBody().status())) {
                    settledCount.incrementAndGet();
                }
            } catch (Exception e) {
                rejectedCount.incrementAndGet();
            }
        }));

        futures.add(executor.submit(() -> {
            try {
                latch.await();
                ResponseEntity<MeshPaymentResult> res = apiController.submitSignedMeshPayment(new SignedPaymentRequest(aliceDeviceId, packet2));
                if (res.getStatusCode() == HttpStatus.OK && "SETTLED".equalsIgnoreCase(res.getBody().status())) {
                    settledCount.incrementAndGet();
                }
            } catch (Exception e) {
                rejectedCount.incrementAndGet();
            }
        }));

        latch.countDown(); // Launch both threads simultaneously
        for (Future<?> f : futures) {
            f.get();
        }
        executor.shutdown();

        // Exactly one concurrent payment must settle, and exactly one must be rejected
        assertEquals(1, settledCount.get(), "Exactly one concurrent offline payment must settle");
        assertEquals(1, rejectedCount.get(), "The competing payment exceeding balance must fail");

        // Alice balance must be exactly ₹0.00 (NEVER negative!)
        assertEquals(new BigDecimal("0.00"), accountRepository.findById("alice").orElseThrow().getBalance());

        // Exactly one recipient received ₹100.00
        BigDecimal bobBalance = accountRepository.findById("bob").orElseThrow().getBalance();
        BigDecimal carolBalance = accountRepository.findById("carol").orElseThrow().getBalance();
        boolean bobSettled = bobBalance.compareTo(new BigDecimal("1100.00")) == 0 && carolBalance.compareTo(new BigDecimal("2000.00")) == 0;
        boolean carolSettled = bobBalance.compareTo(new BigDecimal("1000.00")) == 0 && carolBalance.compareTo(new BigDecimal("2100.00")) == 0;
        assertTrue(bobSettled || carolSettled, "Either Bob or Carol received ₹100.00, but never both");

        // System zero-sum conserved: 0 + bob + carol == 100 + 1000 + 2000 = 3100
        assertEquals(new BigDecimal("3100.00"), bobBalance.add(carolBalance));

        // Ledger contains exactly 1 settled transaction and 1 processed packet record
        assertEquals(1, transactionRepository.count());
        assertEquals(1, processedPacketRepository.count());

        // Authoritative query: Winner is SETTLED, loser is NOT_FOUND
        ResponseEntity<PaymentStatusResponse> status1 = apiController.getPaymentStatus(paymentId1);
        ResponseEntity<PaymentStatusResponse> status2 = apiController.getPaymentStatus(paymentId2);
        if (bobSettled) {
            assertEquals("SETTLED", status1.getBody().status());
            assertEquals("NOT_FOUND", status2.getBody().status());
        } else {
            assertEquals("NOT_FOUND", status1.getBody().status());
            assertEquals("SETTLED", status2.getBody().status());
        }

        // Full mathematical reconciliation passes with zero discrepancies
        Map<String, BigDecimal> openingBalances = Map.of(
                "alice", new BigDecimal("100.00"),
                "bob", new BigDecimal("1000.00"),
                "carol", new BigDecimal("2000.00")
        );
        ReconciliationReport report = reconciliationService.reconcile(openingBalances);
        assertTrue(report.isReconciled());
        assertTrue(report.isLedgerBalanced());
        assertTrue(report.isBalancesReconciled());
        assertTrue(report.discrepancies().isEmpty());
    }

    @Test
    @DisplayName("12. Concurrent distinct payments exceeding balance partially: ₹60 + ₹60 against ₹100 balance settles exactly once")
    void concurrentDistinctPayments_partialOverdraft_settlesOnlyWithinAvailableBalance() throws Exception {
        Account alice = accountRepository.findById("alice").orElseThrow();
        alice.setBalance(new BigDecimal("100.00"));
        accountRepository.save(alice);

        String paymentId1 = "offline-partial-race-1-" + UUID.randomUUID();
        String paymentId2 = "offline-partial-race-2-" + UUID.randomUUID();
        PaymentInstruction packet1 = createSignedInstruction(paymentId1, "alice", "bob", new BigDecimal("60.00"), "nonce-partial-1");
        PaymentInstruction packet2 = createSignedInstruction(paymentId2, "alice", "carol", new BigDecimal("60.00"), "nonce-partial-2");

        ExecutorService executor = Executors.newFixedThreadPool(2);
        CountDownLatch latch = new CountDownLatch(1);
        AtomicInteger settledCount = new AtomicInteger(0);
        AtomicInteger rejectedCount = new AtomicInteger(0);
        List<Future<?>> futures = new ArrayList<>();

        futures.add(executor.submit(() -> {
            try {
                latch.await();
                ResponseEntity<MeshPaymentResult> res = apiController.submitSignedMeshPayment(new SignedPaymentRequest(aliceDeviceId, packet1));
                if (res.getStatusCode() == HttpStatus.OK && "SETTLED".equalsIgnoreCase(res.getBody().status())) {
                    settledCount.incrementAndGet();
                }
            } catch (Exception e) {
                rejectedCount.incrementAndGet();
            }
        }));

        futures.add(executor.submit(() -> {
            try {
                latch.await();
                ResponseEntity<MeshPaymentResult> res = apiController.submitSignedMeshPayment(new SignedPaymentRequest(aliceDeviceId, packet2));
                if (res.getStatusCode() == HttpStatus.OK && "SETTLED".equalsIgnoreCase(res.getBody().status())) {
                    settledCount.incrementAndGet();
                }
            } catch (Exception e) {
                rejectedCount.incrementAndGet();
            }
        }));

        latch.countDown();
        for (Future<?> f : futures) {
            f.get();
        }
        executor.shutdown();

        assertEquals(1, settledCount.get());
        assertEquals(1, rejectedCount.get());

        // Alice remaining balance is exactly ₹40.00
        assertEquals(new BigDecimal("40.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(1, transactionRepository.count());

        Map<String, BigDecimal> openingBalances = Map.of(
                "alice", new BigDecimal("100.00"),
                "bob", new BigDecimal("1000.00"),
                "carol", new BigDecimal("2000.00")
        );
        ReconciliationReport report = reconciliationService.reconcile(openingBalances);
        assertTrue(report.isReconciled());
        assertTrue(report.isLedgerBalanced());
        assertTrue(report.isBalancesReconciled());
    }

    @Test
    @DisplayName("13. Concurrent opposing transfers: Alice -> Bob ₹100 and Bob -> Alice ₹100 race without deadlock")
    void concurrentOpposingTransfers_avoidsDeadlockAndMaintainsZeroSum() throws Exception {
        // Setup Bob's authorized device
        KeyPair bobDeviceKeyPair = cryptoService.generateRsaKeyPair();
        String bobDeviceId = "test-sec-bob-device";
        String bobPubKeyBase64 = Base64.getEncoder().encodeToString(bobDeviceKeyPair.getPublic().getEncoded());
        apiController.registerSenderKey(new KeyRegistrationRequest(bobDeviceId, bobPubKeyBase64), null, null);
        apiController.authorizeDevice(
                new DeviceAuthorizationRequest(bobDeviceId, "bob"),
                "test-admin-secret-token",
                null
        );

        // Seed: Alice ₹500.00, Bob ₹500.00
        Account alice = accountRepository.findById("alice").orElseThrow();
        alice.setBalance(new BigDecimal("500.00"));
        accountRepository.save(alice);
        Account bob = accountRepository.findById("bob").orElseThrow();
        bob.setBalance(new BigDecimal("500.00"));
        accountRepository.save(bob);

        PaymentInstruction aliceToBob = createSignedInstruction(
                "oppose-1-" + UUID.randomUUID(), "alice", "bob", new BigDecimal("100.00"), "nonce-opp-1", aliceDeviceKeyPair
        );
        PaymentInstruction bobToAlice = createSignedInstruction(
                "oppose-2-" + UUID.randomUUID(), "bob", "alice", new BigDecimal("100.00"), "nonce-opp-2", bobDeviceKeyPair
        );

        ExecutorService executor = Executors.newFixedThreadPool(2);
        CountDownLatch latch = new CountDownLatch(1);
        AtomicInteger settledCount = new AtomicInteger(0);
        List<Future<?>> futures = new ArrayList<>();

        futures.add(executor.submit(() -> {
            try {
                latch.await();
                // Retry on optimistic locking conflict if needed
                for (int attempt = 0; attempt < 3; attempt++) {
                    try {
                        ResponseEntity<MeshPaymentResult> res = apiController.submitSignedMeshPayment(new SignedPaymentRequest(aliceDeviceId, aliceToBob));
                        if (res.getStatusCode() == HttpStatus.OK && "SETTLED".equalsIgnoreCase(res.getBody().status())) {
                            settledCount.incrementAndGet();
                            return;
                        }
                    } catch (IllegalStateException e) {
                        if (e.getMessage().contains("Concurrent ledger update conflict")) {
                            Thread.sleep(25);
                            continue;
                        }
                        throw e;
                    }
                }
            } catch (Exception e) {
                throw new RuntimeException(e);
            }
        }));

        futures.add(executor.submit(() -> {
            try {
                latch.await();
                for (int attempt = 0; attempt < 3; attempt++) {
                    try {
                        ResponseEntity<MeshPaymentResult> res = apiController.submitSignedMeshPayment(new SignedPaymentRequest(bobDeviceId, bobToAlice));
                        if (res.getStatusCode() == HttpStatus.OK && "SETTLED".equalsIgnoreCase(res.getBody().status())) {
                            settledCount.incrementAndGet();
                            return;
                        }
                    } catch (IllegalStateException e) {
                        if (e.getMessage().contains("Concurrent ledger update conflict")) {
                            Thread.sleep(25);
                            continue;
                        }
                        throw e;
                    }
                }
            } catch (Exception e) {
                throw new RuntimeException(e);
            }
        }));

        latch.countDown();
        for (Future<?> f : futures) {
            f.get();
        }
        executor.shutdown();

        // Both opposing payments successfully settle
        assertEquals(2, settledCount.get(), "Both opposing payments must settle");
        assertEquals(new BigDecimal("500.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("500.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(2, transactionRepository.count());

        Map<String, BigDecimal> openingBalances = Map.of(
                "alice", new BigDecimal("500.00"),
                "bob", new BigDecimal("500.00"),
                "carol", new BigDecimal("2000.00")
        );
        ReconciliationReport report = reconciliationService.reconcile(openingBalances);
        assertTrue(report.isReconciled());
        assertTrue(report.isLedgerBalanced());
        assertTrue(report.isBalancesReconciled());
    }
}
