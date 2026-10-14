package com.demo.upimesh;

import com.demo.upimesh.model.Account;
import com.demo.upimesh.model.AccountRepository;
import com.demo.upimesh.model.DeviceAuthorizationRequest;
import com.demo.upimesh.model.DeviceAuthorizationResponse;
import com.demo.upimesh.model.DeviceAuthorizationStatus;
import com.demo.upimesh.model.KeyRegistrationRequest;
import com.demo.upimesh.model.MeshPaymentResult;
import com.demo.upimesh.model.PaymentInstruction;
import com.demo.upimesh.model.ProcessedPacketRepository;
import com.demo.upimesh.model.SignedPaymentRequest;
import com.demo.upimesh.model.TransactionRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.test.annotation.DirtiesContext;

import java.math.BigDecimal;
import java.security.KeyPair;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.Callable;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Comprehensive Stage 8 backend test suite validating Account-Owner Authorization,
 * Secure Device Pairing, and the PENDING -> AUTHORIZED -> REVOKED -> EXPIRED lifecycle.
 */
@SpringBootTest
@DirtiesContext(classMode = DirtiesContext.ClassMode.BEFORE_EACH_TEST_METHOD)
public class AccountOwnerAuthorizationLifecycleTest {

    @Autowired
    private ApiController apiController;

    @Autowired
    private AccountRepository accountRepository;

    @Autowired
    private TransactionRepository transactionRepository;

    @Autowired
    private ProcessedPacketRepository processedPacketRepository;

    @Autowired
    private SenderKeyRegistry senderKeyRegistry;

    @Autowired
    private DeviceAuthorizationRegistry deviceAuthorizationRegistry;

    @Autowired
    private CryptoService cryptoService;

    @Autowired
    private SettlementService settlementService;

    @Autowired
    private org.springframework.transaction.PlatformTransactionManager transactionManager;

    private static final String TEST_ADMIN_TOKEN = "stage8-test-admin-secret-token";
    private KeyPair aliceDeviceKeyPair;
    private String aliceDeviceId;

    @BeforeEach
    void setUp() throws Exception {
        accountRepository.deleteAll();
        transactionRepository.deleteAll();
        if (processedPacketRepository != null) {
            processedPacketRepository.deleteAll();
        }
        senderKeyRegistry.clearForTesting();
        deviceAuthorizationRegistry.clearForTesting();

        apiController.setConfiguredAdminToken(TEST_ADMIN_TOKEN);

        accountRepository.save(new Account("alice", new BigDecimal("5000.00")));
        accountRepository.save(new Account("bob", new BigDecimal("1000.00")));
        accountRepository.save(new Account("carol", new BigDecimal("2000.00")));

        aliceDeviceId = "alice-phone-" + UUID.randomUUID();
        aliceDeviceKeyPair = cryptoService.generateRsaKeyPair();

        String pubB64 = Base64.getEncoder().encodeToString(aliceDeviceKeyPair.getPublic().getEncoded());
        apiController.registerSenderKey(new KeyRegistrationRequest(aliceDeviceId, pubB64), null, null);
    }

    private SignedPaymentRequest createSignedRequest(
            String deviceId,
            KeyPair keyPair,
            String fromAccount,
            String toAccount,
            BigDecimal amount
    ) throws Exception {
        return createSignedRequest(deviceId, keyPair, "pay-" + UUID.randomUUID(), fromAccount, toAccount, amount);
    }

    private SignedPaymentRequest createSignedRequest(
            String deviceId,
            KeyPair keyPair,
            String paymentId,
            String fromAccount,
            String toAccount,
            BigDecimal amount
    ) throws Exception {
        PaymentInstruction unsigned = new PaymentInstruction(
                paymentId != null ? paymentId : "pay-" + UUID.randomUUID(),
                fromAccount,
                toAccount,
                amount,
                Instant.now(),
                "nonce-" + UUID.randomUUID(),
                null
        );
        String signature = cryptoService.signBase64(unsigned.toCanonicalBytes(), keyPair.getPrivate());
        return new SignedPaymentRequest(deviceId, unsigned.withSignature(signature));
    }

    @Test
    @DisplayName("1. PENDING status: Pairing alone without account-owner authorization blocks debits")
    void debit_pendingStatus_rejectedFailClosed() throws Exception {
        // Pairing initiated with PENDING status (awaiting owner consent and limit binding)
        DeviceAuthorizationRequest pairReq = new DeviceAuthorizationRequest(
                aliceDeviceId,
                "alice",
                TEST_ADMIN_TOKEN,
                DeviceAuthorizationStatus.PENDING.name(),
                new BigDecimal("500.00"),
                24L
        );
        ResponseEntity<DeviceAuthorizationResponse> pairResp = apiController.authorizeDevice(pairReq);
        assertEquals(HttpStatus.OK, pairResp.getStatusCode());
        assertEquals("PENDING", pairResp.getBody().status());

        // Attempt debit while status is PENDING
        SignedPaymentRequest debitReq = createSignedRequest(aliceDeviceId, aliceDeviceKeyPair, "alice", "bob", new BigDecimal("100.00"));
        IllegalStateException ex = assertThrows(IllegalStateException.class, () ->
                apiController.submitSignedMeshPayment(debitReq)
        );
        assertTrue(ex.getMessage().contains("PENDING account-owner consent"), "Must reject debits for PENDING authorization");

        // Verify balances unchanged
        Account alice = accountRepository.findById("alice").orElseThrow();
        assertEquals(new BigDecimal("5000.00"), alice.getBalance());
    }

    @Test
    @DisplayName("2. AUTHORIZED status: Valid authorization with matching key fingerprint and within spending limit settles")
    void debit_authorizedStatus_succeedsWithinLimit() throws Exception {
        // Explicit account-owner authorization with ₹1,000.00 spending limit
        DeviceAuthorizationRequest authReq = new DeviceAuthorizationRequest(
                aliceDeviceId,
                "alice",
                TEST_ADMIN_TOKEN,
                DeviceAuthorizationStatus.AUTHORIZED.name(),
                new BigDecimal("1000.00"),
                48L
        );
        ResponseEntity<DeviceAuthorizationResponse> authResp = apiController.authorizeDevice(authReq);
        assertEquals(HttpStatus.OK, authResp.getStatusCode());
        assertEquals("AUTHORIZED", authResp.getBody().status());
        assertNotNull(authResp.getBody().keyFingerprint(), "Must bind public key fingerprint");

        // Debit ₹450.00 (within ₹1,000.00 limit)
        SignedPaymentRequest debitReq = createSignedRequest(aliceDeviceId, aliceDeviceKeyPair, "alice", "bob", new BigDecimal("450.00"));
        ResponseEntity<MeshPaymentResult> result = apiController.submitSignedMeshPayment(debitReq);

        assertEquals(HttpStatus.OK, result.getStatusCode());
        assertEquals("SETTLED", result.getBody().status());

        Account alice = accountRepository.findById("alice").orElseThrow();
        Account bob = accountRepository.findById("bob").orElseThrow();
        assertEquals(new BigDecimal("4550.00"), alice.getBalance());
        assertEquals(new BigDecimal("1450.00"), bob.getBalance());
    }

