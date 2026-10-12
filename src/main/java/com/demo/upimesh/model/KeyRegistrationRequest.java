package com.demo.upimesh.model;

/**
 * Request model for registering a sender account's RSA public verification key.
 */
public record KeyRegistrationRequest(
        String accountId,
        String publicKey
) {
}
