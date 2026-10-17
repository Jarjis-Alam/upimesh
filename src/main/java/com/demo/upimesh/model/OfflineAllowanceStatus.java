package com.demo.upimesh.model;

/**
 * Lifecycle states of an offline spending allowance.
 */
public enum OfflineAllowanceStatus {
    /**
     * Active allowance backed by atomic escrow. Eligible for offline spending.
     */
    ACTIVE,

    /**
     * Explicitly revoked before expiry by the account owner or bank authority.
     */
    REVOKED,

    /**
     * Expired by deadline. Unspent escrow released back to the funding account.
     */
    EXPIRED,

    /**
     * Fully consumed by settled offline payments.
     */
    EXHAUSTED,

    /**
     * Reconciled and redeemed at the bridge.
     */
    REDEEMED
}
