package com.demo.upimesh;

import com.demo.upimesh.model.Account;
import com.demo.upimesh.model.AccountRepository;
import com.demo.upimesh.model.BridgePublicKeyResponse;
import com.demo.upimesh.model.KeyRegistrationRequest;
import com.demo.upimesh.model.KeyRegistrationResponse;
import com.demo.upimesh.model.MeshIngestResult;
import com.demo.upimesh.model.MeshPacket;
import com.demo.upimesh.model.PaymentInstruction;
import com.demo.upimesh.model.ProcessedPacketRepository;
import com.demo.upimesh.model.TransactionRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import java.math.BigDecimal;
import java.security.GeneralSecurityException;
import java.security.KeyFactory;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.PublicKey;
import java.security.interfaces.RSAPublicKey;
import java.security.spec.X509EncodedKeySpec;
import java.time.Instant;
import java.util.Base64;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Test suite for Milestone 1: Backend Integration Layer.
 * <p>
 * Verifies:
 * 1. GET /api/bridge/public-key returns valid X.509 Base64-encoded 2048-bit RSA public key.
 * 2. POST /api/keys/register handles valid registration, duplicate idempotency, and rejects arbitrary replacement.
 * 3. POST /api/keys/register rejects malformed, non-RSA, short (<2048 bits), and blank inputs.
 * 4. POST /api/mesh/ingest ingests valid externally-constructed MeshPackets, performing decryption,
 *    signature verification, and atomic database settlement.
 * 5. POST /api/mesh/ingest rejects duplicates, replayed nonces, tampered signatures, corrupted ciphertexts,
 *    expired instructions, and insufficient funds without altering account balances or the transaction ledger.
 */
@SpringBootTest
class BackendIntegrationLayerTest {

    @Autowired
    private ApiController apiController;

    @Autowired
    private BridgeIngestionService bridgeIngestionService;

    @Autowired
    private MeshSimulatorService meshSimulatorService;

    @Autowired
    private CryptoService cryptoService;

    @Autowired
    private SenderKeyRegistry senderKeyRegistry;

    @Autowired
    private AccountRepository accountRepository;

    @Autowired
    private TransactionRepository transactionRepository;

    @Autowired
    private ProcessedPacketRepository processedPacketRepository;

    private KeyPair aliceKeyPair;
    private KeyPair bobKeyPair;

    @BeforeEach
    void setUp() throws GeneralSecurityException {
        processedPacketRepository.deleteAll();
        transactionRepository.deleteAll();
        accountRepository.deleteAll();

        accountRepository.saveAll(List.of(
                new Account("alice", new BigDecimal("5000.00")),
                new Account("bob", new BigDecimal("1000.00")),
                new Account("carol", new BigDecimal("2000.00"))
        ));

        meshSimulatorService.reset();
        meshSimulatorService.initDefaultTopology();

        aliceKeyPair = cryptoService.generateRsaKeyPair();
        bobKeyPair = cryptoService.generateRsaKeyPair();

        meshSimulatorService.registerSenderKeyPair("alice", aliceKeyPair);
        meshSimulatorService.registerSenderKeyPair("bob", bobKeyPair);
    }

    private MeshPacket createExternalMeshPacket(
            String from,
            String to,
            BigDecimal amount,
            KeyPair signerKey,
            PublicKey bridgePubKey
    ) throws GeneralSecurityException {
        PaymentInstruction unsigned = PaymentInstruction.create(from, to, amount);
        String sig = cryptoService.signBase64(unsigned.toCanonicalBytes(), signerKey.getPrivate());
        PaymentInstruction signed = unsigned.withSignature(sig);

        String json = bridgeIngestionService.serializeInstruction(signed);
        EncryptedPacket encryptedPacket = cryptoService.encrypt(json, bridgePubKey);
        return MeshPacket.create("ios_client_node_1", "BRIDGE", 5, encryptedPacket);
    }

    // ---------------------------------------------------------------------------------------------
    // Capability 1: GET /api/bridge/public-key
    // ---------------------------------------------------------------------------------------------

