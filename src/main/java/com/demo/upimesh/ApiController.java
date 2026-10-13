package com.demo.upimesh;

import com.demo.upimesh.model.Account;
import com.demo.upimesh.model.AccountRepository;
import com.demo.upimesh.model.BridgePublicKeyResponse;
import com.demo.upimesh.model.DeviceAuthorizationRequest;
import com.demo.upimesh.model.DeviceAuthorizationResponse;
import com.demo.upimesh.model.KeyRegistrationRequest;
import com.demo.upimesh.model.KeyRegistrationResponse;
import com.demo.upimesh.model.MeshIngestResult;
import com.demo.upimesh.model.MeshPacket;
import com.demo.upimesh.model.MeshPaymentResult;
import com.demo.upimesh.model.PaymentInstruction;
import com.demo.upimesh.model.ReconciliationReport;
import com.demo.upimesh.model.SignedPaymentRequest;
import com.demo.upimesh.model.Transaction;
import com.demo.upimesh.model.TransactionRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.KeyFactory;
import java.security.MessageDigest;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.security.interfaces.RSAPublicKey;
import java.security.spec.X509EncodedKeySpec;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/api")
public class ApiController {

    private static final Logger log = LoggerFactory.getLogger(ApiController.class);

    @Value("${upimesh.admin-token:${UPI_MESH_ADMIN_TOKEN:${UPIMESH_ADMIN_TOKEN:}}}")
    private String configuredAdminToken;

    private final AccountRepository accountRepository;
    private final SettlementService settlementService;
    private final TransactionRepository transactionRepository;
    private final MeshSimulatorService meshSimulatorService;
    private final ReconciliationService reconciliationService;
    private final BridgeIngestionService bridgeIngestionService;
    private final SenderKeyRegistry senderKeyRegistry;
    private final DeviceAuthorizationRegistry deviceAuthorizationRegistry;
    private final CryptoService cryptoService;

    public void setConfiguredAdminToken(String token) {
        this.configuredAdminToken = token;
    }

    private String getEffectiveAdminToken() {
        if (configuredAdminToken != null && !configuredAdminToken.isBlank()) {
            return configuredAdminToken.trim();
        }
        String env1 = System.getenv("UPI_MESH_ADMIN_TOKEN");
        if (env1 != null && !env1.isBlank()) {
            return env1.trim();
        }
        String env2 = System.getenv("UPIMESH_ADMIN_TOKEN");
        if (env2 != null && !env2.isBlank()) {
            return env2.trim();
        }
        return null;
    }

    /**
     * Constant-time comparison between the provided pairing token and the configured administrator token.
     * Never logs the token values.
     */
    private boolean isTokenValid(String providedToken) {
        String expected = getEffectiveAdminToken();
        if (expected == null || expected.isBlank()) {
            // Development admin token is not configured; authorization endpoint is disabled
            return false;
        }
        if (providedToken == null || providedToken.isBlank()) {
            return false;
        }
        byte[] expectedBytes = expected.getBytes(StandardCharsets.UTF_8);
        byte[] providedBytes = providedToken.getBytes(StandardCharsets.UTF_8);
        return MessageDigest.isEqual(expectedBytes, providedBytes);
    }

    @Autowired
    public ApiController(
            AccountRepository accountRepository,
            SettlementService settlementService,
            TransactionRepository transactionRepository,
            MeshSimulatorService meshSimulatorService,
            @Autowired(required = false) ReconciliationService reconciliationService,
            @Autowired(required = false) BridgeIngestionService bridgeIngestionService,
            @Autowired(required = false) SenderKeyRegistry senderKeyRegistry,
            @Autowired(required = false) DeviceAuthorizationRegistry deviceAuthorizationRegistry,
            @Autowired(required = false) CryptoService cryptoService
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
        this.deviceAuthorizationRegistry = deviceAuthorizationRegistry != null
                ? deviceAuthorizationRegistry
                : new DeviceAuthorizationRegistry();
        this.cryptoService = cryptoService != null
                ? cryptoService
                : new CryptoService();
    }

    public ApiController(AccountRepository accountRepository, SettlementService settlementService) {
        this(accountRepository, settlementService, null, null, null, null, null, null, null);
    }

    public ApiController(
            AccountRepository accountRepository,
            SettlementService settlementService,
            TransactionRepository transactionRepository
    ) {
        this(accountRepository, settlementService, transactionRepository, null, null, null, null, null, null);
    }

    public ApiController(
            AccountRepository accountRepository,
            SettlementService settlementService,
            TransactionRepository transactionRepository,
            MeshSimulatorService meshSimulatorService
    ) {
        this(accountRepository, settlementService, transactionRepository, meshSimulatorService, null, null, null, null, null);
    }

