package com.demo.upimesh;

import com.demo.upimesh.model.Account;
import com.demo.upimesh.model.AccountOwnerConsentRequest;
import com.demo.upimesh.model.AccountOwnerKeyRepository;
import com.demo.upimesh.model.AccountRepository;
import com.demo.upimesh.model.ConsumedConsentRepository;
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
import org.springframework.test.annotation.DirtiesContext;

import java.math.BigDecimal;
import java.security.KeyPair;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Base64;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Stage 8.8 Owner-Key Enrollment and Trust-Boundary Verification Test Suite.
 * <p>
 * Specifically verifies:
 * 1. Ordinary public network callers CANNOT claim accounts (first-enrollment takeover closed).
 * 2. Production mode configuration completely disables key enrollment fail-closed.
 * 3. Development provisioning is restricted strictly to authorized test accounts (alice, bob).
 * 4. Infrastructure administrator tokens cannot be misused to enroll owner keys.
 * 5. Controlled development provisioning enables isolated test execution.
 * 6. Key immutability policy is preserved.
 * 7. Consent parameter tampering is rejected fail-closed.
 * 8. Consent replay is rejected fail-closed.
 * 9. Carol remains strictly blocked fail-closed under all circumstances.
 */
@SpringBootTest
@DirtiesContext(classMode = DirtiesContext.ClassMode.BEFORE_EACH_TEST_METHOD)
public class OwnerKeyEnrollmentAuditTest {

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
    private AccountOwnerKeyRepository accountOwnerKeyRepository;

    @Autowired
    private ConsumedConsentRepository consumedConsentRepository;

    @Autowired
    private CryptoService cryptoService;

    private static final String TEST_ADMIN_TOKEN = "audit-stage88-admin-secret-token";
    private static final String TEST_DEV_PROVISIONING_TOKEN = "stage88-test-dev-provisioning-secret-xyz";

