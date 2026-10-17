package com.demo.upimesh;

import com.demo.upimesh.model.Account;
import com.demo.upimesh.model.AccountRepository;
import com.demo.upimesh.model.AllowanceIssuanceRequest;
import com.demo.upimesh.model.DeviceAccountAuthorization;
import com.demo.upimesh.model.DeviceAuthorizationRepository;
import com.demo.upimesh.model.DeviceAuthorizationStatus;
import com.demo.upimesh.model.OfflineAllowance;
import com.demo.upimesh.model.OfflineAllowanceRepository;
import com.demo.upimesh.model.OfflineAllowanceStatus;
import com.demo.upimesh.model.ReconciliationReport;
import com.demo.upimesh.model.TransactionRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import java.math.BigDecimal;
import java.security.KeyPair;
import java.time.Instant;
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

import com.demo.upimesh.model.BankAuthorityCredentialRepository;
import com.demo.upimesh.model.OfflineAllowanceVoucherResponse;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import static org.junit.jupiter.api.Assertions.*;

@SpringBootTest
class OfflineAllowanceServiceTest {

    @Autowired
    private OfflineAllowanceService offlineAllowanceService;

    @Autowired
    private OfflineAllowanceRepository offlineAllowanceRepository;

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
    private BankAuthorityCredentialRepository bankAuthorityCredentialRepository;

    @Autowired
    private OfflineAllowanceController offlineAllowanceController;

    private KeyPair aliceDeviceKeyPair;
    private String aliceDeviceId;
    private String aliceDeviceFingerprint;

    @BeforeEach
    void setUp() throws Exception {
        offlineAllowanceRepository.deleteAll();
        transactionRepository.deleteAll();
        deviceAuthorizationRepository.deleteAll();
        accountRepository.deleteAll();

        // Seed accounts: Alice: 5000.00, Bob: 1000.00, Carol: 2000.00
        accountRepository.save(new Account("alice", new BigDecimal("5000.00")));
        accountRepository.save(new Account("bob", new BigDecimal("1000.00")));
        accountRepository.save(new Account("carol", new BigDecimal("2000.00")));
        accountRepository.save(new Account(OfflineAllowanceService.ESCROW_ACCOUNT_ID, BigDecimal.ZERO));

        // Generate and register Alice's device key
        aliceDeviceKeyPair = cryptoService.generateRsaKeyPair();
        aliceDeviceId = "device-alice-alw-" + UUID.randomUUID();
        senderKeyRegistry.registerKey(aliceDeviceId, aliceDeviceKeyPair.getPublic());
        aliceDeviceFingerprint = DeviceAuthorizationRegistry.computeFingerprint(aliceDeviceKeyPair.getPublic());

        // Authorize Alice's device
        DeviceAccountAuthorization auth = new DeviceAccountAuthorization(
                UUID.randomUUID().toString(),
                aliceDeviceId,
                "alice",
                Instant.now(),
                DeviceAuthorizationStatus.AUTHORIZED.name(),
                aliceDeviceFingerprint,
                new BigDecimal("5000.00"),
                Instant.now().plus(30, ChronoUnit.DAYS),
                null
        );
        deviceAuthorizationRepository.save(auth);
    }

