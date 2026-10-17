package com.demo.upimesh.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.Instant;
import java.util.Objects;

/**
 * JPA entity recording security events, fraud attempts, sequence forks, and integrity violations
 * detected during offline allowance reconciliation.
 */
@Entity
@Table(name = "offline_security_events")
public class OfflineSecurityEvent {

    @Id
    @Column(name = "id", nullable = false, length = 64)
    private String id;

    @Column(name = "allowance_id", nullable = false, length = 64)
    private String allowanceId;

    @Column(name = "payer_account_id", nullable = false, length = 64)
    private String payerAccountId;

    @Column(name = "payer_device_id", nullable = false, length = 128)
    private String payerDeviceId;

    @Column(name = "conflicting_payment_id", length = 64)
    private String conflictingPaymentId;

    @Column(name = "existing_payment_id", length = 64)
    private String existingPaymentId;

    @Column(name = "sequence_number")
    private Integer sequenceNumber;

    @Column(name = "event_type", nullable = false, length = 64)
    private String eventType;

    @Column(name = "details", nullable = false, columnDefinition = "TEXT")
    private String details;

    @Column(name = "detected_at", nullable = false)
    private Instant detectedAt;

    public OfflineSecurityEvent() {
    }

    public OfflineSecurityEvent(
            String id,
            String allowanceId,
            String payerAccountId,
            String payerDeviceId,
            String conflictingPaymentId,
            String existingPaymentId,
            Integer sequenceNumber,
            String eventType,
            String details,
            Instant detectedAt
    ) {
        this.id = id;
        this.allowanceId = allowanceId;
        this.payerAccountId = payerAccountId != null ? payerAccountId.trim().toLowerCase() : "";
        this.payerDeviceId = payerDeviceId != null ? payerDeviceId.trim() : "";
        this.conflictingPaymentId = conflictingPaymentId;
        this.existingPaymentId = existingPaymentId;
        this.sequenceNumber = sequenceNumber;
        this.eventType = eventType;
        this.details = details != null ? details : "";
        this.detectedAt = detectedAt != null ? detectedAt : Instant.now();
    }

    public String getId() {
        return id;
    }

    public String getAllowanceId() {
        return allowanceId;
    }

    public String getPayerAccountId() {
        return payerAccountId;
    }

    public String getPayerDeviceId() {
        return payerDeviceId;
    }

    public String getConflictingPaymentId() {
        return conflictingPaymentId;
    }

    public String getExistingPaymentId() {
        return existingPaymentId;
    }

    public Integer getSequenceNumber() {
        return sequenceNumber;
    }

    public String getEventType() {
        return eventType;
    }

    public String getDetails() {
        return details;
    }

    public Instant getDetectedAt() {
        return detectedAt;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof OfflineSecurityEvent that)) return false;
        return Objects.equals(id, that.id);
    }

    @Override
    public int hashCode() {
        return Objects.hashCode(id);
    }
}
