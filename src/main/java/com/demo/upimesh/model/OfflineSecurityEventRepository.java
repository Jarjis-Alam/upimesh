package com.demo.upimesh.model;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface OfflineSecurityEventRepository extends JpaRepository<OfflineSecurityEvent, String> {

    List<OfflineSecurityEvent> findByAllowanceIdOrderByDetectedAtDesc(String allowanceId);

    List<OfflineSecurityEvent> findByPayerAccountIdOrderByDetectedAtDesc(String payerAccountId);

    boolean existsByAllowanceIdAndEventType(String allowanceId, String eventType);
}
