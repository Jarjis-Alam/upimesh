package com.demo.upimesh;

import com.demo.upimesh.model.AccountOwnerConsentRequest;
import com.demo.upimesh.model.AccountOwnerKeyRepository;
import com.demo.upimesh.model.AccountRepository;
import com.demo.upimesh.model.ConsumedConsent;
import com.demo.upimesh.model.ConsumedConsentRepository;
import com.demo.upimesh.model.DeviceAccountAuthorization;
import com.demo.upimesh.model.DeviceAuthorizationStatus;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.security.PublicKey;
import java.time.Instant;

/**
 * Service verifying cryptographically authentic, non-reusable Account-Owner Consent statements
 * under Stage 8.6.
 * <p>
 * Ensures:
 * 1. Consent is explicitly bound to account ID, device ID, device key fingerprint, spending limit, and expiry.
 * 2. Digital signature is cryptographically verified against the account owner's registered public key.
 * 3. Each unique consent ID can only be consumed once (durable replay protection).
 * 4. Modified parameters (tampered account ID, device ID, limit, expiry) fail verification.
 * 5. Device key fingerprint must strictly match the device's registered public key.
 * 6. Carol debit authorization remains strictly fail-closed.
 */
@Service
public class AccountOwnerConsentService {

    private static final Logger log = LoggerFactory.getLogger(AccountOwnerConsentService.class);

    private final AccountOwnerKeyRegistry accountOwnerKeyRegistry;
    private final SenderKeyRegistry senderKeyRegistry;
    private final ConsumedConsentRepository consumedConsentRepository;
    private final AccountRepository accountRepository;
    private final DeviceAuthorizationRegistry deviceAuthorizationRegistry;
    private final CryptoService cryptoService;

    public AccountOwnerConsentService() {
        this(null, null, null, null, null, null);
    }

    @Autowired
    public AccountOwnerConsentService(
            @Autowired(required = false) AccountOwnerKeyRegistry accountOwnerKeyRegistry,
            @Autowired(required = false) SenderKeyRegistry senderKeyRegistry,
            @Autowired(required = false) ConsumedConsentRepository consumedConsentRepository,
            @Autowired(required = false) AccountRepository accountRepository,
            @Autowired(required = false) DeviceAuthorizationRegistry deviceAuthorizationRegistry,
            @Autowired(required = false) CryptoService cryptoService
    ) {
        this.accountOwnerKeyRegistry = accountOwnerKeyRegistry != null ? accountOwnerKeyRegistry : new AccountOwnerKeyRegistry();
        this.senderKeyRegistry = senderKeyRegistry != null ? senderKeyRegistry : new SenderKeyRegistry();
        this.consumedConsentRepository = consumedConsentRepository;
        this.accountRepository = accountRepository;
        this.deviceAuthorizationRegistry = deviceAuthorizationRegistry != null ? deviceAuthorizationRegistry : new DeviceAuthorizationRegistry();
        this.cryptoService = cryptoService != null ? cryptoService : new CryptoService();
    }

