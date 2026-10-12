package com.demo.upimesh.model;

import java.math.BigDecimal;

/**
 * Structured receipt model returned upon ingesting and settling an external MeshPacket.
 */
public record MeshIngestResult(
        boolean success,
        String status,
        String paymentId,
        String packetId,
        String fromAccount,
        String toAccount,
        BigDecimal amount,
        String message
) {
}
