# MeshPay Security Remediation Report — Phase 6: Administrative API and Configuration Hardening

## 1. Executive Summary & Scope

Phase 6 performs an exhaustive security audit across all exposed REST endpoints in the MeshPay Spring Boot backend and resolves hardcoded network configuration in the iOS client. 

Prior to Phase 6, several endpoints lacked uniform authentication enforcement, client code relied on duplicate hardcoded LAN IP fallbacks, and the production profile lacked an explicit loopback interface bind constraint (`server.address`).

This remediation verifies that:
1. Every administrative and financial endpoint enforces strict role/ownership access control.
2. Production configuration fails closed against debug features, unauthenticated pairing, H2 console exposure, and accidental external network binding.
3. Client configuration provides a single, centralized source of truth (`APIConfiguration.swift`) for backend network resolution.

---

## 2. Exhaustive Backend Endpoint Security Audit

| HTTP Method & Path | Controller | Access Control Required | Input Validation & Error Policy | Status |
| :--- | :--- | :--- | :--- | :---: |
| `GET /api/accounts` | `ApiController` | Authenticated (Admin sees all; User sees self) | Parameter sanitization; returns 401/403 | **REMEDIATED** |
| `GET /api/transactions` | `ApiController` | Authenticated (Admin sees all; User sees self) | Parameter sanitization; returns 401/403 | **REMEDIATED** |
| `POST /api/transfer` | `ApiController` | Dev/Demo only; Blocked in Production | Fails closed with 403 SecurityException in prod | **REMEDIATED** |
| `POST /api/mesh/transfer` | `ApiController` | Dev/Demo only; Blocked in Production | Fails closed with 403 Forbidden in prod | **REMEDIATED** |
| `GET /api/mesh/topology` | `ApiController` | Public (Read-only simulation state) | No secret exposure | **SECURE** |
| `GET /api/reconciliation` | `ApiController` | Authenticated Admin (`X-Admin-Token` / Bearer) | Returns 401 if missing/invalid token | **REMEDIATED** |
| `GET /api/bridge/public-key`| `ApiController`| Public (Bridge RSA public key distribution) | X.509 format, public key only | **SECURE** |
| `POST /api/keys/register` | `ApiController` | Enrolled Owner / Admin; Blocked in Prod | Fails closed in prod (403); rejects unauth on existing accounts (401) | **REMEDIATED (Phase 3)** |
| `POST /api/owner/keys/register`| `ApiController`| Admin Token or Authorized Enrollment | Fails closed in prod; rejects unauth | **REMEDIATED (Phase 1)** |
| `POST /api/devices/authorize` | `ApiController` | Admin Token (`X-Admin-Token` / Bearer) | Carol blocked; enforces bounds & limits | **REMEDIATED** |
| `POST /api/devices/authorize/consent` | `ApiController` | Cryptographic Owner Consent Signature | Enforces signature verification | **REMEDIATED** |
| `POST /api/devices/revoke` | `ApiController` | Admin Token (`X-Admin-Token` / Bearer) | Requires valid admin token | **REMEDIATED** |
| `GET /api/devices/authorizations/{d}/{a}` | `ApiController` | Admin Token (`X-Admin-Token` / Bearer) | Prevents unauthenticated user enumeration | **REMEDIATED** |
| `POST /api/mesh/submit` | `ApiController` | Cryptographic Device Signature (`RSASSA-PSS`) | Replay hash, timestamp window, domain checks | **SECURE** |
| `GET /api/mesh/status/{paymentId}` | `ApiController` | Public (Authoritative settlement query) | Read-only idempotent ledger check | **SECURE** |
| `GET /api/allowance/bank-public-key` | `OfflineAllowanceController` | Public (Authority RSA public key pinning) | Public key only; no secrets | **SECURE** |
| `POST /api/allowance/issue` | `OfflineAllowanceController` | Device Auth Repository Binding & Limits | Double-entry escrow debit; limits checked | **SECURE** |
| `POST /api/allowance/spend` | `OfflineAllowanceController` | Bank Voucher + Payer Signatures (`RSASSA-PSS`) | Multi-layer signature, monotonic sequence & timestamp check | **REMEDIATED (Phase 2)** |
| `POST /api/allowance/refund` | `OfflineAllowanceController` | Escrow Grace Period Expired (`now > expiresAt + 24h`)| Escrow transferred strictly to original payer | **SECURE** |
| `GET /api/allowance/active` | `OfflineAllowanceController` | Public query for active voucher | Read-only voucher response | **SECURE** |
| `GET /api/allowance/{id}` | `OfflineAllowanceController` | Public query for voucher metadata | Read-only voucher response | **SECURE** |
| `GET /api/allowance/{id}/spends` | `OfflineAllowanceController` | Public query for spend history | Read-only ledger records | **SECURE** |
| `GET /api/allowance/{id}/security-events`| `OfflineAllowanceController` | Public query for security events | Read-only audit trail | **SECURE** |

