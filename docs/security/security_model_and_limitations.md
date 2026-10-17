# MeshPay Security Model, Threat Analysis & Remaining Limitations

## 1. System Overview & Trust Boundaries

MeshPay implements an allowance-backed offline payment protocol over peer-to-peer mesh transports (Apple Multipeer Connectivity / Bluetooth LE) settling asynchronously to a Spring Boot double-entry ledger.

### Key Actors & Cryptographic Assets
1. **Bank Authority**: Holds a master RSA-2048 signing key pair. Signs offline allowance vouchers.
2. **Payer (Alice on iOS)**: Holds a hardware-backed key pair (RSASSA-PSS SHA-256) registered in the persistent device registry. Receives bank-signed allowance vouchers and signs offline spending records sequentially.
3. **Payee / Merchant (Bob on macOS)**: P2P receiver that mathematically verifies the Bank's voucher signature and the Payer's device signature offline before accepting a payment.
4. **Mesh Relay Nodes (e.g., Carol)**: Intermediate nodes forwarding packets across multi-hop links.
5. **Bank Settlement Bridge**: Online HTTP ingest service that validates signatures, verifies monotonic sequence numbers and cumulative limits, and executes atomic double-entry balance transfers from `system-escrow` to the payee.

---

## 2. Proven Security Properties (Milestone Verification)

The physical hardware test and automated test suites (344 tests) have verified the following guarantees:

1. **Cryptographic Authenticity**:
   - Payer spending packets cannot be forged without the payer's private key (`RSASSA-PSS SHA-256`).
   - Allowance vouchers cannot be forged or tampered with without the Bank Authority's private key.
2. **Zero-Sum Ledger Invariant**:
   - Issuance atomically debits the payer's available balance and credits `system-escrow`.
   - Settlement atomically debits `system-escrow` and credits the recipient.
   - At no point can unbacked money be created or destroyed.
3. **Idempotency & Replay Protection**:
   - Duplicate submissions of the exact same payment ID or packet return HTTP 200 without duplicate credit to the payee.
4. **Post-Restart Ledger Consistency**:
   - All account balances, transactions, allowance records, and spend histories persist intact across process restarts.

---

## 3. Remaining Security Limitations (Why MeshPay is NOT Yet Production-Ready)

Despite the successful physical milestone, MeshPay currently has structural limitations inherent to disconnected offline transaction protocols:

### A. The Offline Double-Spending Window & Merchant Credit Risk
- **The Vulnerability**: When a payer is completely disconnected from the Internet, they can generate multiple validly-signed spending records referencing the same allowance voucher and distribute them to *different* offline merchants (e.g., spending ₹100 with Bob, and simultaneously spending ₹100 with Carol).
- **Current Behavior**: Both Bob and Carol can mathematically verify that the Bank Authority voucher is genuine and that the payer's signature is valid. They will both accept the payment offline.
- **Settlement Outcome**: Whichever merchant connects to the bridge and submits their packet first will be credited. When the second merchant's packet arrives, the backend detects a sequence fork or allowance exhaustion, rejects the transaction, and marks the allowance as `REVOKED` or `EXHAUSTED`.
- **Impact**: **The second offline merchant absorbs a 100% financial loss.** The central ledger is protected, but offline transaction finality is strictly **provisional**. Offline acceptance is an extension of merchant credit.

### B. Hardware Attestation & Key Protection Boundaries
- **The Vulnerability**: Currently, device keys are generated and stored via Apple Keychain / Secure Enclave APIs, but the backend does not enforce hardware attestation (e.g., Apple DeviceCheck / App Attest or Android KeyStore Attestation).
- **The Attack Vector**: An attacker running a modified jailbroken device, rooted Android emulator, or custom software could extract private keys, clone key state across multiple virtual devices, or manipulate local monotonic sequence counters to flood the network with conflicting offline vouchers.
- **Production Requirement**: Integration of Apple App Attest / Google Play Integrity to ensure keys are non-exportable and bound to hardware TPM/Secure Enclave.

