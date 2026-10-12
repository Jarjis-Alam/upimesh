package com.demo.upimesh;

import com.demo.upimesh.model.MeshPacket;
import com.demo.upimesh.model.MeshPaymentResult;
import com.demo.upimesh.model.PaymentInstruction;
import com.demo.upimesh.model.SimulationResult;
import com.demo.upimesh.model.VirtualDevice;
import jakarta.annotation.PostConstruct;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.security.GeneralSecurityException;
import java.security.KeyPair;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.util.ArrayList;
import java.util.Base64;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Service simulating deterministic, offline multi-hop mesh packet forwarding.
 * <p>
 * Key Characteristics:
 * 1. Fully deterministic: Executes explicit discrete gossip rounds with no threads, timers,
 *    sockets, Bluetooth, or physical networking.
 * 2. Intermediate devices only forward opaque ciphertext envelopes; they cannot decrypt, inspect,
 *    or modify payment instructions.
 * 3. Loop prevention: Devices track seen packet IDs, refusing to re-enqueue packets they have
 *    already witnessed.
 * 4. Bridges act as mesh sinks that terminate forwarding and trigger deferred settlement through
 *    the BridgeIngestionService.
 * 5. Sender Authentication: Senders cryptographically sign canonical payment instructions using
 *    RSASSA-PSS SHA-256 before hybrid encryption.
 */
@Service
public class MeshSimulatorService {

    private final BridgeIngestionService bridgeIngestionService;
    private final CryptoService cryptoService;
    private final SenderKeyRegistry senderKeyRegistry;
    private final Map<String, VirtualDevice> devices = new LinkedHashMap<>();
    private final Map<String, KeyPair> senderKeyPairs = new LinkedHashMap<>();
    private PrivateKey bridgePrivateKey;
    private KeyPair bridgeKeyPair;

    private String lastSettlementError;
    private MeshPacket lastDeliveredPacket;
    private MeshPacket lastDuplicatePacket;

    private final List<MeshPacket> deliveredPackets = new ArrayList<>();
    private final List<PaymentInstruction> settledInstructions = new ArrayList<>();
    private final List<MeshPacket> expiredPackets = new ArrayList<>();
    private final List<MeshPacket> droppedNoNeighborPackets = new ArrayList<>();

    public MeshSimulatorService(BridgeIngestionService bridgeIngestionService) {
        this(
                bridgeIngestionService,
                new CryptoService(),
                bridgeIngestionService.getSenderKeyRegistry() != null ? bridgeIngestionService.getSenderKeyRegistry() : new SenderKeyRegistry()
        );
    }

    public MeshSimulatorService(BridgeIngestionService bridgeIngestionService, CryptoService cryptoService) {
        this(
                bridgeIngestionService,
                cryptoService,
                bridgeIngestionService.getSenderKeyRegistry() != null ? bridgeIngestionService.getSenderKeyRegistry() : new SenderKeyRegistry()
        );
    }

    @Autowired
    public MeshSimulatorService(
            BridgeIngestionService bridgeIngestionService,
            CryptoService cryptoService,
            SenderKeyRegistry senderKeyRegistry
    ) {
        this.bridgeIngestionService = bridgeIngestionService;
        this.cryptoService = cryptoService;
        this.senderKeyRegistry = senderKeyRegistry;
    }

    public void setBridgePrivateKey(PrivateKey bridgePrivateKey) {
        this.bridgePrivateKey = bridgePrivateKey;
    }

    public void setBridgeKeyPair(KeyPair bridgeKeyPair) {
        this.bridgeKeyPair = bridgeKeyPair;
        if (bridgeKeyPair != null) {
            this.bridgePrivateKey = bridgeKeyPair.getPrivate();
        }
    }

    public KeyPair getBridgeKeyPair() {
        return bridgeKeyPair;
    }

    public PublicKey getBridgePublicKey() {
        if (bridgeKeyPair == null) {
            initDefaultTopology();
        }
        return bridgeKeyPair != null ? bridgeKeyPair.getPublic() : null;
    }

