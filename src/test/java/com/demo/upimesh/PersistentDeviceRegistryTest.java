package com.demo.upimesh;

import com.demo.upimesh.model.Account;
import com.demo.upimesh.model.AccountRepository;
import com.demo.upimesh.model.DeviceAuthorizationRepository;
import com.demo.upimesh.model.MeshPaymentResult;
import com.demo.upimesh.model.PaymentInstruction;
import com.demo.upimesh.model.RegisteredDeviceKeyRepository;
import com.demo.upimesh.model.SignedPaymentRequest;
import com.demo.upimesh.model.TransactionRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.test.context.ActiveProfiles;

import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import java.math.BigDecimal;
import java.security.KeyPair;
import java.security.PublicKey;
import java.time.Instant;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;

@SpringBootTest
@ActiveProfiles("test")
public class PersistentDeviceRegistryTest {

    @Autowired
    private RegisteredDeviceKeyRepository registeredDeviceKeyRepository;

    @Autowired
    private DeviceAuthorizationRepository deviceAuthorizationRepository;

    @Autowired
    private AccountRepository accountRepository;

    @Autowired
    private TransactionRepository transactionRepository;

    @Autowired
    private SenderKeyRegistry senderKeyRegistry;

    @Autowired
    private DeviceAuthorizationRegistry deviceAuthorizationRegistry;

    @Autowired
    private ApiController apiController;

    @Autowired
    private CryptoService cryptoService;

    @Autowired
    private MeshSimulatorService meshSimulatorService;

    @Autowired
    private PlatformTransactionManager transactionManager;

    @BeforeEach
    void setUp() {
        accountRepository.deleteAll();
        transactionRepository.deleteAll();
        senderKeyRegistry.clearForTesting();
        deviceAuthorizationRegistry.clearForTesting();

        accountRepository.save(new Account("alice", new BigDecimal("5000.00")));
        accountRepository.save(new Account("bob", new BigDecimal("1000.00")));
        accountRepository.save(new Account("carol", new BigDecimal("2000.00")));
    }

    @Test
    @DisplayName("1. Persistence across registry reinitialization: public keys and authorizations preserved")
    void persistenceAcrossReinitialization_publicKeyAndAuthorizationPreserved() throws Exception {
        String deviceId = "iphone-persist-" + UUID.randomUUID();
        KeyPair keyPair = cryptoService.generateRsaKeyPair();

        // Register key and authorize
        boolean registered = senderKeyRegistry.registerKeyWithPolicy(deviceId, keyPair.getPublic());
        assertTrue(registered);
        deviceAuthorizationRegistry.authorizeDevice(deviceId, "alice");

        // Simulate application restart by creating fresh registry instances pointing to the same repositories
        SenderKeyRegistry restartedKeyRegistry = new SenderKeyRegistry(registeredDeviceKeyRepository);
        restartedKeyRegistry.init();

        DeviceAuthorizationRegistry restartedAuthRegistry = new DeviceAuthorizationRegistry(deviceAuthorizationRepository);
        restartedAuthRegistry.init();

        // Verify key survived restart
        assertTrue(restartedKeyRegistry.hasKey(deviceId));
        assertTrue(restartedKeyRegistry.getPublicKey(deviceId).isPresent());

        // Verify signature verification works with the restored public key
        byte[] testMessage = "TEST-PAYLOAD".getBytes();
        String signature = cryptoService.signBase64(testMessage, keyPair.getPrivate());
        assertTrue(cryptoService.verifySignatureBase64(testMessage, signature, restartedKeyRegistry.getPublicKey(deviceId).get()));

        // Verify authorization survived restart
        assertTrue(restartedAuthRegistry.isDeviceAuthorized(deviceId, "alice"));
        assertFalse(restartedAuthRegistry.isDeviceAuthorized(deviceId, "bob"));
    }

    @Test
    @DisplayName("2. Identical key re-registration succeeds idempotently")
    void identicalKeyReregistration_isIdempotent() throws Exception {
        String deviceId = "iphone-idemp-" + UUID.randomUUID();
        KeyPair keyPair = cryptoService.generateRsaKeyPair();

        // First registration
        boolean first = senderKeyRegistry.registerKeyWithPolicy(deviceId, keyPair.getPublic());
        assertTrue(first, "First registration should return true (newly registered)");

        // Second registration with identical key
        boolean second = senderKeyRegistry.registerKeyWithPolicy(deviceId, keyPair.getPublic());
        assertFalse(second, "Second registration with identical key should return false (already registered)");

        // Verify exactly one row in database
        assertEquals(1, registeredDeviceKeyRepository.count());
    }

