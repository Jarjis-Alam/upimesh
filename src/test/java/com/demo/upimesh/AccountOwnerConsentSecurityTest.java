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
 * Stage 8.6 Security Test Suite: Verifiable Account-Owner Consent and Device-Key Trust.
 * <p>
 * Validates:
 * 1. Cryptographic consent verification binding account ID, device ID, key fingerprint, limit, and expiry.
 * 2. Rejection of forged, invalid, and tampered signatures.
 * 3. Rejection of tampered account ID, device ID, limit, or expiry.
 * 4. Rejection of expired consent tokens and replayed consent tokens.
 * 5. Device key fingerprint mismatch enforcement.
 * 6. Carol fail-closed guard across owner key registration and consent authorization.
 * 7. Key immutability policy (arbitrary owner key replacement forbidden).
 * 8. Revocation enforcement following consent authorization.
 * 9. Spending limit enforcement at settlement boundary.
 */
@SpringBootTest
@DirtiesContext(classMode = DirtiesContext.ClassMode.BEFORE_EACH_TEST_METHOD)
public class AccountOwnerConsentSecurityTest {

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

    private static final String TEST_ADMIN_TOKEN = "stage8-test-admin-secret-token";

    private KeyPair aliceOwnerKeyPair;
    private KeyPair aliceDeviceKeyPair;
    private String aliceDeviceId;
    private String aliceDeviceFingerprint;

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
        apiController.setConfiguredDevProvisioningToken("stage88-test-dev-provisioning-secret-xyz");

        accountRepository.save(new Account("alice", new BigDecimal("5000.00")));
        accountRepository.save(new Account("bob", new BigDecimal("1000.00")));
        accountRepository.save(new Account("carol", new BigDecimal("2000.00")));

        // 1. Generate Alice owner keypair and register via controlled development provisioning path
        aliceOwnerKeyPair = cryptoService.generateRsaKeyPair();
        String ownerPubB64 = Base64.getEncoder().encodeToString(aliceOwnerKeyPair.getPublic().getEncoded());
        ResponseEntity<KeyRegistrationResponse> ownerRegResp = apiController.provisionDevOwnerKey(
                new KeyRegistrationRequest("alice", ownerPubB64)
        );
        assertEquals(HttpStatus.OK, ownerRegResp.getStatusCode());
        assertEquals("REGISTERED", ownerRegResp.getBody().status());

        // 2. Generate Alice device keypair and register in SenderKeyRegistry
        aliceDeviceId = "alice-phone-" + UUID.randomUUID();
        aliceDeviceKeyPair = cryptoService.generateRsaKeyPair();
        String devicePubB64 = Base64.getEncoder().encodeToString(aliceDeviceKeyPair.getPublic().getEncoded());
        ResponseEntity<KeyRegistrationResponse> devRegResp = apiController.registerSenderKey(
                new KeyRegistrationRequest(aliceDeviceId, devicePubB64), null, null
        );
        assertEquals(HttpStatus.OK, devRegResp.getStatusCode());

        aliceDeviceFingerprint = DeviceAuthorizationRegistry.computeFingerprint(aliceDeviceKeyPair.getPublic());
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
    @DisplayName("1. Valid account-owner consent authorizes device and allows payment settlement")
    void validConsent_authorizesDevice_andAllowsPaymentSettlement() throws Exception {
        String consentId = UUID.randomUUID().toString();
        Instant expiry = Instant.now().plus(7, ChronoUnit.DAYS);
        BigDecimal limit = new BigDecimal("500.00");

        AccountOwnerConsentRequest request = createSignedConsent(
                consentId, "alice", aliceDeviceId, aliceDeviceFingerprint, limit, expiry, aliceOwnerKeyPair
        );

        ResponseEntity<DeviceAuthorizationResponse> resp = apiController.authorizeDeviceWithConsent(request);
        assertEquals(HttpStatus.OK, resp.getStatusCode());
        assertNotNull(resp.getBody());
        assertEquals("AUTHORIZED", resp.getBody().status());
        assertEquals(aliceDeviceId, resp.getBody().deviceId());
        assertEquals("alice", resp.getBody().accountId());
        assertEquals(aliceDeviceFingerprint, resp.getBody().keyFingerprint());
        assertEquals(limit, resp.getBody().spendingLimit());

        // Verify device can now settle a payment under this limit
        PaymentInstruction instruction = new PaymentInstruction(
                "consent-pay-" + UUID.randomUUID(),
                "alice",
                "bob",
                new BigDecimal("150.00"),
                Instant.now(),
                UUID.randomUUID().toString()
        );
        String sig = cryptoService.signBase64(instruction.toCanonicalBytes(), aliceDeviceKeyPair.getPrivate());
        SignedPaymentRequest payReq = new SignedPaymentRequest(aliceDeviceId, instruction.withSignature(sig));

        ResponseEntity<MeshPaymentResult> payResp = apiController.submitSignedMeshPayment(payReq);
        assertEquals(HttpStatus.OK, payResp.getStatusCode());
        assertTrue(payResp.getBody().success());
        assertEquals("SETTLED", payResp.getBody().status());
    }

