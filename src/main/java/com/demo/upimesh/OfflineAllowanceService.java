package com.demo.upimesh;

import com.demo.upimesh.model.Account;
import com.demo.upimesh.model.AccountRepository;
import com.demo.upimesh.model.AllowanceIssuanceRequest;
import com.demo.upimesh.model.DeviceAccountAuthorization;
import com.demo.upimesh.model.DeviceAuthorizationRepository;
import com.demo.upimesh.model.DeviceAuthorizationStatus;
import com.demo.upimesh.model.OfflineAllowance;
import com.demo.upimesh.model.OfflineAllowanceRepository;
import com.demo.upimesh.model.OfflineAllowanceStatus;
import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.security.PublicKey;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Optional;
import java.util.UUID;

/**
 * Service managing the issuance and atomic escrow reservation of offline allowances under Phase 1.
 * <p>
 * Financial Invariants:
 * 1. Double-Entry Escrow Reservation:
 *    The allocated allowance amount is atomically debited from the user's available balance
 *    and credited to the system escrow account ({@value #ESCROW_ACCOUNT_ID}) within a single
 *    ACID database transaction. No shadow or off-ledger balance sources are created.
 * 2. Unbroken Conservation of Funds:
 *    Total system money is preserved at all times:
 *    {@code sum(all account balances including system-escrow) == constant}.
 * 3. Database-Enforced Single Active Allowance:
 *    Enforces the single-active-allowance-per-account invariant via database-level uniqueness
 *    on {@code active_account_id}, preventing application-level race conditions.
 * 4. Dedicated Bank Authority Signatures:
 *    Vouchers are signed deterministically using the central bank's dedicated RSA-2048 signing key.
 */
@Service
public class OfflineAllowanceService {

    private static final Logger log = LoggerFactory.getLogger(OfflineAllowanceService.class);

    public static final String ESCROW_ACCOUNT_ID = "system-escrow";
    public static final String DEFAULT_CURRENCY = "INR";
    public static final long MIN_DURATION_HOURS = 1L;
    public static final long MAX_DURATION_HOURS = 72L;

    private final AccountRepository accountRepository;
    private final OfflineAllowanceRepository offlineAllowanceRepository;
    private final SettlementService settlementService;
    private final DeviceAuthorizationRegistry deviceAuthorizationRegistry;
    private final DeviceAuthorizationRepository deviceAuthorizationRepository;
    private final SenderKeyRegistry senderKeyRegistry;
    private final BankAuthorityKeyService bankAuthorityKeyService;

    @Autowired
    public OfflineAllowanceService(
            AccountRepository accountRepository,
            OfflineAllowanceRepository offlineAllowanceRepository,
            SettlementService settlementService,
            DeviceAuthorizationRegistry deviceAuthorizationRegistry,
            DeviceAuthorizationRepository deviceAuthorizationRepository,
            SenderKeyRegistry senderKeyRegistry,
            BankAuthorityKeyService bankAuthorityKeyService
    ) {
        this.accountRepository = accountRepository;
        this.offlineAllowanceRepository = offlineAllowanceRepository;
        this.settlementService = settlementService;
        this.deviceAuthorizationRegistry = deviceAuthorizationRegistry;
        this.deviceAuthorizationRepository = deviceAuthorizationRepository;
        this.senderKeyRegistry = senderKeyRegistry;
        this.bankAuthorityKeyService = bankAuthorityKeyService;
    }

    @PostConstruct
    public void init() {
        ensureEscrowAccountExists();
    }

    /**
     * Ensures the internal system escrow ledger account exists with zero opening balance.
     */
    public synchronized void ensureEscrowAccountExists() {
        if (!accountRepository.existsById(ESCROW_ACCOUNT_ID)) {
            try {
                accountRepository.save(new Account(ESCROW_ACCOUNT_ID, BigDecimal.ZERO));
                log.info("Initialized system escrow account: {}", ESCROW_ACCOUNT_ID);
            } catch (Exception e) {
                // If created concurrently or already present, ignore
            }
        }
    }

