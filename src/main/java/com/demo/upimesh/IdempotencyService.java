package com.demo.upimesh;

import com.demo.upimesh.model.ProcessedPacketRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.nio.ByteBuffer;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Service managing packet deduplication and idempotency claims.
 * <p>
 * Architecture & Concurrency:
 * 1. Deduplication key is the deterministic SHA-256 hash of the complete encrypted packet
 *    (length-prefixed encrypted AES key, IV, and ciphertext).
 * 2. In-memory claims via ConcurrentHashMap provide rapid pre-filtering for concurrent in-flight
 *    duplicate requests.
 * 3. Durable persistence via ProcessedPacketRepository ensures duplicate rejection across
 *    application restarts and service re-instantiation.
 */
@Service
public class IdempotencyService {

    public enum ClaimStatus {
        PROCESSING,
        SETTLED
    }

    private final ProcessedPacketRepository processedPacketRepository;
    private final ConcurrentHashMap<String, ClaimStatus> claims = new ConcurrentHashMap<>();

    @Autowired
    public IdempotencyService(ProcessedPacketRepository processedPacketRepository) {
        this.processedPacketRepository = processedPacketRepository;
    }

    public IdempotencyService() {
        this(null);
    }

    /**
     * Computes a deterministic SHA-256 hash of an EncryptedPacket.
     * Uses length-prefixing on all byte arrays to prevent boundary ambiguity.
     */
    public String computeHash(EncryptedPacket packet) {
        if (packet == null) {
            throw new IllegalArgumentException("EncryptedPacket must not be null");
        }
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] keyBytes = packet.encryptedAesKey();
            byte[] ivBytes = packet.iv();
            byte[] cipherBytes = packet.ciphertext();

            digest.update(ByteBuffer.allocate(4).putInt(keyBytes.length).array());
            digest.update(keyBytes);
            digest.update(ByteBuffer.allocate(4).putInt(ivBytes.length).array());
            digest.update(ivBytes);
            digest.update(ByteBuffer.allocate(4).putInt(cipherBytes.length).array());
            digest.update(cipherBytes);

            return HexFormat.of().formatHex(digest.digest());
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 algorithm not available", e);
        }
    }

    /**
     * Atomically attempts to claim a packet hash for processing.
     *
     * @param packetHash canonical SHA-256 hash of the encrypted packet
     * @return true if successfully claimed (was absent and not settled); false if already processing or settled
     */
    public boolean tryClaim(String packetHash) {
        if (packetHash == null || packetHash.isBlank()) {
            throw new IllegalArgumentException("packetHash must not be blank");
        }
        if (isSettled(packetHash)) {
            return false;
        }
        ClaimStatus existing = claims.putIfAbsent(packetHash, ClaimStatus.PROCESSING);
        return existing == null;
    }

    /**
     * Marks a previously claimed packet as settled in memory.
     */
    public void markSettled(String packetHash) {
        if (packetHash == null || packetHash.isBlank()) {
            throw new IllegalArgumentException("packetHash must not be blank");
        }
        claims.put(packetHash, ClaimStatus.SETTLED);
    }

    /**
     * Releases an in-flight claim if processing failed before settlement,
     * allowing subsequent retry attempts.
     */
    public void releaseClaim(String packetHash) {
        if (packetHash != null) {
            claims.remove(packetHash, ClaimStatus.PROCESSING);
        }
    }

    /**
     * Checks if a packet hash has been successfully settled, checking both
     * the in-memory claims map and persistent storage.
     */
    public boolean isSettled(String packetHash) {
        if (packetHash == null) {
            return false;
        }
        if (claims.get(packetHash) == ClaimStatus.SETTLED) {
            return true;
        }
        if (processedPacketRepository != null && processedPacketRepository.existsByPacketHash(packetHash)) {
            return true;
        }
        return false;
    }

    /**
     * Clears all in-memory claims (primarily for testing).
     */
    public void clear() {
        claims.clear();
    }
}
