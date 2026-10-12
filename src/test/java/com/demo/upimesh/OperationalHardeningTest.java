package com.demo.upimesh;

import com.demo.upimesh.model.Account;
import com.demo.upimesh.model.AccountRepository;
import com.demo.upimesh.model.MeshPacket;
import com.demo.upimesh.model.MeshPaymentResult;
import com.demo.upimesh.model.PaymentInstruction;
import com.demo.upimesh.model.ProcessedPacketRepository;
import com.demo.upimesh.model.ReconciliationReport;
import com.demo.upimesh.model.Transaction;
import com.demo.upimesh.model.TransactionRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import java.math.BigDecimal;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.GeneralSecurityException;
import java.security.KeyPair;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.time.Instant;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Operational Hardening Test Suite (Stage 12).
 * <p>
 * Verifies:
 * 1. File-backed H2 persistence across restarts without data loss, re-seeding overwrites, or replay vulnerability.
 * 2. API error handling for all edge cases (invalid amounts, insufficient funds, unknown accounts, replays, invalid signatures, expired instructions).
 * 3. Security posture: No leak of private keys, stack traces, or decrypted sensitive payloads in API responses.
 * 4. Full regression testing for mesh payments, direct transfers, duplicate rejection, and reconciliation.
 */
@SpringBootTest
class OperationalHardeningTest {

    @Autowired
    private ApiController apiController;

    @Autowired
    private SettlementService settlementService;

    @Autowired
    private ReconciliationService reconciliationService;

    @Autowired
    private BridgeIngestionService bridgeIngestionService;

    @Autowired
    private CryptoService cryptoService;

    @Autowired
    private AccountRepository accountRepository;

    @Autowired
    private TransactionRepository transactionRepository;

    @Autowired
    private ProcessedPacketRepository processedPacketRepository;

    @Autowired
    private MeshSimulatorService meshSimulatorService;

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

    private MeshPacket createSignedMeshPacket(String from, String to, BigDecimal amount, KeyPair signerKey) throws GeneralSecurityException {
        PaymentInstruction unsigned = PaymentInstruction.create(from, to, amount);
        String signature = cryptoService.signBase64(unsigned.toCanonicalBytes(), signerKey.getPrivate());
        PaymentInstruction signed = unsigned.withSignature(signature);

        String json = bridgeIngestionService.serializeInstruction(signed);
        com.demo.upimesh.EncryptedPacket encryptedPacket = cryptoService.encrypt(json, bridgeKeyPair.getPublic());
        return MeshPacket.create("node_test_sender", "BRIDGE", 5, encryptedPacket);
    }

