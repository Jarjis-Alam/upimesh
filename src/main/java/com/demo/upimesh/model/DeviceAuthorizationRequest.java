package com.demo.upimesh.model;

import java.math.BigDecimal;
import java.time.Instant;

/**
 * Request payload for authorizing a device to debit a bank account under Stage 8.
 * <p>
 * Binds the authorization to:
 * - deviceId (hardware/installation ID)
 * - accountId (funding account identifier)
 * - status (PENDING or AUTHORIZED, default AUTHORIZED)
 * - spendingLimit (maximum allowable amount per debit instruction, default ₹10,000.00)
 * - expiresAt or validityHours (authorization deadline)
 * - adminToken (optional administrator pairing token)
 */
public record DeviceAuthorizationRequest(
        String deviceId,
        String accountId,
        String adminToken,
        String status,
        BigDecimal spendingLimit,
        Instant expiresAt,
        Long validityHours,
        String keyFingerprint
) {
    public DeviceAuthorizationRequest {
        if (deviceId == null || deviceId.isBlank()) {
            throw new IllegalArgumentException("deviceId must not be blank");
        }
        if (accountId == null || accountId.isBlank()) {
            throw new IllegalArgumentException("accountId must not be blank");
        }
    }

    /**
     * Backwards-compatible 2-arg constructor for existing tests and clients.
     */
    public DeviceAuthorizationRequest(String deviceId, String accountId) {
        this(deviceId, accountId, null, null, null, null, null, null);
    }

    /**
     * Backwards-compatible 3-arg constructor for existing admin token flows.
     */
    public DeviceAuthorizationRequest(String deviceId, String accountId, String adminToken) {
        this(deviceId, accountId, adminToken, null, null, null, null, null);
    }

    /**
     * Convenience constructor with explicit status, spending limit, and validity hours.
     */
    public DeviceAuthorizationRequest(
            String deviceId,
            String accountId,
            String adminToken,
            String status,
            BigDecimal spendingLimit,
            Long validityHours
    ) {
        this(deviceId, accountId, adminToken, status, spendingLimit, null, validityHours, null);
    }
}
