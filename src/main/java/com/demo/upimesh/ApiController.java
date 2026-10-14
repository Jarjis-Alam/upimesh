package com.demo.upimesh;

import com.demo.upimesh.model.Account;
import com.demo.upimesh.model.AccountRepository;
import com.demo.upimesh.model.BridgePublicKeyResponse;
import com.demo.upimesh.model.DeviceAccountAuthorization;
import com.demo.upimesh.model.DeviceAuthorizationRequest;
import com.demo.upimesh.model.DeviceAuthorizationResponse;
import com.demo.upimesh.model.DeviceAuthorizationStatus;
import com.demo.upimesh.model.KeyRegistrationRequest;
import com.demo.upimesh.model.KeyRegistrationResponse;
import com.demo.upimesh.model.MeshIngestResult;
import com.demo.upimesh.model.MeshPacket;
import com.demo.upimesh.model.MeshPaymentResult;
import com.demo.upimesh.model.PaymentInstruction;
import com.demo.upimesh.model.PaymentStatusResponse;
import com.demo.upimesh.model.ProcessedPacket;
import com.demo.upimesh.model.ReconciliationReport;
import com.demo.upimesh.model.SignedPaymentRequest;
import com.demo.upimesh.model.AccountOwnerConsentRequest;
import com.demo.upimesh.model.Transaction;
import com.demo.upimesh.model.TransactionRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
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
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

@RestController
@RequestMapping("/api")
public class ApiController {

    private static final Logger log = LoggerFactory.getLogger(ApiController.class);

    @Value("${upimesh.admin-token:${UPI_MESH_ADMIN_TOKEN:${UPIMESH_ADMIN_TOKEN:}}}")
    private String configuredAdminToken;

    @Value("${upimesh.dev-key-provisioning-enabled:false}")
    private boolean devKeyProvisioningEnabled = false;

    @Value("${upimesh.dev-provisioning-token:${UPI_MESH_DEV_PROVISIONING_TOKEN:${UPIMESH_DEV_PROVISIONING_TOKEN:}}}")
    private String configuredDevProvisioningToken;

    private static final java.util.Set<String> ALLOWED_DEV_TEST_ACCOUNTS = java.util.Set.of("alice", "bob");

    private final AccountRepository accountRepository;
    private final SettlementService settlementService;
    private final TransactionRepository transactionRepository;
    private final MeshSimulatorService meshSimulatorService;
    private final ReconciliationService reconciliationService;
    private final BridgeIngestionService bridgeIngestionService;
    private final SenderKeyRegistry senderKeyRegistry;
    private final DeviceAuthorizationRegistry deviceAuthorizationRegistry;
    private final CryptoService cryptoService;
    private final AccountOwnerKeyRegistry accountOwnerKeyRegistry;
    private final AccountOwnerConsentService accountOwnerConsentService;

    @Autowired(required = false)
    private org.springframework.core.env.Environment environment;

    private static final java.util.Set<String> REJECTED_INSECURE_TOKENS = java.util.Set.of(
            "true", "false", "token", "dev-test-token", "admin", "password", "secret", "123456"
    );

    public void setEnvironment(org.springframework.core.env.Environment environment) {
        this.environment = environment;
    }

    public boolean isProductionEnvironment() {
        if (environment != null) {
            for (String profile : environment.getActiveProfiles()) {
                if ("prod".equalsIgnoreCase(profile) || "production".equalsIgnoreCase(profile)) {
                    return true;
                }
            }
        }
        String envProfile = System.getenv("SPRING_PROFILES_ACTIVE");
        if (envProfile != null) {
            for (String p : envProfile.split(",")) {
                if ("prod".equalsIgnoreCase(p.trim()) || "production".equalsIgnoreCase(p.trim())) {
                    return true;
                }
            }
        }
        return false;
    }

    public void setConfiguredAdminToken(String token) {
        this.configuredAdminToken = token;
    }

    public void setDevKeyProvisioningEnabled(boolean enabled) {
        if (enabled && isProductionEnvironment()) {
            log.error("CRITICAL: Attempted to enable development key provisioning in production environment! Forcing disabled.");
            this.devKeyProvisioningEnabled = false;
            return;
        }
        this.devKeyProvisioningEnabled = enabled;
    }

    public boolean isDevKeyProvisioningEnabled() {
        if (isProductionEnvironment()) {
            return false;
        }
        return this.devKeyProvisioningEnabled;
    }

