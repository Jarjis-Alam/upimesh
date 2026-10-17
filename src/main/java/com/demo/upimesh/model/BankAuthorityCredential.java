package com.demo.upimesh.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.Instant;
import java.util.Objects;

/**
 * JPA entity storing the persistent cryptographic keypair of the central Bank Authority.
 * Enables the Bank Authority key to survive server restarts so issued offline vouchers
 * remain verifiable across deployments.
 */
@Entity
@Table(name = "bank_authority_credentials")
public class BankAuthorityCredential {

    @Id
    @Column(name = "id", nullable = false, length = 64)
    private String id;

    @Column(name = "public_key_base64", nullable = false, columnDefinition = "TEXT")
    private String publicKeyBase64;

    @Column(name = "private_key_base64", nullable = false, columnDefinition = "TEXT")
    private String privateKeyBase64;

    @Column(name = "algorithm", nullable = false, length = 32)
    private String algorithm;

    @Column(name = "key_size", nullable = false)
    private int keySize;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    public BankAuthorityCredential() {
    }

    public BankAuthorityCredential(
            String id,
            String publicKeyBase64,
            String privateKeyBase64,
            String algorithm,
            int keySize,
            Instant createdAt
    ) {
        if (id == null || id.isBlank()) {
            throw new IllegalArgumentException("Credential ID must not be blank");
        }
        if (publicKeyBase64 == null || publicKeyBase64.isBlank()) {
            throw new IllegalArgumentException("Public key must not be blank");
        }
        if (privateKeyBase64 == null || privateKeyBase64.isBlank()) {
            throw new IllegalArgumentException("Private key must not be blank");
        }
        this.id = id.trim();
        this.publicKeyBase64 = publicKeyBase64.trim();
        this.privateKeyBase64 = privateKeyBase64.trim();
        this.algorithm = algorithm != null ? algorithm.trim() : "RSA";
        this.keySize = keySize > 0 ? keySize : 2048;
        this.createdAt = createdAt != null ? createdAt : Instant.now();
    }

    public String getId() {
        return id;
    }

    public String getPublicKeyBase64() {
        return publicKeyBase64;
    }

    public String getPrivateKeyBase64() {
        return privateKeyBase64;
    }

    public String getAlgorithm() {
        return algorithm;
    }

    public int getKeySize() {
        return keySize;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof BankAuthorityCredential that)) return false;
        return Objects.equals(id, that.id);
    }

    @Override
    public int hashCode() {
        return Objects.hashCode(id);
    }
}
