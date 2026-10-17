# MeshPay — Release Readiness & Security Audit Report

**Date of Audit**: October 17, 2026  
**Auditor**: Senior Systems & Security Auditor (Automated Verification)  
**Target Commit / Tree**: MeshPay Phase 2B Working Tree  
**Repository**: `/Users/munshijarjisalam/Documents/Projects/upimesh`  
**Persistent Database**: `./data/upimesh.mv.db` (Preserved intact; no reseed/reset)

---

## 1. Executive Summary & Verdict

### Final Verdict: **DEMO-READY WITH RESTRICTIONS**

MeshPay has proven **genuine peer-to-peer offline packet delivery, cryptographic integrity, and zero-sum double-entry ledger reconciliation** on physical hardware (iPhone 14 to macOS Companion to Spring Boot backend). The core financial accounting and duplicate payment protections are robust and verifiable across server restarts.

However, the system is **NOT production-ready** for open consumer or commercial deployment due to fundamental offline trust assumptions, plaintext private key storage, hardcoded network defaults, and absence of hardware attestation.

### Conditions for Demonstration:
1. **Local Demo Only**: Demonstration must be conducted in a controlled environment over a dedicated Wi-Fi/P2P network.
2. **Do Not Expose to Public Internet**: The Spring Boot backend exposes `/h2-console`, empty DB passwords, and demo administrative credentials (`demo-token-admin`).
3. **Accurate Positioning**: The offline payment demonstration must be described as an **allowance-backed cryptographic proof-of-concept using Keychain-managed RSA keys**, NOT as a hardware Secure Enclave-attested or double-spend-immune protocol.

---

## 2. Test Execution & Build Verification

Every automated test suite and build script was executed directly in the repository environment. Zero failures occurred.

| Component / Layer | Command Executed | Tests Run | Passed | Failed | Execution Time | Build Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Client Test Suite** | `./run_ios_tests.sh` | 83 | 83 | 0 | 12.4s | **PASS** |
| • *OfflinePaymentPacketTests* | *(Included in above)* | 9 | 9 | 0 | — | PASS |
| • *PeerTransportTests* | *(Included in above)* | 22 | 22 | 0 | — | PASS |
| • *ReconciliationServiceTests* | *(Included in above)* | 16 | 16 | 0 | — | PASS |
| • *OfflineAllowanceTests* | *(Included in above)* | 13 | 13 | 0 | — | PASS |
| • *MeshLedgerViewModelTests* | *(Included in above)* | 7 | 7 | 0 | — | PASS |
| • *MacCompanionTests* | *(Included in above)* | 16 | 16 | 0 | — | PASS |
| **Backend Test Suite** | `./mvnw test` | 277 | 277 | 0 | 1m 30s | **BUILD SUCCESS** |
| **macOS App Bundle** | `./build_macos_companion.sh`| — | — | — | 8.2s | **BUILD SUCCESS** |
| **Total Automated Tests** | — | **360** | **360** | **0** | — | **100% PASS** |

### Live Endpoint Post-Restart Verification (`http://127.0.0.1:8080`)
Command: `curl -s -H "X-Admin-Token: demo-token-admin" http://127.0.0.1:8080/api/accounts`
```json
[
  {"id": "alice", "balance": 4870.00, "version": 6},
  {"id": "bob", "balance": 1130.00, "version": 4},
  {"id": "carol", "balance": 2000.00, "version": 0},
  {"id": "system-escrow", "balance": 0.00, "version": 4}
]
```
Command: `curl -s -H "X-Admin-Token: demo-token-admin" http://127.0.0.1:8080/api/reconciliation`
```json
{
  "isReconciled": true,
  "isLedgerBalanced": true,
  "isBalancesReconciled": true,
  "structuralStatus": "BALANCED",
  "balanceStatus": "RECONCILED",
  "totalTransactionsChecked": 7,
  "totalLedgerDebits": 430.0,
  "totalLedgerCredits": 430.0,
  "systemZeroSumMaintained": true,
  "discrepancies": []
}
```

---

## 3. Detailed Audit Findings Matrix (Post-Remediation Status)

