# MeshPay — Security Remediation Phase 1 Verification Report

**Date**: October 17, 2026  
**Auditor / Verification Lead**: Senior Application Security Engineer  
**Status**: VERIFIED & COMPLETE  
**Deliverable Document**: Phase 1 Verification  
**Persistent Database**: `./data/upimesh.mv.db` (100% Preserved; No Reseed; No Deletion)

---

## 1. Executive Summary

Phase 1 addressed two critical security vulnerabilities identified in the release readiness audit:
- **SEC-04 (Admin Authentication Hardening)**: Default demo token credentials removed, fail-closed startup validation in production profiles implemented, and client fallback token removed.
- **SEC-02 (Bank Authority Key Protection)**: Plaintext RSA master private key storage replaced with authenticated AES-256-GCM encryption at rest, external key derivation, and fail-closed decryption without key regeneration.

This report independently verifies every claim, inspects all call sites, executes the automated adversarial test suite, and confirms persistent database integrity and cryptographic continuity.

---

## 2. Admin Authentication Verification (SEC-04)

### 2.1 Specification vs Implementation Check

| Invariant / Requirement | Implemented Location | Verified Behavior | Status |
| :--- | :--- | :--- | :--- |
| **Demo Auth Disabled by Default** | `src/main/resources/application.properties` (L31) | `upimesh.demo-auth-enabled=false` | **VERIFIED** |
| **Demo Tokens Rejected When Disabled** | `FinancialSecurityService.java` (L125-142) | Returns `Optional.empty()` for demo tokens when `demoAuthEnabled=false` | **VERIFIED** |
| **Admin Endpoints Reject Missing/Bad Tokens** | `ApiController.java` (L320, 356, 457, 794) | Missing or invalid token yields HTTP 401 Unauthorized | **VERIFIED** |
| **Production Profile Startup Validation** | `FinancialSecurityService.java` (L61-78) | Throws `IllegalStateException` on startup if `prod` profile lacks admin token or token length $< 16$ or token is trivial | **VERIFIED** |
| **No Client Fallback to Demo Token** | `APIConfiguration.swift` (L45-56) | Returns `nil` when no token configured in `UserDefaults` | **VERIFIED** |
| **Constant-Time Token Comparison** | `ApiController.java` (L227-239), `FinancialSecurityService.java` (L204-210) | Uses `MessageDigest.isEqual` to mitigate timing attacks | **VERIFIED** |
| **No Secret Leakage in Auth Failures** | `ApiController.java`, `FinancialSecurityService.java` | Generic error messages; stack traces suppressed | **VERIFIED** |

### 2.2 Endpoint Call Site Audit

Every sensitive endpoint was audited for administrative or account-scoped authorization:

1. **`GET /api/accounts`** (`ApiController.java:315`):
   - Resolves `AccountPrincipal` via `financialSecurityService.resolvePrincipal(...)`.
   - Rejects unauthenticated requests with HTTP 401.
   - Non-admin principals are scoped strictly to their own account; cross-account queries yield HTTP 403.
2. **`GET /api/transactions`** (`ApiController.java:351`):
   - Resolves `AccountPrincipal`.
   - Rejects unauthenticated requests with HTTP 401.
   - Non-admin principals are filtered strictly to their own transactions.
3. **`GET /api/reconciliation`** (`ApiController.java:453`):
   - Strictly checks `principal.hasRole("ROLE_ADMIN")`.
   - Rejects unauthenticated callers with HTTP 401 and non-admin callers with HTTP 403.
4. **`POST /api/devices/authorize`** (`ApiController.java:757`):
   - Validates pairing token against `getEffectiveAdminToken()` via `MessageDigest.isEqual`.
   - Rejects missing, invalid, or unconfigured token with HTTP 401.
   - Explicitly blocks debit authorization for `carol` fail-closed (HTTP 403).
5. **`POST /api/devices/revoke`** (`ApiController.java:946`):
   - Validates admin pairing token via `isTokenValid(providedToken)`.
6. **`GET /api/devices/authorizations/{deviceId}/{accountId}`** (`ApiController.java:1000`):
   - Validates admin pairing token via `isTokenValid(providedToken)`.

---

## 3. Bank Authority Key Protection Verification (SEC-02)

### 3.1 Specification vs Implementation Check

| Invariant / Requirement | Implemented Location | Verified Behavior | Status |
| :--- | :--- | :--- | :--- |
| **AES-256-GCM Authenticated Encryption** | `BankAuthorityKeyService.java` (L304-338) | 12-byte random IV, 128-bit authentication tag, standard GCM parameter spec | **VERIFIED** |
| **Independent Key Provisioning** | `BankAuthorityKeyService.java` (L64-65) | Read from `UPI_MESH_KEY_ENCRYPTION_KEY` or `upimesh.bank-authority.encryption-key` | **VERIFIED** |
| **Key Never Stored Beside Ciphertext** | `BankAuthorityKeyService.java` & `BankAuthorityCredential.java` | Only Base64 payload containing `ENC:AES-GCM:<IV + Ciphertext + Tag>` is stored in DB | **VERIFIED** |
| **Fail-Closed on Missing/Wrong Secret** | `BankAuthorityKeyService.java` (L150-165) | Throws `IllegalStateException`; does NOT regenerate key | **VERIFIED** |
| **Corrupted Ciphertext Never Regenerates** | `BankAuthorityKeyService.java` (L160-165) | Fails closed with exception; repository entity preserved | **VERIFIED** |
| **Safe Opt-In Migration** | `BankAuthorityKeyService.java` (L180-210) | Verified roundtrip before saving; disabled by default (`auto-migrate-encryption=false`) | **VERIFIED** |
| **Public Key & Voucher Verification Unchanged** | `BankAuthorityKeyService.java` (L230-260) | Public key matches baseline (`MIIBIjANBgkq...QIDAQAB`); signatures verify RSASSA-PSS | **VERIFIED** |

