package com.demo.upimesh;

import com.demo.upimesh.model.Account;
import com.demo.upimesh.model.AccountRepository;
import com.demo.upimesh.model.AllowanceIssuanceRequest;
import com.demo.upimesh.model.DeviceAccountAuthorization;
import com.demo.upimesh.model.DeviceAuthorizationRepository;
import com.demo.upimesh.model.DeviceAuthorizationStatus;
import com.demo.upimesh.model.OfflineAllowance;
import com.demo.upimesh.model.OfflineAllowanceRefundResult;
import com.demo.upimesh.model.OfflineAllowanceRepository;
import com.demo.upimesh.model.OfflineAllowanceStatus;
import com.demo.upimesh.model.OfflineSecurityEvent;
import com.demo.upimesh.model.OfflineSecurityEventRepository;
import com.demo.upimesh.model.OfflineSpendPayment;
import com.demo.upimesh.model.OfflineSpendPaymentRepository;
import com.demo.upimesh.model.OfflineSpendRecord;
import com.demo.upimesh.model.ReconciliationReport;
import com.demo.upimesh.model.TransactionRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import java.math.BigDecimal;
import java.security.GeneralSecurityException;
import java.security.KeyPair;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.*;

@SpringBootTest
class OfflineAllowanceSettlementServiceTest {

    @Autowired
    private OfflineAllowanceService offlineAllowanceService;

    @Autowired
    private OfflineAllowanceSettlementService offlineAllowanceSettlementService;

    @Autowired
    private OfflineAllowanceRepository offlineAllowanceRepository;

    @Autowired
    private OfflineSpendPaymentRepository offlineSpendPaymentRepository;

    @Autowired
    private OfflineSecurityEventRepository offlineSecurityEventRepository;

    @Autowired
    private AccountRepository accountRepository;

    @Autowired
    private TransactionRepository transactionRepository;

    @Autowired
    private SenderKeyRegistry senderKeyRegistry;

    @Autowired
    private DeviceAuthorizationRepository deviceAuthorizationRepository;

    @Autowired
    private BankAuthorityKeyService bankAuthorityKeyService;

    @Autowired
    private CryptoService cryptoService;

    @Autowired
    private ReconciliationService reconciliationService;

    @Autowired
    private SettlementService settlementService;

    private KeyPair aliceDeviceKeyPair;
    private String aliceDeviceId;
    private String aliceDeviceFingerprint;
    private OfflineAllowance aliceAllowance;

    @BeforeEach
    void setUp() throws Exception {
        offlineSecurityEventRepository.deleteAll();
        offlineSpendPaymentRepository.deleteAll();
        offlineAllowanceRepository.deleteAll();
        transactionRepository.deleteAll();
        deviceAuthorizationRepository.deleteAll();
        accountRepository.deleteAll();

        // Seed accounts: Alice: 5000.00, Bob: 1000.00, Carol: 2000.00, system-escrow: 0.00
        accountRepository.save(new Account("alice", new BigDecimal("5000.00")));
        accountRepository.save(new Account("bob", new BigDecimal("1000.00")));
        accountRepository.save(new Account("carol", new BigDecimal("2000.00")));
        accountRepository.save(new Account(OfflineAllowanceService.ESCROW_ACCOUNT_ID, BigDecimal.ZERO));

        // Register and authorize Alice's device
        aliceDeviceKeyPair = cryptoService.generateRsaKeyPair();
        aliceDeviceId = "device-alice-settle-" + UUID.randomUUID();
        senderKeyRegistry.registerKey(aliceDeviceId, aliceDeviceKeyPair.getPublic());
        aliceDeviceFingerprint = DeviceAuthorizationRegistry.computeFingerprint(aliceDeviceKeyPair.getPublic());

        deviceAuthorizationRepository.save(new DeviceAccountAuthorization(
                UUID.randomUUID().toString(),
                aliceDeviceId,
                "alice",
                Instant.now(),
                DeviceAuthorizationStatus.AUTHORIZED.name(),
                aliceDeviceFingerprint,
                new BigDecimal("5000.00"),
                Instant.now().plus(30, ChronoUnit.DAYS),
                null
        ));

        // Issue a ₹2,000 allowance for Alice (Alice remaining balance: ₹3,000; escrow: ₹2,000)
        aliceAllowance = offlineAllowanceService.issueAllowance(new AllowanceIssuanceRequest(
                "alice",
                aliceDeviceId,
                new BigDecimal("2000.00"),
                "INR",
                24L
        ));
    }

