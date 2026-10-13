package com.demo.upimesh.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

import java.time.Instant;
import java.util.Objects;

/**
 * JPA entity representing a durably persisted device-to-account debit authorization binding.
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

    public DeviceAccountAuthorization() {
    }

    public DeviceAccountAuthorization(String id, String deviceId, String accountId, Instant authorizedAt) {
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
