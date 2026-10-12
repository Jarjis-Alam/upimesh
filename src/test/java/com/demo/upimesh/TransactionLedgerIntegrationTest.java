package com.demo.upimesh;

import com.demo.upimesh.model.Account;
import com.demo.upimesh.model.AccountRepository;
import com.demo.upimesh.model.MeshPacket;
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
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

@SpringBootTest
class TransactionLedgerIntegrationTest {

    @Autowired
    private SettlementService settlementService;

    @Autowired
    private AccountRepository accountRepository;

    @Autowired
    private TransactionRepository transactionRepository;

    @Autowired
    private ApiController apiController;

    @Autowired
    private BridgeIngestionService bridgeIngestionService;

    @Autowired
    private CryptoService cryptoService;

    @BeforeEach
    void resetData() {
        transactionRepository.deleteAll();
        accountRepository.deleteAll();
        accountRepository.save(new Account("alice", new BigDecimal("5000.00")));
        accountRepository.save(new Account("bob", new BigDecimal("1000.00")));
        accountRepository.save(new Account("carol", new BigDecimal("2000.00")));
    }

    @Test
    @DisplayName("A successful transfer updates both balances and creates exactly one ledger entry")
    void successfulTransferUpdatesBalancesAndCreatesLedgerEntry() {
        settlementService.transfer("alice", "bob", new BigDecimal("500.00"));

        Account alice = accountRepository.findById("alice").orElseThrow();
        Account bob = accountRepository.findById("bob").orElseThrow();

        assertEquals(0, new BigDecimal("4500.00").compareTo(alice.getBalance()));
        assertEquals(0, new BigDecimal("1500.00").compareTo(bob.getBalance()));

        List<Transaction> transactions = transactionRepository.findAll();
        assertEquals(1, transactions.size());
        Transaction tx = transactions.get(0);
        assertNotNull(tx.getId());
        assertEquals("alice", tx.getFromAccount());
        assertEquals("bob", tx.getToAccount());
        assertEquals(0, new BigDecimal("500.00").compareTo(tx.getAmount()));
        assertEquals("SETTLED", tx.getStatus());
        assertNotNull(tx.getTimestamp());
    }

    @Test
    @DisplayName("An insufficient-funds transfer changes neither balances nor ledger history")
    void insufficientFundsChangesNeitherBalancesNorLedgerHistory() {
        assertThrows(IllegalStateException.class, () ->
                settlementService.transfer("alice", "bob", new BigDecimal("999999.00"))
        );

        Account alice = accountRepository.findById("alice").orElseThrow();
        Account bob = accountRepository.findById("bob").orElseThrow();

        assertEquals(0, new BigDecimal("5000.00").compareTo(alice.getBalance()));
        assertEquals(0, new BigDecimal("1000.00").compareTo(bob.getBalance()));

        assertEquals(0, transactionRepository.count(), "Ledger must contain no entries after rolled back transfer");
    }

    @Test
    @DisplayName("A rejected zero-amount or self-transfer creates no ledger entry")
    void rejectedInvalidTransfersCreateNoLedger() {
        assertThrows(IllegalArgumentException.class, () ->
                settlementService.transfer("alice", "alice", new BigDecimal("100.00"))
        );

        assertThrows(IllegalArgumentException.class, () ->
                settlementService.transfer("alice", "bob", BigDecimal.ZERO)
        );

        assertThrows(IllegalArgumentException.class, () ->
                settlementService.transfer("alice", "bob", new BigDecimal("-50.00"))
        );

        assertEquals(0, transactionRepository.count(), "No transactions should be recorded for invalid input");
    }

    @Test
    @DisplayName("Transaction history is returned newest first")
    void transactionHistoryReturnedNewestFirst() throws InterruptedException {
        settlementService.transfer("alice", "bob", new BigDecimal("100.00"));
        Thread.sleep(10); // Guarantee discrete timestamps
        settlementService.transfer("bob", "carol", new BigDecimal("50.00"));

        List<Transaction> transactions = apiController.getTransactions();

        assertEquals(2, transactions.size());
        assertEquals("bob", transactions.get(0).getFromAccount(), "Newest transaction must appear first");
        assertEquals("carol", transactions.get(0).getToAccount());
        assertEquals("alice", transactions.get(1).getFromAccount(), "Older transaction must appear second");
        assertEquals("bob", transactions.get(1).getToAccount());
        assertTrue(transactions.get(0).getTimestamp().isAfter(transactions.get(1).getTimestamp()) ||
                   transactions.get(0).getTimestamp().equals(transactions.get(1).getTimestamp()));
    }