    public void setConfiguredDevProvisioningToken(String token) {
        this.configuredDevProvisioningToken = token;
    }

    private String getEffectiveDevProvisioningToken() {
        if (configuredDevProvisioningToken != null && !configuredDevProvisioningToken.isBlank()) {
            return configuredDevProvisioningToken.trim();
        }
        String env1 = System.getenv("UPI_MESH_DEV_PROVISIONING_TOKEN");
        if (env1 != null && !env1.isBlank()) {
            return env1.trim();
        }
        String env2 = System.getenv("UPIMESH_DEV_PROVISIONING_TOKEN");
        if (env2 != null && !env2.isBlank()) {
            return env2.trim();
        }
        return null;
    }

    private boolean isDevProvisioningAuthorized(String devTokenHeader) {
        if (isProductionEnvironment()) {
            log.error("CRITICAL: Development key provisioning rejected: active environment is production (fail-closed)");
            return false;
        }
        String configuredToken = getEffectiveDevProvisioningToken();
        if (configuredToken == null || configuredToken.isBlank()) {
            log.warn("Development key provisioning rejected: dev provisioning token is not configured (fail-closed)");
            return false;
        }
        if (REJECTED_INSECURE_TOKENS.contains(configuredToken.toLowerCase())) {
            log.error("CRITICAL: Insecure placeholder development provisioning token detected ('{}'). Fails closed.", configuredToken);
            return false;
        }
        String adminToken = getEffectiveAdminToken();
        if (adminToken != null && !adminToken.isBlank()) {
            byte[] expBytes = configuredToken.getBytes(StandardCharsets.UTF_8);
            byte[] admBytes = adminToken.trim().getBytes(StandardCharsets.UTF_8);
            if (MessageDigest.isEqual(expBytes, admBytes)) {
                log.error("CRITICAL: Development provisioning secret is identical to administrator pairing token! Token confusion / credential reuse detected. Fails closed.");
                return false;
            }
        }
        if (devTokenHeader == null || devTokenHeader.isBlank()) {
            return false;
        }
        byte[] expected = configuredToken.getBytes(StandardCharsets.UTF_8);
        byte[] provided = devTokenHeader.trim().getBytes(StandardCharsets.UTF_8);
        return MessageDigest.isEqual(expected, provided);
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
            @Autowired(required = false) CryptoService cryptoService,
            @Autowired(required = false) AccountOwnerKeyRegistry accountOwnerKeyRegistry,
            @Autowired(required = false) AccountOwnerConsentService accountOwnerConsentService
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
        this.accountOwnerKeyRegistry = accountOwnerKeyRegistry != null
                ? accountOwnerKeyRegistry
                : new AccountOwnerKeyRegistry();
        this.accountOwnerConsentService = accountOwnerConsentService != null
                ? accountOwnerConsentService
                : new AccountOwnerConsentService(this.accountOwnerKeyRegistry, this.senderKeyRegistry, null, accountRepository, this.deviceAuthorizationRegistry, this.cryptoService);
    }

    public ApiController(AccountRepository accountRepository, SettlementService settlementService) {
        this(accountRepository, settlementService, null, null, null, null, null, null, null, null, null);
    }

    public ApiController(
            AccountRepository accountRepository,
            SettlementService settlementService,
            TransactionRepository transactionRepository
    ) {
        this(accountRepository, settlementService, transactionRepository, null, null, null, null, null, null, null, null);
    }

    public ApiController(
            AccountRepository accountRepository,
            SettlementService settlementService,
            TransactionRepository transactionRepository,
            MeshSimulatorService meshSimulatorService
    ) {
        this(accountRepository, settlementService, transactionRepository, meshSimulatorService, null, null, null, null, null, null, null);
    }

    public ApiController(
            AccountRepository accountRepository,
            SettlementService settlementService,
            TransactionRepository transactionRepository,
            MeshSimulatorService meshSimulatorService,
            ReconciliationService reconciliationService
    ) {
        this(accountRepository, settlementService, transactionRepository, meshSimulatorService, reconciliationService, null, null, null, null, null, null);
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
        if (isProductionEnvironment()) {
            throw new SecurityException("Direct unauthenticated transfer endpoint is disabled in production environment");
        }
        settlementService.transfer(from, to, amount);
        return "OK";
    }

