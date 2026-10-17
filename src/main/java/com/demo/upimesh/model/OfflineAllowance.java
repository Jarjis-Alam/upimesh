package com.demo.upimesh.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import jakarta.persistence.Version;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Objects;

/**
 * Entity representing an authoritative pre-allocated offline spending allowance.
 * <p>
 * Database-level concurrency protection:
 * The column {@code active_account_id} has a unique constraint.
 * When the allowance is {@link OfflineAllowanceStatus#ACTIVE}, {@code active_account_id}
 * is set to the lowercased {@code account_id}. When the allowance transitions to any non-active
 * status (REVOKED, EXPIRED, EXHAUSTED, REDEEMED), {@code active_account_id} is cleared to {@code null}.
 * Because SQL unique constraints permit multiple {@code NULL} entries across all standard SQL databases
 * (H2, PostgreSQL, MySQL, Oracle), this portably enforces that at most ONE active allowance can exist
 * per account concurrently without requiring dialect-specific partial index syntax.
 */
@Entity
@Table(name = "offline_allowances", uniqueConstraints = {
        @UniqueConstraint(name = "uk_active_allowance_per_account", columnNames = {"active_account_id"})
})
public class OfflineAllowance {

    public static final String CANONICAL_HEADER = "UPI-MESH-ALLOWANCE-V1";
    public static final int CURRENT_PROTOCOL_VERSION = 1;

    @Id
    @Column(name = "id", nullable = false, length = 64)
    private String id;

    @Column(name = "account_id", nullable = false, length = 64)
    private String accountId;

    @Column(name = "device_id", nullable = false, length = 128)
    private String deviceId;

    @Column(name = "device_public_key_fingerprint", nullable = false, length = 128)
    private String devicePublicKeyFingerprint;

    @Column(name = "currency", nullable = false, length = 12)
    private String currency;

    @Column(name = "allocated_amount", nullable = false, precision = 19, scale = 2)
    private BigDecimal allocatedAmount;

    @Column(name = "spent_amount", nullable = false, precision = 19, scale = 2)
    private BigDecimal spentAmount = BigDecimal.ZERO;

    @Column(name = "last_sequence_number", nullable = false)
    private int lastSequenceNumber = 0;

    @Version
    @Column(name = "version_opt")
    private Long version;

    @Column(name = "issued_at", nullable = false)
    private Instant issuedAt;

    @Column(name = "expires_at", nullable = false)
    private Instant expiresAt;

