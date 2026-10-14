package com.demo.upimesh;

import com.demo.upimesh.model.Account;
import com.demo.upimesh.model.AccountOwnerConsentRequest;
import com.demo.upimesh.model.AccountOwnerKeyRepository;
import com.demo.upimesh.model.AccountRepository;
import com.demo.upimesh.model.ConsumedConsentRepository;
import com.demo.upimesh.model.DeviceAccountAuthorization;
import com.demo.upimesh.model.DeviceAuthorizationRequest;
import com.demo.upimesh.model.DeviceAuthorizationResponse;
import com.demo.upimesh.model.KeyRegistrationRequest;
import com.demo.upimesh.model.KeyRegistrationResponse;
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
import org.springframework.mock.env.MockEnvironment;
import org.springframework.test.annotation.DirtiesContext;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;

import java.math.BigDecimal;
import java.security.KeyPair;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Base64;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Stage 8.10 API Access-Control and Authorization Audit Test Suite.
 * <p>
 * Specifically verifies:
 * 1. Cross-account debit prevention: Device authorized for Account A cannot debit Account B.
 * 2. Spending limit enforcement: Debits exceeding authorized spending limits are rejected.
 * 3. Temporal expiry enforcement: Debits from expired authorizations are rejected.
 * 4. Revocation enforcement: Debits from revoked authorizations are rejected.
 * 5. Key fingerprint binding: Key substitution without authorization update is rejected.
 * 6. Privilege escalation: Missing or wrong admin token cannot authorize or revoke devices.
 * 7. Information disclosure: Device authorization records require administrative authentication.
 * 8. Production environment protection: Direct unauthenticated transfer endpoints fail closed in production.
 * 9. Account-owner consent forgery: Non-owner keys cannot forge consent for an account.
 * 10. Consent replay attack: Single-use consent cannot be consumed multiple times.
 * 11. Carol fail-closed: Carol cannot be enrolled, paired, or debited under any circumstance.
 */
@SpringBootTest
@DirtiesContext(classMode = DirtiesContext.ClassMode.BEFORE_EACH_TEST_METHOD)
public class ApiAccessControlAuditTest {

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
    private AccountOwnerKeyRegistry accountOwnerKeyRegistry;

    @Autowired
    private ConsumedConsentRepository consumedConsentRepository;

    @Autowired
    private CryptoService cryptoService;

    @Autowired
    private org.springframework.core.env.Environment originalEnvironment;

    @Autowired
    private WebApplicationContext webApplicationContext;

    private MockMvc mockMvc;

    private static final String TEST_ADMIN_TOKEN = "audit-stage810-admin-token";
    private static final String TEST_DEV_PROVISIONING_TOKEN = "audit-stage810-dev-token";

    private KeyPair aliceOwnerKeyPair;
    private KeyPair aliceDeviceKeyPair;
    private String aliceDeviceId;
    private String aliceDeviceFingerprint;

    @BeforeEach
    void setUp() throws Exception {
        mockMvc = MockMvcBuilders.webAppContextSetup(webApplicationContext).build();
        accountRepository.deleteAll();
        transactionRepository.deleteAll();
        if (processedPacketRepository != null) {
            processedPacketRepository.deleteAll();
        }
        senderKeyRegistry.clearForTesting();
        deviceAuthorizationRegistry.clearForTesting();
        accountOwnerKeyRegistry.clearForTesting();
        if (consumedConsentRepository != null) {
            consumedConsentRepository.deleteAll();
        }

        apiController.setConfiguredAdminToken(TEST_ADMIN_TOKEN);
        apiController.setDevKeyProvisioningEnabled(true);
        apiController.setConfiguredDevProvisioningToken(TEST_DEV_PROVISIONING_TOKEN);
        apiController.setEnvironment(originalEnvironment);

        accountRepository.save(new Account("alice", new BigDecimal("5000.00")));
        accountRepository.save(new Account("bob", new BigDecimal("1000.00")));
        accountRepository.save(new Account("carol", new BigDecimal("2000.00")));

        // Provision Alice owner key
        aliceOwnerKeyPair = cryptoService.generateRsaKeyPair();
        String aliceOwnerPubB64 = Base64.getEncoder().encodeToString(aliceOwnerKeyPair.getPublic().getEncoded());
        apiController.provisionDevOwnerKey(new KeyRegistrationRequest("alice", aliceOwnerPubB64));

        // Register Alice mobile device
        aliceDeviceId = "alice-phone-" + UUID.randomUUID();
        aliceDeviceKeyPair = cryptoService.generateRsaKeyPair();
        String devPubB64 = Base64.getEncoder().encodeToString(aliceDeviceKeyPair.getPublic().getEncoded());
        apiController.registerSenderKey(new KeyRegistrationRequest(aliceDeviceId, devPubB64), null, null);
        aliceDeviceFingerprint = DeviceAuthorizationRegistry.computeFingerprint(aliceDeviceKeyPair.getPublic());
    }

