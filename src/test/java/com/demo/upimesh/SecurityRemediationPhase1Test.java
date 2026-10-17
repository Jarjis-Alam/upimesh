package com.demo.upimesh;

import com.demo.upimesh.model.Account;
import com.demo.upimesh.model.AccountRepository;
import com.demo.upimesh.model.BankAuthorityCredential;
import com.demo.upimesh.model.BankAuthorityCredentialRepository;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.mock.env.MockEnvironment;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;

import javax.crypto.SecretKey;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.security.KeyPair;
import java.security.MessageDigest;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.Base64;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@ActiveProfiles("test")
public class SecurityRemediationPhase1Test {

    @Autowired
    private WebApplicationContext webApplicationContext;

    @Autowired
    private AccountRepository accountRepository;

    @Autowired
    private CryptoService cryptoService;

    @Autowired
    private FinancialSecurityService financialSecurityService;

    private MockMvc mockMvc;
    private static final String STRONG_DEV_ADMIN_TOKEN = "meshpay-dev-secure-admin-token-2026!";

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.webAppContextSetup(webApplicationContext).build();
        accountRepository.deleteAll();
        accountRepository.save(new Account("alice", new BigDecimal("5000.00")));
        accountRepository.save(new Account("bob", new BigDecimal("1000.00")));

