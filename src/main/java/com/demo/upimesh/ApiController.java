package com.demo.upimesh;

import com.demo.upimesh.model.Account;
import com.demo.upimesh.model.AccountRepository;
import com.demo.upimesh.model.BridgePublicKeyResponse;
import com.demo.upimesh.model.KeyRegistrationRequest;
import com.demo.upimesh.model.KeyRegistrationResponse;
import com.demo.upimesh.model.MeshIngestResult;
import com.demo.upimesh.model.MeshPacket;
import com.demo.upimesh.model.MeshPaymentResult;
import com.demo.upimesh.model.PaymentInstruction;
import com.demo.upimesh.model.ReconciliationReport;
import com.demo.upimesh.model.Transaction;
import com.demo.upimesh.model.TransactionRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.math.BigDecimal;
import java.security.GeneralSecurityException;
import java.security.KeyFactory;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.security.interfaces.RSAPublicKey;
import java.security.spec.X509EncodedKeySpec;
import java.util.ArrayList;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api")
public class ApiController {

    private static final Logger log = LoggerFactory.getLogger(ApiController.class);

    private final AccountRepository accountRepository;
    private final SettlementService settlementService;
    private final TransactionRepository transactionRepository;
    private final MeshSimulatorService meshSimulatorService;
    private final ReconciliationService reconciliationService;
    private final BridgeIngestionService bridgeIngestionService;
    private final SenderKeyRegistry senderKeyRegistry;

    @Autowired
    public ApiController(
            AccountRepository accountRepository,
            SettlementService settlementService,
            TransactionRepository transactionRepository,
            MeshSimulatorService meshSimulatorService,
            @Autowired(required = false) ReconciliationService reconciliationService,
            @Autowired(required = false) BridgeIngestionService bridgeIngestionService,
            @Autowired(required = false) SenderKeyRegistry senderKeyRegistry
    ) {
        this.accountRepository = accountRepository;
        this.settlementService = settlementService;
        this.transactionRepository = transactionRepository;
        this.meshSimulatorService = meshSimulatorService;
        this.reconciliationService = reconciliationService;
        this.bridgeIngestionService = bridgeIngestionService != null
                ? bridgeIngestionService
                : (meshSimulatorService != null ? meshSimulatorService.getBridgeIngestionService() : null);
        this.senderKeyRegistry = senderKeyRegistry != null
                ? senderKeyRegistry
                : (meshSimulatorService != null ? meshSimulatorService.getSenderKeyRegistry() : null);
    }

    public ApiController(AccountRepository accountRepository, SettlementService settlementService) {
        this(accountRepository, settlementService, null, null, null, null, null);
    }

    public ApiController(
            AccountRepository accountRepository,
            SettlementService settlementService,
            TransactionRepository transactionRepository
    ) {
        this(accountRepository, settlementService, transactionRepository, null, null, null, null);
    }

    public ApiController(
            AccountRepository accountRepository,
            SettlementService settlementService,
            TransactionRepository transactionRepository,
            MeshSimulatorService meshSimulatorService
    ) {
        this(accountRepository, settlementService, transactionRepository, meshSimulatorService, null, null, null);
    }

    public ApiController(
            AccountRepository accountRepository,
            SettlementService settlementService,
            TransactionRepository transactionRepository,
            MeshSimulatorService meshSimulatorService,
            ReconciliationService reconciliationService
    ) {
        this(accountRepository, settlementService, transactionRepository, meshSimulatorService, reconciliationService, null, null);
    }

    @GetMapping("/accounts")
    public List<Account> getAccounts() {
        return accountRepository.findAll();
    }

    @GetMapping("/transactions")
    public List<Transaction> getTransactions() {
        if (transactionRepository != null) {
            return transactionRepository.findAllByOrderByTimestampDesc();
        }
        return List.of();
    }

    @PostMapping("/transfer")
    public String transfer(@RequestParam String from,
                           @RequestParam String to,
                           @RequestParam BigDecimal amount) {
        settlementService.transfer(from, to, amount);
        return "OK";
    }