    @Test
    @DisplayName("1. DataSeeder never overwrites existing account balances on simulated restart")
    void testDataSeederDoesNotResetExistingBalancesOnRestart() {
        // Alice starts at 5000.00, Bob at 1000.00. Execute transfer of 600.00
        settlementService.transfer("alice", "bob", new BigDecimal("600.00"));
        assertEquals(new BigDecimal("4400.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1600.00"), accountRepository.findById("bob").orElseThrow().getBalance());

        // Simulate application restart: DataSeeder CommandLineRunner executes
        DataSeeder seeder = new DataSeeder(accountRepository);
        seeder.run();

        // Balances must remain exactly at post-transfer state (4400.00 / 1600.00), NEVER reset to default seed (5000.00 / 1000.00)
        assertEquals(new BigDecimal("4400.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1600.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(new BigDecimal("2000.00"), accountRepository.findById("carol").orElseThrow().getBalance());
        assertEquals(3, accountRepository.count());
        assertEquals(1, transactionRepository.count());
    }

    @Test
    @DisplayName("2. Genuine file-backed H2 database persistence across connection closures and restarts")
    void testFileBackedH2PersistenceAcrossRestarts() throws Exception {
        Path testDir = Path.of("./target/test-data");
        Files.createDirectories(testDir);
        String dbPath = "./target/test-data/file_persist_test_" + System.currentTimeMillis();
        String jdbcUrl = "jdbc:h2:file:" + dbPath + ";DB_CLOSE_DELAY=0";

        // Phase 1: Open file-backed DB, create schema, and insert data
        try (Connection conn = DriverManager.getConnection(jdbcUrl, "sa", "")) {
            try (Statement stmt = conn.createStatement()) {
                stmt.execute("CREATE TABLE test_accounts (id VARCHAR(50) PRIMARY KEY, balance DECIMAL(19, 2))");
                stmt.execute("INSERT INTO test_accounts VALUES ('alice', 4200.00), ('bob', 1800.00)");
            }
        } // Connection closed completely, DB flushed to disk

        // Phase 2: Re-open file-backed DB to simulate application restart reading persistent disk files
        try (Connection conn2 = DriverManager.getConnection(jdbcUrl, "sa", "")) {
            try (PreparedStatement ps = conn2.prepareStatement("SELECT balance FROM test_accounts WHERE id = ?")) {
                ps.setString(1, "alice");
                try (ResultSet rs = ps.executeQuery()) {
                    assertTrue(rs.next(), "Alice record must exist after restart");
                    assertEquals(new BigDecimal("4200.00"), rs.getBigDecimal("balance"));
                }

                ps.setString(1, "bob");
                try (ResultSet rs = ps.executeQuery()) {
                    assertTrue(rs.next(), "Bob record must exist after restart");
                    assertEquals(new BigDecimal("1800.00"), rs.getBigDecimal("balance"));
                }
            }
        }
    }

    @Test
    @DisplayName("3. Persistent idempotency survives service re-instantiation across restarts")
    void testPersistentIdempotencySurvivesServiceRestart() throws GeneralSecurityException {
        MeshPacket packet = createSignedMeshPacket("alice", "bob", new BigDecimal("150.00"), aliceKeyPair);
        String packetHash = new IdempotencyService().computeHash(packet.payload());

        // Ingest once
        PaymentInstruction settled = bridgeIngestionService.ingest(packet, bridgeKeyPair.getPrivate());
        assertNotNull(settled);
        assertEquals(1, processedPacketRepository.count());

        // Simulate fresh application restart: new IdempotencyService and BridgeIngestionService
        // backed by the durable database repository
        IdempotencyService freshIdempotencyService = new IdempotencyService(processedPacketRepository);
        assertTrue(freshIdempotencyService.isSettled(packetHash), "Must report settled based on persistent database");
        assertFalse(freshIdempotencyService.tryClaim(packetHash), "Claim must fail on restart for already-settled hash");

        BridgeIngestionService freshBridge = new BridgeIngestionService(
                cryptoService,
                settlementService,
                freshIdempotencyService,
                bridgeIngestionService.getSenderKeyRegistry()
        );

        // Attempting to ingest the same packet via fresh bridge instance must be rejected
        DuplicatePacketException ex = assertThrows(DuplicatePacketException.class, () ->
                freshBridge.ingest(packet, bridgeKeyPair.getPrivate())
        );
        assertTrue(ex.getMessage().contains("Duplicate packet rejected"));

        // Balances and ledger unchanged
        assertEquals(new BigDecimal("4850.00"), accountRepository.findById("alice").orElseThrow().getBalance());
        assertEquals(new BigDecimal("1150.00"), accountRepository.findById("bob").orElseThrow().getBalance());
        assertEquals(1, transactionRepository.count());
    }

    @Test
    @DisplayName("4. Direct transfers via POST /api/transfer continue working reliably")
    void directTransfer_worksReliably() {
        String result = apiController.transfer("alice", "bob", new BigDecimal("300.00"));
        assertEquals("OK", result);

        Account alice = accountRepository.findById("alice").orElseThrow();
        Account bob = accountRepository.findById("bob").orElseThrow();
        assertEquals(new BigDecimal("4700.00"), alice.getBalance());
        assertEquals(new BigDecimal("1300.00"), bob.getBalance());
        assertEquals(1, transactionRepository.count());
    }

    @Test
    @DisplayName("5. API error handling returns HTTP 400 Bad Request for invalid amounts without leaking stack traces")
    void apiErrorHandling_invalidAmounts() {
        IllegalArgumentException ex1 = assertThrows(IllegalArgumentException.class, () ->
                apiController.transfer("alice", "bob", new BigDecimal("-50.00"))
        );
        ResponseEntity<String> resp1 = apiController.handleBadRequest(ex1);
        assertEquals(HttpStatus.BAD_REQUEST, resp1.getStatusCode());
        assertTrue(resp1.getBody().contains("greater than zero"));
        assertFalse(resp1.getBody().contains("Exception"));

        IllegalArgumentException ex2 = assertThrows(IllegalArgumentException.class, () ->
                apiController.transfer("alice", "bob", BigDecimal.ZERO)
        );
        ResponseEntity<String> resp2 = apiController.handleBadRequest(ex2);
        assertEquals(HttpStatus.BAD_REQUEST, resp2.getStatusCode());
        assertTrue(resp2.getBody().contains("greater than zero"));
    }

    @Test
    @DisplayName("6. API error handling returns HTTP 400 Bad Request for insufficient funds without leaking stack traces")
    void apiErrorHandling_insufficientFunds() {
        IllegalStateException ex = assertThrows(IllegalStateException.class, () ->
                apiController.transfer("alice", "bob", new BigDecimal("10000.00"))
        );
        ResponseEntity<String> resp = apiController.handleIllegalState(ex);
        assertEquals(HttpStatus.BAD_REQUEST, resp.getStatusCode());
        assertTrue(resp.getBody().contains("Insufficient funds"));
        assertFalse(resp.getBody().contains("at com.demo"));
    }

    @Test
    @DisplayName("7. API error handling returns HTTP 400 Bad Request for unknown accounts and self-transfers")
    void apiErrorHandling_unknownAccountsAndSelfTransfers() {
        IllegalArgumentException ex1 = assertThrows(IllegalArgumentException.class, () ->
                apiController.transfer("nonexistent_user", "bob", new BigDecimal("100.00"))
        );
        ResponseEntity<String> resp1 = apiController.handleBadRequest(ex1);
        assertEquals(HttpStatus.BAD_REQUEST, resp1.getStatusCode());
        assertTrue(resp1.getBody().contains("No account: nonexistent_user"));

        IllegalArgumentException ex2 = assertThrows(IllegalArgumentException.class, () ->
                apiController.transfer("alice", "alice", new BigDecimal("100.00"))
        );
        ResponseEntity<String> resp2 = apiController.handleBadRequest(ex2);
        assertEquals(HttpStatus.BAD_REQUEST, resp2.getStatusCode());
        assertTrue(resp2.getBody().contains("Sender and receiver must be different"));
    }

    @Test
    @DisplayName("8. Duplicate packet replay is rejected with HTTP 400 Bad Request")
    void apiErrorHandling_duplicatePacketReplay() throws GeneralSecurityException {
        MeshPacket packet = createSignedMeshPacket("alice", "bob", new BigDecimal("150.00"), aliceKeyPair);

        assertNotNull(bridgeIngestionService.ingest(packet, bridgeKeyPair.getPrivate()));
        assertEquals(1, transactionRepository.count());

        DuplicatePacketException ex = assertThrows(DuplicatePacketException.class, () ->
                bridgeIngestionService.ingest(packet, bridgeKeyPair.getPrivate())
        );

        ResponseEntity<String> resp = apiController.handleDuplicatePacket(ex);
        assertEquals(HttpStatus.BAD_REQUEST, resp.getStatusCode());
        assertTrue(resp.getBody().contains("Duplicate packet rejected"));
        assertEquals(1, transactionRepository.count());
    }

    @Test
    @DisplayName("9. Invalid digital signature is rejected at bridge without leaking private keys")
    void apiErrorHandling_invalidSignatureRejection() throws GeneralSecurityException {
        PaymentInstruction unsigned = PaymentInstruction.create("alice", "bob", new BigDecimal("100.00"));
        String forgedSignature = cryptoService.signBase64(unsigned.toCanonicalBytes(), bobKeyPair.getPrivate());
        PaymentInstruction forgedInstruction = unsigned.withSignature(forgedSignature);

        String json = bridgeIngestionService.serializeInstruction(forgedInstruction);
        com.demo.upimesh.EncryptedPacket encryptedPacket = cryptoService.encrypt(json, bridgeKeyPair.getPublic());
        MeshPacket meshPacket = MeshPacket.create("node_test", "BRIDGE", 5, encryptedPacket);

        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () ->
                bridgeIngestionService.ingest(meshPacket, bridgeKeyPair.getPrivate())
        );

        ResponseEntity<String> resp = apiController.handleBadRequest(ex);
        assertEquals(HttpStatus.BAD_REQUEST, resp.getStatusCode());
        assertTrue(resp.getBody().contains("Invalid digital signature for sender: alice"));
        assertFalse(resp.getBody().contains("PRIVATE KEY"));
        assertEquals(0, transactionRepository.count());
    }

    @Test
    @DisplayName("10. Expired payment instruction is rejected at bridge boundary")
    void apiErrorHandling_expiredInstructionRejection() throws GeneralSecurityException {
        PaymentInstruction expiredUnsigned = new PaymentInstruction(
                "expired-payment-id",
                "alice",
                "bob",
                new BigDecimal("80.00"),
                Instant.now().minusSeconds(25 * 3600),
                "nonce-expired-1",
                null
        );
        String sig = cryptoService.signBase64(expiredUnsigned.toCanonicalBytes(), aliceKeyPair.getPrivate());
        PaymentInstruction expiredSigned = expiredUnsigned.withSignature(sig);

        String json = bridgeIngestionService.serializeInstruction(expiredSigned);
        com.demo.upimesh.EncryptedPacket encryptedPacket = cryptoService.encrypt(json, bridgeKeyPair.getPublic());
        MeshPacket meshPacket = MeshPacket.create("node_test", "BRIDGE", 5, encryptedPacket);

        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () ->
                bridgeIngestionService.ingest(meshPacket, bridgeKeyPair.getPrivate())
        );

        ResponseEntity<String> resp = apiController.handleBadRequest(ex);
        assertEquals(HttpStatus.BAD_REQUEST, resp.getStatusCode());
        assertTrue(resp.getBody().contains("Payment instruction has expired"));
        assertEquals(0, transactionRepository.count());
    }

