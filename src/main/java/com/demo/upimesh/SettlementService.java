package com.demo.upimesh;

import com.demo.upimesh.model.Account;
import com.demo.upimesh.model.AccountRepository;
import com.demo.upimesh.model.PaymentInstruction;
import com.demo.upimesh.model.ProcessedPacket;
import com.demo.upimesh.model.ProcessedPacketRepository;
import com.demo.upimesh.model.Transaction;
import com.demo.upimesh.model.TransactionRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

@Service
public class SettlementService {

    private final AccountRepository accountRepository;
    private final TransactionRepository transactionRepository;
    private final ProcessedPacketRepository processedPacketRepository;

    @Autowired
    public SettlementService(
            AccountRepository accountRepository,
            TransactionRepository transactionRepository,
            ProcessedPacketRepository processedPacketRepository
    ) {
        this.accountRepository = accountRepository;
        this.transactionRepository = transactionRepository;
        this.processedPacketRepository = processedPacketRepository;
    }

    public SettlementService(AccountRepository accountRepository, TransactionRepository transactionRepository) {
        this(accountRepository, transactionRepository, null);
    }

    public SettlementService(AccountRepository accountRepository) {
        this(accountRepository, null, null);
    }

    /**
     * Direct account transfer (e.g. for non-mesh manual transfers).
     */
    @Transactional
    public void transfer(String from, String to, BigDecimal amount) {
        if (amount == null || amount.compareTo(BigDecimal.ZERO) <= 0) {
            throw new IllegalArgumentException(
                    "Transfer amount must be greater than zero"
            );
        }

        if (from == null || from.isBlank() || to == null || to.isBlank()) {
            throw new IllegalArgumentException(
                    "Sender and receiver accounts must not be blank"
            );
        }

        if (from.equalsIgnoreCase(to)) {
            throw new IllegalArgumentException(
                    "Sender and receiver must be different"
            );
        }

        Account fromAccount = accountRepository.findById(from)
                .orElseThrow(() -> new IllegalArgumentException("No account: " + from));
        Account toAccount = accountRepository.findById(to)
                .orElseThrow(() -> new IllegalArgumentException("No account: " + to));

        if (fromAccount.getBalance().compareTo(amount) < 0) {
            throw new IllegalStateException("Insufficient funds");
        }

        fromAccount.setBalance(fromAccount.getBalance().subtract(amount));
        toAccount.setBalance(toAccount.getBalance().add(amount));

        accountRepository.save(fromAccount);
        accountRepository.save(toAccount);

        Transaction transaction = new Transaction(
                UUID.randomUUID().toString(),
                from,
                to,
                amount,
                Instant.now(),
                "SETTLED"
        );
        if (transactionRepository != null) {
            transactionRepository.save(transaction);
        }
    }

    /**
     * Atomically coordinates account balance updates, transaction ledger persistence, and
     * durable idempotency packet recording within a single database transaction.
     * <p>
     * Concurrency Safety:
     * Enforces unique constraint on packetHash at the database level. Any concurrent attempt
     * to settle the same packet will fail with a uniqueness constraint violation and rollback
     * without leaving corrupted balances or duplicate ledger entries.
     */
    @Transactional
    public void settlePayment(PaymentInstruction instruction, String packetHash) {
        if (instruction == null) {
            throw new IllegalArgumentException("PaymentInstruction must not be null");
        }
        if (packetHash == null || packetHash.isBlank()) {
            throw new IllegalArgumentException("packetHash must not be blank");
        }

        // 1. Fast check against persistent duplicate store (ciphertext hash)
        if (processedPacketRepository != null && processedPacketRepository.existsByPacketHash(packetHash)) {
            throw new DuplicatePacketException("Duplicate packet rejected (already settled): " + packetHash);
        }

        // 2. Persistent replay protection against re-encrypted payment instructions (paymentId uniqueness)
        if (processedPacketRepository != null && processedPacketRepository.existsByPaymentId(instruction.paymentId())) {
            throw new DuplicatePacketException("Duplicate payment rejected (paymentId already settled): " + instruction.paymentId());
        }

        // 3. Persistent replay protection against nonce reuse for the same sender
        if (processedPacketRepository != null && processedPacketRepository.existsByFromAccountAndNonce(instruction.fromAccount().toLowerCase(), instruction.nonce())) {
            throw new DuplicatePacketException("Replayed payment rejected (nonce already used for sender " + instruction.fromAccount() + "): " + instruction.nonce());
        }

        // Perform balance transfer and ledger record
        transfer(instruction.fromAccount(), instruction.toAccount(), instruction.amount());

        // Durably record processed packet idempotency claim and replay protection
        if (processedPacketRepository != null) {
            ProcessedPacket record = new ProcessedPacket(
                    UUID.randomUUID().toString(),
                    packetHash,
                    instruction.paymentId(),
                    instruction.fromAccount().toLowerCase(),
                    instruction.toAccount().toLowerCase(),
                    instruction.nonce(),
                    instruction.amount(),
                    "SETTLED",
                    Instant.now()
            );
            processedPacketRepository.save(record);
        }
    }
}
