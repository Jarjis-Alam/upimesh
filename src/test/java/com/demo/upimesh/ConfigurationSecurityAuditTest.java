package com.demo.upimesh;

import com.demo.upimesh.model.Account;
import com.demo.upimesh.model.AccountOwnerKeyRepository;
import com.demo.upimesh.model.AccountRepository;
import com.demo.upimesh.model.ConsumedConsentRepository;
import com.demo.upimesh.model.DeviceAuthorizationRequest;
import com.demo.upimesh.model.DeviceAuthorizationResponse;
import com.demo.upimesh.model.KeyRegistrationRequest;
import com.demo.upimesh.model.KeyRegistrationResponse;
import com.demo.upimesh.model.ProcessedPacketRepository;
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
import java.util.Base64;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.options;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Stage 8.9 Configuration and Deployment Security Audit Test Suite.
 * <p>
 * Specifically verifies:
 * 1. Development owner-key provisioning is disabled by default and cannot be enabled in production environments.
 * 2. Development provisioning secret is never confused with the administrator pairing token (credential reuse prevention).
 * 3. Insecure placeholder tokens ("dev-test-token", "true", "password", etc.) are strictly rejected fail-closed.
 * 4. Token domain segregation: admin token cannot provision keys, dev token cannot pair/revoke devices.
 * 5. Missing or invalid security configuration fails closed across all protected endpoints.
 * 6. Boolean header alone ('X-Dev-Provisioning: true') is rejected.
 * 7. Carol remains strictly blocked fail-closed under all configurations.
 * 8. Browser CORS policies restrict arbitrary cross-origin domains.
 */
@SpringBootTest
@DirtiesContext(classMode = DirtiesContext.ClassMode.BEFORE_EACH_TEST_METHOD)
public class ConfigurationSecurityAuditTest {

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
    private WebApplicationContext webApplicationContext;

    private MockMvc mockMvc;

    private static final String TEST_ADMIN_TOKEN = "audit-stage89-admin-secret-token";
    private static final String TEST_DEV_PROVISIONING_TOKEN = "audit-stage89-dev-provisioning-secret-xyz";

    @BeforeEach
    void setUp() {
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
        apiController.setEnvironment(null); // default non-production test environment

        accountRepository.save(new Account("alice", new BigDecimal("5000.00")));
        accountRepository.save(new Account("bob", new BigDecimal("1000.00")));
        accountRepository.save(new Account("carol", new BigDecimal("2000.00")));
    }

    @Test
    @DisplayName("1. Dev key provisioning is disabled by default and rejected when devKeyProvisioningEnabled is false")
    void testDevProvisioning_disabledByDefault() throws Exception {
        apiController.setDevKeyProvisioningEnabled(false);
        assertFalse(apiController.isDevKeyProvisioningEnabled());

        KeyPair keyPair = cryptoService.generateRsaKeyPair();
        String pubB64 = Base64.getEncoder().encodeToString(keyPair.getPublic().getEncoded());

        ResponseEntity<KeyRegistrationResponse> response = apiController.registerOwnerKey(
                new KeyRegistrationRequest("bob", pubB64),
                TEST_DEV_PROVISIONING_TOKEN
        );

        assertEquals(HttpStatus.FORBIDDEN, response.getStatusCode());
        assertEquals("FORBIDDEN", response.getBody().status());
        assertTrue(response.getBody().message().contains("Public account-owner key enrollment is disabled"));
        assertFalse(accountOwnerKeyRegistry.hasKey("bob"));
    }

    @Test
    @DisplayName("2. Dev provisioning CANNOT be enabled in a production environment")
    void testDevProvisioning_cannotBeEnabledInProductionEnvironment() throws Exception {
        MockEnvironment prodEnv = new MockEnvironment();
        prodEnv.setActiveProfiles("prod");
        apiController.setEnvironment(prodEnv);

        assertTrue(apiController.isProductionEnvironment());

        // Attempting to enable dev provisioning in production is forcibly blocked
        apiController.setDevKeyProvisioningEnabled(true);
        assertFalse(apiController.isDevKeyProvisioningEnabled());

        KeyPair keyPair = cryptoService.generateRsaKeyPair();
        String pubB64 = Base64.getEncoder().encodeToString(keyPair.getPublic().getEncoded());

        // Even with valid dev provisioning token, registration is rejected with 403 Forbidden
        ResponseEntity<KeyRegistrationResponse> response = apiController.registerOwnerKey(
                new KeyRegistrationRequest("bob", pubB64),
                TEST_DEV_PROVISIONING_TOKEN
        );

        assertEquals(HttpStatus.FORBIDDEN, response.getStatusCode());
        assertEquals("FORBIDDEN", response.getBody().status());
        assertFalse(accountOwnerKeyRegistry.hasKey("bob"));
    }

