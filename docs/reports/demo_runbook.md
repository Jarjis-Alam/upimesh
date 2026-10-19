# MeshPay / UPI Offline Mesh — Controlled Technical Demonstration Runbook

**Document Reference**: `docs/reports/demo_runbook.md`  
**Baseline Date**: October 17, 2026  
**Target Testbed**: Local Physical Testbed (MacBook Pro + Physical iPhone 14)  
**System Classification**: **EDUCATIONAL PROTOTYPE / RESEARCH DEMONSTRATION ONLY**  
**Core Safety Directive**: **Zero financial mutations, zero database resets, zero key rotations, zero test spends on persistent database.**

---

## 1. Operating Boundaries & Threat Model Limitations

Before demonstrating MeshPay, the operator and presentation audience must acknowledge the following architectural realities and security boundaries:

1. **Educational Prototype Status**:
   - MeshPay is a research prototype demonstrating peer-to-peer offline transport (Apple Multipeer Connectivity / AWDL), double-entry escrow reconciliation, and cross-platform cryptography (RSA-PSS with SHA-256).
   - It is **not** connected to live UPI / NPCI banking switches or real Indian Rupee funds.
2. **SEC-01 (Offline Double-Spending is an Inherent Architectural Limitation)**:
   - In disconnected peer-to-peer meshes without online bridge authorization or tamper-proof monotonic hardware counters, a compromised payer device can present validly-signed vouchers to multiple disconnected merchants.
   - The first merchant to sync with the backend bridge settles successfully; the second merchant incurs a 100% credit loss. Offline transaction finality is strictly **provisional** until bridge reconciliation.
3. **SEC-03 (Software Keychain vs. Hardware Secure Enclave)**:
   - Device keys are stored in the Apple iOS software Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
   - The Apple Secure Enclave processor lacks RSA hardware coprocessors and supports ECC NIST P-256 exclusively. Full hardware-enforced private-key attestation requires a Version 2 ECDSA migration.
4. **SEC-05 (Client-Signed Timestamps Do Not Establish Authoritative Real-World Time)**:
   - Server-side validation enforces syntactic timestamp bounds (`createdAt >= issuedAt - 5m`, allowance expiration, and sequence monotonicity).
   - However, a client-signed timestamp proves only that the private key signed that timestamp string, **not that the device clock was truthful**. Establishing trustworthy time in disconnected distributed systems without trusted hardware remains an open research problem.

---

## 2. Hardware and Network Architecture Prerequisites

### A. Physical Devices
- **Host Workstation (Merchant Bob & Bank Bridge)**:
  - MacBook Pro running macOS 14+ or 15+.
  - Active Wi-Fi and Bluetooth enabled (required for Apple Wireless Direct Link / AWDL Multipeer Connectivity).
  - Primary network interface: `en0` (Wi-Fi).
- **Client Device (Payer Alice)**:
  - Physical iPhone (e.g. iPhone 14, iOS 16+) with UPIMesh app installed.
  - Active Wi-Fi and Bluetooth enabled.
  - Registered device UUID: `85343D9B-10E3-4462-BE7F-0919CB8BA014`.

### B. Network Reachability & Dynamic LAN IP Notice
> [!IMPORTANT]
> **Do not assume `192.168.1.100` is permanent or static.**  
> `192.168.1.100` was the assigned DHCP lease on interface `en0` during the verified physical hardware run. In home or office DHCP networks, leases change upon reconnecting or switching access points.
>
> 1. Always dynamically discover the current Mac LAN IP:
>    ```bash
>    ipconfig getifaddr en0
>    ```
> 2. Ensure both the Mac and iPhone are connected to the same Wi-Fi network and subnet (with AP client isolation disabled).
> 3. If the IP differs from `192.168.1.100`, update the iPhone app's API Base URL via `APIConfiguration` in the UI to `http://<CURRENT_MAC_LAN_IP>:8080`.
> 4. Apple Multipeer Connectivity operates over peer-to-peer AWDL and Bluetooth; it functions even when Wi-Fi is disconnected, but bridge synchronization requires LAN reachability.

### C. Software & Tools
- OpenJDK 17 (`/opt/homebrew/Cellar/openjdk@17/...` or system JDK 17)
- Maven Wrapper (`./mvnw`)
- Pre-built macOS Companion App: `macos/build/UPIMeshCompanion.app`
- `curl` command line HTTP client

