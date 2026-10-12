package com.demo.upimesh.model;

import com.demo.upimesh.EncryptedPacket;

import java.util.UUID;

public record MeshPacket(
        String packetId,
        String originDeviceId,
        String destination,
        int ttl,
        int hopCount,
        EncryptedPacket payload
) {
    public MeshPacket {
        if (packetId == null || packetId.isBlank()) {
            throw new IllegalArgumentException("packetId must not be blank");
        }
        if (originDeviceId == null || originDeviceId.isBlank()) {
            throw new IllegalArgumentException("originDeviceId must not be blank");
        }
        if (destination == null || destination.isBlank()) {
            throw new IllegalArgumentException("destination must not be blank");
        }
        if (ttl <= 0) {
            throw new IllegalArgumentException("TTL must be greater than zero");
        }
        if (hopCount < 0) {
            throw new IllegalArgumentException("Hop count cannot be negative");
        }
        if (payload == null) {
            throw new IllegalArgumentException("EncryptedPacket payload must not be null");
        }
    }

    /**
     * Convenience constructor starting with hopCount = 0.
     */
    public MeshPacket(String packetId, String originDeviceId, String destination, int ttl, EncryptedPacket payload) {
        this(packetId, originDeviceId, destination, ttl, 0, payload);
    }

    /**
     * Factory method to create a new MeshPacket with a generated packetId and hopCount = 0.
     */
    public static MeshPacket create(String originDeviceId, String destination, int ttl, EncryptedPacket payload) {
        return new MeshPacket(
                UUID.randomUUID().toString(),
                originDeviceId,
                destination,
                ttl,
                0,
                payload
        );
    }

    /**
     * Returns a new immutable MeshPacket for the next mesh hop, decrementing TTL and incrementing hop count.
     */
    public MeshPacket nextHop() {
        if (ttl <= 1) {
            throw new IllegalStateException("Packet TTL expired; packet cannot be forwarded");
        }
        return new MeshPacket(
                packetId,
                originDeviceId,
                destination,
                ttl - 1,
                hopCount + 1,
                payload
        );
    }

    public String getPacketId() {
        return packetId;
    }

    public String getOriginDeviceId() {
        return originDeviceId;
    }

    public String getDestination() {
        return destination;
    }

    public int getTtl() {
        return ttl;
    }

    public int getHopCount() {
        return hopCount;
    }

    public EncryptedPacket getPayload() {
        return payload;
    }

    public EncryptedPacket getEncryptedPayload() {
        return payload;
    }
}
