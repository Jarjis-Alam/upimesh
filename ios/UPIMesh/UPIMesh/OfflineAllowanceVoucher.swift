import Foundation
import Security
import CryptoKit

/// Authoritative offline allowance voucher issued by the banking authority.
///
/// Under the Phase 1 & Phase 2 architecture:
/// - Bound to `allowanceId`, `accountId`, `deviceId`, and `devicePublicKeyFingerprint`.
/// - Holds an escrow reservation on the banking ledger (`system-escrow`).
/// - Cryptographically signed by the Bank Authority using RSASSA-PSS SHA-256.
/// - Enables the authorized client device to sign offline payment instructions without real-time connectivity.
public struct OfflineAllowanceVoucher: Sendable, Codable, Equatable, Identifiable {

    public static let canonicalHeader = "UPI-MESH-ALLOWANCE-V1"
    public static let currentProtocolVersion = 1

    public let allowanceId: String
    public let accountId: String
    public let deviceId: String
    public let devicePublicKeyFingerprint: String
    public let currency: String
    public let allocatedAmount: Decimal
    public var spentAmount: Decimal
    public var lastSequenceNumber: Int
    public let issuedAt: String
    public let expiresAt: String
    public let protocolVersion: Int
    public var status: String
    public let voucherSignature: String
    public let bankPublicKeyBase64: String?

    public var id: String {
        allowanceId
    }

    public var remainingAmount: Decimal {
        let rem = allocatedAmount - spentAmount
        return rem > 0 ? rem : Decimal.zero
    }