    @PostMapping("/mesh/transfer")
    public ResponseEntity<MeshPaymentResult> simulateMeshTransfer(
            @RequestParam String from,
            @RequestParam String to,
            @RequestParam BigDecimal amount,
            @RequestParam(defaultValue = "5") int ttl) {
        if (isProductionEnvironment()) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }
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
     * Registers an Account-Owner public verification key.
     * Enforces prototype key immutability policy (arbitrary replacement forbidden).
     * Carol debit authorization is explicitly blocked fail-closed.
     */
    /**
     * Registers an Account-Owner public verification key.
     * <p>
     * SECURITY & TRUST-BOUNDARY ENFORCEMENT (Stage 8.8):
     * 1. Public owner-key enrollment is DISABLED by default (fail-closed) to prevent ordinary network
     *    callers from claiming an account (closing first-enrollment takeover).
     * 2. In production, account-owner identity can only be established via certified bank infrastructure
     *    (NPCI Common Library, mPIN, SIM-binding, bank PKI). Self-asserted keys or admin tokens NEVER prove ownership.
     * 3. A controlled, local-development-only provisioning path is available strictly for isolated test accounts
     *    (alice, bob) when 'upimesh.dev-key-provisioning-enabled=true' AND a valid development provisioning token
     *    ('X-Dev-Provisioning-Token') matching the configured secret is supplied.
     *    The boolean header 'X-Dev-Provisioning' is obsolete and never authorizes key provisioning by itself.
     * 4. Carol debit authorization remains strictly blocked fail-closed under all circumstances.
     * 5. Key immutability policy is strictly preserved (arbitrary key replacement forbidden).
     */
    @PostMapping("/owner/keys/register")
    public ResponseEntity<KeyRegistrationResponse> registerOwnerKey(
            @RequestBody KeyRegistrationRequest request,
            @RequestHeader(value = "X-Dev-Provisioning-Token", required = false) String devTokenHeader,
            @RequestHeader(value = "X-Dev-Provisioning", required = false) String devProvisioningHeader
    ) {
        if (request == null) {
            throw new IllegalArgumentException("KeyRegistrationRequest must not be null");
        }
        String accountId = request.accountId();
        String publicKeyBase64 = request.publicKey();
        if (accountId == null || accountId.isBlank()) {
            throw new IllegalArgumentException("accountId must not be blank");
        }
        if (publicKeyBase64 == null || publicKeyBase64.isBlank()) {
            throw new IllegalArgumentException("publicKey must not be blank");
        }

        String normalizedId = accountId.trim().toLowerCase();

        // 1. Strict Fail-Closed Check for Carol
        if ("carol".equalsIgnoreCase(normalizedId)) {
            log.warn("Blocked owner-key registration attempt for account 'carol'");
            return ResponseEntity.status(HttpStatus.FORBIDDEN).body(new KeyRegistrationResponse(
                    "FORBIDDEN",
                    normalizedId,
                    "Account-owner registration is blocked for account 'carol': cryptographic proof of account-owner consent is not implemented"
            ));
        }

        // 2. Production Mode Guard: Public owner-key enrollment is disabled
        if (isProductionEnvironment() || !devKeyProvisioningEnabled) {
            log.warn("Rejected public owner-key registration attempt for account '{}': public enrollment is disabled. Bank identity infrastructure required.", normalizedId);
            return ResponseEntity.status(HttpStatus.FORBIDDEN).body(new KeyRegistrationResponse(
                    "FORBIDDEN",
                    normalizedId,
                    "Public account-owner key enrollment is disabled: account ownership can only be established via certified bank identity infrastructure"
            ));
        }

        // 3. Controlled Development Provisioning Authorization
        if (devProvisioningHeader != null && !devProvisioningHeader.isBlank()) {
            log.warn("Ignored obsolete header 'X-Dev-Provisioning' for account '{}': boolean header cannot authorize key provisioning", normalizedId);
        }
        boolean isDevAuthorized = isDevProvisioningAuthorized(devTokenHeader);
        if (!isDevAuthorized) {
            log.warn("Rejected unauthenticated owner-key registration for '{}': missing or invalid development provisioning token", normalizedId);
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(new KeyRegistrationResponse(
                    "UNAUTHORIZED",
                    normalizedId,
                    "Ordinary network callers cannot register owner keys. Controlled development provisioning requires a valid development provisioning token."
            ));
        }

        // 4. Test Account Scope Restriction: Only authorized test accounts can be provisioned in dev mode
        if (!ALLOWED_DEV_TEST_ACCOUNTS.contains(normalizedId)) {
            log.warn("Rejected owner-key registration for non-test account '{}'. Development provisioning is restricted to authorized test accounts.", normalizedId);
            return ResponseEntity.status(HttpStatus.FORBIDDEN).body(new KeyRegistrationResponse(
                    "FORBIDDEN",
                    normalizedId,
                    "Development key provisioning is restricted to authorized test accounts (alice, bob); unauthorized account: " + normalizedId
            ));
        }

        PublicKey parsedKey;
        try {
            byte[] keyBytes = Base64.getDecoder().decode(publicKeyBase64.trim());
            KeyFactory keyFactory = KeyFactory.getInstance("RSA");
            parsedKey = keyFactory.generatePublic(new X509EncodedKeySpec(keyBytes));
        } catch (Exception e) {
            throw new IllegalArgumentException("Invalid RSA public key specification: " + e.getMessage(), e);
        }

        if (!"RSA".equalsIgnoreCase(parsedKey.getAlgorithm())) {
            throw new IllegalArgumentException("Only RSA public keys are supported");
        }

        if (parsedKey instanceof RSAPublicKey rsaKey && rsaKey.getModulus().bitLength() < 2048) {
            throw new IllegalArgumentException("RSA public key must be at least 2048 bits");
        }

        if (accountOwnerKeyRegistry != null) {
            boolean isNew = accountOwnerKeyRegistry.registerKeyWithPolicy(normalizedId, parsedKey);
            if (!isNew) {
                return ResponseEntity.ok()
                        .header("X-UPI-Mesh-Warning", "Prototype-Development-Key-Only; Not-For-Production")
                        .body(new KeyRegistrationResponse(
                                "ALREADY_REGISTERED",
                                normalizedId,
                                "Owner public key is already registered for account: " + normalizedId
                        ));
            }
        }

        return ResponseEntity.ok()
                .header("X-UPI-Mesh-Warning", "Prototype-Development-Key-Only; Not-For-Production")
                .body(new KeyRegistrationResponse(
                        "REGISTERED",
                        normalizedId,
                        "Owner public key successfully provisioned in development mode for account: " + normalizedId
                ));
    }