    @Test
    @DisplayName("11. Unexpected server errors return sanitized HTTP 500 without leaking internal stack traces")
    void apiErrorHandling_genericExceptionNeverLeaksStackTraces() {
        RuntimeException unexpected = new RuntimeException("Unexpected internal NullPointer in core engine");
        ResponseEntity<String> resp = apiController.handleGenericException(unexpected);

        assertEquals(HttpStatus.INTERNAL_SERVER_ERROR, resp.getStatusCode());
        assertEquals("An internal error occurred. Please check system logs.", resp.getBody());
        assertFalse(resp.getBody().contains("NullPointer"));
        assertFalse(resp.getBody().contains("at com.demo"));
    }

    @Test
    @DisplayName("12. Reconciliation reporting endpoint GET /api/reconciliation returns accurate report")
    void reconciliationReporting_viaEndpoint() {
        settlementService.transfer("alice", "bob", new BigDecimal("250.00"));

        ResponseEntity<ReconciliationReport> response = apiController.getReconciliation();
        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertNotNull(response.getBody());

        ReconciliationReport report = response.getBody();
        assertTrue(report.isReconciled());
        assertTrue(report.isLedgerBalanced());
        assertTrue(report.isBalancesReconciled());
        assertEquals(1, report.totalTransactionsChecked());
        assertEquals(new BigDecimal("250.00"), report.totalLedgerDebits());
        assertEquals(new BigDecimal("250.00"), report.totalLedgerCredits());
        assertTrue(report.discrepancies().isEmpty());
    }