    @Test
    @DisplayName("3. Different key for already-registered device is rejected")
    void differentKeyReregistration_isRejected() throws Exception {
        String deviceId = "iphone-reject-" + UUID.randomUUID();
        KeyPair keyPairA = cryptoService.generateRsaKeyPair();
        KeyPair keyPairB = cryptoService.generateRsaKeyPair();

        // First registration
        boolean first = senderKeyRegistry.registerKeyWithPolicy(deviceId, keyPairA.getPublic());
        assertTrue(first);

        // Second registration with different key
        IllegalStateException ex = assertThrows(IllegalStateException.class, () ->
                senderKeyRegistry.registerKeyWithPolicy(deviceId, keyPairB.getPublic())
        );
        assertTrue(ex.getMessage().contains("already registered with a different public key"));

        // Verify database still has original key
        assertTrue(senderKeyRegistry.getPublicKey(deviceId).isPresent());
        assertArrayEquals(keyPairA.getPublic().getEncoded(), senderKeyRegistry.getPublicKey(deviceId).get().getEncoded());
    }

    @Test
    @DisplayName("4. Duplicate authorization is idempotent and preserves uniqueness constraint")
    void duplicateAuthorization_isIdempotent() {
        String deviceId = "iphone-auth-dup-" + UUID.randomUUID();

        // First authorization
        deviceAuthorizationRegistry.authorizeDevice(deviceId, "alice");
        assertTrue(deviceAuthorizationRegistry.isDeviceAuthorized(deviceId, "alice"));
        assertEquals(1, deviceAuthorizationRepository.count());

        // Duplicate authorization
        deviceAuthorizationRegistry.authorizeDevice(deviceId, "alice");
        assertTrue(deviceAuthorizationRegistry.isDeviceAuthorized(deviceId, "alice"));
        assertEquals(1, deviceAuthorizationRepository.count(), "Duplicate authorization must not insert extra rows");
    }

    @Test
    @DisplayName("5. Device-signed payment succeeds after registry reinitialization")
    void signedPaymentSubmission_afterRegistryReinitialization_settlesAtomically() throws Exception {
        String deviceId = "iphone-cold-boot-" + UUID.randomUUID();
        KeyPair keyPair = cryptoService.generateRsaKeyPair();

        // Register and authorize
        senderKeyRegistry.registerKeyWithPolicy(deviceId, keyPair.getPublic());
        deviceAuthorizationRegistry.authorizeDevice(deviceId, "alice");

        // Simulate server restart by clearing in-memory caches and re-initializing from database
        senderKeyRegistry.init();
        deviceAuthorizationRegistry.init();

        // Construct canonical PaymentInstruction
        BigDecimal amount = new BigDecimal("250.00");
        PaymentInstruction unsigned = new PaymentInstruction(
                "pay-restart-" + UUID.randomUUID(),
                "alice",
                "bob",
                amount,
                Instant.now(),
                "nonce-" + UUID.randomUUID(),
                null
        );

        // Sign canonical bytes with device private key
        String signature = cryptoService.signBase64(unsigned.toCanonicalBytes(), keyPair.getPrivate());
        PaymentInstruction signed = unsigned.withSignature(signature);

        // Submit to API
        SignedPaymentRequest request = new SignedPaymentRequest(deviceId, signed);
        ResponseEntity<MeshPaymentResult> response = apiController.submitSignedMeshPayment(request);

        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertNotNull(response.getBody());
        assertEquals("SETTLED", response.getBody().status());

        // Verify ledger balances updated atomically
        Account alice = accountRepository.findById("alice").orElseThrow();
        Account bob = accountRepository.findById("bob").orElseThrow();
        assertEquals(new BigDecimal("4750.00"), alice.getBalance());
        assertEquals(new BigDecimal("1250.00"), bob.getBalance());
    }

    @Test
    @DisplayName("6. Virtual simulation nodes preserve identity authorization bypass")
    void virtualSimulationNode_identityAuthorizationBypassPreserved() {
        // deviceId == accountId ("alice" == "alice") bypasses explicit device authorization
        assertTrue(deviceAuthorizationRegistry.isDeviceAuthorized("alice", "alice"));
        assertTrue(deviceAuthorizationRegistry.isDeviceAuthorized("bob", "bob"));

        // deviceId != accountId without explicit authorization must be rejected
        assertFalse(deviceAuthorizationRegistry.isDeviceAuthorized("alice", "bob"));
        assertFalse(deviceAuthorizationRegistry.isDeviceAuthorized("rogue-id", "alice"));
    }

