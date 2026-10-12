package com.demo.upimesh.model;

/**
 * Response model exposing the backend bridge's active RSA public key
 * encoded in standard X.509 SubjectPublicKeyInfo Base64 format.
 */
public record BridgePublicKeyResponse(
        String algorithm,
        String format,
        String publicKey
) {
}