### 3.2 Key Continuity Proof

Direct REST verification against the running persistent backend (`http://localhost:8080`):
```bash
curl -s http://localhost:8080/api/allowance/bank-public-key
```
Output:
```json
{
  "algorithm": "RSA",
  "format": "X.509",
  "keyId": "bank-authority-master",
  "publicKeyBase64": "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAw/s+Rg4ukd3DZ8SaF/TTWP4sMip7rIHPnQ7oGpp//2i9jIVNpfXdH9Q9dnq9hdXRC/ND1bpCGn3fDzyXtXgpW2mHzSjF/MSnZisRa20KvH4lRm0PWOdZVQ02ZtfEwMS0TD6HCMMX0Ck0r5/Nlbd/hlvCD8qIqRRynXTyNspl/cgQnIhW2jOvbYVcugzyw3FtQRRaK7ozlndXQmth4kTmVk835nPJbVv3smhRmB2vduq+W1jy/ac/J8tjSH5hckNMtyo/AVCHUbPFY1yN3hzKHI1BQTD5UXKi1LsCbDK/1Gek7BeFPBBozz7NIdhk9oswW+o9hy6fWKBPLOFbn43tlQIDAQAB"
}
```
**Result**: The authority public key is 100% byte-for-byte identical to the pre-remediation key that signed Alice's ₹100 allowance voucher (`alw-d5e534d7-fc4e-478e-82fb-2cb55be77df0`).

---

## 4. Automated Adversarial Test Verification

Executed `./mvnw test -Dtest=SecurityRemediationPhase1Test`:
- **Total Tests Run**: 16
- **Failures**: 0
- **Errors**: 0
- **Execution Time**: 2.517 seconds
- **Pass Rate**: 100%

### Test Case Results

1. `testAdminEndpoints_anonymousRejected`: **PASS** (Rejects unauthenticated requests with HTTP 401 across `/api/accounts`, `/api/transactions`, `/api/reconciliation`, and `/api/devices/authorize`).
2. `testAdminEndpoints_incorrectTokenRejected`: **PASS** (Rejects incorrect bearer and header tokens with HTTP 401).
3. `testReconciliation_nonAdminForbidden`: **PASS** (Rejects user tokens attempting reconciliation with HTTP 403).
4. `testDemoToken_failsWhenDemoAuthDisabled`: **PASS** (Rejects `demo-token-admin` when `demoAuthEnabled=false`).
5. `testExplicitAdminToken_succeeds`: **PASS** (Explicitly configured strong admin token succeeds).
6. `testProductionProfile_missingAdminTokenFailsStartup`: **PASS** (Refuses startup when production profile lacks admin token).
7. `testProductionProfile_insecureAdminTokenFailsStartup`: **PASS** (Refuses startup on trivial/short tokens in production).
8. `testAesGcm_encryptionDecryptionRoundtrip`: **PASS** (Confirms AES-256-GCM encryption/decryption roundtrip).
9. `testKeyService_freshGenerationEncrypted`: **PASS** (Confirms fresh keys are saved with `ENC:AES-GCM:` prefix).
10. `testKeyService_rebootWithCorrectKeyPreservesSignatures`: **PASS** (Confirms voucher signatures verify across simulated restarts).
11. `testKeyService_wrongKeyThrowsWithoutRegenerating`: **PASS** (Throws `IllegalStateException` on wrong key; leaves DB intact).
12. `testKeyService_missingKeyThrowsWithoutRegenerating`: **PASS** (Throws `IllegalStateException` on missing secret; leaves DB intact).
13. `testKeyService_legacyUnencryptedLoadsInDevelopment`: **PASS** (Loads unencrypted legacy keys in dev with security warning).
14. `testKeyService_autoMigrationReEncryptsInPlace`: **PASS** (Migrates unencrypted key to AES-GCM when opt-in flag is enabled).
15. `testKeyService_productionProfileMissingEncryptionKeyFails`: **PASS** (Refuses startup in production if encryption key is missing).
16. `testDeviceAuthorization_validAdminToken_succeeds`: **PASS** (Confirms device authorization succeeds with valid token).

---

## 5. Persistent Financial State & Milestone Integrity

Read-only inspection of persistent database state via running backend:
- Alice Balance: `₹4,870.00` (Version 6) — Matches baseline
- Bob Balance: `₹1,130.00` (Version 4) — Matches baseline
- Carol Balance: `₹2,000.00` (Version 0) — Matches baseline
- Escrow Balance: `₹0.00` (Version 4) — Matches baseline
- Total System Balance: `₹8,000.00` — Zero-sum invariant maintained
- Total Transactions: `7` (Debits: `₹430.00` / Credits: `₹430.00`) — Balanced
- Physical ₹100 Payment: Settled and unchanged

---

## 6. Phase 1 Verification Conclusion

Phase 1 security remediation is fully verified and confirmed robust. No regressions were introduced, all 16 adversarial tests pass, the persistent database was untouched, and cryptographic identity was strictly preserved.

Ready to proceed to **Phase 2: Timestamp Trust, Expiry and Offline Reconciliation**.