    public init(
        allowanceId: String,
        accountId: String,
        deviceId: String,
        devicePublicKeyFingerprint: String,
        currency: String = "INR",
        allocatedAmount: Decimal,
        spentAmount: Decimal = Decimal.zero,
        lastSequenceNumber: Int = 0,
        issuedAt: String,
        expiresAt: String,
        protocolVersion: Int = 1,
        status: String = "ACTIVE",
        voucherSignature: String,
        bankPublicKeyBase64: String? = nil
    ) {
        self.allowanceId = allowanceId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.accountId = accountId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.deviceId = deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.devicePublicKeyFingerprint = devicePublicKeyFingerprint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.currency = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.allocatedAmount = allocatedAmount
        self.spentAmount = spentAmount
        self.lastSequenceNumber = lastSequenceNumber
        self.issuedAt = issuedAt.trimmingCharacters(in: .whitespacesAndNewlines)
        self.expiresAt = expiresAt.trimmingCharacters(in: .whitespacesAndNewlines)
        self.protocolVersion = protocolVersion > 0 ? protocolVersion : Self.currentProtocolVersion
        self.status = status.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.voucherSignature = voucherSignature.trimmingCharacters(in: .whitespacesAndNewlines)
        self.bankPublicKeyBase64 = bankPublicKeyBase64?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Formats amount matching Java's `OfflineAllowance.canonicalAmount(BigDecimal)`.
    public static func canonicalAmount(_ amount: Decimal) -> String {
        let plain = "\(amount)"
        let parts = plain.split(separator: ".")
        if parts.count == 1 {
            return "\(parts[0]).00"
        }
        let frac = String(parts[1])
        if frac.count == 1 {
            return "\(parts[0]).\(frac)0"
        } else if frac.count == 2 {
            return "\(parts[0]).\(frac)"
        } else {
            // scale > 2: strip trailing zeros after decimal point
            var trimmed = frac
            while trimmed.hasSuffix("0") && trimmed.count > 2 {
                trimmed.removeLast()
            }
            return "\(parts[0]).\(trimmed)"
        }
    }

    /// Builds deterministic canonical UTF-8 bytes for cryptographic signing and verification.
    /// Exactly matches Java's `OfflineAllowance.buildCanonicalVoucherBytes(...)`.
    public static func buildCanonicalVoucherBytes(
        allowanceId: String,
        accountId: String,
        deviceId: String,
        deviceFingerprint: String,
        currency: String,
        allocatedAmount: Decimal,
        issuedAt: String,
        expiresAt: String,
        protocolVersion: Int = 1
    ) -> Data {
        let cleanId = allowanceId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAcc = accountId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanDev = deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanFp = deviceFingerprint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanCurr = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let amtStr = canonicalAmount(allocatedAmount)
        let issStr = issuedAt.trimmingCharacters(in: .whitespacesAndNewlines)
        let expStr = expiresAt.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = protocolVersion > 0 ? protocolVersion : currentProtocolVersion

        var sb = ""
        sb.append(canonicalHeader + "\n")
        sb.append("allowanceId:\(cleanId.utf8.count):\(cleanId)\n")
        sb.append("accountId:\(cleanAcc.utf8.count):\(cleanAcc)\n")
        sb.append("deviceId:\(cleanDev.utf8.count):\(cleanDev)\n")
        sb.append("deviceFingerprint:\(cleanFp.utf8.count):\(cleanFp)\n")
        sb.append("currency:\(cleanCurr.utf8.count):\(cleanCurr)\n")
        sb.append("allocatedAmount:\(amtStr.utf8.count):\(amtStr)\n")
        sb.append("issuedAt:\(issStr.utf8.count):\(issStr)\n")
        sb.append("expiresAt:\(expStr.utf8.count):\(expStr)\n")
        sb.append("version:\(String(version).utf8.count):\(version)\n")

        return sb.data(using: .utf8)!
    }

    public func toCanonicalVoucherBytes() -> Data {
        Self.buildCanonicalVoucherBytes(
            allowanceId: allowanceId,
            accountId: accountId,
            deviceId: deviceId,
            deviceFingerprint: devicePublicKeyFingerprint,
            currency: currency,
            allocatedAmount: allocatedAmount,
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            protocolVersion: protocolVersion
        )
    }

    public func toCanonicalVoucherString() -> String {
        String(data: toCanonicalVoucherBytes(), encoding: .utf8) ?? ""
    }

    /// Verifies the bank authority's digital signature against a trusted authority public key.
    ///
    /// CRITICAL SECURITY REQUIREMENT:
    /// Never trust an arbitrary public key provided alongside the voucher.
    /// `trustedBankPublicKeyBase64` must be obtained from a pinned configuration or verified trust store.
    public func verifyBankSignature(
        trustedBankPublicKeyBase64: String
    ) -> (isValid: Bool, errorDescription: String?) {
        guard !voucherSignature.isEmpty else {
            return (false, "Voucher signature is missing or blank")
        }
        let canonical = toCanonicalVoucherBytes()
        return MeshCryptoVerifier.verifyRemoteRSASSA_PSS(
            publicKeyBase64X509: trustedBankPublicKeyBase64,
            message: canonical,
            signatureBase64: voucherSignature
        )
    }

    /// Evaluates whether the allowance has expired relative to a given date (defaults to `Date()`).
    public func isExpired(at date: Date = Date()) -> Bool {
        guard let expDate = ISO8601DateFormatter().date(from: expiresAt) else {
            // Fallback for timestamps with fractional seconds
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let expDate2 = formatter.date(from: expiresAt) {
                return date > expDate2
            }
            return false
        }
        return date > expDate
    }
}

/// Standalone cryptographic signature verifier supporting RSASSA-PSS SHA-256
/// usable across iOS and macOS targets without target-specific identity coupling.
public struct MeshCryptoVerifier {
    public static func verifyRemoteRSASSA_PSS(
        publicKeyBase64X509: String,
        message: Data,
        signatureBase64: String
    ) -> (isValid: Bool, errorDescription: String?) {
        let trimmedKey = publicKeyBase64X509.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let keyData = Data(base64Encoded: trimmedKey) else {
            return (false, "Public key is not valid Base64.")
        }
        let trimmedSig = signatureBase64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sigData = Data(base64Encoded: trimmedSig) else {
            return (false, "Signature is not valid Base64.")
        }

        let importAttrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic
        ]

        var error: Unmanaged<CFError>?
        guard let publicKey = SecKeyCreateWithData(keyData as CFData, importAttrs as CFDictionary, &error) else {
            let desc = error?.takeRetainedValue().localizedDescription ?? "Key import failed"
            return (false, "Failed to import RSA public key: \(desc)")
        }

        guard SecKeyIsAlgorithmSupported(publicKey, .verify, .rsaSignatureMessagePSSSHA256) else {
            return (false, "Algorithm RSASSA-PSS SHA-256 is not supported by imported key.")
        }

        var verifyError: Unmanaged<CFError>?
        let verified = SecKeyVerifySignature(
            publicKey,
            .rsaSignatureMessagePSSSHA256,
            message as CFData,
            sigData as CFData,
            &verifyError
        )

        if verified {
            return (true, nil)
        } else {
            let desc = verifyError?.takeRetainedValue().localizedDescription ?? "Verification failed"
            return (false, desc)
        }
    }
}

