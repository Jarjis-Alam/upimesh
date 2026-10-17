package com.demo.upimesh;

import com.demo.upimesh.model.AllowanceIssuanceRequest;
import com.demo.upimesh.model.OfflineAllowance;
import com.demo.upimesh.model.OfflineAllowanceRefundResult;
import com.demo.upimesh.model.OfflineAllowanceVoucherResponse;
import com.demo.upimesh.model.OfflineSecurityEvent;
import com.demo.upimesh.model.OfflineSpendPayment;
import com.demo.upimesh.model.OfflineSpendRecord;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.security.GeneralSecurityException;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * REST controller managing offline allowance issuance, spending settlement, voucher retrieval,
 * fraud audit logs, and public key discovery.
 */
@RestController
@RequestMapping("/api/allowance")
public class OfflineAllowanceController {

    private static final Logger log = LoggerFactory.getLogger(OfflineAllowanceController.class);

    private final OfflineAllowanceService offlineAllowanceService;
    private final OfflineAllowanceSettlementService settlementService;
    private final BankAuthorityKeyService bankAuthorityKeyService;

    @Autowired
    public OfflineAllowanceController(
            OfflineAllowanceService offlineAllowanceService,
            @Autowired(required = false) OfflineAllowanceSettlementService settlementService,
            BankAuthorityKeyService bankAuthorityKeyService
    ) {
        this.offlineAllowanceService = offlineAllowanceService;
        this.settlementService = settlementService;
        this.bankAuthorityKeyService = bankAuthorityKeyService;
    }

    /**
     * Returns the authoritative Bank Authority public key for cryptographic voucher verification.
     * Enables clients to obtain and pin the bank's public key securely.
     */
    @GetMapping("/bank-public-key")
    public ResponseEntity<Map<String, String>> getBankPublicKey() {
        return ResponseEntity.ok(Map.of(
                "keyId", BankAuthorityKeyService.DEFAULT_MASTER_KEY_ID,
                "algorithm", "RSA",
                "format", "X.509",
                "publicKeyBase64", bankAuthorityKeyService.getBankPublicKeyBase64()
        ));
    }

    /**
     * Atomically issues an offline allowance, reserves funds into escrow, and returns a signed voucher.
     */
    @PostMapping("/issue")
    public ResponseEntity<OfflineAllowanceVoucherResponse> issueAllowance(
            @RequestBody AllowanceIssuanceRequest request
    ) {
        OfflineAllowance allowance = offlineAllowanceService.issueAllowance(request);
        String bankPubKeyB64 = bankAuthorityKeyService.getBankPublicKeyBase64();
        return ResponseEntity.ok(OfflineAllowanceVoucherResponse.fromEntity(allowance, bankPubKeyB64));
    }

    /**
     * Settles an offline spend record submitted by a merchant or mesh relay.
     * Atomically transfers funds from system-escrow to recipient, updates spending evidence,
     * and evaluates sequence/fraud integrity.
     */
    @PostMapping("/spend")
    public ResponseEntity<OfflineSpendPayment> settleOfflineSpend(
            @RequestBody OfflineSpendRecord record
    ) throws GeneralSecurityException {
        if (settlementService == null) {
            throw new IllegalStateException("OfflineAllowanceSettlementService is unavailable");
        }
        OfflineSpendPayment payment = settlementService.settleOfflineSpend(record);
        return ResponseEntity.ok(payment);
    }

    /**
     * Refunds unused allowance funds back to the payer account after the reconciliation window expires.
     */
    @PostMapping("/refund")
    public ResponseEntity<OfflineAllowanceRefundResult> refundUnusedAllowance(
            @RequestParam("allowanceId") String allowanceId
    ) {
        if (settlementService == null) {
            throw new IllegalStateException("OfflineAllowanceSettlementService is unavailable");
        }
        OfflineAllowanceRefundResult result = settlementService.refundUnusedAllowance(allowanceId);
        return ResponseEntity.ok(result);
    }

