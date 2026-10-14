package com.demo.upimesh.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;

/**
 * JPA entity representing a consumed account-owner consent token to prevent replay attacks.
 */
@Entity
@Table(name = "consumed_consents")
public class ConsumedConsent {

    @Id
    @Column(name = "consent_id", nullable = false, length = 64)
    private String consentId;

    @Column(name = "account_id", nullable = false, length = 64)
    private String accountId;

    @Column(name = "device_id", nullable = false, length = 128)
    private String deviceId;

    @Column(name = "consumed_at", nullable = false)
    private Instant consumedAt;

    public ConsumedConsent() {
    }

    public ConsumedConsent(String consentId, String accountId, String deviceId, Instant consumedAt) {
        this.consentId = consentId;
        this.accountId = accountId;
        this.deviceId = deviceId;
        this.consumedAt = consumedAt;
    }

    public String getConsentId() {
        return consentId;
    }

    public void setConsentId(String consentId) {
        this.consentId = consentId;
    }

    public String getAccountId() {
        return accountId;
    }

    public void setAccountId(String accountId) {
        this.accountId = accountId;
    }

    public String getDeviceId() {
        return deviceId;
    }

    public void setDeviceId(String deviceId) {
        this.deviceId = deviceId;
    }

    public Instant getConsumedAt() {
        return consumedAt;
    }

    public void setConsumedAt(Instant consumedAt) {
        this.consumedAt = consumedAt;
    }
}