    public PrivateKey getBridgePrivateKey() {
        if (bridgePrivateKey != null) {
            return bridgePrivateKey;
        }
        if (bridgeKeyPair == null) {
            initDefaultTopology();
        }
        return bridgeKeyPair != null ? bridgeKeyPair.getPrivate() : null;
    }

    public BridgeIngestionService getBridgeIngestionService() {
        return bridgeIngestionService;
    }

    @PostConstruct
    public void initDefaultTopology() {
        if (devices.isEmpty()) {
            VirtualDevice alice = new VirtualDevice("alice");
            VirtualDevice carol = new VirtualDevice("carol");
            VirtualDevice bob = new VirtualDevice("bob");
            VirtualDevice bridge = new VirtualDevice("bridge", true);

            registerDevice(alice);
            registerDevice(carol);
            registerDevice(bob);
            registerDevice(bridge);

            addBidirectionalLink("alice", "carol");
            addBidirectionalLink("bob", "carol");
            addBidirectionalLink("carol", "bridge");
        }

        if (bridgePrivateKey == null && cryptoService != null) {
            try {
                KeyPair keyPair = cryptoService.generateRsaKeyPair();
                setBridgeKeyPair(keyPair);
            } catch (GeneralSecurityException e) {
                throw new IllegalStateException("Failed to generate RSA key pair for bridge simulation", e);
            }
        }

        // Initialize and register sender signing keys for simulated demo wallets
        if (cryptoService != null) {
            ensureSenderKeyPair("alice");
            ensureSenderKeyPair("bob");
            ensureSenderKeyPair("carol");
        }
    }

    public KeyPair ensureSenderKeyPair(String accountId) {
        String id = accountId.toLowerCase();
        if (!senderKeyPairs.containsKey(id)) {
            try {
                KeyPair keyPair = cryptoService.generateRsaKeyPair();
                senderKeyPairs.put(id, keyPair);
                senderKeyRegistry.registerKey(id, keyPair.getPublic());
                return keyPair;
            } catch (GeneralSecurityException e) {
                throw new IllegalStateException("Failed to generate signing key for sender: " + id, e);
            }
        }
        return senderKeyPairs.get(id);
    }

    public void registerSenderKeyPair(String accountId, KeyPair keyPair) {
        if (accountId == null || keyPair == null) {
            throw new IllegalArgumentException("Account ID and KeyPair must not be null");
        }
        String id = accountId.toLowerCase();
        senderKeyPairs.put(id, keyPair);
        senderKeyRegistry.registerKey(id, keyPair.getPublic());
    }

    public KeyPair getSenderKeyPair(String accountId) {
        return accountId != null ? senderKeyPairs.get(accountId.toLowerCase()) : null;
    }

    public SenderKeyRegistry getSenderKeyRegistry() {
        return senderKeyRegistry;
    }

    public Map<String, VirtualDevice> getDevices() {
        return Collections.unmodifiableMap(devices);
    }

    public void registerDevice(VirtualDevice device) {
        if (device == null) {
            throw new IllegalArgumentException("VirtualDevice must not be null");
        }
        devices.put(device.getDeviceId(), device);
    }

    public VirtualDevice getDevice(String deviceId) {
        return devices.get(deviceId);
    }

    public void addBidirectionalLink(String deviceId1, String deviceId2) {
        VirtualDevice d1 = devices.get(deviceId1);
        VirtualDevice d2 = devices.get(deviceId2);
        if (d1 == null || d2 == null) {
            throw new IllegalArgumentException("Both devices must be registered before adding a link");
        }
        d1.addNeighbor(deviceId2);
        d2.addNeighbor(deviceId1);
    }

    public void addDirectedLink(String fromDeviceId, String toDeviceId) {
        VirtualDevice from = devices.get(fromDeviceId);
        VirtualDevice to = devices.get(toDeviceId);
        if (from == null || to == null) {
            throw new IllegalArgumentException("Both devices must be registered before adding a link");
        }
        from.addNeighbor(toDeviceId);
    }