    @Test
    @DisplayName("2. Forged or mathematically invalid owner signature is rejected fail-closed")
    void invalidSignature_rejectedWith403() throws Exception {
        String consentId = UUID.randomUUID().toString();
        Instant expiry = Instant.now().plus(7, ChronoUnit.DAYS);
        BigDecimal limit = new BigDecimal("500.00");

        // Signed by an attacker key instead of Alice's registered owner key
        KeyPair attackerKey = cryptoService.generateRsaKeyPair();
        AccountOwnerConsentRequest request = createSignedConsent(
                consentId, "alice", aliceDeviceId, aliceDeviceFingerprint, limit, expiry, attackerKey
        );

        ResponseEntity<DeviceAuthorizationResponse> resp = apiController.authorizeDeviceWithConsent(request);
        assertEquals(HttpStatus.FORBIDDEN, resp.getStatusCode());
        assertEquals("FORBIDDEN", resp.getBody().status());
        assertTrue(resp.getBody().message().contains("Cryptographic signature verification failed"));

        // Device remains unauthorized
        assertFalse(deviceAuthorizationRegistry.isDeviceAuthorized(aliceDeviceId, "alice"));
    }

    @Test
    @DisplayName("3. Tampered account ID in consent request fails signature verification")
    void tamperedAccountId_rejectedWith403() throws Exception {
        String consentId = UUID.randomUUID().toString();
        Instant expiry = Instant.now().plus(7, ChronoUnit.DAYS);
        BigDecimal limit = new BigDecimal("500.00");

        // Alice signs consent for account 'alice'
        AccountOwnerConsentRequest valid = createSignedConsent(
                consentId, "alice", aliceDeviceId, aliceDeviceFingerprint, limit, expiry, aliceOwnerKeyPair
        );

        // Attacker tampers accountId to 'bob'
        AccountOwnerConsentRequest tampered = new AccountOwnerConsentRequest(
                valid.consentId(),
                "bob",
                valid.deviceId(),
                valid.deviceKeyFingerprint(),
                valid.spendingLimit(),
                valid.expiresAt(),
                valid.ownerSignature()
        );

        ResponseEntity<DeviceAuthorizationResponse> resp = apiController.authorizeDeviceWithConsent(tampered);
        assertEquals(HttpStatus.FORBIDDEN, resp.getStatusCode());
        assertFalse(deviceAuthorizationRegistry.isDeviceAuthorized(aliceDeviceId, "bob"));
    }

    @Test
    @DisplayName("4. Tampered spending limit in consent request fails signature verification")
    void tamperedSpendingLimit_rejectedWith403() throws Exception {
        String consentId = UUID.randomUUID().toString();
        Instant expiry = Instant.now().plus(7, ChronoUnit.DAYS);
        BigDecimal limit = new BigDecimal("100.00");

        AccountOwnerConsentRequest valid = createSignedConsent(
                consentId, "alice", aliceDeviceId, aliceDeviceFingerprint, limit, expiry, aliceOwnerKeyPair
        );

        // Attacker inflates limit to ₹10,000.00
        AccountOwnerConsentRequest tampered = new AccountOwnerConsentRequest(
                valid.consentId(),
                valid.accountId(),
                valid.deviceId(),
                valid.deviceKeyFingerprint(),
                new BigDecimal("10000.00"),
                valid.expiresAt(),
                valid.ownerSignature()
        );

        ResponseEntity<DeviceAuthorizationResponse> resp = apiController.authorizeDeviceWithConsent(tampered);
        assertEquals(HttpStatus.FORBIDDEN, resp.getStatusCode());
        assertFalse(deviceAuthorizationRegistry.isDeviceAuthorized(aliceDeviceId, "alice"));
    }

