package com.demo.upimesh.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.Objects;

/**
 * JPA entity representing a durably processed payment packet for persistent idempotency
 * and replay protection enforcement.
 * <p>
 * Database-enforced Uniqueness Constraints:
 * 1. uk_processed_packet_hash: ensures the exact encrypted packet payload (AES key, IV, ciphertext) cannot settle twice.
 * 2. uk_processed_payment_id: ensures the globally unique paymentId cannot settle twice even if re-encrypted with a different IV.
 * 3. uk_processed_from_nonce: ensures a sender cannot reuse the same cryptographic nonce across distinct instructions.
 * <p>
 * Security & Data Privacy:
 * - Deterministic SHA-256 hash computed over the complete encrypted payload (AES key, IV, ciphertext).
 * - Never stores private encryption or signing keys.
 */
@Entity
@Table(
        name = "processed_packets",
        uniqueConstraints = {
                @UniqueConstraint(name = "uk_processed_packet_hash", columnNames = {"packet_hash"}),
                @UniqueConstraint(name = "uk_processed_payment_id", columnNames = {"payment_id"}),
                @UniqueConstraint(name = "uk_processed_from_nonce", columnNames = {"from_account", "nonce"})
        }
)
public class ProcessedPacket {

    @Id
    private String id;

    @Column(name = "packet_hash", nullable = false, unique = true, length = 64)
    private String packetHash;

    @Column(name = "payment_id", nullable = false, unique = true)
    private String paymentId;

    @Column(name = "from_account", nullable = false)
    private String fromAccount;

    @Column(name = "to_account")
    private String toAccount;

    @Column(name = "nonce", nullable = false)
    private String nonce;

    @Column(name = "amount")
    private BigDecimal amount;

    @Column(name = "status", nullable = false)
    private String status;

    @Column(name = "settled_at", nullable = false)
    private Instant settledAt;

    public ProcessedPacket() {
    }

    public ProcessedPacket(
            String id,
            String packetHash,
            String paymentId,
            String fromAccount,
            String toAccount,
            String nonce,
            BigDecimal amount,
            String status,
            Instant settledAt
    ) {
        this.id = id;
        this.packetHash = packetHash;
        this.paymentId = paymentId;
        this.fromAccount = fromAccount;
        this.toAccount = toAccount;
        this.nonce = nonce;
        this.amount = amount;
        this.status = status;
        this.settledAt = settledAt;
    }

    public ProcessedPacket(
            String id,
            String packetHash,
            String paymentId,
            String fromAccount,
            String toAccount,
            BigDecimal amount,
            String status,
            Instant settledAt
    ) {
        this(id, packetHash, paymentId, fromAccount, toAccount, "", amount, status, settledAt);
    }

    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
    }

    public String getPacketHash() {
        return packetHash;
    }

    public void setPacketHash(String packetHash) {
        this.packetHash = packetHash;
    }

    public String getPaymentId() {
        return paymentId;
    }

    public void setPaymentId(String paymentId) {
        this.paymentId = paymentId;
    }

    public String getFromAccount() {
        return fromAccount;
    }

    public void setFromAccount(String fromAccount) {
        this.fromAccount = fromAccount;
    }

    public String getToAccount() {
        return toAccount;
    }

    public void setToAccount(String toAccount) {
        this.toAccount = toAccount;
    }

    public String getNonce() {
        return nonce;
    }

    public void setNonce(String nonce) {
        this.nonce = nonce;
    }

    public BigDecimal getAmount() {
        return amount;
    }

    public void setAmount(BigDecimal amount) {
        this.amount = amount;
    }

    public String getStatus() {
        return status;
    }

    public void setStatus(String status) {
        this.status = status;
    }

    public Instant getSettledAt() {
        return settledAt;
    }

    public void setSettledAt(Instant settledAt) {
        this.settledAt = settledAt;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof ProcessedPacket that)) return false;
        return Objects.equals(id, that.id)
                || Objects.equals(packetHash, that.packetHash)
                || Objects.equals(paymentId, that.paymentId);
    }

    @Override
    public int hashCode() {
        return Objects.hash(packetHash, paymentId);
    }
}