    public void sendPacket(String originDeviceId, MeshPacket packet) {
        VirtualDevice origin = devices.get(originDeviceId);
        if (origin == null) {
            throw new IllegalArgumentException("Origin device not found: " + originDeviceId);
        }
        if (packet == null) {
            throw new IllegalArgumentException("MeshPacket must not be null");
        }
        origin.markSeen(packet.packetId());
        origin.enqueuePacket(packet);
    }

    /**
     * Executes a single discrete gossip/forwarding round across all registered devices.
     *
     * @return true if any packets were forwarded or processed during this round
     */
    public boolean runGossipRound() {
        // Snapshot current packet buffers to process this round, avoiding in-round re-processing
        Map<String, List<MeshPacket>> roundBuffers = new LinkedHashMap<>();
        for (VirtualDevice device : devices.values()) {
            List<MeshPacket> packets = new ArrayList<>();
            while (!device.getPacketBuffer().isEmpty()) {
                packets.add(device.getPacketBuffer().poll());
            }
            if (!packets.isEmpty()) {
                roundBuffers.put(device.getDeviceId(), packets);
            }
        }

        if (roundBuffers.isEmpty()) {
            return false;
        }

        for (Map.Entry<String, List<MeshPacket>> entry : roundBuffers.entrySet()) {
            VirtualDevice device = devices.get(entry.getKey());
            for (MeshPacket packet : entry.getValue()) {

                // 1. If this device is a bridge, ingest the packet into the backend settlement pipeline
                if (device.isBridge()) {
                    if (bridgePrivateKey != null) {
                        try {
                            PaymentInstruction settled = bridgeIngestionService.ingest(packet, bridgePrivateKey);
                            deliveredPackets.add(packet);
                            settledInstructions.add(settled);
                            lastDeliveredPacket = packet;
                        } catch (DuplicatePacketException e) {
                            // Idempotency caught duplicate packet at bridge boundary; safely ignore
                            lastDuplicatePacket = packet;
                        } catch (Exception e) {
                            // Validation, signature verification, or settlement failed
                            lastSettlementError = e.getMessage();
                        }
                    }
                    continue; // Bridges consume the packet; do not forward further into mesh
                }

                // 2. Non-bridge device: check neighbors
                Set<String> neighbors = device.getNeighborIds();
                if (neighbors.isEmpty()) {
                    droppedNoNeighborPackets.add(packet);
                    continue;
                }

                // 3. Check TTL
                if (packet.ttl() <= 1) {
                    expiredPackets.add(packet);
                    continue; // Packet dropped due to TTL exhaustion
                }

                // 4. Forward nextHop to eligible neighbors that have not witnessed this packet
                MeshPacket nextHopPacket = packet.nextHop();
                for (String neighborId : neighbors) {
                    VirtualDevice neighbor = devices.get(neighborId);
                    if (neighbor != null && !neighbor.hasSeen(packet.packetId())) {
                        neighbor.markSeen(packet.packetId());
                        neighbor.enqueuePacket(nextHopPacket);
                    }
                }
            }
        }

        return true;
    }