    @Test
    @DisplayName("3. Token confusion guard: Dev provisioning token identical to Admin token FAILS CLOSED")
    void testTokenConfusion_devTokenIdenticalToAdminToken_failsClosed() throws Exception {
        String sharedToken = "dangerously-shared-secret-token-123456789";
        apiController.setConfiguredAdminToken(sharedToken);
        apiController.setConfiguredDevProvisioningToken(sharedToken);

        KeyPair keyPair = cryptoService.generateRsaKeyPair();
        String pubB64 = Base64.getEncoder().encodeToString(keyPair.getPublic().getEncoded());

        // Reusable credential across admin and dev domains must be rejected
        ResponseEntity<KeyRegistrationResponse> response = apiController.registerOwnerKey(
                new KeyRegistrationRequest("bob", pubB64),
                sharedToken
        );

        assertEquals(HttpStatus.UNAUTHORIZED, response.getStatusCode());
        assertFalse(accountOwnerKeyRegistry.hasKey("bob"));
    }

    @Test
    @DisplayName("4. Insecure placeholder tokens ('dev-test-token', 'admin', 'password', etc.) FAIL CLOSED")
    void testInsecurePlaceholderTokens_failClosed() throws Exception {
        String[] placeholders = {"dev-test-token", "true", "false", "token", "admin", "password", "secret", "123456"};

        for (String placeholder : placeholders) {
            apiController.setConfiguredDevProvisioningToken(placeholder);

            KeyPair keyPair = cryptoService.generateRsaKeyPair();
            String pubB64 = Base64.getEncoder().encodeToString(keyPair.getPublic().getEncoded());

            ResponseEntity<KeyRegistrationResponse> response = apiController.registerOwnerKey(
                    new KeyRegistrationRequest("bob", pubB64),
                    placeholder
            );

            assertEquals(HttpStatus.UNAUTHORIZED, response.getStatusCode(),
                    "Expected unauthorized for placeholder: " + placeholder);
            assertFalse(accountOwnerKeyRegistry.hasKey("bob"));
        }
    }

    @Test
    @DisplayName("5. Domain isolation: Administrator token CANNOT authorize owner-key registration")
    void testAdminToken_cannotAuthorizeOwnerKeyRegistration() throws Exception {
        KeyPair keyPair = cryptoService.generateRsaKeyPair();
        String pubB64 = Base64.getEncoder().encodeToString(keyPair.getPublic().getEncoded());

        ResponseEntity<KeyRegistrationResponse> response = apiController.registerOwnerKey(
                new KeyRegistrationRequest("bob", pubB64),
                TEST_ADMIN_TOKEN
        );

        assertEquals(HttpStatus.UNAUTHORIZED, response.getStatusCode());
        assertFalse(accountOwnerKeyRegistry.hasKey("bob"));
    }

    @Test
    @DisplayName("6. Domain isolation: Dev provisioning token CANNOT authorize device pairing")
    void testDevToken_cannotAuthorizeDevicePairing() throws Exception {
        String devId = "test-phone-pair";
        KeyPair devKeyPair = cryptoService.generateRsaKeyPair();
        String devPubB64 = Base64.getEncoder().encodeToString(devKeyPair.getPublic().getEncoded());
        apiController.registerSenderKey(new KeyRegistrationRequest(devId, devPubB64), null, null);

        // Attempt device authorization with dev provisioning token instead of admin token
        DeviceAuthorizationRequest request = new DeviceAuthorizationRequest(devId, "alice");
        ResponseEntity<DeviceAuthorizationResponse> response = apiController.authorizeDevice(
                request,
                TEST_DEV_PROVISIONING_TOKEN,
                null
        );

        assertEquals(HttpStatus.UNAUTHORIZED, response.getStatusCode());
        assertFalse(deviceAuthorizationRegistry.isDeviceAuthorized(devId, "alice"));
    }

    @Test
    @DisplayName("7. Domain isolation: Dev provisioning token CANNOT authorize device revocation")
    void testDevToken_cannotAuthorizeDeviceRevocation() throws Exception {
        String devId = "test-phone-revoke";
        KeyPair devKeyPair = cryptoService.generateRsaKeyPair();
        String devPubB64 = Base64.getEncoder().encodeToString(devKeyPair.getPublic().getEncoded());
        apiController.registerSenderKey(new KeyRegistrationRequest(devId, devPubB64), null, null);

        // Pair device with valid admin token
        DeviceAuthorizationRequest pairReq = new DeviceAuthorizationRequest(devId, "alice");
        apiController.authorizeDevice(pairReq, TEST_ADMIN_TOKEN, null);
        assertTrue(deviceAuthorizationRegistry.isDeviceAuthorized(devId, "alice"));

        // Attempt revocation with dev provisioning token
        DeviceAuthorizationRequest revokeReq = new DeviceAuthorizationRequest(devId, "alice");
        ResponseEntity<DeviceAuthorizationResponse> response = apiController.revokeDevice(
                revokeReq,
                TEST_DEV_PROVISIONING_TOKEN,
                null
        );

        assertEquals(HttpStatus.UNAUTHORIZED, response.getStatusCode());
        // Device remains authorized (revocation rejected)
        assertTrue(deviceAuthorizationRegistry.isDeviceAuthorized(devId, "alice"));
    }

