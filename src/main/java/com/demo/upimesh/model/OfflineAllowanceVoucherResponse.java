package com.demo.upimesh.model;

import java.math.BigDecimal;
import java.time.Instant;

/**
 * Authoritative voucher response returned to the client upon successful offline allowance issuance.
 */
public record OfflineAllowanceVoucherResponse(
        String allowanceId,
        String accountId,
        String deviceId,
        String devicePublicKeyFingerprint,
        String currency,
        BigDecimal allocatedAmount,
        Instant issuedAt,
        Instant expiresAt,
        int protocolVersion,
        OfflineAllowanceStatus status,
        String voucherSignature,
        String bankPublicKeyBase64
) {
    public static OfflineAllowanceVoucherResponse fromEntity(OfflineAllowance entity, String bankPublicKeyBase64) {
        return new OfflineAllowanceVoucherResponse(
                entity.getId(),
                entity.getAccountId(),
                entity.getDeviceId(),
                entity.getDevicePublicKeyFingerprint(),
                entity.getCurrency(),
                entity.getAllocatedAmount(),
                entity.getIssuedAt(),
                entity.getExpiresAt(),
                entity.getProtocolVersion(),
                entity.getStatus(),
                entity.getVoucherSignature(),
                bankPublicKeyBase64
        );
    }
}