    /**
     * Executes an end-to-end simulated mesh payment across the 4 stages:
     * 1. Sender: Payment instruction creation and cryptographic signing (RSASSA-PSS SHA-256),
     *    followed by hybrid encryption (RSA-OAEP + AES-256-GCM).
     * 2. Virtual Mesh: Multi-hop forwarding, loop suppression, and TTL decrement across virtual devices.
     * 3. Bridge Ingestion: Canonical SHA-256 deduplication, payload decryption, and signature verification.
     * 4. Settlement: Atomic balance adjustments and persistent transaction ledger insertion.
     */
    public MeshPaymentResult simulateMeshPayment(String from, String to, BigDecimal amount, int ttl) {
        if (from == null || from.isBlank()) {
            throw new IllegalArgumentException("Sender account must not be blank");
        }
        if (to == null || to.isBlank()) {
            throw new IllegalArgumentException("Receiver account must not be blank");
        }
        if (from.equalsIgnoreCase(to)) {
            throw new IllegalArgumentException("Sender and receiver must be different");
        }
        if (amount == null || amount.compareTo(BigDecimal.ZERO) <= 0) {
            throw new IllegalArgumentException("Transfer amount must be greater than zero");
        }

        // Ensure default topology, keys, and sender identity keypairs are ready
        initDefaultTopology();

        String fromId = from.toLowerCase();
        String toId = to.toLowerCase();

        // Ensure origin device exists in mesh
        VirtualDevice origin = devices.get(fromId);
        if (origin == null) {
            origin = new VirtualDevice(fromId);
            registerDevice(origin);
            addBidirectionalLink(fromId, "carol");
        }

        lastSettlementError = null;
        lastDeliveredPacket = null;
        lastDuplicatePacket = null;

        try {
            // Step 1: Create payment instruction and digitally sign using sender's private key
            PaymentInstruction unsignedInstruction = PaymentInstruction.create(fromId, toId, amount);

            KeyPair senderKeyPair = ensureSenderKeyPair(fromId);
            String signature = cryptoService.signBase64(unsignedInstruction.toCanonicalBytes(), senderKeyPair.getPrivate());
            PaymentInstruction signedInstruction = unsignedInstruction.withSignature(signature);

            // Step 2: Serialize signed instruction and hybrid encrypt to Bridge public key
            String json = bridgeIngestionService.serializeInstruction(signedInstruction);

            PublicKey pubKey = getBridgePublicKey();
            if (pubKey == null) {
                throw new IllegalStateException("Bridge public key is not initialized");
            }
            com.demo.upimesh.EncryptedPacket encryptedPacket = cryptoService.encrypt(json, pubKey);

            // Step 3: Create mesh packet and inject into origin device buffer
            int initialTtl = ttl > 0 ? ttl : 5;
            MeshPacket meshPacket = MeshPacket.create(fromId, "bridge", initialTtl, encryptedPacket);
            sendPacket(fromId, meshPacket);

            // Step 4: Run deterministic gossip rounds until delivered or drained
            int startDeliveredCount = deliveredPackets.size();
            SimulationResult simResult = runSimulation(10);

            // Step 5: Evaluate outcome
            boolean wasDelivered = deliveredPackets.size() > startDeliveredCount;
            MeshPacket delivered = wasDelivered ? deliveredPackets.get(deliveredPackets.size() - 1) : null;

            // Route trace
            List<String> routeTrace = new ArrayList<>();
            routeTrace.add(fromId);
            if (!fromId.equals("carol")) {
                routeTrace.add("carol");
            }
            routeTrace.add("bridge");

            String encKeySnippet = encryptedPacket.encryptedAesKey().length > 16
                    ? Base64.getEncoder().encodeToString(encryptedPacket.encryptedAesKey()).substring(0, 16) + "..."
                    : Base64.getEncoder().encodeToString(encryptedPacket.encryptedAesKey());
            String ivHex = bytesToHex(encryptedPacket.iv());
            String cipherSnippet = encryptedPacket.ciphertext().length > 16
                    ? Base64.getEncoder().encodeToString(encryptedPacket.ciphertext()).substring(0, 16) + "..."
                    : Base64.getEncoder().encodeToString(encryptedPacket.ciphertext());

            if (wasDelivered && delivered != null) {
                return new MeshPaymentResult(
                        true,
                        signedInstruction.paymentId(),
                        meshPacket.packetId(),
                        fromId,
                        toId,
                        amount,
                        simResult.roundsRun(),
                        delivered.hopCount(),
                        delivered.ttl(),
                        routeTrace,
                        encKeySnippet,
                        ivHex,
                        cipherSnippet,
                        "SETTLED",
                        "Payment of ₹" + amount.toPlainString() + " authenticated via RSA-PSS, routed via " + delivered.hopCount() + " hops and settled atomically at Bridge Gateway."
                );
            } else if (lastDuplicatePacket != null) {
                return new MeshPaymentResult(
                        false,
                        signedInstruction.paymentId(),
                        meshPacket.packetId(),
                        fromId,
                        toId,
                        amount,
                        simResult.roundsRun(),
                        meshPacket.hopCount(),
                        meshPacket.ttl(),
                        routeTrace,
                        encKeySnippet,
                        ivHex,
                        cipherSnippet,
                        "DUPLICATE_REJECTED",
                        "Duplicate packet rejected by Bridge Idempotency Service."
                );
            } else if (lastSettlementError != null) {
                return new MeshPaymentResult(
                        false,
                        signedInstruction.paymentId(),
                        meshPacket.packetId(),
                        fromId,
                        toId,
                        amount,
                        simResult.roundsRun(),
                        meshPacket.hopCount(),
                        meshPacket.ttl(),
                        routeTrace,
                        encKeySnippet,
                        ivHex,
                        cipherSnippet,
                        "REJECTED",
                        "Settlement rejected at bridge: " + lastSettlementError
                );
            } else if (simResult.getExpiredCount() > 0) {
                return new MeshPaymentResult(
                        false,
                        signedInstruction.paymentId(),
                        meshPacket.packetId(),
                        fromId,
                        toId,
                        amount,
                        simResult.roundsRun(),
                        meshPacket.hopCount(),
                        0,
                        routeTrace,
                        encKeySnippet,
                        ivHex,
                        cipherSnippet,
                        "EXPIRED",
                        "Packet expired before reaching bridge (TTL exhausted)."
                );
            } else if (simResult.getDroppedNoNeighborCount() > 0) {
                return new MeshPaymentResult(
                        false,
                        signedInstruction.paymentId(),
                        meshPacket.packetId(),
                        fromId,
                        toId,
                        amount,
                        simResult.roundsRun(),
                        meshPacket.hopCount(),
                        meshPacket.ttl(),
                        routeTrace,
                        encKeySnippet,
                        ivHex,
                        cipherSnippet,
                        "DROPPED",
                        "Packet dropped: origin device has no connected mesh neighbors."
                );
            } else {
                return new MeshPaymentResult(
                        false,
                        signedInstruction.paymentId(),
                        meshPacket.packetId(),
                        fromId,
                        toId,
                        amount,
                        simResult.roundsRun(),
                        meshPacket.hopCount(),
                        meshPacket.ttl(),
                        routeTrace,
                        encKeySnippet,
                        ivHex,
                        cipherSnippet,
                        "FAILED",
                        "Mesh payment simulation did not reach settlement."
                );
            }
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException("Cryptographic operation failed during mesh payment", e);
        }
    }

