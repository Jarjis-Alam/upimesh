package com.demo.upimesh.model;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

/**
 * Spring Data JPA repository for persisted device-to-account debit authorization bindings.
 */
public interface DeviceAuthorizationRepository extends JpaRepository<DeviceAccountAuthorization, String> {
    boolean existsByDeviceIdAndAccountId(String deviceId, String accountId);
    List<DeviceAccountAuthorization> findByDeviceId(String deviceId);
    void deleteByDeviceIdAndAccountId(String deviceId, String accountId);
}