    /**
     * Queries the active allowance for the specified account, if one exists.
     */
    @GetMapping("/active")
    public ResponseEntity<OfflineAllowanceVoucherResponse> getActiveAllowance(
            @RequestParam("accountId") String accountId
    ) {
        Optional<OfflineAllowance> allowanceOpt = offlineAllowanceService.getActiveAllowance(accountId);
        if (allowanceOpt.isEmpty()) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND).build();
        }
        String bankPubKeyB64 = bankAuthorityKeyService.getBankPublicKeyBase64();
        return ResponseEntity.ok(OfflineAllowanceVoucherResponse.fromEntity(allowanceOpt.get(), bankPubKeyB64));
    }

    /**
     * Queries an allowance by its unique allowance ID.
     */
    @GetMapping("/{allowanceId}")
    public ResponseEntity<OfflineAllowanceVoucherResponse> getAllowanceById(
            @PathVariable("allowanceId") String allowanceId
    ) {
        Optional<OfflineAllowance> allowanceOpt = offlineAllowanceService.getAllowance(allowanceId);
        if (allowanceOpt.isEmpty()) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND).build();
        }
        String bankPubKeyB64 = bankAuthorityKeyService.getBankPublicKeyBase64();
        return ResponseEntity.ok(OfflineAllowanceVoucherResponse.fromEntity(allowanceOpt.get(), bankPubKeyB64));
    }

    /**
     * Retrieves the settled spending history for a specific allowance.
     */
    @GetMapping("/{allowanceId}/spends")
    public ResponseEntity<List<OfflineSpendPayment>> getSpendHistory(
            @PathVariable("allowanceId") String allowanceId
    ) {
        if (settlementService == null) {
            return ResponseEntity.ok(List.of());
        }
        return ResponseEntity.ok(settlementService.getSpendHistory(allowanceId));
    }

    /**
     * Retrieves detected security events and fraud alerts for a specific allowance.
     */
    @GetMapping("/{allowanceId}/security-events")
    public ResponseEntity<List<OfflineSecurityEvent>> getSecurityEvents(
            @PathVariable("allowanceId") String allowanceId
    ) {
        if (settlementService == null) {
            return ResponseEntity.ok(List.of());
        }
        return ResponseEntity.ok(settlementService.getSecurityEvents(allowanceId));
    }

    @ExceptionHandler(DuplicatePacketException.class)
    public ResponseEntity<String> handleDuplicate(DuplicatePacketException e) {
        log.warn("Duplicate offline payment rejected: {}", e.getMessage());
        return ResponseEntity.badRequest().body(e.getMessage());
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<String> handleBadRequest(IllegalArgumentException e) {
        log.warn("Allowance bad request parameter: {}", e.getMessage());
        return ResponseEntity.badRequest().body(e.getMessage());
    }

    @ExceptionHandler(IllegalStateException.class)
    public ResponseEntity<String> handleConflict(IllegalStateException e) {
        log.warn("Allowance conflict or authorization rejection: {}", e.getMessage());
        if (e.getMessage() != null && e.getMessage().contains("Active offline allowance already exists")) {
            return ResponseEntity.status(HttpStatus.CONFLICT).body(e.getMessage());
        }
        if (e.getMessage() != null && e.getMessage().contains("Conflicting offline spending history")) {
            return ResponseEntity.status(HttpStatus.CONFLICT).body(e.getMessage());
        }
        return ResponseEntity.badRequest().body(e.getMessage());
    }

    @ExceptionHandler(GeneralSecurityException.class)
    public ResponseEntity<String> handleSecurityException(GeneralSecurityException e) {
        log.warn("Cryptographic verification failure during allowance settlement: {}", e.getMessage());
        return ResponseEntity.badRequest().body("Cryptographic verification failed: " + e.getMessage());
    }
}
