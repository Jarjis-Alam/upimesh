package com.demo.upimesh.model;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface ConsumedConsentRepository extends JpaRepository<ConsumedConsent, String> {
}