---

## 3. Configuration & Profile Hardening Audit

### A. Production Profile (`application-prod.properties`)
1. **Loopback Interface Binding**:
   - Explicitly added `server.address=127.0.0.1` to prevent Spring Boot from automatically binding to `0.0.0.0` (all public network interfaces) when deployed in production.
2. **H2 Web Console**:
   - `spring.h2.console.enabled=false` strictly enforced.
   - `spring.h2.console.settings.web-allow-others=false` explicitly locked.
3. **Database Schema Mutability**:
   - `spring.jpa.hibernate.ddl-auto=validate` strictly enforced. Schema mutations or table drops are rejected at boot time.
4. **Information Disclosure & Stack Traces**:
   - `server.error.include-stacktrace=never`
   - `server.error.include-message=never`
   - `server.error.include-binding-errors=never`
   - `server.error.include-exception=false`
5. **Key Management at Rest**:
   - `upimesh.bank-authority.auto-migrate-encryption=false` prevents uncoordinated in-place key mutations.
   - Requires external `upimesh.bank-authority.encryption-key` / `UPI_MESH_BANK_AUTHORITY_ENCRYPTION_KEY` environment variable.

### B. Development Profile (`application.properties`)
1. **Console Scope**:
   - `spring.h2.console.settings.web-allow-others=false` restricts H2 console strictly to localhost.
2. **Authentication Defaults**:
   - `upimesh.demo-auth-enabled=false` prevents default bypasses.
   - Requires explicit `UPI_MESH_ADMIN_TOKEN` for administrative endpoints.

### C. Actuator Endpoints & CORS
1. **Actuator**: Confirmed zero Spring Boot Actuator dependencies in `pom.xml`. No `/actuator/**` endpoints are compiled or exposed.
2. **CORS Policy**: `WebMvcSecurityConfig.java` strictly permits `http://localhost:8080` and `http://127.0.0.1:8080`, disallowing wildcard `*` origins and disabling credential sharing (`allowCredentials(false)`).

---

## 4. Client-Side Network Hardening (`APIConfiguration.swift`)

### Issues Identified & Remediated:
1. **Duplicated Hardcoded Fallback Addresses**:
   - `MeshWalletsView.swift` and `MeshLedgerView.swift` previously contained hardcoded fallback strings `"192.168.1.100:8080"`.
   - **Remediation**: Implemented `APIConfiguration.shared.hostDescription` as the unified source of truth.
2. **Stale Hardcoded Subnet Checks**:
   - `APIConfiguration.swift` previously contained `!saved.contains("192.168.1.103")`.
   - **Remediation**: Replaced with standard URL scheme validation (`url.scheme == "http" || url.scheme == "https"`), preserving dynamic runtime overrides via `UserDefaults` without ad-hoc IP hardcoding.

---

## 5. Verification & Test Continuity

- **Backend Configuration**: Verified via `application.properties` and `application-prod.properties`.
- **iOS Test Suite**: Successfully verified via `./run_ios_tests.sh`.
- **Ledger Invariants**: No modifications to the live persistent database `data/upimesh.mv.db`.
