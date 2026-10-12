package com.demo.upimesh;

import com.demo.upimesh.model.Account;
import com.demo.upimesh.model.AccountRepository;
import com.demo.upimesh.model.MeshPacket;
import com.demo.upimesh.model.MeshPaymentResult;
import com.demo.upimesh.model.PaymentInstruction;
import com.demo.upimesh.model.Transaction;
import com.demo.upimesh.model.TransactionRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import java.math.BigDecimal;
import java.security.GeneralSecurityException;
import java.security.KeyPair;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Test suite verifying cryptographic sender authentication for UPI Offline Mesh (Stage 11.1).
 * <p>
 * Ensures:
 * - Deterministic RSA-PSS SHA-256 signatures are verified before any balance mutation or ledger insertion.
 * - Modifications to amount, recipient, nonce, or timestamp invalidate the signature and reject the transfer.
 * - Missing, unknown, or mismatched sender keys are rejected.
 * - Failed signature checks leave account balances and transaction ledger completely unaltered.
 */
@SpringBootTest
class SenderAuthenticationTest {

    @Autowired
    private BridgeIngestionService bridgeIngestionService;

    @Autowired
    private CryptoService cryptoService;

    @Autowired
    private SenderKeyRegistry senderKeyRegistry;

    @Autowired
    private SettlementService settlementService;

    @Autowired
    private MeshSimulatorService meshSimulatorService;

    @Autowired
    private AccountRepository accountRepository;

    @Autowired
    private TransactionRepository transactionRepository;

    private KeyPair bridgeKeyPair;
    private KeyPair aliceKeyPair;
    private KeyPair bobKeyPair;
    private KeyPair malloryKeyPair;

    @BeforeEach
    void setUp() throws GeneralSecurityException {
        // Reset database state
        transactionRepository.deleteAll();
        accountRepository.deleteAll();
        accountRepository.saveAll(List.of(
                new Account("alice", new BigDecimal("5000.00")),
                new Account("bob", new BigDecimal("1000.00")),
                new Account("carol", new BigDecimal("2000.00"))
        ));

        // Reset simulator and initialize topology
        meshSimulatorService.reset();
        meshSimulatorService.initDefaultTopology();

        // Use the simulator's bridge key pair or generate fresh
        bridgeKeyPair = meshSimulatorService.getBridgeKeyPair();
        if (bridgeKeyPair == null) {
            bridgeKeyPair = cryptoService.generateRsaKeyPair();
            meshSimulatorService.setBridgeKeyPair(bridgeKeyPair);
        }

        // Generate fresh test sender key pairs and register in simulator and registry
        aliceKeyPair = cryptoService.generateRsaKeyPair();
        bobKeyPair = cryptoService.generateRsaKeyPair();
        malloryKeyPair = cryptoService.generateRsaKeyPair();

        meshSimulatorService.registerSenderKeyPair("alice", aliceKeyPair);
        meshSimulatorService.registerSenderKeyPair("bob", bobKeyPair);
    }

    private MeshPacket createEncryptedMeshPacket(PaymentInstruction instruction) throws GeneralSecurityException {
        String json = bridgeIngestionService.serializeInstruction(instruction);
        EncryptedPacket encryptedPacket = cryptoService.encrypt(json, bridgeKeyPair.getPublic());
        return MeshPacket.create("device_sim_node", "BRIDGE", 5, encryptedPacket);
    }

    private PaymentInstruction createSignedInstruction(String from, String to, BigDecimal amount, KeyPair signerKey) throws GeneralSecurityException {
        PaymentInstruction unsigned = PaymentInstruction.create(from, to, amount);
        String signature = cryptoService.signBase64(unsigned.toCanonicalBytes(), signerKey.getPrivate());
        return unsigned.withSignature(signature);
    }