    @Test
    @DisplayName("5. Tampered expiry date in consent request fails signature verification")
    void tamperedExpiry_rejectedWith403() throws Exception {
        String consentId = UUID.randomUUID().toString();
        Instant expiry = Instant.now().plus(1, ChronoUnit.DAYS);
        BigDecimal limit = new BigDecimal("100.00");

        AccountOwnerConsentRequest valid = createSignedConsent(
                consentId, "alice", aliceDeviceId, aliceDeviceFingerprint, limit, expiry, aliceOwnerKeyPair
        );

        // Attacker extends validity by a year
        AccountOwnerConsentRequest tampered = new AccountOwnerConsentRequest(
                valid.consentId(),
                valid.accountId(),
                valid.deviceId(),
                valid.deviceKeyFingerprint(),
                valid.spendingLimit(),
                expiry.plus(365, ChronoUnit.DAYS),
                valid.ownerSignature()
        );

        ResponseEntity<DeviceAuthorizationResponse> resp = apiController.authorizeDeviceWithConsent(tampered);
        assertEquals(HttpStatus.FORBIDDEN, resp.getStatusCode());
        assertFalse(deviceAuthorizationRegistry.isDeviceAuthorized(aliceDeviceId, "alice"));
    }

    @Test
    @DisplayName("6. Tampered device ID in consent request fails signature verification")
    void tamperedDeviceId_rejectedWith403() throws Exception {
        String consentId = UUID.randomUUID().toString();
        Instant expiry = Instant.now().plus(7, ChronoUnit.DAYS);
        BigDecimal limit = new BigDecimal("500.00");

        AccountOwnerConsentRequest valid = createSignedConsent(
                consentId, "alice", aliceDeviceId, aliceDeviceFingerprint, limit, expiry, aliceOwnerKeyPair
        );

        String rogueDeviceId = "rogue-device-" + UUID.randomUUID();
        AccountOwnerConsentRequest tampered = new AccountOwnerConsentRequest(
                valid.consentId(),
                valid.accountId(),
                rogueDeviceId,
                valid.deviceKeyFingerprint(),
                valid.spendingLimit(),
                valid.expiresAt(),
                valid.ownerSignature()
        );

        assertThrows(Exception.class, () -> apiController.authorizeDeviceWithConsent(tampered));
        assertFalse(deviceAuthorizationRegistry.isDeviceAuthorized(rogueDeviceId, "alice"));
    }

    @Test
    @DisplayName("7. Expired consent token is rejected fail-closed")
    void expiredConsent_rejectedFailClosed() throws Exception {
        String consentId = UUID.randomUUID().toString();
        Instant pastExpiry = Instant.now().minus(2, ChronoUnit.HOURS);
        BigDecimal limit = new BigDecimal("500.00");

        AccountOwnerConsentRequest request = createSignedConsent(
                consentId, "alice", aliceDeviceId, aliceDeviceFingerprint, limit, pastExpiry, aliceOwnerKeyPair
        );

        assertThrows(IllegalArgumentException.class, () -> apiController.authorizeDeviceWithConsent(request));
        assertFalse(deviceAuthorizationRegistry.isDeviceAuthorized(aliceDeviceId, "alice"));
    }

    @Test
    @DisplayName("8. Replayed consent token is rejected fail-closed")
    void replayedConsent_rejectedWith403() throws Exception {
        String consentId = UUID.randomUUID().toString();
        Instant expiry = Instant.now().plus(7, ChronoUnit.DAYS);
        BigDecimal limit = new BigDecimal("500.00");

        AccountOwnerConsentRequest request = createSignedConsent(
                consentId, "alice", aliceDeviceId, aliceDeviceFingerprint, limit, expiry, aliceOwnerKeyPair
        );

        // First presentation succeeds
        ResponseEntity<DeviceAuthorizationResponse> resp1 = apiController.authorizeDeviceWithConsent(request);
        assertEquals(HttpStatus.OK, resp1.getStatusCode());
        assertEquals("AUTHORIZED", resp1.getBody().status());

        // Replay of identical consent is rejected
        ResponseEntity<DeviceAuthorizationResponse> resp2 = apiController.authorizeDeviceWithConsent(request);
        assertEquals(HttpStatus.FORBIDDEN, resp2.getStatusCode());
        assertEquals("FORBIDDEN", resp2.getBody().status());
        assertTrue(resp2.getBody().message().contains("replay attack detected"));
    }

