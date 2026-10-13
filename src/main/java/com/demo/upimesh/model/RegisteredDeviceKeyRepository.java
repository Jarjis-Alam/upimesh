package com.demo.upimesh.model;

import org.springframework.data.jpa.repository.JpaRepository;

/**
 * Spring Data JPA repository for persisted device public keys.
 */
public interface RegisteredDeviceKeyRepository extends JpaRepository<RegisteredDeviceKey, String> {
}