    private OfflineSpendRecord createSignedSpendRecord(
            String allowanceId,
            String paymentId,
            String payerAccountId,
            String payerDeviceId,
            String recipientAccountId,
            BigDecimal amount,
            int sequenceNumber,
            BigDecimal cumulativeSpentAmount,
            Instant createdAt,
            String voucherSignature,
            KeyPair signingKeyPair
    ) throws GeneralSecurityException {
        byte[] canonical = OfflineSpendRecord.buildCanonicalSpendBytes(
                allowanceId,
                paymentId,
                payerAccountId,
                payerDeviceId,
                recipientAccountId,
                amount,
                "INR",
                sequenceNumber,
                cumulativeSpentAmount,
                createdAt,
                voucherSignature,
                1
        );
        String payerSignature = cryptoService.signBase64(canonical, signingKeyPair.getPrivate());
        return new OfflineSpendRecord(
                allowanceId,
                paymentId,
                payerAccountId,
                payerDeviceId,
                recipientAccountId,
                amount,
                "INR",
                sequenceNumber,
                cumulativeSpentAmount,
                createdAt,
                voucherSignature,
                payerSignature,
                1
        );
    }

    @Test
    @DisplayName("1. Valid spend within allowance settles from escrow and maintains double-entry zero-sum")
    void validSpend_withinAllowance_atomicEscrowSettlementAndReconciliation() throws Exception {
        String paymentId = "pmt-spend-1-" + UUID.randomUUID();
        OfflineSpendRecord record = createSignedSpendRecord(
                aliceAllowance.getId(),
                paymentId,
                "alice",
                aliceDeviceId,
                "bob",
                new BigDecimal("500.00"),
                1,
                new BigDecimal("500.00"),
                Instant.now(),
                aliceAllowance.getVoucherSignature(),
                aliceDeviceKeyPair
        );

        OfflineSpendPayment settled = offlineAllowanceSettlementService.settleOfflineSpend(record);

        assertNotNull(settled);
        assertEquals(paymentId, settled.getPaymentId());
        assertEquals("alice", settled.getPayerAccountId());
        assertEquals("bob", settled.getRecipientAccountId());
        assertEquals(new BigDecimal("500.00"), settled.getAmount());
        assertEquals(1, settled.getSequenceNumber());
        assertEquals(new BigDecimal("500.00"), settled.getCumulativeSpentAmount());
        assertEquals("SETTLED", settled.getStatus());

        // Escrow debited ₹500 (2000 -> 1500)
        Account escrow = accountRepository.findById(OfflineAllowanceService.ESCROW_ACCOUNT_ID).orElseThrow();
        assertEquals(new BigDecimal("1500.00"), escrow.getBalance());

        // Bob credited ₹500 (1000 -> 1500)
        Account bob = accountRepository.findById("bob").orElseThrow();
        assertEquals(new BigDecimal("1500.00"), bob.getBalance());

        // Alice main balance untouched (remains 3000.00, debited at issuance)
        Account alice = accountRepository.findById("alice").orElseThrow();
        assertEquals(new BigDecimal("3000.00"), alice.getBalance());

        // Allowance tracked spending metrics
        OfflineAllowance refreshed = offlineAllowanceRepository.findById(aliceAllowance.getId()).orElseThrow();
        assertEquals(new BigDecimal("500.00"), refreshed.getSpentAmount());
        assertEquals(new BigDecimal("1500.00"), refreshed.getRemainingAmount());
        assertEquals(1, refreshed.getLastSequenceNumber());
        assertEquals(OfflineAllowanceStatus.ACTIVE, refreshed.getStatus());

        // Double-entry reconciliation preserves global zero-sum: 0 discrepancies
        ReconciliationReport report = reconciliationService.reconcile();
        assertTrue(report.isReconciled());
        assertTrue(report.isLedgerBalanced());
        assertTrue(report.isBalancesReconciled());
        assertTrue(report.discrepancies().isEmpty());
    }