---

## 3. Evidence Matrix: Direct Verification vs. Historical Log Evidence

| Demonstrated Capability | Verification Method | Status |
| :--- | :--- | :--- |
| **Backend 303 Test Suite** | Inferred from isolated Gradle/Maven run log (`task-2604.log`) | **PASSED (303/303)** |
| **iOS 83 Test Suite** | Inferred from isolated test run log (`task-2700.log`) | **PASSED (83/83)** |
| **macOS Companion Build** | Verified binary at `macos/build/UPIMeshCompanion.app` | **VERIFIED (Code-Signed App Exists)** |
| **Bank Public Key Continuity** | Directly queried live REST endpoint `GET /api/allowance/bank-public-key` | **VERIFIED (`bank-authority-master`, RSA)** |
| **Historical ₹100 Settlement** | Directly queried live REST endpoint `GET /api/allowance/.../spends` | **VERIFIED (`SETTLED`, Payment ID: `dd3bd00c...`)** |
| **Voucher RSASSA-PSS Math** | Verified via standalone Java RSASSA-PSS verification script | **VERIFIED (`true`)** |
| **Persistent DB Isolation** | Checked file timestamps & size (`data/upimesh.mv.db`, 110,592 bytes) | **VERIFIED (Untouched since Oct 17 20:57)** |
| **Physical P2P AWDL Transfer** | Documented in `hardware_verification_report_100_inr.md` | **HISTORICALLY VERIFIED** |
| **Live Device Reachability** | Dynamically checked via `ipconfig getifaddr en0` | **VERIFIED (Active LAN lease detected)** |

---

## 4. Pre-Demonstration Safety Checklist

Execute these read-only checks in Terminal before starting the demonstration:

```bash
# 1. Confirm persistent database file exists, is uncorrupted, and has not been mutated
ls -la data/upimesh.mv.db
# Expected: ~110,592 bytes, last modified Oct 17 20:57

# 2. Confirm current host LAN IP address (Do not assume 192.168.1.100 is permanent)
CURRENT_IP=$(ipconfig getifaddr en0)
echo "Current Host LAN IP: ${CURRENT_IP}"
# If CURRENT_IP != 192.168.1.100, note it down for the iPhone API Base URL configuration.

# 3. Confirm Git working tree state (zero staged changes, working modifications preserved)
git status --short
```

---

## 5. Safe, Read-Only Step-by-Step Demonstration Procedure

> [!CAUTION]
> **SAFETY DIRECTIVE**: The default demonstration flow below is **strictly read-only**.  
> Do not execute HTTP POST spend submissions, allowance issuances, refunds, or transfers against the persistent database. The historical ₹100 payment was completed during hardware verification; demonstrating it consists of querying authoritative records and reviewing code-level idempotency proofs.

### Phase 1: Launch or Confirm Backend Service

1. Check if the Spring Boot backend is already running:
   ```bash
   curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/allowance/bank-public-key
   ```
   - If response is `200`, the backend is already active. Skip to step 4.
2. If the backend is not running, configure the administrative token and launch in a dedicated Terminal window:
   ```bash
   # Navigate to the repository root directory
   cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

   # Set administrative token (minimum 16 characters for production; sanitized template below)
   export UPI_MESH_ADMIN_TOKEN="<CONFIGURED_ADMIN_PAIRING_TOKEN>"

   # OPTIONAL: Bank authority key encryption at rest (AES-256-GCM)
   # Correct environment variable name: UPI_MESH_KEY_ENCRYPTION_KEY
   # Note: In development profile, unencrypted legacy database keys load safely with a warning.
   # Do NOT enable auto-migrate (upimesh.bank-authority.auto-migrate-encryption=false) to preserve DB immutability.
   # export UPI_MESH_KEY_ENCRYPTION_KEY="<AES_256_GCM_ENCRYPTION_KEY_BASE64>"

   ./mvnw spring-boot:run
   ```
3. Wait for the Spring Boot banner and `Started UpimeshApplication in ... seconds` log line.
4. **Read-Only Verification**: Query the bank authority public key endpoint:
   ```bash
   curl -s http://localhost:8080/api/allowance/bank-public-key
   ```
   **Expected Response**:
   ```json
   {
     "keyId": "bank-authority-master",
     "algorithm": "RSA",
     "publicKeyBase64": "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA..."
   }
   ```

