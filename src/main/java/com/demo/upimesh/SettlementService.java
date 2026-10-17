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
import java.util.Optional;
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

        String firstId = from.compareToIgnoreCase(to) < 0 ? from : to;
        String secondId = from.compareToIgnoreCase(to) < 0 ? to : from;
        Account firstAccount = accountRepository.findById(firstId)
                .orElseThrow(() -> new IllegalArgumentException("No account: " + firstId));
        Account secondAccount = accountRepository.findById(secondId)
                .orElseThrow(() -> new IllegalArgumentException("No account: " + secondId));
        Account fromAccount = from.equalsIgnoreCase(firstId) ? firstAccount : secondAccount;
        Account toAccount = to.equalsIgnoreCase(firstId) ? firstAccount : secondAccount;

        if (fromAccount.getBalance().compareTo(amount) < 0) {
            throw new IllegalStateException("Insufficient funds");
        }

        fromAccount.setBalance(fromAccount.getBalance().subtract(amount));
        toAccount.setBalance(toAccount.getBalance().add(amount));

        // Deterministic ordering to prevent lock cycle deadlocks on opposing transfers
        accountRepository.save(firstAccount);
        accountRepository.save(secondAccount);

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
     * Safely queries the authoritative settled payment record by payment ID.
     */
    public Optional<ProcessedPacket> findSettledPayment(String paymentId) {
        if (paymentId == null || paymentId.isBlank() || processedPacketRepository == null) {
            return Optional.empty();
        }
        return processedPacketRepository.findByPaymentId(paymentId.trim());
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

        if (processedPacketRepository != null) {
            // 1. Check for existing payment by paymentId (distinguishing identical duplicates from conflicting reuse)
            Optional<ProcessedPacket> existingByPaymentId = processedPacketRepository.findByPaymentId(instruction.paymentId());
            if (existingByPaymentId.isPresent()) {
                ProcessedPacket existing = existingByPaymentId.get();
                boolean matches = existing.getFromAccount().equalsIgnoreCase(instruction.fromAccount())
                        && (existing.getToAccount() == null || existing.getToAccount().equalsIgnoreCase(instruction.toAccount()))
                        && (existing.getAmount() == null || existing.getAmount().compareTo(instruction.amount()) == 0)
                        && existing.getNonce().equals(instruction.nonce());
                if (!matches) {
                    throw new DuplicatePacketException(
                            "Conflicting payment instruction rejected: paymentId '" + instruction.paymentId() + "' was already settled with different instruction parameters"
                    );
                }
                throw new DuplicatePacketException("Duplicate payment rejected (paymentId already settled): " + instruction.paymentId());
            }

            // 2. Persistent replay protection against nonce reuse for the same sender across different payments
            Optional<ProcessedPacket> existingByNonce = processedPacketRepository.findByFromAccountAndNonce(
                    instruction.fromAccount().toLowerCase(),
                    instruction.nonce()
            );
            if (existingByNonce.isPresent()) {
                ProcessedPacket existing = existingByNonce.get();
                if (!existing.getPaymentId().equals(instruction.paymentId())) {
                    throw new DuplicatePacketException(
                            "Replayed payment rejected (nonce already used for sender " + instruction.fromAccount() + "): " + instruction.nonce()
                    );
                }
            }

            // 3. Fast check against persistent duplicate store (ciphertext or canonical hash)
            if (processedPacketRepository.existsByPacketHash(packetHash)) {
                throw new DuplicatePacketException("Duplicate packet rejected (already settled): " + packetHash);
            }
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
