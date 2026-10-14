package com.demo.upimesh.model;

import java.math.BigDecimal;
import java.time.Instant;

/**
 * Authoritative payment status response returned by GET /api/mesh/status/{paymentId}.
 * Provides safe verification of committed settlement status before retrying ambiguous requests.
 */
public record PaymentStatusResponse(
        boolean found,
        String paymentId,
        String status,
        String fromAccount,
        String toAccount,
        BigDecimal amount,
        String packetHash,
        Instant settledAt,
        String message
) {
}