    public ApiController(
            AccountRepository accountRepository,
            SettlementService settlementService,
            TransactionRepository transactionRepository,
            MeshSimulatorService meshSimulatorService,
            ReconciliationService reconciliationService
    ) {
        this(accountRepository, settlementService, transactionRepository, meshSimulatorService, reconciliationService, null, null, null, null);
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

    /**
     * Authorizes a registered device ID to debit a specific bank account under prototype trust policy.
     * <p>
     * DEVELOPMENT ACCESS CONTROL:
     * Requires a valid administrator pairing token supplied via 'X-Admin-Token' HTTP header,
     * 'Authorization: Bearer <token>' header, or request payload.
     * The expected token must be configured via the 'UPI_MESH_ADMIN_TOKEN' environment variable.
     */
    @PostMapping("/devices/authorize")
    public ResponseEntity<DeviceAuthorizationResponse> authorizeDevice(
            @RequestBody(required = false) DeviceAuthorizationRequest request,
            @RequestHeader(value = "X-Admin-Token", required = false) String adminTokenHeader,
            @RequestHeader(value = "Authorization", required = false) String authorizationHeader
    ) {
        if (request == null) {
            throw new IllegalArgumentException("DeviceAuthorizationRequest must not be null");
        }
        String deviceId = request.deviceId();
        String accountId = request.accountId();

        if (deviceId == null || deviceId.isBlank()) {
            throw new IllegalArgumentException("deviceId must not be blank");
        }
        if (accountId == null || accountId.isBlank()) {
            throw new IllegalArgumentException("accountId must not be blank");
        }

        String normDev = deviceId.trim().toLowerCase();
        String normAcc = accountId.trim().toLowerCase();

        // 1. Authenticate with Administrator Pairing Token
        String providedToken = null;
        if (adminTokenHeader != null && !adminTokenHeader.isBlank()) {
            providedToken = adminTokenHeader.trim();
        } else if (authorizationHeader != null && !authorizationHeader.isBlank()) {
            String trimmed = authorizationHeader.trim();
            if (trimmed.regionMatches(true, 0, "Bearer ", 0, 7)) {
                providedToken = trimmed.substring(7).trim();
            } else {
                providedToken = trimmed;
            }
        } else if (request.adminToken() != null && !request.adminToken().isBlank()) {
            providedToken = request.adminToken().trim();
        }

        if (!isTokenValid(providedToken)) {
            log.warn("Device authorization rejected: missing or invalid administrator token for device '{}'", normDev);
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(new DeviceAuthorizationResponse(
                    "UNAUTHORIZED",
                    normDev,
                    normAcc,
                    "Administrator pairing token is missing, invalid, or unconfigured in environment"
            ));
        }

        // 2. Device must be already registered in SenderKeyRegistry
        if (senderKeyRegistry != null && !senderKeyRegistry.hasKey(normDev)) {
            throw new IllegalArgumentException("Device '" + normDev + "' must be registered in SenderKeyRegistry before authorization");
        }

        // 3. Account must exist in AccountRepository
        if (accountRepository != null && !accountRepository.existsById(normAcc)) {
            throw new IllegalArgumentException("Account '" + normAcc + "' does not exist in ledger");
        }

        // 4. Check if already authorized (idempotent duplicate protection)
        if (deviceAuthorizationRegistry != null && deviceAuthorizationRegistry.isDeviceAuthorized(normDev, normAcc)) {
            return ResponseEntity.ok(new DeviceAuthorizationResponse(
                    "ALREADY_AUTHORIZED",
                    normDev,
                    normAcc,
                    "Device '" + normDev + "' is already authorized to debit account '" + normAcc + "'"
            ));
        }

        // 5. Authorize device in persistent registry and in-memory cache
        if (deviceAuthorizationRegistry != null) {
            deviceAuthorizationRegistry.authorizeDevice(normDev, normAcc);
        }

        return ResponseEntity.ok(new DeviceAuthorizationResponse(
                "AUTHORIZED",
                normDev,
                normAcc,
                "Device '" + normDev + "' successfully authorized to debit account '" + normAcc + "'"
        ));
    }

    public ResponseEntity<DeviceAuthorizationResponse> authorizeDevice(DeviceAuthorizationRequest request) {
        return authorizeDevice(request, null, null);
    }

    /**
     * Submits and verifies a client-constructed, device-signed PaymentInstruction under
     * the prototype asymmetric trust and device-account authorization model.
     * <p>
     * Reconstructs the canonical byte representation of the PaymentInstruction, verifies
     * the RSASSA-PSS signature against the public key registered in SenderKeyRegistry
     * for the claimed device ID, verifies that the device is authorized to debit the
     * claimed fromAccount, checks replay protection and idempotency, and settles
     * atomically on the database ledger.
     */
    @PostMapping("/mesh/submit")
    public ResponseEntity<MeshPaymentResult> submitSignedMeshPayment(
            @RequestBody SignedPaymentRequest request
    ) throws GeneralSecurityException {
        if (request == null) {
            throw new IllegalArgumentException("SignedPaymentRequest must not be null");
        }
        String deviceId = request.deviceId();
        if (deviceId == null || deviceId.isBlank()) {
            throw new IllegalArgumentException("Signer device ID must not be blank");
        }
        PaymentInstruction instruction = request.instruction();
        if (instruction == null) {
            throw new IllegalArgumentException("PaymentInstruction must not be null");
        }

        String signature = instruction.signature();
        if (signature == null || signature.isBlank()) {
            throw new IllegalArgumentException("Digital signature is missing from payment instruction");
        }

        // 1. Validate payment instruction domain rules
        if (instruction.paymentId() == null || instruction.paymentId().isBlank()) {
            throw new IllegalArgumentException("paymentId must not be blank");
        }
        if (instruction.fromAccount() == null || instruction.fromAccount().isBlank()) {
            throw new IllegalArgumentException("fromAccount must not be blank");
        }
        if (instruction.toAccount() == null || instruction.toAccount().isBlank()) {
            throw new IllegalArgumentException("toAccount must not be blank");
        }
        if (instruction.fromAccount().equalsIgnoreCase(instruction.toAccount())) {
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

        // 2. Timestamp validity window (within 24 hours in past, at most 5 minutes in future)
        Instant now = Instant.now();
        if (instruction.createdAt().isBefore(now.minus(java.time.Duration.ofHours(24)))) {
            throw new IllegalArgumentException("Payment instruction has expired");
        }
        if (instruction.createdAt().isAfter(now.plus(java.time.Duration.ofMinutes(5)))) {
            throw new IllegalArgumentException("Payment instruction timestamp is too far in the future");
        }

        String normalizedDeviceId = deviceId.trim().toLowerCase();

        // 3. Verify that device is registered in SenderKeyRegistry
        if (senderKeyRegistry == null) {
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).build();
        }
        PublicKey devicePublicKey = senderKeyRegistry.getPublicKey(normalizedDeviceId)
                .orElseThrow(() -> new IllegalArgumentException("Unknown or unregistered device: " + normalizedDeviceId));

        // 4. Reconstruct canonical bytes and verify digital signature
        byte[] canonicalBytes = instruction.toCanonicalBytes();
        boolean isSigValid = cryptoService.verifySignatureBase64(canonicalBytes, signature, devicePublicKey);
        if (!isSigValid) {
            throw new IllegalArgumentException("Invalid digital signature for device: " + normalizedDeviceId);
        }

        // 5. Verify device is authorized to debit instruction.fromAccount()
        if (deviceAuthorizationRegistry != null && !deviceAuthorizationRegistry.isDeviceAuthorized(normalizedDeviceId, instruction.fromAccount())) {
            throw new IllegalArgumentException("Device '" + normalizedDeviceId + "' is not authorized to debit account '" + instruction.fromAccount() + "'");
        }

        // 6. Compute canonical hash for idempotency tracking
        MessageDigest sha256 = MessageDigest.getInstance("SHA-256");
        String packetHash = bytesToHex(sha256.digest(canonicalBytes));

        // 7. Atomic database settlement & replay protection
        if (settlementService == null) {
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).build();
        }
        settlementService.settlePayment(instruction, packetHash);

        // 8. Return telemetry result matching client MeshPaymentResultDTO
        List<String> routeTrace = List.of(normalizedDeviceId, "carol", "bridge");
        String packetId = UUID.randomUUID().toString();
        return ResponseEntity.ok(new MeshPaymentResult(
                true,
                instruction.paymentId(),
                packetId,
                instruction.fromAccount().toLowerCase(),
                instruction.toAccount().toLowerCase(),
                instruction.amount(),
                2, // simulation rounds
                2, // hop count
                3, // remaining TTL
                routeTrace,
                null,
                null,
                null,
                "SETTLED",
                "Device-signed payment instruction verified and settled on ledger"
        ));
    }

    private static String bytesToHex(byte[] bytes) {
        StringBuilder sb = new StringBuilder();
        for (byte b : bytes) {
            sb.append(String.format("%02x", b));
        }
        return sb.toString();
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
