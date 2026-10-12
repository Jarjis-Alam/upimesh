package com.demo.upimesh;

import com.demo.upimesh.model.Account;
import com.demo.upimesh.model.AccountRepository;
import com.demo.upimesh.model.MeshPaymentResult;
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
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.math.BigDecimal;
import java.security.GeneralSecurityException;
import java.util.ArrayList;
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

    @Autowired
    public ApiController(
            AccountRepository accountRepository,
            SettlementService settlementService,
            TransactionRepository transactionRepository,
            MeshSimulatorService meshSimulatorService,
            @Autowired(required = false) ReconciliationService reconciliationService
    ) {
        this.accountRepository = accountRepository;
        this.settlementService = settlementService;
        this.transactionRepository = transactionRepository;
        this.meshSimulatorService = meshSimulatorService;
        this.reconciliationService = reconciliationService;
    }

    public ApiController(AccountRepository accountRepository, SettlementService settlementService) {
        this(accountRepository, settlementService, null, null, null);
    }

    public ApiController(
            AccountRepository accountRepository,
            SettlementService settlementService,
            TransactionRepository transactionRepository
    ) {
        this(accountRepository, settlementService, transactionRepository, null, null);
    }

    public ApiController(
            AccountRepository accountRepository,
            SettlementService settlementService,
            TransactionRepository transactionRepository,
            MeshSimulatorService meshSimulatorService
    ) {
        this(accountRepository, settlementService, transactionRepository, meshSimulatorService, null);
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
