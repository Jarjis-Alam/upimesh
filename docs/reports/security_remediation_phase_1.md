# MeshPay — Security Remediation Phase 1 Report

**Date**: October 17, 2026  
**Status**: COMPLETE & VERIFIED  
**Target Milestone**: Preservation of Verified ₹100 Physical-Device Offline Payment  
**Target Vulnerabilities**: SEC-02 (Bank Authority Key Plaintext Storage) & SEC-04 (Unsafe Admin Authentication Defaults)  
**Database State**: `./data/upimesh.mv.db` (100% Preserved; No Reseed; No Deletion)

---

## 1. Executive Summary

Phase 1 of security remediation has successfully eliminated the two primary credential vulnerabilities identified in the release readiness audit:
1. **Administrative Authentication Hardening (SEC-04)**:
   - Disabled simulator demo authentication (`upimesh.demo-auth-enabled=false`) by default across all runtime profiles.
   - Enforced fail-closed startup validation in production profile (`prod`/`production`), requiring an explicitly configured, high-entropy administrator token (`UPI_MESH_ADMIN_TOKEN` or `upimesh.admin-token`, length $\ge 16$, no trivial tokens).
   - Removed hardcoded default token fallback (`demo-token-admin`) from iOS client `APIConfiguration.swift`.
2. **Bank Authority Key Protection (SEC-02)**:
   - Implemented **authenticated encryption at rest** using **AES-256-GCM** (12-byte random IV, 128-bit authentication tag) for the Bank Authority's master RSA private key.
   - Derived encryption keys from an external secret (`UPI_MESH_KEY_ENCRYPTION_KEY` or `upimesh.bank-authority.encryption-key`) via SHA-256 domain-separated derivation or raw 256-bit key parsing.
   - Strictly ensured the encryption key is **never stored alongside the ciphertext**.
   - Made decryption **fail-closed**: if decryption fails, startup halts immediately without silent key regeneration.
   - Maintained **100% backward compatibility** with existing development database keys without risking database corruption or invalidating existing vouchers.

---

## 2. Changes Implemented

### Backend Changes

#### A. [FinancialSecurityService.java](file:///Users/munshijarjisalam/Documents/Projects/upimesh/src/main/java/com/demo/upimesh/FinancialSecurityService.java)
- Added `@PostConstruct validateSecurityConfigurationOnStartup()`:
  - If profile is `prod` or `production`:
    - Asserts `demoAuthEnabled == false`.
    - Asserts administrator token is configured, not in `REJECTED_INSECURE_TOKENS`, not equal to `demo-token-admin`, and length $\ge 16$.
    - Halts context startup immediately if validation fails.
- Extracted reusable static helper `isProduction(Environment environment)`.
- When `demoAuthEnabled=false` (default), all demo tokens are rejected with HTTP 401 Unauthorized unless an administrative token is explicitly configured in the environment.

#### B. [BankAuthorityKeyService.java](file:///Users/munshijarjisalam/Documents/Projects/upimesh/src/main/java/com/demo/upimesh/BankAuthorityKeyService.java)
- Added AES-256-GCM authenticated encryption and decryption helpers:
  - `deriveAesKey(String secret)`
  - `encryptPrivateKey(byte[] pkcs8DerBytes, SecretKey aesKey, SecureRandom random)`
  - `decryptPrivateKey(String encryptedPayload, SecretKey aesKey)`
  - Format: `ENC:AES-GCM:<base64(12-byte IV + ciphertext + 16-byte tag)>`.
- Added external secret resolution via `UPI_MESH_KEY_ENCRYPTION_KEY` / `upimesh.bank-authority.encryption-key`.
- Updated `initializeOrLoadKeyPair()`:
  - Checks if stored key starts with `ENC:AES-GCM:`. If so, decrypts fail-closed.
  - If decryption fails (corrupted data or wrong secret), throws `IllegalStateException` and **aborts startup without key regeneration**.
  - If unencrypted (legacy format), logs a warning and loads the key in development. In production profile, unencrypted keys trigger a startup exception.
  - Added opt-in migration support (`upimesh.bank-authority.auto-migrate-encryption=true`): safely re-encrypts in-place after verifying roundtrip integrity against the original bytes.
  - When generating fresh keys with an encryption key configured, automatically encrypts with AES-256-GCM before saving.