    @Test
    @DisplayName("A valid signature is accepted and the payment settles with exactly one ledger record")
    void validSignature_isAcceptedAndSettles() throws GeneralSecurityException {
        PaymentInstruction instruction = createSignedInstruction("alice", "bob", new BigDecimal("250.00"), aliceKeyPair);
        MeshPacket packet = createEncryptedMeshPacket(instruction);

        PaymentInstruction settled = bridgeIngestionService.ingest(packet, bridgeKeyPair.getPrivate());

        assertNotNull(settled);
        assertEquals("alice", settled.fromAccount());
        assertEquals("bob", settled.toAccount());
        assertEquals(new BigDecimal("250.00"), settled.amount());

        // Verify balances mutated correctly
        Account alice = accountRepository.findById("alice").orElseThrow();
        Account bob = accountRepository.findById("bob").orElseThrow();
        assertEquals(new BigDecimal("4750.00"), alice.getBalance());
        assertEquals(new BigDecimal("1250.00"), bob.getBalance());

        // Verify exactly one ledger entry
        List<Transaction> transactions = transactionRepository.findAllByOrderByTimestampDesc();
        assertEquals(1, transactions.size());
        assertEquals("SETTLED", transactions.get(0).getStatus());
        assertEquals(new BigDecimal("250.00"), transactions.get(0).getAmount());
    }

    @Test
    @DisplayName("A modified amount invalidates the signature and is rejected without mutating balances or ledger")
    void modifiedAmount_invalidatesSignature_rejected() throws GeneralSecurityException {
        // Alice legitimately signs for 100.00
        PaymentInstruction original = createSignedInstruction("alice", "bob", new BigDecimal("100.00"), aliceKeyPair);

        // Adversary alters amount to 500.00 but keeps Alice's signature
        PaymentInstruction tampered = new PaymentInstruction(
                original.paymentId(),
                original.fromAccount(),
                original.toAccount(),
                new BigDecimal("500.00"),
                original.createdAt(),
                original.nonce(),
                original.signature()
        );
        MeshPacket packet = createEncryptedMeshPacket(tampered);

        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () ->
                bridgeIngestionService.ingest(packet, bridgeKeyPair.getPrivate())
        );
        assertTrue(ex.getMessage().contains("Invalid digital signature"), "Should report invalid digital signature");