    /**
     * Cryptographically verifies an account-owner consent statement and authorizes the device upon success.
     *
     * @param request the consent request containing authorization parameters and digital signature
     * @return the newly created or updated DeviceAccountAuthorization
     * @throws SecurityException if signature fails, replay detected, fingerprint mismatches, or Carol is targeted
     * @throws IllegalArgumentException if inputs are invalid, expired, or referenced accounts/devices do not exist
     */
    @Transactional
    public DeviceAccountAuthorization verifyAndApplyConsent(AccountOwnerConsentRequest request) {
        if (request == null) {
            throw new IllegalArgumentException("AccountOwnerConsentRequest must not be null");
        }

        String consentId = request.consentId().trim();
        String accountId = request.accountId().trim().toLowerCase();
        String deviceId = request.deviceId().trim().toLowerCase();
        String deviceKeyFingerprint = request.deviceKeyFingerprint().trim().toLowerCase();
        BigDecimal spendingLimit = request.spendingLimit();
        Instant expiresAt = request.expiresAt();
        String ownerSignature = request.ownerSignature();

        // 1. Fail-closed guard: Carol debit authorization is explicitly blocked
        if ("carol".equalsIgnoreCase(accountId)) {
            log.warn("Blocked account-owner consent authorization attempt for account 'carol' from device '{}'", deviceId);
            throw new SecurityException("Account-owner authorization is blocked for account 'carol': cryptographic proof of account-owner consent is not implemented");
        }

        // 2. Temporal expiry check
        if (expiresAt.isBefore(Instant.now())) {
            log.warn("Consent token '{}' has expired at {}", consentId, expiresAt);
            throw new IllegalArgumentException("Consent token has expired at " + expiresAt);
        }

        // 3. Ledger account existence check
        if (accountRepository != null && !accountRepository.existsById(accountId)) {
            throw new IllegalArgumentException("Account '" + accountId + "' does not exist in ledger");
        }

        // 4. Device registration and cryptographic key fingerprint check
        if (!senderKeyRegistry.hasKey(deviceId)) {
            throw new IllegalArgumentException("Device '" + deviceId + "' must be registered in SenderKeyRegistry before authorization");
        }
        PublicKey devicePubKey = senderKeyRegistry.getPublicKey(deviceId)
                .orElseThrow(() -> new IllegalArgumentException("Device key for '" + deviceId + "' not found in registry"));
        String actualFingerprint = DeviceAuthorizationRegistry.computeFingerprint(devicePubKey);
        if (!actualFingerprint.equalsIgnoreCase(deviceKeyFingerprint)) {
            log.warn("Device key fingerprint mismatch for device '{}'. Expected: {}, Received: {}",
                    deviceId, actualFingerprint, deviceKeyFingerprint);
            throw new SecurityException("Device key fingerprint mismatch. Expected: " + actualFingerprint + ", Provided: " + deviceKeyFingerprint);
        }

        // 5. Account-owner verification key retrieval
        PublicKey ownerPubKey = accountOwnerKeyRegistry.getPublicKey(accountId)
                .orElseThrow(() -> new SecurityException("Account owner public key is not registered for account '" + accountId + "'"));

        // 6. Replay protection check
        if (consumedConsentRepository != null && consumedConsentRepository.existsById(consentId)) {
            log.warn("Replay attack detected: consent ID '{}' has already been consumed", consentId);
            throw new SecurityException("Consent ID '" + consentId + "' has already been consumed (replay attack detected)");
        }

        // 7. Cryptographic signature verification over canonical payload
        byte[] canonicalBytes = request.toCanonicalBytes();
        boolean validSignature = false;
        try {
            validSignature = cryptoService.verifySignatureBase64(canonicalBytes, ownerSignature, ownerPubKey);
        } catch (Exception e) {
            log.warn("Cryptographic verification exception for consent ID '{}': {}", consentId, e.getMessage());
            throw new SecurityException("Cryptographic verification failed: " + e.getMessage(), e);
        }

        if (!validSignature) {
            log.warn("Invalid digital signature on consent ID '{}' for account '{}'", consentId, accountId);
            throw new SecurityException("Cryptographic signature verification failed for account-owner consent");
        }

        // 8. Durable replay record persistence
        if (consumedConsentRepository != null) {
            try {
                consumedConsentRepository.saveAndFlush(new ConsumedConsent(consentId, accountId, deviceId, Instant.now()));
            } catch (DataIntegrityViolationException dive) {
                log.warn("Concurrent consent replay detected for ID '{}': {}", consentId, dive.getMessage());
                throw new SecurityException("Consent ID '" + consentId + "' has already been consumed (concurrent replay detected)", dive);
            }
        }

        // 9. Transition device authorization status to AUTHORIZED with bounded limits
        DeviceAccountAuthorization authRecord = deviceAuthorizationRegistry.authorizeDevice(
                deviceId,
                accountId,
                DeviceAuthorizationStatus.AUTHORIZED,
                actualFingerprint,
                spendingLimit,
                expiresAt
        );

        log.info("Successfully verified account-owner consent '{}' and authorized device '{}' for account '{}' with limit {}",
                consentId, deviceId, accountId, spendingLimit);

        return authRecord;
    }

    /**
     * Checks if a consent ID has already been consumed.
     */
    public boolean isConsentConsumed(String consentId) {
        if (consentId == null || consumedConsentRepository == null) {
            return false;
        }
        return consumedConsentRepository.existsById(consentId.trim());
    }
}