    @Test
    @DisplayName("1.1 GET /api/bridge/public-key returns valid X.509 Base64-encoded RSA public key")
    void getBridgePublicKey_success() throws Exception {
        ResponseEntity<BridgePublicKeyResponse> response = apiController.getBridgePublicKey();

        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertNotNull(response.getBody());

        BridgePublicKeyResponse body = response.getBody();
        assertEquals("RSA", body.algorithm());
        assertEquals("X.509", body.format());
        assertNotNull(body.publicKey());
        assertFalse(body.publicKey().isBlank());

        // Validate that the Base64 string reconstructs into a genuine 2048-bit RSAPublicKey
        byte[] keyBytes = Base64.getDecoder().decode(body.publicKey());
        KeyFactory keyFactory = KeyFactory.getInstance("RSA");
        PublicKey reconstructed = keyFactory.generatePublic(new X509EncodedKeySpec(keyBytes));

        assertTrue(reconstructed instanceof RSAPublicKey);
        RSAPublicKey rsaPubKey = (RSAPublicKey) reconstructed;
        assertEquals(2048, rsaPubKey.getModulus().bitLength());

        // Reconstructed key must match the bridge's actual public key
        PublicKey activeBridgeKey = meshSimulatorService.getBridgePublicKey();
        assertArrayEquals(activeBridgeKey.getEncoded(), reconstructed.getEncoded());
    }

    // ---------------------------------------------------------------------------------------------
    // Capability 2: POST /api/keys/register
    // ---------------------------------------------------------------------------------------------

    @Test
    @DisplayName("2.1 POST /api/keys/register successfully registers a new sender RSA public key")
    void registerSenderKey_validRegistration() throws Exception {
        KeyPair davidKeyPair = cryptoService.generateRsaKeyPair();
        String base64Key = Base64.getEncoder().encodeToString(davidKeyPair.getPublic().getEncoded());

        KeyRegistrationRequest request = new KeyRegistrationRequest("david", base64Key);
        ResponseEntity<KeyRegistrationResponse> response = apiController.registerSenderKey(request, null, null);

        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertNotNull(response.getBody());
        assertEquals("REGISTERED", response.getBody().status());
        assertEquals("david", response.getBody().accountId());

        // Verify key is now present in the trusted registry
        assertTrue(senderKeyRegistry.hasKey("david"));
        assertArrayEquals(davidKeyPair.getPublic().getEncoded(), senderKeyRegistry.getPublicKey("david").orElseThrow().getEncoded());
    }

    @Test
    @DisplayName("2.2 POST /api/keys/register duplicate re-registration with same key is idempotent")
    void registerSenderKey_duplicateSameKeyIsIdempotent() throws Exception {
        KeyPair davidKeyPair = cryptoService.generateRsaKeyPair();
        String base64Key = Base64.getEncoder().encodeToString(davidKeyPair.getPublic().getEncoded());

        KeyRegistrationRequest request = new KeyRegistrationRequest("david", base64Key);
        ResponseEntity<KeyRegistrationResponse> resp1 = apiController.registerSenderKey(request, null, null);
        assertEquals("REGISTERED", resp1.getBody().status());

        // Re-registering the same key for the same account must succeed idempotently
        ResponseEntity<KeyRegistrationResponse> resp2 = apiController.registerSenderKey(request, null, null);
        assertEquals(HttpStatus.OK, resp2.getStatusCode());
        assertEquals("ALREADY_REGISTERED", resp2.getBody().status());
        assertEquals("david", resp2.getBody().accountId());
    }