    @Test
    @DisplayName("3. Spending limit enforcement: Debits exceeding authorized spending limit are rejected")
    void debit_exceedsSpendingLimit_rejected() throws Exception {
        // Authorize with ₹300.00 spending limit
        DeviceAuthorizationRequest authReq = new DeviceAuthorizationRequest(
                aliceDeviceId,
                "alice",
                TEST_ADMIN_TOKEN,
                DeviceAuthorizationStatus.AUTHORIZED.name(),
                new BigDecimal("300.00"),
                24L
        );
        apiController.authorizeDevice(authReq);

        // Attempt debit of ₹350.00 (exceeds ₹300.00 limit)
        SignedPaymentRequest debitReq = createSignedRequest(aliceDeviceId, aliceDeviceKeyPair, "alice", "bob", new BigDecimal("350.00"));
        IllegalStateException ex = assertThrows(IllegalStateException.class, () ->
                apiController.submitSignedMeshPayment(debitReq)
        );
        assertTrue(ex.getMessage().contains("exceeds authorized spending limit of 300.00"));

        // Verify balance untouched
        Account alice = accountRepository.findById("alice").orElseThrow();
        assertEquals(new BigDecimal("5000.00"), alice.getBalance());
    }

    @Test
    @DisplayName("4. REVOKED status: Explicit revocation immediately prevents subsequent debits")
    void debit_revokedStatus_blockedImmediately() throws Exception {
        // Initially authorize
        apiController.authorizeDevice(new DeviceAuthorizationRequest(
                aliceDeviceId,
                "alice",
                TEST_ADMIN_TOKEN,
                DeviceAuthorizationStatus.AUTHORIZED.name(),
                new BigDecimal("1000.00"),
                24L
        ));

        // Revoke authorization
        DeviceAuthorizationRequest revokeReq = new DeviceAuthorizationRequest(aliceDeviceId, "alice", TEST_ADMIN_TOKEN);
        ResponseEntity<DeviceAuthorizationResponse> revokeResp = apiController.revokeDevice(revokeReq, TEST_ADMIN_TOKEN, null);
        assertEquals(HttpStatus.OK, revokeResp.getStatusCode());
        assertEquals("REVOKED", revokeResp.getBody().status());
        assertNotNull(revokeResp.getBody().revokedAt(), "Revoked timestamp must be recorded");

        // Attempt debit after revocation
        SignedPaymentRequest debitReq = createSignedRequest(aliceDeviceId, aliceDeviceKeyPair, "alice", "bob", new BigDecimal("100.00"));
        IllegalStateException ex = assertThrows(IllegalStateException.class, () ->
                apiController.submitSignedMeshPayment(debitReq)
        );
        assertTrue(ex.getMessage().contains("REVOKED"));

        Account alice = accountRepository.findById("alice").orElseThrow();
        assertEquals(new BigDecimal("5000.00"), alice.getBalance());
    }

    @Test
    @DisplayName("5. EXPIRED status: Time-lapsed authorization rejects debits")
    void debit_expiredStatus_rejected() throws Exception {
        // Authorize with an expiry in the past
        Instant pastExpiry = Instant.now().minus(2, ChronoUnit.HOURS);
        DeviceAuthorizationRequest authReq = new DeviceAuthorizationRequest(
                aliceDeviceId,
                "alice",
                TEST_ADMIN_TOKEN,
                DeviceAuthorizationStatus.AUTHORIZED.name(),
                new BigDecimal("1000.00"),
                pastExpiry,
                null,
                null
        );
        apiController.authorizeDevice(authReq);

        // Attempt debit
        SignedPaymentRequest debitReq = createSignedRequest(aliceDeviceId, aliceDeviceKeyPair, "alice", "bob", new BigDecimal("100.00"));
        IllegalStateException ex = assertThrows(IllegalStateException.class, () ->
                apiController.submitSignedMeshPayment(debitReq)
        );
        assertTrue(ex.getMessage().contains("EXPIRED"));

        Account alice = accountRepository.findById("alice").orElseThrow();
        assertEquals(new BigDecimal("5000.00"), alice.getBalance());
    }

