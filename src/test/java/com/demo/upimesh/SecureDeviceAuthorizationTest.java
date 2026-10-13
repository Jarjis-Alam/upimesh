package com.demo.upimesh;

import com.demo.upimesh.model.Account;
import com.demo.upimesh.model.AccountRepository;
import com.demo.upimesh.model.DeviceAuthorizationRequest;
import com.demo.upimesh.model.DeviceAuthorizationResponse;
import com.demo.upimesh.model.KeyRegistrationRequest;
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
import java.util.Base64;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Backend test suite verifying administrator-controlled device debit authorization
 * under prototype security policies (Stage 6.4B.7).
 */
@SpringBootTest
@DirtiesContext(classMode = DirtiesContext.ClassMode.BEFORE_EACH_TEST_METHOD)
class SecureDeviceAuthorizationTest {

    @Autowired
    private ApiController apiController;

    @Autowired
    private AccountRepository accountRepository;

    @Autowired
    private SenderKeyRegistry senderKeyRegistry;

    @Autowired
    private DeviceAuthorizationRegistry deviceAuthorizationRegistry;

    @Autowired
    private CryptoService cryptoService;

    private static final String TEST_ADMIN_TOKEN = "sec-dev-admin-pairing-token-abc123xyz";
    private String testDeviceId;
    private final String testAccountId = "test-account-alice";

    @BeforeEach
    void setUp() throws Exception {
        testDeviceId = "test-device-" + UUID.randomUUID();

        // Configure test admin token on controller
        apiController.setConfiguredAdminToken(TEST_ADMIN_TOKEN);

        // Ensure clean test registries and test account
        senderKeyRegistry.clearForTesting();
        deviceAuthorizationRegistry.clearForTesting();

        if (!accountRepository.existsById(testAccountId)) {
            accountRepository.save(new Account(testAccountId, new BigDecimal("1000.00")));
        }

        // Register public key for testDeviceId
        KeyPair kp = cryptoService.generateRsaKeyPair();
        String pubB64 = Base64.getEncoder().encodeToString(kp.getPublic().getEncoded());
        apiController.registerSenderKey(new KeyRegistrationRequest(testDeviceId, pubB64), null, null);
    }

    @Test
    @DisplayName("1. Missing administrator pairing token is rejected with HTTP 401 Unauthorized")
    void authorize_missingToken_rejectedWith401() {
        DeviceAuthorizationRequest request = new DeviceAuthorizationRequest(testDeviceId, testAccountId);
        ResponseEntity<DeviceAuthorizationResponse> response = apiController.authorizeDevice(request, null, null);

        assertEquals(HttpStatus.UNAUTHORIZED, response.getStatusCode());
        assertNotNull(response.getBody());
        assertEquals("UNAUTHORIZED", response.getBody().status());
        assertFalse(deviceAuthorizationRegistry.isDeviceAuthorized(testDeviceId, testAccountId));
    }

    @Test
    @DisplayName("2. Incorrect administrator pairing token is rejected with HTTP 401 Unauthorized")
    void authorize_incorrectToken_rejectedWith401() {
        DeviceAuthorizationRequest request = new DeviceAuthorizationRequest(testDeviceId, testAccountId);
        ResponseEntity<DeviceAuthorizationResponse> response = apiController.authorizeDevice(request, "invalid-token-xyz", null);

        assertEquals(HttpStatus.UNAUTHORIZED, response.getStatusCode());
        assertNotNull(response.getBody());
        assertEquals("UNAUTHORIZED", response.getBody().status());
        assertFalse(deviceAuthorizationRegistry.isDeviceAuthorized(testDeviceId, testAccountId));
    }

    @Test
    @DisplayName("3. Unconfigured environment token rejects all authorization attempts with HTTP 401")
    void authorize_unconfiguredAdminToken_rejectedWith401() {
        apiController.setConfiguredAdminToken(""); // Unset/empty
        DeviceAuthorizationRequest request = new DeviceAuthorizationRequest(testDeviceId, testAccountId);
        ResponseEntity<DeviceAuthorizationResponse> response = apiController.authorizeDevice(request, TEST_ADMIN_TOKEN, null);

        assertEquals(HttpStatus.UNAUTHORIZED, response.getStatusCode());
        assertNotNull(response.getBody());
        assertEquals("UNAUTHORIZED", response.getBody().status());
        assertFalse(deviceAuthorizationRegistry.isDeviceAuthorized(testDeviceId, testAccountId));
    }