    @Test
    @DisplayName("2.3 POST /api/keys/register rejects arbitrary key replacement with a different key")
    void registerSenderKey_rejectsDifferentKeyReplacement() throws Exception {
        KeyPair key1 = cryptoService.generateRsaKeyPair();
        KeyPair key2 = cryptoService.generateRsaKeyPair();

        String base64Key1 = Base64.getEncoder().encodeToString(key1.getPublic().getEncoded());
        String base64Key2 = Base64.getEncoder().encodeToString(key2.getPublic().getEncoded());

        KeyRegistrationRequest req1 = new KeyRegistrationRequest("david", base64Key1);
        apiController.registerSenderKey(req1, null, null);

        // Attempting to register key2 for david must be rejected
        KeyRegistrationRequest req2 = new KeyRegistrationRequest("david", base64Key2);
        IllegalStateException ex = assertThrows(IllegalStateException.class, () ->
                apiController.registerSenderKey(req2, null, null)
        );

        assertTrue(ex.getMessage().contains("Arbitrary key replacement is forbidden"));

        // Exception handler translates to HTTP 400 Bad Request
        ResponseEntity<String> errorResp = apiController.handleIllegalState(ex);
        assertEquals(HttpStatus.BAD_REQUEST, errorResp.getStatusCode());
        assertTrue(errorResp.getBody().contains("Arbitrary key replacement is forbidden"));

        // Existing key remains unmodified
        assertArrayEquals(key1.getPublic().getEncoded(), senderKeyRegistry.getPublicKey("david").orElseThrow().getEncoded());
    }

    @Test
    @DisplayName("2.4 POST /api/keys/register rejects blank or null accountId and publicKey")
    void registerSenderKey_rejectsBlankInputs() {
        IllegalArgumentException ex1 = assertThrows(IllegalArgumentException.class, () ->
                apiController.registerSenderKey(new KeyRegistrationRequest("", "some-key"), null, null)
        );
        assertTrue(ex1.getMessage().contains("Account ID must not be blank"));

        IllegalArgumentException ex2 = assertThrows(IllegalArgumentException.class, () ->
                apiController.registerSenderKey(new KeyRegistrationRequest("david", "   "), null, null)
        );
        assertTrue(ex2.getMessage().contains("Public key must not be blank"));
    }

