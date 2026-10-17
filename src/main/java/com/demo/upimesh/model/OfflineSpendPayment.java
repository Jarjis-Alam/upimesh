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
 * JPA entity representing a durably settled offline spend payment consumed against an allowance.
 * <p>
 * Database-enforced Uniqueness Constraints:
 * 1. uk_spend_payment_id: Ensures no payment instruction can ever settle twice.
 * 2. uk_allowance_sequence: Ensures that within a given allowance, every sequence number can only
 *    settle once, preventing sequence-reuse fraud and forking attacks.
 */
@Entity
@Table(
        name = "offline_spend_payments",
        uniqueConstraints = {
                @UniqueConstraint(name = "uk_spend_payment_id", columnNames = {"payment_id"}),
                @UniqueConstraint(name = "uk_allowance_sequence", columnNames = {"allowance_id", "sequence_number"})
        }
)
public class OfflineSpendPayment {

    @Id
    @Column(name = "id", nullable = false, length = 64)
    private String id;

    @Column(name = "payment_id", nullable = false, unique = true, length = 64)
    private String paymentId;

    @Column(name = "allowance_id", nullable = false, length = 64)
    private String allowanceId;

    @Column(name = "payer_account_id", nullable = false, length = 64)
    private String payerAccountId;

    @Column(name = "payer_device_id", nullable = false, length = 128)
    private String payerDeviceId;

    @Column(name = "recipient_account_id", nullable = false, length = 64)
    private String recipientAccountId;

    @Column(name = "amount", nullable = false, precision = 19, scale = 2)
    private BigDecimal amount;

    @Column(name = "currency", nullable = false, length = 12)
    private String currency;

    @Column(name = "sequence_number", nullable = false)
    private int sequenceNumber;

    @Column(name = "cumulative_spent_amount", nullable = false, precision = 19, scale = 2)
    private BigDecimal cumulativeSpentAmount;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "settled_at", nullable = false)
    private Instant settledAt;

    @Column(name = "status", nullable = false, length = 32)
    private String status;

    @Column(name = "voucher_signature", nullable = false, columnDefinition = "TEXT")
    private String voucherSignature;

    @Column(name = "payer_signature", nullable = false, columnDefinition = "TEXT")
    private String payerSignature;

    @Column(name = "protocol_version", nullable = false)
    private int protocolVersion;

    public OfflineSpendPayment() {
    }

    public OfflineSpendPayment(
            String id,
            String paymentId,
            String allowanceId,
            String payerAccountId,
            String payerDeviceId,
            String recipientAccountId,
            BigDecimal amount,
            String currency,
            int sequenceNumber,
            BigDecimal cumulativeSpentAmount,
            Instant createdAt,
            Instant settledAt,
            String status,
            String voucherSignature,
            String payerSignature,
            int protocolVersion
    ) {
        if (id == null || id.isBlank()) throw new IllegalArgumentException("id must not be blank");
        if (paymentId == null || paymentId.isBlank()) throw new IllegalArgumentException("paymentId must not be blank");
        if (allowanceId == null || allowanceId.isBlank()) throw new IllegalArgumentException("allowanceId must not be blank");
        if (payerAccountId == null || payerAccountId.isBlank()) throw new IllegalArgumentException("payerAccountId must not be blank");
        if (payerDeviceId == null || payerDeviceId.isBlank()) throw new IllegalArgumentException("payerDeviceId must not be blank");
        if (recipientAccountId == null || recipientAccountId.isBlank()) throw new IllegalArgumentException("recipientAccountId must not be blank");
        if (amount == null || amount.compareTo(BigDecimal.ZERO) <= 0) throw new IllegalArgumentException("amount must be positive");

        this.id = id.trim();
        this.paymentId = paymentId.trim();
        this.allowanceId = allowanceId.trim();
        this.payerAccountId = payerAccountId.trim().toLowerCase();
        this.payerDeviceId = payerDeviceId.trim();
        this.recipientAccountId = recipientAccountId.trim().toLowerCase();
        this.amount = amount;
        this.currency = currency != null ? currency.trim().toUpperCase() : "INR";
        this.sequenceNumber = sequenceNumber;
        this.cumulativeSpentAmount = cumulativeSpentAmount;
        this.createdAt = createdAt != null ? createdAt : Instant.now();
        this.settledAt = settledAt != null ? settledAt : Instant.now();
        this.status = status != null ? status : "SETTLED";
        this.voucherSignature = voucherSignature != null ? voucherSignature.trim() : "";
        this.payerSignature = payerSignature != null ? payerSignature.trim() : "";
        this.protocolVersion = protocolVersion > 0 ? protocolVersion : 1;
    }

    public String getId() {
        return id;
    }

    public String getPaymentId() {
        return paymentId;
    }

    public String getAllowanceId() {
        return allowanceId;
    }

    public String getPayerAccountId() {
        return payerAccountId;
    }

    public String getPayerDeviceId() {
        return payerDeviceId;
    }

    public String getRecipientAccountId() {
        return recipientAccountId;
    }

    public BigDecimal getAmount() {
        return amount;
    }

    public String getCurrency() {
        return currency;
    }

    public int getSequenceNumber() {
        return sequenceNumber;
    }

    public BigDecimal getCumulativeSpentAmount() {
        return cumulativeSpentAmount;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getSettledAt() {
        return settledAt;
    }

    public String getStatus() {
        return status;
    }

    public String getVoucherSignature() {
        return voucherSignature;
    }

    public String getPayerSignature() {
        return payerSignature;
    }

    public int getProtocolVersion() {
        return protocolVersion;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof OfflineSpendPayment that)) return false;
        return Objects.equals(paymentId, that.paymentId);
    }

    @Override
    public int hashCode() {
        return Objects.hashCode(paymentId);
    }
}