    @org.junit.jupiter.api.AfterEach
    void tearDown() {
        apiController.setEnvironment(originalEnvironment);
    }

    private AccountOwnerConsentRequest createSignedConsent(
            String consentId,
            String accountId,
            String deviceId,
            String fingerprint,
            BigDecimal limit,
            Instant expiry,
            KeyPair signingKey
    ) throws Exception {
        AccountOwnerConsentRequest unsigned = new AccountOwnerConsentRequest(
                consentId,
                accountId,
                deviceId,
                fingerprint,
                limit,
                expiry,
                "UNSIGNED"
        );
        String sigB64 = cryptoService.signBase64(unsigned.toCanonicalBytes(), signingKey.getPrivate());
        return new AccountOwnerConsentRequest(
                consentId,
                accountId,
                deviceId,
                fingerprint,
                limit,
                expiry,
                sigB64
        );
    }

    @Test
    @DisplayName("1. Cross-account access: Device authorized for Alice CANNOT debit Bob")
    void testCrossAccountDebit_isRejectedFailClosed() throws Exception {
        // Authorize device for Alice
        AccountOwnerConsentRequest consent = createSignedConsent(
                UUID.randomUUID().toString(), "alice", aliceDeviceId, aliceDeviceFingerprint,
                new BigDecimal("500.00"), Instant.now().plus(7, ChronoUnit.DAYS), aliceOwnerKeyPair
        );
        apiController.authorizeDeviceWithConsent(consent);
        assertTrue(deviceAuthorizationRegistry.isDeviceAuthorized(aliceDeviceId, "alice"));
        assertFalse(deviceAuthorizationRegistry.isDeviceAuthorized(aliceDeviceId, "bob"));

        // Device constructs and signs payment claiming fromAccount = "bob"
        PaymentInstruction crossAccountPay = new PaymentInstruction(
                "cross-pay-" + UUID.randomUUID(),
                "bob", // Attacker attempts to debit Bob using Alice's device
                "carol",
                new BigDecimal("100.00"),
                Instant.now(),
                UUID.randomUUID().toString()
        );
        String sig = cryptoService.signBase64(crossAccountPay.toCanonicalBytes(), aliceDeviceKeyPair.getPrivate());
        SignedPaymentRequest signedReq = new SignedPaymentRequest(aliceDeviceId, crossAccountPay.withSignature(sig));

        // Must throw IllegalArgumentException (device not authorized for bob)
        assertThrows(IllegalArgumentException.class, () -> {
            apiController.submitSignedMeshPayment(signedReq);
        });

        // Balances remain untampered
        assertEquals(new BigDecimal("1000.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(new BigDecimal("5000.00"), accountRepository.findById("alice").orElseThrow().getBalance());
    }

    @Test
    @DisplayName("2. Spending limit enforcement: Payment exceeding authorized limit is rejected")
    void testSpendingLimitEnforcement_exceedingLimitRejected() throws Exception {
        // Authorize Alice device with spending limit of 100.00
        BigDecimal limit = new BigDecimal("100.00");
        AccountOwnerConsentRequest consent = createSignedConsent(
                UUID.randomUUID().toString(), "alice", aliceDeviceId, aliceDeviceFingerprint,
                limit, Instant.now().plus(7, ChronoUnit.DAYS), aliceOwnerKeyPair
        );
        apiController.authorizeDeviceWithConsent(consent);

        // Attempt payment of 100.01 (exceeds limit)
        PaymentInstruction overLimitPay = new PaymentInstruction(
                "overlimit-pay-" + UUID.randomUUID(),
                "alice",
                "bob",
                new BigDecimal("100.01"),
                Instant.now(),
                UUID.randomUUID().toString()
        );
        String sig = cryptoService.signBase64(overLimitPay.toCanonicalBytes(), aliceDeviceKeyPair.getPrivate());
        SignedPaymentRequest signedReq = new SignedPaymentRequest(aliceDeviceId, overLimitPay.withSignature(sig));

        assertThrows(IllegalStateException.class, () -> {
            apiController.submitSignedMeshPayment(signedReq);
        });

        assertEquals(new BigDecimal("5000.00"), accountRepository.findById("alice").orElseThrow().getBalance());
    }

    @Test
    @DisplayName("3. Temporal expiry enforcement: Payment with expired authorization is rejected")
    void testTemporalExpiry_expiredAuthorizationRejected() throws Exception {
        // Authorize with an expiry in the past (via admin pairing simulation for expired state)
        deviceAuthorizationRegistry.authorizeDevice(
                aliceDeviceId, "alice",
                com.demo.upimesh.model.DeviceAuthorizationStatus.AUTHORIZED,
                aliceDeviceFingerprint,
                new BigDecimal("500.00"),
                Instant.now().minus(1, ChronoUnit.SECONDS)
        );

        PaymentInstruction pay = new PaymentInstruction(
                "expired-pay-" + UUID.randomUUID(),
                "alice",
                "bob",
                new BigDecimal("50.00"),
                Instant.now(),
                UUID.randomUUID().toString()
        );
        String sig = cryptoService.signBase64(pay.toCanonicalBytes(), aliceDeviceKeyPair.getPrivate());
        SignedPaymentRequest signedReq = new SignedPaymentRequest(aliceDeviceId, pay.withSignature(sig));

        assertThrows(IllegalStateException.class, () -> {
            apiController.submitSignedMeshPayment(signedReq);
        });

        assertEquals(new BigDecimal("5000.00"), accountRepository.findById("alice").orElseThrow().getBalance());
    }

    @Test
    @DisplayName("4. Revocation enforcement: Payment with revoked authorization is rejected")
    void testRevocationEnforcement_revokedDeviceBlocked() throws Exception {
        AccountOwnerConsentRequest consent = createSignedConsent(
                UUID.randomUUID().toString(), "alice", aliceDeviceId, aliceDeviceFingerprint,
                new BigDecimal("500.00"), Instant.now().plus(7, ChronoUnit.DAYS), aliceOwnerKeyPair
        );
        apiController.authorizeDeviceWithConsent(consent);

        // Revoke authorization
        DeviceAuthorizationRequest revokeReq = new DeviceAuthorizationRequest(aliceDeviceId, "alice");
        apiController.revokeDevice(revokeReq, TEST_ADMIN_TOKEN, null);

        // Attempt payment after revocation
        PaymentInstruction pay = new PaymentInstruction(
                "revoked-pay-" + UUID.randomUUID(),
                "alice",
                "bob",
                new BigDecimal("50.00"),
                Instant.now(),
                UUID.randomUUID().toString()
        );
        String sig = cryptoService.signBase64(pay.toCanonicalBytes(), aliceDeviceKeyPair.getPrivate());
        SignedPaymentRequest signedReq = new SignedPaymentRequest(aliceDeviceId, pay.withSignature(sig));

        assertThrows(IllegalStateException.class, () -> {
            apiController.submitSignedMeshPayment(signedReq);
        });

        assertEquals(new BigDecimal("5000.00"), accountRepository.findById("alice").orElseThrow().getBalance());
    }

    @Test
    @DisplayName("5. Key fingerprint binding: Signing with unregistered or substituted key is rejected")
    void testKeyFingerprintBinding_substitutedKeyRejected() throws Exception {
        AccountOwnerConsentRequest consent = createSignedConsent(
                UUID.randomUUID().toString(), "alice", aliceDeviceId, aliceDeviceFingerprint,
                new BigDecimal("500.00"), Instant.now().plus(7, ChronoUnit.DAYS), aliceOwnerKeyPair
        );
        apiController.authorizeDeviceWithConsent(consent);

        // Generate an attacker keypair (different key)
        KeyPair rogueKey = cryptoService.generateRsaKeyPair();

        PaymentInstruction pay = new PaymentInstruction(
                "rogue-key-pay-" + UUID.randomUUID(),
                "alice",
                "bob",
                new BigDecimal("50.00"),
                Instant.now(),
                UUID.randomUUID().toString()
        );
        // Signed with rogue key, but registered key in SenderKeyRegistry is aliceDeviceKeyPair
        String sig = cryptoService.signBase64(pay.toCanonicalBytes(), rogueKey.getPrivate());
        SignedPaymentRequest signedReq = new SignedPaymentRequest(aliceDeviceId, pay.withSignature(sig));

        // Signature verification against registered key fails
        assertThrows(IllegalArgumentException.class, () -> {
            apiController.submitSignedMeshPayment(signedReq);
        });

        assertEquals(new BigDecimal("5000.00"), accountRepository.findById("alice").orElseThrow().getBalance());
    }

    @Test
    @DisplayName("6. Privilege escalation: Unauthorized callers CANNOT authorize or revoke devices")
    void testPrivilegeEscalation_unauthorizedAdminCallsRejected() throws Exception {
        DeviceAuthorizationRequest pairReq = new DeviceAuthorizationRequest(aliceDeviceId, "alice");

        // 1. Missing token
        ResponseEntity<DeviceAuthorizationResponse> r1 = apiController.authorizeDevice(pairReq, null, null);
        assertEquals(HttpStatus.UNAUTHORIZED, r1.getStatusCode());

        // 2. Invalid token
        ResponseEntity<DeviceAuthorizationResponse> r2 = apiController.authorizeDevice(pairReq, "wrong-token", null);
        assertEquals(HttpStatus.UNAUTHORIZED, r2.getStatusCode());

        // 3. Dev provisioning token instead of admin token
        ResponseEntity<DeviceAuthorizationResponse> r3 = apiController.authorizeDevice(pairReq, TEST_DEV_PROVISIONING_TOKEN, null);
        assertEquals(HttpStatus.UNAUTHORIZED, r3.getStatusCode());

        // 4. Missing token on revoke
        ResponseEntity<DeviceAuthorizationResponse> r4 = apiController.revokeDevice(pairReq, null, null);
        assertEquals(HttpStatus.UNAUTHORIZED, r4.getStatusCode());
    }

    @Test
    @DisplayName("7. Information disclosure: Querying authorization details requires admin credentials")
    void testInformationDisclosure_deviceAuthQueryProtected() throws Exception {
        // Querying authorization details without admin credentials returns 401
        ResponseEntity<DeviceAuthorizationResponse> unauthResp = apiController.getDeviceAccountAuthorization(
                aliceDeviceId, "alice", null, null
        );
        assertEquals(HttpStatus.UNAUTHORIZED, unauthResp.getStatusCode());

        // Querying with wrong token returns 401
        ResponseEntity<DeviceAuthorizationResponse> wrongResp = apiController.getDeviceAccountAuthorization(
                aliceDeviceId, "alice", "wrong-token", null
        );
        assertEquals(HttpStatus.UNAUTHORIZED, wrongResp.getStatusCode());

        // Querying with valid admin token succeeds (200 or 404 depending on existence)
        ResponseEntity<DeviceAuthorizationResponse> authResp = apiController.getDeviceAccountAuthorization(
                aliceDeviceId, "alice", TEST_ADMIN_TOKEN, null
        );
        assertEquals(HttpStatus.NOT_FOUND, authResp.getStatusCode()); // 404 because not yet authorized, but authenticated!
    }

    @Test
    @DisplayName("8. Production guard: Direct unauthenticated transfer endpoints fail closed in production profile")
    void testDirectTransfer_disabledInProductionEnvironment() throws Exception {
        try {
            MockEnvironment prodEnv = new MockEnvironment();
            prodEnv.setActiveProfiles("prod");
            apiController.setEnvironment(prodEnv);

            assertTrue(apiController.isProductionEnvironment());

            // Calling direct unauthenticated transfer in production throws SecurityException
            assertThrows(SecurityException.class, () -> {
                apiController.transfer("alice", "bob", new BigDecimal("50.00"));
            });

            // Calling simulated mesh transfer in production returns 403 FORBIDDEN
            ResponseEntity<MeshPaymentResult> simResp = apiController.simulateMeshTransfer("alice", "bob", new BigDecimal("50.00"), 5);
            assertEquals(HttpStatus.FORBIDDEN, simResp.getStatusCode());
        } finally {
            apiController.setEnvironment(originalEnvironment);
        }
    }

    @Test
    @DisplayName("9. Consent forgery: Consent signed with non-owner key is rejected fail-closed")
    void testConsentForgery_rejectedFailClosed() throws Exception {
        KeyPair attackerKey = cryptoService.generateRsaKeyPair();

        // Attacker creates consent for Alice, signed with attacker's private key
        AccountOwnerConsentRequest forgedConsent = createSignedConsent(
                UUID.randomUUID().toString(), "alice", aliceDeviceId, aliceDeviceFingerprint,
                new BigDecimal("500.00"), Instant.now().plus(7, ChronoUnit.DAYS), attackerKey
        );

        ResponseEntity<DeviceAuthorizationResponse> resp = apiController.authorizeDeviceWithConsent(forgedConsent);
        assertEquals(HttpStatus.FORBIDDEN, resp.getStatusCode());
        assertEquals("FORBIDDEN", resp.getBody().status());
        assertFalse(deviceAuthorizationRegistry.isDeviceAuthorized(aliceDeviceId, "alice"));
    }

    @Test
    @DisplayName("10. Consent replay: Replaying a consumed consent ID is detected and rejected")
    void testConsentReplay_detectedAndRejected() throws Exception {
        String consentId = UUID.randomUUID().toString();
        AccountOwnerConsentRequest validConsent = createSignedConsent(
                consentId, "alice", aliceDeviceId, aliceDeviceFingerprint,
                new BigDecimal("500.00"), Instant.now().plus(7, ChronoUnit.DAYS), aliceOwnerKeyPair
        );

        // First submission succeeds
        ResponseEntity<DeviceAuthorizationResponse> resp1 = apiController.authorizeDeviceWithConsent(validConsent);
        assertEquals(HttpStatus.OK, resp1.getStatusCode());
        assertEquals("AUTHORIZED", resp1.getBody().status());

        // Second submission of identical consentId is rejected as replay attack
        ResponseEntity<DeviceAuthorizationResponse> resp2 = apiController.authorizeDeviceWithConsent(validConsent);
        assertEquals(HttpStatus.FORBIDDEN, resp2.getStatusCode());
        assertEquals("FORBIDDEN", resp2.getBody().status());
        assertTrue(resp2.getBody().message().contains("replay attack detected"));
    }

    @Test
    @DisplayName("11. Carol fail-closed: All operations for Carol remain strictly blocked")
    void testCarol_strictlyBlockedFailClosed() throws Exception {
        KeyPair carolKey = cryptoService.generateRsaKeyPair();
        String carolPubB64 = Base64.getEncoder().encodeToString(carolKey.getPublic().getEncoded());

        // 1. Owner key registration for Carol
        ResponseEntity<KeyRegistrationResponse> r1 = apiController.registerOwnerKey(
                new KeyRegistrationRequest("carol", carolPubB64), TEST_DEV_PROVISIONING_TOKEN
        );
        assertEquals(HttpStatus.FORBIDDEN, r1.getStatusCode());

        // 2. Device pairing for Carol
        apiController.registerSenderKey(new KeyRegistrationRequest("carol-phone", carolPubB64), null, null);
        ResponseEntity<DeviceAuthorizationResponse> r2 = apiController.authorizeDevice(
                new DeviceAuthorizationRequest("carol-phone", "carol"), TEST_ADMIN_TOKEN, null
        );
        assertEquals(HttpStatus.FORBIDDEN, r2.getStatusCode());

        // 3. Consent authorization for Carol
        AccountOwnerConsentRequest consent = createSignedConsent(
                UUID.randomUUID().toString(), "carol", "carol-phone", "any-fp",
                new BigDecimal("100.00"), Instant.now().plus(1, ChronoUnit.DAYS), carolKey
        );
        ResponseEntity<DeviceAuthorizationResponse> r3 = apiController.authorizeDeviceWithConsent(consent);
        assertEquals(HttpStatus.FORBIDDEN, r3.getStatusCode());

        // 4. Registry verification fails closed
        assertThrows(IllegalArgumentException.class, () -> {
            deviceAuthorizationRegistry.verifyDebitAuthorization("carol-phone", "carol", new BigDecimal("10.00"), carolKey.getPublic());
        });
    }

    @Test
    @DisplayName("12. CORS is NOT authentication: Origin headers cannot bypass authentication or access control")
    void testCorsDoesNotAuthenticate_unauthorizedRequestRejected() throws Exception {
        // 1. GET /api/devices/authorizations/{deviceId}/{accountId} with trusted Origin but no credentials -> 401
        mockMvc.perform(get("/api/devices/authorizations/" + aliceDeviceId + "/alice")
                        .header("Origin", "http://localhost:8080"))
                .andExpect(status().isUnauthorized());

        // 2. POST /api/devices/authorize with trusted Origin but invalid credentials -> 401
        mockMvc.perform(post("/api/devices/authorize")
                        .header("Origin", "http://localhost:8080")
                        .contentType("application/json")
                        .content("{\"deviceId\":\"" + aliceDeviceId + "\",\"accountId\":\"alice\"}"))
                .andExpect(status().isUnauthorized());

        // 3. POST /api/devices/revoke with trusted Origin but no credentials -> 401
        mockMvc.perform(post("/api/devices/revoke")
                        .header("Origin", "http://localhost:8080")
                        .contentType("application/json")
                        .content("{\"deviceId\":\"" + aliceDeviceId + "\",\"accountId\":\"alice\"}"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("13. Production environment overrides: Configuration overrides cannot bypass production restrictions")
    void testProductionConfigurationOverride_cannotBypassSecurity() throws Exception {
        try {
            MockEnvironment prodEnv = new MockEnvironment();
            prodEnv.setActiveProfiles("production"); // check alternative profile name
            apiController.setEnvironment(prodEnv);

            assertTrue(apiController.isProductionEnvironment());

            // 1. Attempting to override devKeyProvisioningEnabled in production is forcibly disabled
            apiController.setDevKeyProvisioningEnabled(true);
            assertFalse(apiController.isDevKeyProvisioningEnabled());

            // 2. Registering owner key even with valid dev provisioning token is rejected 403
            KeyPair bobKey = cryptoService.generateRsaKeyPair();
            String bobPubB64 = Base64.getEncoder().encodeToString(bobKey.getPublic().getEncoded());
            ResponseEntity<KeyRegistrationResponse> regResp = apiController.registerOwnerKey(
                    new KeyRegistrationRequest("bob", bobPubB64),
                    TEST_DEV_PROVISIONING_TOKEN
            );
            assertEquals(HttpStatus.FORBIDDEN, regResp.getStatusCode());
            assertFalse(accountOwnerKeyRegistry.hasKey("bob"));

            // 3. Direct unauthenticated transfer throws SecurityException
            assertThrows(SecurityException.class, () -> {
                apiController.transfer("alice", "bob", new BigDecimal("25.00"));
            });

            // 4. Simulated mesh transfer returns 403 Forbidden
            ResponseEntity<MeshPaymentResult> simResp = apiController.simulateMeshTransfer("alice", "bob", new BigDecimal("25.00"), 5);
            assertEquals(HttpStatus.FORBIDDEN, simResp.getStatusCode());
        } finally {
            apiController.setEnvironment(originalEnvironment);
        }
    }

    @Test
    @DisplayName("14. State preservation: Rejected and unauthorized requests leave financial ledger and consent unchanged")
    void testStatePreservation_rejectedRequestsLeaveFinancialStateUntouched() throws Exception {
        BigDecimal initialAlice = accountRepository.findById("alice").orElseThrow().getBalance();
        BigDecimal initialBob = accountRepository.findById("bob").orElseThrow().getBalance();
        BigDecimal initialCarol = accountRepository.findById("carol").orElseThrow().getBalance();
        long initialTxCount = transactionRepository.count();

        // 1. Rejected direct transfer attempt (in production environment)
        try {
            MockEnvironment prodEnv = new MockEnvironment();
            prodEnv.setActiveProfiles("prod");
            apiController.setEnvironment(prodEnv);
            assertThrows(SecurityException.class, () -> apiController.transfer("alice", "bob", new BigDecimal("50.00")));
        } finally {
            apiController.setEnvironment(originalEnvironment);
        }

        // 2. Rejected unauthorized device pairing
        ResponseEntity<DeviceAuthorizationResponse> pairResp = apiController.authorizeDevice(
                new DeviceAuthorizationRequest(aliceDeviceId, "alice"), "invalid-token", null
        );
        assertEquals(HttpStatus.UNAUTHORIZED, pairResp.getStatusCode());

        // 3. Rejected unauthorized device revocation
        ResponseEntity<DeviceAuthorizationResponse> revokeResp = apiController.revokeDevice(
                new DeviceAuthorizationRequest(aliceDeviceId, "alice"), "invalid-token", null
        );
        assertEquals(HttpStatus.UNAUTHORIZED, revokeResp.getStatusCode());

        // 4. Rejected forged owner consent — must NOT be saved in consumedConsentRepository
        KeyPair rogueOwnerKey = cryptoService.generateRsaKeyPair();
        String forgedConsentId = UUID.randomUUID().toString();
        AccountOwnerConsentRequest forgedConsent = createSignedConsent(
                forgedConsentId, "alice", aliceDeviceId, aliceDeviceFingerprint,
                new BigDecimal("500.00"), Instant.now().plus(7, ChronoUnit.DAYS), rogueOwnerKey
        );
        ResponseEntity<DeviceAuthorizationResponse> forgedResp = apiController.authorizeDeviceWithConsent(forgedConsent);
        assertEquals(HttpStatus.FORBIDDEN, forgedResp.getStatusCode());
        assertFalse(consumedConsentRepository.existsById(forgedConsentId), "Forged consent ID must not be consumed");

        // 5. Authorize device legitimately for Alice with 100 limit
        String validConsentId = UUID.randomUUID().toString();
        AccountOwnerConsentRequest validConsent = createSignedConsent(
                validConsentId, "alice", aliceDeviceId, aliceDeviceFingerprint,
                new BigDecimal("100.00"), Instant.now().plus(7, ChronoUnit.DAYS), aliceOwnerKeyPair
        );
        ResponseEntity<DeviceAuthorizationResponse> validResp = apiController.authorizeDeviceWithConsent(validConsent);
        assertEquals(HttpStatus.OK, validResp.getStatusCode());
        assertTrue(consumedConsentRepository.existsById(validConsentId));

        // 6. Over-limit payment rejected
        PaymentInstruction overLimitPay = new PaymentInstruction(
                "rej-overlimit-" + UUID.randomUUID(), "alice", "bob", new BigDecimal("200.00"), Instant.now(), UUID.randomUUID().toString()
        );
        String overLimitSig = cryptoService.signBase64(overLimitPay.toCanonicalBytes(), aliceDeviceKeyPair.getPrivate());
        assertThrows(IllegalStateException.class, () -> {
            apiController.submitSignedMeshPayment(new SignedPaymentRequest(aliceDeviceId, overLimitPay.withSignature(overLimitSig)));
        });

        // 7. Cross-account debit rejected (Alice device attempting to debit Bob)
        PaymentInstruction crossPay = new PaymentInstruction(
                "rej-crosspay-" + UUID.randomUUID(), "bob", "alice", new BigDecimal("50.00"), Instant.now(), UUID.randomUUID().toString()
        );
        String crossSig = cryptoService.signBase64(crossPay.toCanonicalBytes(), aliceDeviceKeyPair.getPrivate());
        assertThrows(IllegalArgumentException.class, () -> {
            apiController.submitSignedMeshPayment(new SignedPaymentRequest(aliceDeviceId, crossPay.withSignature(crossSig)));
        });

        // 8. Blocked account debit rejected (attempting to debit Carol)
        PaymentInstruction carolPay = new PaymentInstruction(
                "rej-carolpay-" + UUID.randomUUID(), "carol", "alice", new BigDecimal("10.00"), Instant.now(), UUID.randomUUID().toString()
        );
        String carolSig = cryptoService.signBase64(carolPay.toCanonicalBytes(), aliceDeviceKeyPair.getPrivate());
        assertThrows(IllegalArgumentException.class, () -> {
            apiController.submitSignedMeshPayment(new SignedPaymentRequest(aliceDeviceId, carolPay.withSignature(carolSig)));
        });

        // Assert all balances and transactions remain strictly identical to initial state
        assertEquals(initialAlice, accountRepository.findById("alice").orElseThrow().getBalance(), "Alice balance must remain unchanged");
        assertEquals(initialBob, accountRepository.findById("bob").orElseThrow().getBalance(), "Bob balance must remain unchanged");
        assertEquals(initialCarol, accountRepository.findById("carol").orElseThrow().getBalance(), "Carol balance must remain unchanged");
        assertEquals(initialTxCount, transactionRepository.count(), "Transaction count must remain 0");
    }
}