| Finding ID | Severity | Category | Title | Status | Affected Files & Deliverable Reports |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **SEC-01** | **CRITICAL** | Protocol / Threat Model | Disconnected Offline Double-Spending Causes 100% Merchant Loss | **BLOCKED** (Inherent architectural constraint) | `OfflineAllowanceSettlementService.java`, [docs/reports/security_remediation_phase_5.md](file:///Users/munshijarjisalam/Documents/Projects/upimesh/docs/reports/security_remediation_phase_5.md) |
| **SEC-02** | **HIGH** | Cryptography / Key Storage | Bank Authority Master Private Key Stored in Plaintext Database Column | **REMEDIATED** | `BankAuthorityKeyService.java`, `BankAuthorityCredential.java`, [docs/reports/security_remediation_phase_1_verification.md](file:///Users/munshijarjisalam/Documents/Projects/upimesh/docs/reports/security_remediation_phase_1_verification.md) |
| **SEC-03** | **HIGH** | Cryptography / Hardware Claims | Key Generation Uses Software Keychain, Not Hardware Secure Enclave | **PARTIALLY REMEDIATED** (Keychain hardened; SEP ECC roadmap defined) | `DeviceIdentityManager.swift`, [docs/reports/security_remediation_phase_4.md](file:///Users/munshijarjisalam/Documents/Projects/upimesh/docs/reports/security_remediation_phase_4.md) |
| **SEC-04** | **MEDIUM** | Authentication & Access Control | Administrative Demo Token Enabled by Default in Runtime Properties | **REMEDIATED** | `application.properties`, `FinancialSecurityService.java`, `APIConfiguration.swift`, [docs/reports/security_remediation_phase_1_verification.md](file:///Users/munshijarjisalam/Documents/Projects/upimesh/docs/reports/security_remediation_phase_1_verification.md) |
| **SEC-05** | **MEDIUM** | Temporal Validation | Client-Generated Timestamps Allow Backdated Spend Creation in Grace Window | **REMEDIATED** | `OfflineAllowanceSettlementService.java`, [docs/reports/security_remediation_phase_2.md](file:///Users/munshijarjisalam/Documents/Projects/upimesh/docs/reports/security_remediation_phase_2.md) |
| **SEC-06** | **LOW** | Authorization | Unauthenticated Sender Key Registration (`/api/keys/register`) | **REMEDIATED** | `ApiController.java`, `SecurityRemediationPhase3Test.java`, [docs/reports/security_remediation_phase_3.md](file:///Users/munshijarjisalam/Documents/Projects/upimesh/docs/reports/security_remediation_phase_3.md) |
| **SEC-07** | **LOW** | Configuration / Portability | Hardcoded Local Machine IP Addresses in Client Default Configuration | **REMEDIATED** | `APIConfiguration.swift`, `MeshWalletsView.swift`, `MeshLedgerView.swift`, [docs/reports/security_remediation_phase_6.md](file:///Users/munshijarjisalam/Documents/Projects/upimesh/docs/reports/security_remediation_phase_6.md) |
| **SEC-08** | **INFORMATIONAL** | Configuration | H2 Web Console Enabled on Localhost Without Password | **REMEDIATED** | `application.properties`, `application-prod.properties`, [docs/reports/security_remediation_phase_6.md](file:///Users/munshijarjisalam/Documents/Projects/upimesh/docs/reports/security_remediation_phase_6.md) |

---



## 4. Deep-Dive Analysis of Findings

### [SEC-01] Disconnected Offline Double-Spending Causes 100% Merchant Loss
* **Severity**: **CRITICAL** (Inherent to offline peer-to-peer spending without central coordination)
* **Affected Files**:
  - `src/main/java/com/demo/upimesh/OfflineAllowanceSettlementService.java` (lines 229–250)
  - `docs/security/security_model_and_limitations.md` (Section 3.A)
* **Evidence**:
  In `OfflineAllowanceSettlementService.java`:
  ```java
  Optional<OfflineSpendPayment> existingSeqOpt = offlineSpendPaymentRepository
          .findByAllowanceIdAndSequenceNumber(allowance.getId(), record.sequenceNumber());
  if (existingSeqOpt.isPresent()) {
      OfflineSpendPayment existingSeq = existingSeqOpt.get();
      securityAuditService.recordSecurityEventAndRevokeAllowance(
              allowance.getId(), record.payerAccountId(), record.payerDeviceId(),
              record.paymentId(), existingSeq.getPaymentId(), record.sequenceNumber(),
              "SEQUENCE_FORK_CONFLICT",
              "Duplicate sequence number ... Allowance revoked."
      );
      throw new IllegalStateException("Conflicting offline spending history detected at sequence 1! Allowance revoked.");
  }
  ```
* **Failure Scenario**:
  1. Alice reserves a ₹100 allowance voucher (`alw-001`). Alice's balance drops from ₹5,000 to ₹4,900; `system-escrow` holds ₹100.
  2. Disconnected from cellular/internet, Alice visits Merchant Bob. Alice signs Spend Record 1 (Seq 1, ₹100, Recipient: `bob`).
  3. Bob verifies the Bank Authority signature and Alice's signature offline. Bob dispenses ₹100 of physical goods to Alice.
  4. While still offline, Alice walks to Merchant Carol. Alice signs Spend Record 2 (Seq 1, ₹100, Recipient: `carol`).
  5. Carol verifies the Bank Authority signature and Alice's signature offline. Carol dispenses ₹100 of physical goods to Alice.
  6. Bob reaches the network first. `POST /api/allowance/spend` settles `PID_1`. Escrow pays Bob ₹100. Allowance status transitions to `EXHAUSTED`.
  7. Carol reaches the network later. `POST /api/allowance/spend` submits `PID_2`. Backend detects `SEQUENCE_FORK_CONFLICT` at Sequence 1. The allowance is marked `REVOKED`, and Carol's settlement request is rejected with HTTP 409 Conflict.
* **Realistic Impact**:
  **Carol suffers a 100% financial loss (unrecoverable ₹100 goods)**. The central banking ledger remains balanced, but the second merchant bears full credit risk.
* **Recommended Mitigation** *(Do not implement during audit)*:
  - Enforce low offline spend limits (e.g., maximum ₹200 per allowance).
  - Require merchants to evaluate payer risk / peer trust ratings before accepting offline payments.
  - Implement a merchant guarantee fund or loss-sharing protocol sponsored by the issuing bank.

---

### [SEC-02] Bank Authority Master Private Key Stored in Plaintext Database Column
* **Severity**: **HIGH**
* **Affected Files**:
  - `src/main/java/com/demo/upimesh/BankAuthorityKeyService.java` (lines 91–103)
  - `src/main/java/com/demo/upimesh/model/BankAuthorityCredential.java` (lines 27–28)
* **Evidence**:
  In `BankAuthorityKeyService.java`:
  ```java
  String privB64 = Base64.getEncoder().encodeToString(freshPair.getPrivate().getEncoded());
  BankAuthorityCredential cred = new BankAuthorityCredential(
          DEFAULT_MASTER_KEY_ID, pubB64, privB64, "RSA", 2048, Instant.now()
  );
  credentialRepository.save(cred);
  ```
  In `BankAuthorityCredential.java`:
  ```java
  @Column(name = "private_key_base64", nullable = false, columnDefinition = "TEXT")
  private String privateKeyBase64;
  ```
* **Realistic Impact**:
  The RSA-2048 private key used to sign all authoritative offline vouchers is written unencrypted in the H2 database (`./data/upimesh.mv.db`). Anyone with read access to the database file or local H2 console can extract the private key and forge unlimited bank vouchers for any account.
* **Recommended Mitigation** *(Do not implement during audit)*:
  - Integrate a Hardware Security Module (HSM), Cloud KMS (AWS KMS / GCP Cloud KMS), or HashiCorp Vault.
  - At minimum, apply AES-GCM envelope encryption using a master key derived from an operating system environment variable.

---

### [SEC-03] Key Generation Uses Software Keychain, Not Hardware Secure Enclave
* **Severity**: **HIGH** (Discrepancy with documentation claims)
* **Affected Files**:
  - `ios/UPIMesh/UPIMesh/DeviceIdentityManager.swift` (lines 364–375)
  - `docs/reports/hardware_verification_report_100_inr.md` (Section 1)
* **Evidence**:
  In `DeviceIdentityManager.swift`:
  ```swift
  let keyAttributes: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
      kSecAttrKeySizeInBits as String: 2048,
      kSecAttrApplicationTag as String: tagData,
      kSecAttrIsPermanent as String: true,
      kSecPrivateKeyAttrs as String: [
          kSecAttrIsPermanent as String: true,
          kSecAttrApplicationTag as String: tagData,
          kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      ]
  ]
  guard let privateKey = SecKeyCreateRandomKey(keyAttributes as CFDictionary, &error) else { ... }
  ```
  1. The key type is RSA-2048 (`kSecAttrKeyTypeRSA`). **Apple's Secure Enclave hardware coprocessor does NOT support RSA keys**. It strictly supports 256-bit elliptic curves (NIST P-256 / secp256r1 via `kSecAttrKeyTypeECSECPrimeRandom`).
  2. The query does not specify `kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave`.
  3. The key is stored in standard software Keychain SQLite storage (`kSecClassKey`).
* **Realistic Impact**:
  The key is protected by the user passcode / iOS data protection, but is **NOT isolated inside the Secure Enclave hardware chip**. On a jailbroken device or compromised operating system, the private key can be extracted.
* **Recommended Mitigation** *(Do not implement during audit)*:
  - Migrate device signing from RSA-2048 to NIST P-256 (secp256r1) with `kSecAttrTokenID: kSecAttrTokenIDSecureEnclave`.
  - Update `docs/reports/hardware_verification_report_100_inr.md` to state "Apple Keychain-managed software keys" instead of "Apple Secure Enclave".

---

### [SEC-04] Administrative Demo Token Enabled by Default in Runtime Properties
* **Severity**: **MEDIUM**
* **Affected Files**:
  - `src/main/resources/application.properties` (lines 29–31)
  - `src/main/java/com/demo/upimesh/FinancialSecurityService.java` (lines 173–193)
  - `ios/UPIMesh/UPIMesh/APIConfiguration.swift` (lines 44–50)
* **Evidence**:
  In `application.properties`:
  ```properties
  # Stage 8.14: Controlled demo authentication for local development simulator only
  upimesh.demo-auth-enabled=true
  ```
  In `FinancialSecurityService.java`:
  ```java
  private Optional<AccountPrincipal> resolveDemoToken(String token) {
      if (token.startsWith("demo-token-")) {
          String target = token.substring("demo-token-".length()).trim().toLowerCase();
          if ("admin".equalsIgnoreCase(target)) {
              return Optional.of(new AccountPrincipal("admin", Set.of(AccountPrincipal.ROLE_ADMIN)));
          }
      }
  }
  ```
  In `APIConfiguration.swift`:
  ```swift
  public var authToken: String? {
      get {
          return UserDefaults.standard.string(forKey: authTokenKey) ?? "demo-token-admin"
      }
  }
  ```
* **Realistic Impact**:
  Any HTTP client that supplies `X-Admin-Token: demo-token-admin` or `Authorization: Bearer demo-token-admin` receives full administrative privileges to query all balances, inspect all transactions, and authorize/revoke devices.
* **Recommended Mitigation** *(Do not implement during audit)*:
  - In `application.properties`, set `upimesh.demo-auth-enabled=false` by default.
  - Require an explicit, strong secret via environment variable `UPI_MESH_ADMIN_TOKEN`.

---

### [SEC-05] Client-Generated Timestamps Allow Backdated Spend Creation in Grace Window
* **Severity**: **MEDIUM**
* **Affected Files**:
  - `src/main/java/com/demo/upimesh/OfflineAllowanceSettlementService.java` (lines 210–226)
* **Evidence**:
  In `OfflineAllowanceSettlementService.java`:
  ```java
  Instant now = Instant.now(clock);
  if (record.createdAt().isAfter(now.plus(MAX_FUTURE_CLOCK_SKEW))) {
      throw new IllegalArgumentException("Payment instruction timestamp is in the future beyond allowed clock skew");
  }
  if (record.createdAt().isAfter(allowance.getExpiresAt())) {
      throw new IllegalStateException("Payment instruction was created after allowance spending deadline");
  }
  Instant gracePeriodDeadline = allowance.getExpiresAt().plus(RECONCILIATION_GRACE_PERIOD);
  if (now.isAfter(gracePeriodDeadline)) {
      throw new IllegalStateException("Late payment submission rejected: reconciliation grace period ended");
  }
  ```
* **Realistic Impact**:
  Because `record.createdAt()` is generated on the client, an attacker who possesses an expired allowance can generate a backdated `createdAt` timestamp (e.g. 1 minute before `expiresAt`). The server only checks if `record.createdAt() <= expiresAt` and `now <= expiresAt + 24h`. If the merchant does not enforce strict real-time wall-clock checks offline, the attacker can sign new spends during the 24-hour grace window.
* **Recommended Mitigation** *(Do not implement during audit)*:
  - Merchants must reject vouchers whose `expiresAt` is earlier than the merchant's local wall clock.
  - Incorporate merchant-signed arrival timestamps into the spend bundle.

---

### [SEC-06] Unauthenticated Sender Key Registration (`/api/keys/register`)
* **Severity**: **LOW**
* **Affected Files**:
  - `src/main/java/com/demo/upimesh/ApiController.java` (lines 510–567)
* **Evidence**:
  The endpoint `POST /api/keys/register` accepts `accountId` and `publicKey` without requiring administrative credentials or proof of ownership:
  ```java
  @PostMapping("/keys/register")
  public ResponseEntity<KeyRegistrationResponse> registerSenderKey(...)
  ```
* **Realistic Impact**:
  While the controller prevents key overwrites once a key is registered (`ALREADY_REGISTERED`), an attacker on the local network could race to register an unauthorized public key for an uninitialized account.
* **Recommended Mitigation** *(Do not implement during audit)*:
  - Require administrator authentication or account owner PKI certificates for initial key enrollment.

---

### [SEC-07] Hardcoded Local Machine IP Addresses in Client Default Configuration
* **Severity**: **LOW**
* **Affected Files**:
  - `ios/UPIMesh/UPIMesh/APIConfiguration.swift` (lines 15, 24)
  - `ios/UPIMesh/UPIMesh/MeshWalletsView.swift` (line 201)
  - `ios/UPIMesh/UPIMesh/MeshLedgerView.swift` (line 232)
* **Evidence**:
  In `APIConfiguration.swift`:
  ```swift
  public static let defaultBaseURL = URL(string: "http://192.168.1.100:8080")!
  ...
  !saved.contains("192.168.1.103")
  ```
* **Realistic Impact**:
  If the host computer's IP address changes via DHCP or if the code is deployed on another developer's workstation, the iOS app defaults to attempting connections against `192.168.1.100`.
* **Recommended Mitigation** *(Do not implement during audit)*:
  - Implement mDNS / Bonjour network discovery (`_upimesh-http._tcp`) or present a configuration prompt on first launch.

---

### [SEC-08] H2 Web Console Enabled on Localhost Without Password
* **Severity**: **INFORMATIONAL**
* **Affected Files**:
  - `src/main/resources/application.properties` (lines 6–7, 15–17)
* **Evidence**:
  `spring.datasource.password=` (empty)  
  `spring.h2.console.enabled=true`  
  `spring.h2.console.settings.web-allow-others=false`
* **Realistic Impact**:
  Restricted to localhost (`web-allow-others=false`), so external network callers cannot access it. However, any local process or browser on the Mac host can access `/h2-console` and inspect the database directly.
* **Recommended Mitigation** *(Do not implement during audit)*:
  - Disable `spring.h2.console.enabled` in production profiles.
  - Set a non-empty password for `sa`.

---

## 5. Security & Invariant Verification Checklist

| Security Property | Method / Inspection Target | Verified Status | Evidence |
| :--- | :--- | :--- | :--- |
| **Duplicate Payment Protection** | `OfflineAllowanceSettlementService.java` (lines 125–142) | **VERIFIED** | Replaying settled `paymentId` returns HTTP 200 with identical DTO; no secondary debit. |
| **Tampered Signature Rejection** | `OfflineAllowanceSettlementServiceTest.java`, `OfflineAllowanceTests.swift` | **VERIFIED** | Altering 1 byte in payload or signature causes `GeneralSecurityException`. |
| **Allowance Expiry Enforcement** | `OfflineAllowanceSettlementService.java` (line 214) | **VERIFIED** | Spends created after `expiresAt` are rejected fail-closed. |
| **Monotonic Sequence Enforcement**| `OfflineAllowanceSettlementService.java` (lines 229–250) | **VERIFIED** | Duplicate sequence numbers trigger `SEQUENCE_FORK_CONFLICT` and revoke allowance. |
| **Cumulative Overspend Rejection**| `OfflineAllowanceSettlementService.java` (lines 275–291) | **VERIFIED** | Spends exceeding allocated remaining limit throw `OVERSPEND_ATTEMPT`. |
| **Zero-Sum Ledger Balance** | `ReconciliationService.java`, Live DB query | **VERIFIED** | Sum of all accounts including escrow strictly equals ₹8,000.00. |
| **Restart Data Persistence** | Server kill & relaunch test | **VERIFIED** | All 4 accounts, transactions, and spend records survive clean restart. |

---

## 6. Demonstration Guidelines & Operating Boundaries

To ensure a safe and credible live demonstration:

1. **Demonstrate Supported Flows**:
   - Issue ₹100 allowance to Alice on physical iPhone (`POST /api/allowance/issue`).
   - Show Alice's available balance reducing by ₹100 and `system-escrow` holding ₹100.
   - Disable Wi-Fi/Cellular on iPhone.
   - Transmit signed ₹100 payment packet to Mac Companion over P2P Multipeer Connectivity.
   - Show Mac Companion verifying RSASSA-PSS signature and Bank Authority voucher offline.
   - Reconnect Mac Companion to backend bridge; show settlement crediting Bob ₹100 from escrow.
   - Run reconciliation endpoint (`GET /api/reconciliation`) to display zero discrepancies.

2. **Required Disclaimers During Demo**:
   - Explicitly disclose that keys are stored in the iOS software Keychain, not hardware Secure Enclave.
   - Clarify that offline payments carry merchant credit risk until ingested by the bank bridge.
   - Acknowledge that enterprise production deployment requires hardware attestation (Apple App Attest) and an HSM for Bank Authority key management.

---

## 7. Master Security Remediation & Final Release Decision (October 17, 2026)

All security findings from this initial audit were systematically remediated or formally documented in the multi-phase security roadmap:
- **SEC-01**: Formally evaluated across 5 protocol alternatives in [docs/reports/security_remediation_phase_5.md](file:///Users/munshijarjisalam/Documents/Projects/upimesh/docs/reports/security_remediation_phase_5.md). Status: **BLOCKED (Architectural Distributed Systems Limitation)**.
- **SEC-02**: AES-256-GCM encryption at rest implemented for Bank Authority master key. Status: **REMEDIATED**.
- **SEC-03**: Apple SEP silicon constraints documented (SEP supports ECC P-256 only; software Keychain hardened with `ThisDeviceOnly`; Version 2 migration designed). Status: **PARTIALLY REMEDIATED**.
- **SEC-04**: Demo admin authentication disabled by default; fail-closed guards in production profile. Status: **REMEDIATED**.
- **SEC-05**: Pre-issuance and monotonic sequence timestamp validation enforced in settlement engine. Status: **REMEDIATED**.
- **SEC-06**: Account enrollment and public key registration hardened against unauthenticated takeover. Status: **REMEDIATED**.
- **SEC-07**: Centralized dynamic `hostDescription` implemented in `APIConfiguration.swift`. Status: **REMEDIATED**.
- **SEC-08**: H2 console locked to localhost in dev, disabled in prod; loopback binding enforced. Status: **REMEDIATED**.

**Final Release Verdict**: **EDUCATIONAL PROTOTYPE / EXPERIMENTAL DEMONSTRATION READY — NOT APPROVED FOR COMMERCIAL PRODUCTION**.  
For complete verification evidence, financial persistence proofs, and test results, refer to the master deliverable: [docs/reports/security_remediation_final_report.md](file:///Users/munshijarjisalam/Documents/Projects/upimesh/docs/reports/security_remediation_final_report.md).

