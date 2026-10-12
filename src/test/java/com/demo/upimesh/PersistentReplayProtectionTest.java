package com.demo.upimesh;

import com.demo.upimesh.model.Account;
import com.demo.upimesh.model.AccountRepository;
import com.demo.upimesh.model.MeshPacket;
import com.demo.upimesh.model.PaymentInstruction;
import com.demo.upimesh.model.ProcessedPacket;
import com.demo.upimesh.model.ProcessedPacketRepository;
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
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Test suite verifying persistent replay protection (Stage 11.3).
 * <p>
 * Ensures:
 * - Re-encrypting the same signed payment with a fresh AES-GCM IV is rejected by paymentId uniqueness.
 * - Nonce reuse for the same sender is rejected by (fromAccount, nonce) uniqueness.
 * - Replayed payments fail even after creating a new application service instance.
 * - Genuine new payments settle normally.
 * - Invalid signatures and expired timestamps do not consume payment identity.
 * - Concurrent replay attempts with distinct IVs yield at most one settlement.
 */
@SpringBootTest
class PersistentReplayProtectionTest {

    @Autowired
    private BridgeIngestionService bridgeIngestionService;

    @Autowired
    private CryptoService cryptoService;

    @Autowired
    private SettlementService settlementService;

    @Autowired
    private IdempotencyService idempotencyService;

    @Autowired
    private SenderKeyRegistry senderKeyRegistry;

    @Autowired
    private MeshSimulatorService meshSimulatorService;

    @Autowired
    private AccountRepository accountRepository;

    @Autowired
    private TransactionRepository transactionRepository;

    @Autowired
    private ProcessedPacketRepository processedPacketRepository;

    private KeyPair bridgeKeyPair;
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

        idempotencyService.clear();

        meshSimulatorService.reset();
        meshSimulatorService.initDefaultTopology();

        bridgeKeyPair = meshSimulatorService.getBridgeKeyPair();
        if (bridgeKeyPair == null) {
            bridgeKeyPair = cryptoService.generateRsaKeyPair();
            meshSimulatorService.setBridgeKeyPair(bridgeKeyPair);
        }

        aliceKeyPair = cryptoService.generateRsaKeyPair();
        bobKeyPair = cryptoService.generateRsaKeyPair();

