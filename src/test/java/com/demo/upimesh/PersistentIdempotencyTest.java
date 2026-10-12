package com.demo.upimesh;

import com.demo.upimesh.model.Account;
import com.demo.upimesh.model.AccountRepository;
import com.demo.upimesh.model.MeshPacket;
import com.demo.upimesh.model.MeshPaymentResult;
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
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Test suite verifying persistent idempotency and restart durability (Stage 11.2).
 * <p>
 * Ensures:
 * - Duplicate packets cannot settle twice.
 * - Concurrent submissions yield at most one ledger entry.
 * - Failed transactions roll back and allow legitimate retries.
 * - Re-instantiated service instances recognize previously settled packets from the database.
 * - Invalid signatures never persist idempotency records.
 * - Distinct packets settle independently.
 * - Direct transfers and simulated mesh payments continue to function correctly.
 */
@SpringBootTest
class PersistentIdempotencyTest {

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
        // Clear repositories to deterministic initial state
        processedPacketRepository.deleteAll();
        transactionRepository.deleteAll();
        accountRepository.deleteAll();
        accountRepository.saveAll(List.of(
                new Account("alice", new BigDecimal("5000.00")),
                new Account("bob", new BigDecimal("1000.00")),
                new Account("carol", new BigDecimal("2000.00"))
        ));

        idempotencyService.clear();

        // Reset simulator and topology
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

    private MeshPacket createSignedAndEncryptedPacket(String from, String to, BigDecimal amount, KeyPair signerKey) throws GeneralSecurityException {
        PaymentInstruction instruction = PaymentInstruction.create(from, to, amount);
        String signature = cryptoService.signBase64(instruction.toCanonicalBytes(), signerKey.getPrivate());
        PaymentInstruction signedInstruction = instruction.withSignature(signature);

        String json = bridgeIngestionService.serializeInstruction(signedInstruction);
        EncryptedPacket encryptedPacket = cryptoService.encrypt(json, bridgeKeyPair.getPublic());
        return MeshPacket.create("node_test_sender", "BRIDGE", 5, encryptedPacket);
    }

