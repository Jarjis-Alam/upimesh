package com.demo.upimesh;

import com.demo.upimesh.model.MeshPacket;
import com.demo.upimesh.model.PaymentInstruction;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

import java.math.BigDecimal;
import java.security.GeneralSecurityException;
import java.security.KeyPair;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;

class BridgeIngestionServiceTest {

    private CryptoService cryptoService;
    private SettlementService settlementService;
    private BridgeIngestionService ingestionService;
    private KeyPair serverKeyPair;
    private KeyPair aliceKeyPair;
    private KeyPair bobKeyPair;

    @BeforeEach
    void setUp() throws GeneralSecurityException {
        cryptoService = new CryptoService();
        settlementService = Mockito.mock(SettlementService.class);
        Mockito.doAnswer(invocation -> {
            PaymentInstruction inst = invocation.getArgument(0);
            settlementService.transfer(inst.fromAccount(), inst.toAccount(), inst.amount());
            return null;
        }).when(settlementService).settlePayment(Mockito.any(), Mockito.any());

        ingestionService = new BridgeIngestionService(cryptoService, settlementService);
        serverKeyPair = cryptoService.generateRsaKeyPair();

        // Register trusted demo signing keys
        aliceKeyPair = cryptoService.generateRsaKeyPair();
        bobKeyPair = cryptoService.generateRsaKeyPair();
        ingestionService.getSenderKeyRegistry().registerKey("alice", aliceKeyPair.getPublic());
        ingestionService.getSenderKeyRegistry().registerKey("bob", bobKeyPair.getPublic());
    }

    private PaymentInstruction createSignedInstruction(String from, String to, BigDecimal amount) throws GeneralSecurityException {
        PaymentInstruction instruction = PaymentInstruction.create(from, to, amount);
        KeyPair senderKey = from.equalsIgnoreCase("alice") ? aliceKeyPair : bobKeyPair;
        String signature = cryptoService.signBase64(instruction.toCanonicalBytes(), senderKey.getPrivate());
        return instruction.withSignature(signature);
    }

    @Test
    @DisplayName("Valid ingested payment decrypts, validates, and settles successfully")
    void validIngestedPaymentSettlesSuccessfully() throws GeneralSecurityException {
        PaymentInstruction instruction = createSignedInstruction("alice", "bob", new BigDecimal("150.00"));

        String json = ingestionService.serializeInstruction(instruction);
        EncryptedPacket encryptedPacket = cryptoService.encrypt(json, serverKeyPair.getPublic());
        MeshPacket meshPacket = MeshPacket.create("phone_node_1", "BRIDGE", 5, encryptedPacket);

        PaymentInstruction settled = ingestionService.ingest(meshPacket, serverKeyPair.getPrivate());

        assertNotNull(settled);
        assertEquals("alice", settled.fromAccount());
        assertEquals("bob", settled.toAccount());
        assertEquals(new BigDecimal("150.00"), settled.amount());
        assertEquals(instruction.paymentId(), settled.paymentId());

        // Verify settlement service transfer was invoked with exact parameters
        verify(settlementService).transfer("alice", "bob", new BigDecimal("150.00"));
    }

    @Test
    @DisplayName("Expired instruction older than 24 hours is rejected without settlement")
    void expiredInstructionOlderThan24HoursIsRejected() throws GeneralSecurityException {
        Instant expiredTimestamp = Instant.now().minus(25, ChronoUnit.HOURS);
        PaymentInstruction expiredInstruction = new PaymentInstruction(
                UUID.randomUUID().toString(),
                "alice",
                "bob",
                new BigDecimal("50.00"),
                expiredTimestamp,
                UUID.randomUUID().toString()
        );
        String sig = cryptoService.signBase64(expiredInstruction.toCanonicalBytes(), aliceKeyPair.getPrivate());
        expiredInstruction = expiredInstruction.withSignature(sig);

        String json = ingestionService.serializeInstruction(expiredInstruction);
        EncryptedPacket encryptedPacket = cryptoService.encrypt(json, serverKeyPair.getPublic());
        MeshPacket meshPacket = MeshPacket.create("phone_node_1", "BRIDGE", 5, encryptedPacket);

        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () ->
                ingestionService.ingest(meshPacket, serverKeyPair.getPrivate())
        );