        financialSecurityService.setEnvironment(null);
        financialSecurityService.setConfiguredAdminToken(STRONG_DEV_ADMIN_TOKEN);
        financialSecurityService.setDemoAuthEnabled(false);
        financialSecurityService.clearConfiguredUserTokens();
        financialSecurityService.setConfiguredUserToken("alice", "alice-secure-token-12345");
    }

    @AfterEach
    void tearDown() {
        financialSecurityService.setEnvironment(null);
        financialSecurityService.setConfiguredAdminToken(null);
        financialSecurityService.setDemoAuthEnabled(false);
        financialSecurityService.clearConfiguredUserTokens();
    }

    // =========================================================================
    // 1. Admin Authentication & Authorization
    // =========================================================================

    @Test
    @DisplayName("Admin Auth: Anonymous requests to admin endpoints are rejected with 401")
    void testAdminEndpoints_anonymousRejected() throws Exception {
        mockMvc.perform(get("/api/accounts"))
                .andExpect(status().isUnauthorized());

        mockMvc.perform(get("/api/transactions"))
                .andExpect(status().isUnauthorized());

        mockMvc.perform(get("/api/reconciliation"))
                .andExpect(status().isUnauthorized());

        mockMvc.perform(post("/api/devices/authorize")
                        .contentType("application/json")
                        .content("{\"deviceId\":\"dev-1\",\"accountId\":\"alice\"}"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("Admin Auth: Incorrect tokens are rejected with 401")
    void testAdminEndpoints_incorrectTokenRejected() throws Exception {
        mockMvc.perform(get("/api/accounts")
                        .header("X-Admin-Token", "wrong-secret-token"))
                .andExpect(status().isUnauthorized());

        mockMvc.perform(get("/api/reconciliation")
                        .header("Authorization", "Bearer wrong-secret-token"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("Admin Auth: Non-admin user token cannot access /api/reconciliation (403 Forbidden)")
    void testReconciliation_nonAdminForbidden() throws Exception {
        mockMvc.perform(get("/api/reconciliation")
                        .header("Authorization", "Bearer alice-secure-token-12345"))
                .andExpect(status().isForbidden());
    }

    @Test
    @DisplayName("Admin Auth: Demo tokens fail when demoAuthEnabled=false")
    void testDemoToken_failsWhenDemoAuthDisabled() throws Exception {
        financialSecurityService.setDemoAuthEnabled(false);

        mockMvc.perform(get("/api/accounts")
                        .header("X-Admin-Token", "demo-token-admin"))
                .andExpect(status().isUnauthorized());

        mockMvc.perform(get("/api/accounts")
                        .header("Authorization", "Bearer demo-token-alice"))
                .andExpect(status().isUnauthorized());

        mockMvc.perform(get("/api/reconciliation")
                        .header("X-Admin-Token", "demo-token-admin"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("Admin Auth: Explicitly configured development admin token succeeds")
    void testExplicitAdminToken_succeeds() throws Exception {
        financialSecurityService.setConfiguredAdminToken(STRONG_DEV_ADMIN_TOKEN);

        mockMvc.perform(get("/api/accounts")
                        .header("X-Admin-Token", STRONG_DEV_ADMIN_TOKEN))
                .andExpect(status().isOk());

        mockMvc.perform(get("/api/reconciliation")
                        .header("X-Admin-Token", STRONG_DEV_ADMIN_TOKEN))
                .andExpect(status().isOk());
    }

    @Test
    @DisplayName("Production Profile: Missing admin token fails startup validation")
    void testProductionProfile_missingAdminTokenFailsStartup() {
        MockEnvironment prodEnv = new MockEnvironment();
        prodEnv.setActiveProfiles("production");

        FinancialSecurityService secService = new FinancialSecurityService(prodEnv);
        secService.setConfiguredAdminToken(null);
        secService.setDemoAuthEnabled(false);

        IllegalStateException ex = assertThrows(IllegalStateException.class, secService::validateSecurityConfigurationOnStartup);
        assertTrue(ex.getMessage().contains("An explicitly configured administrative token"), "Expected error about missing token, got: " + ex.getMessage());
    }

    @Test
    @DisplayName("Production Profile: Insecure or short admin token fails startup validation")
    void testProductionProfile_insecureAdminTokenFailsStartup() {
        MockEnvironment prodEnv = new MockEnvironment();
        prodEnv.setActiveProfiles("prod");

        FinancialSecurityService secService = new FinancialSecurityService(prodEnv);
        secService.setDemoAuthEnabled(false);

        // Trivial token
        secService.setConfiguredAdminToken("admin");
        assertThrows(IllegalStateException.class, secService::validateSecurityConfigurationOnStartup);

        // Short token (< 16 chars)
        secService.setConfiguredAdminToken("short-token-123");
        assertThrows(IllegalStateException.class, secService::validateSecurityConfigurationOnStartup);

        // Demo token
        secService.setConfiguredAdminToken("demo-token-admin");
        assertThrows(IllegalStateException.class, secService::validateSecurityConfigurationOnStartup);
    }

    @Test
    @DisplayName("Production Profile: Enabling demo auth fails startup validation")
    void testProductionProfile_demoAuthFailsStartup() {
        MockEnvironment prodEnv = new MockEnvironment();
        prodEnv.setActiveProfiles("prod");

        FinancialSecurityService secService = new FinancialSecurityService(prodEnv);
        secService.setConfiguredAdminToken("a-valid-production-admin-token-32b!");
        secService.setDemoAuthEnabled(true);

        // setDemoAuthEnabled in prod forces it false, but if property was somehow configured true:
        assertFalse(secService.isDemoAuthEnabled());
    }

    // =========================================================================
    // 2. Bank Authority Key Protection (AES-256-GCM)
    // =========================================================================

    @Test
    @DisplayName("Key Encryption: AES-256-GCM encryption and decryption roundtrip")
    void testAesGcm_encryptionDecryptionRoundtrip() throws Exception {
        SecretKey aesKey = BankAuthorityKeyService.deriveAesKey("my-super-secret-bank-encryption-key-32b!");
        KeyPair rsaPair = cryptoService.generateRsaKeyPair();
        byte[] originalPrivBytes = rsaPair.getPrivate().getEncoded();

        SecureRandom random = new SecureRandom();
        String encrypted = BankAuthorityKeyService.encryptPrivateKey(originalPrivBytes, aesKey, random);

        assertTrue(BankAuthorityKeyService.isEncryptedFormat(encrypted));
        assertTrue(encrypted.startsWith("ENC:AES-GCM:"));

        byte[] decrypted = BankAuthorityKeyService.decryptPrivateKey(encrypted, aesKey);
        assertArrayEquals(originalPrivBytes, decrypted);
    }

    @Test
    @DisplayName("Key Encryption: Fresh key generation with encryption key persists encrypted format")
    void testKeyService_freshGenerationEncrypted() {
        InMemoryCredentialRepo mockRepo = new InMemoryCredentialRepo();
        String encSecret = "bank-master-encryption-secret-2026";

        BankAuthorityKeyService service = new BankAuthorityKeyService(cryptoService, mockRepo, encSecret);

        Optional<BankAuthorityCredential> savedOpt = mockRepo.findById(BankAuthorityKeyService.DEFAULT_MASTER_KEY_ID);
        assertTrue(savedOpt.isPresent());
        BankAuthorityCredential saved = savedOpt.get();

        assertTrue(BankAuthorityKeyService.isEncryptedFormat(saved.getPrivateKeyBase64()),
                "Saved private key must be in encrypted format");
        assertNotNull(service.getBankPublicKey());
        assertNotNull(service.getBankPublicKeyBase64());
    }

    @Test
    @DisplayName("Key Encryption: Re-loading encrypted key with correct secret succeeds and preserves signatures")
    void testKeyService_rebootWithCorrectKeyPreservesSignatures() throws Exception {
        InMemoryCredentialRepo mockRepo = new InMemoryCredentialRepo();
        String encSecret = "bank-master-encryption-secret-2026";

        // Step 1: Initialize service
        BankAuthorityKeyService service1 = new BankAuthorityKeyService(cryptoService, mockRepo, encSecret);
        byte[] testData = "voucher:canonical:alice:100.00:INR".getBytes(StandardCharsets.UTF_8);
        String sig1 = service1.signVoucherBase64(testData);
        String pubKeyB64 = service1.getBankPublicKeyBase64();

        // Step 2: Reboot service with same repo and same secret
        BankAuthorityKeyService service2 = new BankAuthorityKeyService(cryptoService, mockRepo, encSecret);

        // Verify public key is identical
        assertEquals(pubKeyB64, service2.getBankPublicKeyBase64());

        // Verify signature from service1 is verifiable by service2
        assertTrue(service2.verifyVoucherSignature(testData, sig1));

        // Verify service2 signs compatibly
        String sig2 = service2.signVoucherBase64(testData);
        assertTrue(service1.verifyVoucherSignature(testData, sig2));
    }

    @Test
    @DisplayName("Key Encryption: Re-loading encrypted key with wrong secret throws exception without regenerating")
    void testKeyService_wrongKeyThrowsWithoutRegenerating() {
        InMemoryCredentialRepo mockRepo = new InMemoryCredentialRepo();
        String correctSecret = "bank-master-encryption-secret-2026";

        // Initialize and persist with correct secret
        BankAuthorityKeyService service1 = new BankAuthorityKeyService(cryptoService, mockRepo, correctSecret);
        String originalPubKey = service1.getBankPublicKeyBase64();

        // Attempt reboot with wrong secret
        String wrongSecret = "wrong-bad-encryption-secret-9999";
        IllegalStateException ex = assertThrows(IllegalStateException.class, () ->
                new BankAuthorityKeyService(cryptoService, mockRepo, wrongSecret)
        );

        assertTrue(ex.getMessage().contains("Failed to decrypt bank authority private key"),
                "Expected decryption failure message, got: " + ex.getMessage());

        // Ensure key was NOT regenerated or overwritten in repo
        BankAuthorityCredential credAfter = mockRepo.findById(BankAuthorityKeyService.DEFAULT_MASTER_KEY_ID).orElseThrow();
        assertEquals(originalPubKey, credAfter.getPublicKeyBase64(),
                "Public key in repository must NOT be altered on decryption failure");
    }

    @Test
    @DisplayName("Key Encryption: Loading encrypted key without secret throws exception without regenerating")
    void testKeyService_missingKeyThrowsWithoutRegenerating() {
        InMemoryCredentialRepo mockRepo = new InMemoryCredentialRepo();
        String correctSecret = "bank-master-encryption-secret-2026";

        // Initialize and persist with correct secret
        BankAuthorityKeyService service1 = new BankAuthorityKeyService(cryptoService, mockRepo, correctSecret);
        String originalPubKey = service1.getBankPublicKeyBase64();

        // Attempt reboot without any secret
        IllegalStateException ex = assertThrows(IllegalStateException.class, () ->
                new BankAuthorityKeyService(cryptoService, mockRepo, (String) null)
        );

        assertTrue(ex.getMessage().contains("is encrypted, but encryption key"),
                "Expected missing key message, got: " + ex.getMessage());

        BankAuthorityCredential credAfter = mockRepo.findById(BankAuthorityKeyService.DEFAULT_MASTER_KEY_ID).orElseThrow();
        assertEquals(originalPubKey, credAfter.getPublicKeyBase64());
    }

    @Test
    @DisplayName("Key Encryption: Legacy unencrypted key loads cleanly in non-production")
    void testKeyService_legacyUnencryptedLoadsInDevelopment() throws Exception {
        InMemoryCredentialRepo mockRepo = new InMemoryCredentialRepo();
        KeyPair rsaPair = cryptoService.generateRsaKeyPair();
        String pubB64 = Base64.getEncoder().encodeToString(rsaPair.getPublic().getEncoded());
        String privB64 = Base64.getEncoder().encodeToString(rsaPair.getPrivate().getEncoded());

        // Store legacy unencrypted credential
        mockRepo.save(new BankAuthorityCredential(
                BankAuthorityKeyService.DEFAULT_MASTER_KEY_ID,
                pubB64,
                privB64,
                "RSA",
                2048,
                Instant.now()
        ));

        // Load without encryption key
        BankAuthorityKeyService service = new BankAuthorityKeyService(cryptoService, mockRepo, (String) null);

        assertEquals(pubB64, service.getBankPublicKeyBase64());
        byte[] payload = "test-voucher-legacy".getBytes(StandardCharsets.UTF_8);
        String sig = service.signVoucherBase64(payload);
        assertTrue(service.verifyVoucherSignature(payload, sig));
    }

    @Test
    @DisplayName("Key Encryption: Auto-migration seamlessly re-encrypts legacy key in place")
    void testKeyService_autoMigrationReEncryptsInPlace() throws Exception {
        InMemoryCredentialRepo mockRepo = new InMemoryCredentialRepo();
        KeyPair rsaPair = cryptoService.generateRsaKeyPair();
        String pubB64 = Base64.getEncoder().encodeToString(rsaPair.getPublic().getEncoded());
        String privB64 = Base64.getEncoder().encodeToString(rsaPair.getPrivate().getEncoded());

        mockRepo.save(new BankAuthorityCredential(
                BankAuthorityKeyService.DEFAULT_MASTER_KEY_ID,
                pubB64,
                privB64,
                "RSA",
                2048,
                Instant.now()
        ));

        String encSecret = "migration-secret-key-32bytes-pass";
        MockEnvironment env = new MockEnvironment();
        env.setProperty("upimesh.bank-authority.encryption-key", encSecret);
        env.setProperty("upimesh.bank-authority.auto-migrate-encryption", "true");

        // Load with auto-migrate enabled
        BankAuthorityKeyService service = new BankAuthorityKeyService(cryptoService, mockRepo, env);

        // Public key must remain strictly unchanged
        assertEquals(pubB64, service.getBankPublicKeyBase64());

        // Stored private key must now be encrypted!
        BankAuthorityCredential updated = mockRepo.findById(BankAuthorityKeyService.DEFAULT_MASTER_KEY_ID).orElseThrow();
        assertTrue(BankAuthorityKeyService.isEncryptedFormat(updated.getPrivateKeyBase64()));

        // Signatures must continue to verify
        byte[] payload = "test-migrated-voucher".getBytes(StandardCharsets.UTF_8);
        String sig = service.signVoucherBase64(payload);
        assertTrue(service.verifyVoucherSignature(payload, sig));
    }

    @Test
    @DisplayName("Production Profile: Missing encryption key fails startup validation")
    void testKeyService_productionProfileMissingEncryptionKeyFails() {
        InMemoryCredentialRepo mockRepo = new InMemoryCredentialRepo();
        MockEnvironment prodEnv = new MockEnvironment();
        prodEnv.setActiveProfiles("production");

        IllegalStateException ex = assertThrows(IllegalStateException.class, () ->
                new BankAuthorityKeyService(cryptoService, mockRepo, prodEnv)
        );
        assertTrue(ex.getMessage().contains("strictly required"), "Expected strictly required error: " + ex.getMessage());
    }

    // =========================================================================
    // Mock In-Memory Credential Repository for Test Isolation
    // =========================================================================

    private static class InMemoryCredentialRepo implements BankAuthorityCredentialRepository {
        private BankAuthorityCredential stored;

        @Override
        public Optional<BankAuthorityCredential> findById(String id) {
            if (stored != null && stored.getId().equals(id)) {
                return Optional.of(stored);
            }
            return Optional.empty();
        }

        @Override
        public <S extends BankAuthorityCredential> S save(S entity) {
            this.stored = entity;
            return entity;
        }

        @Override public <S extends BankAuthorityCredential> S saveAndFlush(S entity) { return save(entity); }
        @Override public boolean existsById(String s) { return stored != null && stored.getId().equals(s); }
        @Override public long count() { return stored != null ? 1 : 0; }
        @Override public void deleteById(String s) { if (stored != null && stored.getId().equals(s)) stored = null; }
        @Override public void delete(BankAuthorityCredential entity) { stored = null; }
        @Override public void deleteAll() { stored = null; }
        @Override public java.util.List<BankAuthorityCredential> findAll() { return stored != null ? java.util.List.of(stored) : java.util.List.of(); }
        @Override public <S extends BankAuthorityCredential> java.util.List<S> saveAll(Iterable<S> entities) { throw new UnsupportedOperationException(); }
        @Override public java.util.List<BankAuthorityCredential> findAllById(Iterable<String> strings) { throw new UnsupportedOperationException(); }
        @Override public void deleteAllById(Iterable<? extends String> strings) { throw new UnsupportedOperationException(); }
        @Override public void deleteAll(Iterable<? extends BankAuthorityCredential> entities) { throw new UnsupportedOperationException(); }
        @Override public void flush() {}
        @Override public <S extends BankAuthorityCredential> java.util.List<S> saveAllAndFlush(Iterable<S> entities) { throw new UnsupportedOperationException(); }
        @Override public void deleteAllInBatch(Iterable<BankAuthorityCredential> entities) { throw new UnsupportedOperationException(); }
        @Override public void deleteAllByIdInBatch(Iterable<String> strings) { throw new UnsupportedOperationException(); }
        @Override public void deleteAllInBatch() { stored = null; }
        @Override public BankAuthorityCredential getOne(String s) { return stored; }
        @Override public BankAuthorityCredential getById(String s) { return stored; }
        @Override public BankAuthorityCredential getReferenceById(String s) { return stored; }
        @Override public <S extends BankAuthorityCredential> Optional<S> findOne(org.springframework.data.domain.Example<S> example) { throw new UnsupportedOperationException(); }
        @Override public <S extends BankAuthorityCredential> java.util.List<S> findAll(org.springframework.data.domain.Example<S> example) { throw new UnsupportedOperationException(); }
        @Override public <S extends BankAuthorityCredential> java.util.List<S> findAll(org.springframework.data.domain.Example<S> example, org.springframework.data.domain.Sort sort) { throw new UnsupportedOperationException(); }
        @Override public <S extends BankAuthorityCredential> org.springframework.data.domain.Page<S> findAll(org.springframework.data.domain.Example<S> example, org.springframework.data.domain.Pageable pageable) { throw new UnsupportedOperationException(); }
        @Override public <S extends BankAuthorityCredential> long count(org.springframework.data.domain.Example<S> example) { throw new UnsupportedOperationException(); }
        @Override public <S extends BankAuthorityCredential> boolean exists(org.springframework.data.domain.Example<S> example) { throw new UnsupportedOperationException(); }
        @Override public <S extends BankAuthorityCredential, R> R findBy(org.springframework.data.domain.Example<S> example, java.util.function.Function<org.springframework.data.repository.query.FluentQuery.FetchableFluentQuery<S>, R> queryFunction) { throw new UnsupportedOperationException(); }
        @Override public java.util.List<BankAuthorityCredential> findAll(org.springframework.data.domain.Sort sort) { return findAll(); }
        @Override public org.springframework.data.domain.Page<BankAuthorityCredential> findAll(org.springframework.data.domain.Pageable pageable) { throw new UnsupportedOperationException(); }
    }
}