    @BeforeEach
    void setUp() throws Exception {
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

        accountRepository.save(new Account("alice", new BigDecimal("5000.00")));
        accountRepository.save(new Account("bob", new BigDecimal("1000.00")));
        accountRepository.save(new Account("carol", new BigDecimal("2000.00")));
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
    @DisplayName("Stage 8.8-1: Ordinary network caller without dev credentials CANNOT claim an account")
    void testOrdinaryNetworkCaller_cannotClaimAccount() throws Exception {
        assertFalse(accountOwnerKeyRegistry.hasKey("bob"));

        KeyPair attackerKeyPair = cryptoService.generateRsaKeyPair();
        String attackerPubB64 = Base64.getEncoder().encodeToString(attackerKeyPair.getPublic().getEncoded());

        // Ordinary caller sends unauthenticated request to /api/owner/keys/register
        ResponseEntity<KeyRegistrationResponse> response = apiController.registerOwnerKey(
                new KeyRegistrationRequest("bob", attackerPubB64)
        );

        // Must be rejected with HTTP 401 Unauthorized
        assertEquals(HttpStatus.UNAUTHORIZED, response.getStatusCode());
        assertEquals("UNAUTHORIZED", response.getBody().status());
        assertTrue(response.getBody().message().contains("Ordinary network callers cannot register owner keys"));

        // Bob's account remains untampered and unowned
        assertFalse(accountOwnerKeyRegistry.hasKey("bob"));
    }

    @Test
    @DisplayName("Stage 8.8-1b: Boolean header alone ('X-Dev-Provisioning: true') is strictly REJECTED")
    void testBooleanHeaderAlone_isRejected() throws Exception {
        assertFalse(accountOwnerKeyRegistry.hasKey("bob"));

        KeyPair attackerKeyPair = cryptoService.generateRsaKeyPair();
        String attackerPubB64 = Base64.getEncoder().encodeToString(attackerKeyPair.getPublic().getEncoded());

        // 1. Passing X-Dev-Provisioning: true without token
        ResponseEntity<KeyRegistrationResponse> resp1 = apiController.registerOwnerKey(
                new KeyRegistrationRequest("bob", attackerPubB64),
                null,
                "true"
        );
        assertEquals(HttpStatus.UNAUTHORIZED, resp1.getStatusCode());
        assertEquals("UNAUTHORIZED", resp1.getBody().status());
        assertTrue(resp1.getBody().message().contains("valid development provisioning token"));
        assertFalse(accountOwnerKeyRegistry.hasKey("bob"));

        // 2. Passing X-Dev-Provisioning: true with empty token
        ResponseEntity<KeyRegistrationResponse> resp2 = apiController.registerOwnerKey(
                new KeyRegistrationRequest("bob", attackerPubB64),
                "",
                "true"
        );
        assertEquals(HttpStatus.UNAUTHORIZED, resp2.getStatusCode());
        assertFalse(accountOwnerKeyRegistry.hasKey("bob"));

        // 3. Passing X-Dev-Provisioning: true with whitespace token
        ResponseEntity<KeyRegistrationResponse> resp3 = apiController.registerOwnerKey(
                new KeyRegistrationRequest("bob", attackerPubB64),
                "   ",
                "true"
        );
        assertEquals(HttpStatus.UNAUTHORIZED, resp3.getStatusCode());
        assertFalse(accountOwnerKeyRegistry.hasKey("bob"));
    }

    @Test
    @DisplayName("Stage 8.8-1c: Missing, blank, and incorrect tokens are strictly REJECTED")
    void testMissingBlankAndIncorrectTokens_areRejected() throws Exception {
        assertFalse(accountOwnerKeyRegistry.hasKey("bob"));

        KeyPair attackerKeyPair = cryptoService.generateRsaKeyPair();
        String attackerPubB64 = Base64.getEncoder().encodeToString(attackerKeyPair.getPublic().getEncoded());

        // 1. Missing token (null)
        ResponseEntity<KeyRegistrationResponse> respNull = apiController.registerOwnerKey(
                new KeyRegistrationRequest("bob", attackerPubB64),
                null
        );
        assertEquals(HttpStatus.UNAUTHORIZED, respNull.getStatusCode());

        // 2. Blank token ("")
        ResponseEntity<KeyRegistrationResponse> respBlank = apiController.registerOwnerKey(
                new KeyRegistrationRequest("bob", attackerPubB64),
                ""
        );
        assertEquals(HttpStatus.UNAUTHORIZED, respBlank.getStatusCode());

        // 3. Whitespace token ("  ")
        ResponseEntity<KeyRegistrationResponse> respSpaces = apiController.registerOwnerKey(
                new KeyRegistrationRequest("bob", attackerPubB64),
                "    "
        );
        assertEquals(HttpStatus.UNAUTHORIZED, respSpaces.getStatusCode());

        // 4. Incorrect secret token
        ResponseEntity<KeyRegistrationResponse> respWrong = apiController.registerOwnerKey(
                new KeyRegistrationRequest("bob", attackerPubB64),
                "wrong-secret-token"
        );
        assertEquals(HttpStatus.UNAUTHORIZED, respWrong.getStatusCode());

        // 5. Insecure legacy default ("dev-test-token") is rejected when secret is configured
        ResponseEntity<KeyRegistrationResponse> respLegacy = apiController.registerOwnerKey(
                new KeyRegistrationRequest("bob", attackerPubB64),
                "dev-test-token"
        );
        assertEquals(HttpStatus.UNAUTHORIZED, respLegacy.getStatusCode());

        assertFalse(accountOwnerKeyRegistry.hasKey("bob"));
    }

    @Test
    @DisplayName("Stage 8.8-1d: Valid token works ONLY when development provisioning is enabled")
    void testValidTokenWorksOnlyWhenDevProvisioningEnabled() throws Exception {
        KeyPair keyPair = cryptoService.generateRsaKeyPair();
        String pubB64 = Base64.getEncoder().encodeToString(keyPair.getPublic().getEncoded());

        // Feature is enabled: valid token succeeds
        assertTrue(apiController.isDevKeyProvisioningEnabled());
        ResponseEntity<KeyRegistrationResponse> respEnabled = apiController.registerOwnerKey(
                new KeyRegistrationRequest("bob", pubB64),
                TEST_DEV_PROVISIONING_TOKEN
        );
        assertEquals(HttpStatus.OK, respEnabled.getStatusCode());
        assertEquals("REGISTERED", respEnabled.getBody().status());
        assertTrue(accountOwnerKeyRegistry.hasKey("bob"));

        // Feature is disabled: valid token is rejected fail-closed with 403 Forbidden
        accountOwnerKeyRegistry.clearForTesting();
        apiController.setDevKeyProvisioningEnabled(false);
        assertFalse(apiController.isDevKeyProvisioningEnabled());

        ResponseEntity<KeyRegistrationResponse> respDisabled = apiController.registerOwnerKey(
                new KeyRegistrationRequest("bob", pubB64),
                TEST_DEV_PROVISIONING_TOKEN
        );
        assertEquals(HttpStatus.FORBIDDEN, respDisabled.getStatusCode());
        assertEquals("FORBIDDEN", respDisabled.getBody().status());
        assertTrue(respDisabled.getBody().message().contains("Public account-owner key enrollment is disabled"));
        assertFalse(accountOwnerKeyRegistry.hasKey("bob"));
    }

    @Test
    @DisplayName("Stage 8.8-1e: Unconfigured server secret token FAILS CLOSED even if client passes token")
    void testUnconfiguredServerToken_failsClosed() throws Exception {
        KeyPair keyPair = cryptoService.generateRsaKeyPair();
        String pubB64 = Base64.getEncoder().encodeToString(keyPair.getPublic().getEncoded());

        // Server has null token configured
        apiController.setConfiguredDevProvisioningToken(null);
        ResponseEntity<KeyRegistrationResponse> respNull = apiController.registerOwnerKey(
                new KeyRegistrationRequest("bob", pubB64),
                TEST_DEV_PROVISIONING_TOKEN
        );
        assertEquals(HttpStatus.UNAUTHORIZED, respNull.getStatusCode());
        assertFalse(accountOwnerKeyRegistry.hasKey("bob"));

        // Server has empty token configured
        apiController.setConfiguredDevProvisioningToken("   ");
        ResponseEntity<KeyRegistrationResponse> respBlank = apiController.registerOwnerKey(
                new KeyRegistrationRequest("bob", pubB64),
                TEST_DEV_PROVISIONING_TOKEN
        );
        assertEquals(HttpStatus.UNAUTHORIZED, respBlank.getStatusCode());
        assertFalse(accountOwnerKeyRegistry.hasKey("bob"));
    }

    @Test
    @DisplayName("Stage 8.8-2: Production mode configuration completely disables owner-key enrollment")
    void testProductionMode_disablesEnrollmentEntirely() throws Exception {
        // Explicitly set production mode: devKeyProvisioningEnabled = false
        apiController.setDevKeyProvisioningEnabled(false);

        KeyPair keyPair = cryptoService.generateRsaKeyPair();
        String pubB64 = Base64.getEncoder().encodeToString(keyPair.getPublic().getEncoded());

        // Even with valid dev provisioning token and boolean header, production mode must reject fail-closed
        ResponseEntity<KeyRegistrationResponse> response = apiController.registerOwnerKey(
                new KeyRegistrationRequest("bob", pubB64),
                TEST_DEV_PROVISIONING_TOKEN,
                "true"
        );

        assertEquals(HttpStatus.FORBIDDEN, response.getStatusCode());
        assertEquals("FORBIDDEN", response.getBody().status());
        assertTrue(response.getBody().message().contains("Public account-owner key enrollment is disabled"));
        assertFalse(accountOwnerKeyRegistry.hasKey("bob"));
    }

    @Test
    @DisplayName("Stage 8.8-3: Development provisioning is restricted strictly to authorized test accounts")
    void testDevProvisioning_restrictedToAuthorizedTestAccounts() throws Exception {
        KeyPair keyPair = cryptoService.generateRsaKeyPair();
        String pubB64 = Base64.getEncoder().encodeToString(keyPair.getPublic().getEncoded());

        // Attempting to provision an unapproved/arbitrary account (e.g. 'charlie') even with dev token
        ResponseEntity<KeyRegistrationResponse> response = apiController.provisionDevOwnerKey(
                new KeyRegistrationRequest("charlie", pubB64)
        );

        assertEquals(HttpStatus.FORBIDDEN, response.getStatusCode());
        assertEquals("FORBIDDEN", response.getBody().status());
        assertTrue(response.getBody().message().contains("restricted to authorized test accounts"));
        assertFalse(accountOwnerKeyRegistry.hasKey("charlie"));
    }

    @Test
    @DisplayName("Stage 8.8-4: Administrator pairing token cannot be misused as owner-key enrollment credential")
    void testAdminToken_cannotEnrollOwnerKey() throws Exception {
        KeyPair keyPair = cryptoService.generateRsaKeyPair();
        String pubB64 = Base64.getEncoder().encodeToString(keyPair.getPublic().getEncoded());

        // Calling with administrator token instead of dev provisioning secret is rejected
        ResponseEntity<KeyRegistrationResponse> response = apiController.registerOwnerKey(
                new KeyRegistrationRequest("bob", pubB64),
                TEST_ADMIN_TOKEN,
                null
        );

        assertEquals(HttpStatus.UNAUTHORIZED, response.getStatusCode());
        assertFalse(accountOwnerKeyRegistry.hasKey("bob"));
    }

    @Test
    @DisplayName("Stage 8.8-5: Controlled dev provisioning succeeds for authorized test account and allows payments")
    void testControlledDevProvisioning_succeedsForAuthorizedTestAccount() throws Exception {
        KeyPair bobOwnerKeyPair = cryptoService.generateRsaKeyPair();
        String bobPubB64 = Base64.getEncoder().encodeToString(bobOwnerKeyPair.getPublic().getEncoded());

        // Provision via controlled dev path for 'bob'
        ResponseEntity<KeyRegistrationResponse> regResp = apiController.provisionDevOwnerKey(
                new KeyRegistrationRequest("bob", bobPubB64)
        );
        assertEquals(HttpStatus.OK, regResp.getStatusCode());
        assertEquals("REGISTERED", regResp.getBody().status());
        assertTrue(accountOwnerKeyRegistry.hasKey("bob"));

        // Register Bob's mobile device
        String bobDeviceId = "bob-phone-01";
        KeyPair bobDeviceKeyPair = cryptoService.generateRsaKeyPair();
        String bobDevPubB64 = Base64.getEncoder().encodeToString(bobDeviceKeyPair.getPublic().getEncoded());
        apiController.registerSenderKey(new KeyRegistrationRequest(bobDeviceId, bobDevPubB64), null, null);
        String bobDevFingerprint = DeviceAuthorizationRegistry.computeFingerprint(bobDeviceKeyPair.getPublic());

        // Authorize device via valid owner consent
        String consentId = UUID.randomUUID().toString();
        AccountOwnerConsentRequest consent = createSignedConsent(
                consentId,
                "bob",
                bobDeviceId,
                bobDevFingerprint,
                new BigDecimal("500.00"),
                Instant.now().plus(7, ChronoUnit.DAYS),
                bobOwnerKeyPair
        );

        ResponseEntity<DeviceAuthorizationResponse> authResp = apiController.authorizeDeviceWithConsent(consent);
        assertEquals(HttpStatus.OK, authResp.getStatusCode());
        assertEquals("AUTHORIZED", authResp.getBody().status());

        // Settle a payment under this authorized consent
        PaymentInstruction instruction = new PaymentInstruction(
                "bob-pay-" + UUID.randomUUID(),
                "bob",
                "alice",
                new BigDecimal("100.00"),
                Instant.now(),
                UUID.randomUUID().toString()
        );
        String sig = cryptoService.signBase64(instruction.toCanonicalBytes(), bobDeviceKeyPair.getPrivate());
        SignedPaymentRequest payReq = new SignedPaymentRequest(bobDeviceId, instruction.withSignature(sig));

        ResponseEntity<MeshPaymentResult> payResp = apiController.submitSignedMeshPayment(payReq);
        assertEquals(HttpStatus.OK, payResp.getStatusCode());
        assertTrue(payResp.getBody().success());
        assertEquals("SETTLED", payResp.getBody().status());

        Account bob = accountRepository.findById("bob").orElseThrow();
        assertEquals(new BigDecimal("900.00"), bob.getBalance());
    }

    @Test
    @DisplayName("Stage 8.8-6: Key replacement remains strictly blocked under immutability policy")
    void testKeyReplacement_remainsStrictlyBlocked() throws Exception {
        KeyPair keyPair1 = cryptoService.generateRsaKeyPair();
        String key1B64 = Base64.getEncoder().encodeToString(keyPair1.getPublic().getEncoded());
        apiController.provisionDevOwnerKey(new KeyRegistrationRequest("alice", key1B64));

        // Idempotent re-registration
        ResponseEntity<KeyRegistrationResponse> idempResp = apiController.provisionDevOwnerKey(
                new KeyRegistrationRequest("alice", key1B64)
        );
        assertEquals(HttpStatus.OK, idempResp.getStatusCode());
        assertEquals("ALREADY_REGISTERED", idempResp.getBody().status());

        // Different key is rejected
        KeyPair keyPair2 = cryptoService.generateRsaKeyPair();
        String key2B64 = Base64.getEncoder().encodeToString(keyPair2.getPublic().getEncoded());
        assertThrows(IllegalStateException.class, () -> {
            apiController.provisionDevOwnerKey(new KeyRegistrationRequest("alice", key2B64));
        });
    }

    @Test
    @DisplayName("Stage 8.8-7: Consent parameter tampering is rejected fail-closed")
    void testConsentTampering_isRejectedFailClosed() throws Exception {
        KeyPair aliceOwnerKey = cryptoService.generateRsaKeyPair();
        apiController.provisionDevOwnerKey(new KeyRegistrationRequest("alice", Base64.getEncoder().encodeToString(aliceOwnerKey.getPublic().getEncoded())));

        String devId = "alice-dev-" + UUID.randomUUID();
        KeyPair devKey = cryptoService.generateRsaKeyPair();
        apiController.registerSenderKey(new KeyRegistrationRequest(devId, Base64.getEncoder().encodeToString(devKey.getPublic().getEncoded())), null, null);
        String devFp = DeviceAuthorizationRegistry.computeFingerprint(devKey.getPublic());

        Instant expiry = Instant.now().plus(7, ChronoUnit.DAYS);
        BigDecimal limit = new BigDecimal("100.00");
        String consentId = UUID.randomUUID().toString();

        AccountOwnerConsentRequest valid = createSignedConsent(consentId, "alice", devId, devFp, limit, expiry, aliceOwnerKey);

        // 1. Tamper limit
        AccountOwnerConsentRequest tamperedLimit = new AccountOwnerConsentRequest(
                valid.consentId(), valid.accountId(), valid.deviceId(), valid.deviceKeyFingerprint(),
                new BigDecimal("1000.00"), valid.expiresAt(), valid.ownerSignature()
        );
        assertEquals(HttpStatus.FORBIDDEN, apiController.authorizeDeviceWithConsent(tamperedLimit).getStatusCode());

        // 2. Tamper account
        AccountOwnerConsentRequest tamperedAccount = new AccountOwnerConsentRequest(
                valid.consentId(), "bob", valid.deviceId(), valid.deviceKeyFingerprint(),
                valid.spendingLimit(), valid.expiresAt(), valid.ownerSignature()
        );
        assertEquals(HttpStatus.FORBIDDEN, apiController.authorizeDeviceWithConsent(tamperedAccount).getStatusCode());

        // 3. Tamper expiry
        AccountOwnerConsentRequest tamperedExpiry = new AccountOwnerConsentRequest(
                valid.consentId(), valid.accountId(), valid.deviceId(), valid.deviceKeyFingerprint(),
                valid.spendingLimit(), expiry.plus(365, ChronoUnit.DAYS), valid.ownerSignature()
        );
        assertEquals(HttpStatus.FORBIDDEN, apiController.authorizeDeviceWithConsent(tamperedExpiry).getStatusCode());
    }

    @Test
    @DisplayName("Stage 8.8-8: Consent replay is rejected fail-closed")
    void testConsentReplay_isRejectedFailClosed() throws Exception {
        KeyPair aliceOwnerKey = cryptoService.generateRsaKeyPair();
        apiController.provisionDevOwnerKey(new KeyRegistrationRequest("alice", Base64.getEncoder().encodeToString(aliceOwnerKey.getPublic().getEncoded())));

        String devId = "alice-dev-" + UUID.randomUUID();
        KeyPair devKey = cryptoService.generateRsaKeyPair();
        apiController.registerSenderKey(new KeyRegistrationRequest(devId, Base64.getEncoder().encodeToString(devKey.getPublic().getEncoded())), null, null);
        String devFp = DeviceAuthorizationRegistry.computeFingerprint(devKey.getPublic());

        String consentId = UUID.randomUUID().toString();
        AccountOwnerConsentRequest consent = createSignedConsent(
                consentId, "alice", devId, devFp, new BigDecimal("200.00"), Instant.now().plus(7, ChronoUnit.DAYS), aliceOwnerKey
        );

        assertEquals(HttpStatus.OK, apiController.authorizeDeviceWithConsent(consent).getStatusCode());

        // Replay of exact same consentId is rejected
        ResponseEntity<DeviceAuthorizationResponse> resp2 = apiController.authorizeDeviceWithConsent(consent);
        assertEquals(HttpStatus.FORBIDDEN, resp2.getStatusCode());
        assertTrue(resp2.getBody().message().contains("replay attack detected"));
    }

    @Test
    @DisplayName("Stage 8.8-9: Carol remains strictly fail-closed across all paths")
    void testCarolRemainsStrictlyFailClosed() throws Exception {
        KeyPair carolKey = cryptoService.generateRsaKeyPair();
        String carolPubB64 = Base64.getEncoder().encodeToString(carolKey.getPublic().getEncoded());

        // 1. Owner key registration for Carol is blocked even with dev headers
        ResponseEntity<KeyRegistrationResponse> regResp = apiController.provisionDevOwnerKey(
                new KeyRegistrationRequest("carol", carolPubB64)
        );
        assertEquals(HttpStatus.FORBIDDEN, regResp.getStatusCode());
        assertFalse(accountOwnerKeyRegistry.hasKey("carol"));

        // 2. Admin pairing for Carol is blocked
        DeviceAuthorizationRequest pairReq = new DeviceAuthorizationRequest("carol-phone", "carol");
        assertEquals(HttpStatus.FORBIDDEN, apiController.authorizeDevice(pairReq, TEST_ADMIN_TOKEN, null).getStatusCode());

        // 3. Consent authorization for Carol is blocked
        AccountOwnerConsentRequest consent = createSignedConsent(
                UUID.randomUUID().toString(), "carol", "carol-phone", "abcdef123456",
                new BigDecimal("100.00"), Instant.now().plus(1, ChronoUnit.DAYS), carolKey
        );
        assertEquals(HttpStatus.FORBIDDEN, apiController.authorizeDeviceWithConsent(consent).getStatusCode());

        // 4. Query & verification fail-closed
        assertFalse(deviceAuthorizationRegistry.isDeviceAuthorized("carol-phone", "carol"));
        assertThrows(IllegalArgumentException.class, () -> {
            deviceAuthorizationRegistry.verifyDebitAuthorization("carol-phone", "carol", new BigDecimal("10.00"), carolKey.getPublic());
        });
    }
}