    @Test
    @DisplayName("4. Correct token with unknown device ID (not in SenderKeyRegistry) throws IllegalArgumentException")
    void authorize_correctToken_unknownDevice_rejectedWithBadRequest() {
        String unknownDev = "unknown-device-" + UUID.randomUUID();
        DeviceAuthorizationRequest request = new DeviceAuthorizationRequest(unknownDev, testAccountId);

        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () ->
                apiController.authorizeDevice(request, TEST_ADMIN_TOKEN, null)
        );
        assertTrue(ex.getMessage().contains("must be registered in SenderKeyRegistry"));
        assertFalse(deviceAuthorizationRegistry.isDeviceAuthorized(unknownDev, testAccountId));
    }

    @Test
    @DisplayName("5. Correct token with unknown account ID (not in AccountRepository) throws IllegalArgumentException")
    void authorize_correctToken_unknownAccount_rejectedWithBadRequest() {
        String unknownAcc = "nonexistent-user-" + UUID.randomUUID();
        DeviceAuthorizationRequest request = new DeviceAuthorizationRequest(testDeviceId, unknownAcc);

        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () ->
                apiController.authorizeDevice(request, TEST_ADMIN_TOKEN, null)
        );
        assertTrue(ex.getMessage().contains("does not exist in ledger"));
        assertFalse(deviceAuthorizationRegistry.isDeviceAuthorized(testDeviceId, unknownAcc));
    }

    @Test
    @DisplayName("6. Correct token with registered device and valid account successfully authorizes device")
    void authorize_correctToken_validDeviceAndAccount_succeeds() {
        DeviceAuthorizationRequest request = new DeviceAuthorizationRequest(testDeviceId, testAccountId);
        ResponseEntity<DeviceAuthorizationResponse> response = apiController.authorizeDevice(request, TEST_ADMIN_TOKEN, null);

        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertNotNull(response.getBody());
        assertEquals("AUTHORIZED", response.getBody().status());
        assertEquals(testDeviceId, response.getBody().deviceId());
        assertEquals(testAccountId, response.getBody().accountId());
        assertTrue(deviceAuthorizationRegistry.isDeviceAuthorized(testDeviceId, testAccountId));
    }

    @Test
    @DisplayName("7. Re-authorizing an already authorized device returns ALREADY_AUTHORIZED idempotently")
    void authorize_correctToken_alreadyAuthorized_returnsAlreadyAuthorized() {
        // Initial authorization
        DeviceAuthorizationRequest request = new DeviceAuthorizationRequest(testDeviceId, testAccountId);
        ResponseEntity<DeviceAuthorizationResponse> first = apiController.authorizeDevice(request, TEST_ADMIN_TOKEN, null);
        assertEquals(HttpStatus.OK, first.getStatusCode());
        assertEquals("AUTHORIZED", first.getBody().status());

        // Second authorization attempt
        ResponseEntity<DeviceAuthorizationResponse> second = apiController.authorizeDevice(request, TEST_ADMIN_TOKEN, null);
        assertEquals(HttpStatus.OK, second.getStatusCode());
        assertNotNull(second.getBody());
        assertEquals("ALREADY_AUTHORIZED", second.getBody().status());
        assertEquals(testDeviceId, second.getBody().deviceId());
        assertEquals(testAccountId, second.getBody().accountId());
        assertTrue(deviceAuthorizationRegistry.isDeviceAuthorized(testDeviceId, testAccountId));
    }

    @Test
    @DisplayName("8. Authorizing via Authorization: Bearer <token> header succeeds")
    void authorize_bearerTokenHeader_succeeds() {
        DeviceAuthorizationRequest request = new DeviceAuthorizationRequest(testDeviceId, testAccountId);
        ResponseEntity<DeviceAuthorizationResponse> response = apiController.authorizeDevice(
                request,
                null,
                "Bearer " + TEST_ADMIN_TOKEN
        );

        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertEquals("AUTHORIZED", response.getBody().status());
        assertTrue(deviceAuthorizationRegistry.isDeviceAuthorized(testDeviceId, testAccountId));
    }

    @Test
    @DisplayName("9. Authorizing via request payload adminToken field succeeds")
    void authorize_requestBodyAdminToken_succeeds() {
        DeviceAuthorizationRequest request = new DeviceAuthorizationRequest(
                testDeviceId,
                testAccountId,
                TEST_ADMIN_TOKEN
        );
        ResponseEntity<DeviceAuthorizationResponse> response = apiController.authorizeDevice(request);

        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertEquals("AUTHORIZED", response.getBody().status());
        assertTrue(deviceAuthorizationRegistry.isDeviceAuthorized(testDeviceId, testAccountId));
    }
}
