package com.demo.upimesh;

import org.springframework.stereotype.Service;

import java.security.PublicKey;
import java.util.Collections;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Prototype trusted registry mapping account IDs to their registered public signing keys.
 * <p>
 * PROTOTYPE TRUST BOUNDARY NOTICE:
 * Public-key registration in this service is currently an unauthenticated prototype trust boundary
 * designed for demonstration, local development, and mesh simulation. It does NOT constitute
 * secure, verified identity authentication.
 * <p>
 * In a production UPI offline mesh deployment:
 * 1. Account-key bindings must be cryptographically certified by a Certificate Authority (CA)
 *    or bank identity provider during out-of-band onboarding using hardware attestation.
 * 2. Key rotation, hardware security module (Secure Enclave / TEE) hardware binding,
 *    and real-time revocation lists (CRL/OCSP-style or bridge-cached revocation) must be enforced.
 * 3. Bridges must never accept self-asserted or in-band uncertified public keys.
 */
@Service
public class SenderKeyRegistry {

    private final Map<String, PublicKey> trustedPublicKeys = new ConcurrentHashMap<>();

    /**
     * Registers a trusted public key for an account ID (internal / test usage).
     */
    public void registerKey(String accountId, PublicKey publicKey) {
        if (accountId == null || accountId.isBlank()) {
            throw new IllegalArgumentException("Account ID must not be blank");
        }
        if (publicKey == null) {
            throw new IllegalArgumentException("Public key must not be null");
        }
        trustedPublicKeys.put(accountId.toLowerCase(), publicKey);
    }

    /**
     * Registers a trusted public key enforcing the prototype trust policy.
     * <p>
     * Prototype Policy:
     * Arbitrary replacement of an already-registered key with a different key is forbidden.
     * Re-registering the exact same key succeeds idempotently without error.
     *
     * @param accountId the account ID to register
     * @param publicKey the public key to register
     * @return true if newly registered, false if already registered with the identical key
     * @throws IllegalStateException if the account already has a different registered key
     */
    public boolean registerKeyWithPolicy(String accountId, PublicKey publicKey) {
        if (accountId == null || accountId.isBlank()) {
            throw new IllegalArgumentException("Account ID must not be blank");
        }
        if (publicKey == null) {
            throw new IllegalArgumentException("Public key must not be null");
        }
        String id = accountId.toLowerCase();
        PublicKey existing = trustedPublicKeys.get(id);
        if (existing != null) {
            if (java.util.Arrays.equals(existing.getEncoded(), publicKey.getEncoded())) {
                return false;
            }
            throw new IllegalStateException(
                    "Account '" + id + "' is already registered with a different public key. "
                    + "Arbitrary key replacement is forbidden under prototype trust policy."
            );
        }
        trustedPublicKeys.put(id, publicKey);
        return true;
    }

    /**
     * Retrieves the trusted public key registered for the given account ID.
     */
    public Optional<PublicKey> getPublicKey(String accountId) {
        if (accountId == null) {
            return Optional.empty();
        }
        return Optional.ofNullable(trustedPublicKeys.get(accountId.toLowerCase()));
    }

    /**
     * Checks if a public key is registered for the account ID.
     */
    public boolean hasKey(String accountId) {
        if (accountId == null) return false;
        return trustedPublicKeys.containsKey(accountId.toLowerCase());
    }

    /**
     * Returns an unmodifiable view of all registered public keys.
     */
    public Map<String, PublicKey> getAllKeys() {
        return Collections.unmodifiableMap(trustedPublicKeys);
    }

    /**
     * Clears all registered keys.
     */
    public void clear() {
        trustedPublicKeys.clear();
    }
}
