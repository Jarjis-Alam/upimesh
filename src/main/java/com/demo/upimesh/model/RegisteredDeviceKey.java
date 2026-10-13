package com.demo.upimesh.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.Instant;
import java.util.Objects;

/**
 * JPA entity representing a durably registered device public signing key.
 * <p>
 * Database-enforced Uniqueness:
 * - Primary key on `id` ensures each device UUID or account ID possesses at most one registered key.
 * - Anti-replacement policy forbids overwriting an existing registered key with a different key.
 */
@Entity
@Table(name = "registered_device_keys")
public class RegisteredDeviceKey {

    @Id
    @Column(name = "id", nullable = false, length = 128)
    private String id; // Normalized lowercase device UUID or account identifier

    @Column(name = "public_key_base64", nullable = false, length = 1024)
    private String publicKeyBase64; // X.509 SubjectPublicKeyInfo Base64

    @Column(name = "algorithm", nullable = false, length = 32)
    private String algorithm; // "RSA"

    @Column(name = "registered_at", nullable = false)
    private Instant registeredAt;

    public RegisteredDeviceKey() {
    }

    public RegisteredDeviceKey(String id, String publicKeyBase64, String algorithm, Instant registeredAt) {
        if (id == null || id.isBlank()) {
            throw new IllegalArgumentException("id must not be blank");
        }
        if (publicKeyBase64 == null || publicKeyBase64.isBlank()) {
            throw new IllegalArgumentException("publicKeyBase64 must not be blank");
        }
        if (algorithm == null || algorithm.isBlank()) {
            throw new IllegalArgumentException("algorithm must not be blank");
        }
        if (registeredAt == null) {
            throw new IllegalArgumentException("registeredAt must not be null");
        }
        this.id = id.trim().toLowerCase();
        this.publicKeyBase64 = publicKeyBase64.trim();
        this.algorithm = algorithm.trim();
        this.registeredAt = registeredAt;
    }

    public String getId() {
        return id;
    }

    public String getPublicKeyBase64() {
        return publicKeyBase64;
    }

    public String getAlgorithm() {
        return algorithm;
    }

    public Instant getRegisteredAt() {
        return registeredAt;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        RegisteredDeviceKey that = (RegisteredDeviceKey) o;
        return Objects.equals(id, that.id);
    }

    @Override
    public int hashCode() {
        return Objects.hash(id);
    }
}