    @Test
    @DisplayName("9. Device key fingerprint mismatch is rejected fail-closed")
    void fingerprintMismatch_rejectedWith403() throws Exception {
        String consentId = UUID.randomUUID().toString();
        Instant expiry = Instant.now().plus(7, ChronoUnit.DAYS);
        BigDecimal limit = new BigDecimal("500.00");

        // Fake fingerprint that doesn't match the device's registered public key
        String fakeFingerprint = "deadbeefcafebabe0123456789abcdef0123456789abcdef0123456789abcdef";

        AccountOwnerConsentRequest request = createSignedConsent(
                consentId, "alice", aliceDeviceId, fakeFingerprint, limit, expiry, aliceOwnerKeyPair
        );

        ResponseEntity<DeviceAuthorizationResponse> resp = apiController.authorizeDeviceWithConsent(request);
        assertEquals(HttpStatus.FORBIDDEN, resp.getStatusCode());
        assertTrue(resp.getBody().message().contains("Device key fingerprint mismatch"));
        assertFalse(deviceAuthorizationRegistry.isDeviceAuthorized(aliceDeviceId, "alice"));
    }

    @Test
    @DisplayName("10. Carol debit authorizations remain strictly fail-closed")
    void carolAuthorization_strictlyBlockedFailClosed() throws Exception {
        KeyPair carolOwnerKey = cryptoService.generateRsaKeyPair();
        String carolPubB64 = Base64.getEncoder().encodeToString(carolOwnerKey.getPublic().getEncoded());

        // 1. Registering owner key for Carol is blocked
        ResponseEntity<KeyRegistrationResponse> regResp = apiController.registerOwnerKey(
                new KeyRegistrationRequest("carol", carolPubB64)
        );
        assertEquals(HttpStatus.FORBIDDEN, regResp.getStatusCode());
        assertEquals("FORBIDDEN", regResp.getBody().status());
        assertTrue(regResp.getBody().message().contains("blocked for account 'carol'"));

        // 2. Submitting consent for Carol is blocked
        String consentId = UUID.randomUUID().toString();
        Instant expiry = Instant.now().plus(7, ChronoUnit.DAYS);
        AccountOwnerConsentRequest carolConsent = createSignedConsent(
                consentId, "carol", aliceDeviceId, aliceDeviceFingerprint, new BigDecimal("100.00"), expiry, carolOwnerKey
        );

        ResponseEntity<DeviceAuthorizationResponse> consentResp = apiController.authorizeDeviceWithConsent(carolConsent);
        assertEquals(HttpStatus.FORBIDDEN, consentResp.getStatusCode());
        assertEquals("FORBIDDEN", consentResp.getBody().status());
        assertTrue(consentResp.getBody().message().contains("blocked for account 'carol'"));

        assertFalse(deviceAuthorizationRegistry.isDeviceAuthorized(aliceDeviceId, "carol"));
    }

    @Test
    @DisplayName("11. Owner key replacement is rejected under prototype trust policy")
    void ownerKeyReplacement_rejected() throws Exception {
        // Re-registering exact same key succeeds idempotently
        String originalKeyB64 = Base64.getEncoder().encodeToString(aliceOwnerKeyPair.getPublic().getEncoded());
        ResponseEntity<KeyRegistrationResponse> idempotentResp = apiController.provisionDevOwnerKey(
                new KeyRegistrationRequest("alice", originalKeyB64)
        );
        assertEquals(HttpStatus.OK, idempotentResp.getStatusCode());
        assertEquals("ALREADY_REGISTERED", idempotentResp.getBody().status());

        // Registering a different public key for alice is rejected
        KeyPair newKeyPair = cryptoService.generateRsaKeyPair();
        String newKeyB64 = Base64.getEncoder().encodeToString(newKeyPair.getPublic().getEncoded());

        assertThrows(IllegalStateException.class, () -> {
            apiController.provisionDevOwnerKey(new KeyRegistrationRequest("alice", newKeyB64));
        });
    }

