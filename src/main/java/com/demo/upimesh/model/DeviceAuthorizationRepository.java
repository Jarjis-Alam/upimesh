package com.demo.upimesh.model;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

/**
 * Spring Data JPA repository for persisted device-to-account debit authorization bindings.
 */
public interface DeviceAuthorizationRepository extends JpaRepository<DeviceAccountAuthorization, String> {
    boolean existsByDeviceIdAndAccountId(String deviceId, String accountId);
    Optional<DeviceAccountAuthorization> findByDeviceIdAndAccountId(String deviceId, String accountId);
    List<DeviceAccountAuthorization> findByDeviceId(String deviceId);
    List<DeviceAccountAuthorization> findByAccountId(String accountId);
    void deleteByDeviceIdAndAccountId(String deviceId, String accountId);
}
