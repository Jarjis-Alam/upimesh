package com.demo.upimesh;

import com.demo.upimesh.model.OfflineAllowance;
import com.demo.upimesh.model.OfflineAllowanceRepository;
import com.demo.upimesh.model.OfflineAllowanceStatus;
import com.demo.upimesh.model.OfflineSecurityEvent;
import com.demo.upimesh.model.OfflineSecurityEventRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.UUID;

/**
 * Service managing durable security audit logging and allowance revocation in an isolated
 * autonomous transaction (REQUIRES_NEW). Ensures fraud events and account freeze actions
 * survive transaction rollbacks of rejected payments.
 */
@Service
public class OfflineSecurityAuditService {

    private static final Logger log = LoggerFactory.getLogger(OfflineSecurityAuditService.class);

    private final OfflineSecurityEventRepository securityEventRepository;
    private final OfflineAllowanceRepository allowanceRepository;

    @Autowired
    public OfflineSecurityAuditService(
            OfflineSecurityEventRepository securityEventRepository,
            OfflineAllowanceRepository allowanceRepository
    ) {
        this.securityEventRepository = securityEventRepository;
        this.allowanceRepository = allowanceRepository;
    }

    /**
     * Persists a security audit event in an independent transaction that commits even if the outer
     * payment settlement rolls back.
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void recordSecurityEvent(
            String allowanceId,
            String payerAccountId,
            String payerDeviceId,
            String incomingPaymentId,
            String existingPaymentId,
            Integer sequenceNumber,
            String eventType,
            String details
    ) {
        log.warn("SECURITY ALERT [{}] for allowance {}: {}", eventType, allowanceId, details);
        try {
            OfflineSecurityEvent event = new OfflineSecurityEvent(
                    UUID.randomUUID().toString(),
                    allowanceId,
                    payerAccountId,
                    payerDeviceId,
                    incomingPaymentId,
                    existingPaymentId,
                    sequenceNumber,
                    eventType,
                    details,
                    Instant.now()
            );
            securityEventRepository.saveAndFlush(event);
        } catch (Exception e) {
            log.error("Failed to persist security audit event: {}", e.getMessage(), e);
        }
    }

    /**
     * Persists a security audit event and immediately revokes the allowance in an independent transaction.
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void recordSecurityEventAndRevokeAllowance(
            String allowanceId,
            String payerAccountId,
            String payerDeviceId,
            String incomingPaymentId,
            String existingPaymentId,
            Integer sequenceNumber,
            String eventType,
            String details
    ) {
        recordSecurityEvent(allowanceId, payerAccountId, payerDeviceId, incomingPaymentId, existingPaymentId, sequenceNumber, eventType, details);
        try {
            if (allowanceId != null && !allowanceId.isBlank()) {
                allowanceRepository.findById(allowanceId.trim()).ifPresent(allowance -> {
                    allowance.setStatus(OfflineAllowanceStatus.REVOKED);
                    allowanceRepository.saveAndFlush(allowance);
                    log.warn("Revoked allowance {} due to security violation: {}", allowanceId, eventType);
                });
            }
        } catch (Exception e) {
            log.error("Failed to revoke allowance {} during security event: {}", allowanceId, e.getMessage(), e);
        }
    }
}
