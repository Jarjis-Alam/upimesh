package com.demo.upimesh;

import com.demo.upimesh.model.RegisteredDeviceKey;
import com.demo.upimesh.model.RegisteredDeviceKeyRepository;
import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import java.security.KeyFactory;
import java.security.PublicKey;
import java.security.spec.X509EncodedKeySpec;
import java.time.Instant;
import java.util.Arrays;
import java.util.Base64;
import java.util.Collections;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Prototype trusted registry mapping account/device IDs to their registered public signing keys.
 * Backed by durable H2 database persistence across application restarts, with an in-memory
 * cache for sub-microsecond verification latency.
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

    private static final Logger log = LoggerFactory.getLogger(SenderKeyRegistry.class);

    private final RegisteredDeviceKeyRepository registeredDeviceKeyRepository;
    private final Map<String, PublicKey> trustedPublicKeys = new ConcurrentHashMap<>();

    public SenderKeyRegistry() {
        this(null);
    }

    @Autowired
    public SenderKeyRegistry(@Autowired(required = false) RegisteredDeviceKeyRepository registeredDeviceKeyRepository) {
        this.registeredDeviceKeyRepository = registeredDeviceKeyRepository;
    }

    /**
     * Warms the in-memory cache with all persisted device public keys at startup.
     */
    @PostConstruct
    public void init() {
        if (registeredDeviceKeyRepository != null) {
            KeyFactory keyFactory = getRsaKeyFactory();
            for (RegisteredDeviceKey record : registeredDeviceKeyRepository.findAll()) {
                try {
                    PublicKey pubKey = decodeRsaPublicKey(record.getPublicKeyBase64(), keyFactory);
                    trustedPublicKeys.put(record.getId().toLowerCase(), pubKey);
                } catch (Exception e) {
                    log.error("Failed to load persisted public key for device {}: {}", record.getId(), e.getMessage());
                }
            }
        }
    }

    /**
     * Registers a trusted public key for an account/device ID (internal / test / virtual node usage).
     * If the ID is already durably registered in the persistent repository, virtual simulation
     * nodes are never permitted to overwrite it.
     */
    public void registerKey(String accountId, PublicKey publicKey) {
        if (accountId == null || accountId.isBlank()) {
            throw new IllegalArgumentException("Account ID must not be blank");
        }
        if (publicKey == null) {
            throw new IllegalArgumentException("Public key must not be null");
        }
        String id = accountId.toLowerCase().trim();
        // Never overwrite a persisted device key with an ephemeral simulation key
        if (registeredDeviceKeyRepository != null && registeredDeviceKeyRepository.existsById(id)) {
            log.warn("Preserving persisted key for '{}'; ignoring virtual simulation node registration", id);
            return;
        }
        trustedPublicKeys.put(id, publicKey);
    }

    /**
     * Unregisters a key from the in-memory cache (for simulated node cleanup).
     * Does not delete or affect persisted device keys.
     */
    public void unregisterKey(String accountId) {
        if (accountId != null) {
            String id = accountId.toLowerCase().trim();
            if (registeredDeviceKeyRepository == null || !registeredDeviceKeyRepository.existsById(id)) {
                trustedPublicKeys.remove(id);
            }
        }
    }

    /**
     * Registers a trusted public key enforcing the prototype trust policy and persisting to database.
     * <p>
     * Prototype Policy:
     * - Arbitrary replacement of an already-registered key with a different key is forbidden.
     * - Re-registering the exact same key succeeds idempotently without error.
     *
     * @param accountId the account or device ID to register
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
        String id = accountId.toLowerCase().trim();

        // 1. Check existing in-memory cache or database
        PublicKey existing = trustedPublicKeys.get(id);
        if (existing == null && registeredDeviceKeyRepository != null) {
            existing = loadKeyFromDb(id).orElse(null);
        }

        if (existing != null) {
            if (Arrays.equals(existing.getEncoded(), publicKey.getEncoded())) {
                updateCacheWithRollbackSync(id, existing);
                return false;
            }
            throw new IllegalStateException(
                    "Account '" + id + "' is already registered with a different public key. "
                    + "Arbitrary key replacement is forbidden under prototype trust policy."
            );
        }

        // 2. Persist to database first (consistent write-through with immediate flush)
        if (registeredDeviceKeyRepository != null) {
            String b64 = Base64.getEncoder().encodeToString(publicKey.getEncoded());
            RegisteredDeviceKey entity = new RegisteredDeviceKey(id, b64, publicKey.getAlgorithm(), Instant.now());
            try {
                registeredDeviceKeyRepository.saveAndFlush(entity);
            } catch (DataIntegrityViolationException ex) {
                // Handle concurrent registration race condition
                Optional<RegisteredDeviceKey> raced = registeredDeviceKeyRepository.findById(id);
                if (raced.isPresent() && raced.get().getPublicKeyBase64().equals(b64)) {
                    updateCacheWithRollbackSync(id, publicKey);
                    return false;
                }
                throw new IllegalStateException(
                        "Account '" + id + "' is already registered with a different public key.",
                        ex
                );
            }
        }

        // 3. Update in-memory cache only after durable database persistence succeeds
        updateCacheWithRollbackSync(id, publicKey);
        return true;
    }

    private void updateCacheWithRollbackSync(String id, PublicKey publicKey) {
        trustedPublicKeys.put(id, publicKey);
        if (TransactionSynchronizationManager.isActualTransactionActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override
                public void afterCompletion(int status) {
                    if (status != STATUS_COMMITTED) {
                        trustedPublicKeys.remove(id);
                    }
                }
            });
        }
    }

    /**
     * Retrieves the trusted public key registered for the given account ID.
     */
    public Optional<PublicKey> getPublicKey(String accountId) {
        if (accountId == null) {
            return Optional.empty();
        }
        String id = accountId.toLowerCase().trim();
        PublicKey cached = trustedPublicKeys.get(id);
        if (cached != null) {
            return Optional.of(cached);
        }
        if (registeredDeviceKeyRepository != null) {
            Optional<PublicKey> loaded = loadKeyFromDb(id);
            loaded.ifPresent(k -> trustedPublicKeys.put(id, k));
            return loaded;
        }
        return Optional.empty();
    }

    /**
     * Checks if a public key is registered for the account ID.
     */
    public boolean hasKey(String accountId) {
        if (accountId == null) return false;
        String id = accountId.toLowerCase().trim();
        if (trustedPublicKeys.containsKey(id)) {
            return true;
        }
        if (registeredDeviceKeyRepository != null && registeredDeviceKeyRepository.existsById(id)) {
            getPublicKey(id); // warm cache
            return true;
        }
        return false;
    }

    /**
     * Returns an unmodifiable view of all currently cached public keys.
     */
    public Map<String, PublicKey> getAllKeys() {
        return Collections.unmodifiableMap(trustedPublicKeys);
    }

    /**
     * Clears all registered keys from cache and database explicitly for test isolation.
     */
    @Transactional
    public void clearForTesting() {
        trustedPublicKeys.clear();
        if (registeredDeviceKeyRepository != null) {
            registeredDeviceKeyRepository.deleteAll();
            registeredDeviceKeyRepository.flush();
        }
    }

    /**
     * @deprecated Use {@link #clearForTesting()} in tests. Preserved for backwards compatibility.
     */
    @Deprecated
    public void clear() {
        clearForTesting();
    }

    private Optional<PublicKey> loadKeyFromDb(String id) {
        if (registeredDeviceKeyRepository == null) return Optional.empty();
        return registeredDeviceKeyRepository.findById(id).map(record -> {
            try {
                return decodeRsaPublicKey(record.getPublicKeyBase64(), getRsaKeyFactory());
            } catch (Exception e) {
                log.error("Failed to decode persisted key for '{}': {}", id, e.getMessage());
                return null;
            }
        });
    }

    private KeyFactory getRsaKeyFactory() {
        try {
            return KeyFactory.getInstance("RSA");
        } catch (Exception e) {
            throw new IllegalStateException("RSA algorithm unavailable", e);
        }
    }

    private PublicKey decodeRsaPublicKey(String base64, KeyFactory factory) throws Exception {
        byte[] derBytes = Base64.getDecoder().decode(base64);
        X509EncodedKeySpec spec = new X509EncodedKeySpec(derBytes);
        return factory.generatePublic(spec);
    }
}
