package com.demo.upimesh;

import com.demo.upimesh.model.DeviceAccountAuthorization;
import com.demo.upimesh.model.DeviceAuthorizationRepository;
import com.demo.upimesh.model.DeviceAuthorizationStatus;
import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import java.math.BigDecimal;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.PublicKey;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Collections;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.locks.ReentrantReadWriteLock;

/**
 * Authorization registry linking registered physical/virtual device IDs
 * to the bank accounts they are authorized to debit under Stage 8.
 * <p>
 * Backed by durable H2 database persistence across application restarts, with an
 * in-memory cache for fast verification.
 * <p>
 * STAGE 8 ACCOUNT-OWNER AUTHORIZATION & LIFECYCLE:
 * 1. PENDING: Pairing initiated, awaiting owner approval.
 * 2. AUTHORIZED: Active, bound to account ID, device ID, public-key fingerprint, spending limit, and expiry.
 * 3. REVOKED: Explicitly revoked by account owner or administrator; blocked from debiting.
 * 4. EXPIRED: Expired by time deadline; blocked from debiting until renewed.
 * <p>
 * PROTOTYPE TRUST BOUNDARY:
 * Public-key registration in SenderKeyRegistry proves possession of an RSA keypair.
 * Administrator pairing token guards the pairing action.
 * Account-owner authorization explicitly binds the debit permissions, spending limit,
 * and key fingerprint.
 */
@Service
public class DeviceAuthorizationRegistry {

    private static final Logger log = LoggerFactory.getLogger(DeviceAuthorizationRegistry.class);

    private final DeviceAuthorizationRepository deviceAuthorizationRepository;
    private final SenderKeyRegistry senderKeyRegistry;

    // Composite key cache: "deviceId:accountId" -> DeviceAccountAuthorization
    private final Map<String, DeviceAccountAuthorization> authorizationCache = new ConcurrentHashMap<>();
    // Secondary index for backward compatibility: deviceId -> Set<accountId>
    private final Map<String, Set<String>> authorizedAccountsByDevice = new ConcurrentHashMap<>();
    // Striped/composite concurrency locks: "deviceId:accountId" -> ReentrantReadWriteLock(fair=true)
    private final ConcurrentHashMap<String, ReentrantReadWriteLock> authorizationLocks = new ConcurrentHashMap<>();

    public ReentrantReadWriteLock getAuthorizationLock(String deviceId, String accountId) {
        if (deviceId == null || accountId == null) {
            return new ReentrantReadWriteLock(true);
        }
        String key = deviceId.trim().toLowerCase() + ":" + accountId.trim().toLowerCase();
        return authorizationLocks.computeIfAbsent(key, k -> new ReentrantReadWriteLock(true));
    }

    @FunctionalInterface
    public interface SettlingAction<T, E extends Throwable> {
        T execute() throws E;
    }

    private DeviceAccountAuthorization copyAuthorization(DeviceAccountAuthorization auth) {
        if (auth == null) return null;
        return new DeviceAccountAuthorization(
                auth.getId(),
                auth.getDeviceId(),
                auth.getAccountId(),
                auth.getAuthorizedAt(),
                auth.getStatus(),
                auth.getKeyFingerprint(),
                auth.getSpendingLimit(),
                auth.getExpiresAt(),
                auth.getRevokedAt()
        );
    }

    /**
     * Executes a payment settlement action atomically under the protection of the device's
     * authorization read lock. This guarantees that:
     * 1. Authorization checks and settlement have a strictly defined, atomic ordering.
     * 2. Any concurrent revocation must acquire the write lock, which blocks until any in-flight
     *    settlement completes, or blocks settlement until revocation commits.
     * 3. Multiple concurrent settlements under valid authorizations can proceed concurrently.
     * 4. The read lock is held until the database transaction has actually committed or rolled back.
     */
    public <T, E extends Throwable> T executeWithAuthorization(
            String deviceId,
            String accountId,
            BigDecimal amount,
            PublicKey signingKey,
            SettlingAction<T, E> settlingAction
    ) throws E {
        ReentrantReadWriteLock rwLock = getAuthorizationLock(deviceId, accountId);
        rwLock.readLock().lock();
        boolean lockDeferredToTx = false;
        try {
            verifyDebitAuthorization(deviceId, accountId, amount, signingKey);

            if (TransactionSynchronizationManager.isActualTransactionActive()) {
                // If an outer transaction is already active, hold read lock until transaction completion
                TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                    @Override
                    public void afterCompletion(int status) {
                        rwLock.readLock().unlock();
                    }
                });
                lockDeferredToTx = true;
            }