### C. Offline Revocation List (CRL) Distribution
- **The Vulnerability**: If a user reports their device stolen, or if a bank revokes an active allowance due to fraud, disconnected merchants have no real-time mechanism to receive revocation notifications.
- **Current Behavior**: Merchants only check the voucher's `expiresAt` timestamp and cryptographic signature. Stolen or revoked allowances remain spendable offline until the expiry timestamp elapses.
- **Production Requirement**: A peer-to-peer gossiped compact Certificate Revocation List (CRL) or Bloom-filter-based revocation accumulator distributed across the mesh.

### D. Multi-Hop Mesh Relay Attacks (Griefing & Packet Withholding)
- **The Vulnerability**: In a decentralized mesh network, packets travel through untrusted intermediate peers.
- **Attack Vectors**:
  - **Packet Dropping / Blackholing**: An intermediary node receives a signed payment packet intended for the bridge and intentionally discards it.
  - **Packet Withholding**: An intermediary delays forwarding until the allowance voucher expires (`expiresAt`), making it impossible for the merchant to settle the payment.
- **Production Requirement**: Direct merchant-to-bridge connectivity confirmation, multi-path routing with redundant carrier relays, and end-to-end receipt acknowledgments.

### E. Clock Skew and Temporal Expiry Exploits
- **The Vulnerability**: Expiry validation relies on device clock synchronization.
- **The Risk**: A merchant whose system clock is lagging may accept an expired allowance. Conversely, a device with a clock skewed ahead may reject valid payments.
- **Production Requirement**: Enforcing narrow tolerance bounds, peer-to-peer NTP/consensus time verification, and network-enforced timestamp checking at the bridge.

### F. Allowance Exhaustion vs. Unspent Escrow Refunds
- **Current Limitation**: When an allowance expires with unspent funds, the funds remain locked in `system-escrow` until explicitly refunded. If a merchant's settlement arrives *after* an unspent refund is processed, a conflict occurs.
- **Production Requirement**: Strict grace periods between voucher expiry and escrow refund release to allow in-flight mesh packets to clear.

---

## 4. Threat Matrix & Mitigation Roadmap

| Threat / Attack Vector | Current State | Risk Level | Production Mitigation Roadmap |
| :--- | :--- | :--- | :--- |
| **Payer Signature Forgery** | **Prevented** (RSASSA-PSS SHA-256) | Low | Retain existing cryptographic standards. |
| **Bank Voucher Tampering** | **Prevented** (Pinned Bank Authority Key) | Low | Rotate authority keys with standard X.509 PKI hierarchy. |
| **Backend Balance Overdraft** | **Prevented** (Atomic Escrow Reservation) | Low | Double-entry invariant fully verified. |
| **Duplicate Packet Replay** | **Prevented** (Idempotency Hash Store) | Low | Retain persistent idempotency keys. |
| **Sequence Fork / Collusion** | **Detected at Bridge** (Allowance Revoked) | **Critical** | Merchant credit scoring, low offline spend limits (e.g. ₹500 cap), merchant liability agreements. |
| **Offline Double-Spending** | **Merchant at Risk** (First to bridge settles) | **Critical** | Dynamic risk engine, peer-to-peer gossip for spend sequence announcements, short allowance TTLs. |
| **Client Key Extraction** | **Keychain Stored** (No hardware attestation) | **High** | Apple App Attest / Android SafetyNet hardware attestation. |
| **Offline Stolen Device Usage**| **Vulnerable until Expiry** | **High** | Mesh-gossiped Bloom filter revocation lists. |
| **Relay Packet Withholding** | **Vulnerable to dropping** | **Medium** | Merchant-side local storage and direct cellular/Wi-Fi uplink retries. |

---

## 5. Conclusion & Milestone Status

MeshPay has proven **cryptographic transport integrity, secure peer-to-peer delivery, and authoritative backend reconciliation** on physical hardware. 

However, until hardware attestation, mesh revocation gossip, and merchant credit-risk controls are deployed, **MeshPay is an experimental prototype and demonstration system, not a production-ready financial settlement network.**