    private static String bytesToHex(byte[] bytes) {
        if (bytes == null) return "";
        StringBuilder sb = new StringBuilder();
        for (byte b : bytes) {
            sb.append(String.format("%02x", b));
        }
        return sb.toString();
    }

    /**
     * Runs gossip rounds until all packet buffers are empty or maxRounds is reached.
     */
    public SimulationResult runSimulation(int maxRounds) {
        int rounds = 0;
        while (rounds < maxRounds) {
            rounds++;
            boolean hadActivity = runGossipRound();
            if (!hadActivity) {
                rounds--; // last round had no activity
                break;
            }
        }
        return new SimulationResult(
                rounds,
                Collections.unmodifiableList(new ArrayList<>(deliveredPackets)),
                Collections.unmodifiableList(new ArrayList<>(settledInstructions)),
                Collections.unmodifiableList(new ArrayList<>(expiredPackets)),
                Collections.unmodifiableList(new ArrayList<>(droppedNoNeighborPackets))
        );
    }

    /**
     * Clears all simulated device states and accumulated metrics.
     */
    public void reset() {
        devices.values().forEach(VirtualDevice::clear);
        devices.clear();
        deliveredPackets.clear();
        settledInstructions.clear();
        expiredPackets.clear();
        droppedNoNeighborPackets.clear();
        senderKeyPairs.clear();
        senderKeyRegistry.clear();
        lastSettlementError = null;
        lastDeliveredPacket = null;
        lastDuplicatePacket = null;
    }
}
