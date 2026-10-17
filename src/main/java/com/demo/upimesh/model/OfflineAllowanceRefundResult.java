package com.demo.upimesh.model;

import java.math.BigDecimal;
import java.time.Instant;

/**
 * Result record returned when unspent escrow funds are refunded to the allowance owner.
 */
public record OfflineAllowanceRefundResult(
        boolean success,
        String allowanceId,
        String accountId,
        BigDecimal refundedAmount,
        BigDecimal totalAllocated,
        BigDecimal totalSpent,
        OfflineAllowanceStatus newStatus,
        Instant refundedAt,
        String message
) {
}
