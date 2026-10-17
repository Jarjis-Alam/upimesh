# MeshPay Security Remediation Report — Phase 10: Logging, Auditability and Recovery

## 1. Executive Summary & Audit Scope

Phase 10 evaluates the observability, security telemetry, audit durability, and disaster recovery procedures of the MeshPay backend.

In financial infrastructure, logging and auditability must balance two competing security requirements:
1. **High Observability**: Fraud attempts, sequence forks, and authentication failures must be recorded with non-repudiable forensic detail.
2. **Strict Secret Hygiene**: Private signing keys, key-encryption keys, administrator tokens, and sensitive customer credentials must **never** be emitted into log streams, console output, or error messages.

This audit confirms that MeshPay enforces strict secret sanitization, provides durable security event persistence via autonomous database transactions, and maintains operational recovery procedures that preserve historical cryptographic identities.

---

## 2. Security Event & Fraud Telemetry

When security violations or integrity anomalies occur during offline reconciliation, they are immediately captured in the `offline_security_events` database table via `OfflineSecurityAuditService.java`:

| Event Type | Trigger Condition | Forensic Metadata Captured | Automated Countermeasure |
| :--- | :--- | :--- | :--- |
| `SEQUENCE_FORK_CONFLICT` | Two distinct payment IDs claim the identical sequence number under one allowance | Allowance ID, Payer Account, Payer Device, Incoming Payment ID, Existing Payment ID, Sequence Number, Timestamp | **Immediate Allowance Revocation** (`REVOKED`); unspent escrow frozen; settlement rejected |
| `OVERSPEND_ATTEMPT` | Cumulative spent amount exceeds the allocated voucher limit | Allowance ID, Payer Account, Device ID, Attempted Amount, Remaining Limit, Sequence Number | Settlement rejected; security alert persisted |
| `TAMPERED_VOUCHER_SIGNATURE` | Bank Authority voucher signature fails RSASSA-PSS verification | Allowance ID, Payment ID, Sequence Number, Detection Timestamp | Settlement rejected; security alert persisted |
| `INVALID_PAYER_SIGNATURE` | Payer device signature fails verification against registered public key | Allowance ID, Payment ID, Device ID, Sequence Number, Detection Timestamp | Settlement rejected; security alert persisted |
| `CUMULATIVE_AMOUNT_MISMATCH` | Spend cumulative amount does not match running ledger total | Allowance ID, Payment ID, Sequence Number, Expected vs Claimed Amount | Settlement rejected; security alert persisted |

### Autonomous Transaction Durability (`REQUIRES_NEW`):
In `OfflineSecurityAuditService.java`, event logging and allowance revocation are annotated with:
```java
@Transactional(propagation = Propagation.REQUIRES_NEW)
public void recordSecurityEventAndRevokeAllowance(...)
```
This guarantees that even when the payment settlement transaction encounters an exception and rolls back all ledger balance modifications, the security event and allowance revocation commit independently to the database.

---

## 3. Secret Hygiene and Log Sanitization Audit

An automated inspection of all logging call sites across the Java backend and Swift clients verified:

1. **Zero Secret Leakage**:
   - Private RSA keys are never converted to string logs.
   - Master key-encryption secrets (`UPI_MESH_BANK_AUTHORITY_ENCRYPTION_KEY`) are never logged.
   - Administrator pairing tokens (`X-Admin-Token` / Bearer) are sanitized; logs only report success or failure along with the target device/account identifier.
2. **Structured Parameterization**:
   - Loggers strictly use SLF4J parameterized placeholders (`log.warn("Device '{}' authorization rejected", id)`), preventing log injection attacks via untrusted user inputs.
3. **Suppression of Production Stack Traces**:
   - `server.error.include-stacktrace=never`
   - `server.error.include-message=never`
   - Unhandled runtime exceptions return sanitized RFC 7807 / standard HTTP error codes without disclosing internal SQL queries or memory dumps.

---

## 4. Disaster Recovery & Key Continuity Procedures

### A. Bank Authority Key Continuity
- **The Invariant**: Under no circumstance should a startup failure or database error trigger the silent regeneration of the master Bank Authority keypair (`bank-authority-master`).
- **Fail-Closed Behavior**: If the key-encryption secret is incorrect or missing, or if database ciphertext is corrupted, `BankAuthorityKeyService` throws an unrecoverable `IllegalStateException` and aborts application startup.
- **Voucher Preservation**: Because the master key is never overwritten or regenerated on failure, all existing vouchers held by physical devices remain cryptographically valid and verifiable.

### B. Persistent Database Backup & Restoration (`data/upimesh.mv.db`)
1. **Cold Backup Procedure**:
   - Stop the backend process (`kill <pid>`).
   - Copy `data/upimesh.mv.db` to a secure, encrypted backup location.
   - Restart the backend.
2. **Online Hot Backup (H2 SCRIPT)**:
   - Administrators can execute a non-destructive SQL backup using H2's `SCRIPT TO 'backup.sql'` command through authenticated administration tools.
3. **Restoration**:
   - Restoring the `.mv.db` file restores all account balances, transaction journals, registered device keys, active allowances, and settled payment records without requiring key rotation or re-enrollment.

---

## 5. Audit Immutability Boundary Disclosures

In accordance with strict application security principles:
- **No Claim of Blockchain-Style Immutability**: The audit events and ledger transactions reside in standard relational database tables (`offline_security_events`, `transactions`).
- **Privileged Access Boundary**: A system administrator or DBA with direct filesystem access or superuser database privileges (`SA`) has the technical capability to modify or delete database rows.
- **Production Requirement for Commercial Release**: Production environments must stream security logs to an external, write-once-read-many (WORM) append-only security information and event management (SIEM) system (e.g. Splunk, AWS CloudWatch Logs, Datadog) with cryptographic log hashing.