    public ResponseEntity<KeyRegistrationResponse> registerOwnerKey(KeyRegistrationRequest request) {
        return registerOwnerKey(request, null, null);
    }

    public ResponseEntity<KeyRegistrationResponse> registerOwnerKey(
            KeyRegistrationRequest request,
            String devTokenHeader
    ) {
        return registerOwnerKey(request, devTokenHeader, null);
    }

    public ResponseEntity<KeyRegistrationResponse> provisionDevOwnerKey(KeyRegistrationRequest request) {
        String token = getEffectiveDevProvisioningToken();
        return registerOwnerKey(request, token, null);
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

        // 2. Account-Owner Authorization Safeguard:
        // Carol debit authorization is explicitly blocked because cryptographic proof of account-owner consent is not implemented.
        // Infrastructure administrator tokens must never be misused to forge or substitute for customer account-owner consent.
        if ("carol".equalsIgnoreCase(normAcc)) {
            log.warn("Blocked device debit authorization attempt for account 'carol' from device '{}'", normDev);
            return ResponseEntity.status(HttpStatus.FORBIDDEN).body(new DeviceAuthorizationResponse(
                    "FORBIDDEN",
                    normDev,
                    normAcc,
                    "Account-owner authorization is blocked for account 'carol': cryptographic proof of account-owner consent is not implemented"
            ));
        }

        // 3. Device must be already registered in SenderKeyRegistry
        if (senderKeyRegistry != null && !senderKeyRegistry.hasKey(normDev)) {
            throw new IllegalArgumentException("Device '" + normDev + "' must be registered in SenderKeyRegistry before authorization");
        }

        // 4. Account must exist in AccountRepository
        if (accountRepository != null && !accountRepository.existsById(normAcc)) {
            throw new IllegalArgumentException("Account '" + normAcc + "' does not exist in ledger");
        }

        // 5. Input bounds and validity checks
        if (request.spendingLimit() != null && request.spendingLimit().compareTo(BigDecimal.ZERO) <= 0) {
            throw new IllegalArgumentException("spendingLimit must be greater than zero");
        }
        if (request.validityHours() != null && request.validityHours() <= 0) {
            throw new IllegalArgumentException("validityHours must be greater than zero");
        }

        // 6. Resolve Stage 8 explicit authorization parameters
        DeviceAuthorizationStatus targetStatus = request.status() != null
                ? DeviceAuthorizationStatus.fromString(request.status())
                : DeviceAuthorizationStatus.AUTHORIZED;
        BigDecimal spendingLimit = request.spendingLimit() != null
                ? request.spendingLimit()
                : new BigDecimal("10000.00");
        Instant expiresAt = request.expiresAt();
        if (expiresAt == null && request.validityHours() != null) {
            expiresAt = Instant.now().plus(request.validityHours(), ChronoUnit.HOURS);
        } else if (expiresAt == null) {
            expiresAt = Instant.now().plus(30, ChronoUnit.DAYS);
        }

        String keyFingerprint = request.keyFingerprint();
        if (keyFingerprint == null && senderKeyRegistry != null) {
            Optional<PublicKey> pubKey = senderKeyRegistry.getPublicKey(normDev);
            if (pubKey.isPresent()) {
                keyFingerprint = DeviceAuthorizationRegistry.computeFingerprint(pubKey.get());
            }
        }

        // 5. Check if already authorized with identical parameters (idempotent duplicate protection)
        if (deviceAuthorizationRegistry != null && deviceAuthorizationRegistry.isDeviceAuthorized(normDev, normAcc)
                && request.status() == null && request.spendingLimit() == null && request.validityHours() == null) {
            Optional<DeviceAccountAuthorization> existing = deviceAuthorizationRegistry.getAuthorization(normDev, normAcc);
            return ResponseEntity.ok(new DeviceAuthorizationResponse(
                    "ALREADY_AUTHORIZED",
                    normDev,
                    normAcc,
                    "Device '" + normDev + "' is already authorized to debit account '" + normAcc + "'",
                    existing.map(DeviceAccountAuthorization::getKeyFingerprint).orElse(keyFingerprint),
                    existing.map(DeviceAccountAuthorization::getSpendingLimit).orElse(spendingLimit),
                    existing.map(DeviceAccountAuthorization::getExpiresAt).orElse(expiresAt),
                    existing.map(DeviceAccountAuthorization::getAuthorizedAt).orElse(Instant.now()),
                    existing.flatMap(a -> Optional.ofNullable(a.getRevokedAt())).orElse(null)
            ));
        }

        // 6. Authorize device in persistent registry and in-memory cache
        DeviceAccountAuthorization authRecord = null;
        if (deviceAuthorizationRegistry != null) {
            authRecord = deviceAuthorizationRegistry.authorizeDevice(
                    normDev,
                    normAcc,
                    targetStatus,
                    keyFingerprint,
                    spendingLimit,
                    expiresAt
            );
        }

        return ResponseEntity.ok(new DeviceAuthorizationResponse(
                authRecord != null ? authRecord.getStatus() : targetStatus.name(),
                normDev,
                normAcc,
                "Device '" + normDev + "' successfully authorized to debit account '" + normAcc + "'",
                authRecord != null ? authRecord.getKeyFingerprint() : keyFingerprint,
                authRecord != null ? authRecord.getSpendingLimit() : spendingLimit,
                authRecord != null ? authRecord.getExpiresAt() : expiresAt,
                authRecord != null ? authRecord.getAuthorizedAt() : Instant.now(),
                authRecord != null ? authRecord.getRevokedAt() : null
        ));
    }