    @Test
    @DisplayName("8. Missing security configuration fails closed across all protected endpoints")
    void testMissingSecurityConfiguration_failsClosed() throws Exception {
        KeyPair keyPair = cryptoService.generateRsaKeyPair();
        String pubB64 = Base64.getEncoder().encodeToString(keyPair.getPublic().getEncoded());

        // A. Dev provisioning token unconfigured
        apiController.setConfiguredDevProvisioningToken(null);
        ResponseEntity<KeyRegistrationResponse> respDev = apiController.registerOwnerKey(
                new KeyRegistrationRequest("bob", pubB64),
                "some-token"
        );
        assertEquals(HttpStatus.UNAUTHORIZED, respDev.getStatusCode());

        // B. Admin token unconfigured
        apiController.setConfiguredAdminToken(null);
        String devId = "phone-unconfigured-admin";
        apiController.registerSenderKey(new KeyRegistrationRequest(devId, pubB64), null, null);
        ResponseEntity<DeviceAuthorizationResponse> respAdmin = apiController.authorizeDevice(
                new DeviceAuthorizationRequest(devId, "alice"),
                "some-admin-token",
                null
        );
        assertEquals(HttpStatus.UNAUTHORIZED, respAdmin.getStatusCode());
    }

    @Test
    @DisplayName("9. Boolean header 'X-Dev-Provisioning: true' alone is strictly rejected")
    void testBooleanHeaderAlone_isRejected() throws Exception {
        KeyPair keyPair = cryptoService.generateRsaKeyPair();
        String pubB64 = Base64.getEncoder().encodeToString(keyPair.getPublic().getEncoded());

        ResponseEntity<KeyRegistrationResponse> resp = apiController.registerOwnerKey(
                new KeyRegistrationRequest("bob", pubB64),
                null,
                "true"
        );

        assertEquals(HttpStatus.UNAUTHORIZED, resp.getStatusCode());
        assertFalse(accountOwnerKeyRegistry.hasKey("bob"));
    }

    @Test
    @DisplayName("10. Carol remains strictly blocked fail-closed under all configurations")
    void testCarolBlocked_failClosed() throws Exception {
        KeyPair carolKeyPair = cryptoService.generateRsaKeyPair();
        String carolPubB64 = Base64.getEncoder().encodeToString(carolKeyPair.getPublic().getEncoded());

        // 1. Owner key enrollment for Carol blocked
        ResponseEntity<KeyRegistrationResponse> regResp = apiController.registerOwnerKey(
                new KeyRegistrationRequest("carol", carolPubB64),
                TEST_DEV_PROVISIONING_TOKEN
        );
        assertEquals(HttpStatus.FORBIDDEN, regResp.getStatusCode());

        // 2. Device pairing for Carol blocked
        apiController.registerSenderKey(new KeyRegistrationRequest("carol-phone", carolPubB64), null, null);
        ResponseEntity<DeviceAuthorizationResponse> authResp = apiController.authorizeDevice(
                new DeviceAuthorizationRequest("carol-phone", "carol"),
                TEST_ADMIN_TOKEN,
                null
        );
        assertEquals(HttpStatus.FORBIDDEN, authResp.getStatusCode());
        assertFalse(deviceAuthorizationRegistry.isDeviceAuthorized("carol-phone", "carol"));
    }

    @Test
    @DisplayName("11. CORS policy restricts unauthorized browser cross-origin requests")
    void testCorsPolicy_restrictsUnauthorizedCrossOrigins() throws Exception {
        // 1. Unauthorized origin: preflight OPTIONS must be rejected (403 Forbidden)
        mockMvc.perform(options("/api/accounts")
                        .header("Origin", "http://evil-attacker-website.com")
                        .header("Access-Control-Request-Method", "GET"))
                .andExpect(status().isForbidden());

        // 2. Unauthorized origin: GET request must not receive Access-Control-Allow-Origin header
        mockMvc.perform(get("/api/accounts")
                        .header("Origin", "http://evil-attacker-website.com"))
                .andExpect(header().doesNotExist("Access-Control-Allow-Origin"));

        // 3. Trusted local origin: preflight OPTIONS is accepted (200 OK)
        mockMvc.perform(options("/api/accounts")
                        .header("Origin", "http://localhost:8080")
                        .header("Access-Control-Request-Method", "GET"))
                .andExpect(status().isOk())
                .andExpect(header().string("Access-Control-Allow-Origin", "http://localhost:8080"));
    }
}
