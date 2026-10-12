package com.demo.upimesh.model;

import java.math.BigDecimal;
import java.util.List;

/**
 * Result model capturing the end-to-end outcome of a simulated mesh payment.
 * <p>
 * Demonstrates the 4-stage pipeline:
 * 1. Sender: Payment instruction creation and hybrid encryption (RSA-OAEP + AES-256-GCM).
 * 2. Virtual Mesh: Multi-hop forwarding, loop suppression, and TTL decrement across virtual devices.
 * 3. Bridge Ingestion: Canonical SHA-256 deduplication and hybrid payload decryption.
 * 4. Settlement: Atomic balance adjustments and persistent transaction ledger insertion.
 */
public record MeshPaymentResult(
        boolean success,
        String paymentId,
        String packetId,
        String fromAccount,
        String toAccount,
        BigDecimal amount,
        int roundsRun,
        int hopsTaken,
        int remainingTtl,
        List<String> routeTrace,
        String encryptedKeySnippet,
        String ivHex,
        String ciphertextSnippet,
        String status,
        String message
) {
}