        meshSimulatorService.registerSenderKeyPair("alice", aliceKeyPair);
        meshSimulatorService.registerSenderKeyPair("bob", bobKeyPair);
    }

    private PaymentInstruction createSignedInstruction(String from, String to, BigDecimal amount, KeyPair signerKey) throws GeneralSecurityException {
        PaymentInstruction unsigned = PaymentInstruction.create(from, to, amount);
        String signature = cryptoService.signBase64(unsigned.toCanonicalBytes(), signerKey.getPrivate());
        return unsigned.withSignature(signature);
    }

    private MeshPacket encryptInstruction(PaymentInstruction instruction) throws GeneralSecurityException {
        String json = bridgeIngestionService.serializeInstruction(instruction);
        EncryptedPacket encryptedPacket = cryptoService.encrypt(json, bridgeKeyPair.getPublic());
        return MeshPacket.create("node_test_sender", "BRIDGE", 5, encryptedPacket);
    }

    @Test
    @DisplayName("1. Re-encrypting the same signed payment with a different IV is rejected as duplicate")
    void reEncryptingSameSignedPaymentWithDifferentIv_isRejected() throws GeneralSecurityException {
        PaymentInstruction signed = createSignedInstruction("alice", "bob", new BigDecimal("200.00"), aliceKeyPair);

        // Encrypt first time -> Packet 1
        MeshPacket packet1 = encryptInstruction(signed);
        PaymentInstruction settled = bridgeIngestionService.ingest(packet1, bridgeKeyPair.getPrivate());
        assertNotNull(settled);

        assertEquals(new BigDecimal("4800.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1200.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(1, transactionRepository.count());
        assertEquals(1, processedPacketRepository.count());

        // Re-encrypt the exact same signed instruction -> Packet 2 (different IV, different ciphertext, different packetHash)
        MeshPacket packet2 = encryptInstruction(signed);
        assertFalse(Arrays.equals(packet1.payload().iv(), packet2.payload().iv()), "IVs must be different");
        assertNotEquals(idempotencyService.computeHash(packet1.payload()), idempotencyService.computeHash(packet2.payload()), "Packet hashes must be different");

        // Submitting Packet 2 must be rejected because paymentId is already settled
        DuplicatePacketException ex = assertThrows(DuplicatePacketException.class, () ->
                bridgeIngestionService.ingest(packet2, bridgeKeyPair.getPrivate())
        );
        assertTrue(ex.getMessage().contains("paymentId already settled") || ex.getMessage().contains("Duplicate"));

        // Balances and ledger remain untouched
        assertEquals(new BigDecimal("4800.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1200.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(1, transactionRepository.count());
        assertEquals(1, processedPacketRepository.count());
    }

    @Test
    @DisplayName("2. Replaying the same payment after creating a new service instance is rejected from database")
    void replayingSamePaymentAfterCreatingNewServiceInstance_isRejectedFromDatabase() throws GeneralSecurityException {
        PaymentInstruction signed = createSignedInstruction("alice", "bob", new BigDecimal("150.00"), aliceKeyPair);
        MeshPacket packet1 = encryptInstruction(signed);

        // Settle via initial service instance
        bridgeIngestionService.ingest(packet1, bridgeKeyPair.getPrivate());
        assertEquals(1, processedPacketRepository.count());

        // Create a fresh IdempotencyService (empty in-memory cache) and fresh BridgeIngestionService
        IdempotencyService freshIdempotencyService = new IdempotencyService(processedPacketRepository);
        BridgeIngestionService freshBridgeInstance = new BridgeIngestionService(
                cryptoService,
                settlementService,
                freshIdempotencyService,
                bridgeIngestionService.getSenderKeyRegistry()
        );

        // Re-encrypt same payment into packet2 with fresh IV
        MeshPacket packet2 = encryptInstruction(signed);

        // Submit packet2 to the fresh bridge instance
        DuplicatePacketException ex = assertThrows(DuplicatePacketException.class, () ->
                freshBridgeInstance.ingest(packet2, bridgeKeyPair.getPrivate())
        );
        assertTrue(ex.getMessage().contains("paymentId already settled") || ex.getMessage().contains("Duplicate"));

        assertEquals(new BigDecimal("4850.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1150.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(1, transactionRepository.count());
    }

    @Test
    @DisplayName("3. Reusing a nonce for the same sender is rejected by (fromAccount, nonce) constraint")
    void reusingNonceForSameSender_isRejected() throws GeneralSecurityException {
        String fixedNonce = "nonce-fixed-" + UUID.randomUUID();

        // 1. Legitimate instruction 1 with fixedNonce
        PaymentInstruction inst1 = new PaymentInstruction(
                UUID.randomUUID().toString(),
                "alice",
                "bob",
                new BigDecimal("100.00"),
                Instant.now(),
                fixedNonce,
                null
        );
        String sig1 = cryptoService.signBase64(inst1.toCanonicalBytes(), aliceKeyPair.getPrivate());
        inst1 = inst1.withSignature(sig1);

        MeshPacket packet1 = encryptInstruction(inst1);
        bridgeIngestionService.ingest(packet1, bridgeKeyPair.getPrivate());

        assertEquals(new BigDecimal("4900.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(1, transactionRepository.count());

        // 2. New instruction 2 with distinct paymentId but reusing fixedNonce for alice
        PaymentInstruction inst2 = new PaymentInstruction(
                UUID.randomUUID().toString(),
                "alice",
                "bob",
                new BigDecimal("50.00"),
                Instant.now(),
                fixedNonce, // Reused nonce!
                null
        );
        String sig2 = cryptoService.signBase64(inst2.toCanonicalBytes(), aliceKeyPair.getPrivate());
        inst2 = inst2.withSignature(sig2);

        MeshPacket packet2 = encryptInstruction(inst2);

        DuplicatePacketException ex = assertThrows(DuplicatePacketException.class, () ->
                bridgeIngestionService.ingest(packet2, bridgeKeyPair.getPrivate())
        );
        assertTrue(ex.getMessage().contains("nonce already used") || ex.getMessage().contains("Duplicate"));

        // Balances and ledger remain as from payment 1 only
        assertEquals(new BigDecimal("4900.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(1, transactionRepository.count());
    }

    @Test
    @DisplayName("4. Same nonce used by different senders is allowed and settles independently")
    void sameNonceUsedByDifferentSenders_isAllowed() throws GeneralSecurityException {
        String sharedNonce = "shared-nonce-12345";

        // Alice uses sharedNonce
        PaymentInstruction aliceInst = new PaymentInstruction(
                UUID.randomUUID().toString(),
                "alice",
                "bob",
                new BigDecimal("100.00"),
                Instant.now(),
                sharedNonce,
                null
        );
        aliceInst = aliceInst.withSignature(cryptoService.signBase64(aliceInst.toCanonicalBytes(), aliceKeyPair.getPrivate()));

        // Bob uses the same sharedNonce
        PaymentInstruction bobInst = new PaymentInstruction(
                UUID.randomUUID().toString(),
                "bob",
                "carol",
                new BigDecimal("70.00"),
                Instant.now(),
                sharedNonce,
                null
        );
        bobInst = bobInst.withSignature(cryptoService.signBase64(bobInst.toCanonicalBytes(), bobKeyPair.getPrivate()));

        assertNotNull(bridgeIngestionService.ingest(encryptInstruction(aliceInst), bridgeKeyPair.getPrivate()));
        assertNotNull(bridgeIngestionService.ingest(encryptInstruction(bobInst), bridgeKeyPair.getPrivate()));

        assertEquals(new BigDecimal("4900.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1030.00"), accountRepository.findById("bob").orElseThrow().getBalance()); // 1000 + 100 - 70
        assertEquals(new BigDecimal("2070.00"), accountRepository.findById("carol").orElseThrow().getBalance());
        assertEquals(2, transactionRepository.count());
        assertEquals(2, processedPacketRepository.count());
    }

    @Test
    @DisplayName("5. A genuinely new signed payment succeeds and increments ledger")
    void genuinelyNewSignedPaymentSucceeds() throws GeneralSecurityException {
        PaymentInstruction payment1 = createSignedInstruction("alice", "bob", new BigDecimal("100.00"), aliceKeyPair);
        PaymentInstruction payment2 = createSignedInstruction("alice", "bob", new BigDecimal("200.00"), aliceKeyPair);

        assertNotNull(bridgeIngestionService.ingest(encryptInstruction(payment1), bridgeKeyPair.getPrivate()));
        assertNotNull(bridgeIngestionService.ingest(encryptInstruction(payment2), bridgeKeyPair.getPrivate()));

        assertEquals(new BigDecimal("4700.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1300.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(2, transactionRepository.count());
        assertEquals(2, processedPacketRepository.count());
    }

    @Test
    @DisplayName("6. Invalid signatures and expired instructions leave no settled records")
    void invalidSignaturesAndExpiredInstructions_leaveNoSettledRecords() throws GeneralSecurityException {
        // 1. Invalid signature
        PaymentInstruction unsigned = PaymentInstruction.create("alice", "bob", new BigDecimal("50.00"));
        PaymentInstruction invalidSigInst = unsigned.withSignature("BAD_FORGED_SIG_BYTES");
        MeshPacket badSigPacket = encryptInstruction(invalidSigInst);

        assertThrows(IllegalArgumentException.class, () ->
                bridgeIngestionService.ingest(badSigPacket, bridgeKeyPair.getPrivate())
        );
        assertEquals(0, processedPacketRepository.count());
        assertEquals(0, transactionRepository.count());

        // 2. Expired timestamp (> 24 hours old)
        PaymentInstruction expiredUnsigned = new PaymentInstruction(
                UUID.randomUUID().toString(),
                "alice",
                "bob",
                new BigDecimal("50.00"),
                Instant.now().minus(25, ChronoUnit.HOURS),
                UUID.randomUUID().toString(),
                null
        );
        String expSig = cryptoService.signBase64(expiredUnsigned.toCanonicalBytes(), aliceKeyPair.getPrivate());
        PaymentInstruction expiredInst = expiredUnsigned.withSignature(expSig);
        MeshPacket expiredPacket = encryptInstruction(expiredInst);

        assertThrows(IllegalArgumentException.class, () ->
                bridgeIngestionService.ingest(expiredPacket, bridgeKeyPair.getPrivate())
        );
        assertEquals(0, processedPacketRepository.count());
        assertEquals(0, transactionRepository.count());

        // Balances untouched
        assertEquals(new BigDecimal("5000.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1000.00"), accountRepository.findById("bob").orElseThrow().getBalance());
    }

    @Test
    @DisplayName("7. Concurrent replay attempts with different IVs produce at most one settlement")
    void concurrentReplayAttemptsWithDifferentIvs_produceAtMostOneSettlement() throws Exception {
        PaymentInstruction instruction = createSignedInstruction("alice", "bob", new BigDecimal("300.00"), aliceKeyPair);

        int threadCount = 10;
        List<MeshPacket> packetsWithDistinctIvs = new ArrayList<>();
        for (int i = 0; i < threadCount; i++) {
            packetsWithDistinctIvs.add(encryptInstruction(instruction));
        }

        ExecutorService executor = Executors.newFixedThreadPool(threadCount);
        CountDownLatch startLatch = new CountDownLatch(1);
        AtomicInteger successCount = new AtomicInteger(0);
        AtomicInteger duplicateCount = new AtomicInteger(0);
        List<Future<?>> futures = new ArrayList<>();

        for (int i = 0; i < threadCount; i++) {
            final MeshPacket packet = packetsWithDistinctIvs.get(i);
            futures.add(executor.submit(() -> {
                try {
                    startLatch.await();
                    bridgeIngestionService.ingest(packet, bridgeKeyPair.getPrivate());
                    successCount.incrementAndGet();
                } catch (DuplicatePacketException e) {
                    duplicateCount.incrementAndGet();
                } catch (Exception e) {
                    // unexpected error
                }
            }));
        }

        startLatch.countDown();
        for (Future<?> f : futures) {
            f.get();
        }
        executor.shutdown();

        assertEquals(1, successCount.get(), "Exactly one concurrent thread must succeed");
        assertEquals(threadCount - 1, duplicateCount.get(), "All other concurrent attempts must be rejected");

        // Exactly one balance mutation and ledger record
        assertEquals(new BigDecimal("4700.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1300.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(1, transactionRepository.count());
        assertEquals(1, processedPacketRepository.count());
    }
}
