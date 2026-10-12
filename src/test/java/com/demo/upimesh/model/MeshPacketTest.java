package com.demo.upimesh.model;

import com.demo.upimesh.EncryptedPacket;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;

class MeshPacketTest {

    private EncryptedPacket dummyPayload;

    @BeforeEach
    void setUp() {
        dummyPayload = new EncryptedPacket(
                new byte[]{1, 2, 3},
                new byte[]{4, 5, 6},
                new byte[]{7, 8, 9}
        );
    }

    @Test
    @DisplayName("Factory method create() constructs valid MeshPacket with hopCount = 0")
    void factoryMethodConstructsValidPacket() {
        MeshPacket packet = MeshPacket.create("device_phone_1", "SERVER", 5, dummyPayload);

        assertNotNull(packet.packetId());
        assertNotNull(UUID.fromString(packet.packetId()));
        assertEquals("device_phone_1", packet.originDeviceId());
        assertEquals("SERVER", packet.destination());
        assertEquals(5, packet.ttl());
        assertEquals(0, packet.hopCount());
        assertEquals(dummyPayload, packet.payload());
        assertEquals(dummyPayload, packet.getEncryptedPayload());
    }

    @Test
    @DisplayName("Rejects TTL <= 0")
    void rejectsInvalidTtl() {
        assertThrows(IllegalArgumentException.class, () ->
                MeshPacket.create("device_phone_1", "SERVER", 0, dummyPayload)
        );

        assertThrows(IllegalArgumentException.class, () ->
                MeshPacket.create("device_phone_1", "SERVER", -3, dummyPayload)
        );
    }

    @Test
    @DisplayName("Rejects negative hop count in canonical constructor")
    void rejectsNegativeHopCount() {
        assertThrows(IllegalArgumentException.class, () ->
                new MeshPacket("pkt-1", "device_1", "SERVER", 3, -1, dummyPayload)
        );
    }

    @Test
    @DisplayName("Rejects null payload")
    void rejectsNullPayload() {
        assertThrows(IllegalArgumentException.class, () ->
                MeshPacket.create("device_phone_1", "SERVER", 3, null)
        );
    }

    @Test
    @DisplayName("Rejects blank or null identifiers")
    void rejectsBlankOrNullIdentifiers() {
        assertThrows(IllegalArgumentException.class, () ->
                new MeshPacket(null, "device_1", "SERVER", 3, 0, dummyPayload)
        );
        assertThrows(IllegalArgumentException.class, () ->
                new MeshPacket("  ", "device_1", "SERVER", 3, 0, dummyPayload)
        );
        assertThrows(IllegalArgumentException.class, () ->
                new MeshPacket("pkt-1", null, "SERVER", 3, 0, dummyPayload)
        );
        assertThrows(IllegalArgumentException.class, () ->
                new MeshPacket("pkt-1", "device_1", null, 3, 0, dummyPayload)
        );
    }

    @Test
    @DisplayName("nextHop() decrements TTL and increments hop count")
    void nextHopUpdatesTtlAndHopCount() {
        MeshPacket initial = MeshPacket.create("phone_A", "BRIDGE", 3, dummyPayload);
        assertEquals(3, initial.ttl());
        assertEquals(0, initial.hopCount());

        MeshPacket hop1 = initial.nextHop();
        assertEquals(initial.packetId(), hop1.packetId());
        assertEquals(2, hop1.ttl());
        assertEquals(1, hop1.hopCount());

        MeshPacket hop2 = hop1.nextHop();
        assertEquals(1, hop2.ttl());
        assertEquals(2, hop2.hopCount());

        // TTL reached 1, cannot forward further
        assertThrows(IllegalStateException.class, hop2::nextHop);
    }
}
