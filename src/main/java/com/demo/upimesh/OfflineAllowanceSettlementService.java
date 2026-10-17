package com.demo.upimesh;

import com.demo.upimesh.model.AccountRepository;
import com.demo.upimesh.model.OfflineAllowance;
import com.demo.upimesh.model.OfflineAllowanceRefundResult;
import com.demo.upimesh.model.OfflineAllowanceRepository;
import com.demo.upimesh.model.OfflineAllowanceStatus;
import com.demo.upimesh.model.OfflineSecurityEvent;
import com.demo.upimesh.model.OfflineSecurityEventRepository;
import com.demo.upimesh.model.OfflineSpendPayment;
import com.demo.upimesh.model.OfflineSpendPaymentRepository;
import com.demo.upimesh.model.OfflineSpendRecord;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.security.GeneralSecurityException;
import java.security.PublicKey;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * Service managing the settlement of offline allowance spends, double-entry escrow reconciliation,
 * and security event detection.
 * <p>
 * Financial & Cryptographic Invariants:
 * 1. Double-Entry Escrow Settlement:
 *    Accepted offline payments are settled by debiting the system escrow account ({@value OfflineAllowanceService#ESCROW_ACCOUNT_ID})
 *    and crediting the merchant recipient. Payer funds were already reserved at issuance; no shadow accounts or overdrafts.
 * 2. Unbroken System Zero-Sum:
 *    Total system funds remain strictly constant: sum(all accounts including system-escrow) == constant.
 * 3. Authority Voucher & Payer Signature Verification:
 *    Both the original bank-signed voucher and the device-signed spend record are cryptographically verified
 *    using RSASSA-PSS SHA-256 before settlement.
 * 4. Fraud & Sequence Fork Detection:
 *    Conflicting sequence numbers or cumulative amounts for the same allowance are treated as high-severity security events,
 *    triggering durable audit logging and immediate allowance revocation.
 * 5. In-Transit Merchant Protection & Reconciliation Window:
 *    Unused escrow funds are protected during an active reconciliation grace window ({@link #RECONCILIATION_GRACE_PERIOD})
 *    to prevent the payer from recovering escrow before merchants can connect and redeem valid offline payments.
 */
@Service
public class OfflineAllowanceSettlementService {

    private static final Logger log = LoggerFactory.getLogger(OfflineAllowanceSettlementService.class);

    public static final Duration RECONCILIATION_GRACE_PERIOD = Duration.ofHours(24);
    public static final Duration MAX_FUTURE_CLOCK_SKEW = Duration.ofMinutes(5);

    private final AccountRepository accountRepository;
    private final OfflineAllowanceRepository offlineAllowanceRepository;
    private final OfflineSpendPaymentRepository offlineSpendPaymentRepository;
    private final OfflineSecurityEventRepository offlineSecurityEventRepository;
    private final SettlementService settlementService;
    private final SenderKeyRegistry senderKeyRegistry;
    private final BankAuthorityKeyService bankAuthorityKeyService;
    private final CryptoService cryptoService;
    private final OfflineSecurityAuditService securityAuditService;
    private final Clock clock;

    @Autowired
    public OfflineAllowanceSettlementService(
            AccountRepository accountRepository,
            OfflineAllowanceRepository offlineAllowanceRepository,
            OfflineSpendPaymentRepository offlineSpendPaymentRepository,
            OfflineSecurityEventRepository offlineSecurityEventRepository,
            SettlementService settlementService,
            SenderKeyRegistry senderKeyRegistry,
            BankAuthorityKeyService bankAuthorityKeyService,
            CryptoService cryptoService,
            @Autowired(required = false) OfflineSecurityAuditService securityAuditService
    ) {
        this(accountRepository, offlineAllowanceRepository, offlineSpendPaymentRepository,
                offlineSecurityEventRepository, settlementService, senderKeyRegistry,
                bankAuthorityKeyService, cryptoService, securityAuditService, Clock.systemUTC());
    }

    public OfflineAllowanceSettlementService(
            AccountRepository accountRepository,
            OfflineAllowanceRepository offlineAllowanceRepository,
            OfflineSpendPaymentRepository offlineSpendPaymentRepository,
            OfflineSecurityEventRepository offlineSecurityEventRepository,
            SettlementService settlementService,
            SenderKeyRegistry senderKeyRegistry,
            BankAuthorityKeyService bankAuthorityKeyService,
            CryptoService cryptoService,
            OfflineSecurityAuditService securityAuditService,
            Clock clock
    ) {
        this.accountRepository = accountRepository;
        this.offlineAllowanceRepository = offlineAllowanceRepository;
        this.offlineSpendPaymentRepository = offlineSpendPaymentRepository;
        this.offlineSecurityEventRepository = offlineSecurityEventRepository;
        this.settlementService = settlementService;
        this.senderKeyRegistry = senderKeyRegistry;
        this.bankAuthorityKeyService = bankAuthorityKeyService;
        this.cryptoService = cryptoService;
        this.securityAuditService = securityAuditService != null
                ? securityAuditService
                : new OfflineSecurityAuditService(offlineSecurityEventRepository, offlineAllowanceRepository);
        this.clock = clock;
    }

    /**
     * Atomically validates an offline spend record, verifies all signatures, evaluates fraud evidence,
     * debits system escrow, credits the recipient merchant, and records the consumption.
     */
    @Transactional
    public OfflineSpendPayment settleOfflineSpend(OfflineSpendRecord record) throws GeneralSecurityException {
        if (record == null) {
            throw new IllegalArgumentException("OfflineSpendRecord must not be null");
        }

        // 1. Basic field & parameter validation
        validateSpendRecordFields(record);

        // 2. Persistent Idempotency check: paymentId uniqueness
        Optional<OfflineSpendPayment> existingOpt = offlineSpendPaymentRepository.findByPaymentId(record.paymentId());
        if (existingOpt.isPresent()) {
            OfflineSpendPayment existing = existingOpt.get();
            boolean matches = existing.getAllowanceId().equalsIgnoreCase(record.allowanceId())
                    && existing.getPayerAccountId().equalsIgnoreCase(record.payerAccountId())
                    && existing.getRecipientAccountId().equalsIgnoreCase(record.recipientAccountId())
                    && existing.getAmount().compareTo(record.amount()) == 0
                    && existing.getSequenceNumber() == record.sequenceNumber();
            if (!matches) {
                throw new DuplicatePacketException(
                        "Conflicting payment instruction rejected: paymentId '" + record.paymentId() +
                                "' was already settled with different parameters"
                );
            }
            log.info("Idempotent replay of settled offline payment: {}", record.paymentId());
            return existing;
        }

        // 3. Load & check OfflineAllowance
        OfflineAllowance allowance = offlineAllowanceRepository.findById(record.allowanceId())
                .orElseThrow(() -> new IllegalArgumentException("No allowance found with ID: " + record.allowanceId()));

        if (allowance.getStatus() == OfflineAllowanceStatus.REVOKED) {
            throw new IllegalStateException("Allowance has been revoked due to security violation or fraud: " + allowance.getId());
        }
        if (allowance.getStatus() == OfflineAllowanceStatus.REDEEMED) {
            throw new IllegalStateException("Allowance has already been redeemed and closed: " + allowance.getId());
        }

        // 4. Validate Bank Authority Voucher signature
        byte[] voucherBytes = allowance.toCanonicalVoucherBytes();
        boolean voucherValid = bankAuthorityKeyService.verifyVoucherSignature(voucherBytes, record.voucherSignature());
        if (!voucherValid) {
            recordSecurityEvent(allowance, record.paymentId(), null, record.sequenceNumber(),
                    "TAMPERED_VOUCHER_SIGNATURE",
                    "Offline spend presented with invalid or tampered bank authority voucher signature");
            throw new GeneralSecurityException("Invalid bank authority voucher signature for allowance: " + allowance.getId());
        }

        // 5. Verify account and device binding
        if (!record.payerAccountId().equalsIgnoreCase(allowance.getAccountId())) {
            throw new IllegalArgumentException(String.format(
                    "Payer account mismatch: record specifies '%s', but allowance belongs to '%s'",
                    record.payerAccountId(), allowance.getAccountId()
            ));
        }
        if (!record.payerDeviceId().equalsIgnoreCase(allowance.getDeviceId())) {
            throw new IllegalArgumentException(String.format(
                    "Payer device ID mismatch: record specifies '%s', but allowance bound to '%s'",
                    record.payerDeviceId(), allowance.getDeviceId()
            ));
        }

        // 6. Verify Payer Digital Signature
        PublicKey payerPublicKey = senderKeyRegistry != null
                ? senderKeyRegistry.getPublicKey(record.payerDeviceId()).orElse(null)
                : null;
        if (payerPublicKey == null) {
            throw new IllegalArgumentException("Unknown or unregistered payer device ID: " + record.payerDeviceId());
        }
        String computedFingerprint = DeviceAuthorizationRegistry.computeFingerprint(payerPublicKey);
        if (!computedFingerprint.equalsIgnoreCase(allowance.getDevicePublicKeyFingerprint())) {
            throw new IllegalStateException("Payer device public key fingerprint mismatch with allowance binding");
        }

        byte[] spendCanonicalBytes = record.toCanonicalSpendBytes();
        boolean payerSigValid = cryptoService.verifySignatureBase64(spendCanonicalBytes, record.payerSignature(), payerPublicKey);
        if (!payerSigValid) {
            recordSecurityEvent(allowance, record.paymentId(), null, record.sequenceNumber(),
                    "INVALID_PAYER_SIGNATURE",
                    "Payer digital signature verification failed over canonical spend payload");
            throw new GeneralSecurityException("Invalid payer device digital signature for payment: " + record.paymentId());
        }

        // 7. Verify recipient account exists
        String recipientId = record.recipientAccountId().toLowerCase();
        if (!accountRepository.existsById(recipientId)) {
            throw new IllegalArgumentException("Recipient account does not exist: " + record.recipientAccountId());
        }
        if (record.payerAccountId().equalsIgnoreCase(recipientId)) {
            throw new IllegalArgumentException("Payer and recipient accounts must be different");
        }

        // 8. Timestamp validity & Reconciliation Grace Window checks
        Instant now = Instant.now(clock);
        if (record.createdAt().isAfter(now.plus(MAX_FUTURE_CLOCK_SKEW))) {
            throw new IllegalArgumentException("Payment instruction timestamp is in the future beyond allowed clock skew");
        }
        if (allowance.getIssuedAt() != null && record.createdAt().isBefore(allowance.getIssuedAt().minus(MAX_FUTURE_CLOCK_SKEW))) {
            throw new IllegalArgumentException(String.format(
                    "Payment instruction timestamp precedes allowance issuance time (created: %s, issued: %s)",
                    record.createdAt(), allowance.getIssuedAt()
            ));
        }
        if (record.createdAt().isAfter(allowance.getExpiresAt())) {
            throw new IllegalStateException(String.format(
                    "Payment instruction was created after allowance spending deadline (created: %s, expired: %s)",
                    record.createdAt(), allowance.getExpiresAt()
            ));
        }
        Instant gracePeriodDeadline = allowance.getExpiresAt().plus(RECONCILIATION_GRACE_PERIOD);
        if (now.isAfter(gracePeriodDeadline)) {
            throw new IllegalStateException(String.format(
                    "Late payment submission rejected: reconciliation grace period ended at %s (current: %s)",
                    gracePeriodDeadline, now
            ));
        }

        // 9. Sequence & Cumulative Spend Evidence Verification (Conflict & Fork Detection)
        Optional<OfflineSpendPayment> existingSeqOpt = offlineSpendPaymentRepository
                .findByAllowanceIdAndSequenceNumber(allowance.getId(), record.sequenceNumber());
        if (existingSeqOpt.isPresent()) {
            OfflineSpendPayment existingSeq = existingSeqOpt.get();
            // Critical Security Event: Two different payment IDs claiming the same sequence number!
            securityAuditService.recordSecurityEventAndRevokeAllowance(
                    allowance.getId(),
                    record.payerAccountId(),
                    record.payerDeviceId(),
                    record.paymentId(),
                    existingSeq.getPaymentId(),
                    record.sequenceNumber(),
                    "SEQUENCE_FORK_CONFLICT",
                    String.format("Duplicate sequence number %d with conflicting payment ID: existing=%s, incoming=%s. Compromised device or forked state detected. Allowance revoked.",
                            record.sequenceNumber(), existingSeq.getPaymentId(), record.paymentId())
            );
            throw new IllegalStateException(String.format(
                    "Conflicting offline spending history detected at sequence %d! Allowance revoked.",
                    record.sequenceNumber()
            ));
        }

        // Monotonic sequence timestamp verification: spend must not precede previous sequence spend
        if (record.sequenceNumber() > 1) {
            Optional<OfflineSpendPayment> prevSeqOpt = offlineSpendPaymentRepository
                    .findByAllowanceIdAndSequenceNumber(allowance.getId(), record.sequenceNumber() - 1);
            if (prevSeqOpt.isPresent()) {
                OfflineSpendPayment prevSeq = prevSeqOpt.get();
                if (record.createdAt().isBefore(prevSeq.getCreatedAt().minus(MAX_FUTURE_CLOCK_SKEW))) {
                    throw new IllegalArgumentException(String.format(
                            "Payment instruction timestamp (%s) cannot precede previous sequence %d spend timestamp (%s)",
                            record.createdAt(), prevSeq.getSequenceNumber(), prevSeq.getCreatedAt()
                    ));
                }
            }
        }

        // Check sequence progression & cumulative spend arithmetic
        BigDecimal expectedCumulative;
        if (record.sequenceNumber() == 1) {
            expectedCumulative = record.amount();
        } else {
            // If sequence > 1, verify cumulative spend consistency
            expectedCumulative = allowance.getSpentAmount().add(record.amount());
        }
        if (record.cumulativeSpentAmount().compareTo(expectedCumulative) != 0) {
            recordSecurityEvent(
                    allowance,
                    record.paymentId(),
                    null,
                    record.sequenceNumber(),
                    "CUMULATIVE_AMOUNT_MISMATCH",
                    String.format("Cumulative spent amount mismatch: record claims %s, but expected %s (previous spent: %s, amount: %s)",
                            record.cumulativeSpentAmount(), expectedCumulative, allowance.getSpentAmount(), record.amount())
            );
            throw new IllegalArgumentException(String.format(
                    "Cumulative spent amount mismatch: record claims %s, but expected %s",
                    record.cumulativeSpentAmount(), expectedCumulative
            ));
        }

        // Check allowance spending limit (Overspending rejection)
        BigDecimal newTotalSpent = allowance.getSpentAmount().add(record.amount());
        if (newTotalSpent.compareTo(allowance.getAllocatedAmount()) > 0) {
            recordSecurityEvent(
                    allowance,
                    record.paymentId(),
                    null,
                    record.sequenceNumber(),
                    "OVERSPEND_ATTEMPT",
                    String.format("Payment amount %s exceeds remaining allowance limit %s (allocated: %s, already spent: %s)",
                            record.amount(), allowance.getRemainingAmount(), allowance.getAllocatedAmount(), allowance.getSpentAmount())
            );
            throw new IllegalStateException(String.format(
                    "Payment amount %s exceeds remaining allowance limit %s",
                    record.amount(), allowance.getRemainingAmount()
            ));
        }

        // 10. Execute double-entry transfer from system-escrow to recipient
        settlementService.transfer(
                OfflineAllowanceService.ESCROW_ACCOUNT_ID,
                recipientId,
                record.amount()
        );

        // 11. Update Allowance spending metrics and status
        allowance.setSpentAmount(newTotalSpent);
        allowance.setLastSequenceNumber(Math.max(allowance.getLastSequenceNumber(), record.sequenceNumber()));
        if (newTotalSpent.compareTo(allowance.getAllocatedAmount()) == 0) {
            log.info("Allowance {} has been fully exhausted (allocated: {}, spent: {})",
                    allowance.getId(), allowance.getAllocatedAmount(), newTotalSpent);
            allowance.setStatus(OfflineAllowanceStatus.EXHAUSTED);
        }
        offlineAllowanceRepository.saveAndFlush(allowance);

        // 12. Durably record the settled OfflineSpendPayment
        OfflineSpendPayment payment = new OfflineSpendPayment(
                UUID.randomUUID().toString(),
                record.paymentId(),
                record.allowanceId(),
                record.payerAccountId(),
                record.payerDeviceId(),
                recipientId,
                record.amount(),
                record.currency(),
                record.sequenceNumber(),
                record.cumulativeSpentAmount(),
                record.createdAt(),
                now,
                "SETTLED",
                record.voucherSignature(),
                record.payerSignature(),
                record.protocolVersion()
        );

        try {
            return offlineSpendPaymentRepository.saveAndFlush(payment);
        } catch (DataIntegrityViolationException e) {
            throw new DuplicatePacketException("Duplicate payment rejected by database constraint: " + record.paymentId(), e);
        }
    }

    /**
     * Refunds unspent escrow funds back to the allowance owner.
     * <p>
     * Reconciliation Window Policy:
     * To protect offline merchants whose valid payments might still be in transit, escrow funds
     * CANNOT be refunded while within the spending deadline plus reconciliation grace window:
     * {@code now < expiresAt + RECONCILIATION_GRACE_PERIOD}.
     */
    @Transactional
    public OfflineAllowanceRefundResult refundUnusedAllowance(String allowanceId) {
        if (allowanceId == null || allowanceId.isBlank()) {
            throw new IllegalArgumentException("Allowance ID must not be blank");
        }

        OfflineAllowance allowance = offlineAllowanceRepository.findById(allowanceId.trim())
                .orElseThrow(() -> new IllegalArgumentException("No allowance found with ID: " + allowanceId));

        if (allowance.getStatus() == OfflineAllowanceStatus.EXHAUSTED) {
            return new OfflineAllowanceRefundResult(
                    true,
                    allowance.getId(),
                    allowance.getAccountId(),
                    BigDecimal.ZERO,
                    allowance.getAllocatedAmount(),
                    allowance.getSpentAmount(),
                    OfflineAllowanceStatus.EXHAUSTED,
                    Instant.now(clock),
                    "Allowance has already been fully spent; no escrow funds remain to refund"
            );
        }

        if (allowance.getStatus() == OfflineAllowanceStatus.REDEEMED) {
            return new OfflineAllowanceRefundResult(
                    true,
                    allowance.getId(),
                    allowance.getAccountId(),
                    BigDecimal.ZERO,
                    allowance.getAllocatedAmount(),
                    allowance.getSpentAmount(),
                    OfflineAllowanceStatus.REDEEMED,
                    Instant.now(clock),
                    "Allowance has already been redeemed and closed"
            );
        }

        Instant now = Instant.now(clock);
        Instant graceDeadline = allowance.getExpiresAt().plus(RECONCILIATION_GRACE_PERIOD);

        // Enforce merchant protection window
        if (now.isBefore(graceDeadline) && allowance.getStatus() != OfflineAllowanceStatus.REVOKED) {
            throw new IllegalStateException(String.format(
                    "Cannot release escrow funds during active reconciliation grace window. " +
                            "Offline payments may still be in transit until %s (current time: %s)",
                    graceDeadline, now
            ));
        }

        BigDecimal remainingEscrow = allowance.getRemainingAmount();
        if (remainingEscrow.compareTo(BigDecimal.ZERO) > 0) {
            // Transfer remaining funds from system-escrow back to the payer account
            settlementService.transfer(
                    OfflineAllowanceService.ESCROW_ACCOUNT_ID,
                    allowance.getAccountId(),
                    remainingEscrow
            );
            log.info("Refunded {} unspent escrow from allowance {} to account {}",
                    remainingEscrow, allowance.getId(), allowance.getAccountId());
        }

        allowance.setStatus(OfflineAllowanceStatus.REDEEMED);
        offlineAllowanceRepository.saveAndFlush(allowance);

        return new OfflineAllowanceRefundResult(
                true,
                allowance.getId(),
                allowance.getAccountId(),
                remainingEscrow,
                allowance.getAllocatedAmount(),
                allowance.getSpentAmount(),
                OfflineAllowanceStatus.REDEEMED,
                now,
                "Unused allowance funds successfully refunded to account " + allowance.getAccountId()
        );
    }

    private void recordSecurityEvent(
            OfflineAllowance allowance,
            String incomingPaymentId,
            String existingPaymentId,
            Integer sequenceNumber,
            String eventType,
            String details
    ) {
        if (securityAuditService != null) {
            securityAuditService.recordSecurityEvent(
                    allowance.getId(),
                    allowance.getAccountId(),
                    allowance.getDeviceId(),
                    incomingPaymentId,
                    existingPaymentId,
                    sequenceNumber,
                    eventType,
                    details
            );
        }
    }

    private void validateSpendRecordFields(OfflineSpendRecord record) {
        if (record.allowanceId() == null || record.allowanceId().isBlank()) {
            throw new IllegalArgumentException("allowanceId must not be blank");
        }
        if (record.paymentId() == null || record.paymentId().isBlank()) {
            throw new IllegalArgumentException("paymentId must not be blank");
        }
        if (record.payerAccountId() == null || record.payerAccountId().isBlank()) {
            throw new IllegalArgumentException("payerAccountId must not be blank");
        }
        if (record.payerDeviceId() == null || record.payerDeviceId().isBlank()) {
            throw new IllegalArgumentException("payerDeviceId must not be blank");
        }
        if (record.recipientAccountId() == null || record.recipientAccountId().isBlank()) {
            throw new IllegalArgumentException("recipientAccountId must not be blank");
        }
        if (record.amount() == null || record.amount().compareTo(BigDecimal.ZERO) <= 0) {
            throw new IllegalArgumentException("Spend amount must be strictly greater than zero");
        }
        if (record.amount().scale() > 2) {
            throw new IllegalArgumentException("Spend amount cannot have more than 2 decimal places");
        }
        if (!"INR".equalsIgnoreCase(record.currency())) {
            throw new IllegalArgumentException("Unsupported currency: " + record.currency() + "; only INR is supported");
        }
        if (record.sequenceNumber() < 1) {
            throw new IllegalArgumentException("sequenceNumber must be at least 1");
        }
        if (record.cumulativeSpentAmount() == null || record.cumulativeSpentAmount().compareTo(BigDecimal.ZERO) <= 0) {
            throw new IllegalArgumentException("cumulativeSpentAmount must be greater than zero");
        }
        if (record.createdAt() == null) {
            throw new IllegalArgumentException("createdAt timestamp must not be null");
        }
        if (record.voucherSignature() == null || record.voucherSignature().isBlank()) {
            throw new IllegalArgumentException("voucherSignature must not be blank");
        }
        if (record.payerSignature() == null || record.payerSignature().isBlank()) {
            throw new IllegalArgumentException("payerSignature must not be blank");
        }
    }

    @Transactional(readOnly = true)
    public List<OfflineSpendPayment> getSpendHistory(String allowanceId) {
        if (allowanceId == null || allowanceId.isBlank()) {
            return List.of();
        }
        return offlineSpendPaymentRepository.findByAllowanceIdOrderBySequenceNumberAsc(allowanceId.trim());
    }

    @Transactional(readOnly = true)
    public List<OfflineSecurityEvent> getSecurityEvents(String allowanceId) {
        if (allowanceId == null || allowanceId.isBlank()) {
            return List.of();
        }
        return offlineSecurityEventRepository.findByAllowanceIdOrderByDetectedAtDesc(allowanceId.trim());
    }
}
