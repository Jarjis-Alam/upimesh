package com.demo.upimesh;

import com.demo.upimesh.model.MeshPacket;
import com.demo.upimesh.model.PaymentInstruction;
import com.demo.upimesh.model.SimulationResult;
import com.demo.upimesh.model.VirtualDevice;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

import java.math.BigDecimal;
import java.security.GeneralSecurityException;
import java.security.KeyPair;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;

class MeshSimulatorServiceTest {

    private CryptoService cryptoService;
    private SettlementService settlementService;
    private IdempotencyService idempotencyService;
    private BridgeIngestionService bridgeIngestionService;
    private MeshSimulatorService simulator;
    private KeyPair serverKeyPair;
    private KeyPair aliceSigningKey;

    @BeforeEach
    void setUp() throws GeneralSecurityException {
        cryptoService = new CryptoService();
        settlementService = Mockito.mock(SettlementService.class);
        Mockito.doAnswer(invocation -> {
            PaymentInstruction inst = invocation.getArgument(0);
            settlementService.transfer(inst.fromAccount(), inst.toAccount(), inst.amount());
            return null;
        }).when(settlementService).settlePayment(Mockito.any(), Mockito.any());

        idempotencyService = new IdempotencyService();
        bridgeIngestionService = new BridgeIngestionService(cryptoService, settlementService, idempotencyService);
        simulator = new MeshSimulatorService(bridgeIngestionService);
        serverKeyPair = cryptoService.generateRsaKeyPair();
        simulator.setBridgePrivateKey(serverKeyPair.getPrivate());

        aliceSigningKey = cryptoService.generateRsaKeyPair();
        bridgeIngestionService.getSenderKeyRegistry().registerKey("alice", aliceSigningKey.getPublic());
    }

    private MeshPacket createPacket(String from, String to, BigDecimal amount, int ttl, String originDeviceId) throws GeneralSecurityException {
        PaymentInstruction instruction = PaymentInstruction.create(from, to, amount);
        String sig = cryptoService.signBase64(instruction.toCanonicalBytes(), aliceSigningKey.getPrivate());
        instruction = instruction.withSignature(sig);
        String json = bridgeIngestionService.serializeInstruction(instruction);
        EncryptedPacket encryptedPacket = cryptoService.encrypt(json, serverKeyPair.getPublic());
        return MeshPacket.create(originDeviceId, "BRIDGE", ttl, encryptedPacket);
    }

    @Test
    @DisplayName("Multi-hop forwarding successfully reaches bridge and triggers settlement")
    void multiHopForwardingToBridgeSucceeds() throws GeneralSecurityException {
        // Topology: phone_A -> phone_B -> phone_C -> bridge_1
        VirtualDevice phoneA = new VirtualDevice("phone_A");
        VirtualDevice phoneB = new VirtualDevice("phone_B");
        VirtualDevice phoneC = new VirtualDevice("phone_C");
        VirtualDevice bridge1 = new VirtualDevice("bridge_1", true);

        simulator.registerDevice(phoneA);
        simulator.registerDevice(phoneB);
        simulator.registerDevice(phoneC);
        simulator.registerDevice(bridge1);

        simulator.addBidirectionalLink("phone_A", "phone_B");
        simulator.addBidirectionalLink("phone_B", "phone_C");
        simulator.addBidirectionalLink("phone_C", "bridge_1");

        MeshPacket packet = createPacket("alice", "bob", new BigDecimal("120.00"), 5, "phone_A");
        simulator.sendPacket("phone_A", packet);

        SimulationResult result = simulator.runSimulation(10);

        assertTrue(result.isFullyDelivered());
        assertEquals(1, result.getDeliveredCount());
        assertEquals(0, result.getExpiredCount());
        assertEquals(0, result.getDroppedNoNeighborCount());

        // Verify delivered packet hop count and TTL
        MeshPacket delivered = result.deliveredPackets().get(0);
        assertEquals(3, delivered.hopCount());
        assertEquals(2, delivered.ttl());

        verify(settlementService).transfer("alice", "bob", new BigDecimal("120.00"));
    }

