package com.demo.upimesh.model;

/**
 * Response model returned after registering or evaluating a sender account's public key.
 */
public record KeyRegistrationResponse(
        String status,
        String accountId,
        String message
) {
}