    public ResponseEntity<DeviceAuthorizationResponse> authorizeDevice(DeviceAuthorizationRequest request) {
        return authorizeDevice(request, null, null);
    }

    /**
     * Authorizes a device to debit an account based on a cryptographically verified Account-Owner Consent statement.
     * Binds consentId, accountId, deviceId, deviceKeyFingerprint, spendingLimit, and expiresAt.
     */
    @PostMapping("/devices/authorize/consent")
    public ResponseEntity<DeviceAuthorizationResponse> authorizeDeviceWithConsent(
            @RequestBody AccountOwnerConsentRequest request
    ) {
        if (request == null) {
            throw new IllegalArgumentException("AccountOwnerConsentRequest must not be null");
        }

        if (accountOwnerConsentService == null) {
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).build();
        }

        DeviceAccountAuthorization authRecord;
        try {
            authRecord = accountOwnerConsentService.verifyAndApplyConsent(request);
        } catch (SecurityException se) {
            log.warn("Account-owner consent verification failed: {}", se.getMessage());
            return ResponseEntity.status(HttpStatus.FORBIDDEN).body(new DeviceAuthorizationResponse(
                    "FORBIDDEN",
                    request.deviceId() != null ? request.deviceId().trim().toLowerCase() : "",
                    request.accountId() != null ? request.accountId().trim().toLowerCase() : "",
                    se.getMessage()
            ));
        }