---

### Phase 2: Launch the macOS Companion App

1. Launch the code-signed macOS Companion application:
   ```bash
   open macos/build/UPIMeshCompanion.app
   ```
2. The macOS Companion window displays:
   - **Identity**: `Merchant Bob (Mac)`
   - **Service Identifier**: `upimesh-pay`
   - **Network Bridge**: Connects to `http://localhost:8080` (or host LAN IP)
   - **Multipeer Status**: Advertising as nearby merchant peer.

---

### Phase 3: Connect Physical iPhone & Verify Configuration

1. On the physical iPhone 14, open the **UPIMesh** application.
2. Navigate to **Offline Pay**:
   - Verify the connection toggle is **ON** (Discovery mode active).
   - Under nearby peers, observe `MacBook Pro (Mac)` or `Merchant Bob (Mac)`.
   - Tap to pair. Both devices transition to **Connected**.
3. **Verify API Endpoint**:
   - In iPhone settings / network debug view, confirm Base URL matches the host LAN IP: `http://<CURRENT_MAC_LAN_IP>:8080` (default: `http://192.168.1.100:8080`).

---

### Phase 4: Inspect the Settled Historical ₹100 Payment (Read-Only)

> [!NOTE]
> The ₹100 payment (`dd3bd00c-646a-4d8d-9fb2-828505c3e9b4`) is a **historical milestone** executed on physical hardware at `2026-10-17T14:05:16Z`. It is **not** a new payment to be created during this demo.

1. **Inspect Settled Allowance Voucher State**:
   ```bash
   curl -s http://localhost:8080/api/allowance/alw-d5e534d7-fc4e-478e-82fb-2cb55be77df0
   ```
   **Expected Response**:
   - `id`: `"alw-d5e534d7-fc4e-478e-82fb-2cb55be77df0"`
   - `accountId`: `"alice"`
   - `allocatedAmount`: `100.00`
   - `spentAmount`: `100.00`
   - `remainingAmount`: `0.00`
   - `status`: `"EXHAUSTED"`
   - `lastSequenceNumber`: `1`

2. **Inspect Settled Spend Record**:
   ```bash
   curl -s http://localhost:8080/api/allowance/alw-d5e534d7-fc4e-478e-82fb-2cb55be77df0/spends
   ```
   **Expected Response**:
   ```json
   [
     {
       "paymentId": "dd3bd00c-646a-4d8d-9fb2-828505c3e9b4",
       "allowanceId": "alw-d5e534d7-fc4e-478e-82fb-2cb55be77df0",
       "payerAccountId": "alice",
       "payerDeviceId": "85343D9B-10E3-4462-BE7F-0919CB8BA014",
       "recipientAccountId": "bob",
       "amount": 100.00,
       "sequenceNumber": 1,
       "cumulativeSpentAmount": 100.00,
       "createdAt": "2026-10-17T14:05:16.895267Z",
       "settledAt": "2026-10-17T14:05:21...",
       "status": "SETTLED"
     }
   ]
   ```

---

### Phase 5: Replay Protection & Idempotency (Code Evidence)

Instead of sending live spend requests to the production database, explain the deterministic duplicate-spend processing order implemented in `OfflineAllowanceSettlementService.java` (lines 126–142):

```java
// 2. Persistent Idempotency check: paymentId uniqueness
Optional<OfflineSpendPayment> existingOpt = offlineSpendPaymentRepository.findByPaymentId(record.paymentId());
if (existingOpt.isPresent()) {
    OfflineSpendPayment existing = existingOpt.get();
    boolean matches = existing.getAllowanceId().equalsIgnoreCase(record.allowanceId())
            && existing.getPayerAccountId().equalsIgnoreCase(record.payerAccountId())
            && existing.getRecipientAccountId().equalsIgnoreCase(record.recipientAccountId())
            && existing.getAmount().compareTo(record.amount()) == 0
            && existing.getSequenceNumber() == record.sequenceNumber();
    if (!matches) {
        throw new DuplicatePacketException(
                "Conflicting payment instruction rejected: paymentId '" + record.paymentId() +
                        "' was already settled with different parameters"
        );
    }
    log.info("Idempotent replay of settled offline payment: {}", record.paymentId());
    return existing;
}
```

