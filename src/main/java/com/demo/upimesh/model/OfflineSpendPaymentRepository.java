package com.demo.upimesh.model;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface OfflineSpendPaymentRepository extends JpaRepository<OfflineSpendPayment, String> {

    Optional<OfflineSpendPayment> findByPaymentId(String paymentId);

    boolean existsByPaymentId(String paymentId);

    Optional<OfflineSpendPayment> findByAllowanceIdAndSequenceNumber(String allowanceId, int sequenceNumber);

    List<OfflineSpendPayment> findByAllowanceIdOrderBySequenceNumberAsc(String allowanceId);

    Optional<OfflineSpendPayment> findTopByAllowanceIdOrderBySequenceNumberDesc(String allowanceId);

    List<OfflineSpendPayment> findByPayerAccountIdOrderBySettledAtDesc(String payerAccountId);

    List<OfflineSpendPayment> findByRecipientAccountIdOrderBySettledAtDesc(String recipientAccountId);
}