    @Test
    @DisplayName("7. Transaction rollback evicts uncommitted keys and authorizations from in-memory cache")
    void transactionRollback_evictsKeyAndAuthorizationFromCache() throws Exception {
        String deviceId = "iphone-tx-rollback-" + UUID.randomUUID();
        KeyPair keyPair = cryptoService.generateRsaKeyPair();
        TransactionTemplate txTemplate = new TransactionTemplate(transactionManager);

        assertThrows(RuntimeException.class, () -> {
            txTemplate.execute(status -> {
                senderKeyRegistry.registerKeyWithPolicy(deviceId, keyPair.getPublic());
                deviceAuthorizationRegistry.authorizeDevice(deviceId, "alice");

                // Verify cache is visible within the active transaction
                assertTrue(senderKeyRegistry.hasKey(deviceId));
                assertTrue(deviceAuthorizationRegistry.isDeviceAuthorized(deviceId, "alice"));

                // Force transaction rollback
                throw new RuntimeException("Simulated transaction rollback");
            });
        });

        // Verify database rolled back completely
        assertEquals(0, registeredDeviceKeyRepository.count(), "DB must have 0 registered keys after rollback");
        assertEquals(0, deviceAuthorizationRepository.count(), "DB must have 0 authorizations after rollback");

        // Verify in-memory cache was evicted by TransactionSynchronization
        assertFalse(senderKeyRegistry.hasKey(deviceId), "Cache must evict uncommitted key after rollback");
        assertFalse(senderKeyRegistry.getPublicKey(deviceId).isPresent(), "PublicKey must not be present in cache");
        assertFalse(deviceAuthorizationRegistry.isDeviceAuthorized(deviceId, "alice"), "Cache must evict uncommitted authorization after rollback");
    }

    @Test
    @DisplayName("8. Virtual simulation node registration cannot overwrite a persisted physical-device key")
    void simulationNodeRegistration_cannotOverwritePersistedKey() throws Exception {
        String deviceId = "iphone-sim-protect-" + UUID.randomUUID();
        KeyPair physicalKeyPair = cryptoService.generateRsaKeyPair();
        KeyPair virtualKeyPair = cryptoService.generateRsaKeyPair();

        // 1. Durably register physical key
        boolean registered = senderKeyRegistry.registerKeyWithPolicy(deviceId, physicalKeyPair.getPublic());
        assertTrue(registered);
        assertEquals(1, registeredDeviceKeyRepository.count());

        // 2. Virtual node attempts to overwrite using unpersisted registerKey()
        senderKeyRegistry.registerKey(deviceId, virtualKeyPair.getPublic());

        // 3. Verify physical key was preserved in both cache and DB
        PublicKey currentKey = senderKeyRegistry.getPublicKey(deviceId).orElseThrow();
        assertArrayEquals(physicalKeyPair.getPublic().getEncoded(), currentKey.getEncoded(),
                "Persisted key must NOT be overwritten by virtual simulation node registration");
    }

    @Test
    @DisplayName("9. Simulator reset does not delete persistent device registrations or authorizations")
    void simulatorReset_doesNotDeletePersistentKeysOrAuthorizations() throws Exception {
        String deviceId = "iphone-sim-reset-" + UUID.randomUUID();
        KeyPair keyPair = cryptoService.generateRsaKeyPair();

        // Register persistent device key and authorize
        senderKeyRegistry.registerKeyWithPolicy(deviceId, keyPair.getPublic());
        deviceAuthorizationRegistry.authorizeDevice(deviceId, "alice");

        assertEquals(1, registeredDeviceKeyRepository.count());
        assertEquals(1, deviceAuthorizationRepository.count());

        // Reset simulator
        meshSimulatorService.reset();

        // Verify persistent records and cache are intact
        assertEquals(1, registeredDeviceKeyRepository.count(), "Durable keys must NOT be deleted by simulator reset");
        assertEquals(1, deviceAuthorizationRepository.count(), "Durable authorizations must NOT be deleted by simulator reset");
        assertTrue(senderKeyRegistry.hasKey(deviceId), "Persistent key must remain cached/accessible after simulator reset");
        assertTrue(deviceAuthorizationRegistry.isDeviceAuthorized(deviceId, "alice"), "Authorization must remain valid after simulator reset");
    }
}