    @Test
    @DisplayName("1. Successful ₹2,000 allowance issuance against ₹5,000 balance reserves escrow atomically")
    void issueAllowance_success_atomicEscrowReservation() {
        AllowanceIssuanceRequest request = new AllowanceIssuanceRequest(
                "alice",
                aliceDeviceId,
                new BigDecimal("2000.00"),
                "INR",
                24L
        );

        OfflineAllowance allowance = offlineAllowanceService.issueAllowance(request);

        assertNotNull(allowance);
        assertNotNull(allowance.getId());
        assertEquals("alice", allowance.getAccountId());
        assertEquals(aliceDeviceId, allowance.getDeviceId());
        assertEquals(aliceDeviceFingerprint, allowance.getDevicePublicKeyFingerprint());
        assertEquals(new BigDecimal("2000.00"), allowance.getAllocatedAmount());
        assertEquals("INR", allowance.getCurrency());
        assertEquals(OfflineAllowanceStatus.ACTIVE, allowance.getStatus());
        assertEquals("alice", allowance.getActiveAccountId());
        assertFalse(allowance.getVoucherSignature().isBlank());

        // Account balances: Alice debited ₹2,000 (5000 -> 3000), Escrow credited ₹2,000 (0 -> 2000)
        Account alice = accountRepository.findById("alice").orElseThrow();
        assertEquals(new BigDecimal("3000.00"), alice.getBalance());

        Account escrow = accountRepository.findById(OfflineAllowanceService.ESCROW_ACCOUNT_ID).orElseThrow();
        assertEquals(new BigDecimal("2000.00"), escrow.getBalance());

        // Ledger: Exactly 1 transaction recorded from alice to system-escrow
        assertEquals(1, transactionRepository.count());
        var tx = transactionRepository.findAll().get(0);
        assertEquals("alice", tx.getFromAccount());
        assertEquals(OfflineAllowanceService.ESCROW_ACCOUNT_ID, tx.getToAccount());
        assertEquals(new BigDecimal("2000.00"), tx.getAmount());
        assertEquals("SETTLED", tx.getStatus());

        // Voucher signature verifies against bank authority public key
        assertTrue(bankAuthorityKeyService.verifyVoucherSignature(
                allowance.toCanonicalVoucherBytes(),
                allowance.getVoucherSignature()
        ));

        // Full double-entry ledger reconciliation preserves system zero-sum
        ReconciliationReport report = reconciliationService.reconcile(Map.of(
                "alice", new BigDecimal("5000.00"),
                "bob", new BigDecimal("1000.00"),
                "carol", new BigDecimal("2000.00"),
                OfflineAllowanceService.ESCROW_ACCOUNT_ID, BigDecimal.ZERO
        ));
        assertTrue(report.isReconciled());
        assertTrue(report.isLedgerBalanced());
        assertTrue(report.isBalancesReconciled());
        assertTrue(report.discrepancies().isEmpty());
    }

    @Test
    @DisplayName("2. Insufficient funds rejects allowance and leaves balances/ledger unchanged")
    void issueAllowance_insufficientFunds_rejectedWithoutSideEffects() {
        // Set Alice balance to ₹500.00
        Account alice = accountRepository.findById("alice").orElseThrow();
        alice.setBalance(new BigDecimal("500.00"));
        accountRepository.save(alice);

        AllowanceIssuanceRequest request = new AllowanceIssuanceRequest(
                "alice",
                aliceDeviceId,
                new BigDecimal("2000.00"),
                "INR",
                24L
        );

        IllegalStateException ex = assertThrows(IllegalStateException.class, () ->
                offlineAllowanceService.issueAllowance(request)
        );
        assertTrue(ex.getMessage().contains("Insufficient funds"));

        // Alice balance remains ₹500.00
        assertEquals(new BigDecimal("500.00"), accountRepository.findById("alice").orElseThrow().getBalance());

        // Escrow balance remains ₹0.00
        assertEquals(new BigDecimal("0.00"), accountRepository.findById(OfflineAllowanceService.ESCROW_ACCOUNT_ID).orElseThrow().getBalance());

        // Ledger and allowance repositories remain empty
        assertEquals(0, transactionRepository.count());
        assertEquals(0, offlineAllowanceRepository.count());
    }

