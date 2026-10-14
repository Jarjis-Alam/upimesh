package com.demo.upimesh.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Objects;

/**
 * JPA entity representing a durably persisted device-to-account debit authorization binding.
 * <p>
 * Under Stage 8 (Account-Owner Authorization & Secure Device Pairing):
 * - Binds authorization to accountId, deviceId, registered public-key fingerprint,
 *   spending limit, and expiry timestamp.
 * - Enforces explicit lifecycle status: PENDING, AUTHORIZED, REVOKED, EXPIRED.
 * <p>
 * Database-enforced Uniqueness:
 * - Unique composite constraint `uk_device_account` on (device_id, account_id) prevents
 *   duplicate concurrent authorization bindings.
 */
@Entity
@Table(
        name = "device_authorizations",
        uniqueConstraints = {
                @UniqueConstraint(name = "uk_device_account", columnNames = {"device_id", "account_id"})
        }
)
public class DeviceAccountAuthorization {

    @Id
    @Column(name = "id", nullable = false, length = 36)
    private String id; // UUID surrogate key

    @Column(name = "device_id", nullable = false, length = 128)
    private String deviceId; // Normalized lowercase device UUID

    @Column(name = "account_id", nullable = false, length = 64)
    private String accountId; // Normalized lowercase account identifier (e.g. "alice")

    @Column(name = "authorized_at", nullable = false)
    private Instant authorizedAt;

    @Column(name = "status", length = 32)
    private String status = DeviceAuthorizationStatus.AUTHORIZED.name();

    @Column(name = "key_fingerprint", length = 64)
    private String keyFingerprint; // Lowercase hex of SHA-256(publicKey.getEncoded())

    @Column(name = "spending_limit", precision = 19, scale = 2)
    private BigDecimal spendingLimit; // Maximum allowable amount per debit instruction

    @Column(name = "expires_at")
    private Instant expiresAt; // Authorization validity deadline

    @Column(name = "revoked_at")
    private Instant revokedAt; // Timestamp when authorization was revoked, if applicable

    public DeviceAccountAuthorization() {
    }

    /**
     * Backwards-compatible constructor for existing tests and migrations.
     * Defaults status to AUTHORIZED, spendingLimit to ₹10,000.00, and expiry to 30 days.
     */
    public DeviceAccountAuthorization(String id, String deviceId, String accountId, Instant authorizedAt) {
        this(
                id,
                deviceId,
                accountId,
                authorizedAt,
                DeviceAuthorizationStatus.AUTHORIZED.name(),
                null,
                new BigDecimal("10000.00"),
                authorizedAt != null ? authorizedAt.plus(30, ChronoUnit.DAYS) : Instant.now().plus(30, ChronoUnit.DAYS),
                null
        );
    }

    /**
     * Full constructor for Stage 8 explicit lifecycle authorization bindings.
     */
    public DeviceAccountAuthorization(
            String id,
            String deviceId,
            String accountId,
            Instant authorizedAt,
            String status,
            String keyFingerprint,
            BigDecimal spendingLimit,
            Instant expiresAt,
            Instant revokedAt
    ) {
        if (id == null || id.isBlank()) {
            throw new IllegalArgumentException("id must not be blank");
        }
        if (deviceId == null || deviceId.isBlank()) {
            throw new IllegalArgumentException("deviceId must not be blank");
        }
        if (accountId == null || accountId.isBlank()) {
            throw new IllegalArgumentException("accountId must not be blank");
        }
        if (authorizedAt == null) {
            throw new IllegalArgumentException("authorizedAt must not be null");
        }
        this.id = id;
        this.deviceId = deviceId.trim().toLowerCase();
        this.accountId = accountId.trim().toLowerCase();
        this.authorizedAt = authorizedAt;
        this.status = status != null && !status.isBlank()
                ? status.trim().toUpperCase()
                : DeviceAuthorizationStatus.AUTHORIZED.name();
        this.keyFingerprint = keyFingerprint != null ? keyFingerprint.trim().toLowerCase() : null;
        this.spendingLimit = spendingLimit != null ? spendingLimit : new BigDecimal("10000.00");
        this.expiresAt = expiresAt != null ? expiresAt : authorizedAt.plus(30, ChronoUnit.DAYS);
        this.revokedAt = revokedAt;
    }

    public String getId() {
        return id;
    }

    public String getDeviceId() {
        return deviceId;
    }

    public String getAccountId() {
        return accountId;
    }

    public Instant getAuthorizedAt() {
        return authorizedAt;
    }

    public String getStatus() {
        return status != null ? status : DeviceAuthorizationStatus.AUTHORIZED.name();
    }

    public void setStatus(String status) {
        this.status = status != null ? status.trim().toUpperCase() : DeviceAuthorizationStatus.AUTHORIZED.name();
    }

    public DeviceAuthorizationStatus getStatusEnum() {
        return DeviceAuthorizationStatus.fromString(this.status);
    }

    public String getKeyFingerprint() {
        return keyFingerprint;
    }

    public void setKeyFingerprint(String keyFingerprint) {
        this.keyFingerprint = keyFingerprint != null ? keyFingerprint.trim().toLowerCase() : null;
    }

    public BigDecimal getSpendingLimit() {
        return spendingLimit != null ? spendingLimit : new BigDecimal("10000.00");
    }

    public void setSpendingLimit(BigDecimal spendingLimit) {
        this.spendingLimit = spendingLimit;
    }

    public Instant getExpiresAt() {
        return expiresAt != null ? expiresAt : (authorizedAt != null ? authorizedAt.plus(30, ChronoUnit.DAYS) : Instant.now().plus(30, ChronoUnit.DAYS));
    }

    public void setExpiresAt(Instant expiresAt) {
        this.expiresAt = expiresAt;
    }

    public Instant getRevokedAt() {
        return revokedAt;
    }

    public void setRevokedAt(Instant revokedAt) {
        this.revokedAt = revokedAt;
    }

    public boolean isExpired(Instant now) {
        return expiresAt != null && now.isAfter(expiresAt);
    }

    public boolean isActive(Instant now) {
        return DeviceAuthorizationStatus.AUTHORIZED.name().equalsIgnoreCase(status) && !isExpired(now);
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        DeviceAccountAuthorization that = (DeviceAccountAuthorization) o;
        return Objects.equals(deviceId, that.deviceId) && Objects.equals(accountId, that.accountId);
    }

    @Override
    public int hashCode() {
        return Objects.hash(deviceId, accountId);
    }
}
