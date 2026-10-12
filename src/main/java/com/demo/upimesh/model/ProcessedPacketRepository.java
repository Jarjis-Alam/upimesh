package com.demo.upimesh.model;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface ProcessedPacketRepository extends JpaRepository<ProcessedPacket, String> {

    Optional<ProcessedPacket> findByPacketHash(String packetHash);

    boolean existsByPacketHash(String packetHash);

    Optional<ProcessedPacket> findByPaymentId(String paymentId);

    boolean existsByPaymentId(String paymentId);

    Optional<ProcessedPacket> findByFromAccountAndNonce(String fromAccount, String nonce);

    boolean existsByFromAccountAndNonce(String fromAccount, String nonce);
}
