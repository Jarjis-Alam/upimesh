package com.demo.upimesh.model;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.nio.charset.StandardCharsets;
import java.time.Instant;

/**
 * Digitally signed consent statement issued by an account owner authorizing
 * an offline device to debit their bank account under Stage 8.6.
 * <p>
 * Cryptographically binds:
 * - consentId (unique UUID preventing consent replay)
 * - accountId (funding account identifier)
 * - deviceId (physical device hardware/installation UUID)
 * - deviceKeyFingerprint (SHA-256 fingerprint of device's RSA public key)
 * - spendingLimit (maximum allowable per-debit amount)
 * - expiresAt (authorization validity deadline)
 * - ownerSignature (RSA-SHA256 signature produced by account-owner private key)
 */
public record AccountOwnerConsentRequest(
        String consentId,
        String accountId,
        String deviceId,
        String deviceKeyFingerprint,
        BigDecimal spendingLimit,
        Instant expiresAt,
        String ownerSignature
) {
    public AccountOwnerConsentRequest {
        if (consentId == null || consentId.isBlank()) {
            throw new IllegalArgumentException("consentId must not be blank");
        }
        if (accountId == null || accountId.isBlank()) {
            throw new IllegalArgumentException("accountId must not be blank");
        }
        if (deviceId == null || deviceId.isBlank()) {
            throw new IllegalArgumentException("deviceId must not be blank");
        }
        if (deviceKeyFingerprint == null || deviceKeyFingerprint.isBlank()) {
            throw new IllegalArgumentException("deviceKeyFingerprint must not be blank");
        }
        if (spendingLimit == null || spendingLimit.compareTo(BigDecimal.ZERO) <= 0) {
            throw new IllegalArgumentException("spendingLimit must be greater than zero");
        }
        if (expiresAt == null) {
            throw new IllegalArgumentException("expiresAt must not be null");
        }
    }

    /**
     * Constructs the canonical byte sequence for digital signature generation and verification.
     * Format: consentId|accountId|deviceId|deviceKeyFingerprint|spendingLimit|expiresAt
     */
    public byte[] toCanonicalBytes() {
        String canonicalStr = String.join("|",
                consentId.trim(),
                accountId.trim().toLowerCase(),
                deviceId.trim().toLowerCase(),
                deviceKeyFingerprint.trim().toLowerCase(),
                spendingLimit.setScale(2, RoundingMode.HALF_UP).toPlainString(),
                expiresAt.toString()
        );
        return canonicalStr.getBytes(StandardCharsets.UTF_8);
    }
}