    @Test
    @DisplayName("2.5 POST /api/keys/register rejects malformed Base64")
    void registerSenderKey_rejectsMalformedBase64() {
        KeyRegistrationRequest request = new KeyRegistrationRequest("david", "not-a-valid-base64!!!");
        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () ->
                apiController.registerSenderKey(request, null, null)
        );
        assertTrue(ex.getMessage().contains("Public key must be valid Base64"));
    }

    @Test
    @DisplayName("2.6 POST /api/keys/register rejects corrupt non-RSA key bytes")
    void registerSenderKey_rejectsCorruptKeyBytes() {
        String invalidKeyBytesBase64 = Base64.getEncoder().encodeToString(new byte[]{1, 2, 3, 4, 5, 6, 7, 8});
        KeyRegistrationRequest request = new KeyRegistrationRequest("david", invalidKeyBytesBase64);
        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () ->
                apiController.registerSenderKey(request, null, null)
        );
        assertTrue(ex.getMessage().contains("Invalid RSA public key specification"));
    }

    @Test
    @DisplayName("2.7 POST /api/keys/register rejects short RSA keys (< 2048 bits)")
    void registerSenderKey_rejectsShortRsaKeys() throws Exception {
        KeyPairGenerator kpg = KeyPairGenerator.getInstance("RSA");
        kpg.initialize(1024);
        KeyPair shortKeyPair = kpg.generateKeyPair();
        String base64ShortKey = Base64.getEncoder().encodeToString(shortKeyPair.getPublic().getEncoded());

        KeyRegistrationRequest request = new KeyRegistrationRequest("david", base64ShortKey);
        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () ->
                apiController.registerSenderKey(request, null, null)
        );
        assertTrue(ex.getMessage().contains("at least 2048 bits"));
    }

    // ---------------------------------------------------------------------------------------------
    // Capability 3: POST /api/mesh/ingest
    // ---------------------------------------------------------------------------------------------

    @Test
    @DisplayName("3.1 POST /api/mesh/ingest settles valid externally-constructed MeshPacket")
    void ingestMeshPacket_validPacketSettlesSuccessfully() throws Exception {
        PublicKey bridgeKey = meshSimulatorService.getBridgePublicKey();
        MeshPacket packet = createExternalMeshPacket("alice", "bob", new BigDecimal("350.00"), aliceKeyPair, bridgeKey);

        ResponseEntity<MeshIngestResult> response = apiController.ingestMeshPacket(packet);

        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertNotNull(response.getBody());
        MeshIngestResult result = response.getBody();
        assertTrue(result.success());
        assertEquals("SETTLED", result.status());
        assertEquals("alice", result.fromAccount());
        assertEquals("bob", result.toAccount());
        assertEquals(new BigDecimal("350.00"), result.amount());
        assertEquals(packet.packetId(), result.packetId());

        // Verify balances in database
        assertEquals(new BigDecimal("4650.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1350.00"), accountRepository.findById("bob").orElseThrow().getBalance());

        // Verify transaction ledger
        assertEquals(1, transactionRepository.count());
        assertEquals(new BigDecimal("350.00"), transactionRepository.findAll().get(0).getAmount());

        // Verify processed packet idempotency record
        assertEquals(1, processedPacketRepository.count());
    }

    @Test
    @DisplayName("3.2 POST /api/mesh/ingest rejects duplicate packet replay without altering balances")
    void ingestMeshPacket_rejectsDuplicateReplay() throws Exception {
        PublicKey bridgeKey = meshSimulatorService.getBridgePublicKey();
        MeshPacket packet = createExternalMeshPacket("alice", "bob", new BigDecimal("200.00"), aliceKeyPair, bridgeKey);

        // First ingestion succeeds
        ResponseEntity<MeshIngestResult> resp1 = apiController.ingestMeshPacket(packet);
        assertEquals(HttpStatus.OK, resp1.getStatusCode());
        assertEquals(new BigDecimal("4800.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1200.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(1, transactionRepository.count());

        // Second ingestion of the identical packet must be rejected
        DuplicatePacketException ex = assertThrows(DuplicatePacketException.class, () ->
                apiController.ingestMeshPacket(packet)
        );
        assertTrue(ex.getMessage().contains("Duplicate packet rejected"));

        ResponseEntity<String> errorResp = apiController.handleDuplicatePacket(ex);
        assertEquals(HttpStatus.BAD_REQUEST, errorResp.getStatusCode());

        // Balances and ledger must remain untouched
        assertEquals(new BigDecimal("4800.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1200.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(1, transactionRepository.count());
    }

    @Test
    @DisplayName("3.3 POST /api/mesh/ingest rejects tampered signature without altering balances")
    void ingestMeshPacket_rejectsTamperedSignature() throws Exception {
        PublicKey bridgeKey = meshSimulatorService.getBridgePublicKey();

        PaymentInstruction unsigned = PaymentInstruction.create("alice", "bob", new BigDecimal("100.00"));
        // Alice claim, but signed by Bob's private key (forgery)
        String forgedSignature = cryptoService.signBase64(unsigned.toCanonicalBytes(), bobKeyPair.getPrivate());
        PaymentInstruction forgedInstruction = unsigned.withSignature(forgedSignature);

        String json = bridgeIngestionService.serializeInstruction(forgedInstruction);
        EncryptedPacket encryptedPacket = cryptoService.encrypt(json, bridgeKey);
        MeshPacket forgedPacket = MeshPacket.create("ios_attacker", "BRIDGE", 5, encryptedPacket);

        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () ->
                apiController.ingestMeshPacket(forgedPacket)
        );
        assertTrue(ex.getMessage().contains("Invalid digital signature for sender: alice"));

        ResponseEntity<String> errorResp = apiController.handleBadRequest(ex);
        assertEquals(HttpStatus.BAD_REQUEST, errorResp.getStatusCode());

        // Balances and ledger completely unaltered
        assertEquals(new BigDecimal("5000.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1000.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(0, transactionRepository.count());
        assertEquals(0, processedPacketRepository.count());
    }

    @Test
    @DisplayName("3.4 POST /api/mesh/ingest rejects corrupted ciphertext without altering balances")
    void ingestMeshPacket_rejectsCorruptedCiphertext() throws Exception {
        PublicKey bridgeKey = meshSimulatorService.getBridgePublicKey();
        MeshPacket validPacket = createExternalMeshPacket("alice", "bob", new BigDecimal("100.00"), aliceKeyPair, bridgeKey);

        // Corrupt ciphertext byte
        byte[] corruptedCiphertext = validPacket.payload().ciphertext().clone();
        corruptedCiphertext[0] ^= 0xFF;

        EncryptedPacket corruptedPayload = new EncryptedPacket(
                validPacket.payload().encryptedAesKey(),
                validPacket.payload().iv(),
                corruptedCiphertext
        );
        MeshPacket corruptedPacket = new MeshPacket(
                validPacket.packetId(),
                validPacket.originDeviceId(),
                validPacket.destination(),
                validPacket.ttl(),
                validPacket.hopCount(),
                corruptedPayload
        );

        GeneralSecurityException ex = assertThrows(GeneralSecurityException.class, () ->
                apiController.ingestMeshPacket(corruptedPacket)
        );
        ResponseEntity<String> errorResp = apiController.handleSecurityException(ex);
        assertEquals(HttpStatus.BAD_REQUEST, errorResp.getStatusCode());
        assertTrue(errorResp.getBody().contains("Cryptographic verification failed"));

        // Balances and ledger unaltered
        assertEquals(new BigDecimal("5000.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1000.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(0, transactionRepository.count());
        assertEquals(0, processedPacketRepository.count());
    }

    @Test
    @DisplayName("3.5 POST /api/mesh/ingest rejects expired payment instruction without altering balances")
    void ingestMeshPacket_rejectsExpiredInstruction() throws Exception {
        PublicKey bridgeKey = meshSimulatorService.getBridgePublicKey();

        PaymentInstruction expired = new PaymentInstruction(
                "expired-id-1",
                "alice",
                "bob",
                new BigDecimal("50.00"),
                Instant.now().minusSeconds(25 * 3600), // 25 hours ago
                "nonce-expired-1",
                null
        );
        String sig = cryptoService.signBase64(expired.toCanonicalBytes(), aliceKeyPair.getPrivate());
        PaymentInstruction signedExpired = expired.withSignature(sig);

        String json = bridgeIngestionService.serializeInstruction(signedExpired);
        EncryptedPacket encryptedPacket = cryptoService.encrypt(json, bridgeKey);
        MeshPacket packet = MeshPacket.create("ios_client", "BRIDGE", 5, encryptedPacket);

        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () ->
                apiController.ingestMeshPacket(packet)
        );
        assertTrue(ex.getMessage().contains("Payment instruction has expired"));

        assertEquals(new BigDecimal("5000.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1000.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(0, transactionRepository.count());
    }

    @Test
    @DisplayName("3.6 POST /api/mesh/ingest rejects insufficient funds without altering balances")
    void ingestMeshPacket_rejectsInsufficientFunds() throws Exception {
        PublicKey bridgeKey = meshSimulatorService.getBridgePublicKey();
        // Alice has 5000.00, attempting to transfer 9000.00
        MeshPacket packet = createExternalMeshPacket("alice", "bob", new BigDecimal("9000.00"), aliceKeyPair, bridgeKey);

        IllegalStateException ex = assertThrows(IllegalStateException.class, () ->
                apiController.ingestMeshPacket(packet)
        );
        assertTrue(ex.getMessage().contains("Insufficient funds"));

        assertEquals(new BigDecimal("5000.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1000.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(0, transactionRepository.count());
    }

    @Test
    @DisplayName("3.7 POST /api/mesh/ingest rejects null packet and null payload")
    void ingestMeshPacket_rejectsNullInputs() {
        IllegalArgumentException ex1 = assertThrows(IllegalArgumentException.class, () ->
                apiController.ingestMeshPacket(null)
        );
        assertEquals("MeshPacket must not be null", ex1.getMessage());
    }
}
