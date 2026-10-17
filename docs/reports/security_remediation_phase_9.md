# MeshPay Security Remediation Report — Phase 9: Peer-to-Peer Transport and Bridge Security

## 1. Executive Summary & Transport Architecture

Phase 9 audits the security of the peer-to-peer transport layer connecting physical iPhones and macOS bridge companions over Apple Multipeer Connectivity (Bluetooth Low Energy discovery and Apple Wireless Direct Link / AWDL Wi-Fi).

In decentralized and ad-hoc networks, the transport layer is fundamentally untrusted:
- Wireless broadcasts can be monitored or injected by nearby malicious actors.
- Peer display names (e.g. `"Bob's MacBook"`) can be casually spoofed without cryptographic credentials.
- Intermediate relay nodes can delay, duplicate, or alter forwarded packets.

This audit verifies that MeshPay achieves **end-to-end cryptographic transport integrity**, enforces **strict separation between discovery and authentication**, and protects local storage against buffer exhaustion and packet replay.

---

## 2. Multipeer Transport & Trust Boundaries

```
[ Alice iPhone (Payer) ]
        │
        │ 1. Advertises service 'upimesh-pay'
        │ 2. Connects via MCSession (encryptionPreference: .required)
        ▼
[ Bob / Mac Companion (Receiver) ]
        │
        │ 3. Validates envelope size (<= 64 KB) & schema version
        │ 4. Checks local deduplication stores (inbox & queue)
        │ 5. Verifies RSASSA-PSS digital signature offline
        │ 6. Marks record: RECEIVED — NOT SETTLED (sender identity unverified)
        ▼
[ Bank Settlement Bridge (Online Backend) ]
        │
        │ 7. Authenticates device public key against RegisteredDeviceKeyRepository
        │ 8. Verifies Bank Authority voucher signature & sequence monotonicity
        │ 9. Atomically executes double-entry escrow settlement
```

### Key Trust Principles:
1. **Discovery is Never Mistaken for Authentication**:
   - The Apple `MCPeerID.displayName` is treated strictly as an untrusted diagnostic label.
   - In `MeshPeerTransportService.swift` and `MacBridgeClient.swift`, received records are explicitly tagged:
     `isSenderIdentityAuthenticated = false`
     `trustStatusNote = "RSASSA-PSS signature mathematically valid. Sender identity is UNVERIFIED offline (authorization and balance settlement require bridge)."`
   - A peer cannot obtain trusted status or trigger balance credits merely by presenting a familiar name.
2. **End-to-End Cryptographic Envelope**:
   - The inner `OfflinePaymentPacket` is cryptographically signed by the payer device's private key before being placed on the wire.
   - Any modification of fields (payer, recipient, amount, nonce, sequence number, timestamps) by an untrusted intermediary relay causes immediate signature rejection.
3. **Transport Layer Encryption**:
   - `MCSession` is initialized with `encryptionPreference: .required`, ensuring that the wireless link between nearby devices is encrypted using Apple's underlying TLS-like authenticated channel.

---

## 3. Ingestion, Bounds, and Replay Protection

### A. Payload Boundary Enforcement
- To prevent denial-of-service, buffer overflow, and memory exhaustion attacks on constrained mobile devices, `PeerTransferMessage.maxPayloadBytes` enforces an absolute **64 KB ceiling** on all inbound wire messages.
- Oversized messages are dropped immediately before JSON deserialization (`PeerTransferError.payloadTooLarge`).

### B. Local Deduplication & Idempotency
- When an inbound packet arrives, the receiver checks both:
  1. `OfflinePacketStore.shared.contains(paymentId: pid)` (Outgoing/created packets)
  2. `ReceivedPacketStore.shared.contains(paymentId: pid)` (Incoming/received inbox)
- Duplicate transmissions are rejected with an explicit warning without invoking cryptographic verification or overwriting existing states.

### C. Receipt Semantics (`RECEIVED — NOT SETTLED`)
- The receiver device never credits its local wallet balance upon peer transport receipt.
- The packet is held in an isolated local store in the `RECEIVED` state until an online bridge ingestion path becomes available.
- If the sender device loses power or disconnects mid-transfer, partially received data is discarded cleanly without corrupting the store.

---

## 4. Mac Bridge Companion Ingestion Pipeline

The macOS Companion (`UPIMeshCompanion`) serves as the edge gateway connecting the Bluetooth/AWDL mesh to the Spring Boot REST backend:
1. **Inbox Polling & Ingestion**:
   - Mac companion receives signed packets from nearby iPhones.
   - For allowance-backed spends, the Mac verifies the Bank Authority voucher signature and payer device signature offline before accepting physical delivery.
2. **Bridge Submission**:
   - When internet connectivity is present, `MacBridgeClient` submits the verified packet via `POST /api/allowance/spend` or `POST /api/mesh/submit`.
3. **Status Synchronization**:
   - Upon HTTP 200, the packet transitions from `SETTLING` to `SETTLED`.
   - In the event of transient network failure (HTTP timeout / connection refused), the record remains in `SETTLING` with a retryable backoff, preserving non-volatile records across app relaunches.

---

## 5. Automated Transport Test Evidence

All 38 iOS and macOS transport tests execute and pass cleanly:
- `PeerTransportTests` (22 tests):
  - Invariant validation & schema version checks.
  - 64 KB payload size limit enforcement.
  - Malformed payload rejection.
  - RSASSA-PSS mathematical signature verification.
  - Tampered signature rejection.
  - Store deduplication and status isolation (`RECEIVED` not settled).
  - Diagnostic ping/pong message isolation.
- `MacCompanionTests` (16 tests):
  - Isolation and deduplication in Mac received packet store.
  - Remote signature verification against SubjectPublicKeyInfo.
  - Bridge registration request encoding & response handling.
  - Allowance packet verification and lifecycle transition.