        // Balances and ledger must remain completely untouched
        assertEquals(new BigDecimal("5000.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1000.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(0, transactionRepository.count());
    }

    @Test
    @DisplayName("A modified recipient invalidates the signature and is rejected without mutating balances or ledger")
    void modifiedRecipient_invalidatesSignature_rejected() throws GeneralSecurityException {
        // Alice legitimately signs for Bob
        PaymentInstruction original = createSignedInstruction("alice", "bob", new BigDecimal("150.00"), aliceKeyPair);

        // Adversary alters toAccount to Carol
        PaymentInstruction tampered = new PaymentInstruction(
                original.paymentId(),
                original.fromAccount(),
                "carol",
                original.amount(),
                original.createdAt(),
                original.nonce(),
                original.signature()
        );
        MeshPacket packet = createEncryptedMeshPacket(tampered);

        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () ->
                bridgeIngestionService.ingest(packet, bridgeKeyPair.getPrivate())
        );
        assertTrue(ex.getMessage().contains("Invalid digital signature"));

        // Balances must remain unchanged
        assertEquals(new BigDecimal("5000.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1000.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(new BigDecimal("2000.00"), accountRepository.findById("carol").orElseThrow().getBalance());
        assertEquals(0, transactionRepository.count());
    }

    @Test
    @DisplayName("A signature generated by another sender's key is rejected")
    void signatureFromAnotherSender_isRejected() throws GeneralSecurityException {
        // Claimed sender is Alice, but signed with Bob's private key
        PaymentInstruction unsigned = PaymentInstruction.create("alice", "carol", new BigDecimal("100.00"));
        String forgedSignature = cryptoService.signBase64(unsigned.toCanonicalBytes(), bobKeyPair.getPrivate());
        PaymentInstruction instruction = unsigned.withSignature(forgedSignature);
        MeshPacket packet = createEncryptedMeshPacket(instruction);

        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () ->
                bridgeIngestionService.ingest(packet, bridgeKeyPair.getPrivate())
        );
        assertTrue(ex.getMessage().contains("Invalid digital signature for sender: alice"));

        // Verify state is unaltered
        assertEquals(new BigDecimal("5000.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("2000.00"), accountRepository.findById("carol").orElseThrow().getBalance());
        assertEquals(0, transactionRepository.count());
    }

    @Test
    @DisplayName("An unknown or unregistered sender is rejected before settlement")
    void unknownSender_isRejected() throws GeneralSecurityException {
        // Mallory is not in SenderKeyRegistry
        PaymentInstruction unsigned = PaymentInstruction.create("mallory", "bob", new BigDecimal("100.00"));
        String signature = cryptoService.signBase64(unsigned.toCanonicalBytes(), malloryKeyPair.getPrivate());
        PaymentInstruction instruction = unsigned.withSignature(signature);
        MeshPacket packet = createEncryptedMeshPacket(instruction);

        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () ->
                bridgeIngestionService.ingest(packet, bridgeKeyPair.getPrivate())
        );
        assertTrue(ex.getMessage().contains("Unknown or unregistered sender: mallory"));

        // Verify state is unaltered
        assertEquals(new BigDecimal("1000.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(0, transactionRepository.count());
    }

    @Test
    @DisplayName("A missing or null signature is rejected before settlement")
    void missingSignature_isRejected() throws GeneralSecurityException {
        PaymentInstruction unsigned = PaymentInstruction.create("alice", "bob", new BigDecimal("100.00"));
        // signature is null
        MeshPacket packet = createEncryptedMeshPacket(unsigned);

        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () ->
                bridgeIngestionService.ingest(packet, bridgeKeyPair.getPrivate())
        );
        assertTrue(ex.getMessage().contains("signature is missing"));

        // Verify state is unaltered
        assertEquals(new BigDecimal("5000.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1000.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(0, transactionRepository.count());
    }

    @Test
    @DisplayName("An invalid signature does not change balances or ledger history")
    void invalidSignature_doesNotChangeBalancesOrLedgerHistory() throws GeneralSecurityException {
        // Corrupted base64 signature
        PaymentInstruction unsigned = PaymentInstruction.create("alice", "bob", new BigDecimal("300.00"));
        PaymentInstruction instruction = unsigned.withSignature("AAAA_CORRUPTED_SIGNATURE_BYTES_XXXX");
        MeshPacket packet = createEncryptedMeshPacket(instruction);

        assertThrows(IllegalArgumentException.class, () ->
                bridgeIngestionService.ingest(packet, bridgeKeyPair.getPrivate())
        );

        // Balances exactly as initial
        assertEquals(new BigDecimal("5000.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1000.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(new BigDecimal("2000.00"), accountRepository.findById("carol").orElseThrow().getBalance());
        assertEquals(0, transactionRepository.count());
    }

    @Test
    @DisplayName("Tampered nonce or creation timestamp invalidates signature")
    void tamperedNonceOrTimestamp_invalidatesSignature() throws GeneralSecurityException {
        PaymentInstruction original = createSignedInstruction("alice", "bob", new BigDecimal("100.00"), aliceKeyPair);

        // 1. Tampered nonce
        PaymentInstruction tamperedNonce = new PaymentInstruction(
                original.paymentId(),
                original.fromAccount(),
                original.toAccount(),
                original.amount(),
                original.createdAt(),
                UUID.randomUUID().toString(), // altered nonce
                original.signature()
        );
        MeshPacket packet1 = createEncryptedMeshPacket(tamperedNonce);
        assertThrows(IllegalArgumentException.class, () ->
                bridgeIngestionService.ingest(packet1, bridgeKeyPair.getPrivate())
        );

        // 2. Tampered timestamp
        PaymentInstruction tamperedTime = new PaymentInstruction(
                original.paymentId(),
                original.fromAccount(),
                original.toAccount(),
                original.amount(),
                Instant.now().minusSeconds(30), // altered timestamp
                original.nonce(),
                original.signature()
        );
        MeshPacket packet2 = createEncryptedMeshPacket(tamperedTime);
        assertThrows(IllegalArgumentException.class, () ->
                bridgeIngestionService.ingest(packet2, bridgeKeyPair.getPrivate())
        );

        assertEquals(0, transactionRepository.count());
    }

    @Test
    @DisplayName("End-to-end mesh simulation automatically signs with sender key, forwards, and settles")
    void endToEndMeshPayment_withSignatures_settlesSuccessfully() {
        MeshPaymentResult result = meshSimulatorService.simulateMeshPayment("alice", "bob", new BigDecimal("300.00"), 5);

        assertTrue(result.success());
        assertEquals("SETTLED", result.status());
        assertEquals(new BigDecimal("4700.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1300.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(1, transactionRepository.count());
    }
}