    @Test
    @DisplayName("2. Multi-spend sequence consumes allowance to exhaustion with exact monetary arithmetic")
    void multiSpend_sequential_exactMonetaryArithmeticAndExhaustion() throws Exception {
        // Spend 1: ₹500 to Bob (seq 1)
        OfflineSpendRecord spend1 = createSignedSpendRecord(
                aliceAllowance.getId(),
                "pmt-multi-1",
                "alice",
                aliceDeviceId,
                "bob",
                new BigDecimal("500.00"),
                1,
                new BigDecimal("500.00"),
                Instant.now(),
                aliceAllowance.getVoucherSignature(),
                aliceDeviceKeyPair
        );
        offlineAllowanceSettlementService.settleOfflineSpend(spend1);

        // Spend 2: ₹1,500 to Carol (seq 2, cumulative ₹2,000)
        OfflineSpendRecord spend2 = createSignedSpendRecord(
                aliceAllowance.getId(),
                "pmt-multi-2",
                "alice",
                aliceDeviceId,
                "carol",
                new BigDecimal("1500.00"),
                2,
                new BigDecimal("2000.00"),
                Instant.now(),
                aliceAllowance.getVoucherSignature(),
                aliceDeviceKeyPair
        );
        offlineAllowanceSettlementService.settleOfflineSpend(spend2);

        // Escrow fully consumed to ₹0.00
        Account escrow = accountRepository.findById(OfflineAllowanceService.ESCROW_ACCOUNT_ID).orElseThrow();
        assertEquals(new BigDecimal("0.00"), escrow.getBalance());

        // Bob: ₹1,500.00, Carol: ₹3,500.00, Alice: ₹3,000.00
        assertEquals(new BigDecimal("1500.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(new BigDecimal("3500.00"), accountRepository.findById("carol").orElseThrow().getBalance());
        assertEquals(new BigDecimal("3000.00"), accountRepository.findById("alice").orElseThrow().getBalance());

        // Allowance transitioned to EXHAUSTED
        OfflineAllowance refreshed = offlineAllowanceRepository.findById(aliceAllowance.getId()).orElseThrow();
        assertEquals(new BigDecimal("2000.00"), refreshed.getSpentAmount());
        assertEquals(new BigDecimal("0.00"), refreshed.getRemainingAmount());
        assertEquals(2, refreshed.getLastSequenceNumber());
        assertEquals(OfflineAllowanceStatus.EXHAUSTED, refreshed.getStatus());

        // Reconciliation
        ReconciliationReport report = reconciliationService.reconcile();
        assertTrue(report.isReconciled());
        assertTrue(report.isLedgerBalanced());
    }

    @Test
    @DisplayName("3. Overspending exceeding allowance limit is rejected and logged as a security event")
    void overspending_exceedingAllowanceLimit_rejected() throws Exception {
        // Spend ₹2,500 against ₹2,000 allowance
        OfflineSpendRecord overspend = createSignedSpendRecord(
                aliceAllowance.getId(),
                "pmt-overspend",
                "alice",
                aliceDeviceId,
                "bob",
                new BigDecimal("2500.00"),
                1,
                new BigDecimal("2500.00"),
                Instant.now(),
                aliceAllowance.getVoucherSignature(),
                aliceDeviceKeyPair
        );

        IllegalStateException ex = assertThrows(IllegalStateException.class, () ->
                offlineAllowanceSettlementService.settleOfflineSpend(overspend)
        );
        assertTrue(ex.getMessage().contains("exceeds remaining allowance limit"));

        // Security event logged
        List<OfflineSecurityEvent> events = offlineSecurityEventRepository.findByAllowanceIdOrderByDetectedAtDesc(aliceAllowance.getId());
        assertEquals(1, events.size());
        assertEquals("OVERSPEND_ATTEMPT", events.get(0).getEventType());

        // Escrow balance untouched
        assertEquals(new BigDecimal("2000.00"), accountRepository.findById(OfflineAllowanceService.ESCROW_ACCOUNT_ID).orElseThrow().getBalance());
        assertEquals(new BigDecimal("1000.00"), accountRepository.findById("bob").orElseThrow().getBalance());
    }

    @Test
    @DisplayName("4. Tampered voucher signature is rejected and logged as security event")
    void tamperedVoucher_bankSignatureVerificationFailure_rejected() throws Exception {
        OfflineSpendRecord tampered = createSignedSpendRecord(
                aliceAllowance.getId(),
                "pmt-tampered-voucher",
                "alice",
                aliceDeviceId,
                "bob",
                new BigDecimal("500.00"),
                1,
                new BigDecimal("500.00"),
                Instant.now(),
                "tampered-invalid-voucher-signature-base64", // Tampered bank signature
                aliceDeviceKeyPair
        );

        GeneralSecurityException ex = assertThrows(GeneralSecurityException.class, () ->
                offlineAllowanceSettlementService.settleOfflineSpend(tampered)
        );
        assertTrue(ex.getMessage().contains("Invalid bank authority voucher signature"));

        List<OfflineSecurityEvent> events = offlineSecurityEventRepository.findByAllowanceIdOrderByDetectedAtDesc(aliceAllowance.getId());
        assertEquals(1, events.size());
        assertEquals("TAMPERED_VOUCHER_SIGNATURE", events.get(0).getEventType());
    }

    @Test
    @DisplayName("5. Invalid payer device digital signature is rejected and logged as security event")
    void invalidPayerSignature_payloadTampering_rejected() throws Exception {
        // Sign with Alice's key, but provide forged signature bytes
        OfflineSpendRecord badSig = new OfflineSpendRecord(
                aliceAllowance.getId(),
                "pmt-bad-sig",
                "alice",
                aliceDeviceId,
                "bob",
                new BigDecimal("500.00"),
                "INR",
                1,
                new BigDecimal("500.00"),
                Instant.now(),
                aliceAllowance.getVoucherSignature(),
                "forged-signature-base64-content", // Invalid signature
                1
        );

        GeneralSecurityException ex = assertThrows(GeneralSecurityException.class, () ->
                offlineAllowanceSettlementService.settleOfflineSpend(badSig)
        );
        assertTrue(ex.getMessage().contains("Invalid payer device digital signature"));

        List<OfflineSecurityEvent> events = offlineSecurityEventRepository.findByAllowanceIdOrderByDetectedAtDesc(aliceAllowance.getId());
        assertEquals(1, events.size());
        assertEquals("INVALID_PAYER_SIGNATURE", events.get(0).getEventType());
    }

    @Test
    @DisplayName("6. Wrong-device payment signed by an unauthorized key is rejected")
    void wrongDevice_orWrongAccount_rejected() throws Exception {
        KeyPair malloryKeyPair = cryptoService.generateRsaKeyPair();
        String malloryDeviceId = "device-mallory-" + UUID.randomUUID();
        senderKeyRegistry.registerKey(malloryDeviceId, malloryKeyPair.getPublic());

        // Mallory attempts to sign a spend record for Alice's allowance
        OfflineSpendRecord mallorySpend = createSignedSpendRecord(
                aliceAllowance.getId(),
                "pmt-mallory-attack",
                "alice",
                malloryDeviceId, // Wrong device
                "bob",
                new BigDecimal("500.00"),
                1,
                new BigDecimal("500.00"),
                Instant.now(),
                aliceAllowance.getVoucherSignature(),
                malloryKeyPair
        );

        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () ->
                offlineAllowanceSettlementService.settleOfflineSpend(mallorySpend)
        );
        assertTrue(ex.getMessage().contains("Payer device ID mismatch"));
    }

    @Test
    @DisplayName("7. Expired allowance: spend created after allowance spending deadline is rejected")
    void expiredAllowance_spendingPastDeadline_rejected() throws Exception {
        // Evaluate at a simulated time 2 hours after allowance expiry
        Instant evaluationTime = aliceAllowance.getExpiresAt().plus(2, ChronoUnit.HOURS);
        Clock testClock = Clock.fixed(evaluationTime, ZoneOffset.UTC);
        OfflineAllowanceSettlementService serviceWithClock = new OfflineAllowanceSettlementService(
                accountRepository, offlineAllowanceRepository, offlineSpendPaymentRepository,
                offlineSecurityEventRepository, settlementService, senderKeyRegistry,
                bankAuthorityKeyService, cryptoService, null, testClock
        );

        // Spend created 1 hour after allowance expiry (after deadline, but 1 hour before evaluationTime so clock-skew passes)
        Instant postExpirySpendCreation = aliceAllowance.getExpiresAt().plus(1, ChronoUnit.HOURS);
        OfflineSpendRecord lateSpend = createSignedSpendRecord(
                aliceAllowance.getId(),
                "pmt-post-expiry",
                "alice",
                aliceDeviceId,
                "bob",
                new BigDecimal("500.00"),
                1,
                new BigDecimal("500.00"),
                postExpirySpendCreation,
                aliceAllowance.getVoucherSignature(),
                aliceDeviceKeyPair
        );

        IllegalStateException ex = assertThrows(IllegalStateException.class, () ->
                serviceWithClock.settleOfflineSpend(lateSpend)
        );
        assertTrue(ex.getMessage().contains("after allowance spending deadline"));
    }

    @Test
    @DisplayName("8. Reconciliation window: valid spend created before deadline settles within grace period, but rejected past grace period")
    void reconciliationWindow_gracePeriodEnforcement() throws Exception {
        // Payment signed before deadline (valid offline spend)
        Instant preExpiry = aliceAllowance.getExpiresAt().minus(10, ChronoUnit.MINUTES);
        OfflineSpendRecord validPreExpirySpend = createSignedSpendRecord(
                aliceAllowance.getId(),
                "pmt-grace-window-test",
                "alice",
                aliceDeviceId,
                "bob",
                new BigDecimal("500.00"),
                1,
                new BigDecimal("500.00"),
                preExpiry,
                aliceAllowance.getVoucherSignature(),
                aliceDeviceKeyPair
        );

        // Case A: Arrives at backend 2 hours after expiry (WITHIN 24-hour grace window) -> SETTLES
        Instant withinGrace = aliceAllowance.getExpiresAt().plus(2, ChronoUnit.HOURS);
        Clock clockWithinGrace = Clock.fixed(withinGrace, ZoneOffset.UTC);
        OfflineAllowanceSettlementService serviceWithinGrace = new OfflineAllowanceSettlementService(
                accountRepository, offlineAllowanceRepository, offlineSpendPaymentRepository,
                offlineSecurityEventRepository, settlementService, senderKeyRegistry,
                bankAuthorityKeyService, cryptoService, null, clockWithinGrace
        );

        OfflineSpendPayment settled = serviceWithinGrace.settleOfflineSpend(validPreExpirySpend);
        assertNotNull(settled);
        assertEquals("SETTLED", settled.getStatus());

        // Reset for Case B
        offlineSpendPaymentRepository.deleteAll();
        Account bob = accountRepository.findById("bob").orElseThrow();
        bob.setBalance(new BigDecimal("1000.00"));
        accountRepository.save(bob);
        Account escrow = accountRepository.findById(OfflineAllowanceService.ESCROW_ACCOUNT_ID).orElseThrow();
        escrow.setBalance(new BigDecimal("2000.00"));
        accountRepository.save(escrow);
        OfflineAllowance allowanceReloaded = offlineAllowanceRepository.findById(aliceAllowance.getId()).orElseThrow();
        allowanceReloaded.setSpentAmount(BigDecimal.ZERO);
        allowanceReloaded.setLastSequenceNumber(0);
        offlineAllowanceRepository.saveAndFlush(allowanceReloaded);

        // Case B: Arrives at backend 25 hours after expiry (PAST 24-hour grace window) -> REJECTED
        Instant pastGrace = aliceAllowance.getExpiresAt().plus(25, ChronoUnit.HOURS);
        Clock clockPastGrace = Clock.fixed(pastGrace, ZoneOffset.UTC);
        OfflineAllowanceSettlementService servicePastGrace = new OfflineAllowanceSettlementService(
                accountRepository, offlineAllowanceRepository, offlineSpendPaymentRepository,
                offlineSecurityEventRepository, settlementService, senderKeyRegistry,
                bankAuthorityKeyService, cryptoService, null, clockPastGrace
        );

        IllegalStateException ex = assertThrows(IllegalStateException.class, () ->
                servicePastGrace.settleOfflineSpend(validPreExpirySpend)
        );
        assertTrue(ex.getMessage().contains("Late payment submission rejected: reconciliation grace period ended"));
    }

    @Test
    @DisplayName("9. Duplicate submission of settled payment returns idempotent result without re-debiting escrow")
    void duplicatePayment_idempotentReplay() throws Exception {
        OfflineSpendRecord spend = createSignedSpendRecord(
                aliceAllowance.getId(),
                "pmt-idempotent-test",
                "alice",
                aliceDeviceId,
                "bob",
                new BigDecimal("500.00"),
                1,
                new BigDecimal("500.00"),
                Instant.now(),
                aliceAllowance.getVoucherSignature(),
                aliceDeviceKeyPair
        );

        // First settlement
        OfflineSpendPayment first = offlineAllowanceSettlementService.settleOfflineSpend(spend);
        assertNotNull(first);
        assertEquals(new BigDecimal("1500.00"), accountRepository.findById(OfflineAllowanceService.ESCROW_ACCOUNT_ID).orElseThrow().getBalance());

        // Replay submission of the exact same instruction
        OfflineSpendPayment second = offlineAllowanceSettlementService.settleOfflineSpend(spend);
        assertNotNull(second);
        assertEquals(first.getId(), second.getId());

        // Escrow not debited twice: remains exactly ₹1,500.00
        assertEquals(new BigDecimal("1500.00"), accountRepository.findById(OfflineAllowanceService.ESCROW_ACCOUNT_ID).orElseThrow().getBalance());
        assertEquals(new BigDecimal("1500.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(1, offlineSpendPaymentRepository.count());
    }

    @Test
    @DisplayName("10. Conflicting sequence numbers (forked history / offline double-spend) revokes allowance and logs fraud event")
    void conflictingSpendingHistories_sequenceFork_treatedAsSecurityEvent() throws Exception {
        // Spend 1: Alice pays Bob ₹500 at sequence 1
        OfflineSpendRecord spendToBob = createSignedSpendRecord(
                aliceAllowance.getId(),
                "pmt-fork-bob",
                "alice",
                aliceDeviceId,
                "bob",
                new BigDecimal("500.00"),
                1,
                new BigDecimal("500.00"),
                Instant.now(),
                aliceAllowance.getVoucherSignature(),
                aliceDeviceKeyPair
        );
        offlineAllowanceSettlementService.settleOfflineSpend(spendToBob);

        // Spend 2: Alice pays Carol ₹500 ALSO AT SEQUENCE 1 (Forked history / local rewind / double-spend attack!)
        OfflineSpendRecord spendToCarol = createSignedSpendRecord(
                aliceAllowance.getId(),
                "pmt-fork-carol",
                "alice",
                aliceDeviceId,
                "carol",
                new BigDecimal("500.00"),
                1, // Reused sequence 1!
                new BigDecimal("500.00"),
                Instant.now(),
                aliceAllowance.getVoucherSignature(),
                aliceDeviceKeyPair
        );

        // Carol's submission MUST fail and revoke the allowance
        IllegalStateException ex = assertThrows(IllegalStateException.class, () ->
                offlineAllowanceSettlementService.settleOfflineSpend(spendToCarol)
        );
        assertTrue(ex.getMessage().contains("Conflicting offline spending history detected at sequence 1! Allowance revoked."));

        // Allowance is REVOKED
        OfflineAllowance refreshed = offlineAllowanceRepository.findById(aliceAllowance.getId()).orElseThrow();
        assertEquals(OfflineAllowanceStatus.REVOKED, refreshed.getStatus());

        // Security event recorded
        List<OfflineSecurityEvent> events = offlineSecurityEventRepository.findByAllowanceIdOrderByDetectedAtDesc(aliceAllowance.getId());
        assertEquals(1, events.size());
        assertEquals("SEQUENCE_FORK_CONFLICT", events.get(0).getEventType());
        assertEquals("pmt-fork-carol", events.get(0).getConflictingPaymentId());
        assertEquals("pmt-fork-bob", events.get(0).getExistingPaymentId());

        // Carol is NOT paid from escrow
        assertEquals(new BigDecimal("2000.00"), accountRepository.findById("carol").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1500.00"), accountRepository.findById(OfflineAllowanceService.ESCROW_ACCOUNT_ID).orElseThrow().getBalance());
    }

    @Test
    @DisplayName("11. Concurrent redemption race: database constraints prevent duplicate settlement")
    void concurrentRedemption_databaseUniqueConstraintEnforcement() throws Exception {
        int threads = 2;
        ExecutorService executor = Executors.newFixedThreadPool(threads);
        CountDownLatch latch = new CountDownLatch(1);
        AtomicInteger successCount = new AtomicInteger(0);
        AtomicInteger failCount = new AtomicInteger(0);
        List<Future<?>> futures = new ArrayList<>();

        OfflineSpendRecord spend = createSignedSpendRecord(
                aliceAllowance.getId(),
                "pmt-concurrent-race-" + UUID.randomUUID(),
                "alice",
                aliceDeviceId,
                "bob",
                new BigDecimal("500.00"),
                1,
                new BigDecimal("500.00"),
                Instant.now(),
                aliceAllowance.getVoucherSignature(),
                aliceDeviceKeyPair
        );

        for (int i = 0; i < threads; i++) {
            futures.add(executor.submit(() -> {
                try {
                    latch.await();
                    offlineAllowanceSettlementService.settleOfflineSpend(spend);
                    successCount.incrementAndGet();
                } catch (Exception e) {
                    failCount.incrementAndGet();
                }
            }));
        }

        latch.countDown();
        for (Future<?> f : futures) {
            f.get();
        }
        executor.shutdown();

        // Exactly 1 winner (or 1 win + 1 idempotent return, or 1 fail)
        // In our service, tryClaim / database unique constraint guarantees exactly one settlement
        assertEquals(new BigDecimal("1500.00"), accountRepository.findById(OfflineAllowanceService.ESCROW_ACCOUNT_ID).orElseThrow().getBalance());
        assertEquals(new BigDecimal("1500.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(1, offlineSpendPaymentRepository.count());
    }

    @Test
    @DisplayName("12. Unused allowance escrow refund: blocked during active grace window, succeeds after grace window expires")
    void unusedAllowanceRefund_gracePeriodEnforcementAndZeroSumConservation() throws Exception {
        // Spend ₹500 to Bob; remaining unspent escrow is ₹1,500.00
        OfflineSpendRecord spend = createSignedSpendRecord(
                aliceAllowance.getId(),
                "pmt-refund-test",
                "alice",
                aliceDeviceId,
                "bob",
                new BigDecimal("500.00"),
                1,
                new BigDecimal("500.00"),
                Instant.now(),
                aliceAllowance.getVoucherSignature(),
                aliceDeviceKeyPair
        );
        offlineAllowanceSettlementService.settleOfflineSpend(spend);
        assertEquals(new BigDecimal("1500.00"), accountRepository.findById(OfflineAllowanceService.ESCROW_ACCOUNT_ID).orElseThrow().getBalance());

        // Step 1: Attempt refund WHILE WITHIN GRACE WINDOW -> BLOCKED
        IllegalStateException prematureEx = assertThrows(IllegalStateException.class, () ->
                offlineAllowanceSettlementService.refundUnusedAllowance(aliceAllowance.getId())
        );
        assertTrue(prematureEx.getMessage().contains("Cannot release escrow funds during active reconciliation grace window"));

        // Step 2: Simulate passage of time past reconciliation grace window
        Instant pastGrace = aliceAllowance.getExpiresAt().plus(OfflineAllowanceSettlementService.RECONCILIATION_GRACE_PERIOD).plus(1, ChronoUnit.HOURS);
        Clock clockPastGrace = Clock.fixed(pastGrace, ZoneOffset.UTC);
        OfflineAllowanceSettlementService servicePastGrace = new OfflineAllowanceSettlementService(
                accountRepository, offlineAllowanceRepository, offlineSpendPaymentRepository,
                offlineSecurityEventRepository, settlementService, senderKeyRegistry,
                bankAuthorityKeyService, cryptoService, null, clockPastGrace
        );

        OfflineAllowanceRefundResult result = servicePastGrace.refundUnusedAllowance(aliceAllowance.getId());

        assertTrue(result.success());
        assertEquals(new BigDecimal("1500.00"), result.refundedAmount());
        assertEquals(OfflineAllowanceStatus.REDEEMED, result.newStatus());

        // Escrow debited ₹1,500 back to ₹0.00
        assertEquals(new BigDecimal("0.00"), accountRepository.findById(OfflineAllowanceService.ESCROW_ACCOUNT_ID).orElseThrow().getBalance());

        // Alice credited ₹1,500 (3000 + 1500 = 4500.00)
        assertEquals(new BigDecimal("4500.00"), accountRepository.findById("alice").orElseThrow().getBalance());

        // Bob retains settled ₹1,500 (1000 + 500)
        assertEquals(new BigDecimal("1500.00"), accountRepository.findById("bob").orElseThrow().getBalance());

        // Full double-entry reconciliation passes: system funds strictly conserved (4500 + 1500 + 2000 = 8000.00)
        ReconciliationReport report = reconciliationService.reconcile();
        assertTrue(report.isReconciled());
        assertTrue(report.isLedgerBalanced());
        assertTrue(report.isBalancesReconciled());
    }

    @Test
    @DisplayName("Shared Test Vector: Canonical voucher and spend serialization match expected test vector bytes")
    void sharedTestVector_canonicalVoucherAndSpend_byteParity() {
        // 1. Voucher Canonical Vector
        byte[] voucherBytes = OfflineAllowance.buildCanonicalVoucherBytes(
                "alw-test-voucher-001",
                "alice",
                "iphone-test-device",
                "sha256:abc123def456",
                "INR",
                new BigDecimal("500.00"),
                Instant.parse("2026-10-15T10:00:00Z"),
                Instant.parse("2026-10-16T10:00:00Z"),
                1
        );
        String expectedVoucherCanonicalString =
                "UPI-MESH-ALLOWANCE-V1\n" +
                "allowanceId:20:alw-test-voucher-001\n" +
                "accountId:5:alice\n" +
                "deviceId:18:iphone-test-device\n" +
                "deviceFingerprint:19:sha256:abc123def456\n" +
                "currency:3:INR\n" +
                "allocatedAmount:6:500.00\n" +
                "issuedAt:20:2026-10-15T10:00:00Z\n" +
                "expiresAt:20:2026-10-16T10:00:00Z\n" +
                "version:1:1\n";
        assertEquals(expectedVoucherCanonicalString, new String(voucherBytes, java.nio.charset.StandardCharsets.UTF_8));
        assertEquals(expectedVoucherCanonicalString.getBytes(java.nio.charset.StandardCharsets.UTF_8).length, voucherBytes.length);

        // 2. Spend Canonical Vector
        byte[] spendBytes = OfflineSpendRecord.buildCanonicalSpendBytes(
                "alw-test-voucher-001",
                "pay-test-spend-999",
                "alice",
                "iphone-test-device",
                "bob",
                new BigDecimal("75.50"),
                "INR",
                1,
                new BigDecimal("75.50"),
                Instant.parse("2026-10-15T11:30:00Z"),
                "VOUCHER_SIG_BASE64_PLACEHOLDER",
                1
        );
        String expectedSpendCanonicalString =
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
                "version:1:1\n";
        assertEquals(expectedSpendCanonicalString, new String(spendBytes, java.nio.charset.StandardCharsets.UTF_8));
        assertEquals(expectedSpendCanonicalString.getBytes(java.nio.charset.StandardCharsets.UTF_8).length, spendBytes.length);
    }

    @Test
    @DisplayName("14. Spend created before allowance issuance time is rejected with IllegalArgumentException")
    void spendCreatedBeforeAllowanceIssuance_rejected() throws Exception {
        // Spend created 1 hour before allowance issuance
        Instant preIssuanceTime = aliceAllowance.getIssuedAt().minus(1, ChronoUnit.HOURS);
        OfflineSpendRecord preIssuanceSpend = createSignedSpendRecord(
                aliceAllowance.getId(),
                "pmt-pre-issuance",
                "alice",
                aliceDeviceId,
                "bob",
                new BigDecimal("100.00"),
                1,
                new BigDecimal("100.00"),
                preIssuanceTime,
                aliceAllowance.getVoucherSignature(),
                aliceDeviceKeyPair
        );

        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () ->
                offlineAllowanceSettlementService.settleOfflineSpend(preIssuanceSpend)
        );
        assertTrue(ex.getMessage().contains("precedes allowance issuance time"));
    }

    @Test
    @DisplayName("15. Non-monotonic sequence timestamps (sequence 2 backdated before sequence 1) is rejected")
    void nonMonotonicSequenceTimestamps_rejected() throws Exception {
        // Construct settlement service with clock fixed 30 minutes after allowance issuance
        Instant simulatedNow = aliceAllowance.getIssuedAt().plus(30, ChronoUnit.MINUTES);
        Clock testClock = Clock.fixed(simulatedNow, ZoneOffset.UTC);
        OfflineAllowanceSettlementService testService = new OfflineAllowanceSettlementService(
                accountRepository, offlineAllowanceRepository, offlineSpendPaymentRepository,
                offlineSecurityEventRepository, settlementService, senderKeyRegistry,
                bankAuthorityKeyService, cryptoService, null, testClock
        );

        // Spend 1: Created 10 minutes ago relative to simulatedNow (20 minutes after issuance)
        Instant seq1Time = simulatedNow.minus(10, ChronoUnit.MINUTES);
        OfflineSpendRecord spendSeq1 = createSignedSpendRecord(
                aliceAllowance.getId(),
                "pmt-seq1-ok",
                "alice",
                aliceDeviceId,
                "bob",
                new BigDecimal("200.00"),
                1,
                new BigDecimal("200.00"),
                seq1Time,
                aliceAllowance.getVoucherSignature(),
                aliceDeviceKeyPair
        );
        OfflineSpendPayment settledSeq1 = testService.settleOfflineSpend(spendSeq1);
        assertNotNull(settledSeq1);

        // Spend 2: Backdated to 20 minutes ago relative to simulatedNow (10 minutes BEFORE spend 1!)
        Instant seq2BackdatedTime = simulatedNow.minus(20, ChronoUnit.MINUTES);
        OfflineSpendRecord spendSeq2 = createSignedSpendRecord(
                aliceAllowance.getId(),
                "pmt-seq2-backdated",
                "alice",
                aliceDeviceId,
                "bob",
                new BigDecimal("200.00"),
                2,
                new BigDecimal("400.00"),
                seq2BackdatedTime,
                aliceAllowance.getVoucherSignature(),
                aliceDeviceKeyPair
        );

        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () ->
                testService.settleOfflineSpend(spendSeq2)
        );
        assertTrue(ex.getMessage().contains("cannot precede previous sequence"));
    }
}