    @Test
    @DisplayName("Packet with insufficient TTL expires before reaching bridge")
    void ttlExpirationDropsPacketBeforeBridge() throws GeneralSecurityException {
        // Topology: phone_A -> phone_B -> phone_C -> bridge_1 (3 hops needed)
        VirtualDevice phoneA = new VirtualDevice("phone_A");
        VirtualDevice phoneB = new VirtualDevice("phone_B");
        VirtualDevice phoneC = new VirtualDevice("phone_C");
        VirtualDevice bridge1 = new VirtualDevice("bridge_1", true);

        simulator.registerDevice(phoneA);
        simulator.registerDevice(phoneB);
        simulator.registerDevice(phoneC);
        simulator.registerDevice(bridge1);

        simulator.addDirectedLink("phone_A", "phone_B");
        simulator.addDirectedLink("phone_B", "phone_C");
        simulator.addDirectedLink("phone_C", "bridge_1");

        // TTL = 2 allows only 1 forward hop (phone_A -> phone_B), expiring at phone_B
        MeshPacket packet = createPacket("alice", "bob", new BigDecimal("50.00"), 2, "phone_A");
        simulator.sendPacket("phone_A", packet);

        SimulationResult result = simulator.runSimulation(10);

        assertEquals(0, result.getDeliveredCount(), "Packet must not reach bridge");
        assertEquals(1, result.getExpiredCount(), "Packet must be recorded as expired");
        verifyNoInteractions(settlementService);
    }

    @Test
    @DisplayName("Disconnected device with no neighbors drops packet and records metric")
    void disconnectedDeviceDropsPacket() throws GeneralSecurityException {
        VirtualDevice isolated = new VirtualDevice("isolated_device");
        VirtualDevice bridge = new VirtualDevice("bridge_1", true);

        simulator.registerDevice(isolated);
        simulator.registerDevice(bridge);

        MeshPacket packet = createPacket("alice", "bob", new BigDecimal("30.00"), 5, "isolated_device");
        simulator.sendPacket("isolated_device", packet);

        SimulationResult result = simulator.runSimulation(5);

        assertEquals(0, result.getDeliveredCount());
        assertEquals(1, result.getDroppedNoNeighborCount());
        verifyNoInteractions(settlementService);
    }

    @Test
    @DisplayName("Cyclic topology terminates without endless forwarding loops")
    void cyclicTopologyTerminatesWithoutInfiniteLoops() throws GeneralSecurityException {
        // Topology: Triangle loop phone_A <-> phone_B <-> phone_C <-> phone_A
        // with phone_C -> bridge_1
        VirtualDevice phoneA = new VirtualDevice("phone_A");
        VirtualDevice phoneB = new VirtualDevice("phone_B");
        VirtualDevice phoneC = new VirtualDevice("phone_C");
        VirtualDevice bridge1 = new VirtualDevice("bridge_1", true);

        simulator.registerDevice(phoneA);
        simulator.registerDevice(phoneB);
        simulator.registerDevice(phoneC);
        simulator.registerDevice(bridge1);

        simulator.addBidirectionalLink("phone_A", "phone_B");
        simulator.addBidirectionalLink("phone_B", "phone_C");
        simulator.addBidirectionalLink("phone_C", "phone_A");
        simulator.addBidirectionalLink("phone_C", "bridge_1");

        MeshPacket packet = createPacket("alice", "bob", new BigDecimal("80.00"), 10, "phone_A");
        simulator.sendPacket("phone_A", packet);

        // Simulation given up to 20 rounds, but loop suppression must drain it much sooner
        SimulationResult result = simulator.runSimulation(20);

        assertTrue(result.roundsRun() < 10, "Simulation should terminate in few rounds due to loop suppression");
        assertEquals(1, result.getDeliveredCount());
        verify(settlementService, Mockito.times(1)).transfer("alice", "bob", new BigDecimal("80.00"));
    }

    @Test
    @DisplayName("Duplicate packet suppression during gossip delivers exactly once")
    void duplicatePacketSuppressionDuringGossip() throws GeneralSecurityException {
        // Diamond topology: phone_A forwards to both phone_B and phone_C, both connected to bridge_1
        VirtualDevice phoneA = new VirtualDevice("phone_A");
        VirtualDevice phoneB = new VirtualDevice("phone_B");
        VirtualDevice phoneC = new VirtualDevice("phone_C");
        VirtualDevice bridge1 = new VirtualDevice("bridge_1", true);

        simulator.registerDevice(phoneA);
        simulator.registerDevice(phoneB);
        simulator.registerDevice(phoneC);
        simulator.registerDevice(bridge1);

        simulator.addDirectedLink("phone_A", "phone_B");
        simulator.addDirectedLink("phone_A", "phone_C");
        simulator.addDirectedLink("phone_B", "bridge_1");
        simulator.addDirectedLink("phone_C", "bridge_1");

        MeshPacket packet = createPacket("alice", "bob", new BigDecimal("95.00"), 5, "phone_A");
        simulator.sendPacket("phone_A", packet);

        SimulationResult result = simulator.runSimulation(10);

        assertEquals(1, result.getDeliveredCount());
        verify(settlementService, Mockito.times(1)).transfer("alice", "bob", new BigDecimal("95.00"));
    }
}
