package com.demo.upimesh;

import com.demo.upimesh.model.MeshPacket;
import com.demo.upimesh.model.PaymentInstruction;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import tools.jackson.databind.ObjectMapper;

import java.math.BigDecimal;
import java.security.GeneralSecurityException;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;

/**
 * Service responsible for ingesting mesh-routed packets arriving at a backend bridge.
 * <p>
 * Security Considerations:
 * 1. Routing metadata (originDeviceId, destination, hopCount) is untrusted transport metadata
 *    used solely for mesh routing and must NEVER be treated as proof of payment validity.
 * 2. Hybrid encryption (RSA-OAEP + AES-256-GCM) guarantees payload confidentiality and integrity
 *    across untrusted mesh relays.
 * 3. Cryptographic sender authentication (RSASSA-PSS SHA-256) verifies the authenticity of the
 *    claimed sender account against a trusted sender key registry before settlement.
 * 4. Idempotency (SHA-256 canonical ciphertext hash) prevents replay and duplicate settlement.
 */
@Service
public class BridgeIngestionService {

    /**
     * Allowed clock-skew window for timestamps slightly in the future (5 minutes).
     */
    public static final Duration MAX_CLOCK_SKEW = Duration.ofMinutes(5);

    /**
     * Maximum age for an offline payment instruction before it is deemed expired (24 hours).
     */
    public static final Duration MAX_INSTRUCTION_AGE = Duration.ofHours(24);

    private final CryptoService cryptoService;
    private final SettlementService settlementService;
    private final IdempotencyService idempotencyService;
    private final SenderKeyRegistry senderKeyRegistry;
    private final ObjectMapper objectMapper;
    private final Clock clock;

    @Autowired
    public BridgeIngestionService(
            CryptoService cryptoService,
            SettlementService settlementService,
            IdempotencyService idempotencyService,
            SenderKeyRegistry senderKeyRegistry
    ) {
        this(cryptoService, settlementService, idempotencyService, senderKeyRegistry, new ObjectMapper(), Clock.systemUTC());
    }

    public BridgeIngestionService(CryptoService cryptoService, SettlementService settlementService) {
        this(cryptoService, settlementService, new IdempotencyService(), new SenderKeyRegistry(), new ObjectMapper(), Clock.systemUTC());
    }

    public BridgeIngestionService(
            CryptoService cryptoService,
            SettlementService settlementService,
            IdempotencyService idempotencyService
    ) {
        this(cryptoService, settlementService, idempotencyService, new SenderKeyRegistry(), new ObjectMapper(), Clock.systemUTC());
    }

    public BridgeIngestionService(
            CryptoService cryptoService,
            SettlementService settlementService,
            IdempotencyService idempotencyService,
            SenderKeyRegistry senderKeyRegistry,
            ObjectMapper objectMapper,
            Clock clock
    ) {
        this.cryptoService = cryptoService;
        this.settlementService = settlementService;
        this.idempotencyService = idempotencyService;
        this.senderKeyRegistry = senderKeyRegistry;
        this.objectMapper = objectMapper;
        this.clock = clock;
    }

    public SenderKeyRegistry getSenderKeyRegistry() {
        return senderKeyRegistry;
    }

    /**
     * Serializes a PaymentInstruction into JSON.
     */
    public String serializeInstruction(PaymentInstruction instruction) {
        if (instruction == null) {
            throw new IllegalArgumentException("PaymentInstruction must not be null");
        }
        try {
            return objectMapper.writeValueAsString(instruction);
        } catch (Exception e) {
            throw new IllegalArgumentException("Failed to serialize payment instruction to JSON", e);
        }
    }

