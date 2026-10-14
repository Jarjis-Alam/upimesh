package com.demo.upimesh.model;

/**
 * Lifecycle states for account-to-device debit authorization under Stage 8.
 * <p>
 * PROTOTYPE TRUST BOUNDARY & LIFECYCLE:
 * - PENDING: Device pairing initiated, awaiting account-owner approval with explicit parameters.
 * - AUTHORIZED: Actively authorized by account owner with defined spending limit, expiry timestamp,
 *               and cryptographic binding to the device's registered public key fingerprint.
 * - REVOKED: Explicitly revoked by account owner or administrator; permanently blocked from debiting.
 * - EXPIRED: Time-bounded validity has elapsed; blocked from debiting until renewed.
 */
public enum DeviceAuthorizationStatus {
    PENDING,
    AUTHORIZED,
    REVOKED,
    EXPIRED;

    public static DeviceAuthorizationStatus fromString(String value) {
        if (value == null || value.isBlank()) {
            return AUTHORIZED;
        }
        try {
            return DeviceAuthorizationStatus.valueOf(value.trim().toUpperCase());
        } catch (IllegalArgumentException e) {
            return AUTHORIZED;
        }
    }
}