#### C. [application.properties](file:///Users/munshijarjisalam/Documents/Projects/upimesh/src/main/resources/application.properties) & [application-prod.properties](file:///Users/munshijarjisalam/Documents/Projects/upimesh/src/main/resources/application-prod.properties)
- Set `upimesh.demo-auth-enabled=false` by default.
- Added commented configuration keys for `upimesh.bank-authority.encryption-key`.
- Disabled auto-migration by default (`upimesh.bank-authority.auto-migrate-encryption=false`) to protect database files.

### Client Changes

#### [APIConfiguration.swift](file:///Users/munshijarjisalam/Documents/Projects/upimesh/ios/UPIMesh/UPIMesh/APIConfiguration.swift)
- Removed hardcoded default `"demo-token-admin"` fallback in `authToken` property getter.
- When no token is configured in `UserDefaults`, `authToken` returns `nil`.

---

## 3. Automated Test Suite Results

All automated tests across backend and client passed with zero failures:

| Test Suite | Command | Tests Run | Result | Duration |
| :--- | :--- | :--- | :--- | :--- |
| **New Phase 1 Security Suite** | `./mvnw test -Dtest=SecurityRemediationPhase1Test` | 16 | **16 Passed, 0 Failed** | 2.6s |
| **Full Backend Suite** | `./mvnw test` | 293 | **293 Passed, 0 Failed** | 1m 29s |
| **iOS / macOS Client Suite** | `./run_ios_tests.sh` | 83 | **83 Passed, 0 Failed** | 12.4s |
| **macOS App Bundle** | `./build_macos_companion.sh` | — | **Build Succeeded** | 8.2s |
| **Total Automated Tests** | — | **376** | **376 Passed (100%)** | — |

### Detailed Breakdown of `SecurityRemediationPhase1Test`:
1. `testAdminEndpoints_anonymousRejected`: Confirms `/api/accounts`, `/api/transactions`, `/api/reconciliation`, and `/api/devices/authorize` reject unauthenticated requests with HTTP 401.
2. `testAdminEndpoints_incorrectTokenRejected`: Confirms bad tokens return HTTP 401.
3. `testReconciliation_nonAdminForbidden`: Confirms non-admin user tokens return HTTP 403 Forbidden.
4. `testDemoToken_failsWhenDemoAuthDisabled`: Confirms `demo-token-admin` fails when `demoAuthEnabled=false`.
5. `testExplicitAdminToken_succeeds`: Confirms explicitly configured dev token succeeds.
6. `testProductionProfile_missingAdminTokenFailsStartup`: Confirms production profile halts on missing token.
7. `testProductionProfile_insecureAdminTokenFailsStartup`: Confirms production profile rejects trivial/short tokens.
8. `testAesGcm_encryptionDecryptionRoundtrip`: Validates AES-256-GCM authenticated encryption.
9. `testKeyService_freshGenerationEncrypted`: Validates new keys are persisted with `ENC:AES-GCM:` prefix.
10. `testKeyService_rebootWithCorrectKeyPreservesSignatures`: Validates key survives restart and preserves mathematical voucher signatures.
11. `testKeyService_wrongKeyThrowsWithoutRegenerating`: Confirms wrong key throws `IllegalStateException` and leaves repo untouched.
12. `testKeyService_missingKeyThrowsWithoutRegenerating`: Confirms missing key throws `IllegalStateException` and leaves repo untouched.
13. `testKeyService_legacyUnencryptedLoadsInDevelopment`: Confirms backward compatibility for existing development databases.
14. `testKeyService_autoMigrationReEncryptsInPlace`: Confirms opt-in migration safely encrypts legacy keys at rest.
15. `testKeyService_productionProfileMissingEncryptionKeyFails`: Confirms production profile enforces key encryption.

---

## 4. Verification of Live Database & Milestone Invariants

After restarting the Spring Boot server with the remediation code active:

### A. Bank Authority Public Key Preservation
Endpoint: `GET http://127.0.0.1:8080/api/allowance/bank-public-key`
- **Result**: Identical before and after remediation.
```json
{
  "keyId": "bank-authority-master",
  "format": "X.509",
  "algorithm": "RSA",
  "publicKeyBase64": "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAw/s+Rg4ukd3DZ8SaF/TTWP4sMip7rIHPnQ7oGpp//2i9jIVNpfXdH9Q9dnq9hdXRC/ND1bpCGn3fDzyXtXgpW2mHzSjF/MSnZisRa20KvH4lRm0PWOdZVQ02ZtfEwMS0TD6HCMMX0Ck0r5/Nlbd/hlvCD8qIqRRynXTyNspl/cgQnIhW2jOvbYVcugzyw3FtQRRaK7ozlndXQmth4kTmVk835nPJbVv3smhRmB2vduq+W1jy/ac/J8tjSH5hckNMtyo/AVCHUbPFY1yN3hzKHI1BQTD5UXKi1LsCbDK/1Gek7BeFPBBozz7NIdhk9oswW+o9hy6fWKBPLOFbn43tlQIDAQAB"
}
```

### B. Account Balances (`GET /api/accounts`)
- **Anonymous Access**: HTTP 401 Unauthorized.
- **Incorrect Token**: HTTP 401 Unauthorized.
- **With Configured Admin Token**:
  - `alice`: **₹4,870.00** (v6)
  - `bob`: **₹1,130.00** (v4)
  - `carol`: **₹2,000.00** (v0)
  - `system-escrow`: **₹0.00** (v4)
  - **Zero-Sum Balance Total**: **₹8,000.00** (Preserved)

### C. Settled Payment History (`GET /api/allowance/{id}/spends`)
- Payment `dd3bd00c-646a-4d8d-9fb2-828505c3e9b4` remains persisted with status **`SETTLED`**, sequence `1`, cumulative ₹100.00, and RSASSA-PSS signature.

### D. Reconciliation Status (`GET /api/reconciliation`)
- `isReconciled`: **`true`**
- `structuralStatus`: **`BALANCED`**
- `balanceStatus`: **`RECONCILED`**
- `discrepancies`: **`[]`**

---

## 5. Configuration Guide

### Development Environment
To run the server in development with administrative access enabled:
```bash
export UPI_MESH_ADMIN_TOKEN="your-chosen-local-admin-secret"
./mvnw spring-boot:run
```
*(Optional)* To also enable private key encryption at rest in development:
```bash
export UPI_MESH_KEY_ENCRYPTION_KEY="your-local-key-encryption-secret"
./mvnw spring-boot:run
```

### Production Environment
In production (`SPRING_PROFILES_ACTIVE=prod` or `--spring.profiles.active=production`), the application strictly enforces:
1. `UPI_MESH_ADMIN_TOKEN` must be set, length $\ge 16$, and non-trivial.
2. `UPI_MESH_KEY_ENCRYPTION_KEY` must be set.
3. Private keys in the database must be encrypted with `ENC:AES-GCM:`.
```bash
export SPRING_PROFILES_ACTIVE="prod"
export UPI_MESH_ADMIN_TOKEN="Production-Admin-Secret-Minimum-16-Chars!"
export UPI_MESH_KEY_ENCRYPTION_KEY="Production-Bank-Key-Encryption-Secret-32Bytes!"
java -jar target/upimesh-0.0.1-SNAPSHOT.jar
```

---

## 6. Database Migration & Rollback Procedures

### Safe In-Place Key Migration Procedure
If an operator wishes to encrypt the legacy unencrypted Bank Authority key in an existing persistent database:
1. Create a full backup of `./data/upimesh.mv.db`:
   ```bash
   cp data/upimesh.mv.db data/upimesh.mv.db.bak
   ```
2. Launch the backend with an encryption key and the migration flag enabled:
   ```bash
   UPI_MESH_KEY_ENCRYPTION_KEY="my-persistent-encryption-key" \
   ./mvnw spring-boot:run -Dupimesh.bank-authority.auto-migrate-encryption=true
   ```
3. Observe log output:
   `Successfully migrated bank authority private key to AES-GCM encrypted format at rest.`
4. Verify via endpoint:
   `curl -s http://127.0.0.1:8080/api/allowance/bank-public-key` confirms the public key is identical.
5. In future runs, unset `upimesh.bank-authority.auto-migrate-encryption` and supply `UPI_MESH_KEY_ENCRYPTION_KEY`.

### Rollback Procedure
If decryption issues occur or an encryption secret is misplaced before migration:
1. Restore the database file:
   ```bash
   cp data/upimesh.mv.db.bak data/upimesh.mv.db
   ```
2. Unset `UPI_MESH_KEY_ENCRYPTION_KEY`. The server will cleanly load the legacy unencrypted key in development mode.