    @PostMapping("/mesh/transfer")
    public ResponseEntity<MeshPaymentResult> simulateMeshTransfer(
            @RequestParam String from,
            @RequestParam String to,
            @RequestParam BigDecimal amount,
            @RequestParam(defaultValue = "5") int ttl) {
        if (meshSimulatorService == null) {
            return ResponseEntity.internalServerError().build();
        }
        MeshPaymentResult result = meshSimulatorService.simulateMeshPayment(from, to, amount, ttl);
        if (result.success()) {
            return ResponseEntity.ok(result);
        } else {
            return ResponseEntity.badRequest().body(result);
        }
    }

    @GetMapping("/mesh/topology")
    public Map<String, Object> getMeshTopology() {
        if (meshSimulatorService == null) {
            return Map.of("devices", List.of(), "status", "OFFLINE");
        }
        meshSimulatorService.initDefaultTopology();
        Map<String, Object> topo = new LinkedHashMap<>();
        List<Map<String, Object>> deviceList = new ArrayList<>();
        meshSimulatorService.getDevices().values().forEach(d -> {
            Map<String, Object> dev = new LinkedHashMap<>();
            dev.put("deviceId", d.getDeviceId());
            dev.put("isBridge", d.isBridge());
            dev.put("neighbors", d.getNeighborIds());
            deviceList.add(dev);
        });
        topo.put("devices", deviceList);
        topo.put("bridgePublicKey", meshSimulatorService.getBridgePublicKey() != null);
        topo.put("status", "ONLINE");
        return topo;
    }

