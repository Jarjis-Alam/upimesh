package com.demo.upimesh;

import com.demo.upimesh.model.Account;
import com.demo.upimesh.model.AccountRepository;
import com.demo.upimesh.model.MeshPaymentResult;
import com.demo.upimesh.model.Transaction;
import com.demo.upimesh.model.TransactionRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import java.math.BigDecimal;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

@SpringBootTest
class EndToEndMeshPaymentTest {

    @Autowired
    private MeshSimulatorService meshSimulatorService;

    @Autowired
    private AccountRepository accountRepository;

    @Autowired
    private TransactionRepository transactionRepository;

    @Autowired
    private ApiController apiController;

    @BeforeEach
    void setUp() {
        // Reset repositories to deterministic seed state
        transactionRepository.deleteAll();
        accountRepository.deleteAll();

        accountRepository.saveAll(List.of(
                new Account("alice", new BigDecimal("5000.00")),
                new Account("bob", new BigDecimal("2000.00")),
                new Account("carol", new BigDecimal("1000.00"))
        ));

        meshSimulatorService.reset();
        meshSimulatorService.initDefaultTopology();
    }

    @Test
    @DisplayName("End-to-end mesh payment routes across virtual devices, settles at bridge, and records ledger")
    void successfulEndToEndMeshPayment_updatesBalancesAndRecordsLedger() {
        MeshPaymentResult result = meshSimulatorService.simulateMeshPayment("alice", "bob", new BigDecimal("350.00"), 5);

        assertTrue(result.success(), "Mesh payment should succeed");
        assertEquals("SETTLED", result.status());
        assertEquals("alice", result.fromAccount());
        assertEquals("bob", result.toAccount());
        assertEquals(new BigDecimal("350.00"), result.amount());
        assertEquals(2, result.hopsTaken(), "Path from Alice via Carol to Bridge is 2 hops");
        assertTrue(result.roundsRun() >= 2, "Should take at least 2 discrete gossip rounds");
        assertEquals(3, result.remainingTtl(), "Initial TTL 5 decremented by 2 hops equals 3");
        assertNotNull(result.encryptedKeySnippet());
        assertNotNull(result.ivHex());

        // Verify Account Balances updated atomically
        Account alice = accountRepository.findById("alice").orElseThrow();
        Account bob = accountRepository.findById("bob").orElseThrow();
        assertEquals(new BigDecimal("4650.00"), alice.getBalance());
        assertEquals(new BigDecimal("2350.00"), bob.getBalance());

        // Verify Transaction Ledger recorded exactly 1 entry
        List<Transaction> txs = transactionRepository.findAllByOrderByTimestampDesc();
        assertEquals(1, txs.size());
        Transaction tx = txs.get(0);
        assertEquals("alice", tx.getFromAccount());
        assertEquals("bob", tx.getToAccount());
        assertEquals(new BigDecimal("350.00"), tx.getAmount());
        assertEquals("SETTLED", tx.getStatus());
    }

    @Test
    @DisplayName("Insufficient balance causes rejection at bridge and preserves balances without ledger entry")
    void insufficientBalance_rejectsPaymentAtBridgeAndRollsBack() {
        MeshPaymentResult result = meshSimulatorService.simulateMeshPayment("alice", "bob", new BigDecimal("10000.00"), 5);

        assertFalse(result.success(), "Overdraft mesh payment should fail");
        assertEquals("REJECTED", result.status());
        assertTrue(result.message().contains("Insufficient funds"));

        // Balances must remain unchanged
        Account alice = accountRepository.findById("alice").orElseThrow();
        Account bob = accountRepository.findById("bob").orElseThrow();
        assertEquals(new BigDecimal("5000.00"), alice.getBalance());
        assertEquals(new BigDecimal("2000.00"), bob.getBalance());

        // No ledger entry
        assertEquals(0, transactionRepository.count());
    }

    @Test
    @DisplayName("Insufficient TTL expires packet before reaching bridge sink")
    void ttlExpiration_dropsPacketBeforeReachingBridge() {
        // TTL = 1 cannot make 2 hops to bridge
        MeshPaymentResult result = meshSimulatorService.simulateMeshPayment("alice", "bob", new BigDecimal("50.00"), 1);

        assertFalse(result.success(), "Packet with TTL=1 should expire before reaching bridge");
        assertEquals("EXPIRED", result.status());

        // Balances must remain unchanged
        Account alice = accountRepository.findById("alice").orElseThrow();
        assertEquals(new BigDecimal("5000.00"), alice.getBalance());
        assertEquals(0, transactionRepository.count());
    }

    @Test
    @DisplayName("ApiController /api/mesh/transfer executes end-to-end payment successfully")
    void apiControllerMeshTransfer_returnsHttp200AndValidResult() {
        var response = apiController.simulateMeshTransfer("alice", "bob", new BigDecimal("100.00"), 5);

        assertEquals(200, response.getStatusCode().value());
        MeshPaymentResult body = response.getBody();
        assertNotNull(body);
        assertTrue(body.success());
        assertEquals("SETTLED", body.status());

        Account alice = accountRepository.findById("alice").orElseThrow();
        assertEquals(new BigDecimal("4900.00"), alice.getBalance());
        assertEquals(1, transactionRepository.count());
    }

    @Test
    @DisplayName("ApiController /api/mesh/topology returns registered virtual devices and status")
    void apiControllerMeshTopology_returnsRegisteredDevices() {
        var topo = apiController.getMeshTopology();

        assertEquals("ONLINE", topo.get("status"));
        assertTrue((Boolean) topo.get("bridgePublicKey"));
        @SuppressWarnings("unchecked")
        List<?> devices = (List<?>) topo.get("devices");
        assertTrue(devices.size() >= 4, "Should have alice, bob, carol, and bridge registered");
    }
}