**Key Architectural Points to Explain**:
1. **Short-Circuit Before Ledger Transfer**:
   - The idempotency check is executed at **Step 2**, before checking allowance balances (Step 3), verifying bank voucher signatures (Step 4), verifying payer signatures (Step 6), or performing ledger transfers (Step 10).
2. **Zero Financial Mutation**:
   - Replaying the identical settled payment returns the persisted record directly (`return existing;`). Escrow is **not** debited again, and Bob is **not** credited again.
3. **HTTP 200 Return**:
   - In `OfflineAllowanceController.java` (line 93), the returned entity is wrapped in `ResponseEntity.ok(payment)`, yielding an HTTP 200 OK.
4. **Conflict Rejection**:
   - If an attacker submits the same `paymentId` with altered amounts or recipient IDs, `!matches` triggers `DuplicatePacketException` (HTTP 400 Bad Request).

---

### Phase 6: Authoritative Ledger Zero-Sum Reconciliation (Read-Only)

Demonstrate total ledger conservation across all accounts:

```bash
# Query the administrative reconciliation audit endpoint using the configured token:
curl -s http://localhost:8080/api/reconciliation -H "X-Admin-Token: ${UPI_MESH_ADMIN_TOKEN}"
```

**Authoritative Response Verified from Current Persistent State**:
```json
{
  "isReconciled": true,
  "isLedgerBalanced": true,
  "isBalancesReconciled": true,
  "structuralStatus": "BALANCED",
  "balanceStatus": "RECONCILED",
  "totalTransactionsChecked": 7,
  "totalLedgerDebits": 430.00,
  "totalLedgerCredits": 430.00,
  "systemZeroSumMaintained": true,
  "accountResults": [
    {
      "accountId": "alice",
      "openingBalance": 5000.00,
      "totalCredits": 100.00,
      "totalDebits": 230.00,
      "netMovement": -130.00,
      "expectedBalance": 4870.00,
      "actualBalance": 4870.00,
      "discrepancy": 0.00,
      "status": "RECONCILED",
      "matches": true
    },
    {
      "accountId": "bob",
      "openingBalance": 1000.00,
      "totalCredits": 130.00,
      "totalDebits": 0,
      "netMovement": 130.00,
      "expectedBalance": 1130.00,
      "actualBalance": 1130.00,
      "discrepancy": 0.00,
      "status": "RECONCILED",
      "matches": true
    },
    {
      "accountId": "carol",
      "openingBalance": 2000.00,
      "totalCredits": 0,
      "totalDebits": 0,
      "netMovement": 0,
      "expectedBalance": 2000.00,
      "actualBalance": 2000.00,
      "discrepancy": 0.00,
      "status": "RECONCILED",
      "matches": true
    },
    {
      "accountId": "system-escrow",
      "openingBalance": 0,
      "totalCredits": 200.00,
      "totalDebits": 200.00,
      "netMovement": 0.00,
      "expectedBalance": 0.00,
      "actualBalance": 0.00,
      "discrepancy": 0.00,
      "status": "RECONCILED",
      "matches": true
    }
  ],
  "discrepancies": [],
  "unverifiableAccounts": []
}
```

**Verification Summary**:
- **Total In-System Liquidity**: ₹8,000.00 conserved (Alice ₹4,870.00 + Bob ₹1,130.00 + Carol ₹2,000.00 + Escrow ₹0.00).
- **Double-Entry Equilibrium**: Total debits (`430.00`) == Total credits (`430.00`).
- **Escrow Invariant**: Fully drained (`0.00`) following settlement.

---

## 6. Failure Scenarios and Rapid Recovery

