package com.demo.upimesh.model;

/**
 * Response payload confirming device-to-account debit authorization status.
 */
public record DeviceAuthorizationResponse(
        String status,
        String deviceId,
        String accountId,
        String message
) {
}