    /**
     * Atomically issues an offline allowance and reserves the requested funds into system escrow.
     *
     * @param request the allowance issuance parameters
     * @return the persisted and cryptographically signed OfflineAllowance
     * @throws IllegalArgumentException if request parameters or accounts are invalid
     * @throws IllegalStateException    if the account has insufficient funds, unapproved device, or an active allowance
     */
    @Transactional
    public OfflineAllowance issueAllowance(AllowanceIssuanceRequest request) {
        if (request == null) {
            throw new IllegalArgumentException("Allowance issuance request must not be null");
        }

        if (request.accountId() == null || request.accountId().isBlank()) {
            throw new IllegalArgumentException("Account ID must not be blank");
        }
        final String accountId = request.accountId().trim().toLowerCase();

        if (request.deviceId() == null || request.deviceId().isBlank()) {
            throw new IllegalArgumentException("Device ID must not be blank");
        }
        final String deviceId = request.deviceId().trim();

        BigDecimal amount = request.amount();
        if (amount == null || amount.compareTo(BigDecimal.ZERO) <= 0) {
            throw new IllegalArgumentException("Allocated allowance amount must be strictly greater than zero");
        }
        if (amount.scale() > 2) {
            throw new IllegalArgumentException("Allocated amount cannot have more than 2 decimal places");
        }

        String currency = request.currency();
        if (currency == null || currency.isBlank()) {
            currency = DEFAULT_CURRENCY;
        }
        currency = currency.trim().toUpperCase();
        if (!DEFAULT_CURRENCY.equalsIgnoreCase(currency)) {
            throw new IllegalArgumentException("Unsupported currency: " + currency + "; only " + DEFAULT_CURRENCY + " is supported");
        }

        long durationHours = request.durationHours() != null ? request.durationHours() : 24L;
        if (durationHours < MIN_DURATION_HOURS || durationHours > MAX_DURATION_HOURS) {
            throw new IllegalArgumentException(String.format(
                    "Allowance duration must be between %d and %d hours (requested: %d)",
                    MIN_DURATION_HOURS, MAX_DURATION_HOURS, durationHours
            ));
        }

        // 1. Verify funding account exists
        Account account = accountRepository.findById(accountId)
                .orElseThrow(() -> new IllegalArgumentException("No account exists with ID: " + accountId));

        // 2. Verify device public key registration and resolve fingerprint
        PublicKey devicePublicKey = senderKeyRegistry != null
                ? senderKeyRegistry.getPublicKey(deviceId).orElse(null)
                : null;
        if (devicePublicKey == null) {
            throw new IllegalArgumentException("Unknown or unregistered device ID: " + deviceId);
        }
        String deviceFingerprint = DeviceAuthorizationRegistry.computeFingerprint(devicePublicKey);

        // 3. Verify device authorization permissions and status for this account (FAIL-CLOSED)
        if (deviceAuthorizationRepository != null) {
            String normDev = deviceId.toLowerCase();
            DeviceAccountAuthorization auth = deviceAuthorizationRepository.findByDeviceIdAndAccountId(normDev, accountId)
                    .orElseThrow(() -> new IllegalStateException(
                            "Device '" + deviceId + "' is not authorized to debit account: " + accountId
                    ));
            if ("REVOKED".equalsIgnoreCase(auth.getStatus())) {
                throw new IllegalStateException("Device authorization has been revoked for account: " + accountId);
            }
            if ("EXPIRED".equalsIgnoreCase(auth.getStatus()) ||
                    (auth.getExpiresAt() != null && auth.getExpiresAt().isBefore(Instant.now()))) {
                throw new IllegalStateException("Device authorization has expired for account: " + accountId);
            }
            if (!"AUTHORIZED".equalsIgnoreCase(auth.getStatus())) {
                throw new IllegalStateException("Device is not in AUTHORIZED status for account: " + accountId);
            }
            if (auth.getSpendingLimit() != null && amount.compareTo(auth.getSpendingLimit()) > 0) {
                throw new IllegalStateException(String.format(
                        "Requested allowance amount (%s) exceeds authorized device limit (%s)",
                        amount, auth.getSpendingLimit()
                ));
            }
            if (auth.getKeyFingerprint() != null && !auth.getKeyFingerprint().isBlank()
                    && !auth.getKeyFingerprint().equalsIgnoreCase(deviceFingerprint)) {
                throw new IllegalStateException(
                        "Device public key fingerprint does not match authorized binding for account: " + accountId
                );
            }
        } else {
            throw new IllegalStateException("Device authorization repository is required but unavailable");
        }

        // 4. Ensure no active unexpired allowance exists for this account.
        // If an old allowance exists that has expired by deadline, transition it to EXPIRED to free the active slot.
        Instant now = Instant.now();
        Optional<OfflineAllowance> existingActive = offlineAllowanceRepository.findByActiveAccountId(accountId);
        if (existingActive.isPresent()) {
            OfflineAllowance existing = existingActive.get();
            if (existing.getStatus() == OfflineAllowanceStatus.ACTIVE) {
                if (existing.getExpiresAt().isAfter(now)) {
                    throw new IllegalStateException("Active offline allowance already exists for account: " + accountId);
                } else {
                    // Transition expired allowance so active_account_id is cleared to null
                    log.info("Transitioning expired allowance {} for account {} to EXPIRED", existing.getId(), accountId);
                    existing.setStatus(OfflineAllowanceStatus.EXPIRED);
                    offlineAllowanceRepository.saveAndFlush(existing);
                }
            }
        }

        // 5. Ensure internal system escrow account exists
        ensureEscrowAccountExists();

        // 6. Atomically transfer funds from user account into system escrow ledger account
        // (SettlementService.transfer checks for sufficient funds and orders entity saves deterministically)
        settlementService.transfer(accountId, ESCROW_ACCOUNT_ID, amount);

        // 7. Construct allowance timestamps and canonical representation
        Instant expiresAt = now.plus(durationHours, ChronoUnit.HOURS);
        String allowanceId = "alw-" + UUID.randomUUID();
        int version = OfflineAllowance.CURRENT_PROTOCOL_VERSION;

        byte[] canonicalBytes = OfflineAllowance.buildCanonicalVoucherBytes(
                allowanceId,
                accountId,
                deviceId,
                deviceFingerprint,
                currency,
                amount,
                now,
                expiresAt,
                version
        );

        // 8. Sign canonical voucher with Bank Authority dedicated private key
        String voucherSignature = bankAuthorityKeyService.signVoucherBase64(canonicalBytes);

        // 9. Persist OfflineAllowance entity with activeAccountId set
        OfflineAllowance allowance = new OfflineAllowance(
                allowanceId,
                accountId,
                deviceId,
                deviceFingerprint,
                currency,
                amount,
                now,
                expiresAt,
                version,
                OfflineAllowanceStatus.ACTIVE,
                voucherSignature
        );

        try {
            return offlineAllowanceRepository.saveAndFlush(allowance);
        } catch (DataIntegrityViolationException e) {
            // Database-level uniqueness violation on active_account_id caught during concurrent race
            throw new IllegalStateException("Active offline allowance already exists for account: " + accountId, e);
        }
    }

    /**
     * Retrieves an allowance by unique identifier.
     */
    @Transactional(readOnly = true)
    public Optional<OfflineAllowance> getAllowance(String allowanceId) {
        if (allowanceId == null || allowanceId.isBlank()) {
            return Optional.empty();
        }
        return offlineAllowanceRepository.findById(allowanceId.trim());
    }

    /**
     * Retrieves the currently active allowance for the specified account, if one exists.
     */
    @Transactional(readOnly = true)
    public Optional<OfflineAllowance> getActiveAllowance(String accountId) {
        if (accountId == null || accountId.isBlank()) {
            return Optional.empty();
        }
        return offlineAllowanceRepository.findByActiveAccountId(accountId.trim().toLowerCase());
    }
}
