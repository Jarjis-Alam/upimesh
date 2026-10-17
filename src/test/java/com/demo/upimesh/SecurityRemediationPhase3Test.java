package com.demo.upimesh;

import com.demo.upimesh.model.Account;
import com.demo.upimesh.model.AccountRepository;
import com.demo.upimesh.model.KeyRegistrationRequest;
import com.demo.upimesh.model.KeyRegistrationResponse;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.mock.env.MockEnvironment;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;

import java.math.BigDecimal;
import java.security.KeyPair;
import java.util.Base64;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@ActiveProfiles("test")
@org.springframework.test.annotation.DirtiesContext(classMode = org.springframework.test.annotation.DirtiesContext.ClassMode.AFTER_CLASS)
public class SecurityRemediationPhase3Test {

    @Autowired
    private WebApplicationContext webApplicationContext;

    @Autowired
    private ApiController apiController;

    @Autowired
    private AccountRepository accountRepository;

    @Autowired
    private SenderKeyRegistry senderKeyRegistry;

    @Autowired
    private CryptoService cryptoService;

    private MockMvc mockMvc;
    private static final String STRONG_DEV_ADMIN_TOKEN = "meshpay-dev-secure-admin-token-2026!";
    private static final String DEV_PROVISIONING_TOKEN = "stage88-test-dev-provisioning-secret-xyz";

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.webAppContextSetup(webApplicationContext).build();
        accountRepository.deleteAll();
        accountRepository.save(new Account("alice", new BigDecimal("5000.00")));
        accountRepository.save(new Account("bob", new BigDecimal("1000.00")));
        senderKeyRegistry.clearForTesting();