| Symptom | Root Cause | Recovery Procedure |
| :--- | :--- | :--- |
| **iPhone cannot find Mac companion peer** | Bluetooth or AWDL radio sleeping | Toggle Bluetooth off and on on both devices; toggle "Discovery" in iPhone app. |
| **`HTTP 401 Unauthorized` on `/api/reconciliation`** | Request missing or mismatched `X-Admin-Token` header | Pass the exact token configured in `UPI_MESH_ADMIN_TOKEN` at server startup (e.g. `curl -H "X-Admin-Token: <CONFIGURED_TOKEN>"`). |
| **`HTTP 404 Not Found` on `/api/allowance/active`** | Alice's ₹100 allowance is exhausted | Expected behavior. Alice has no currently active spending allowance. Query specific ID `/api/allowance/alw-d5e534d7-fc4e-478e-82fb-2cb55be77df0`. |
| **iPhone cannot reach backend bridge (`Connection Refused` or timeout)** | Host LAN IP changed via DHCP | Run `ipconfig getifaddr en0` on Mac; update the Base URL setting in the iPhone app to match the new IP. |
| **Backend startup failure: `Encryption key is strictly required`** | Started with `spring.profiles.active=prod` without key | Ensure profile is default development, or configure `UPI_MESH_KEY_ENCRYPTION_KEY`. |

---

## 7. Post-Demonstration Integrity Check

After concluding the demonstration, verify that zero ledger changes or database alterations occurred:

```bash
# 1. Query reconciliation endpoint to verify total transactions remains 7
curl -s http://localhost:8080/api/reconciliation -H "X-Admin-Token: ${UPI_MESH_ADMIN_TOKEN}" | grep '"totalTransactionsChecked":7'

# 2. Confirm database file modification timestamp and size are identical
ls -la data/upimesh.mv.db
# Expected: Exactly 110,592 bytes

# 3. Confirm Git working tree remains unchanged
git status --short
```

---

## 8. Operator Quick-Reference Card

```text
┌────────────────────────────────────────────────────────────────────────┐
│                   MESHPAY SAFE READ-ONLY DEMO CHECKLIST                │
├────────────────────────────────────────────────────────────────────────┤
│ 1. [ ] Check LAN IP: ipconfig getifaddr en0 (verify subnet match)      │
│ 2. [ ] Check DB File: ls -la data/upimesh.mv.db (~110,592 bytes)       │
│ 3. [ ] Launch/Verify Backend: curl GET /api/allowance/bank-public-key  │
│ 4. [ ] Launch Mac Companion: open macos/build/UPIMeshCompanion.app     │
│ 5. [ ] Open UPIMesh on iPhone 14; verify Multipeer P2P Connected state │
│ 6. [ ] Show Settled Historical Voucher: GET /api/allowance/alw-d5e...  │
│ 7. [ ] Show Historical ₹100 Spend Record: GET /api/allowance/.../spends │
│ 8. [ ] Explain Replay Protection: Code audit (Step 2 short-circuit)   │
│ 9. [ ] Show Zero-Sum Reconciliation: GET /api/reconciliation (430/430) │
│ 10.[ ] Disclose Boundaries: SEC-01 (Double-Spend), SEC-03, SEC-05      │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 9. Appendix: Mutation-Capable Operations (DO NOT EXECUTE IN STANDARD DEMO)

> [!WARNING]
> **MUTATION RISK: PERMANENT LEDGER ALTERATION**  
> The endpoints below execute database and balance mutations. They are documented here solely for API reference and architecture audits.  
> **NEVER execute these during a technical baseline demonstration**, as doing so will alter account balances, create new transactions, consume allowances, and invalidate the historical reconciliation baseline.

1. **`POST /api/allowance/issue`**:
   - Transfers funds from user account (`alice`) into `system-escrow`.
   - Generates and signs a new `OfflineAllowance` voucher.
   - Mutates: `Account`, `Transaction`, `OfflineAllowance`.
2. **`POST /api/allowance/spend` (Fresh Spend Record)**:
   - Validates signatures and transfers funds from `system-escrow` to merchant (`bob`).
   - Increments allowance cumulative spent amount.
   - Mutates: `Account`, `Transaction`, `OfflineAllowance`, `OfflineSpendPayment`.
3. **`POST /api/allowance/refund`**:
   - Reclaims unspent allowance funds from `system-escrow` back to the payer.
   - Closes and marks the allowance `REDEEMED`.
   - Mutates: `Account`, `Transaction`, `OfflineAllowance`.
4. **`POST /api/transfer` and `POST /api/mesh/submit`**:
   - Executes direct online or mesh ledger transfers between accounts.
   - Mutates: `Account`, `Transaction`.
