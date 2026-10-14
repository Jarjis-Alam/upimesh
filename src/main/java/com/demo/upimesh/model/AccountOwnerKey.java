package com.demo.upimesh.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;

/**
 * JPA entity representing a durably persisted Account Owner public verification key.
 */
@Entity
@Table(name = "account_owner_keys")
public class AccountOwnerKey {

    @Id
    @Column(name = "account_id", nullable = false, length = 64)
    private String accountId;

    @Column(name = "public_key_base64", nullable = false, length = 1024)
    private String publicKeyBase64;

    @Column(name = "algorithm", nullable = false, length = 32)
    private String algorithm = "RSA";

    @Column(name = "registered_at", nullable = false)
    private Instant registeredAt;

    public AccountOwnerKey() {
    }

    public AccountOwnerKey(String accountId, String publicKeyBase64, String algorithm, Instant registeredAt) {
        this.accountId = accountId;
        this.publicKeyBase64 = publicKeyBase64;
        this.algorithm = algorithm;
        this.registeredAt = registeredAt;
    }

    public String getAccountId() {
        return accountId;
    }

    public void setAccountId(String accountId) {
        this.accountId = accountId;
    }

    public String getPublicKeyBase64() {
        return publicKeyBase64;
    }

    public void setPublicKeyBase64(String publicKeyBase64) {
        this.publicKeyBase64 = publicKeyBase64;
    }

    public String getAlgorithm() {
        return algorithm;
    }

    public void setAlgorithm(String algorithm) {
        this.algorithm = algorithm;
    }

    public Instant getRegisteredAt() {
        return registeredAt;
    }

    public void setRegisteredAt(Instant registeredAt) {
        this.registeredAt = registeredAt;
    }
}
