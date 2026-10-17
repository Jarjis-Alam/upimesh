package com.demo.upimesh.model;

import java.math.BigDecimal;

/**
 * Request payload for issuing an offline spending allowance backed by atomic escrow.
 */
public record AllowanceIssuanceRequest(
        String accountId,
        String deviceId,
        BigDecimal amount,
        String currency,
        Long durationHours
) {
    public AllowanceIssuanceRequest {
        if (accountId != null) accountId = accountId.trim().toLowerCase();
        if (deviceId != null) deviceId = deviceId.trim();
        if (currency != null) currency = currency.trim().toUpperCase();
        if (durationHours == null) durationHours = 24L; // Default 24 hours
    }
}