    @Test
    @DisplayName("Bridge-based settlement creates a ledger entry")
    void bridgeBasedSettlementCreatesLedgerEntry() throws GeneralSecurityException {
        KeyPair serverKeyPair = cryptoService.generateRsaKeyPair();
        KeyPair carolKey = cryptoService.generateRsaKeyPair();
        bridgeIngestionService.getSenderKeyRegistry().registerKey("carol", carolKey.getPublic());

        PaymentInstruction instruction = PaymentInstruction.create("carol", "alice", new BigDecimal("300.00"));
        String sig = cryptoService.signBase64(instruction.toCanonicalBytes(), carolKey.getPrivate());
        instruction = instruction.withSignature(sig);

        String json = bridgeIngestionService.serializeInstruction(instruction);
        EncryptedPacket encryptedPacket = cryptoService.encrypt(json, serverKeyPair.getPublic());
        MeshPacket meshPacket = MeshPacket.create("device_1", "BRIDGE", 5, encryptedPacket);

        PaymentInstruction settled = bridgeIngestionService.ingest(meshPacket, serverKeyPair.getPrivate());
        assertNotNull(settled);

        Account carol = accountRepository.findById("carol").orElseThrow();
        Account alice = accountRepository.findById("alice").orElseThrow();

        assertEquals(0, new BigDecimal("1700.00").compareTo(carol.getBalance()));
        assertEquals(0, new BigDecimal("5300.00").compareTo(alice.getBalance()));

        List<Transaction> transactions = transactionRepository.findAll();
        assertEquals(1, transactions.size());
        assertEquals("carol", transactions.get(0).getFromAccount());
        assertEquals("alice", transactions.get(0).getToAccount());
        assertEquals(0, new BigDecimal("300.00").compareTo(transactions.get(0).getAmount()));
        assertEquals("SETTLED", transactions.get(0).getStatus());
    }

    @Test
    @DisplayName("Existing bridge idempotency prevents duplicate settlement and duplicate ledger entries")
    void duplicateBridgeSettlementCreatesNoDuplicateLedgerEntry() throws GeneralSecurityException {
        KeyPair serverKeyPair = cryptoService.generateRsaKeyPair();
        KeyPair aliceKey = cryptoService.generateRsaKeyPair();
        bridgeIngestionService.getSenderKeyRegistry().registerKey("alice", aliceKey.getPublic());

        PaymentInstruction instruction = PaymentInstruction.create("alice", "bob", new BigDecimal("200.00"));
        String sig = cryptoService.signBase64(instruction.toCanonicalBytes(), aliceKey.getPrivate());
        instruction = instruction.withSignature(sig);

        String json = bridgeIngestionService.serializeInstruction(instruction);
        EncryptedPacket encryptedPacket = cryptoService.encrypt(json, serverKeyPair.getPublic());
        MeshPacket meshPacket = MeshPacket.create("device_1", "BRIDGE", 5, encryptedPacket);

        // First ingestion succeeds
        bridgeIngestionService.ingest(meshPacket, serverKeyPair.getPrivate());
        assertEquals(1, transactionRepository.count());

        // Duplicate presentation of exact same packet must throw DuplicatePacketException
        assertThrows(DuplicatePacketException.class, () ->
                bridgeIngestionService.ingest(meshPacket, serverKeyPair.getPrivate())
        );

        // Verify ledger has not been duplicated and balances only transferred once
        assertEquals(1, transactionRepository.count(), "Ledger entry count must not increase on duplicate packet");
        Account alice = accountRepository.findById("alice").orElseThrow();
        Account bob = accountRepository.findById("bob").orElseThrow();
        assertEquals(0, new BigDecimal("4800.00").compareTo(alice.getBalance()));
        assertEquals(0, new BigDecimal("1200.00").compareTo(bob.getBalance()));
    }
}