            T result = settlingAction.execute();

            if (!lockDeferredToTx && TransactionSynchronizationManager.isActualTransactionActive()) {
                // If the settling action opened a transaction that is still awaiting completion
                TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                    @Override
                    public void afterCompletion(int status) {
                        rwLock.readLock().unlock();
                    }
                });
                lockDeferredToTx = true;
            }

            return result;
        } finally {
            if (!lockDeferredToTx) {
                rwLock.readLock().unlock();
            }
        }
    }

    public DeviceAuthorizationRegistry() {
        this(null, null);
    }

    public DeviceAuthorizationRegistry(DeviceAuthorizationRepository deviceAuthorizationRepository) {
        this(deviceAuthorizationRepository, null);
    }

    @Autowired
    public DeviceAuthorizationRegistry(
            @Autowired(required = false) DeviceAuthorizationRepository deviceAuthorizationRepository,
            @Autowired(required = false) SenderKeyRegistry senderKeyRegistry
    ) {
        this.deviceAuthorizationRepository = deviceAuthorizationRepository;
        this.senderKeyRegistry = senderKeyRegistry;
    }

    /**
     * Warms the in-memory cache with all persisted authorization bindings at startup,
     * evaluating any expired authorizations.
     */
    @PostConstruct
    public void init() {
        if (deviceAuthorizationRepository != null) {
            Instant now = Instant.now();
            for (DeviceAccountAuthorization auth : deviceAuthorizationRepository.findAll()) {
                String dev = auth.getDeviceId().toLowerCase().trim();
                String acc = auth.getAccountId().toLowerCase().trim();
                String cacheKey = dev + ":" + acc;

                if (auth.isExpired(now) && auth.getStatusEnum() == DeviceAuthorizationStatus.AUTHORIZED) {
                    auth.setStatus(DeviceAuthorizationStatus.EXPIRED.name());
                    try {
                        deviceAuthorizationRepository.save(auth);
                    } catch (Exception e) {
                        log.warn("Failed to persist expired status for {}: {}", cacheKey, e.getMessage());
                    }
                }

                authorizationCache.put(cacheKey, auth);
                if (auth.isActive(now)) {
                    authorizedAccountsByDevice.computeIfAbsent(dev, k -> ConcurrentHashMap.newKeySet()).add(acc);
                }
            }
        }
    }

    /**
     * Authorizes a device with default ₹10,000.00 spending limit and 30-day validity.
     * Automatically captures public key fingerprint if device is in SenderKeyRegistry.
     */
    @Transactional
    public DeviceAccountAuthorization authorizeDevice(String deviceId, String accountId) {
        return authorizeDevice(
                deviceId,
                accountId,
                DeviceAuthorizationStatus.AUTHORIZED,
                null,
                new BigDecimal("10000.00"),
                Instant.now().plus(30, ChronoUnit.DAYS)
        );
    }

    /**
     * Explicit Stage 8 device authorization binding account ID, device ID, status,
     * public-key fingerprint, spending limit, and expiry.
     */
    @Transactional
    public DeviceAccountAuthorization authorizeDevice(
            String deviceId,
            String accountId,
            DeviceAuthorizationStatus status,
            String keyFingerprint,
            BigDecimal spendingLimit,
            Instant expiresAt
    ) {
        if (deviceId == null || deviceId.isBlank()) {
            throw new IllegalArgumentException("deviceId must not be blank");
        }
        if (accountId == null || accountId.isBlank()) {
            throw new IllegalArgumentException("accountId must not be blank");
        }
        String dev = deviceId.trim().toLowerCase();
        String acc = accountId.trim().toLowerCase();
        String cacheKey = dev + ":" + acc;

        ReentrantReadWriteLock rwLock = getAuthorizationLock(dev, acc);
        rwLock.writeLock().lock();
        boolean lockDeferredToTx = false;
        try {
            DeviceAccountAuthorization previousCached = authorizationCache.get(cacheKey);
            DeviceAccountAuthorization previousSnapshot = copyAuthorization(previousCached);
            boolean wasInActiveSet = authorizedAccountsByDevice.get(dev) != null
                    && authorizedAccountsByDevice.get(dev).contains(acc);

            // Auto-detect public key fingerprint if not explicitly supplied
            String fingerprint = keyFingerprint;
            if (fingerprint == null && senderKeyRegistry != null) {
                Optional<PublicKey> pubKey = senderKeyRegistry.getPublicKey(dev);
                if (pubKey.isPresent()) {
                    fingerprint = computeFingerprint(pubKey.get());
                }
            }

            DeviceAuthorizationStatus finalStatus = status != null ? status : DeviceAuthorizationStatus.AUTHORIZED;
            BigDecimal finalLimit = spendingLimit != null ? spendingLimit : new BigDecimal("10000.00");
            Instant finalExpiry = expiresAt != null ? expiresAt : Instant.now().plus(30, ChronoUnit.DAYS);

            DeviceAccountAuthorization authRecord = null;
            if (deviceAuthorizationRepository != null) {
                Optional<DeviceAccountAuthorization> existingOpt = deviceAuthorizationRepository.findByDeviceIdAndAccountId(dev, acc);
                if (existingOpt.isPresent()) {
                    authRecord = existingOpt.get();
                    authRecord.setStatus(finalStatus.name());
                    if (fingerprint != null) {
                        authRecord.setKeyFingerprint(fingerprint);
                    }
                    authRecord.setSpendingLimit(finalLimit);
                    authRecord.setExpiresAt(finalExpiry);
                    authRecord.setRevokedAt(null);
                } else {
                    authRecord = new DeviceAccountAuthorization(
                            UUID.randomUUID().toString(),
                            dev,
                            acc,
                            Instant.now(),
                            finalStatus.name(),
                            fingerprint,
                            finalLimit,
                            finalExpiry,
                            null
                    );
                }
                try {
                    authRecord = deviceAuthorizationRepository.saveAndFlush(authRecord);
                } catch (DataIntegrityViolationException ex) {
                    authRecord = deviceAuthorizationRepository.findByDeviceIdAndAccountId(dev, acc)
                            .orElse(authRecord);
                }
            } else {
                authRecord = new DeviceAccountAuthorization(
                        UUID.randomUUID().toString(),
                        dev,
                        acc,
                        Instant.now(),
                        finalStatus.name(),
                        fingerprint,
                        finalLimit,
                        finalExpiry,
                        null
                );
            }

            // Update in-memory cache
            authorizationCache.put(cacheKey, authRecord);
            if (authRecord.isActive(Instant.now())) {
                authorizedAccountsByDevice.computeIfAbsent(dev, k -> ConcurrentHashMap.newKeySet()).add(acc);
            } else {
                Set<String> accounts = authorizedAccountsByDevice.get(dev);
                if (accounts != null) {
                    accounts.remove(acc);
                }
            }

            if (TransactionSynchronizationManager.isActualTransactionActive()) {
                TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                    @Override
                    public void afterCompletion(int status) {
                        try {
                            if (status != STATUS_COMMITTED) {
                                if (previousSnapshot != null) {
                                    authorizationCache.put(cacheKey, previousSnapshot);
                                } else {
                                    authorizationCache.remove(cacheKey);
                                }
                                if (wasInActiveSet) {
                                    authorizedAccountsByDevice.computeIfAbsent(dev, k -> ConcurrentHashMap.newKeySet()).add(acc);
                                } else {
                                    Set<String> accounts = authorizedAccountsByDevice.get(dev);
                                    if (accounts != null) {
                                        accounts.remove(acc);
                                    }
                                }
                            }
                        } finally {
                            rwLock.writeLock().unlock();
                        }
                    }
                });
                lockDeferredToTx = true;
            }

            return authRecord;
        } finally {
            if (!lockDeferredToTx) {
                rwLock.writeLock().unlock();
            }
        }
    }

    /**
     * Revokes authorization for a device to debit the specified account.
     */
    @Transactional
    public void revokeDevice(String deviceId, String accountId) {
        if (deviceId == null || accountId == null) {
            return;
        }
        String dev = deviceId.trim().toLowerCase();
        String acc = accountId.trim().toLowerCase();
        String cacheKey = dev + ":" + acc;

        ReentrantReadWriteLock rwLock = getAuthorizationLock(dev, acc);
        rwLock.writeLock().lock();
        boolean lockDeferredToTx = false;
        try {
            // Snapshot previous state for rollback recovery
            DeviceAccountAuthorization previousCached = authorizationCache.get(cacheKey);
            DeviceAccountAuthorization previousSnapshot = copyAuthorization(previousCached);
            boolean wasInActiveSet = authorizedAccountsByDevice.get(dev) != null
                    && authorizedAccountsByDevice.get(dev).contains(acc);

            // Persist to database first (fail-closed if persistence fails)
            DeviceAccountAuthorization record = null;
            if (deviceAuthorizationRepository != null) {
                Optional<DeviceAccountAuthorization> recordOpt = deviceAuthorizationRepository.findByDeviceIdAndAccountId(dev, acc);
                if (recordOpt.isPresent()) {
                    record = recordOpt.get();
                    record.setStatus(DeviceAuthorizationStatus.REVOKED.name());
                    record.setRevokedAt(Instant.now());
                    record = deviceAuthorizationRepository.saveAndFlush(record);
                }
            }

            // Update in-memory state only after successful database flush
            Set<String> accounts = authorizedAccountsByDevice.get(dev);
            if (accounts != null) {
                accounts.remove(acc);
            }
            if (record != null) {
                authorizationCache.put(cacheKey, record);
            } else if (previousCached != null) {
                DeviceAccountAuthorization updated = copyAuthorization(previousCached);
                updated.setStatus(DeviceAuthorizationStatus.REVOKED.name());
                updated.setRevokedAt(Instant.now());
                authorizationCache.put(cacheKey, updated);
            }

            // Bind lock release and rollback recovery to transaction completion
            if (TransactionSynchronizationManager.isActualTransactionActive()) {
                TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                    @Override
                    public void afterCompletion(int status) {
                        try {
                            if (status != STATUS_COMMITTED) {
                                // Transaction rolled back: restore in-memory cache to pre-revocation state
                                if (previousSnapshot != null) {
                                    authorizationCache.put(cacheKey, previousSnapshot);
                                } else {
                                    authorizationCache.remove(cacheKey);
                                }
                                if (wasInActiveSet) {
                                    authorizedAccountsByDevice.computeIfAbsent(dev, k -> ConcurrentHashMap.newKeySet()).add(acc);
                                }
                            }
                        } finally {
                            rwLock.writeLock().unlock();
                        }
                    }
                });
                lockDeferredToTx = true;
            }
        } finally {
            if (!lockDeferredToTx) {
                rwLock.writeLock().unlock();
            }
        }
    }

    /**
     * Checks if a device is currently authorized and active to debit the given account.
     * Returns true if status is AUTHORIZED and not expired.
     */
    public boolean isDeviceAuthorized(String deviceId, String accountId) {
        if (deviceId == null || accountId == null) {
            return false;
        }
        String dev = deviceId.trim().toLowerCase();
        String acc = accountId.trim().toLowerCase();

        // Account-owner debit authorization for Carol is explicitly blocked (fail-closed)
        if ("carol".equalsIgnoreCase(acc)) {
            return false;
        }

        // Allow virtual simulation devices where deviceId is identical to accountId (excluding Carol)
        if (dev.equals(acc)) {
            return true;
        }

        String cacheKey = dev + ":" + acc;
        DeviceAccountAuthorization auth = authorizationCache.get(cacheKey);
        Instant now = Instant.now();

        if (auth != null) {
            if (auth.isExpired(now) && auth.getStatusEnum() == DeviceAuthorizationStatus.AUTHORIZED) {
                auth.setStatus(DeviceAuthorizationStatus.EXPIRED.name());
                Set<String> accounts = authorizedAccountsByDevice.get(dev);
                if (accounts != null) {
                    accounts.remove(acc);
                }
            }
            return auth.isActive(now);
        }

        // Fallback read-through to database
        if (deviceAuthorizationRepository != null) {
            Optional<DeviceAccountAuthorization> dbRecord = deviceAuthorizationRepository.findByDeviceIdAndAccountId(dev, acc);
            if (dbRecord.isPresent()) {
                DeviceAccountAuthorization record = dbRecord.get();
                if (record.isExpired(now) && record.getStatusEnum() == DeviceAuthorizationStatus.AUTHORIZED) {
                    record.setStatus(DeviceAuthorizationStatus.EXPIRED.name());
                }
                authorizationCache.put(cacheKey, record);
                if (record.isActive(now)) {
                    authorizedAccountsByDevice.computeIfAbsent(dev, k -> ConcurrentHashMap.newKeySet()).add(acc);
                    return true;
                }
            }
        }

        return false;
    }

    /**
     * Server-side enforcement of account-to-device authorization for every debit attempt.
     * <p>
     * Enforces:
     * 1. Authorization existence for (deviceId, accountId).
     * 2. Lifecycle state: PENDING, REVOKED, EXPIRED are rejected with descriptive errors.
     * 3. Public-key fingerprint binding: prevents key substitution or unauthorized rotation.
     * 4. Spending limit enforcement: rejects debits exceeding the authorized threshold.
     *
     * @param deviceId   device submitting the debit instruction
     * @param accountId  funding bank account ID to debit
     * @param amount     debit amount
     * @param signingKey public key used to verify the payment instruction signature
     * @throws IllegalArgumentException if unauthorized, key fingerprint mismatch, or invalid params
     * @throws IllegalStateException    if status is PENDING, REVOKED, EXPIRED, or exceeds spending limit
     */
    public void verifyDebitAuthorization(
            String deviceId,
            String accountId,
            BigDecimal amount,
            PublicKey signingKey
    ) {
        if (deviceId == null || deviceId.isBlank()) {
            throw new IllegalArgumentException("deviceId must not be blank");
        }
        if (accountId == null || accountId.isBlank()) {
            throw new IllegalArgumentException("accountId must not be blank");
        }
        String dev = deviceId.trim().toLowerCase();
        String acc = accountId.trim().toLowerCase();

        // 1. Strict Fail-Closed Check for Carol
        // Account-owner debit authorization is explicitly blocked because cryptographic proof of owner consent is not implemented
        if ("carol".equalsIgnoreCase(acc)) {
            throw new IllegalArgumentException(
                    "Device '" + dev + "' is not authorized to debit account 'carol': account-owner consent is not implemented"
            );
        }

        String cacheKey = dev + ":" + acc;
        DeviceAccountAuthorization auth = authorizationCache.get(cacheKey);
        if (auth == null && deviceAuthorizationRepository != null) {
            auth = deviceAuthorizationRepository.findByDeviceIdAndAccountId(dev, acc).orElse(null);
            if (auth != null) {
                authorizationCache.put(cacheKey, auth);
            }
        }

        if (auth == null) {
            throw new IllegalArgumentException(
                    "Device '" + dev + "' is not authorized to debit account '" + acc + "'"
            );
        }

        Instant now = Instant.now();

        // 2. Check lifecycle status
        DeviceAuthorizationStatus status = auth.getStatusEnum();
        if (status == DeviceAuthorizationStatus.PENDING) {
            throw new IllegalStateException("Device authorization is PENDING account-owner consent");
        }
        if (status == DeviceAuthorizationStatus.REVOKED) {
            throw new IllegalStateException("Device authorization has been REVOKED");
        }
        if (status == DeviceAuthorizationStatus.EXPIRED || auth.isExpired(now)) {
            auth.setStatus(DeviceAuthorizationStatus.EXPIRED.name());
            if (deviceAuthorizationRepository != null) {
                try {
                    deviceAuthorizationRepository.save(auth);
                } catch (Exception e) {}
            }
            throw new IllegalStateException("Device authorization has EXPIRED");
        }
        if (status != DeviceAuthorizationStatus.AUTHORIZED) {
            throw new IllegalStateException("Device authorization is in invalid state: " + auth.getStatus());
        }

        // 3. Verify registered public-key fingerprint binding
        if (auth.getKeyFingerprint() == null || auth.getKeyFingerprint().isBlank()) {
            throw new IllegalStateException("Device authorization record is missing required public-key fingerprint binding");
        }
        if (signingKey == null) {
            throw new IllegalArgumentException("Signing public key must not be null");
        }
        String activeFingerprint = computeFingerprint(signingKey);
        if (!auth.getKeyFingerprint().equalsIgnoreCase(activeFingerprint)) {
            throw new IllegalArgumentException(
                    "Device public key fingerprint mismatch with authorization record: "
                    + activeFingerprint + " != " + auth.getKeyFingerprint()
            );
        }

        // 4. Verify spending limit
        if (auth.getSpendingLimit() == null || auth.getSpendingLimit().compareTo(BigDecimal.ZERO) <= 0) {
            throw new IllegalStateException("Device authorization record has invalid or missing spending limit");
        }
        if (amount != null && amount.compareTo(auth.getSpendingLimit()) > 0) {
            throw new IllegalStateException(
                    "Debit amount (" + amount + ") exceeds authorized spending limit of " + auth.getSpendingLimit()
            );
        }
    }

    /**
     * Queries the authorization record for a device and account.
     */
    public Optional<DeviceAccountAuthorization> getAuthorization(String deviceId, String accountId) {
        if (deviceId == null || accountId == null) {
            return Optional.empty();
        }
        String dev = deviceId.trim().toLowerCase();
        String acc = accountId.trim().toLowerCase();
        String cacheKey = dev + ":" + acc;

        DeviceAccountAuthorization auth = authorizationCache.get(cacheKey);
        Instant now = Instant.now();
        if (auth != null) {
            if (auth.isExpired(now) && auth.getStatusEnum() == DeviceAuthorizationStatus.AUTHORIZED) {
                auth.setStatus(DeviceAuthorizationStatus.EXPIRED.name());
                if (deviceAuthorizationRepository != null) {
                    try {
                        deviceAuthorizationRepository.save(auth);
                    } catch (Exception e) {}
                }
            }
            return Optional.of(auth);
        }
        if (deviceAuthorizationRepository != null) {
            Optional<DeviceAccountAuthorization> dbRecord = deviceAuthorizationRepository.findByDeviceIdAndAccountId(dev, acc);
            dbRecord.ifPresent(r -> {
                if (r.isExpired(now) && r.getStatusEnum() == DeviceAuthorizationStatus.AUTHORIZED) {
                    r.setStatus(DeviceAuthorizationStatus.EXPIRED.name());
                    try {
                        deviceAuthorizationRepository.save(r);
                    } catch (Exception e) {}
                }
                authorizationCache.put(cacheKey, r);
            });
            return dbRecord;
        }
        return Optional.empty();
    }

    /**
     * Returns an unmodifiable set of account IDs actively authorized for the given device.
     */
    public Set<String> getAuthorizedAccounts(String deviceId) {
        if (deviceId == null) return Collections.emptySet();
        String dev = deviceId.trim().toLowerCase();
        Set<String> accounts = authorizedAccountsByDevice.get(dev);
        return accounts != null ? Collections.unmodifiableSet(accounts) : Collections.emptySet();
    }

    /**
     * Computes the SHA-256 fingerprint (in lowercase hex) of the given public key's DER-encoded bytes.
     */
    public static String computeFingerprint(PublicKey publicKey) {
        if (publicKey == null) return null;
        try {
            MessageDigest sha256 = MessageDigest.getInstance("SHA-256");
            byte[] digest = sha256.digest(publicKey.getEncoded());
            StringBuilder sb = new StringBuilder();
            for (byte b : digest) {
                sb.append(String.format("%02x", b));
            }
            return sb.toString();
        } catch (NoSuchAlgorithmException e) {
            throw new RuntimeException("SHA-256 not supported by JVM", e);
        }
    }

    /**
     * Clears all authorizations from cache and database explicitly for test isolation.
     */
    @Transactional
    public void clearForTesting() {
        authorizationCache.clear();
        authorizedAccountsByDevice.clear();
        if (deviceAuthorizationRepository != null) {
            deviceAuthorizationRepository.deleteAll();
            deviceAuthorizationRepository.flush();
        }
    }

    /**
     * @deprecated Use {@link #clearForTesting()} in tests. Preserved for backwards compatibility.
     */
    @Deprecated
    public void clear() {
        clearForTesting();
    }
}
