package com.demo.upimesh.model;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.UUID;

public record PaymentInstruction(
        String paymentId,
        String fromAccount,
        String toAccount,
        BigDecimal amount,
        Instant createdAt,
        String nonce,
        String signature
) {
    public PaymentInstruction {
        if (paymentId == null || paymentId.isBlank()) {
            throw new IllegalArgumentException("paymentId must not be blank");
        }
        if (fromAccount == null || fromAccount.isBlank()) {
            throw new IllegalArgumentException("fromAccount must not be blank");
        }
        if (toAccount == null || toAccount.isBlank()) {
            throw new IllegalArgumentException("toAccount must not be blank");
        }
        if (fromAccount.equals(toAccount)) {
            throw new IllegalArgumentException("Sender and receiver must be different");
        }
        if (amount == null || amount.compareTo(BigDecimal.ZERO) <= 0) {
            throw new IllegalArgumentException("Transfer amount must be greater than zero");
        }
        if (createdAt == null) {
            throw new IllegalArgumentException("createdAt must not be null");
        }
        if (nonce == null || nonce.isBlank()) {
            throw new IllegalArgumentException("nonce must not be blank");
        }
    }

    /**
     * Backward-compatible 6-argument constructor with null signature.
     */
    public PaymentInstruction(
            String paymentId,
            String fromAccount,
            String toAccount,
            BigDecimal amount,
            Instant createdAt,
            String nonce
    ) {
        this(paymentId, fromAccount, toAccount, amount, createdAt, nonce, null);
    }

    /**
     * Factory method to create an unsigned PaymentInstruction with generated UUIDs and current timestamp.
     */
    public static PaymentInstruction create(String fromAccount, String toAccount, BigDecimal amount) {
        return new PaymentInstruction(
                UUID.randomUUID().toString(),
                fromAccount,
                toAccount,
                amount,
                Instant.now(),
                UUID.randomUUID().toString(),
                null
        );
    }

    /**
     * Returns a copy of this payment instruction with the specified digital signature.
     */
    public PaymentInstruction withSignature(String signature) {
        return new PaymentInstruction(
                this.paymentId,
                this.fromAccount,
                this.toAccount,
                this.amount,
                this.createdAt,
                this.nonce,
                signature
        );
    }

    /**
     * Produces a deterministic, length-prefixed canonical representation of the payment instruction
     * used for digital signature generation and verification.
     * <p>
     * Includes all critical business fields: paymentId, fromAccount, toAccount, amount, createdAt, nonce.
     * Length-prefixing guarantees ambiguity resistance and immunity to delimiter collisions.
     */
    public byte[] toCanonicalBytes() {
        String amtStr = canonicalAmount(amount);
        String timeStr = createdAt.toString();
        String from = fromAccount.toLowerCase();
        String to = toAccount.toLowerCase();

        StringBuilder sb = new StringBuilder();
        sb.append("UPI-MESH-INSTRUCTION-V1\n");
        sb.append("paymentId:").append(paymentId.length()).append(":").append(paymentId).append("\n");
        sb.append("fromAccount:").append(from.length()).append(":").append(from).append("\n");
        sb.append("toAccount:").append(to.length()).append(":").append(to).append("\n");
        sb.append("amount:").append(amtStr.length()).append(":").append(amtStr).append("\n");
        sb.append("createdAt:").append(timeStr.length()).append(":").append(timeStr).append("\n");
        sb.append("nonce:").append(nonce.length()).append(":").append(nonce).append("\n");
        return sb.toString().getBytes(StandardCharsets.UTF_8);
    }

    private static String canonicalAmount(BigDecimal amount) {
        if (amount == null) return "";
        if (amount.scale() <= 2) {
            return amount.setScale(2, RoundingMode.UNNECESSARY).toPlainString();
        }
        return amount.stripTrailingZeros().toPlainString();
    }

    public String getPaymentId() {
        return paymentId;
    }

    public String getFromAccount() {
        return fromAccount;
    }

    public String getToAccount() {
        return toAccount;
    }

    public BigDecimal getAmount() {
        return amount;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public String getNonce() {
        return nonce;
    }

    public String getSignature() {
        return signature;
    }
}