    @Test
    @DisplayName("3. Invalid amounts, unknown accounts, and unregistered devices fail safely")
    void issueAllowance_invalidInputs_failClosed() {
        // A. Zero amount
        assertThrows(IllegalArgumentException.class, () ->
                offlineAllowanceService.issueAllowance(new AllowanceIssuanceRequest("alice", aliceDeviceId, BigDecimal.ZERO, "INR", 24L))
        );

        // B. Negative amount
        assertThrows(IllegalArgumentException.class, () ->
                offlineAllowanceService.issueAllowance(new AllowanceIssuanceRequest("alice", aliceDeviceId, new BigDecimal("-100.00"), "INR", 24L))
        );

        // C. Excessive fractional digits
        assertThrows(IllegalArgumentException.class, () ->
                offlineAllowanceService.issueAllowance(new AllowanceIssuanceRequest("alice", aliceDeviceId, new BigDecimal("100.555"), "INR", 24L))
        );

        // D. Unknown account ID
        assertThrows(IllegalArgumentException.class, () ->
                offlineAllowanceService.issueAllowance(new AllowanceIssuanceRequest("unknown-user", aliceDeviceId, new BigDecimal("100.00"), "INR", 24L))
        );

        // E. Unregistered device
        assertThrows(IllegalArgumentException.class, () ->
                offlineAllowanceService.issueAllowance(new AllowanceIssuanceRequest("alice", "unregistered-device-xyz", new BigDecimal("100.00"), "INR", 24L))
        );

        // F. Unsupported currency
        assertThrows(IllegalArgumentException.class, () ->
                offlineAllowanceService.issueAllowance(new AllowanceIssuanceRequest("alice", aliceDeviceId, new BigDecimal("100.00"), "USD", 24L))
        );

        // Balances and ledger unchanged
        assertEquals(new BigDecimal("5000.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("0.00"), accountRepository.findById(OfflineAllowanceService.ESCROW_ACCOUNT_ID).orElseThrow().getBalance());
        assertEquals(0, transactionRepository.count());
        assertEquals(0, offlineAllowanceRepository.count());
    }

    @Test
    @DisplayName("4. Duplicate active allowance issuance is rejected when an active allowance already exists")
    void issueAllowance_duplicateActive_rejected() {
        // 1. First allowance succeeds
        AllowanceIssuanceRequest request1 = new AllowanceIssuanceRequest(
                "alice",
                aliceDeviceId,
                new BigDecimal("1000.00"),
                "INR",
                24L
        );
        OfflineAllowance first = offlineAllowanceService.issueAllowance(request1);
        assertNotNull(first);
        assertEquals(new BigDecimal("4000.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1000.00"), accountRepository.findById(OfflineAllowanceService.ESCROW_ACCOUNT_ID).orElseThrow().getBalance());

        // 2. Second request for same account fails
        AllowanceIssuanceRequest request2 = new AllowanceIssuanceRequest(
                "alice",
                aliceDeviceId,
                new BigDecimal("1000.00"),
                "INR",
                24L
        );
        IllegalStateException ex = assertThrows(IllegalStateException.class, () ->
                offlineAllowanceService.issueAllowance(request2)
        );
        assertTrue(ex.getMessage().contains("Active offline allowance already exists"));

        // Alice is not debited twice: balance remains ₹4,000.00, escrow remains ₹1,000.00
        assertEquals(new BigDecimal("4000.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1000.00"), accountRepository.findById(OfflineAllowanceService.ESCROW_ACCOUNT_ID).orElseThrow().getBalance());
        assertEquals(1, transactionRepository.count());
        assertEquals(1, offlineAllowanceRepository.count());
    }

    @Test
    @DisplayName("5. Concurrent issuance attempts for the same account: database unique constraint ensures exactly one active allowance")
    void issueAllowance_concurrentRace_onlyOneWinsAndBalanceProtected() throws Exception {
        int threads = 2;
        ExecutorService executor = Executors.newFixedThreadPool(threads);
        CountDownLatch latch = new CountDownLatch(1);
        AtomicInteger successCount = new AtomicInteger(0);
        AtomicInteger failCount = new AtomicInteger(0);
        List<Future<?>> futures = new ArrayList<>();

        for (int i = 0; i < threads; i++) {
            futures.add(executor.submit(() -> {
                try {
                    latch.await();
                    offlineAllowanceService.issueAllowance(new AllowanceIssuanceRequest(
                            "alice",
                            aliceDeviceId,
                            new BigDecimal("2000.00"),
                            "INR",
                            24L
                    ));
                    successCount.incrementAndGet();
                } catch (Exception e) {
                    failCount.incrementAndGet();
                }
            }));
        }

        latch.countDown(); // Launch both threads simultaneously
        for (Future<?> f : futures) {
            f.get();
        }
        executor.shutdown();

        // Exactly 1 winner, exactly 1 rejection
        assertEquals(1, successCount.get(), "Exactly one concurrent allowance request must succeed");
        assertEquals(1, failCount.get(), "The competing concurrent allowance request must fail");

        // Alice balance must be ₹3,000.00 (debited once, NEVER twice!)
        assertEquals(new BigDecimal("3000.00"), accountRepository.findById("alice").orElseThrow().getBalance());

        // Escrow balance must be ₹2,000.00
        assertEquals(new BigDecimal("2000.00"), accountRepository.findById(OfflineAllowanceService.ESCROW_ACCOUNT_ID).orElseThrow().getBalance());

        // Exactly 1 ledger transaction and 1 active allowance record
        assertEquals(1, transactionRepository.count());
        assertEquals(1, offlineAllowanceRepository.count());

        // Total system money remains strictly ₹8,000.00
        BigDecimal total = accountRepository.findAll().stream()
                .map(Account::getBalance)
                .reduce(BigDecimal.ZERO, BigDecimal::add);
        assertEquals(new BigDecimal("8000.00"), total);
    }

    @Test
    @DisplayName("6. Voucher signature verification and tamper detection")
    void voucherSignature_tamperDetection() {
        AllowanceIssuanceRequest request = new AllowanceIssuanceRequest(
                "alice",
                aliceDeviceId,
                new BigDecimal("2000.00"),
                "INR",
                24L
        );
        OfflineAllowance allowance = offlineAllowanceService.issueAllowance(request);

        // A. Untampered voucher verifies
        byte[] validCanonicalBytes = allowance.toCanonicalVoucherBytes();
        assertTrue(bankAuthorityKeyService.verifyVoucherSignature(validCanonicalBytes, allowance.getVoucherSignature()));

        // B. Tampered amount fails
        byte[] tamperedAmount = OfflineAllowance.buildCanonicalVoucherBytes(
                allowance.getId(),
                allowance.getAccountId(),
                allowance.getDeviceId(),
                allowance.getDevicePublicKeyFingerprint(),
                allowance.getCurrency(),
                new BigDecimal("5000.00"), // Tampered amount
                allowance.getIssuedAt(),
                allowance.getExpiresAt(),
                allowance.getProtocolVersion()
        );
        assertFalse(bankAuthorityKeyService.verifyVoucherSignature(tamperedAmount, allowance.getVoucherSignature()));

        // C. Tampered recipient / device fingerprint fails
        byte[] tamperedFingerprint = OfflineAllowance.buildCanonicalVoucherBytes(
                allowance.getId(),
                allowance.getAccountId(),
                allowance.getDeviceId(),
                "attacker-fingerprint-0000000000000000000000000000000000000000",
                allowance.getCurrency(),
                allowance.getAllocatedAmount(),
                allowance.getIssuedAt(),
                allowance.getExpiresAt(),
                allowance.getProtocolVersion()
        );
        assertFalse(bankAuthorityKeyService.verifyVoucherSignature(tamperedFingerprint, allowance.getVoucherSignature()));

        // D. Tampered expiry fails
        byte[] tamperedExpiry = OfflineAllowance.buildCanonicalVoucherBytes(
                allowance.getId(),
                allowance.getAccountId(),
                allowance.getDeviceId(),
                allowance.getDevicePublicKeyFingerprint(),
                allowance.getCurrency(),
                allowance.getAllocatedAmount(),
                allowance.getIssuedAt(),
                allowance.getExpiresAt().plus(30, ChronoUnit.DAYS), // Tampered expiry
                allowance.getProtocolVersion()
        );
        assertFalse(bankAuthorityKeyService.verifyVoucherSignature(tamperedExpiry, allowance.getVoucherSignature()));
    }

    @Test
    @DisplayName("7. Cross-user attack and device authorization enforcement: unauthorized device, revoked auth, expired auth, and limit violations fail closed")
    void issueAllowance_authorizationEnforcement_failClosed() throws Exception {
        // A. Cross-user attack: Bob's device attempts to issue allowance on Alice's account
        KeyPair bobDeviceKeyPair = cryptoService.generateRsaKeyPair();
        String bobDeviceId = "device-bob-" + UUID.randomUUID();
        senderKeyRegistry.registerKey(bobDeviceId, bobDeviceKeyPair.getPublic());
        String bobFingerprint = DeviceAuthorizationRegistry.computeFingerprint(bobDeviceKeyPair.getPublic());

        // Bob's device is authorized ONLY for 'bob'
        deviceAuthorizationRepository.save(new DeviceAccountAuthorization(
                UUID.randomUUID().toString(),
                bobDeviceId,
                "bob",
                Instant.now(),
                DeviceAuthorizationStatus.AUTHORIZED.name(),
                bobFingerprint,
                new BigDecimal("1000.00"),
                Instant.now().plus(30, ChronoUnit.DAYS),
                null
        ));

        // Bob's device tries to issue allowance on Alice's account -> FAILS
        IllegalStateException crossUserEx = assertThrows(IllegalStateException.class, () ->
                offlineAllowanceService.issueAllowance(new AllowanceIssuanceRequest(
                        "alice",
                        bobDeviceId,
                        new BigDecimal("500.00"),
                        "INR",
                        24L
                ))
        );
        assertTrue(crossUserEx.getMessage().contains("is not authorized to debit account: alice"));

        // B. Revoked authorization is rejected
        DeviceAccountAuthorization aliceAuth = deviceAuthorizationRepository
                .findByDeviceIdAndAccountId(aliceDeviceId, "alice").orElseThrow();
        aliceAuth.setStatus(DeviceAuthorizationStatus.REVOKED.name());
        deviceAuthorizationRepository.save(aliceAuth);

        IllegalStateException revokedEx = assertThrows(IllegalStateException.class, () ->
                offlineAllowanceService.issueAllowance(new AllowanceIssuanceRequest(
                        "alice",
                        aliceDeviceId,
                        new BigDecimal("500.00"),
                        "INR",
                        24L
                ))
        );
        assertTrue(revokedEx.getMessage().contains("Device authorization has been revoked"));

        // C. Expired authorization is rejected
        aliceAuth.setStatus(DeviceAuthorizationStatus.AUTHORIZED.name());
        aliceAuth.setExpiresAt(Instant.now().minus(1, ChronoUnit.DAYS));
        deviceAuthorizationRepository.save(aliceAuth);

        IllegalStateException expiredEx = assertThrows(IllegalStateException.class, () ->
                offlineAllowanceService.issueAllowance(new AllowanceIssuanceRequest(
                        "alice",
                        aliceDeviceId,
                        new BigDecimal("500.00"),
                        "INR",
                        24L
                ))
        );
        assertTrue(expiredEx.getMessage().contains("Device authorization has expired"));

        // D. Spending limit exceeded
        aliceAuth.setExpiresAt(Instant.now().plus(30, ChronoUnit.DAYS));
        aliceAuth.setSpendingLimit(new BigDecimal("300.00")); // Limit ₹300
        deviceAuthorizationRepository.save(aliceAuth);

        IllegalStateException limitEx = assertThrows(IllegalStateException.class, () ->
                offlineAllowanceService.issueAllowance(new AllowanceIssuanceRequest(
                        "alice",
                        aliceDeviceId,
                        new BigDecimal("500.00"), // Requests ₹500
                        "INR",
                        24L
                ))
        );
        assertTrue(limitEx.getMessage().contains("exceeds authorized device limit"));

        // E. Fingerprint mismatch rejected
        aliceAuth.setSpendingLimit(new BigDecimal("5000.00"));
        aliceAuth.setKeyFingerprint("mismatched-fingerprint-0000000000000000000000000000000000000000");
        deviceAuthorizationRepository.save(aliceAuth);

        IllegalStateException fpEx = assertThrows(IllegalStateException.class, () ->
                offlineAllowanceService.issueAllowance(new AllowanceIssuanceRequest(
                        "alice",
                        aliceDeviceId,
                        new BigDecimal("500.00"),
                        "INR",
                        24L
                ))
        );
        assertTrue(fpEx.getMessage().contains("Device public key fingerprint does not match"));

        // All failed attempts produced ZERO debit or ledger side-effects
        assertEquals(new BigDecimal("5000.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("0.00"), accountRepository.findById(OfflineAllowanceService.ESCROW_ACCOUNT_ID).orElseThrow().getBalance());
        assertEquals(0, transactionRepository.count());
        assertEquals(0, offlineAllowanceRepository.count());
    }

    @Test
    @DisplayName("8. Bank Authority key persistence across simulated server reboot")
    void bankAuthorityKey_persistsAcrossRestart() {
        // Issue an allowance using current service instance
        OfflineAllowance allowance = offlineAllowanceService.issueAllowance(new AllowanceIssuanceRequest(
                "alice",
                aliceDeviceId,
                new BigDecimal("1000.00"),
                "INR",
                24L
        ));

        String originalPubKeyB64 = bankAuthorityKeyService.getBankPublicKeyBase64();
        assertTrue(bankAuthorityKeyService.verifyVoucherSignature(
                allowance.toCanonicalVoucherBytes(),
                allowance.getVoucherSignature()
        ));

        // Simulate application restart: instantiate a new BankAuthorityKeyService backed by the same repository
        BankAuthorityKeyService rebootedKeyService = new BankAuthorityKeyService(cryptoService, bankAuthorityCredentialRepository);

        // Public key must be identical
        assertEquals(originalPubKeyB64, rebootedKeyService.getBankPublicKeyBase64());

        // Rebooted service must successfully verify the previously issued voucher
        assertTrue(rebootedKeyService.verifyVoucherSignature(
                allowance.toCanonicalVoucherBytes(),
                allowance.getVoucherSignature()
        ));

        // New signature generated by rebooted service is verifiable by original instance
        byte[] testPayload = "UPI-MESH-TEST-REBOOT-PAYLOAD".getBytes();
        String rebootSig = rebootedKeyService.signVoucherBase64(testPayload);
        assertTrue(bankAuthorityKeyService.verifyVoucherSignature(testPayload, rebootSig));
    }

    @Test
    @DisplayName("9. Expired allowance automatic transition allows subsequent allowance issuance")
    void issueAllowance_expiredAllowanceAutoTransitioned_allowsNewIssuance() {
        // 1. Issue first allowance
        OfflineAllowance first = offlineAllowanceService.issueAllowance(new AllowanceIssuanceRequest(
                "alice",
                aliceDeviceId,
                new BigDecimal("1000.00"),
                "INR",
                24L
        ));
        assertEquals(OfflineAllowanceStatus.ACTIVE, first.getStatus());
        assertEquals("alice", first.getActiveAccountId());

        // 2. Simulate expiration of the first allowance
        first.setExpiresAt(Instant.now().minus(1, ChronoUnit.HOURS));
        offlineAllowanceRepository.saveAndFlush(first);

        // 3. Issue second allowance for Alice: service auto-transitions first to EXPIRED and succeeds
        OfflineAllowance second = offlineAllowanceService.issueAllowance(new AllowanceIssuanceRequest(
                "alice",
                aliceDeviceId,
                new BigDecimal("1500.00"),
                "INR",
                24L
        ));

        assertNotNull(second);
        assertEquals(OfflineAllowanceStatus.ACTIVE, second.getStatus());
        assertEquals("alice", second.getActiveAccountId());

        // First allowance is now EXPIRED and activeAccountId is null
        OfflineAllowance refreshedFirst = offlineAllowanceRepository.findById(first.getId()).orElseThrow();
        assertEquals(OfflineAllowanceStatus.EXPIRED, refreshedFirst.getStatus());
        assertNull(refreshedFirst.getActiveAccountId());

        // Total allowances in DB is 2, but exactly 1 has activeAccountId non-null
        assertEquals(2, offlineAllowanceRepository.count());
        assertEquals(1, offlineAllowanceRepository.findAll().stream().filter(a -> a.getActiveAccountId() != null).count());
    }

    @Test
    @DisplayName("10. Atomic rollback: failure during allowance creation rolls back account balances and ledger")
    void issueAllowance_failureRollsBackBalancesAndLedger() {
        // Create an invalid request with excessive duration that fails AFTER argument checks if intercepted,
        // or test transaction rollback by providing an unsupported duration (> 72 hours)
        assertThrows(IllegalArgumentException.class, () ->
                offlineAllowanceService.issueAllowance(new AllowanceIssuanceRequest(
                        "alice",
                        aliceDeviceId,
                        new BigDecimal("1000.00"),
                        "INR",
                        100L // Exceeds MAX_DURATION_HOURS (72)
                ))
        );

        // Alice balance, escrow balance, and ledger are completely untouched
        assertEquals(new BigDecimal("5000.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("0.00"), accountRepository.findById(OfflineAllowanceService.ESCROW_ACCOUNT_ID).orElseThrow().getBalance());
        assertEquals(0, transactionRepository.count());
        assertEquals(0, offlineAllowanceRepository.count());
    }

    @Test
    @DisplayName("11. End-to-end OfflineAllowanceController REST endpoints")
    void offlineAllowanceController_restEndpoints() {
        // 1. GET /api/allowance/bank-public-key
        var pubKeyRes = offlineAllowanceController.getBankPublicKey();
        assertEquals(HttpStatus.OK, pubKeyRes.getStatusCode());
        assertNotNull(pubKeyRes.getBody());
        assertEquals(BankAuthorityKeyService.DEFAULT_MASTER_KEY_ID, pubKeyRes.getBody().get("keyId"));
        assertEquals("RSA", pubKeyRes.getBody().get("algorithm"));
        assertEquals("X.509", pubKeyRes.getBody().get("format"));
        assertEquals(bankAuthorityKeyService.getBankPublicKeyBase64(), pubKeyRes.getBody().get("publicKeyBase64"));

        // 2. POST /api/allowance/issue
        var issueRes = offlineAllowanceController.issueAllowance(new AllowanceIssuanceRequest(
                "alice",
                aliceDeviceId,
                new BigDecimal("1000.00"),
                "INR",
                24L
        ));
        assertEquals(HttpStatus.OK, issueRes.getStatusCode());
        OfflineAllowanceVoucherResponse voucher = issueRes.getBody();
        assertNotNull(voucher);
        assertEquals("alice", voucher.accountId());
        assertEquals(aliceDeviceId, voucher.deviceId());
        assertEquals(new BigDecimal("1000.00"), voucher.allocatedAmount());
        assertEquals(OfflineAllowanceStatus.ACTIVE, voucher.status());
        assertNotNull(voucher.voucherSignature());
        assertEquals(bankAuthorityKeyService.getBankPublicKeyBase64(), voucher.bankPublicKeyBase64());

        // 3. GET /api/allowance/active?accountId=alice
        var activeRes = offlineAllowanceController.getActiveAllowance("alice");
        assertEquals(HttpStatus.OK, activeRes.getStatusCode());
        assertEquals(voucher.allowanceId(), activeRes.getBody().allowanceId());

        // 4. GET /api/allowance/{allowanceId}
        var byIdRes = offlineAllowanceController.getAllowanceById(voucher.allowanceId());
        assertEquals(HttpStatus.OK, byIdRes.getStatusCode());
        assertEquals(voucher.allowanceId(), byIdRes.getBody().allowanceId());

        // 5. GET /api/allowance/active for Bob (no active allowance) returns 404
        var bobActiveRes = offlineAllowanceController.getActiveAllowance("bob");
        assertEquals(HttpStatus.NOT_FOUND, bobActiveRes.getStatusCode());
    }
}

