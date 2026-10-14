package com.demo.upimesh.model;

import java.math.BigDecimal;
import java.time.Instant;

/**
 * Response payload confirming device-to-account debit authorization status and lifecycle details.
 */
public record DeviceAuthorizationResponse(
        String status,
        String deviceId,
        String accountId,
        String message,
        String keyFingerprint,
        BigDecimal spendingLimit,
        Instant expiresAt,
        Instant authorizedAt,
        Instant revokedAt
) {
    /**
     * Backwards-compatible constructor preserving previous 4-argument signature.
     */
    public DeviceAuthorizationResponse(String status, String deviceId, String accountId, String message) {
        this(status, deviceId, accountId, message, null, null, null, null, null);
    }
}