    @Test
    @DisplayName("12. Revoking device after consent authorization prevents subsequent payments")
    void revokeDevice_blocksSettlementAfterConsent() throws Exception {
        String consentId = UUID.randomUUID().toString();
        Instant expiry = Instant.now().plus(7, ChronoUnit.DAYS);
        BigDecimal limit = new BigDecimal("500.00");

        AccountOwnerConsentRequest request = createSignedConsent(
                consentId, "alice", aliceDeviceId, aliceDeviceFingerprint, limit, expiry, aliceOwnerKeyPair
        );

        // Authorize via consent
        ResponseEntity<DeviceAuthorizationResponse> authResp = apiController.authorizeDeviceWithConsent(request);
        assertEquals(HttpStatus.OK, authResp.getStatusCode());

        // Revoke device authorization
        DeviceAuthorizationRequest revokeReq = new DeviceAuthorizationRequest(aliceDeviceId, "alice");
        ResponseEntity<DeviceAuthorizationResponse> revokeResp = apiController.revokeDevice(
                revokeReq, TEST_ADMIN_TOKEN, null
        );
        assertEquals(HttpStatus.OK, revokeResp.getStatusCode());
        assertEquals("REVOKED", revokeResp.getBody().status());

        // Payment settlement attempt must fail fail-closed with IllegalStateException
        PaymentInstruction instruction = new PaymentInstruction(
                "pay-revoked-" + UUID.randomUUID(),
                "alice",
                "bob",
                new BigDecimal("50.00"),
                Instant.now(),
                UUID.randomUUID().toString()
        );
        String sig = cryptoService.signBase64(instruction.toCanonicalBytes(), aliceDeviceKeyPair.getPrivate());
        SignedPaymentRequest payReq = new SignedPaymentRequest(aliceDeviceId, instruction.withSignature(sig));

        IllegalStateException ex = assertThrows(IllegalStateException.class, () ->
                apiController.submitSignedMeshPayment(payReq)
        );
        assertTrue(ex.getMessage().contains("REVOKED"));
    }

    @Test
    @DisplayName("13. Spending limit specified in consent is strictly enforced at settlement")
    void spendingLimitInConsent_strictlyEnforcedAtSettlement() throws Exception {
        String consentId = UUID.randomUUID().toString();
        Instant expiry = Instant.now().plus(7, ChronoUnit.DAYS);
        BigDecimal limit = new BigDecimal("200.00"); // Limit is ₹200.00

        AccountOwnerConsentRequest request = createSignedConsent(
                consentId, "alice", aliceDeviceId, aliceDeviceFingerprint, limit, expiry, aliceOwnerKeyPair
        );

        ResponseEntity<DeviceAuthorizationResponse> authResp = apiController.authorizeDeviceWithConsent(request);
        assertEquals(HttpStatus.OK, authResp.getStatusCode());

        // Attempt payment for ₹250.00 exceeding authorized limit of ₹200.00
        PaymentInstruction overLimitInstruction = new PaymentInstruction(
                "pay-overlimit-" + UUID.randomUUID(),
                "alice",
                "bob",
                new BigDecimal("250.00"),
                Instant.now(),
                UUID.randomUUID().toString()
        );
        String sig = cryptoService.signBase64(overLimitInstruction.toCanonicalBytes(), aliceDeviceKeyPair.getPrivate());
        SignedPaymentRequest payReq = new SignedPaymentRequest(aliceDeviceId, overLimitInstruction.withSignature(sig));

        IllegalStateException ex = assertThrows(IllegalStateException.class, () ->
                apiController.submitSignedMeshPayment(payReq)
        );
        assertTrue(ex.getMessage().contains("exceeds authorized spending limit"));
    }

    @Test
    @DisplayName("14. Unregistered device cannot be authorized via consent")
    void unregisteredDevice_cannotBeAuthorized() throws Exception {
        String unregisteredDevId = "unregistered-phone-" + UUID.randomUUID();
        String fakeFingerprint = "abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234";

        AccountOwnerConsentRequest request = createSignedConsent(
                UUID.randomUUID().toString(),
                "alice",
                unregisteredDevId,
                fakeFingerprint,
                new BigDecimal("100.00"),
                Instant.now().plus(1, ChronoUnit.DAYS),
                aliceOwnerKeyPair
        );

        assertThrows(IllegalArgumentException.class, () -> {
            apiController.authorizeDeviceWithConsent(request);
        });
    }
}
