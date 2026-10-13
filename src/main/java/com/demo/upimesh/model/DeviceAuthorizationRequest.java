package com.demo.upimesh.model;

/**
 * Request payload for authorizing a device to debit a bank account under prototype trust policy.
 */
public record DeviceAuthorizationRequest(
        String deviceId,
        String accountId
) {
    public DeviceAuthorizationRequest {
        if (deviceId == null || deviceId.isBlank()) {
            throw new IllegalArgumentException("deviceId must not be blank");
        }
        if (accountId == null || accountId.isBlank()) {
            throw new IllegalArgumentException("accountId must not be blank");
        }
    }
}
