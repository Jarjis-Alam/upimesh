# MeshPay — Security Remediation Phase 3 Report

**Date**: October 17, 2026  
**Status**: COMPLETE & VERIFIED  
**Target Vulnerability**: SEC-06 (Unauthenticated Sender Key Registration and Identity Ownership Binding)  
**Deliverable**: Phase 3 Hardening Report  
**Persistent Database**: `./data/upimesh.mv.db` (100% Preserved; No Reseed; No Deletion)

---

## 1. Executive Summary

Phase 3 addresses the authorization and identity-binding vulnerability identified in **SEC-06**:
Under the initial implementation, `POST /api/keys/register` allowed any unauthenticated caller on the network to register an arbitrary RSA public key for any account or device ID in `SenderKeyRegistry`. Because the registry enforces an immutability policy ("first key registered wins; arbitrary replacement is rejected"), an unauthenticated attacker could preemptively register public keys for target accounts (`alice`, `bob`, etc.), permanently taking over cryptographic identity for subsequent device authorization or allowance issuance.

This phase hardens `POST /api/keys/register` to establish strict authorization boundaries, protect ledger accounts against unauthorized takeover, fail closed in production, and preserve idempotent compatibility for legitimate registered devices.

---

## 2. Threat Analysis & Vulnerability Mechanics

### The First-Registration Takeover Attack (SEC-06)
1. **Target**: An uninitialized account ID (e.g. `alice` in `AccountRepository` with a balance of ₹5,000.00, or a newly created customer account).
2. **Precondition**: `alice` has not yet enrolled an active signing device key in `SenderKeyRegistry`.
3. **Exploitation**:
   - Attacker generates an attacker-controlled RSA-2048 keypair.
   - Attacker calls `POST /api/keys/register` with `accountId="alice"` and `publicKey="<attacker_public_key>"`.
   - The unhardened endpoint accepted the payload with `HTTP 200 REGISTERED`.
   - Subsequent calls from legitimate devices were rejected with `HTTP 400 Bad Request` ("Account 'alice' is already registered with a different public key").
4. **Impact**: Legitimate account holders were locked out of their identity, and payments signed by the attacker's key would be accepted by services resolving `senderKeyRegistry.getPublicKey("alice")`.

---

## 3. Implemented Hardening Measures

In `src/main/java/com/demo/upimesh/ApiController.java`:

### 3.1 Idempotency & Conflict Check
If the account/device is already registered in `SenderKeyRegistry`:
- **Identical Key**: Returns `HTTP 200 OK` with `status: "ALREADY_REGISTERED"` idempotently.
- **Different Key**: Throws `IllegalStateException` ("Arbitrary key replacement is forbidden under prototype trust policy") resulting in `HTTP 400 Bad Request`. Key rotation requires explicit administrative revocation.

### 3.2 Authorization Resolution
Extracted authorization credentials from request headers:
- `X-Admin-Token` or `Authorization: Bearer <token>` (validated against configured admin secret via constant-time comparison `MessageDigest.isEqual`).
- `X-Dev-Provisioning-Token` (validated against configured development provisioning secret).

### 3.3 Strict Production Mode Enforcement
In production profile (`isProductionEnvironment()`), public self-registration of keys is disabled fail-closed:
```java
if (isProductionEnvironment() && !isAuthorized) {
    log.warn("Rejected unauthenticated key registration for '{}' in production profile", normalizedId);
    return ResponseEntity.status(HttpStatus.FORBIDDEN).body(new KeyRegistrationResponse(
            "FORBIDDEN",
            normalizedId,
            "Public key self-registration is disabled in production profile: certified onboarding required."
    ));
}
```

### 3.4 Ledger Account Protection
If the target identifier represents an existing funding ledger account (`accountRepository.existsById(normalizedId)`), unauthenticated registration is strictly rejected with `HTTP 401 Unauthorized`:
```java
if (accountRepository != null && accountRepository.existsById(normalizedId) && !isAuthorized) {
    log.warn("Rejected unauthenticated key registration for existing ledger account '{}'", normalizedId);
    return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(new KeyRegistrationResponse(
            "UNAUTHORIZED",
            normalizedId,
            "Unauthorized key enrollment: registering a public key for ledger account '" + normalizedId
            + "' requires administrator authorization or development provisioning credentials."
    ));
}
```

### 3.5 Backward Compatibility Overload
Preserved the 3-parameter Java method signature `registerSenderKey(request, accountId, publicKey)` delegating to the 6-parameter authorized method, ensuring that existing internal and mock tests remain fully compatible.

---

## 4. Automated Adversarial Test Suite Results

A dedicated security test suite `SecurityRemediationPhase3Test.java` was created and executed:
- **Total Tests Run**: 8
- **Failures**: 0
- **Errors**: 0
- **Pass Rate**: 100%

| Test Case | Scenario Verified | HTTP Status | Invariant Verified |
| :--- | :--- | :--- | :--- |
| `3.1 testUnauthorizedRegistration_existingLedgerAccount_rejected` | Unauthenticated attacker calls `/api/keys/register` for `alice` | **401 Unauthorized** | First-registration takeover of ledger account blocked |
| `3.2 testAuthorizedRegistration_withAdminToken_succeeds` | Legitimate administrator registers key for `alice` | **200 OK** (`REGISTERED`) | Admin-authorized enrollment succeeds |
| `3.3 testAuthorizedRegistration_withDevProvisioningToken_succeeds` | Legitimate tester registers key for `bob` using dev token | **200 OK** (`REGISTERED`) | Controlled development provisioning succeeds |
| `3.4 testDuplicateRegistration_sameKey_idempotent` | Re-registering identical key without headers | **200 OK** (`ALREADY_REGISTERED`) | Safe idempotent re-affirmation without re-auth |
| `3.5 testConflictingKeyRegistration_differentKey_rejected` | Attempting to overwrite existing key with different key | **400 Bad Request** | Arbitrary key replacement forbidden |
| `3.6 testProductionProfile_unauthenticatedRegistration_forbidden` | Registering device key in production profile without token | **403 Forbidden** | Production self-registration disabled |
| `3.7 testProductionProfile_withAdminToken_succeeds` | Registering device key in production profile with admin token | **200 OK** (`REGISTERED`) | Production admin enrollment authorized |
| `3.8 testConcurrentRegistration_safe` | 4 concurrent threads registering same key simultaneously | **200 OK** across all threads | Concurrency and unique constraints thread-safe |

---

## 5. Production Identity Bootstrap & Limitations

### Prototype vs Production Onboarding
1. **Prototype Trust Mechanism**: In this educational prototype, key binding is secured via:
   - Administrative pairing token (`X-Admin-Token`), or
   - Out-of-band development provisioning secret (`X-Dev-Provisioning-Token`), or
   - Verified bank account consent (`/api/owner/keys/register`).
2. **Production Requirements**:
   In commercial UPI deployments, self-asserted public keys or administrator tokens cannot substitute for customer identity. Account-to-key binding requires:
   - NPCI Common Library (CL) hardware-bound key attestation.
   - Cryptographic SIM-binding via telecom carrier out-of-band SMS challenge.
   - Bank-certified X.509 Device Certificates issued by a banking CA during initial customer onboarding.

---

## 6. Phase 3 Verification Status

Phase 3 is complete and verified. Vulnerability **SEC-06** is remediated, all 8 adversarial tests pass, and persistent database `./data/upimesh.mv.db` is 100% preserved.

Ready to proceed to **Phase 4: Device Identity and Signing-Key Protection**.
