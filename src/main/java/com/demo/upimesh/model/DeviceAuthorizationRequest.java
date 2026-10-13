package com.demo.upimesh.model;

/**
 * Request payload for authorizing a device to debit a bank account under prototype trust policy.
 * <p>
 * Under Stage 6.4B.7, authorization requires an administrator pairing token supplied via
 * the 'X-Admin-Token' HTTP header, 'Authorization: Bearer <token>' header, or the optional
 * 'adminToken' field in this request payload.
 */
public record DeviceAuthorizationRequest(
        String deviceId,
        String accountId,
        String adminToken
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
     * Backwards-compatible constructor allowing creation without body-embedded admin token.
     */
    public DeviceAuthorizationRequest(String deviceId, String accountId) {
        this(deviceId, accountId, null);
    }
}
