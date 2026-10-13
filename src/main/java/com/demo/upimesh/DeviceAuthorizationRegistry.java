package com.demo.upimesh;

import com.demo.upimesh.model.DeviceAccountAuthorization;
import com.demo.upimesh.model.DeviceAuthorizationRepository;
import jakarta.annotation.PostConstruct;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import java.time.Instant;
import java.util.Collections;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Prototype authorization registry linking registered physical/virtual device IDs
 * to the bank accounts they are authorized to debit.
 * Backed by durable H2 database persistence across application restarts, with an
 * in-memory cache for fast verification.
 * <p>
 * PROTOTYPE TRUST BOUNDARY & AUTHORIZATION MODEL:
 * In a production UPI offline mesh architecture, account-to-device authorization is established
 * out-of-band by the issuing bank via hardware attestation (Apple DeviceCheck / App Attest)
 * combined with SMS OTP challenge and cryptographic key binding certified by the bank's CA.
 * <p>
 * Under prototype policy:
 * 1. Public key registration in SenderKeyRegistry proves the device possesses a valid RSA-2048 keypair.
 * 2. But public key self-registration alone DOES NOT grant ownership or debit authority over arbitrary bank accounts.
 * 3. A device ID must be explicitly authorized in this registry for a specific account ID before debit instructions are accepted.
 * 4. Virtual demo nodes where deviceId equals accountId (e.g. simulated "alice" node) are self-authorized for simulation backwards-compatibility.
 */
@Service
public class DeviceAuthorizationRegistry {

    private final DeviceAuthorizationRepository deviceAuthorizationRepository;
    private final Map<String, Set<String>> authorizedAccountsByDevice = new ConcurrentHashMap<>();

    public DeviceAuthorizationRegistry() {
        this(null);
    }

    @Autowired
    public DeviceAuthorizationRegistry(@Autowired(required = false) DeviceAuthorizationRepository deviceAuthorizationRepository) {
        this.deviceAuthorizationRepository = deviceAuthorizationRepository;
    }

    /**
     * Warms the in-memory cache with all persisted authorization bindings at startup.
     */
    @PostConstruct
    public void init() {
        if (deviceAuthorizationRepository != null) {
            for (DeviceAccountAuthorization auth : deviceAuthorizationRepository.findAll()) {
                authorizedAccountsByDevice.computeIfAbsent(
                        auth.getDeviceId().toLowerCase().trim(),
                        k -> ConcurrentHashMap.newKeySet()
                ).add(auth.getAccountId().toLowerCase().trim());
            }
        }
    }

    /**
     * Authorizes a device to debit the specified account and persists the binding to database.
     *
     * @param deviceId  the unique hardware/installation device ID
     * @param accountId the funding bank account ID (e.g. "alice")
     */
    public void authorizeDevice(String deviceId, String accountId) {
        if (deviceId == null || deviceId.isBlank()) {
            throw new IllegalArgumentException("deviceId must not be blank");
        }
        if (accountId == null || accountId.isBlank()) {
            throw new IllegalArgumentException("accountId must not be blank");
        }
        String dev = deviceId.trim().toLowerCase();
        String acc = accountId.trim().toLowerCase();

        // 1. Persist to database if not already stored (consistent write-through with immediate flush)
        if (deviceAuthorizationRepository != null) {
            if (!deviceAuthorizationRepository.existsByDeviceIdAndAccountId(dev, acc)) {
                try {
                    deviceAuthorizationRepository.saveAndFlush(new DeviceAccountAuthorization(
                            UUID.randomUUID().toString(),
                            dev,
                            acc,
                            Instant.now()
                    ));
                } catch (DataIntegrityViolationException ex) {
                    // Handled concurrently by another thread; idempotent duplicate insert
                }
            }
        }

        // 2. Update in-memory cache only after durable database persistence succeeds
        updateCacheWithRollbackSync(dev, acc);
    }

    private void updateCacheWithRollbackSync(String dev, String acc) {
        authorizedAccountsByDevice.computeIfAbsent(dev, k -> ConcurrentHashMap.newKeySet()).add(acc);
        if (TransactionSynchronizationManager.isActualTransactionActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override
                public void afterCompletion(int status) {
                    if (status != STATUS_COMMITTED) {
                        Set<String> accounts = authorizedAccountsByDevice.get(dev);
                        if (accounts != null) {
                            accounts.remove(acc);
                        }
                    }
                }
            });
        }
    }

    /**
     * Revokes authorization for a device to debit the specified account.
     */
    @Transactional
    public void revokeDevice(String deviceId, String accountId) {
        if (deviceId != null && accountId != null) {
            String dev = deviceId.trim().toLowerCase();
            String acc = accountId.trim().toLowerCase();
            Set<String> accounts = authorizedAccountsByDevice.get(dev);
            if (accounts != null) {
                accounts.remove(acc);
            }
            if (deviceAuthorizationRepository != null) {
                deviceAuthorizationRepository.deleteByDeviceIdAndAccountId(dev, acc);
            }
        }
    }

    /**
     * Checks if a device is authorized to debit the given account.
     *
     * @param deviceId  the device claiming to authorize the transaction
     * @param accountId the funding account to be debited
     * @return true if authorized, false otherwise
     */
    public boolean isDeviceAuthorized(String deviceId, String accountId) {
        if (deviceId == null || accountId == null) {
            return false;
        }
        String dev = deviceId.trim().toLowerCase();
        String acc = accountId.trim().toLowerCase();

        // Allow virtual simulation devices where deviceId is identical to accountId
        if (dev.equals(acc)) {
            return true;
        }

        Set<String> accounts = authorizedAccountsByDevice.get(dev);
        if (accounts != null && accounts.contains(acc)) {
            return true;
        }

        // Fallback read-through to database
        if (deviceAuthorizationRepository != null && deviceAuthorizationRepository.existsByDeviceIdAndAccountId(dev, acc)) {
            authorizedAccountsByDevice.computeIfAbsent(dev, k -> ConcurrentHashMap.newKeySet()).add(acc);
            return true;
        }

        return false;
    }

    /**
     * Returns an unmodifiable set of account IDs authorized for the given device.
     */
    public Set<String> getAuthorizedAccounts(String deviceId) {
        if (deviceId == null) return Collections.emptySet();
        String dev = deviceId.trim().toLowerCase();
        Set<String> accounts = authorizedAccountsByDevice.get(dev);
        return accounts != null ? Collections.unmodifiableSet(accounts) : Collections.emptySet();
    }

    /**
     * Clears all authorizations from cache and database explicitly for test isolation.
     */
    @Transactional
    public void clearForTesting() {
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