    @Test
    @DisplayName("6. Key fingerprint binding: Device public key substitution is detected and rejected")
    void debit_keyFingerprintMismatch_rejected() throws Exception {
        // Authorize Alice's original device
        apiController.authorizeDevice(new DeviceAuthorizationRequest(
                aliceDeviceId,
                "alice",
                TEST_ADMIN_TOKEN,
                DeviceAuthorizationStatus.AUTHORIZED.name(),
                new BigDecimal("1000.00"),
                24L
        ));

        // Attacker generates a different keypair and replaces key in registry or signs with a different key
        KeyPair attackerKeyPair = cryptoService.generateRsaKeyPair();

        // Sign instruction using unauthorized keypair but claiming Alice's device ID
        SignedPaymentRequest tamperedKeyReq = createSignedRequest(aliceDeviceId, attackerKeyPair, "alice", "bob", new BigDecimal("100.00"));

        // If verified against registry's key, signature check fails;
        // If attacker managed to register key with a different fingerprint, fingerprint check fails
        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () ->
                apiController.submitSignedMeshPayment(tamperedKeyReq)
        );
        assertTrue(ex.getMessage().contains("Invalid digital signature") || ex.getMessage().contains("fingerprint mismatch"));
    }

    @Test
    @DisplayName("7. Account mismatch: Device authorized for Alice cannot debit Bob or Carol")
    void debit_accountMismatch_rejected() throws Exception {
        apiController.authorizeDevice(new DeviceAuthorizationRequest(
                aliceDeviceId,
                "alice",
                TEST_ADMIN_TOKEN,
                DeviceAuthorizationStatus.AUTHORIZED.name(),
                new BigDecimal("1000.00"),
                24L
        ));

        // Attempt debiting Bob using Alice's device
        SignedPaymentRequest debitReq = createSignedRequest(aliceDeviceId, aliceDeviceKeyPair, "bob", "alice", new BigDecimal("100.00"));
        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () ->
                apiController.submitSignedMeshPayment(debitReq)
        );
        assertTrue(ex.getMessage().contains("is not authorized to debit account 'bob'"));
    }

    @Test
    @DisplayName("8. Carol safeguard preserved: Unauthorized devices cannot debit Carol")
    void debit_carolProtected_cannotDebitWithoutAuthorization() throws Exception {
        // Verify Carol cannot be debited by Alice's device
        SignedPaymentRequest debitReq = createSignedRequest(aliceDeviceId, aliceDeviceKeyPair, "carol", "bob", new BigDecimal("50.00"));
        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () ->
                apiController.submitSignedMeshPayment(debitReq)
        );
        assertTrue(ex.getMessage().contains("is not authorized to debit account 'carol'"));

        Account carol = accountRepository.findById("carol").orElseThrow();
        assertEquals(new BigDecimal("2000.00"), carol.getBalance(), "Carol balance must remain intact");
    }

    @Test
    @DisplayName("9. Authorizations query endpoint returns complete Stage 8 lifecycle details when authenticated")
    void query_authorizationStatus_returnsLifecycleDetails() {
        DeviceAuthorizationRequest authReq = new DeviceAuthorizationRequest(
                aliceDeviceId,
                "alice",
                TEST_ADMIN_TOKEN,
                DeviceAuthorizationStatus.AUTHORIZED.name(),
                new BigDecimal("2500.00"),
                72L
        );
        apiController.authorizeDevice(authReq);

        ResponseEntity<DeviceAuthorizationResponse> queryResp = apiController.getDeviceAccountAuthorization(
                aliceDeviceId,
                "alice",
                TEST_ADMIN_TOKEN,
                null
        );
        assertEquals(HttpStatus.OK, queryResp.getStatusCode());
        assertNotNull(queryResp.getBody());
        assertEquals("AUTHORIZED", queryResp.getBody().status());
        assertEquals(new BigDecimal("2500.00"), queryResp.getBody().spendingLimit());
        assertNotNull(queryResp.getBody().keyFingerprint());
        assertNotNull(queryResp.getBody().expiresAt());
    }

    @Test
    @DisplayName("10. Concurrent debits under valid authorization execute safely and debit exactly once per instruction")
    void concurrentDebits_underValidAuthorization_executeSafely() throws Exception {
        // Authorize Alice's device with sufficient spending limit for ₹100.00 debits
        apiController.authorizeDevice(new DeviceAuthorizationRequest(
                aliceDeviceId,
                "alice",
                TEST_ADMIN_TOKEN,
                DeviceAuthorizationStatus.AUTHORIZED.name(),
                new BigDecimal("500.00"),
                24L
        ));

        int threadCount = 4;
        ExecutorService executor = Executors.newFixedThreadPool(threadCount);
        List<Callable<MeshPaymentResult>> tasks = new ArrayList<>();

        for (int i = 0; i < threadCount; i++) {
            SignedPaymentRequest req = createSignedRequest(aliceDeviceId, aliceDeviceKeyPair, "alice", "bob", new BigDecimal("50.00"));
            tasks.add(() -> {
                int attempts = 0;
                while (attempts < 5) {
                    try {
                        attempts++;
                        ResponseEntity<MeshPaymentResult> resp = apiController.submitSignedMeshPayment(req);
                        return resp.getBody();
                    } catch (IllegalStateException e) {
                        if (e.getMessage().contains("Concurrent ledger update conflict") && attempts < 5) {
                            Thread.sleep(25);
                            continue;
                        }
                        throw e;
                    }
                }
                return null;
            });
        }

        List<Future<MeshPaymentResult>> futures = executor.invokeAll(tasks);
        executor.shutdown();

        int successfulDebits = 0;
        for (Future<MeshPaymentResult> f : futures) {
            MeshPaymentResult res = f.get();
            if (res != null && "SETTLED".equalsIgnoreCase(res.status())) {
                successfulDebits++;
            }
        }

        assertEquals(threadCount, successfulDebits, "All valid distinct debit instructions should settle");

        Account alice = accountRepository.findById("alice").orElseThrow();
        Account bob = accountRepository.findById("bob").orElseThrow();
        BigDecimal totalDebited = new BigDecimal("50.00").multiply(new BigDecimal(threadCount));
        assertEquals(new BigDecimal("5000.00").subtract(totalDebited), alice.getBalance());
        assertEquals(new BigDecimal("1000.00").add(totalDebited), bob.getBalance());
    }

    @Test
    @DisplayName("11. Vulnerability 1 Regression: Admin token cannot authorize debits for Carol without owner consent")
    void authorizeDevice_carolAccount_rejectedWithHttp403Forbidden() {
        DeviceAuthorizationRequest carolAuthReq = new DeviceAuthorizationRequest(
                aliceDeviceId,
                "carol",
                TEST_ADMIN_TOKEN,
                DeviceAuthorizationStatus.AUTHORIZED.name(),
                new BigDecimal("500.00"),
                24L
        );

        ResponseEntity<DeviceAuthorizationResponse> response = apiController.authorizeDevice(carolAuthReq);
        assertEquals(HttpStatus.FORBIDDEN, response.getStatusCode());
        assertNotNull(response.getBody());
        assertEquals("FORBIDDEN", response.getBody().status());
        assertTrue(response.getBody().message().contains("cryptographic proof of account-owner consent is not implemented"));

        // Confirm Carol is NOT authorized in registry
        assertFalse(deviceAuthorizationRegistry.isDeviceAuthorized(aliceDeviceId, "carol"));
    }

    @Test
    @DisplayName("12. Vulnerability 2 Regression: Device ID matching account ID cannot bypass authorization checks")
    void debit_deviceIdEqualsFromAccount_cannotBypassAuthorization() throws Exception {
        // Register key for a device named "carol"
        KeyPair carolKeyPair = cryptoService.generateRsaKeyPair();
        senderKeyRegistry.registerKey("carol", carolKeyPair.getPublic());

        // Attempt debit with deviceId == "carol" and fromAccount == "carol"
        SignedPaymentRequest debitReq = createSignedRequest("carol", carolKeyPair, "carol", "bob", new BigDecimal("50.00"));
        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () ->
                apiController.submitSignedMeshPayment(debitReq)
        );
        assertTrue(ex.getMessage().contains("is not authorized to debit account 'carol'"));

        // Carol's balance must remain untouched
        Account carol = accountRepository.findById("carol").orElseThrow();
        assertEquals(new BigDecimal("2000.00"), carol.getBalance());

        // Also test for Alice without prior authorization: deviceId="alice", fromAccount="alice"
        senderKeyRegistry.registerKey("alice", aliceDeviceKeyPair.getPublic());
        SignedPaymentRequest aliceSelfReq = createSignedRequest("alice", aliceDeviceKeyPair, "alice", "bob", new BigDecimal("50.00"));
        IllegalArgumentException aliceEx = assertThrows(IllegalArgumentException.class, () ->
                apiController.submitSignedMeshPayment(aliceSelfReq)
        );
        assertTrue(aliceEx.getMessage().contains("is not authorized to debit account 'alice'"));
    }

    @Test
    @DisplayName("13. Vulnerability 3 Regression: Unauthenticated authorizations query is rejected with HTTP 401")
    void queryAuthorization_unauthenticated_rejectedWithHttp401Unauthorized() {
        // Unauthenticated call without token
        ResponseEntity<DeviceAuthorizationResponse> noTokenResp = apiController.getDeviceAccountAuthorization(
                aliceDeviceId,
                "alice"
        );
        assertEquals(HttpStatus.UNAUTHORIZED, noTokenResp.getStatusCode());
        assertEquals("UNAUTHORIZED", noTokenResp.getBody().status());

        // Call with invalid token
        ResponseEntity<DeviceAuthorizationResponse> badTokenResp = apiController.getDeviceAccountAuthorization(
                aliceDeviceId,
                "alice",
                "invalid-token",
                null
        );
        assertEquals(HttpStatus.UNAUTHORIZED, badTokenResp.getStatusCode());
        assertEquals("UNAUTHORIZED", badTokenResp.getBody().status());
    }

    @Test
    @DisplayName("14. Vulnerability 4 Regression: Non-positive spending limit and validity are rejected with HTTP 400")
    void authorizeDevice_invalidSpendingLimitAndValidity_rejectedWithBadRequest() {
        // Zero spending limit
        DeviceAuthorizationRequest zeroLimitReq = new DeviceAuthorizationRequest(
                aliceDeviceId,
                "alice",
                TEST_ADMIN_TOKEN,
                DeviceAuthorizationStatus.AUTHORIZED.name(),
                BigDecimal.ZERO,
                24L
        );
        IllegalArgumentException zeroEx = assertThrows(IllegalArgumentException.class, () ->
                apiController.authorizeDevice(zeroLimitReq)
        );
        assertTrue(zeroEx.getMessage().contains("spendingLimit must be greater than zero"));

        // Negative spending limit
        DeviceAuthorizationRequest negLimitReq = new DeviceAuthorizationRequest(
                aliceDeviceId,
                "alice",
                TEST_ADMIN_TOKEN,
                DeviceAuthorizationStatus.AUTHORIZED.name(),
                new BigDecimal("-500.00"),
                24L
        );
        IllegalArgumentException negEx = assertThrows(IllegalArgumentException.class, () ->
                apiController.authorizeDevice(negLimitReq)
        );
        assertTrue(negEx.getMessage().contains("spendingLimit must be greater than zero"));

        // Negative validity hours
        DeviceAuthorizationRequest negHoursReq = new DeviceAuthorizationRequest(
                aliceDeviceId,
                "alice",
                TEST_ADMIN_TOKEN,
                DeviceAuthorizationStatus.AUTHORIZED.name(),
                new BigDecimal("500.00"),
                -10L
        );
        IllegalArgumentException hoursEx = assertThrows(IllegalArgumentException.class, () ->
                apiController.authorizeDevice(negHoursReq)
        );
        assertTrue(hoursEx.getMessage().contains("validityHours must be greater than zero"));
    }

    @Test
    @DisplayName("15. Vulnerability 5 Regression: Missing key fingerprint binding in active authorization fails closed")
    void verifyDebitAuthorization_missingKeyFingerprint_rejectedFailClosed() {
        // Register an authorization with null fingerprint
        deviceAuthorizationRegistry.authorizeDevice(
                aliceDeviceId,
                "alice",
                DeviceAuthorizationStatus.AUTHORIZED,
                "", // Blank fingerprint
                new BigDecimal("1000.00"),
                Instant.now().plus(24, ChronoUnit.HOURS)
        );

        IllegalStateException ex = assertThrows(IllegalStateException.class, () ->
                deviceAuthorizationRegistry.verifyDebitAuthorization(
                        aliceDeviceId,
                        "alice",
                        new BigDecimal("100.00"),
                        aliceDeviceKeyPair.getPublic()
                )
        );
        assertTrue(ex.getMessage().contains("missing required public-key fingerprint binding"));
    }

    @Test
    @DisplayName("16. Vulnerability 6 Regression: Revocation immediately blocks debits without cache sync race")
    void concurrentRevocation_immediatelyBlocksSubsequentDebits() throws Exception {
        // Authorize Alice's device
        apiController.authorizeDevice(new DeviceAuthorizationRequest(
                aliceDeviceId,
                "alice",
                TEST_ADMIN_TOKEN,
                DeviceAuthorizationStatus.AUTHORIZED.name(),
                new BigDecimal("1000.00"),
                24L
        ));

        // First debit settles
        SignedPaymentRequest req1 = createSignedRequest(aliceDeviceId, aliceDeviceKeyPair, "alice", "bob", new BigDecimal("50.00"));
        ResponseEntity<MeshPaymentResult> res1 = apiController.submitSignedMeshPayment(req1);
        assertEquals("SETTLED", res1.getBody().status());

        // Revoke device
        apiController.revokeDevice(new DeviceAuthorizationRequest(aliceDeviceId, "alice", TEST_ADMIN_TOKEN), TEST_ADMIN_TOKEN, null);

        // Subsequent debit immediately rejected
        SignedPaymentRequest req2 = createSignedRequest(aliceDeviceId, aliceDeviceKeyPair, "alice", "bob", new BigDecimal("50.00"));
        IllegalStateException ex = assertThrows(IllegalStateException.class, () ->
                apiController.submitSignedMeshPayment(req2)
        );
        assertTrue(ex.getMessage().contains("REVOKED"));
    }

    @Test
    @DisplayName("17. Revocation vs. settlement race: Revocation atomically blocks in-flight or racing settlement")
    void revocationVsSettlement_simultaneousRace_strictlyOrdered() throws Exception {
        // Authorize Alice's device
        apiController.authorizeDevice(new DeviceAuthorizationRequest(
                aliceDeviceId,
                "alice",
                TEST_ADMIN_TOKEN,
                DeviceAuthorizationStatus.AUTHORIZED.name(),
                new BigDecimal("1000.00"),
                24L
        ));

        CyclicBarrier barrier = new CyclicBarrier(2);
        AtomicBoolean settlementSucceeded = new AtomicBoolean(false);
        AtomicBoolean settlementFailedRevoked = new AtomicBoolean(false);

        SignedPaymentRequest debitReq = createSignedRequest(aliceDeviceId, aliceDeviceKeyPair, "alice", "bob", new BigDecimal("100.00"));

        Thread settleThread = new Thread(() -> {
            try {
                barrier.await(5, TimeUnit.SECONDS);
                ResponseEntity<MeshPaymentResult> resp = apiController.submitSignedMeshPayment(debitReq);
                if (resp != null && "SETTLED".equalsIgnoreCase(resp.getBody().status())) {
                    settlementSucceeded.set(true);
                }
            } catch (IllegalStateException e) {
                if (e.getMessage().contains("REVOKED")) {
                    settlementFailedRevoked.set(true);
                }
            } catch (Exception ignored) {}
        });

        Thread revokeThread = new Thread(() -> {
            try {
                barrier.await(5, TimeUnit.SECONDS);
                apiController.revokeDevice(new DeviceAuthorizationRequest(aliceDeviceId, "alice", TEST_ADMIN_TOKEN), TEST_ADMIN_TOKEN, null);
            } catch (Exception ignored) {}
        });

        settleThread.start();
        revokeThread.start();
        settleThread.join(5000);
        revokeThread.join(5000);

        // Revocation must be committed in registry
        assertFalse(deviceAuthorizationRegistry.isDeviceAuthorized(aliceDeviceId, "alice"));

        // Exactly one of two deterministic outcomes occurred without partial/corrupted state:
        // Outcome A: Settlement acquired lock before revocation -> settled, then revocation revoked.
        // Outcome B: Revocation acquired lock before settlement -> settlement failed closed with REVOKED.
        assertTrue(settlementSucceeded.get() || settlementFailedRevoked.get(), "Settlement must either cleanly settle before revocation or fail-closed as REVOKED");

        if (settlementSucceeded.get()) {
            Account alice = accountRepository.findById("alice").orElseThrow();
            assertEquals(new BigDecimal("4900.00"), alice.getBalance());
        } else {
            Account alice = accountRepository.findById("alice").orElseThrow();
            assertEquals(new BigDecimal("5000.00"), alice.getBalance());
        }

        // In either case, any subsequent debit must be immediately rejected
        SignedPaymentRequest postRevokeReq = createSignedRequest(aliceDeviceId, aliceDeviceKeyPair, "alice", "bob", new BigDecimal("50.00"));
        IllegalStateException ex = assertThrows(IllegalStateException.class, () ->
                apiController.submitSignedMeshPayment(postRevokeReq)
        );
        assertTrue(ex.getMessage().contains("REVOKED"));
    }

    @Test
    @DisplayName("18. Revocation holding lock blocks pending settlement deterministically until fail-closed rejection")
    void revocationHoldingLock_blocksSettlementDeterministically() throws Exception {
        // Authorize Alice's device
        apiController.authorizeDevice(new DeviceAuthorizationRequest(
                aliceDeviceId,
                "alice",
                TEST_ADMIN_TOKEN,
                DeviceAuthorizationStatus.AUTHORIZED.name(),
                new BigDecimal("1000.00"),
                24L
        ));

        CountDownLatch revokeStartedLatch = new CountDownLatch(1);
        CountDownLatch revokeHoldLatch = new CountDownLatch(1);
        AtomicBoolean settlementRejected = new AtomicBoolean(false);

        // Thread 1 acquires write lock simulating an in-progress revocation operation
        Thread revoker = new Thread(() -> {
            var lock = deviceAuthorizationRegistry.getAuthorizationLock(aliceDeviceId, "alice");
            lock.writeLock().lock();
            try {
                revokeStartedLatch.countDown();
                // Mutate authorization to REVOKED while holding lock
                deviceAuthorizationRegistry.revokeDevice(aliceDeviceId, "alice");
                revokeHoldLatch.await(3, TimeUnit.SECONDS);
            } catch (Exception ignored) {
            } finally {
                lock.writeLock().unlock();
            }
        });

        // Thread 2 attempts settlement while revocation is holding lock
        Thread settler = new Thread(() -> {
            try {
                revokeStartedLatch.await(3, TimeUnit.SECONDS);
                SignedPaymentRequest req = createSignedRequest(aliceDeviceId, aliceDeviceKeyPair, "alice", "bob", new BigDecimal("100.00"));
                apiController.submitSignedMeshPayment(req);
            } catch (IllegalStateException e) {
                if (e.getMessage().contains("REVOKED")) {
                    settlementRejected.set(true);
                }
            } catch (Exception ignored) {}
        });

        revoker.start();
        settler.start();

        // Allow some time for settler to block on lock, then release revoker
        Thread.sleep(50);
        revokeHoldLatch.countDown();

        revoker.join(3000);
        settler.join(3000);

        assertTrue(settlementRejected.get(), "Settlement blocked behind revocation write lock must fail-closed once lock releases");
        Account alice = accountRepository.findById("alice").orElseThrow();
        assertEquals(new BigDecimal("5000.00"), alice.getBalance(), "No balance debit should have occurred");
    }

    @Test
    @DisplayName("19. Concurrent duplicate submissions: Exactly one settles and database constraints prevent double-spending")
    void concurrentDuplicateSubmissions_settleExactlyOnce() throws Exception {
        // Authorize Alice's device
        apiController.authorizeDevice(new DeviceAuthorizationRequest(
                aliceDeviceId,
                "alice",
                TEST_ADMIN_TOKEN,
                DeviceAuthorizationStatus.AUTHORIZED.name(),
                new BigDecimal("1000.00"),
                24L
        ));

        int threadCount = 4;
        CyclicBarrier barrier = new CyclicBarrier(threadCount);
        ExecutorService executor = Executors.newFixedThreadPool(threadCount);

        // Create the EXACT SAME signed payment instruction
        SignedPaymentRequest identicalRequest = createSignedRequest(aliceDeviceId, aliceDeviceKeyPair, "alice", "bob", new BigDecimal("150.00"));

        List<Callable<Boolean>> tasks = new ArrayList<>();
        for (int i = 0; i < threadCount; i++) {
            tasks.add(() -> {
                barrier.await(5, TimeUnit.SECONDS);
                try {
                    ResponseEntity<MeshPaymentResult> resp = apiController.submitSignedMeshPayment(identicalRequest);
                    return resp != null && "SETTLED".equalsIgnoreCase(resp.getBody().status());
                } catch (DuplicatePacketException e) {
                    return false;
                }
            });
        }

        List<Future<Boolean>> futures = executor.invokeAll(tasks);
        executor.shutdown();

        int successfulSubmissions = 0;
        int duplicateRejections = 0;
        for (Future<Boolean> f : futures) {
            if (f.get()) {
                successfulSubmissions++;
            } else {
                duplicateRejections++;
            }
        }

        assertEquals(1, successfulSubmissions, "Exactly one duplicate submission must successfully initiate settlement");
        assertEquals(threadCount - 1, duplicateRejections, "All other concurrent duplicates must be rejected as duplicates");

        // Alice must be debited exactly ONCE (₹150.00, not 4 × ₹150.00)
        Account alice = accountRepository.findById("alice").orElseThrow();
        Account bob = accountRepository.findById("bob").orElseThrow();
        assertEquals(new BigDecimal("4850.00"), alice.getBalance());
        assertEquals(new BigDecimal("1150.00"), bob.getBalance());

        // Exactly one ledger transaction record
        assertEquals(1, transactionRepository.count());
        // Exactly one processed packet record
        assertEquals(1, processedPacketRepository.count());
    }

    @Test
    @DisplayName("20. Concurrent spending limits: Per-instruction ceiling is strictly enforced across threads")
    void concurrentSpendingLimits_perInstructionCeilingStrictlyEnforced() throws Exception {
        // Authorize Alice's device with ₹200.00 per-instruction ceiling
        apiController.authorizeDevice(new DeviceAuthorizationRequest(
                aliceDeviceId,
                "alice",
                TEST_ADMIN_TOKEN,
                DeviceAuthorizationStatus.AUTHORIZED.name(),
                new BigDecimal("200.00"),
                24L
        ));

        // 1. Single instruction exceeding ceiling is rejected
        SignedPaymentRequest overCeiling = createSignedRequest(aliceDeviceId, aliceDeviceKeyPair, "alice", "bob", new BigDecimal("250.00"));
        IllegalStateException ex = assertThrows(IllegalStateException.class, () ->
                apiController.submitSignedMeshPayment(overCeiling)
        );
        assertTrue(ex.getMessage().contains("exceeds authorized spending limit of 200.00"));

        // 2. Concurrently submit 2 instructions within the ₹200.00 limit (₹120.00 each)
        CyclicBarrier barrier = new CyclicBarrier(2);
        ExecutorService executor = Executors.newFixedThreadPool(2);

        SignedPaymentRequest req1 = createSignedRequest(aliceDeviceId, aliceDeviceKeyPair, "alice", "bob", new BigDecimal("120.00"));
        SignedPaymentRequest req2 = createSignedRequest(aliceDeviceId, aliceDeviceKeyPair, "alice", "bob", new BigDecimal("120.00"));

        List<Callable<MeshPaymentResult>> tasks = List.of(
                () -> {
                    barrier.await(5, TimeUnit.SECONDS);
                    int attempts = 0;
                    while (attempts < 5) {
                        try {
                            attempts++;
                            return apiController.submitSignedMeshPayment(req1).getBody();
                        } catch (IllegalStateException e) {
                            if (e.getMessage().contains("Concurrent ledger update conflict") && attempts < 5) {
                                Thread.sleep(25);
                                continue;
                            }
                            throw e;
                        }
                    }
                    return null;
                },
                () -> {
                    barrier.await(5, TimeUnit.SECONDS);
                    int attempts = 0;
                    while (attempts < 5) {
                        try {
                            attempts++;
                            return apiController.submitSignedMeshPayment(req2).getBody();
                        } catch (IllegalStateException e) {
                            if (e.getMessage().contains("Concurrent ledger update conflict") && attempts < 5) {
                                Thread.sleep(25);
                                continue;
                            }
                            throw e;
                        }
                    }
                    return null;
                }
        );

        List<Future<MeshPaymentResult>> futures = executor.invokeAll(tasks);
        executor.shutdown();

        for (Future<MeshPaymentResult> f : futures) {
            assertNotNull(f.get());
            assertEquals("SETTLED", f.get().status());
        }

        // Both individual instructions satisfied the ₹200.00 per-instruction ceiling
        Account alice = accountRepository.findById("alice").orElseThrow();
        assertEquals(new BigDecimal("4760.00"), alice.getBalance()); // 5000 - 240
    }

    @Test
    @DisplayName("21. Cache consistency: Stale in-memory cache dynamically evaluates expiry on read and fails closed")
    void cacheConsistency_staleCacheEntry_evaluatesDynamicExpiry() {
        // Authorize Alice's device with a past expiration timestamp
        Instant pastExpiry = Instant.now().minus(1, ChronoUnit.HOURS);
        DeviceAuthorizationRequest authReq = new DeviceAuthorizationRequest(
                aliceDeviceId,
                "alice",
                TEST_ADMIN_TOKEN,
                DeviceAuthorizationStatus.AUTHORIZED.name(),
                new BigDecimal("500.00"),
                pastExpiry,
                null,
                null
        );
        apiController.authorizeDevice(authReq);

        // 1. isDeviceAuthorized should return false dynamically
        assertFalse(deviceAuthorizationRegistry.isDeviceAuthorized(aliceDeviceId, "alice"));

        // 2. getAuthorization should return EXPIRED status dynamically
        var authOpt = deviceAuthorizationRegistry.getAuthorization(aliceDeviceId, "alice");
        assertTrue(authOpt.isPresent());
        assertEquals("EXPIRED", authOpt.get().getStatus());

        // 3. verifyDebitAuthorization must fail closed
        IllegalStateException ex = assertThrows(IllegalStateException.class, () ->
                deviceAuthorizationRegistry.verifyDebitAuthorization(
                        aliceDeviceId,
                        "alice",
                        new BigDecimal("50.00"),
                        aliceDeviceKeyPair.getPublic()
                )
        );
        assertTrue(ex.getMessage().contains("EXPIRED"));
    }

    @Test
    @DisplayName("22. Transaction boundary: Rollback in revocation restores in-memory cache and prevents desynchronization")
    void transactionRollback_inRevocation_restoresInMemoryCache() throws Exception {
        // 1. Authorize Alice's device
        DeviceAuthorizationRequest authReq = new DeviceAuthorizationRequest(
                aliceDeviceId,
                "alice",
                TEST_ADMIN_TOKEN,
                DeviceAuthorizationStatus.AUTHORIZED.name(),
                new BigDecimal("500.00"),
                Instant.now().plus(30, ChronoUnit.DAYS),
                null,
                null
        );
        apiController.authorizeDevice(authReq);
        assertTrue(deviceAuthorizationRegistry.isDeviceAuthorized(aliceDeviceId, "alice"));

        // 2. Execute revocation inside an outer transaction that rolls back
        org.springframework.transaction.support.TransactionTemplate txTemplate =
                new org.springframework.transaction.support.TransactionTemplate(transactionManager);

        assertThrows(RuntimeException.class, () ->
                txTemplate.execute(status -> {
                    deviceAuthorizationRegistry.revokeDevice(aliceDeviceId, "alice");
                    // Force transaction rollback
                    throw new RuntimeException("Simulated transaction failure to trigger rollback");
                })
        );

        // 3. Verify in-memory cache was restored to pre-revocation state
        assertTrue(deviceAuthorizationRegistry.isDeviceAuthorized(aliceDeviceId, "alice"));
        assertTrue(deviceAuthorizationRegistry.getAuthorizedAccounts(aliceDeviceId).contains("alice"));
        var authOpt = deviceAuthorizationRegistry.getAuthorization(aliceDeviceId, "alice");
        assertTrue(authOpt.isPresent());
        assertEquals("AUTHORIZED", authOpt.get().getStatus());

        // 4. Verify settlement succeeds using the restored authorization
        SignedPaymentRequest payReq = createSignedRequest(
                aliceDeviceId,
                aliceDeviceKeyPair,
                "alice",
                "bob",
                new BigDecimal("25.00")
        );
        ResponseEntity<MeshPaymentResult> response = apiController.submitSignedMeshPayment(payReq);
        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertEquals("SETTLED", response.getBody().status());
    }

    @Test
    @DisplayName("23. Transaction boundary: executeWithAuthorization holds read-lock across transaction duration; revocation blocks until commit")
    void executeWithAuthorization_holdsReadLockUntilTransactionCommit() throws Exception {
        // 1. Authorize Alice's device
        DeviceAuthorizationRequest authReq = new DeviceAuthorizationRequest(
                aliceDeviceId,
                "alice",
                TEST_ADMIN_TOKEN,
                DeviceAuthorizationStatus.AUTHORIZED.name(),
                new BigDecimal("500.00"),
                Instant.now().plus(30, ChronoUnit.DAYS),
                null,
                null
        );
        apiController.authorizeDevice(authReq);

        CountDownLatch settlementInsideTxLatch = new CountDownLatch(1);
        CountDownLatch revocationAttemptLatch = new CountDownLatch(1);
        CountDownLatch completeSettlementLatch = new CountDownLatch(1);

        ExecutorService executor = Executors.newFixedThreadPool(2);
        AtomicBoolean settlementCommittedBeforeRevocation = new AtomicBoolean(false);
        AtomicBoolean revocationFinished = new AtomicBoolean(false);

        // Thread 1: Executes settlement within an outer transaction, holding read lock until transaction commits
        Future<?> settlementFuture = executor.submit(() -> {
            org.springframework.transaction.support.TransactionTemplate txTemplate =
                    new org.springframework.transaction.support.TransactionTemplate(transactionManager);
            txTemplate.execute(status -> {
                try {
                    return deviceAuthorizationRegistry.executeWithAuthorization(
                            aliceDeviceId,
                            "alice",
                            new BigDecimal("30.00"),
                            aliceDeviceKeyPair.getPublic(),
                            () -> {
                                PaymentInstruction instruction = new PaymentInstruction(
                                        UUID.randomUUID().toString(),
                                        "alice",
                                        "bob",
                                        new BigDecimal("30.00"),
                                        Instant.now(),
                                        UUID.randomUUID().toString(),
                                        null
                                );
                                settlementService.settlePayment(instruction, UUID.randomUUID().toString());
                                settlementInsideTxLatch.countDown(); // Signal that settlement is inside transaction with read lock held
                                revocationAttemptLatch.await(5, TimeUnit.SECONDS);
                                completeSettlementLatch.await(5, TimeUnit.SECONDS);
                                return null;
                            }
                    );
                } catch (Exception e) {
                    throw new RuntimeException(e);
                }
            });
            // Outer transaction has committed!
            settlementCommittedBeforeRevocation.set(!revocationFinished.get());
        });

        // Thread 2: Attempts revocation while settlement transaction is active
        Future<?> revocationFuture = executor.submit(() -> {
            try {
                settlementInsideTxLatch.await(5, TimeUnit.SECONDS);
                revocationAttemptLatch.countDown();
                // revokeDevice must acquire the write lock. Because Thread 1 holds the read lock across the transaction,
                // Thread 2 must block here until Thread 1's transaction commits!
                deviceAuthorizationRegistry.revokeDevice(aliceDeviceId, "alice");
                revocationFinished.set(true);
            } catch (Exception e) {
                throw new RuntimeException(e);
            }
        });

        // Give Thread 2 time to block on the write lock
        Thread.sleep(100);
        assertFalse(revocationFinished.get(), "Revocation should be blocked while settlement transaction is active");

        // Now allow Thread 1 to complete and commit its transaction
        completeSettlementLatch.countDown();

        settlementFuture.get(5, TimeUnit.SECONDS);
        revocationFuture.get(5, TimeUnit.SECONDS);
        executor.shutdown();

        // Verify ordering: settlement committed before revocation completed
        assertTrue(settlementCommittedBeforeRevocation.get());
        assertTrue(revocationFinished.get());

        // Now device is revoked; subsequent settlement must fail closed
        SignedPaymentRequest payReq = createSignedRequest(
                aliceDeviceId,
                aliceDeviceKeyPair,
                "alice",
                "bob",
                new BigDecimal("10.00")
        );
        IllegalStateException ex = assertThrows(IllegalStateException.class, () ->
                apiController.submitSignedMeshPayment(payReq)
        );
        assertTrue(ex.getMessage().contains("REVOKED"));
    }

    @Test
    @DisplayName("24. Optimistic locking: Concurrent ledger updates on same account handle conflict safely without partial mutations")
    void concurrentOptimisticLocking_handlesConflictSafely() throws Exception {
        // Authorize device for Alice
        DeviceAuthorizationRequest authReq = new DeviceAuthorizationRequest(
                aliceDeviceId,
                "alice",
                TEST_ADMIN_TOKEN,
                DeviceAuthorizationStatus.AUTHORIZED.name(),
                new BigDecimal("500.00"),
                Instant.now().plus(30, ChronoUnit.DAYS),
                null,
                null
        );
        apiController.authorizeDevice(authReq);

        SignedPaymentRequest req1 = createSignedRequest(
                aliceDeviceId,
                aliceDeviceKeyPair,
                "alice",
                "bob",
                new BigDecimal("50.00")
        );
        SignedPaymentRequest req2 = createSignedRequest(
                aliceDeviceId,
                aliceDeviceKeyPair,
                "alice",
                "bob",
                new BigDecimal("50.00")
        );

        CyclicBarrier barrier = new CyclicBarrier(2);
        ExecutorService executor = Executors.newFixedThreadPool(2);
        AtomicInteger successCount = new AtomicInteger(0);
        AtomicInteger conflictCount = new AtomicInteger(0);

        List<Callable<Void>> tasks = List.of(
                () -> {
                    barrier.await(5, TimeUnit.SECONDS);
                    try {
                        ResponseEntity<MeshPaymentResult> res = apiController.submitSignedMeshPayment(req1);
                        if (res.getStatusCode() == HttpStatus.OK) {
                            successCount.incrementAndGet();
                        }
                    } catch (IllegalStateException e) {
                        if (e.getMessage().contains("Concurrent ledger update conflict")) {
                            conflictCount.incrementAndGet();
                        } else {
                            throw e;
                        }
                    }
                    return null;
                },
                () -> {
                    barrier.await(5, TimeUnit.SECONDS);
                    try {
                        ResponseEntity<MeshPaymentResult> res = apiController.submitSignedMeshPayment(req2);
                        if (res.getStatusCode() == HttpStatus.OK) {
                            successCount.incrementAndGet();
                        }
                    } catch (IllegalStateException e) {
                        if (e.getMessage().contains("Concurrent ledger update conflict")) {
                            conflictCount.incrementAndGet();
                        } else {
                            throw e;
                        }
                    }
                    return null;
                }
        );

        List<Future<Void>> futures = executor.invokeAll(tasks);
        executor.shutdown();
        for (Future<Void> f : futures) {
            f.get(5, TimeUnit.SECONDS);
        }

        // Ledger must be consistent:
        // Either both succeeded (serialized), or one succeeded and one experienced optimistic lock conflict
        assertTrue(successCount.get() >= 1, "At least one settlement should succeed");
        Account alice = accountRepository.findById("alice").orElseThrow();
        Account bob = accountRepository.findById("bob").orElseThrow();

        if (successCount.get() == 2) {
            assertEquals(new BigDecimal("4900.00"), alice.getBalance());
            assertEquals(new BigDecimal("1100.00"), bob.getBalance());
        } else {
            assertEquals(1, conflictCount.get());
            assertEquals(new BigDecimal("4950.00"), alice.getBalance());
            assertEquals(new BigDecimal("1050.00"), bob.getBalance());
        }
    }

    @Test
    @DisplayName("25. Transaction rollback: Failed settlement leaves zero ledger/packet artifacts; status check returns NOT_FOUND")
    void failedSettlement_leavesZeroArtifacts_statusReturnsNotFound() throws Exception {
        // Authorize device for Alice
        DeviceAuthorizationRequest authReq = new DeviceAuthorizationRequest(
                aliceDeviceId,
                "alice",
                TEST_ADMIN_TOKEN,
                DeviceAuthorizationStatus.AUTHORIZED.name(),
                new BigDecimal("500.00"),
                Instant.now().plus(30, ChronoUnit.DAYS),
                null,
                null
        );
        apiController.authorizeDevice(authReq);

        String paymentId = "failing-payment-" + UUID.randomUUID();
        Account alice = accountRepository.findById("alice").orElseThrow();
        alice.setBalance(new BigDecimal("10.00"));
        accountRepository.save(alice);

        SignedPaymentRequest req = createSignedRequest(
                aliceDeviceId,
                aliceDeviceKeyPair,
                paymentId,
                "alice",
                "bob",
                new BigDecimal("20.00")
        );

        // Submit settlement: must throw Insufficient funds
        IllegalStateException ex = assertThrows(IllegalStateException.class, () ->
                apiController.submitSignedMeshPayment(req)
        );
        assertTrue(ex.getMessage().contains("Insufficient funds"));

        // 1. Alice's balance must remain 10.00
        Account aliceAfter = accountRepository.findById("alice").orElseThrow();
        assertEquals(new BigDecimal("10.00"), aliceAfter.getBalance());

        // 2. No transaction record created
        assertEquals(0, transactionRepository.findAll().size());

        // 3. No processed packet record created
        assertFalse(processedPacketRepository.findByPaymentId(paymentId).isPresent());

        // 4. Authoritative payment status endpoint returns 404 NOT_FOUND
        ResponseEntity<com.demo.upimesh.model.PaymentStatusResponse> statusRes = apiController.getPaymentStatus(paymentId);
        assertEquals(HttpStatus.NOT_FOUND, statusRes.getStatusCode());
        assertEquals("NOT_FOUND", statusRes.getBody().status());
        assertFalse(statusRes.getBody().found());
    }

    @Test
    @DisplayName("26. Controller concurrency: Simultaneous API controller calls for settlement and revocation serialize correctly without lock leak")
    void controllerConcurrency_simultaneousSettlementAndRevocation_serializedCleanly() throws Exception {
        DeviceAuthorizationRequest authReq = new DeviceAuthorizationRequest(
                aliceDeviceId,
                "alice",
                TEST_ADMIN_TOKEN,
                DeviceAuthorizationStatus.AUTHORIZED.name(),
                new BigDecimal("500.00"),
                Instant.now().plus(30, ChronoUnit.DAYS),
                null,
                null
        );
        apiController.authorizeDevice(authReq);

        SignedPaymentRequest payReq = createSignedRequest(
                aliceDeviceId,
                aliceDeviceKeyPair,
                "alice",
                "bob",
                new BigDecimal("25.00")
        );
        DeviceAuthorizationRequest revokeReq = new DeviceAuthorizationRequest(
                aliceDeviceId,
                "alice",
                TEST_ADMIN_TOKEN
        );

        CyclicBarrier barrier = new CyclicBarrier(2);
        ExecutorService executor = Executors.newFixedThreadPool(2);

        AtomicBoolean settlementSucceeded = new AtomicBoolean(false);
        AtomicBoolean settlementRejectedRevoked = new AtomicBoolean(false);
        AtomicBoolean revocationSucceeded = new AtomicBoolean(false);

        Future<?> f1 = executor.submit(() -> {
            barrier.await(5, TimeUnit.SECONDS);
            try {
                ResponseEntity<MeshPaymentResult> res = apiController.submitSignedMeshPayment(payReq);
                if (res.getStatusCode() == HttpStatus.OK && "SETTLED".equalsIgnoreCase(res.getBody().status())) {
                    settlementSucceeded.set(true);
                }
            } catch (IllegalStateException e) {
                if (e.getMessage().contains("REVOKED")) {
                    settlementRejectedRevoked.set(true);
                } else {
                    throw e;
                }
            }
            return null;
        });

        Future<?> f2 = executor.submit(() -> {
            barrier.await(5, TimeUnit.SECONDS);
            ResponseEntity<DeviceAuthorizationResponse> res = apiController.revokeDevice(revokeReq, TEST_ADMIN_TOKEN, null);
            if (res.getStatusCode() == HttpStatus.OK && "REVOKED".equalsIgnoreCase(res.getBody().status())) {
                revocationSucceeded.set(true);
            }
            return null;
        });

        f1.get(5, TimeUnit.SECONDS);
        f2.get(5, TimeUnit.SECONDS);
        executor.shutdown();

        // Exactly one settlement outcome must have occurred
        assertTrue(settlementSucceeded.get() ^ settlementRejectedRevoked.get(),
                "Settlement must either cleanly succeed before revocation or be rejected fail-closed after revocation");
        assertTrue(revocationSucceeded.get(), "Revocation must always succeed");

        // Verify zero lingering locks
        var rwLock = deviceAuthorizationRegistry.getAuthorizationLock(aliceDeviceId, "alice");
        assertEquals(0, rwLock.getReadLockCount(), "No read locks should remain held");
        assertFalse(rwLock.isWriteLocked(), "No write lock should remain held");
    }

    @Test
    @DisplayName("27. Exception handling: Exceptions before and after synchronization registration cleanly release locks without leakage")
    void exceptionHandling_beforeAndAfterSynchronization_releasesLocks() throws Exception {
        DeviceAuthorizationRequest authReq = new DeviceAuthorizationRequest(
                aliceDeviceId,
                "alice",
                TEST_ADMIN_TOKEN,
                DeviceAuthorizationStatus.AUTHORIZED.name(),
                new BigDecimal("100.00"),
                Instant.now().plus(30, ChronoUnit.DAYS),
                null,
                null
        );
        apiController.authorizeDevice(authReq);

        var rwLock = deviceAuthorizationRegistry.getAuthorizationLock(aliceDeviceId, "alice");

        // Case A: Exception before synchronization (spending limit exceeded during verification)
        SignedPaymentRequest overLimitReq = createSignedRequest(
                aliceDeviceId,
                aliceDeviceKeyPair,
                "alice",
                "bob",
                new BigDecimal("150.00") // Exceeds 100.00
        );
        assertThrows(IllegalStateException.class, () ->
                apiController.submitSignedMeshPayment(overLimitReq)
        );
        assertEquals(0, rwLock.getReadLockCount(), "Read lock must be released immediately when verification fails");
        assertFalse(rwLock.isWriteLocked());

        // Case B: Exception after synchronization in transactional block
        org.springframework.transaction.support.TransactionTemplate txTemplate =
                new org.springframework.transaction.support.TransactionTemplate(transactionManager);

        assertThrows(RuntimeException.class, () ->
                txTemplate.execute(status -> {
                    try {
                        return deviceAuthorizationRegistry.executeWithAuthorization(
                                aliceDeviceId,
                                "alice",
                                new BigDecimal("10.00"),
                                aliceDeviceKeyPair.getPublic(),
                                () -> {
                                    // Simulated failure after lock acquired and synchronization registered
                                    throw new RuntimeException("Simulated mid-transaction failure");
                                }
                        );
                    } catch (RuntimeException e) {
                        throw e;
                    } catch (Exception e) {
                        throw new RuntimeException(e);
                    }
                })
        );
        assertEquals(0, rwLock.getReadLockCount(), "Read lock must be released when transaction rolls back");
        assertFalse(rwLock.isWriteLocked());
    }

    @Test
    @DisplayName("28. Lock lifecycle: executeWithAuthorization holds read lock across transaction execution and releases after commit")
    void lockLifecycle_readLockHeldDuringTx_releasedAfterCommit() {
        DeviceAuthorizationRequest authReq = new DeviceAuthorizationRequest(
                aliceDeviceId,
                "alice",
                TEST_ADMIN_TOKEN,
                DeviceAuthorizationStatus.AUTHORIZED.name(),
                new BigDecimal("500.00"),
                Instant.now().plus(30, ChronoUnit.DAYS),
                null,
                null
        );
        apiController.authorizeDevice(authReq);

        var rwLock = deviceAuthorizationRegistry.getAuthorizationLock(aliceDeviceId, "alice");
        assertEquals(0, rwLock.getReadLockCount());

        org.springframework.transaction.support.TransactionTemplate txTemplate =
                new org.springframework.transaction.support.TransactionTemplate(transactionManager);

        AtomicInteger lockCountInsideTx = new AtomicInteger(0);

        txTemplate.execute(status -> {
            try {
                return deviceAuthorizationRegistry.executeWithAuthorization(
                        aliceDeviceId,
                        "alice",
                        new BigDecimal("20.00"),
                        aliceDeviceKeyPair.getPublic(),
                        () -> {
                            // Lock must be held right now
                            lockCountInsideTx.set(rwLock.getReadLockCount());
                            return "OK";
                        }
                );
            } catch (Exception e) {
                throw new RuntimeException(e);
            }
        });

        // 1. Lock was strictly held during execution
        assertTrue(lockCountInsideTx.get() > 0, "Read lock must be held during transaction execution");

        // 2. Lock is strictly released after transaction completes
        assertEquals(0, rwLock.getReadLockCount(), "Read lock must be released after transaction commit");
        assertFalse(rwLock.isWriteLocked(), "Write lock must not be held");
    }

    @Test
    @DisplayName("29. Lock lifecycle: revokeDevice holds write lock across transaction execution and releases after commit")
    void lockLifecycle_writeLockHeldDuringRevoke_releasedAfterCommit() {
        DeviceAuthorizationRequest authReq = new DeviceAuthorizationRequest(
                aliceDeviceId,
                "alice",
                TEST_ADMIN_TOKEN,
                DeviceAuthorizationStatus.AUTHORIZED.name(),
                new BigDecimal("500.00"),
                Instant.now().plus(30, ChronoUnit.DAYS),
                null,
                null
        );
        apiController.authorizeDevice(authReq);

        var rwLock = deviceAuthorizationRegistry.getAuthorizationLock(aliceDeviceId, "alice");
        assertFalse(rwLock.isWriteLocked());

        org.springframework.transaction.support.TransactionTemplate txTemplate =
                new org.springframework.transaction.support.TransactionTemplate(transactionManager);

        AtomicBoolean writeLockedDuringTx = new AtomicBoolean(false);

        txTemplate.execute(status -> {
            deviceAuthorizationRegistry.revokeDevice(aliceDeviceId, "alice");
            // The write lock is held until the transaction commits in afterCompletion
            writeLockedDuringTx.set(rwLock.isWriteLocked());
            return "OK";
        });

        // 1. Write lock was strictly held before commit
        assertTrue(writeLockedDuringTx.get(), "Write lock must be held during transaction before commit");

        // 2. Write lock is strictly released after transaction commit
        assertFalse(rwLock.isWriteLocked(), "Write lock must be released after transaction commit");
        assertEquals(0, rwLock.getReadLockCount(), "No read locks should remain");
    }
}