        apiController.setEnvironment(null);
        apiController.setConfiguredAdminToken(STRONG_DEV_ADMIN_TOKEN);
        apiController.setDevKeyProvisioningEnabled(true);
        apiController.setConfiguredDevProvisioningToken(DEV_PROVISIONING_TOKEN);
    }

    @AfterEach
    void tearDown() {
        senderKeyRegistry.clearForTesting();
        accountRepository.deleteAll();
        apiController.setEnvironment(null);
        apiController.setConfiguredAdminToken(null);
        apiController.setDevKeyProvisioningEnabled(false);
        apiController.setConfiguredDevProvisioningToken(null);
    }

    @Test
    @DisplayName("3.1 Unauthenticated attempt to register key for existing ledger account 'alice' is rejected with 401")
    void testUnauthorizedRegistration_existingLedgerAccount_rejected() throws Exception {
        KeyPair keyPair = cryptoService.generateRsaKeyPair();
        String pubKeyB64 = Base64.getEncoder().encodeToString(keyPair.getPublic().getEncoded());

        // Unauthenticated network request to register Alice's key
        mockMvc.perform(post("/api/keys/register")
                        .contentType("application/json")
                        .content("{\"accountId\":\"alice\",\"publicKey\":\"" + pubKeyB64 + "\"}"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.status").value("UNAUTHORIZED"))
                .andExpect(jsonPath("$.accountId").value("alice"));

        // Confirm key was NOT registered in SenderKeyRegistry
        assertFalse(senderKeyRegistry.hasKey("alice"));
    }

    @Test
    @DisplayName("3.2 Authorized registration for ledger account with admin token succeeds")
    void testAuthorizedRegistration_withAdminToken_succeeds() throws Exception {
        KeyPair keyPair = cryptoService.generateRsaKeyPair();
        String pubKeyB64 = Base64.getEncoder().encodeToString(keyPair.getPublic().getEncoded());

        mockMvc.perform(post("/api/keys/register")
                        .header("X-Admin-Token", STRONG_DEV_ADMIN_TOKEN)
                        .contentType("application/json")
                        .content("{\"accountId\":\"alice\",\"publicKey\":\"" + pubKeyB64 + "\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("REGISTERED"))
                .andExpect(jsonPath("$.accountId").value("alice"));

        assertTrue(senderKeyRegistry.hasKey("alice"));
    }

    @Test
    @DisplayName("3.3 Authorized registration for ledger account with dev provisioning token succeeds")
    void testAuthorizedRegistration_withDevProvisioningToken_succeeds() throws Exception {
        KeyPair keyPair = cryptoService.generateRsaKeyPair();
        String pubKeyB64 = Base64.getEncoder().encodeToString(keyPair.getPublic().getEncoded());

        mockMvc.perform(post("/api/keys/register")
                        .header("X-Dev-Provisioning-Token", DEV_PROVISIONING_TOKEN)
                        .contentType("application/json")
                        .content("{\"accountId\":\"bob\",\"publicKey\":\"" + pubKeyB64 + "\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("REGISTERED"))
                .andExpect(jsonPath("$.accountId").value("bob"));

        assertTrue(senderKeyRegistry.hasKey("bob"));
    }

    @Test
    @DisplayName("3.4 Idempotent re-registration of identical key succeeds without requiring re-auth")
    void testDuplicateRegistration_sameKey_idempotent() throws Exception {
        KeyPair keyPair = cryptoService.generateRsaKeyPair();
        String pubKeyB64 = Base64.getEncoder().encodeToString(keyPair.getPublic().getEncoded());

        // First registration with admin token
        KeyRegistrationRequest req = new KeyRegistrationRequest("alice", pubKeyB64);
        ResponseEntity<KeyRegistrationResponse> resp1 = apiController.registerSenderKey(
                req, null, null, STRONG_DEV_ADMIN_TOKEN, null, null
        );
        assertEquals(HttpStatus.OK, resp1.getStatusCode());
        assertEquals("REGISTERED", resp1.getBody().status());

        // Second registration with NO auth header (idempotent re-affirmation)
        ResponseEntity<KeyRegistrationResponse> resp2 = apiController.registerSenderKey(
                req, null, null, null, null, null
        );
        assertEquals(HttpStatus.OK, resp2.getStatusCode());
        assertEquals("ALREADY_REGISTERED", resp2.getBody().status());
    }

    @Test
    @DisplayName("3.5 Conflicting key replacement with different key is rejected with IllegalStateException")
    void testConflictingKeyRegistration_differentKey_rejected() throws Exception {
        KeyPair key1 = cryptoService.generateRsaKeyPair();
        KeyPair key2 = cryptoService.generateRsaKeyPair();
        String b64Key1 = Base64.getEncoder().encodeToString(key1.getPublic().getEncoded());
        String b64Key2 = Base64.getEncoder().encodeToString(key2.getPublic().getEncoded());

        // Register key1
        apiController.registerSenderKey(
                new KeyRegistrationRequest("alice", b64Key1), null, null, STRONG_DEV_ADMIN_TOKEN, null, null
        );

        // Attempt to register key2 for alice (even with admin token, arbitrary replacement is forbidden)
        IllegalStateException ex = assertThrows(IllegalStateException.class, () ->
                apiController.registerSenderKey(
                        new KeyRegistrationRequest("alice", b64Key2), null, null, STRONG_DEV_ADMIN_TOKEN, null, null
                )
        );
        assertTrue(ex.getMessage().contains("Arbitrary key replacement is forbidden"));
    }

    @Test
    @DisplayName("3.6 Production profile rejects unauthenticated registration with 403 Forbidden")
    void testProductionProfile_unauthenticatedRegistration_forbidden() throws Exception {
        MockEnvironment prodEnv = new MockEnvironment();
        prodEnv.setActiveProfiles("prod");
        apiController.setEnvironment(prodEnv);

        KeyPair keyPair = cryptoService.generateRsaKeyPair();
        String pubKeyB64 = Base64.getEncoder().encodeToString(keyPair.getPublic().getEncoded());

        KeyRegistrationRequest req = new KeyRegistrationRequest("device-mac-123", pubKeyB64);
        ResponseEntity<KeyRegistrationResponse> response = apiController.registerSenderKey(
                req, null, null, null, null, null
        );

        assertEquals(HttpStatus.FORBIDDEN, response.getStatusCode());
        assertEquals("FORBIDDEN", response.getBody().status());
        assertTrue(response.getBody().message().contains("Public key self-registration is disabled in production profile"));
    }

    @Test
    @DisplayName("3.7 Production profile with valid admin token succeeds")
    void testProductionProfile_withAdminToken_succeeds() throws Exception {
        MockEnvironment prodEnv = new MockEnvironment();
        prodEnv.setActiveProfiles("prod");
        apiController.setEnvironment(prodEnv);

        KeyPair keyPair = cryptoService.generateRsaKeyPair();
        String pubKeyB64 = Base64.getEncoder().encodeToString(keyPair.getPublic().getEncoded());

        KeyRegistrationRequest req = new KeyRegistrationRequest("device-mac-123", pubKeyB64);
        ResponseEntity<KeyRegistrationResponse> response = apiController.registerSenderKey(
                req, null, null, STRONG_DEV_ADMIN_TOKEN, null, null
        );

        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertEquals("REGISTERED", response.getBody().status());
    }

    @Test
    @DisplayName("3.8 Concurrent registration for same key is safely thread-safe")
    void testConcurrentRegistration_safe() throws Exception {
        KeyPair keyPair = cryptoService.generateRsaKeyPair();
        String pubKeyB64 = Base64.getEncoder().encodeToString(keyPair.getPublic().getEncoded());

        int threads = 4;
        ExecutorService executor = Executors.newFixedThreadPool(threads);
        CountDownLatch latch = new CountDownLatch(1);
        AtomicInteger successCount = new AtomicInteger(0);

        for (int i = 0; i < threads; i++) {
            executor.submit(() -> {
                try {
                    latch.await();
                    ResponseEntity<KeyRegistrationResponse> resp = apiController.registerSenderKey(
                            new KeyRegistrationRequest("device-concurrent-test", pubKeyB64),
                            null, null, STRONG_DEV_ADMIN_TOKEN, null, null
                    );
                    if (resp.getStatusCode() == HttpStatus.OK) {
                        successCount.incrementAndGet();
                    }
                } catch (Exception ignored) {
                }
            });
        }

        latch.countDown();
        executor.shutdown();
        executor.awaitTermination(5, java.util.concurrent.TimeUnit.SECONDS);

        assertEquals(threads, successCount.get());
        assertTrue(senderKeyRegistry.hasKey("device-concurrent-test"));
    }
}