        return ResponseEntity.ok(new DeviceAuthorizationResponse(
                authRecord.getStatus(),
                authRecord.getDeviceId(),
                authRecord.getAccountId(),
                "Device '" + authRecord.getDeviceId() + "' successfully authorized via verified account-owner consent",
                authRecord.getKeyFingerprint(),
                authRecord.getSpendingLimit(),
                authRecord.getExpiresAt(),
                authRecord.getAuthorizedAt(),
                authRecord.getRevokedAt()
        ));
    }

    @PostMapping("/devices/revoke")
    public ResponseEntity<DeviceAuthorizationResponse> revokeDevice(
            @RequestBody DeviceAuthorizationRequest request,
            @RequestHeader(value = "X-Admin-Token", required = false) String adminTokenHeader,
            @RequestHeader(value = "Authorization", required = false) String authorizationHeader
    ) {
        if (request == null) {
            throw new IllegalArgumentException("DeviceAuthorizationRequest must not be null");
        }
        String deviceId = request.deviceId();
        String accountId = request.accountId();
        if (deviceId == null || deviceId.isBlank() || accountId == null || accountId.isBlank()) {
            throw new IllegalArgumentException("deviceId and accountId must not be blank");
        }
        String normDev = deviceId.trim().toLowerCase();
        String normAcc = accountId.trim().toLowerCase();

        String providedToken = adminTokenHeader != null && !adminTokenHeader.isBlank()
                ? adminTokenHeader.trim()
                : (authorizationHeader != null ? authorizationHeader.trim() : request.adminToken());
        if (providedToken != null && providedToken.regionMatches(true, 0, "Bearer ", 0, 7)) {
            providedToken = providedToken.substring(7).trim();
        }

        if (!isTokenValid(providedToken)) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(new DeviceAuthorizationResponse(
                    "UNAUTHORIZED",
                    normDev,
                    normAcc,
                    "Administrator pairing token is missing, invalid, or unconfigured in environment"
            ));
        }

        if (deviceAuthorizationRegistry != null) {
            deviceAuthorizationRegistry.revokeDevice(normDev, normAcc);
        }

        Optional<DeviceAccountAuthorization> authOpt = deviceAuthorizationRegistry != null
                ? deviceAuthorizationRegistry.getAuthorization(normDev, normAcc)
                : Optional.empty();

        return ResponseEntity.ok(new DeviceAuthorizationResponse(
                "REVOKED",
                normDev,
                normAcc,
                "Device '" + normDev + "' authorization for account '" + normAcc + "' has been revoked",
                authOpt.map(DeviceAccountAuthorization::getKeyFingerprint).orElse(null),
                authOpt.map(DeviceAccountAuthorization::getSpendingLimit).orElse(null),
                authOpt.map(DeviceAccountAuthorization::getExpiresAt).orElse(null),
                authOpt.map(DeviceAccountAuthorization::getAuthorizedAt).orElse(null),
                authOpt.map(DeviceAccountAuthorization::getRevokedAt).orElse(Instant.now())
        ));
    }

    @GetMapping("/devices/authorizations/{deviceId}/{accountId}")
    public ResponseEntity<DeviceAuthorizationResponse> getDeviceAccountAuthorization(
            @PathVariable("deviceId") String deviceId,
            @PathVariable("accountId") String accountId,
            @RequestHeader(value = "X-Admin-Token", required = false) String adminTokenHeader,
            @RequestHeader(value = "Authorization", required = false) String authorizationHeader
    ) {
        if (deviceId == null || deviceId.isBlank() || accountId == null || accountId.isBlank()) {
            throw new IllegalArgumentException("deviceId and accountId must not be blank");
        }
        String normDev = deviceId.trim().toLowerCase();
        String normAcc = accountId.trim().toLowerCase();

        // Require administrator authentication to prevent unauthenticated information disclosure and account enumeration
        String providedToken = adminTokenHeader != null && !adminTokenHeader.isBlank()
                ? adminTokenHeader.trim()
                : (authorizationHeader != null ? authorizationHeader.trim() : null);
        if (providedToken != null && providedToken.regionMatches(true, 0, "Bearer ", 0, 7)) {
            providedToken = providedToken.substring(7).trim();
        }

        if (!isTokenValid(providedToken)) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(new DeviceAuthorizationResponse(
                    "UNAUTHORIZED",
                    normDev,
                    normAcc,
                    "Administrator pairing token is missing, invalid, or unconfigured in environment"
            ));
        }

        Optional<DeviceAccountAuthorization> authOpt = deviceAuthorizationRegistry != null
                ? deviceAuthorizationRegistry.getAuthorization(normDev, normAcc)
                : Optional.empty();

        if (authOpt.isEmpty()) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND).body(new DeviceAuthorizationResponse(
                    "NOT_FOUND",
                    normDev,
                    normAcc,
                    "No authorization record found for device '" + normDev + "' and account '" + normAcc + "'"
            ));
        }

        DeviceAccountAuthorization auth = authOpt.get();
        return ResponseEntity.ok(new DeviceAuthorizationResponse(
                auth.getStatus(),
                normDev,
                normAcc,
                "Authorization status: " + auth.getStatus(),
                auth.getKeyFingerprint(),
                auth.getSpendingLimit(),
                auth.getExpiresAt(),
                auth.getAuthorizedAt(),
                auth.getRevokedAt()
        ));
    }

    public ResponseEntity<DeviceAuthorizationResponse> getDeviceAccountAuthorization(String deviceId, String accountId) {
        return getDeviceAccountAuthorization(deviceId, accountId, null, null);
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
            @RequestBody SignedPaymentRequest request,
            @RequestHeader(value = "X-Idempotent-Replay", required = false) String idempotentHeader,
            @RequestParam(value = "idempotent", required = false, defaultValue = "false") boolean idempotentParam
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

        // 5. Compute canonical hash for idempotency tracking
        MessageDigest sha256 = MessageDigest.getInstance("SHA-256");
        String packetHash = bytesToHex(sha256.digest(canonicalBytes));

        // 6. Check if explicit idempotent replay is requested and payment is demonstrably already settled
        boolean allowIdempotentReplay = idempotentParam || "true".equalsIgnoreCase(idempotentHeader);
        if (allowIdempotentReplay && settlementService != null) {
            Optional<ProcessedPacket> existingOpt = settlementService.findSettledPayment(instruction.paymentId());
            if (existingOpt.isPresent()) {
                ProcessedPacket existing = existingOpt.get();
                boolean matches = existing.getFromAccount().equalsIgnoreCase(instruction.fromAccount())
                        && (existing.getToAccount() == null || existing.getToAccount().equalsIgnoreCase(instruction.toAccount()))
                        && (existing.getAmount() == null || existing.getAmount().compareTo(instruction.amount()) == 0)
                        && existing.getNonce().equals(instruction.nonce())
                        && existing.getPacketHash().equalsIgnoreCase(packetHash)
                        && "SETTLED".equalsIgnoreCase(existing.getStatus());
                if (!matches) {
                    throw new DuplicatePacketException(
                            "Conflicting payment instruction rejected: paymentId '" + instruction.paymentId() + "' was already settled with different instruction parameters"
                    );
                }
                List<String> routeTrace = List.of(normalizedDeviceId, "carol", "bridge");
                String packetId = UUID.randomUUID().toString();
                return ResponseEntity.ok(new MeshPaymentResult(
                        true,
                        instruction.paymentId(),
                        packetId,
                        instruction.fromAccount().toLowerCase(),
                        instruction.toAccount().toLowerCase(),
                        instruction.amount(),
                        2,
                        2,
                        3,
                        routeTrace,
                        null,
                        null,
                        null,
                        "SETTLED",
                        "Payment instruction already settled on ledger (idempotent replay)"
                ));
            }
        }

        // 7. Atomic database settlement & replay protection coordinated under authorization lock
        if (deviceAuthorizationRegistry == null || settlementService == null) {
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).build();
        }
        try {
            deviceAuthorizationRegistry.executeWithAuthorization(
                    normalizedDeviceId,
                    instruction.fromAccount(),
                    instruction.amount(),
                    devicePublicKey,
                    () -> {
                        settlementService.settlePayment(instruction, packetHash);
                        return null;
                    }
            );
        } catch (OptimisticLockingFailureException e) {
            throw new IllegalStateException("Concurrent ledger update conflict on account; please retry transaction", e);
        } catch (DataIntegrityViolationException e) {
            if (allowIdempotentReplay) {
                Optional<ProcessedPacket> raced = settlementService.findSettledPayment(instruction.paymentId());
                if (raced.isPresent() && raced.get().getPacketHash().equalsIgnoreCase(packetHash) && "SETTLED".equalsIgnoreCase(raced.get().getStatus())) {
                    List<String> routeTrace = List.of(normalizedDeviceId, "carol", "bridge");
                    String packetId = UUID.randomUUID().toString();
                    return ResponseEntity.ok(new MeshPaymentResult(
                            true,
                            instruction.paymentId(),
                            packetId,
                            instruction.fromAccount().toLowerCase(),
                            instruction.toAccount().toLowerCase(),
                            instruction.amount(),
                            2,
                            2,
                            3,
                            routeTrace,
                            null,
                            null,
                            null,
                            "SETTLED",
                            "Payment instruction settled concurrently on ledger"
                    ));
                }
            }
            throw new DuplicatePacketException("Duplicate payment rejected by database constraint: " + instruction.paymentId(), e);
        }

        // 9. Return telemetry result matching client MeshPaymentResultDTO
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

    public ResponseEntity<MeshPaymentResult> submitSignedMeshPayment(SignedPaymentRequest request) throws GeneralSecurityException {
        return submitSignedMeshPayment(request, null, false);
    }

    /**
     * Authoritatively queries the settlement status of a payment instruction by its unique payment ID.
     * Distinguishes committed transactions from ambiguous network or client states.
     */
    @GetMapping("/mesh/status/{paymentId}")
    public ResponseEntity<PaymentStatusResponse> getPaymentStatus(@PathVariable("paymentId") String paymentId) {
        if (paymentId == null || paymentId.isBlank()) {
            throw new IllegalArgumentException("paymentId must not be blank");
        }
        String cleanId = paymentId.trim();
        Optional<ProcessedPacket> recordOpt = settlementService != null
                ? settlementService.findSettledPayment(cleanId)
                : Optional.empty();

        if (recordOpt.isEmpty()) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND).body(new PaymentStatusResponse(
                    false,
                    cleanId,
                    "NOT_FOUND",
                    null,
                    null,
                    null,
                    null,
                    null,
                    "Payment instruction not found on ledger"
            ));
        }

        ProcessedPacket p = recordOpt.get();
        return ResponseEntity.ok(new PaymentStatusResponse(
                true,
                p.getPaymentId(),
                p.getStatus(),
                p.getFromAccount(),
                p.getToAccount(),
                p.getAmount(),
                p.getPacketHash(),
                p.getSettledAt(),
                "Payment instruction authoritatively settled on ledger"
        ));
    }

    @GetMapping("/mesh/status")
    public ResponseEntity<PaymentStatusResponse> getPaymentStatusByParam(@RequestParam("paymentId") String paymentId) {
        return getPaymentStatus(paymentId);
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

    @ExceptionHandler(DataIntegrityViolationException.class)
    public ResponseEntity<String> handleDataIntegrityViolation(DataIntegrityViolationException e) {
        log.warn("Database constraint violation during request: {}", e.getMessage());
        return ResponseEntity.badRequest().body("Database constraint violation: duplicate or conflicting record");
    }

    @ExceptionHandler(OptimisticLockingFailureException.class)
    public ResponseEntity<String> handleOptimisticLocking(OptimisticLockingFailureException e) {
        log.warn("Optimistic locking conflict during request: {}", e.getMessage());
        return ResponseEntity.status(HttpStatus.CONFLICT).body("Concurrent ledger update conflict on account; please retry");
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

    @ExceptionHandler(SecurityException.class)
    public ResponseEntity<String> handleSecurityException(SecurityException e) {
        log.warn("Security rejection: {}", e.getMessage());
        return ResponseEntity.status(HttpStatus.FORBIDDEN).body(e.getMessage());
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<String> handleGenericException(Exception e) {
        log.error("Unexpected server error: {}", e.getMessage(), e);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body("An internal error occurred. Please check system logs.");
    }
}