    @Test
    @DisplayName("1. The same encrypted packet cannot settle twice")
    void sameEncryptedPacketCannotSettleTwice() throws GeneralSecurityException {
        MeshPacket packet = createSignedAndEncryptedPacket("alice", "bob", new BigDecimal("100.00"), aliceKeyPair);

        // First submission succeeds
        PaymentInstruction settled = bridgeIngestionService.ingest(packet, bridgeKeyPair.getPrivate());
        assertNotNull(settled);

        Account alice = accountRepository.findById("alice").orElseThrow();
        Account bob = accountRepository.findById("bob").orElseThrow();
        assertEquals(new BigDecimal("4900.00"), alice.getBalance());
        assertEquals(new BigDecimal("1100.00"), bob.getBalance());
        assertEquals(1, transactionRepository.count());
        assertEquals(1, processedPacketRepository.count());

        // Second submission of the exact same packet must be rejected as duplicate
        DuplicatePacketException ex = assertThrows(DuplicatePacketException.class, () ->
                bridgeIngestionService.ingest(packet, bridgeKeyPair.getPrivate())
        );
        assertTrue(ex.getMessage().contains("Duplicate packet rejected"));

        // Balances and ledger remain unchanged
        assertEquals(new BigDecimal("4900.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1100.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(1, transactionRepository.count());
        assertEquals(1, processedPacketRepository.count());
    }

    @Test
    @DisplayName("2. Concurrent submissions of the same packet create at most one ledger entry")
    void concurrentSubmissionsOfSamePacket_createExactlyOneLedgerEntry() throws Exception {
        MeshPacket packet = createSignedAndEncryptedPacket("alice", "bob", new BigDecimal("250.00"), aliceKeyPair);

        int threadCount = 12;
        ExecutorService executor = Executors.newFixedThreadPool(threadCount);
        CountDownLatch startLatch = new CountDownLatch(1);
        AtomicInteger successCount = new AtomicInteger(0);
        AtomicInteger duplicateCount = new AtomicInteger(0);
        List<Future<?>> futures = new ArrayList<>();

        for (int i = 0; i < threadCount; i++) {
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

        assertEquals(1, successCount.get(), "Exactly one concurrent thread must settle the packet");
        assertEquals(threadCount - 1, duplicateCount.get(), "All other concurrent attempts must be rejected as duplicates");

        // Exactly one balance mutation and ledger record
        assertEquals(new BigDecimal("4750.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1250.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(1, transactionRepository.count());
        assertEquals(1, processedPacketRepository.count());
    }

    @Test
    @DisplayName("3. A failed settlement does not permanently block a valid retry")
    void failedSettlementDoesNotPermanentlyBlockValidRetry() throws GeneralSecurityException {
        // Alice has 5000.00; attempt transfer of 10000.00 (fails due to insufficient funds)
        MeshPacket packet = createSignedAndEncryptedPacket("alice", "bob", new BigDecimal("10000.00"), aliceKeyPair);

        assertThrows(IllegalStateException.class, () ->
                bridgeIngestionService.ingest(packet, bridgeKeyPair.getPrivate())
        );

        // Verify balances untouched and no idempotency record persisted
        assertEquals(new BigDecimal("5000.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1000.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(0, transactionRepository.count());
        assertEquals(0, processedPacketRepository.count());

        // Now Alice receives an external top-up
        Account alice = accountRepository.findById("alice").orElseThrow();
        alice.setBalance(new BigDecimal("15000.00"));
        accountRepository.save(alice);

        // Retrying the exact same packet must now succeed and settle
        PaymentInstruction retried = bridgeIngestionService.ingest(packet, bridgeKeyPair.getPrivate());
        assertNotNull(retried);

        assertEquals(new BigDecimal("5000.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("11000.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(1, transactionRepository.count());
        assertEquals(1, processedPacketRepository.count());
    }

    @Test
    @DisplayName("4. A new application service instance still recognizes an already-settled packet from database")
    void newServiceInstanceRecognizesAlreadySettledPacketFromDatabase() throws GeneralSecurityException {
        MeshPacket packet = createSignedAndEncryptedPacket("alice", "bob", new BigDecimal("120.00"), aliceKeyPair);
        String packetHash = idempotencyService.computeHash(packet.payload());

        // Settle using initial service instance
        bridgeIngestionService.ingest(packet, bridgeKeyPair.getPrivate());
        assertEquals(1, processedPacketRepository.count());

        // Simulate fresh application restart: instantiate a brand new IdempotencyService and BridgeIngestionService
        // backed by the exact same database repository
        IdempotencyService freshIdempotencyService = new IdempotencyService(processedPacketRepository);
        // The fresh service has an empty in-memory claims map
        assertTrue(freshIdempotencyService.isSettled(packetHash), "Must report settled based on persistent DB");
        assertFalse(freshIdempotencyService.tryClaim(packetHash), "tryClaim must fail on restart for already-settled hash");

        BridgeIngestionService freshBridgeInstance = new BridgeIngestionService(
                cryptoService,
                settlementService,
                freshIdempotencyService,
                bridgeIngestionService.getSenderKeyRegistry()
        );

        // Attempt ingestion via the fresh bridge instance
        DuplicatePacketException ex = assertThrows(DuplicatePacketException.class, () ->
                freshBridgeInstance.ingest(packet, bridgeKeyPair.getPrivate())
        );
        assertTrue(ex.getMessage().contains("Duplicate packet rejected"));

        // Balances and ledger remain exactly as settled once
        assertEquals(new BigDecimal("4880.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1120.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(1, transactionRepository.count());
    }

    @Test
    @DisplayName("5. Invalid signatures never create settled records")
    void invalidSignaturesNeverCreateSettledRecords() throws GeneralSecurityException {
        // Create instruction with corrupted signature
        PaymentInstruction unsigned = PaymentInstruction.create("alice", "bob", new BigDecimal("50.00"));
        PaymentInstruction corrupted = unsigned.withSignature("INVALID_TAMPERED_SIGNATURE_BYTES");

        String json = bridgeIngestionService.serializeInstruction(corrupted);
        EncryptedPacket encryptedPacket = cryptoService.encrypt(json, bridgeKeyPair.getPublic());
        MeshPacket packet = MeshPacket.create("node_attacker", "BRIDGE", 5, encryptedPacket);

        assertThrows(IllegalArgumentException.class, () ->
                bridgeIngestionService.ingest(packet, bridgeKeyPair.getPrivate())
        );

        assertEquals(0, processedPacketRepository.count(), "No ProcessedPacket record should exist");
        assertEquals(0, transactionRepository.count(), "No Transaction ledger record should exist");
        assertEquals(new BigDecimal("5000.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1000.00"), accountRepository.findById("bob").orElseThrow().getBalance());
    }

    @Test
    @DisplayName("6. Distinct valid packets can settle independently")
    void distinctValidPacketsSettleIndependently() throws GeneralSecurityException {
        MeshPacket packet1 = createSignedAndEncryptedPacket("alice", "bob", new BigDecimal("80.00"), aliceKeyPair);
        MeshPacket packet2 = createSignedAndEncryptedPacket("alice", "bob", new BigDecimal("40.00"), aliceKeyPair);

        assertNotNull(bridgeIngestionService.ingest(packet1, bridgeKeyPair.getPrivate()));
        assertNotNull(bridgeIngestionService.ingest(packet2, bridgeKeyPair.getPrivate()));

        assertEquals(new BigDecimal("4880.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1120.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(2, transactionRepository.count());
        assertEquals(2, processedPacketRepository.count());
    }

    @Test
    @DisplayName("7. Existing direct transfers and end-to-end mesh payments still work")
    void directTransfersAndEndToEndMeshPaymentsStillWork() {
        // Direct non-mesh transfer via SettlementService
        settlementService.transfer("alice", "bob", new BigDecimal("100.00"));
        assertEquals(new BigDecimal("4900.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1100.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(1, transactionRepository.count());

        // Simulated end-to-end mesh payment
        MeshPaymentResult result = meshSimulatorService.simulateMeshPayment("alice", "bob", new BigDecimal("50.00"), 5);
        assertTrue(result.success());
        assertEquals("SETTLED", result.status());

        assertEquals(new BigDecimal("4850.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1150.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(2, transactionRepository.count());
        assertEquals(1, processedPacketRepository.count());
    }
}
