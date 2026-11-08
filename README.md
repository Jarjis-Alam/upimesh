<div align="center">

<img src="assets/icon.png" alt="MeshPay Icon" width="140" height="140" style="border-radius: 32px; box-shadow: 0 12px 36px rgba(0,0,0,0.6);" />

# 🌐 MeshPay / UPI Offline Mesh

### *Decentralized, Peer-to-Peer Offline Payment Routing with Dual Cryptographic Signatures, Direct Apple Wireless Multipeer Transport, Bank-Issued Allowance Vouchers, Persistent Replay Idempotency & Mathematical Double-Entry Ledger Reconciliation*

[![Java](https://img.shields.io/badge/Java-17%2B-ED8B00?style=for-the-badge&logo=openjdk&logoColor=white)](https://openjdk.org/)
[![Spring Boot](https://img.shields.io/badge/Spring_Boot-4.2.0_M2-6DB33F?style=for-the-badge&logo=spring-boot&logoColor=white)](https://spring.io/projects/spring-boot)
[![Python](https://img.shields.io/badge/Python-3.10%2B-3776AB?style=for-the-badge&logo=python&logoColor=white)](research/predictive-provisioning/)
[![Tests](https://img.shields.io/badge/Tests-429%20Passed-brightgreen?style=for-the-badge&logo=junit5&logoColor=white)](https://github.com/Jarjis-Alam/upimesh)
[![Security](https://img.shields.io/badge/Security-RSA--PSS%202048%20%7C%20AES--256--GCM-blueviolet?style=for-the-badge&logo=lock&logoColor=white)](https://github.com/Jarjis-Alam/upimesh)
[![Database](https://img.shields.io/badge/Database-H2_File--Backed-blue?style=for-the-badge&logo=database&logoColor=white)](https://github.com/Jarjis-Alam/upimesh)
[![Apple](https://img.shields.io/badge/Apple-iOS%2016%2B%20%7C%20macOS%2014%2B%20%7C%20SwiftUI-007AFF?style=for-the-badge&logo=swift&logoColor=white)](https://github.com/Jarjis-Alam/upimesh)
[![Transport](https://img.shields.io/badge/Transport-Multipeer%20Connectivity-FF9500?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/Jarjis-Alam/upimesh)
[![License](https://img.shields.io/badge/License-Apache_2.0-red?style=for-the-badge)](https://opensource.org/licenses/Apache-2.0)

<br/>

> [!IMPORTANT]
> **RESEARCH & EDUCATIONAL PROTOTYPE CLASSIFICATION**
> MeshPay / UPI Offline Mesh is an experimental academic and educational prototype exploring store-and-forward offline payment routing, cryptographic allowance vouchers, and Apple Multipeer wireless transport. It is **not affiliated with, endorsed by, or connected to the National Payments Corporation of India (NPCI), the Reserve Bank of India (RBI), or live production UPI banking rails**. All account identifiers (`alice`, `bob`, `carol`), cryptographic keys, and ledger transactions in this repository are synthetic, isolated testbed fixtures.

<br/>

[About](#-about-the-project) •
[Physical Milestone](#-physical-device-milestone-verified-100-payment) •
[Core Capabilities](#-core-capabilities) •
[System Architecture](#-system-architecture) •
[Predictive Provisioning Research](#-predictive-adaptive-offline-provisioning-research-module) •
[Judge Demo Station](#-judge-ready-demonstration--5-scenario-demo-mode) •
[Cryptographic Pipeline](#-dual-signature-cryptographic-pipeline) •
[Direct P2P Transport](#-direct-offline-peer-to-peer-transport) •
[iOS & macOS Apps](#-native-applications-macos-ipados--ios) •
[Quickstart](#-quickstart-guide) •
[API Reference](#-api-reference) •
[Reconciliation Engine](#-mathematical-reconciliation-engine) •
[Test Suite](#-test-suite--verification-429-passing-tests) •
[Security Model & Boundaries](#-security-model--threat-boundaries) •
[Documentation Index](#-documentation-index)

---

</div>

## 📖 About the Project

### The Connectivity Bottleneck in Digital Payments
The Unified Payments Interface (UPI) handles billions of transactions monthly, powering financial inclusion. However, its foundational premise is **continuous, synchronous cellular or internet connectivity** linking mobile clients, telecom infrastructure, banking switches, and the central NPCI network.

When telecom links sever, digital payments cease entirely. Critical real-world scenarios include:
- **Disaster Zones & Power Grid Outages**: Severe weather, earthquakes, or substation blackouts severing cell towers.
- **Underground Transit & Remote Topography**: Subways, basements, deep tunnels, and remote mountainous transit lacking radio penetration.
- **High-Density Congestion**: Music festivals, crowded bazaars, and stadiums where cell towers suffer radio bandwidth exhaustion.
- **Rural & Underserved Regions**: Connectivity-sparse corridors where merchant-customer proximity exists without continuous cloud backhaul.

---

### The Architecture: Allowance-Backed P2P Mesh with Authoritative Escrow
**MeshPay / UPI Offline Mesh** resolves this bottleneck through a peer-to-peer, store-and-forward architecture built on **bank-issued cryptographic allowances** and **direct device-to-device wireless transport**:

1. **Pre-Authorized Bank Allowance**: While online, the payer reserves funds from their balance into bank escrow (`system-escrow`). The banking core issues a digitally signed `OfflineAllowance` voucher authenticated with **2048-bit RSA-PSS (SHA-256)**.
2. **Dual-Signature Scheme**: Offline payments require two distinct signatures:
   - **Bank Authority Voucher Signature**: Proves the existence of genuine reserved escrow funds.
   - **Payer Device Signature**: Proves authentic instruction consent signed on-device via **2048-bit RSASSA-PSS** (with NIST P-256 Secure Enclave architecture designed for hardware attestation).
     *Note: Offline mathematical verification proves key possession, but authentic binding of a public key to an account identity requires authoritative verification against the banking registry during bridge settlement.*
3. **Zero-Internet Wireless Exchange**: The payer transmits the signed payment packet to the merchant over Apple's **Multipeer Connectivity framework** (Wi-Fi Direct / Apple Wireless Direct Link / Bluetooth Low Energy) with zero cellular, Wi-Fi router, or internet access.
4. **Deterministic Canonicalization (RFC 8785 subset)**: Custom canonical JSON serialization in Swift and Java guarantees byte-for-byte deterministic signature verification across iOS and Spring Boot.
5. **Isolated Receiver Inbox & Provisional Status**: The merchant companion records the payment in an isolated storage inbox (`RECEIVED — NOT SETTLED`) without inflating balances. An offline payment remains strictly **provisional** until bridge settlement.
6. **Delayed Bridge Settlement & Persistent Idempotency**: When a node reaches connectivity, it submits the spend record to the bank bridge. The settlement engine executes an atomic double-entry transfer from escrow to the merchant, enforces strict sequence monotonic timestamps, audits for sequence forks, and enforces persistent replay idempotency.
7. **Mathematical Double-Entry Reconciliation**: A decoupled audit engine mathematically verifies total double-entry conservation ($\sum \text{Debits} \equiv \sum \text{Credits}$) and reconciles all account closing balances against opening baselines.

---

## 🏆 Physical Device Milestone: Verified ₹100 Payment

> [!NOTE]
> **Sanitized Testbed Demonstration Data**
> All financial amounts, account handles (`alice`, `bob`, `carol`), device identifiers, and payment UUIDs shown below were generated inside an isolated, non-production testbed environment backed by a local H2 database (`./data/upimesh.mv.db`). No real-world currency, personal identifiable information (PII), or production banking rails were used.

The architecture has been proven end-to-end on **physical testbed hardware** (Physical iPhone 14 + MacBook Pro merchant node + Spring Boot backend on a persistent H2 database):

- **Payment ID**: `dd3bd00c-646a-4d8d-9fb2-828505c3e9b4`
- **Payer**: Alice (`alice`) $\rightarrow$ **Merchant**: Bob (`bob`)
- **Amount**: **₹100.00 INR** (Sequence 1)
- **Settlement Status**: `SETTLED` (Escrow debited ₹100; Bob credited ₹100)
- **Payer Post-Payment Balance**: ₹4,870.00 (from ₹5,000.00 opening balance; ₹100 settled, ₹30 prior online transfer)
- **Recipient Post-Payment Balance**: ₹1,130.00 (from ₹1,000.00 opening balance; ₹100 credited, ₹30 prior online transfer)
- **Escrow Balance**: ₹0.00 (fully settled and cleared)
- **Double-Entry Ledger Status**: **BALANCED** ($\sum \text{Debits} = \text{₹430.00} \equiv \sum \text{Credits} = \text{₹430.00}$)
- **Replay Protection**: Verified that replaying the identical payment instruction returns **HTTP 200 OK** without crediting the merchant a second time.

Detailed hardware verification data is preserved in [`docs/reports/hardware_verification_report_100_inr.md`](docs/reports/hardware_verification_report_100_inr.md).

---

## 🚀 Core Capabilities

- **🔐 Dual Cryptographic Authentications**: Bank authority voucher signing with **2048-bit RSA-PSS**; payer client signing with **2048-bit RSASSA-PSS** stored in the iOS software Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), with NIST P-256 Secure Enclave architecture designed for hardware attestation.
- **🛡️ Authenticated Key Storage at Rest**: The Bank Authority master private key is protected at rest with **AES-256-GCM** using externally provisioned secrets (`UPI_MESH_KEY_ENCRYPTION_KEY`).
- **🔒 Scoped Administrative Access Control**: Fail-closed token authentication (`UPI_MESH_ADMIN_TOKEN` / `X-Admin-Token` header) on reconciliation, sensitive audits, and device authorization.
- **📡 Direct Wireless P2P Transport (Multipeer Connectivity)**: Physical iPhones and Mac companion nodes discover peers and transfer payment packets offline over peer-to-peer Wi-Fi and Bluetooth (`_upimesh-pay._tcp`).
- **⚡ Step 2 Replay Protection & Idempotency**: Persistent database uniqueness checks intercept replayed payment IDs before balance modifications or allowance alterations, returning idempotent HTTP 200 responses.
- **⚖️ Double-Entry Ledger & Continuous Audit Engine**: Optimistic concurrency locking (`@Version`); read-only mathematical reconciliation audit checking $\sum \text{Debits} \equiv \sum \text{Credits}$ and $E(i) = B_0(i) + \Delta(i)$.
- **🚨 Sequence Fork & Fraud Detection**: Conflicting spend payments claiming the same sequence number trigger automatic `SEQUENCE_FORK_CONFLICT` security events and immediately revoke the parent allowance.
- **🔮 Predictive Adaptive Offline Provisioning**: Uncertainty-aware stochastic dynamic reserve allocation that balances outage risk, spending demand variance, liquidity lock cost, and exposure penalties to maintain high offline payment success without locking excessive funds in escrow.
- **🎬 5-Scenario Judge-Ready Demo Station**: Native macOS Companion presentation console driving simulated network degradation, grid shock injection, offline spend drawdown, and recovery sync, streaming live advisory packets over zero-internet Apple Wireless Direct Link (AWDL).
- **📱 Native Apple Clients**: Full SwiftUI iOS mobile application (**Liquid Mesh UPI**) and native code-signed macOS Companion application.

---

## 🏛️ System Architecture

```mermaid
flowchart TD
    subgraph Payer["📱 Sender Device (Alice's iPhone 14)"]
        ALW_INIT["🏦 Issue Allowance Request"] -->|POST /api/allowance/issue| BACKEND_ISSUE
        BACKEND_ISSUE --> VOUCHER["🎫 OfflineAllowanceVoucher<br/>(Signed by Bank RSA-PSS)"]
        VOUCHER --> ALW_STORE[("💾 Local Allowance Store")]
        
        ALW_STORE --> SPEND_BUILD["✍️ Sign OfflineSpendRecord<br/>(Payer 2048-bit RSA-PSS)"]
        SPEND_BUILD --> PKT_OUT["📦 OfflinePaymentPacket<br/>(Voucher + Spend Record)"]
    end

    subgraph Wireless["📡 Direct P2P Wireless Transport (Zero Internet)"]
        PKT_OUT --> ADV["📡 Multipeer Advertiser<br/>(Apple AWDL / BLE)"]
        ADV <-->|Peer-to-Peer Wi-Fi / BLE<br/>Service: _upimesh-pay._tcp| BROWSE["🔍 Multipeer Browser<br/>(Apple AWDL / BLE)"]
    end

    subgraph Receiver["💻 Merchant Device (Bob's MacBook Companion)"]
        BROWSE --> RECV_INBOX["📥 ReceivedPacketStore<br/>(Isolated Merchant Inbox)"]
        RECV_INBOX --> R_STATE["🏷️ Status: RECEIVED (Provisional)"]
        R_STATE -.->|When Bridge Reachable| SUBMIT_BRIDGE["🌉 MacBridgeClient<br/>(POST /api/allowance/spend)"]
    end

    subgraph Backend["🏦 Banking Core & Settlement Engine (Spring Boot 4.2)"]
        SUBMIT_BRIDGE --> STEP1["1. Schema & Field Validation"]
        STEP1 --> STEP2{"2. paymentId Settled?"}
        STEP2 -- "Yes (Matches)" --> IDEMP["⚡ Return Existing (HTTP 200)<br/>Zero Second Debit/Credit"]
        STEP2 -- "No" --> STEP4["4. Verify Bank Voucher Signature"]
        STEP4 --> STEP6["6. Verify Payer Device Signature"]
        STEP6 --> STEP9{"9. Sequence Conflict?"}
        STEP9 -- "Conflict" --> REVOKE["🚨 Revoke Allowance (Fraud Audit)"]
        STEP9 -- "Valid" --> STEP10["10. Atomic Double-Entry Settlement<br/>(system-escrow ➔ bob)"]
        STEP10 --> STEP12["12. Record OfflineSpendPayment<br/>Status: SETTLED"]
    end

    subgraph Audit["⚖️ Continuous Reconciliation Audit"]
        AUDIT_REQ["GET /api/reconciliation<br/>Header: X-Admin-Token"] --> RECON_SVC["⚙️ ReconciliationService"]
        RECON_SVC --> CHK_STRUCT["Check Double-Entry Invariant:<br/>sum(Debits) == sum(Credits)"]
        RECON_SVC --> CHK_BAL["Check Account Baselines:<br/>Actual == Expected(B0 + net)"]
    end
```

---

## 🔮 Predictive Adaptive Offline Provisioning (Research Module)

### The Offline Escrow Dilemma
In decentralized offline payment architectures like MeshPay, spending offline requires funds to be pre-authorized into an escrow voucher. However, users face a fundamental trade-off:
- **Over-Provisioning Penalty**: Locking substantial capital (e.g. ₹2,000+) in escrow leaves those funds unavailable for day-to-day online UPI transfers and exposes the payer to theft or loss if their physical device is compromised.
- **Under-Provisioning Shortage**: Reserving too little (e.g. ₹50) leads to payment failures when a user encounters sudden, prolonged network blackouts (e.g., subway commutes, rural transit, disaster outages).
- **Static Inefficiency**: Fixed allocations (e.g. static ₹500 allowances) ignore current network health, temporal spending rates, and prediction confidence, consistently either over-locking or under-serving.

To resolve this dilemma, we developed the **Predictive Adaptive Offline Provisioning** module located in [`research/predictive-provisioning/`](research/predictive-provisioning/). The engine models connectivity state transitions and demand distributions as stochastic processes, dynamically calculating an optimal, uncertainty-aware offline reserve recommendation.

---

### Mathematical Optimization Framework

The provisioning engine minimizes the total expected economic cost $J(R)$ over the decision horizon:

$$J(R) = \underbrace{c_s \cdot \mathbb{E}\left[\max(0, D - R)\right]}_{\text{Shortage Penalty}} + \underbrace{c_l \cdot R}_{\text{Liquidity Lock Cost}} + \underbrace{c_e \cdot \mathbb{E}\left[\min(R, D)\right]}_{\text{Exposure Penalty}}$$

Where:
- $R$ is the provisioned offline reserve.
- $D$ is the random payment demand during an outage window, modeled as $D \sim \text{Poisson}(\lambda \cdot \tau)$ or heavy-tailed log-normal in adversarial bursts.
- $p_{\text{out}}$ is the predicted probability of experiencing a connectivity outage.
- $\tau$ is the estimated outage duration (in minutes).
- $c_s$ is the unit penalty for failing an offline payment (shortage).
- $c_l$ is the opportunity cost rate of locked escrow liquidity.
- $c_e$ is the exposure penalty reflecting escrow theft or operational risk.

#### Uncertainty-Aware Allocation Model ($M_2$)
Unlike deterministic demand estimators, the $M_2$ algorithm explicitly incorporates forecast uncertainty $\sigma_D$ and situational confidence $\kappa$:

$$R^* = \min\left(B_{\text{max}},\ \max\left(R_{\text{floor}}(p_{\text{out}}, \text{profile}),\ \hat{D} + z_{\alpha} \cdot \sigma_D\right)\right)$$

Key features of this formulation:
1. **Dynamic Risk Floor ($R_{\text{floor}}$)**: When outage probability $p_{\text{out}} > 0.4$, a safety floor activates to guarantee basic survivability for essentials, even if historical spending was temporarily zero.
2. **Confidence-Scaled Quantile ($z_\alpha$)**: The uncertainty margin expands when predictive confidence is low ($\kappa \rightarrow 0$) or when network variance spikes, guarding against sudden connectivity shocks.
3. **Liquidity Conservation**: When connected to reliable 5G with low outage risk ($p_{\text{out}} < 0.1$), the engine recommends minimal or zero reserve, freeing 100% of user liquidity for standard digital banking.

---

### Empirical Validation & Benchmark Results

The system was benchmarked across **30 independent random seeds** and 1,000 simulation epochs across 4 distinct connectivity environments:

| Scenario / Profile | Strategy | Success Rate (%) | Avg Locked (₹) | Unused Reserve (₹) | Shortage (₹) | Combined Cost |
|---|---|:---:|:---:|:---:|:---:|:---:|
| **Reliable Urban 5G** | Fixed ₹500 | 99.8% | ₹500.00 | ₹482.10 | ₹0.20 | 51.4 |
| | Demand-Only | 99.4% | ₹32.40 | ₹14.80 | ₹0.80 | 12.1 |
| | **Uncertainty-Aware ($M_2$)** | **99.6%** | **₹36.80** | **₹18.20** | **₹0.50** | **11.8** *(Lowest)* |
| **Commute Subway** | Fixed ₹500 | 91.2% | ₹500.00 | ₹274.50 | ₹42.80 | 148.6 |
| | Demand-Only | 84.1% | ₹295.30 | ₹112.40 | ₹86.10 | 214.2 |
| | **Uncertainty-Aware ($M_2$)** | **94.8%** | **₹348.60** | **₹145.20** | **₹23.40** | **102.4** *(Lowest)* |
| **Rural Weak Signal** | Fixed ₹500 | 88.4% | ₹500.00 | ₹198.30 | ₹64.20 | 186.7 |
| | Demand-Only | 79.2% | ₹342.10 | ₹85.60 | ₹114.80 | 276.5 |
| | **Uncertainty-Aware ($M_2$)** | **93.7%** | **₹412.50** | **₹132.80** | **₹31.20** | **124.9** *(Lowest)* |
| **Adversarial Jamming** | Fixed ₹500 | 72.1% | ₹500.00 | ₹84.20 | ₹182.40 | 382.1 |
| | Demand-Only | 61.5% | ₹380.00 | ₹41.20 | ₹264.80 | 498.3 |
| | **Uncertainty-Aware ($M_2$)** | **88.6%** | **₹540.20** | **₹96.10** | **₹68.50** | **218.4** *(Lowest)* |

<div align="center">
  <table border="0">
    <tr>
      <td width="50%" align="center">
        <b>📈 Pareto Frontier: Availability vs Locked Liquidity</b><br/>
        <img src="research/predictive-provisioning/results/milestone3/charts/pareto_frontier.svg" alt="Pareto Frontier" width="460" /><br/>
        <sub>M2 achieves an optimal frontier position: 94%+ availability without static over-locking</sub>
      </td>
      <td width="50%" align="center">
        <b>⚡ Cold Start Convergence & Heavy Tail Response</b><br/>
        <img src="research/predictive-provisioning/results/milestone3/charts/cold_start_convergence.svg" alt="Convergence" width="460" /><br/>
        <sub>Bayesian prior updates converge within 8 epochs from cold start</sub>
      </td>
    </tr>
  </table>
</div>

---

## 🎬 Judge-Ready Demonstration & 5-Scenario Demo Mode

The predictive provisioning system is fully integrated into the live UPIMesh environment as a **Judge-Facing Demonstration Station** operating directly on the native **macOS Companion** and **iOS** applications.

```mermaid
flowchart LR
    subgraph Research["🔬 Python Research Engine (Port 8050)"]
        DEMO_ENG["⚙️ DemoEngine<br/>(Scenario States & Shocks)"]
        HTTP_SRV["🌐 demo_server.py<br/>(GET /state, POST /scenario)"]
        DEMO_ENG <--> HTTP_SRV
    end

    subgraph MacApp["💻 macOS Companion Station (Judge Console)"]
        BRIDGE["🌉 MacPredictionBridgeClient<br/>(1.0s Polling Loop)"]
        VIEW["🖥️ MacCompanionView<br/>• 5 Scenario Cards<br/>• Inject Grid Shock<br/>• Reset Demo<br/>• Live Matrix & Timeline"]
        TRANS["📡 MacPeerTransportService<br/>(MCSession AWDL / BLE)"]
        
        HTTP_SRV <-->|Loopback HTTP| BRIDGE
        BRIDGE --> VIEW
        BRIDGE -->|PeerPredictionMessage| TRANS
        TRANS -.->|PeerPredictionAck| BRIDGE
    end

    subgraph iPhone["📱 iPhone 14 Client (Zero Internet)"]
        M_TRANS["📡 MeshPeerTransportService<br/>(MCSession AWDL / BLE)"]
        ADV_CARD["💳 PredictiveAdvisoryCardView<br/>• Recommended Reserve Hero<br/>• Status: NORMAL / HIGH RISK<br/>• 4-Metric Telemetry Grid<br/>• Strategy Comparison Strip"]
        
        TRANS ===|Zero Internet AWDL / BLE<br/>Type: PREDICTION_UPDATE| M_TRANS
        M_TRANS ===|Type: PREDICTION_ACK| TRANS
        M_TRANS --> ADV_CARD
    end
```

### The 5 Guided Presentation Scenarios

Presenters can step through 5 curated, live-simulated scenarios using dedicated cards on the Mac Companion:

1. **Scenario 1 — Normal 5G (`NORMAL`)**:
   - **Network Conditions**: Fiber-backed 5G, outage probability $p_{\text{out}} = 0.05$, expected outage duration 5 minutes, zero pending demand.
   - **System Behavior**: High forecast confidence. Recommends minimal reserve (₹0–₹50).
   - **Demonstration Insight**: Proves the system doesn't unnecessarily lock user liquidity when connectivity is robust.
2. **Scenario 2 — Network Deterioration (`ELEVATED RISK`)**:
   - **Network Conditions**: Signal drops to weak cellular ($p_{\text{out}} = 0.45$), expected outage duration 20 minutes, predicted demand ₹280.
   - **System Behavior**: Uncertainty increases; reserve recommendation dynamically climbs to ₹380.
   - **Demonstration Insight**: Shows proactive anticipation *before* disconnection occurs.
3. **Scenario 3 — Grid Shock (`HIGH RISK`)**:
   - **Network Conditions**: Sudden catastrophic regional blackout ($p_{\text{out}} = 0.90$, duration 120 minutes, extreme forecast uncertainty).
   - **System Behavior**: Safety floor engages; recommended reserve expands to ₹750–₹1,000 to protect critical offline purchasing capability.
   - **One-Click Shock**: Presenter can hit `⚡️ Inject Grid Shock` from any state to immediately trigger this response.
4. **Scenario 4 — Fully Offline (`OFFLINE`)**:
   - **Network Conditions**: Complete telecom blackout ($p_{\text{out}} = 1.0$).
   - **System Behavior**: Mobile client operates purely peer-to-peer. Offline payments draw down available reserve headroom; remaining budget is dynamically tracked.
5. **Scenario 5 — Recovery & Reconciliation (`NORMAL`)**:
   - **Network Conditions**: Power and telecom restored ($p_{\text{out}} \rightarrow 0$).
   - **System Behavior**: Mac bridge submits provisional payment receipts to the bank ledger for atomic double-entry settlement. Surplus escrow is unlocked, returning unspent funds to Alice's primary balance.

### Live Mac Station Features

- **Segmented Top Switcher**: Seamlessly toggles between **`DEMO MODE`** (judge presentation dashboard) and **`PACKET INBOX`** (merchant payment store & forward).
- **Strategy Comparison Strip**: Live 4-way comparison showing:
  - *Fixed ₹500*: ₹500 constant.
  - *Demand-Only*: Based solely on $\hat{\lambda} \cdot \tau$.
  - *Uncertainty-Aware*: Full $M_2$ model with confidence interval.
  - *Actual Provisioned Reserve*: Current active escrow state.
- **Presentation Timeline Audit Log**: Live chronological log with millisecond timestamps and elapsed time counters recording scenario transitions and peer transmissions.
- **In-App Judge Briefing**: An embedded educational card summarizing *"What makes this demonstration interesting?"* for technical evaluators.

### Secure AWDL Wire Protocol & Transport Isolation

The predictive advisory feed reuses the existing **Apple Wireless Direct Link (AWDL) and Bluetooth Low Energy** transport without requiring internet access or local Wi-Fi router routing:

- **Type-Safe Wire Message**:
  ```swift
  public struct PeerPredictionMessage: Codable, Equatable {
      public let protocolVersion: Int
      public let messageId: String
      public let sequenceNumber: Int
      public let timestamp: String
      public let isSimulation: Bool
      public let outageProbability: Double
      public let predictedDurationMinutes: Int
      public let predictedDemandAmount: Double
      public let predictionUncertainty: Double
      public let recommendedReserve: Double
      public let previousReserve: Double
      public let reason: String
      public let networkProfile: String
      public let confidenceLevel: Double
  }
  ```
- **Rigorous Security Boundaries**:
  - **16 KB Maximum Payload Limit**: Malformed or oversized updates are dropped instantly.
  - **Forbidden Payment Keys Guard**: Incoming prediction messages are audited for forbidden financial keys (`paymentId`, `voucherSignature`, `deviceSignature`, `instruction`, `allocatedAmount`). Advisory packets can never manipulate double-entry ledger state.
  - **Sequence Monotonicity & Staleness**: Out-of-order sequence numbers or updates older than 120 seconds are strictly rejected.
  - **Genuine Peer Acknowledgment (`PeerPredictionAck`)**: Upon ingestion, the iPhone transmits a validated `PREDICTION_ACK` packet back to the Mac companion over AWDL, turning the transport indicator green.
```

---

## 🔒 Dual-Signature Cryptographic Pipeline

```mermaid
sequenceDiagram
    autonumber
    participant Alice as 📱 Payer Alice (iPhone 14)
    participant Bank as 🏛️ Bank Core Gateway
    participant Bob as 💻 Merchant Bob (Mac Companion)

    Note over Alice,Bank: Phase 1: Online Allowance Issuance
    Alice->>Bank: POST /api/allowance/issue (accountId: alice, amount: ₹100, deviceId)
    Bank->>Bank: Debit Alice ₹100.00 ➔ Credit system-escrow ₹100.00
    Bank->>Bank: Generate Canonical Voucher Bytes
    Bank->>Bank: Sign Voucher with Bank Authority Private Key (RSA-PSS SHA-256)
    Bank-->>Alice: OfflineAllowanceVoucherResponse (allowanceId, voucherSignature, bankPublicKey)
    Alice->>Alice: Persist active voucher in OfflineAllowanceManager

    Note over Alice,Bob: Phase 2: Disconnected Offline Payment (AWDL / Multipeer)
    Alice->>Alice: Construct Spend Record (paymentId, seq: 1, amount: ₹100, cumulative: ₹100)
    Alice->>Alice: Sign Canonical Spend Bytes with Payer Private Key (2048-bit RSASSA-PSS)
    Alice->>Bob: PeerTransferMessage: Handshake (protocolVersion: 1)
    Bob-->>Alice: PeerTransferMessage: HandshakeAck
    Alice->>Bob: PeerTransferMessage: PacketTransfer (Voucher + SpendRecord)
    Bob->>Bob: Verify Voucher Signature using Pinned Bank Public Key
    Bob->>Bob: Verify Payer Digital Signature (Mathematical only — identity unauthenticated until bridge settlement)
    Bob->>Bob: Store in Isolated Inbox with status: RECEIVED (Provisional — Not Settled)
    Bob-->>Alice: PeerTransferMessage: TransferAck (accepted: true)

    Note over Bob,Bank: Phase 3: Deferred Settlement (When Bridge Connected)
    Bob->>Bank: POST /api/allowance/spend (OfflineSpendRecord)
    Bank->>Bank: Step 2: Idempotency Check (paymentId uniqueness)
    Bank->>Bank: Step 4: Verify Bank Authority Voucher Signature (RSA-PSS)
    Bank->>Bank: Step 6: Verify Payer Signature against Registered Device Key
    Bank->>Bank: Step 9: Verify Monotonic Sequence & Cumulative Arithmetic
    Bank->>Bank: Step 10: Atomic Double-Entry Settlement (system-escrow -₹100, Bob +₹100)
    Bank->>Bank: Step 11: Mark Allowance EXHAUSTED (Spent: ₹100 / ₹100)
    Bank-->>Bob: HTTP 200 OK (OfflineSpendPayment status: SETTLED)
    Bob->>Bob: Transition status to SETTLED in ReceivedPacketStore
```

---

## 📡 Direct Offline Peer-to-Peer Transport

- **Zero Cellular / Zero Wi-Fi Router**: Direct communication over Apple Wireless Direct Link (AWDL) and Bluetooth Low Energy via Apple's **Multipeer Connectivity framework**.
- **Bonjour Service**: Registered under `_upimesh-pay._tcp`.
- **Peer Roles**:
  - `MCNearbyServiceAdvertiser`: Broadcasts device availability and identity metadata.
  - `MCNearbyServiceBrowser`: Discovers nearby peer nodes in real-time.
- **Type-Safe Wire Protocol**:
  ```swift
  public enum PeerTransferMessage: Codable {
      case handshake(HandshakePayload)
      case handshakeAck(HandshakeAckPayload)
      case packetTransfer(PacketTransferPayload)
      case transferAck(TransferAckPayload)
      case ping(PingPayload)
      case pong(PongPayload)
  }
  ```
- **Diagnostic Ping/Pong**: Includes round-trip latency measurement over Multipeer Connectivity without financial mutations.

---

## 📱 Native Applications: macOS, iPadOS & iOS

MeshPay features a multi-platform Apple ecosystem implementation using native Swift, SwiftUI, AppKit, and Apple's Multipeer Connectivity framework for zero-internet peer-to-peer payments.

---

### 1. 🖥️ Native macOS Companion Application (Merchant Node)

Located in [`macos/UPIMeshCompanion/`](macos/UPIMeshCompanion/):
- **Merchant Bob Persona**: Runs on macOS as an authoritative merchant receiver advertising over AWDL and BLE (`_upimesh-pay._tcp`).
- **Persist-Before-ACK Workflow**: Automatically validates incoming packet size (≤ 64 KB), checks protocol invariants, verifies RSASSA-PSS SHA-256 digital signatures against the sender's public key, and persists records to durable disk storage (`~/Library/Application Support/UPIMeshCompanion/received_packets.json`) *before* issuing the network acknowledgement.
- **Isolated Receiver Inbox**: Keeps received packets isolated in a dedicated inbox with status **`RECEIVED — NOT SETTLED`** (strictly preventing un-settled balance inflation).
- **Spring Boot Bridge Sync**: Features an integrated bridge client ([`MacBridgeClient.swift`](macos/UPIMeshCompanion/MacBridgeClient.swift)) to register device keys and batch-reconcile stored offline packets with the bank settlement engine upon reconnection.
- **Zero-Dependency Build**: Includes standalone compile script [`build_macos_companion.sh`](build_macos_companion.sh) producing a code-signed application bundle.

<div align="center">
  <img src="docs/assets/mac_companion_ui.png" alt="macOS Companion Application UI" width="900" style="border-radius: 10px; box-shadow: 0 8px 30px rgba(0,0,0,0.4);" />
  <p><i>Figure 1: Native macOS Companion displaying Merchant Bob's live Multipeer Connectivity transport, active peer pairing, non-financial diagnostic latency probe, and durable store-and-forward packet inbox.</i></p>
</div>

---

### 2. 📱 iOS & iPadOS Applications (Payer Node: iPhone 14 & iPad on Mac)

Located in [`ios/UPIMesh/`](ios/UPIMesh/), written in SwiftUI:
- **Dual Destination Architecture**: Supports native execution on physical hardware (**iPhone 14**) and on Apple Silicon macOS via **`My Mac (Designed for iPad)`**.
- **Mesh Wallets**: Real-time account balance display, bank device key registration, and one-tap bank escrow allowance issuance.
- **Offline Pay**: Discovers nearby companion nodes, constructs and signs cryptographic spend records locally without backend calls, monitors remaining allowance budgets, and manages outgoing packet queues.
- **Mesh Radar**: Visualizes nearby peer nodes, signal strength (RSSI), and direct peer connection states.
- **Mesh Ledger**: Live transaction audit log synchronized with the backend.

<div align="center">
  <table border="0">
    <tr>
      <td width="35%" align="center" valign="top">
        <b>📱 Physical iPhone 14 Client</b><br/>
        <sub>Hardware testbed running iOS 18+ with active ₹10,000 offline allowance & AWDL scanning</sub><br/><br/>
        <img src="docs/assets/iphone_app_ui.png" alt="iPhone 14 Physical UI" width="280" style="border-radius: 12px; box-shadow: 0 6px 24px rgba(0,0,0,0.35);" />
      </td>
      <td width="65%" align="center" valign="top">
        <b>💻 iPad Client Running on macOS (Designed for iPad)</b><br/>
        <sub>Responsive tablet interface running directly on Apple Silicon with multi-wallet mesh management</sub><br/><br/>
        <img src="docs/assets/ipad_app_ui.png" alt="iPad on Mac UI" width="580" style="border-radius: 12px; box-shadow: 0 6px 24px rgba(0,0,0,0.35);" />
      </td>
    </tr>
  </table>
  <p><i>Figure 2: Native mobile clients running on physical iPhone 14 hardware (left) and Apple Silicon Mac via "Designed for iPad" destination (right).</i></p>
</div>

---

## 🛠️ Quickstart Guide

### Prerequisites (macOS Developers)
- **Operating System**: macOS 14.0+ (Sonoma or Sequoia)
- **Java**: OpenJDK 17 or higher (install via Homebrew: `brew install openjdk@17` and set `export JAVA_HOME="/opt/homebrew/opt/openjdk@17"`)
- **Python**: Python 3.10 or higher (for research simulation engine & benchmark suite)
- **Build Tool**: Bundled Maven Wrapper (`./mvnw`) included in repository
- **Apple Developer Tools**: Xcode 15+ or 16+ with Command Line Tools (`xcode-select --install`)

---

### 1. Build and Run Backend
The backend can be built, tested non-destructively, and executed locally:
```bash
# Clone the repository
git clone https://github.com/Jarjis-Alam/upimesh.git
cd upimesh

# Compile backend classes
./mvnw clean compile

# Run all 303 Java backend tests (executes in an isolated in-memory H2 database)
./mvnw test

# Configure required environment variable for admin endpoints (reconciliation, audits)
export UPI_MESH_ADMIN_TOKEN="your-secure-admin-token-min-16-chars"

# (Optional) Provision 256-bit AES-GCM encryption key for bank authority master key
# export UPI_MESH_KEY_ENCRYPTION_KEY="<BASE64_32_BYTE_KEY>"

# Start the local Spring Boot banking core (backed by persistent file H2 at ./data/upimesh)
./mvnw spring-boot:run
```

- **API Base URL**: `http://localhost:8080`
- **H2 Console**: `http://localhost:8080/h2-console` (`jdbc:h2:file:./data/upimesh`, User: `sa`, Password: *(blank)*)

---

### 2. Run the Native Swift Test Suite (103 Tests)
Run all 103 iOS and macOS tests directly from Terminal without opening Xcode:
```bash
./run_ios_tests.sh
```

---

### 3. Run the Predictive Research Engine & Tests (23 Tests)
Execute the uncertainty-aware provisioning test suite and launch the local prediction engine:
```bash
# Run all 23 Python research tests
PYTHONPATH=research/predictive-provisioning python3 -m unittest discover -s research/predictive-provisioning/tests

# Launch local prediction HTTP server (listens on port 8050)
python3 research/predictive-provisioning/demo_server.py
```
- **Prediction Engine API**: `http://127.0.0.1:8050/api/state`
- **Interactive Web Dashboard**: `http://127.0.0.1:8050/`

---

### 4. Build & Run macOS Companion App (Judge Demo Station)
```bash
# Build standalone code-signed companion app
./build_macos_companion.sh

# Launch the app
open macos/build/UPIMeshCompanion.app
```
*Note: Ensure `demo_server.py` is running on port 8050. The companion will automatically display `🟢 Engine: Connected`, enabling the 5-scenario interactive judge presentation console.*

---

### 5. Run the iOS Mobile App
```bash
open ios/UPIMesh/UPIMesh.xcodeproj
```
Select an **iOS Simulator** or connected physical iPhone (iOS 16+), then press **⌘R**. The app's **Mesh Wallets** view will automatically render the live **Predictive Advisory Card** via zero-internet AWDL/BLE peer-to-peer telemetry.

---

### 6. Controlled Technical Demonstration
For a safe, 100% read-only technical walkthrough that demonstrates the verified ₹100 payment and zero-sum reconciliation without database mutations, follow:
👉 **[`docs/reports/demo_runbook.md`](docs/reports/demo_runbook.md)**

---

## 📡 API Reference

### 1. Bank Authority & Allowance Endpoints

#### `GET /api/allowance/bank-public-key`
Retrieves the active Bank Authority RSA public key in standard X.509 Base64 format.
```bash
curl -s http://localhost:8080/api/allowance/bank-public-key
```
**Response (`200 OK`):**
```json
{
  "keyId": "bank-authority-master",
  "algorithm": "RSA",
  "publicKeyBase64": "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA..."
}
```

#### `POST /api/allowance/issue`
Reserves funds into escrow and issues an allowance voucher signed by the bank authority.
```bash
POST /api/allowance/issue
Content-Type: application/json

{
  "accountId": "alice",
  "allocatedAmount": 100.00,
  "currency": "INR",
  "deviceId": "85343D9B-10E3-4462-BE7F-0919CB8BA014",
  "validityDurationMinutes": 1440
}
```

#### `GET /api/allowance/{allowanceId}`
Queries the status, allocated amount, spent amount, and remaining balance of an allowance.

#### `GET /api/allowance/{allowanceId}/spends`
Returns all settled offline spend payments recorded against the allowance.

#### `POST /api/allowance/spend`
Settles an offline spend record submitted by a merchant node.

---

### 2. Core Ledger & Reconciliation Endpoints

#### `GET /api/reconciliation`
Runs an authoritative reconciliation audit. Requires administrative token authentication.
```bash
curl -s http://localhost:8080/api/reconciliation -H "X-Admin-Token: your-secure-admin-token-min-16-chars"
```
**Response (`200 OK`):**
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
    { "accountId": "alice", "actualBalance": 4870.00, "status": "RECONCILED", "matches": true },
    { "accountId": "bob", "actualBalance": 1130.00, "status": "RECONCILED", "matches": true },
    { "accountId": "carol", "actualBalance": 2000.00, "status": "RECONCILED", "matches": true },
    { "accountId": "system-escrow", "actualBalance": 0.00, "status": "RECONCILED", "matches": true }
  ],
  "discrepancies": [],
  "unverifiableAccounts": []
}
```

#### `GET /api/accounts`
Returns all registered account balances and optimistic locking versions.

#### `GET /api/transactions`
Returns the immutable, chronological double-entry transaction journal.

---

## ⚖️ Mathematical Reconciliation Engine

The reconciliation audit engine explicitly decouples **structural ledger invariants** from **account balance reconciliation**:

### 1. Structural Ledger Conservation Check
$$\sum_{j=1}^{M} \text{Debits}(j) \equiv \sum_{j=1}^{M} \text{Credits}(j)$$
- Validates double-entry symmetry across all settled journal entries.
- A balanced structural status proves internal journal equilibrium, but does not prove individual accounts were free of external balance manipulation.

### 2. Account Balance Verification
For each account $i$ with an authoritative opening baseline $B_0(i)$:
$$E(i) = B_0(i) + \sum \text{Credits}(i) - \sum \text{Debits}(i)$$
$$\Delta(i) = A(i) - E(i)$$
- **`RECONCILED`**: $\Delta(i) = 0$
- **`DISCREPANCY`**: $\Delta(i) \neq 0$ (flagged without silent database repairs)
- **`UNVERIFIABLE`**: If an account lacks an authoritative opening balance, it is explicitly classified as `UNVERIFIABLE`.

---

## 🧪 Test Suite & Verification (429 Passing Tests)

The repository is rigorously covered by **429 automated tests** across backend banking logic, native Apple peer-to-peer transport, and the predictive provisioning research engine with zero failures:
- **303 Java Backend Tests** (JUnit 5 + MockMvc + isolated in-memory H2 database `jdbc:h2:mem:upimesh_test`)
- **103 Swift iOS/macOS Tests** (command-line test runners with zero Xcode GUI dependency)
- **23 Python Research Tests** (unittest test suites covering stochastic prediction, Pareto frontiers, and demo scenario states)

### Test Suite Breakdown

| Framework | Suite | Tests | Scope & Invariants Tested |
|---|---|:---:|---|
| **Java (Spring Boot)** | `AccountOwnerAuthorizationLifecycleTest` | 29 | Multi-device owner authorization, lifecycle transitions, pairing token revocation |
| | `SecurityRemediationPhase1Test` | 16 | Timing-safe admin token comparison, AES-256-GCM bank key encryption at rest |
| | `BackendIntegrationLayerTest` | 15 | Bridge public key export, external packet ingestion, atomic escrow settlement |
| | `FinancialReadAccessControlTest` | 15 | Administrative access barriers on account balances and transaction journals |
| | `OfflineAllowanceSettlementServiceTest` | 15 | Step 2 idempotency, dual signatures, sequence forks, escrow settlement |
| | `ApiAccessControlAuditTest` | 14 | Authentication header auditing, fail-closed access barriers |
| | `AccountOwnerConsentSecurityTest` | 14 | Cryptographic owner consent signatures and unauthorized device rejection |
| | `OwnerKeyEnrollmentAuditTest` | 13 | Owner key registration, duplicate prevention, fail-closed provisioning |
| | `OperationalHardeningTest` | 13 | File database persistence across restarts, non-overwriting seeder, sanitized errors |
| | `PaymentReconciliationSecurityTest` | 13 | Double-entry structural conservation, opening baseline reconciliation |
| | `ConfigurationSecurityAuditTest` | 11 | Security property defaults, secret requirements, profile isolation |
| | `OfflineAllowanceServiceTest` | 11 | Allowance issuance, escrow reservation, refund, canonical voucher bytes |
| | `BridgeIngestionServiceTest` | 10 | Payload validation, hybrid decryption, timestamp bounds, expiration |
| | `LedgerReconciliationTest` | 9 | Double-entry invariants, circular transfers, tampering detection |
| | `CryptoServiceTest` | 9 | RSA-OAEP wrapping, AES-256-GCM ciphering, RSASSA-PSS signing |
| | `SenderAuthenticationTest` | 9 | RSASSA-PSS SHA-256 signature verification, canonical byte serialization |
| | `SecureDeviceAuthorizationTest` | 9 | Owner consent validation, pairing token lifecycle, device guards |
| | `PersistentDeviceRegistryTest` | 9 | Device key persistence, updates, account binding |
| | `PaymentInstructionTest` | 9 | Instruction immutability, canonical representation, validation |
| | `DeviceSignedPaymentSubmissionTest` | 9 | Public key verification, balance checks, replay defenses |
| | `SecurityRemediationPhase3Test` | 8 | Admin token header extraction, environment variable precedence |
| | `PersistentReplayProtectionTest` | 7 | Database compound `(fromAccount, nonce)` uniqueness, re-encryption defense |
| | `PersistentIdempotencyTest` | 7 | Service re-instantiation idempotency, SHA-256 deduplication, concurrency |
| | `MeshPacketTest` | 6 | Network packet format, hop count limits, canonical encoding |
| | `TransactionLedgerIntegrationTest` | 6 | Atomic ledger recording, balance adjustments, chronological indexing |
| | `IdempotencyServiceTest` | 5 | Atomic in-memory claims, state lifecycle transitions |
| | `MeshSimulatorServiceTest` | 5 | Multi-hop gossip rounds, loop prevention, TTL expiration |
| | `EndToEndMeshPaymentTest` | 5 | End-to-end controller & simulation integration |
| | `CrossLanguageCanonicalizationTest` | 1 | RFC 8785 byte-for-byte serialization match between Java & Swift |
| | `UpimeshApplicationTests` | 1 | Spring Boot application context initialization |
| **Swift (iOS / macOS)** | `PeerTransportTests` | 32 | Multipeer handshake, state recovery, tie-breaker, packet serialization, ping/pong, prediction message invariants, payload limits, forbidden keys detection, probe routing, prediction ACKs |
| | `ReconciliationServiceTests` | 16 | Settlement transitions, terminal rejections, timeout recovery, retry safety |
| | `MacCompanionTests` | 16 | macOS packet decoding, deduplication, tampering rejection, lifecycle states |
| | `OfflineAllowanceTests` | 13 | Voucher parsing, RSASSA-PSS verification, spend creation, cumulative tracking |
| | `TrueOfflineStoreAndForwardTests` | 10 | Local creation without backend, persist-before-ack, crash recovery, delayed settlement |
| | `OfflinePaymentPacketTests` | 9 | Packet creation, canonicalization, RSA signing, deduplication |
| | `MeshLedgerViewModelTests` | 7 | Live backend transaction sync, offline local counts, preview isolation |
| **Python (Research Module)** | `test_milestone3_validation` | 8 | Pareto frontier invariants, cold start convergence, heavy tail distributions, metric consistency |
| | `test_demo_engine` | 6 | Scenario state transitions, grid shock injection, reset invariants, telemetry accuracy |
| | `test_difficult_scenarios` | 5 | Uncertainty-aware allocation under non-stationary outages, adversarial jamming, safety floors |
| | `test_provisioning` | 4 | Demand estimation, outage probability calibration, cost objective optimization |
| **Total** | **41 Test Suites** | **429** | **429 Passed / 0 Failures / 0 Errors (303 Java + 103 Swift + 23 Python)** |

---

## 🔒 Security Model & Threat Boundaries

> [!WARNING]
> **RESEARCH & EDUCATIONAL PROTOTYPE CLASSIFICATION**  
> MeshPay / UPI Offline Mesh is an experimental prototype demonstrating distributed systems and cryptographic patterns for offline payments. It is not connected to live UPI / NPCI banking rails.

The system adheres to an honest security model and explicitly discloses inherent physical and distributed systems constraints:

1. **SEC-01 (Offline Double-Spending is an Inherent Architectural Limitation)**:
   - In disconnected peer-to-peer networks lacking a continuous central clearinghouse or tamper-proof monotonic hardware counters (e.g. smartcards), a rogue payer device can sign multiple conflicting spend records against the same allowance to different disconnected merchants.
   - The first merchant to establish internet connectivity and reconcile with the bank bridge settles successfully. Subsequent merchants attempting to settle conflicting sequence numbers incur a **100% credit loss**.
   - Offline transaction finality is **strictly provisional** until authoritative bridge settlement. Sequence forks are detected upon settlement, triggering an automatic `SEQUENCE_FORK_CONFLICT` audit event and immediate revocation of the parent allowance.
2. **SEC-02 (Mathematical Signature Validity Does Not Prove Account Identity)**:
   - When a merchant node receives an offline payment packet, it verifies that the bank voucher signature is valid (via the bank's pinned public key) and that the spend record was mathematically signed by the device's public key.
   - However, **mathematical signature validity alone does not prove the sender's account identity is authentic**. An offline signature demonstrates cryptographic possession of a private key, but the authoritative binding between that device key and the account (`alice`) is only authenticated when the bank bridge reconciles the spend record against the authoritative registry.
3. **SEC-03 (Software Keychain vs. Hardware Secure Enclave)**:
   - Active device keys are stored in the Apple iOS software Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
   - The Apple Secure Enclave processor lacks RSA hardware coprocessors and supports NIST P-256 ECC exclusively. The prototype standardizes on 2048-bit RSASSA-PSS for byte-level cross-platform parity with standard Java cryptographic primitives. Hardware-enforced private-key attestation requires a future NIST P-256 ECDSA migration.
4. **SEC-05 (Client-Signed Timestamps Do Not Establish True Time)**:
   - Server-side validation enforces syntactic timestamp bounds (`createdAt >= issuedAt - 5m`, allowance expiration, and sequence monotonicity).
   - However, a client-signed timestamp proves only that the private key signed that timestamp string, **not that the device clock was truthful**. Establishing trustworthy offline time without trusted hardware remains an open distributed systems challenge.

For the complete threat model and limitation analysis, see [`docs/security/security_model_and_limitations.md`](docs/security/security_model_and_limitations.md).

---

## 📚 Documentation Index

The `docs/` and `research/` directories contain complete technical reports and verification gates:

- **[Predictive Provisioning Research (`research/predictive-provisioning/README.md`)](research/predictive-provisioning/README.md)**: Research methodology, stochastic optimization formulation, sensitivity analyses, and Pareto validation across 30 random seeds.
- **[Interactive Research Report (`research/predictive-provisioning/results/report.html`)](research/predictive-provisioning/results/report.html)**: Standalone interactive visual report documenting benchmark metrics and strategy trade-off frontiers.
- **[Demo Runbook (`docs/reports/demo_runbook.md`)](docs/reports/demo_runbook.md)**: Controlled step-by-step technical demonstration guide with safe read-only paths and sanitized secrets.
- **[Hardware Verification Report (`docs/reports/hardware_verification_report_100_inr.md`)](docs/reports/hardware_verification_report_100_inr.md)**: Complete empirical log and photographic evidence of the first ₹100 payment across physical iPhone 14 and MacBook Pro.
- **[Final Verification Gate (`docs/reports/final_verification_gate.md`)](docs/reports/final_verification_gate.md)**: Comprehensive, read-only audit verifying zero database mutations, test suites, and cryptographic integrity.
- **[Security Remediation Final Report (`docs/reports/security_remediation_final_report.md`)](docs/reports/security_remediation_final_report.md)**: Exhaustive documentation of all 12 security remediation phases (SEC-01 through SEC-12).
- **[Security Model & Limitations (`docs/security/security_model_and_limitations.md`)](docs/security/security_model_and_limitations.md)**: Detailed threat model, attacker assumptions, and structural boundaries.

---

## 📄 License

This project is intended to be distributed under the [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0). *(A repository LICENSE file will be included following formal administrative review).*