        assertEquals("Payment instruction has expired (older than 24 hours)", ex.getMessage());
        verifyNoInteractions(settlementService);
    }

    @Test
    @DisplayName("Instruction with timestamp in the future beyond allowed clock skew is rejected")
    void futureInstructionBeyondClockSkewIsRejected() throws GeneralSecurityException {
        Instant futureTimestamp = Instant.now().plus(10, ChronoUnit.MINUTES);
        PaymentInstruction futureInstruction = new PaymentInstruction(
                UUID.randomUUID().toString(),
                "alice",
                "bob",
                new BigDecimal("50.00"),
                futureTimestamp,
                UUID.randomUUID().toString()
        );
        String sig = cryptoService.signBase64(futureInstruction.toCanonicalBytes(), aliceKeyPair.getPrivate());
        futureInstruction = futureInstruction.withSignature(sig);

        String json = ingestionService.serializeInstruction(futureInstruction);
        EncryptedPacket encryptedPacket = cryptoService.encrypt(json, serverKeyPair.getPublic());
        MeshPacket meshPacket = MeshPacket.create("phone_node_1", "BRIDGE", 5, encryptedPacket);

        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () ->
                ingestionService.ingest(meshPacket, serverKeyPair.getPrivate())
        );

        assertEquals("Payment instruction timestamp is in the future beyond allowed clock skew", ex.getMessage());
        verifyNoInteractions(settlementService);
    }

    @Test
    @DisplayName("Invalid or malformed JSON payload is rejected without settlement")
    void invalidJsonPayloadIsRejected() throws GeneralSecurityException {
        String invalidJson = "{ \"fromAccount\": \"alice\", \"bad\": true ";
        EncryptedPacket encryptedPacket = cryptoService.encrypt(invalidJson, serverKeyPair.getPublic());
        MeshPacket meshPacket = MeshPacket.create("phone_node_1", "BRIDGE", 5, encryptedPacket);

        assertThrows(IllegalArgumentException.class, () ->
                ingestionService.ingest(meshPacket, serverKeyPair.getPrivate())
        );

        verifyNoInteractions(settlementService);
    }

    @Test
    @DisplayName("Tampered ciphertext is rejected by AEAD integrity verification without settlement")
    void tamperedCiphertextIsRejected() throws GeneralSecurityException {
        PaymentInstruction instruction = createSignedInstruction("alice", "bob", new BigDecimal("100.00"));
        String json = ingestionService.serializeInstruction(instruction);
        EncryptedPacket packet = cryptoService.encrypt(json, serverKeyPair.getPublic());

        // Tamper with the ciphertext byte
        byte[] tamperedBytes = packet.ciphertext().clone();
        tamperedBytes[0] ^= 0x01;

        EncryptedPacket tamperedPacket = new EncryptedPacket(
                packet.encryptedAesKey(),
                packet.iv(),
                tamperedBytes
        );
        MeshPacket meshPacket = MeshPacket.create("phone_node_1", "BRIDGE", 5, tamperedPacket);

        assertThrows(GeneralSecurityException.class, () ->
                ingestionService.ingest(meshPacket, serverKeyPair.getPrivate())
        );

        verifyNoInteractions(settlementService);
    }

    @Test
    @DisplayName("Decryption with wrong private key fails without settlement")
    void wrongPrivateKeyFailsDecryption() throws GeneralSecurityException {
        PaymentInstruction instruction = createSignedInstruction("alice", "bob", new BigDecimal("100.00"));
        String json = ingestionService.serializeInstruction(instruction);
        EncryptedPacket packet = cryptoService.encrypt(json, serverKeyPair.getPublic());
        MeshPacket meshPacket = MeshPacket.create("phone_node_1", "BRIDGE", 5, packet);

        KeyPair anotherKeyPair = cryptoService.generateRsaKeyPair();

        assertThrows(GeneralSecurityException.class, () ->
                ingestionService.ingest(meshPacket, anotherKeyPair.getPrivate())
        );

        verifyNoInteractions(settlementService);
    }

    @Test
    @DisplayName("Same packet is rejected on repeat attempt without duplicate settlement")
    void samePacketRejectedOnRepeat() throws GeneralSecurityException {
        PaymentInstruction instruction = createSignedInstruction("alice", "bob", new BigDecimal("100.00"));
        String json = ingestionService.serializeInstruction(instruction);
        EncryptedPacket packet = cryptoService.encrypt(json, serverKeyPair.getPublic());
        MeshPacket meshPacket = MeshPacket.create("phone_node_1", "BRIDGE", 5, packet);

        // First attempt succeeds
        PaymentInstruction first = ingestionService.ingest(meshPacket, serverKeyPair.getPrivate());
        assertNotNull(first);

        // Second attempt with exact same packet must be rejected
        assertThrows(DuplicatePacketException.class, () ->
                ingestionService.ingest(meshPacket, serverKeyPair.getPrivate())
        );

        // Settlement transfer was invoked only once
        verify(settlementService, Mockito.times(1)).transfer("alice", "bob", new BigDecimal("100.00"));
    }

    @Test
    @DisplayName("Multiple concurrent ingestion attempts result in exactly one successful settlement")
    void concurrentIngestionsResultInExactlyOneSettlement() throws Exception {
        PaymentInstruction instruction = createSignedInstruction("alice", "bob", new BigDecimal("75.00"));
        String json = ingestionService.serializeInstruction(instruction);
        EncryptedPacket packet = cryptoService.encrypt(json, serverKeyPair.getPublic());
        MeshPacket meshPacket = MeshPacket.create("phone_node_1", "BRIDGE", 5, packet);

        int threadCount = 10;
        java.util.concurrent.ExecutorService executor = java.util.concurrent.Executors.newFixedThreadPool(threadCount);
        java.util.concurrent.CountDownLatch startLatch = new java.util.concurrent.CountDownLatch(1);
        java.util.concurrent.atomic.AtomicInteger successCount = new java.util.concurrent.atomic.AtomicInteger(0);
        java.util.concurrent.atomic.AtomicInteger duplicateCount = new java.util.concurrent.atomic.AtomicInteger(0);
        java.util.List<java.util.concurrent.Future<?>> futures = new java.util.ArrayList<>();

        for (int i = 0; i < threadCount; i++) {
            futures.add(executor.submit(() -> {
                try {
                    startLatch.await();
                    ingestionService.ingest(meshPacket, serverKeyPair.getPrivate());
                    successCount.incrementAndGet();
                } catch (DuplicatePacketException e) {
                    duplicateCount.incrementAndGet();
                } catch (Exception e) {
                    // unexpected exception
                }
            }));
        }

        startLatch.countDown(); // start all threads at once

        for (java.util.concurrent.Future<?> f : futures) {
            f.get();
        }
        executor.shutdown();

        assertEquals(1, successCount.get(), "Exactly one concurrent thread must settle the packet");
        assertEquals(threadCount - 1, duplicateCount.get(), "All other concurrent attempts must be rejected as duplicates");
        verify(settlementService, Mockito.times(1)).transfer("alice", "bob", new BigDecimal("75.00"));
    }

    @Test
    @DisplayName("Failed settlement releases claim and allows subsequent successful retry")
    void failedSettlementAllowsSubsequentRetry() throws GeneralSecurityException {
        PaymentInstruction instruction = createSignedInstruction("alice", "bob", new BigDecimal("200.00"));
        String json = ingestionService.serializeInstruction(instruction);
        EncryptedPacket packet = cryptoService.encrypt(json, serverKeyPair.getPublic());
        MeshPacket meshPacket = MeshPacket.create("phone_node_1", "BRIDGE", 5, packet);

        // First attempt: settlement fails with insufficient funds
        Mockito.doThrow(new IllegalStateException("Insufficient funds"))
                .doNothing() // Second attempt will succeed
                .when(settlementService).transfer("alice", "bob", new BigDecimal("200.00"));

        assertThrows(IllegalStateException.class, () ->
                ingestionService.ingest(meshPacket, serverKeyPair.getPrivate())
        );

        // Second attempt: retrying the same packet succeeds now that funds are available
        PaymentInstruction retried = ingestionService.ingest(meshPacket, serverKeyPair.getPrivate());
        assertNotNull(retried);

        verify(settlementService, Mockito.times(2)).transfer("alice", "bob", new BigDecimal("200.00"));
    }

    @Test
    @DisplayName("Different ciphertext packets can be claimed and settled independently")
    void differentCiphertextPacketsSettleIndependently() throws GeneralSecurityException {
        PaymentInstruction instruction1 = createSignedInstruction("alice", "bob", new BigDecimal("50.00"));
        PaymentInstruction instruction2 = createSignedInstruction("bob", "carol", new BigDecimal("30.00"));

        String json1 = ingestionService.serializeInstruction(instruction1);
        String json2 = ingestionService.serializeInstruction(instruction2);

        MeshPacket packet1 = MeshPacket.create("phone_1", "BRIDGE", 5, cryptoService.encrypt(json1, serverKeyPair.getPublic()));
        MeshPacket packet2 = MeshPacket.create("phone_2", "BRIDGE", 5, cryptoService.encrypt(json2, serverKeyPair.getPublic()));

        assertNotNull(ingestionService.ingest(packet1, serverKeyPair.getPrivate()));
        assertNotNull(ingestionService.ingest(packet2, serverKeyPair.getPrivate()));

        verify(settlementService).transfer("alice", "bob", new BigDecimal("50.00"));
        verify(settlementService).transfer("bob", "carol", new BigDecimal("30.00"));
    }
}