    @Test
    @DisplayName("13. End-to-end simulated mesh transfer via POST /api/mesh/transfer executes successfully")
    void endToEndSimulatedMeshTransfer_viaApi() {
        ResponseEntity<MeshPaymentResult> response = apiController.simulateMeshTransfer(
                "alice", "bob", new BigDecimal("175.00"), 5
        );

        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertNotNull(response.getBody());
        MeshPaymentResult result = response.getBody();
        assertTrue(result.success());
        assertEquals("SETTLED", result.status());
        assertEquals("alice", result.fromAccount());
        assertEquals("bob", result.toAccount());
        assertEquals(new BigDecimal("175.00"), result.amount());
        assertTrue(result.hopsTaken() >= 2);
        assertNotNull(result.encryptedKeySnippet());
        assertNotNull(result.ivHex());
        assertFalse(result.encryptedKeySnippet().contains("PRIVATE KEY"));
        assertFalse(result.message().contains("PRIVATE KEY"));

        Account alice = accountRepository.findById("alice").orElseThrow();
        Account bob = accountRepository.findById("bob").orElseThrow();
        assertEquals(new BigDecimal("4825.00"), alice.getBalance());
        assertEquals(new BigDecimal("1175.00"), bob.getBalance());
        assertEquals(1, transactionRepository.count());
    }
}
