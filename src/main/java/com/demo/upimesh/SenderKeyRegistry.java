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
 * Security & Architecture Note:
 * In this prototype/simulation environment, key pairs for demo peers (Alice, Bob, Carol)
 * are provisioned at bootstrap. In a production offline mesh deployment:
 * 1. Account-key bindings must be cryptographically certified by a Certificate Authority
 *    or bank identity provider during out-of-band onboarding.
 * 2. Key rotation, hardware security module (Secure Element/TEE) hardware binding,
 *    and real-time revocation lists (CRL/OCSP-style or bridge-cached revocation)
 *    must be enforced.
 * 3. Bridges must never accept self-asserted or in-band uncertified public keys.
 */
@Service
public class SenderKeyRegistry {

    private final Map<String, PublicKey> trustedPublicKeys = new ConcurrentHashMap<>();

    /**
     * Registers a trusted public key for an account ID.
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