    @Column(name = "protocol_version", nullable = false)
    private int protocolVersion;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 32)
    private OfflineAllowanceStatus status;

    @Column(name = "voucher_signature", nullable = false, columnDefinition = "TEXT")
    private String voucherSignature;

    /**
     * Portable single-active-allowance constraint column.
     * Contains accountId when ACTIVE; NULL when not ACTIVE.
     */
    @Column(name = "active_account_id", unique = true, nullable = true, length = 64)
    private String activeAccountId;

    public OfflineAllowance() {
    }

    public OfflineAllowance(
            String id,
            String accountId,
            String deviceId,
            String devicePublicKeyFingerprint,
            String currency,
            BigDecimal allocatedAmount,
            Instant issuedAt,
            Instant expiresAt,
            int protocolVersion,
            OfflineAllowanceStatus status,
            String voucherSignature
    ) {
        if (id == null || id.isBlank()) {
            throw new IllegalArgumentException("Allowance ID must not be blank");
        }
        if (accountId == null || accountId.isBlank()) {
            throw new IllegalArgumentException("Account ID must not be blank");
        }
        if (deviceId == null || deviceId.isBlank()) {
            throw new IllegalArgumentException("Device ID must not be blank");
        }
        if (devicePublicKeyFingerprint == null || devicePublicKeyFingerprint.isBlank()) {
            throw new IllegalArgumentException("Device public-key fingerprint must not be blank");
        }
        if (currency == null || currency.isBlank()) {
            throw new IllegalArgumentException("Currency must not be blank");
        }
        if (allocatedAmount == null || allocatedAmount.compareTo(BigDecimal.ZERO) <= 0) {
            throw new IllegalArgumentException("Allocated amount must be strictly greater than zero");
        }
        if (issuedAt == null) {
            throw new IllegalArgumentException("IssuedAt timestamp must not be null");
        }
        if (expiresAt == null) {
            throw new IllegalArgumentException("ExpiresAt timestamp must not be null");
        }
        if (!expiresAt.isAfter(issuedAt)) {
            throw new IllegalArgumentException("ExpiresAt must be after issuedAt");
        }
        if (status == null) {
            throw new IllegalArgumentException("Status must not be null");
        }

        this.id = id.trim();
        this.accountId = accountId.trim().toLowerCase();
        this.deviceId = deviceId.trim();
        this.devicePublicKeyFingerprint = devicePublicKeyFingerprint.trim().toLowerCase();
        this.currency = currency.trim().toUpperCase();
        this.allocatedAmount = allocatedAmount;
        this.spentAmount = BigDecimal.ZERO;
        this.lastSequenceNumber = 0;
        this.issuedAt = issuedAt;
        this.expiresAt = expiresAt;
        this.protocolVersion = protocolVersion > 0 ? protocolVersion : CURRENT_PROTOCOL_VERSION;
        this.status = status;
        this.voucherSignature = voucherSignature != null ? voucherSignature.trim() : "";
        this.activeAccountId = (status == OfflineAllowanceStatus.ACTIVE) ? this.accountId : null;
    }

    /**
     * Formats monetary amounts deterministically with 2 decimal places.
     */
    public static String canonicalAmount(BigDecimal amount) {
        if (amount == null) {
            return "0.00";
        }
        if (amount.scale() <= 2) {
            return amount.setScale(2, java.math.RoundingMode.UNNECESSARY).toPlainString();
        }
        return amount.stripTrailingZeros().toPlainString();
    }

    /**
     * Produces deterministic, versioned canonical voucher bytes for cryptographic signing and verification.
     */
    public byte[] toCanonicalVoucherBytes() {
        return buildCanonicalVoucherBytes(
                this.id,
                this.accountId,
                this.deviceId,
                this.devicePublicKeyFingerprint,
                this.currency,
                this.allocatedAmount,
                this.issuedAt,
                this.expiresAt,
                this.protocolVersion
        );
    }

    /**
     * Static helper to build canonical voucher bytes from raw values prior to entity construction.
     */
    public static byte[] buildCanonicalVoucherBytes(
            String id,
            String accountId,
            String deviceId,
            String deviceFingerprint,
            String currency,
            BigDecimal allocatedAmount,
            Instant issuedAt,
            Instant expiresAt,
            int protocolVersion
    ) {
        String cleanId = id != null ? id.trim() : "";
        String cleanAcc = accountId != null ? accountId.trim().toLowerCase() : "";
        String cleanDev = deviceId != null ? deviceId.trim() : "";
        String cleanFp = deviceFingerprint != null ? deviceFingerprint.trim().toLowerCase() : "";
        String cleanCurr = currency != null ? currency.trim().toUpperCase() : "";
        String amtStr = canonicalAmount(allocatedAmount);
        String issStr = issuedAt != null ? issuedAt.toString() : "";
        String expStr = expiresAt != null ? expiresAt.toString() : "";
        int version = protocolVersion > 0 ? protocolVersion : CURRENT_PROTOCOL_VERSION;

        StringBuilder sb = new StringBuilder();
        sb.append(CANONICAL_HEADER).append("\n");
        sb.append("allowanceId:").append(cleanId.length()).append(":").append(cleanId).append("\n");
        sb.append("accountId:").append(cleanAcc.length()).append(":").append(cleanAcc).append("\n");
        sb.append("deviceId:").append(cleanDev.length()).append(":").append(cleanDev).append("\n");
        sb.append("deviceFingerprint:").append(cleanFp.length()).append(":").append(cleanFp).append("\n");
        sb.append("currency:").append(cleanCurr.length()).append(":").append(cleanCurr).append("\n");
        sb.append("allocatedAmount:").append(amtStr.length()).append(":").append(amtStr).append("\n");
        sb.append("issuedAt:").append(issStr.length()).append(":").append(issStr).append("\n");
        sb.append("expiresAt:").append(expStr.length()).append(":").append(expStr).append("\n");
        sb.append("version:").append(String.valueOf(version).length()).append(":").append(version).append("\n");

        return sb.toString().getBytes(StandardCharsets.UTF_8);
    }

    public void setVoucherSignature(String voucherSignature) {
        this.voucherSignature = voucherSignature != null ? voucherSignature.trim() : "";
    }

    public void setStatus(OfflineAllowanceStatus newStatus) {
        this.status = newStatus;
        this.activeAccountId = (newStatus == OfflineAllowanceStatus.ACTIVE) ? this.accountId : null;
    }

    public void setExpiresAt(Instant expiresAt) {
        this.expiresAt = expiresAt;
    }

    public String getId() {
        return id;
    }

    public String getAccountId() {
        return accountId;
    }

    public String getDeviceId() {
        return deviceId;
    }

    public String getDevicePublicKeyFingerprint() {
        return devicePublicKeyFingerprint;
    }

    public String getCurrency() {
        return currency;
    }

    public BigDecimal getAllocatedAmount() {
        return allocatedAmount;
    }

    public Instant getIssuedAt() {
        return issuedAt;
    }

    public Instant getExpiresAt() {
        return expiresAt;
    }

    public int getProtocolVersion() {
        return protocolVersion;
    }

    public OfflineAllowanceStatus getStatus() {
        return status;
    }

    public String getVoucherSignature() {
        return voucherSignature;
    }

    public String getActiveAccountId() {
        return activeAccountId;
    }

    public BigDecimal getSpentAmount() {
        return spentAmount != null ? spentAmount : BigDecimal.ZERO;
    }

    public void setSpentAmount(BigDecimal spentAmount) {
        this.spentAmount = spentAmount != null ? spentAmount : BigDecimal.ZERO;
    }

    public int getLastSequenceNumber() {
        return lastSequenceNumber;
    }

    public void setLastSequenceNumber(int lastSequenceNumber) {
        this.lastSequenceNumber = lastSequenceNumber;
    }

    public BigDecimal getRemainingAmount() {
        BigDecimal total = allocatedAmount != null ? allocatedAmount : BigDecimal.ZERO;
        BigDecimal spent = spentAmount != null ? spentAmount : BigDecimal.ZERO;
        return total.subtract(spent);
    }

    public Long getVersion() {
        return version;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof OfflineAllowance that)) return false;
        return Objects.equals(id, that.id);
    }

    @Override
    public int hashCode() {
        return Objects.hashCode(id);
    }
}