    /**
     * Ingests a mesh packet, decrypts the payload, validates the instruction, verifies the sender
     * signature against the trusted registry, and triggers atomic settlement.
     *
     * @param packet               the received mesh packet
     * @param recipientPrivateKey  the backend's RSA private key to decrypt the AES session key
     * @return the validated and settled PaymentInstruction
     * @throws GeneralSecurityException if cryptographic decryption or signature verification fails
     */
    public PaymentInstruction ingest(MeshPacket packet, PrivateKey recipientPrivateKey) throws GeneralSecurityException {
        if (packet == null) {
            throw new IllegalArgumentException("MeshPacket must not be null");
        }
        if (recipientPrivateKey == null) {
            throw new IllegalArgumentException("Recipient private key must not be null");
        }

        // 1. Compute canonical ciphertext hash and acquire atomic in-memory claim
        String packetHash = idempotencyService.computeHash(packet.payload());
        if (idempotencyService.isSettled(packetHash) || !idempotencyService.tryClaim(packetHash)) {
            throw new DuplicatePacketException("Duplicate packet rejected: " + packetHash);
        }

        boolean success = false;
        try {
            // 2. Decrypt packet payload using CryptoService (AES-256-GCM + RSA-OAEP)
            String plaintextJson = cryptoService.decrypt(packet.payload(), recipientPrivateKey);

            // 3. Deserialize plaintext JSON into PaymentInstruction
            PaymentInstruction instruction;
            try {
                instruction = objectMapper.readValue(plaintextJson, PaymentInstruction.class);
            } catch (Exception e) {
                throw new IllegalArgumentException("Failed to deserialize payment instruction from plaintext JSON", e);
            }

            if (instruction == null) {
                throw new IllegalArgumentException("Deserialized payment instruction is null");
            }

            // 4. Validate payment instruction domain rules and timestamp window
            validateInstruction(instruction);

            // 5. Verify cryptographic digital signature against trusted sender key registry
            verifySenderSignature(instruction);

            // 6. Trigger atomic settlement transfer and persistent idempotency record
            try {
                settlementService.settlePayment(instruction, packetHash);
            } catch (DataIntegrityViolationException e) {
                throw new DuplicatePacketException("Duplicate packet rejected by database constraint: " + packetHash, e);
            }

            // 7. Mark idempotency claim as SETTLED in memory
            idempotencyService.markSettled(packetHash);
            success = true;

            return instruction;
        } finally {
            if (!success) {
                // If processing failed (decryption, validation, signature, or settlement), release the claim to allow retries
                idempotencyService.releaseClaim(packetHash);
            }
        }
    }

    /**
     * Verifies the RSA-PSS SHA-256 digital signature of the payment instruction using the trusted public
     * key registered for the claimed sender account ID.
     */
    private void verifySenderSignature(PaymentInstruction instruction) throws GeneralSecurityException {
        String fromAccount = instruction.fromAccount();
        String signature = instruction.signature();

        if (signature == null || signature.isBlank()) {
            throw new IllegalArgumentException("Payment instruction signature is missing for sender: " + fromAccount);
        }

        PublicKey senderPublicKey = senderKeyRegistry.getPublicKey(fromAccount)
                .orElseThrow(() -> new IllegalArgumentException("Unknown or unregistered sender: " + fromAccount));

        byte[] canonicalBytes = instruction.toCanonicalBytes();
        boolean isValid = cryptoService.verifySignatureBase64(canonicalBytes, signature, senderPublicKey);

        if (!isValid) {
            throw new IllegalArgumentException("Invalid digital signature for sender: " + fromAccount);
        }
    }

    /**
     * Validates business invariants and timestamp validity window.
     */
    private void validateInstruction(PaymentInstruction instruction) {
        if (instruction.paymentId() == null || instruction.paymentId().isBlank()) {
            throw new IllegalArgumentException("paymentId must not be blank");
        }
        if (instruction.fromAccount() == null || instruction.fromAccount().isBlank()) {
            throw new IllegalArgumentException("fromAccount must not be blank");
        }
        if (instruction.toAccount() == null || instruction.toAccount().isBlank()) {
            throw new IllegalArgumentException("toAccount must not be blank");
        }
        if (instruction.fromAccount().equals(instruction.toAccount())) {
            throw new IllegalArgumentException("Sender and receiver must be different");
        }
        if (instruction.amount() == null || instruction.amount().compareTo(BigDecimal.ZERO) <= 0) {
            throw new IllegalArgumentException("Transfer amount must be greater than zero");
        }
        if (instruction.nonce() == null || instruction.nonce().isBlank()) {
            throw new IllegalArgumentException("nonce must not be blank");
        }
        if (instruction.createdAt() == null) {
            throw new IllegalArgumentException("createdAt timestamp must not be null");
        }

        Instant now = Instant.now(clock);
        if (instruction.createdAt().isAfter(now.plus(MAX_CLOCK_SKEW))) {
            throw new IllegalArgumentException("Payment instruction timestamp is in the future beyond allowed clock skew");
        }
        if (instruction.createdAt().isBefore(now.minus(MAX_INSTRUCTION_AGE))) {
            throw new IllegalArgumentException("Payment instruction has expired (older than 24 hours)");
        }
    }
}
