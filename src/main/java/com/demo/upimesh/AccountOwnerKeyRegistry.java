package com.demo.upimesh;

import com.demo.upimesh.model.AccountOwnerKey;
import com.demo.upimesh.model.AccountOwnerKeyRepository;
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
 * Trusted registry mapping bank account IDs to their registered Account-Owner public verification keys.
 * Backed by durable H2 database persistence across application restarts, with an in-memory
 * cache for sub-microsecond verification latency.
 * <p>
 * PROTOTYPE TRUST BOUNDARY & ACCOUNT-OWNER POLICY:
 * 1. Account owners possess an authoritative private signing key.
 * 2. Public-key registration binds the account ID to the owner's verification key.
 * 3. Arbitrary replacement of an already-registered owner key with a different key is forbidden.
 * 4. Carol debit authorizations remain strictly fail-closed; registering keys for 'carol' is blocked.
 * 5. In production UPI, this trust root would be established via bank-issued credentials (e.g. MPIN,
 *    SIM binding, bank PKI / CL library), not self-asserted software keys.
 */
@Service
public class AccountOwnerKeyRegistry {

    private static final Logger log = LoggerFactory.getLogger(AccountOwnerKeyRegistry.class);

    private final AccountOwnerKeyRepository accountOwnerKeyRepository;
    private final Map<String, PublicKey> trustedOwnerKeys = new ConcurrentHashMap<>();

    public AccountOwnerKeyRegistry() {
        this(null);
    }

    @Autowired
    public AccountOwnerKeyRegistry(@Autowired(required = false) AccountOwnerKeyRepository accountOwnerKeyRepository) {
        this.accountOwnerKeyRepository = accountOwnerKeyRepository;
    }

    /**
     * Warms the in-memory cache with all persisted account-owner public keys at startup.
     */
    @PostConstruct
    public void init() {
        if (accountOwnerKeyRepository != null) {
            KeyFactory keyFactory = getRsaKeyFactory();
            for (AccountOwnerKey record : accountOwnerKeyRepository.findAll()) {
                try {
                    PublicKey pubKey = decodeRsaPublicKey(record.getPublicKeyBase64(), keyFactory);
                    trustedOwnerKeys.put(record.getAccountId().toLowerCase(), pubKey);
                } catch (Exception e) {
                    log.error("Failed to load persisted public key for account {}: {}", record.getAccountId(), e.getMessage());
                }
            }
        }
    }

    /**
     * Registers a trusted public key for an account owner, enforcing the prototype trust policy and persistence.
     *
     * @param accountId the bank account ID
     * @param publicKey the account owner's public key
     * @return true if newly registered, false if already registered with the identical key
     * @throws IllegalArgumentException if accountId is blank or refers to blocked accounts (carol)
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

        // Fail-closed guard: Carol debit authorization is explicitly blocked
        if ("carol".equalsIgnoreCase(id)) {
            throw new IllegalArgumentException("Account-owner registration is blocked for account 'carol': cryptographic proof of account-owner consent is not implemented");
        }

        // 1. Check existing in-memory cache or database
        PublicKey existing = trustedOwnerKeys.get(id);
        if (existing == null && accountOwnerKeyRepository != null) {
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
        if (accountOwnerKeyRepository != null) {
            String b64 = Base64.getEncoder().encodeToString(publicKey.getEncoded());
            AccountOwnerKey entity = new AccountOwnerKey(id, b64, publicKey.getAlgorithm(), Instant.now());
            try {
                accountOwnerKeyRepository.saveAndFlush(entity);
            } catch (DataIntegrityViolationException ex) {
                // Handle concurrent registration race condition
                Optional<AccountOwnerKey> raced = accountOwnerKeyRepository.findById(id);
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
        trustedOwnerKeys.put(id, publicKey);
        if (TransactionSynchronizationManager.isActualTransactionActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override
                public void afterCompletion(int status) {
                    if (status != STATUS_COMMITTED) {
                        trustedOwnerKeys.remove(id);
                    }
                }
            });
        }
    }

    /**
     * Retrieves the trusted public key registered for the given account owner.
     */
    public Optional<PublicKey> getPublicKey(String accountId) {
        if (accountId == null) {
            return Optional.empty();
        }
        String id = accountId.toLowerCase().trim();
        PublicKey cached = trustedOwnerKeys.get(id);
        if (cached != null) {
            return Optional.of(cached);
        }
        if (accountOwnerKeyRepository != null) {
            Optional<PublicKey> loaded = loadKeyFromDb(id);
            loaded.ifPresent(k -> trustedOwnerKeys.put(id, k));
            return loaded;
        }
        return Optional.empty();
    }

    /**
     * Checks if an account owner key is registered for the account ID.
     */
    public boolean hasKey(String accountId) {
        if (accountId == null) return false;
        String id = accountId.toLowerCase().trim();
        if (trustedOwnerKeys.containsKey(id)) {
            return true;
        }
        if (accountOwnerKeyRepository != null && accountOwnerKeyRepository.existsById(id)) {
            getPublicKey(id); // warm cache
            return true;
        }
        return false;
    }

    /**
     * Returns an unmodifiable view of all currently cached owner keys.
     */
    public Map<String, PublicKey> getAllKeys() {
        return Collections.unmodifiableMap(trustedOwnerKeys);
    }

    /**
     * Clears all registered owner keys from cache and database explicitly for test isolation.
     */
    @Transactional
    public void clearForTesting() {
        trustedOwnerKeys.clear();
        if (accountOwnerKeyRepository != null) {
            accountOwnerKeyRepository.deleteAll();
            accountOwnerKeyRepository.flush();
        }
    }

    private Optional<PublicKey> loadKeyFromDb(String id) {
        if (accountOwnerKeyRepository == null) return Optional.empty();
        return accountOwnerKeyRepository.findById(id).map(record -> {
            try {
                return decodeRsaPublicKey(record.getPublicKeyBase64(), getRsaKeyFactory());
            } catch (Exception e) {
                log.error("Failed to decode persisted owner key for '{}': {}", id, e.getMessage());
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