    @GetMapping("/reconciliation")
    public ResponseEntity<ReconciliationReport> getReconciliation() {
        if (reconciliationService != null) {
            return ResponseEntity.ok(reconciliationService.reconcile());
        }
        return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).build();
    }

    /**
     * Exposes the active backend bridge RSA public key in standard Base64-encoded X.509
     * SubjectPublicKeyInfo format for hybrid encryption key wrapping by offline mobile clients.
     */
    @GetMapping("/bridge/public-key")
    public ResponseEntity<BridgePublicKeyResponse> getBridgePublicKey() {
        if (meshSimulatorService == null) {
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).build();
        }
        PublicKey bridgePublicKey = meshSimulatorService.getBridgePublicKey();
        if (bridgePublicKey == null) {
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).build();
        }
        String base64Key = Base64.getEncoder().encodeToString(bridgePublicKey.getEncoded());
        return ResponseEntity.ok(new BridgePublicKeyResponse("RSA", "X.509", base64Key));
    }

    /**
     * Registers a sender account's RSA public verification key in the prototype registry.
     * <p>
     * PROTOTYPE TRUST BOUNDARY POLICY:
     * This endpoint registers public verification keys in the prototype SenderKeyRegistry.
     * It is designed for testing, integration, and mesh simulation. In a production deployment,
     * account-key bindings must be certified out-of-band by an identity provider or CA.
     * To prevent arbitrary key replacement / hijacking in this prototype environment:
     * - Re-registering the exact same key for an account succeeds idempotently.
     * - Attempting to register a different key for an already-registered account is rejected with HTTP 400.
     */
    @PostMapping("/keys/register")
    public ResponseEntity<KeyRegistrationResponse> registerSenderKey(
            @RequestBody(required = false) KeyRegistrationRequest request,
            @RequestParam(required = false) String accountId,
            @RequestParam(required = false) String publicKey
    ) {
        String targetAccountId = request != null && request.accountId() != null ? request.accountId() : accountId;
        String targetPublicKey = request != null && request.publicKey() != null ? request.publicKey() : publicKey;

        if (targetAccountId == null || targetAccountId.isBlank()) {
            throw new IllegalArgumentException("Account ID must not be blank");
        }
        if (targetPublicKey == null || targetPublicKey.isBlank()) {
            throw new IllegalArgumentException("Public key must not be blank");
        }

        byte[] keyBytes;
        try {
            keyBytes = Base64.getDecoder().decode(targetPublicKey.trim());
        } catch (IllegalArgumentException e) {
            throw new IllegalArgumentException("Public key must be valid Base64", e);
        }

        PublicKey parsedKey;
        try {
            KeyFactory keyFactory = KeyFactory.getInstance("RSA");
            X509EncodedKeySpec keySpec = new X509EncodedKeySpec(keyBytes);
            parsedKey = keyFactory.generatePublic(keySpec);
        } catch (Exception e) {
            throw new IllegalArgumentException("Invalid RSA public key specification: " + e.getMessage(), e);
        }

        if (!"RSA".equalsIgnoreCase(parsedKey.getAlgorithm())) {
            throw new IllegalArgumentException("Only RSA public keys are supported");
        }

        if (parsedKey instanceof RSAPublicKey rsaKey && rsaKey.getModulus().bitLength() < 2048) {
            throw new IllegalArgumentException("RSA public key must be at least 2048 bits");
        }

        String normalizedId = targetAccountId.trim().toLowerCase();
        if (senderKeyRegistry != null) {
            boolean isNew = senderKeyRegistry.registerKeyWithPolicy(normalizedId, parsedKey);
            if (!isNew) {
                return ResponseEntity.ok(new KeyRegistrationResponse(
                        "ALREADY_REGISTERED",
                        normalizedId,
                        "Public key is already registered for account: " + normalizedId
                ));
            }
        }

        return ResponseEntity.ok(new KeyRegistrationResponse(
                "REGISTERED",
                normalizedId,
                "Public key successfully registered for account: " + normalizedId
        ));
    }

    /**
     * Ingests an externally constructed MeshPacket arriving from a peer relay or client device.
     * Passes the packet through the complete cryptographic, idempotency, signature verification,
     * and atomic settlement pipeline.
     */
    @PostMapping("/mesh/ingest")
    public ResponseEntity<MeshIngestResult> ingestMeshPacket(@RequestBody MeshPacket packet) throws GeneralSecurityException {
        if (packet == null) {
            throw new IllegalArgumentException("MeshPacket must not be null");
        }
        if (packet.payload() == null) {
            throw new IllegalArgumentException("EncryptedPacket payload must not be null");
        }

        BridgeIngestionService ingestionService = bridgeIngestionService != null
                ? bridgeIngestionService
                : (meshSimulatorService != null ? meshSimulatorService.getBridgeIngestionService() : null);

        if (ingestionService == null || meshSimulatorService == null) {
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).build();
        }

        PrivateKey bridgePrivateKey = meshSimulatorService.getBridgePrivateKey();
        if (bridgePrivateKey == null) {
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).build();
        }

        PaymentInstruction settled = ingestionService.ingest(packet, bridgePrivateKey);

        return ResponseEntity.ok(new MeshIngestResult(
                true,
                "SETTLED",
                settled.paymentId(),
                packet.packetId(),
                settled.fromAccount(),
                settled.toAccount(),
                settled.amount(),
                "Payment instruction settled successfully"
        ));
    }

    @ExceptionHandler(DuplicatePacketException.class)
    public ResponseEntity<String> handleDuplicatePacket(DuplicatePacketException e) {
        log.warn("Duplicate packet rejected: {}", e.getMessage());
        return ResponseEntity.badRequest().body(e.getMessage());
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<String> handleBadRequest(IllegalArgumentException e) {
        log.warn("Bad request parameter: {}", e.getMessage());
        return ResponseEntity.badRequest().body(e.getMessage());
    }

    @ExceptionHandler(IllegalStateException.class)
    public ResponseEntity<String> handleIllegalState(IllegalStateException e) {
        log.warn("Illegal state during request: {}", e.getMessage());
        return ResponseEntity.badRequest().body(e.getMessage());
    }

    @ExceptionHandler(GeneralSecurityException.class)
    public ResponseEntity<String> handleSecurityException(GeneralSecurityException e) {
        log.warn("Cryptographic verification failure: {}", e.getMessage());
        return ResponseEntity.badRequest().body("Cryptographic verification failed: " + e.getMessage());
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<String> handleGenericException(Exception e) {
        log.error("Unexpected server error: {}", e.getMessage(), e);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body("An internal error occurred. Please check system logs.");
    }
}
