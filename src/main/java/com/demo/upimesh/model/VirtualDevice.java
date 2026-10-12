package com.demo.upimesh.model;

import java.util.ArrayDeque;
import java.util.Collections;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.Queue;
import java.util.Set;

/**
 * Model representing a virtual participant or bridge node in the simulated offline mesh network.
 */
public class VirtualDevice {

    private final String deviceId;
    private final boolean isBridge;
    private final Set<String> neighborIds = new LinkedHashSet<>();
    private final Queue<MeshPacket> packetBuffer = new ArrayDeque<>();
    private final Set<String> seenPacketIds = new HashSet<>();

    public VirtualDevice(String deviceId, boolean isBridge) {
        if (deviceId == null || deviceId.isBlank()) {
            throw new IllegalArgumentException("deviceId must not be blank");
        }
        this.deviceId = deviceId;
        this.isBridge = isBridge;
    }

    public VirtualDevice(String deviceId) {
        this(deviceId, false);
    }

    public String getDeviceId() {
        return deviceId;
    }

    public boolean isBridge() {
        return isBridge;
    }

    public Set<String> getNeighborIds() {
        return Collections.unmodifiableSet(neighborIds);
    }

    public void addNeighbor(String neighborId) {
        if (neighborId != null && !neighborId.isBlank() && !neighborId.equals(this.deviceId)) {
            neighborIds.add(neighborId);
        }
    }

    public void removeNeighbor(String neighborId) {
        neighborIds.remove(neighborId);
    }

    public Queue<MeshPacket> getPacketBuffer() {
        return packetBuffer;
    }

    public void enqueuePacket(MeshPacket packet) {
        if (packet != null) {
            packetBuffer.add(packet);
        }
    }

    public Set<String> getSeenPacketIds() {
        return Collections.unmodifiableSet(seenPacketIds);
    }

    public boolean markSeen(String packetId) {
        if (packetId == null) return false;
        return seenPacketIds.add(packetId);
    }

    public boolean hasSeen(String packetId) {
        if (packetId == null) return false;
        return seenPacketIds.contains(packetId);
    }

    public void clear() {
        packetBuffer.clear();
        seenPacketIds.clear();
    }
}
