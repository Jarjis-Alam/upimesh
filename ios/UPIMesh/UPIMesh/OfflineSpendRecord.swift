import Foundation
import Security
import CryptoKit

/// Canonical offline spend record representing a payment instruction debited from an offline allowance.
///
/// Cryptographically bound to:
/// - `allowanceId`: The authoritative banking escrow allocation.
/// - `paymentId`: Unique transaction ID preventing replay.
/// - `payerAccountId` & `payerDeviceId`: Authorized debtor identity and signing device.
/// - `recipientAccountId`: Creditor account.
/// - `amount` & `currency`: Exact monetary transfer amount.
/// - `sequenceNumber` & `cumulativeSpentAmount`: Anti-double-spending sequence evidence.
/// - `createdAt`: Instant timestamp of spend generation.
/// - `voucherSignature`: Original bank voucher signature proving escrow backing.
/// - `payerSignature`: Payer's RSASSA-PSS digital signature over canonical spend bytes.
/// - `protocolVersion`: Protocol version (1).
public struct OfflineSpendRecord: Sendable, Codable, Equatable, Identifiable {

    public static let canonicalHeader = "UPI-MESH-SPEND-V1"
    public static let currentProtocolVersion = 1

    public let allowanceId: String
    public let paymentId: String
    public let payerAccountId: String
    public let payerDeviceId: String
    public let recipientAccountId: String
    public let amount: Decimal
    public let currency: String
    public let sequenceNumber: Int
    public let cumulativeSpentAmount: Decimal
    public let createdAt: String
    public let voucherSignature: String
    public let payerSignature: String
    public let protocolVersion: Int

    public var id: String {
        paymentId
    }

    public var amountDouble: Double {
        NSDecimalNumber(decimal: amount).doubleValue
    }

    public var cumulativeSpentDouble: Double {
        NSDecimalNumber(decimal: cumulativeSpentAmount).doubleValue
    }

    public init(
        allowanceId: String,
        paymentId: String,
        payerAccountId: String,
        payerDeviceId: String,
        recipientAccountId: String,
        amount: Decimal,
        currency: String = "INR",
        sequenceNumber: Int,
        cumulativeSpentAmount: Decimal,
        createdAt: String,
        voucherSignature: String,
        payerSignature: String,
        protocolVersion: Int = 1
    ) {
        self.allowanceId = allowanceId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.paymentId = paymentId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.payerAccountId = payerAccountId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.payerDeviceId = payerDeviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.recipientAccountId = recipientAccountId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.amount = amount
        self.currency = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.sequenceNumber = sequenceNumber
        self.cumulativeSpentAmount = cumulativeSpentAmount
        self.createdAt = createdAt.trimmingCharacters(in: .whitespacesAndNewlines)
        self.voucherSignature = voucherSignature.trimmingCharacters(in: .whitespacesAndNewlines)
        self.payerSignature = payerSignature.trimmingCharacters(in: .whitespacesAndNewlines)
        self.protocolVersion = protocolVersion > 0 ? protocolVersion : Self.currentProtocolVersion
    }

    /// Formats amount matching Java's `OfflineSpendRecord.canonicalAmount(BigDecimal)`.
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
            var trimmed = frac
            while trimmed.hasSuffix("0") && trimmed.count > 2 {
                trimmed.removeLast()
            }
            return "\(parts[0]).\(trimmed)"
        }
    }

    /// Builds deterministic canonical UTF-8 bytes for cryptographic signing and verification.
    /// Matches Java's `OfflineSpendRecord.buildCanonicalSpendBytes(...)` byte-for-byte.
    public static func buildCanonicalSpendBytes(
        allowanceId: String,
        paymentId: String,
        payerAccountId: String,
        payerDeviceId: String,
        recipientAccountId: String,
        amount: Decimal,
        currency: String = "INR",
        sequenceNumber: Int,
        cumulativeSpentAmount: Decimal,
        createdAt: String,
        voucherSignature: String,
        protocolVersion: Int = 1
    ) -> Data {
        let cleanAlw = allowanceId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPayId = paymentId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPayer = payerAccountId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanDev = payerDeviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanRecip = recipientAccountId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let amtStr = canonicalAmount(amount)
        let cleanCurr = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let seqStr = String(sequenceNumber)
        let cumStr = canonicalAmount(cumulativeSpentAmount)
        let timeStr = createdAt.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanVoucherSig = voucherSignature.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = protocolVersion > 0 ? protocolVersion : currentProtocolVersion

        var sb = ""
        sb.append(canonicalHeader + "\n")
        sb.append("allowanceId:\(cleanAlw.utf8.count):\(cleanAlw)\n")
        sb.append("paymentId:\(cleanPayId.utf8.count):\(cleanPayId)\n")
        sb.append("payerAccountId:\(cleanPayer.utf8.count):\(cleanPayer)\n")
        sb.append("payerDeviceId:\(cleanDev.utf8.count):\(cleanDev)\n")
        sb.append("recipientAccountId:\(cleanRecip.utf8.count):\(cleanRecip)\n")
        sb.append("currency:\(cleanCurr.utf8.count):\(cleanCurr)\n")
        sb.append("amount:\(amtStr.utf8.count):\(amtStr)\n")
        sb.append("sequenceNumber:\(seqStr.utf8.count):\(seqStr)\n")
        sb.append("cumulativeSpentAmount:\(cumStr.utf8.count):\(cumStr)\n")
        sb.append("createdAt:\(timeStr.utf8.count):\(timeStr)\n")
        sb.append("voucherSignature:\(cleanVoucherSig.utf8.count):\(cleanVoucherSig)\n")
        sb.append("version:\(String(version).utf8.count):\(version)\n")

        return sb.data(using: .utf8)!
    }

    public func toCanonicalSpendBytes() -> Data {
        Self.buildCanonicalSpendBytes(
            allowanceId: allowanceId,
            paymentId: paymentId,
            payerAccountId: payerAccountId,
            payerDeviceId: payerDeviceId,
            recipientAccountId: recipientAccountId,
            amount: amount,
            currency: currency,
            sequenceNumber: sequenceNumber,
            cumulativeSpentAmount: cumulativeSpentAmount,
            createdAt: createdAt,
            voucherSignature: voucherSignature,
            protocolVersion: protocolVersion
        )
    }

    public func toCanonicalSpendString() -> String {
        String(data: toCanonicalSpendBytes(), encoding: .utf8) ?? ""
    }

    /// Verifies the payer's digital signature against the payer's device public key.
    public func verifyPayerSignature(
        payerPublicKeyBase64X509: String
    ) -> (isValid: Bool, errorDescription: String?) {
        guard !payerSignature.isEmpty else {
            return (false, "Payer signature is missing or blank")
        }
        let canonical = toCanonicalSpendBytes()
        return MeshCryptoVerifier.verifyRemoteRSASSA_PSS(
            publicKeyBase64X509: payerPublicKeyBase64X509,
            message: canonical,
            signatureBase64: payerSignature
        )
    }
}

// MARK: - Shared Allowance DTOs

public struct BankAuthorityPublicKeyResponseDTO: Codable, Sendable, Equatable {
    public let keyId: String
    public let algorithm: String
    public let format: String
    public let publicKeyBase64: String

    public init(keyId: String, algorithm: String, format: String, publicKeyBase64: String) {
        self.keyId = keyId
        self.algorithm = algorithm
        self.format = format
        self.publicKeyBase64 = publicKeyBase64
    }
}

public struct OfflineSpendPaymentDTO: Codable, Sendable, Equatable {
    public let id: String?
    public let paymentId: String
    public let allowanceId: String
    public let payerAccountId: String
    public let payerDeviceId: String
    public let recipientAccountId: String
    public let amount: Decimal
    public let currency: String
    public let sequenceNumber: Int
    public let cumulativeSpentAmount: Decimal
    public let createdAt: String?
    public let settledAt: String?
    public let status: String
    public let voucherSignature: String?
    public let payerSignature: String?
    public let protocolVersion: Int?

    public init(
        id: String? = nil,
        paymentId: String,
        allowanceId: String,
        payerAccountId: String,
        payerDeviceId: String,
        recipientAccountId: String,
        amount: Decimal,
        currency: String = "INR",
        sequenceNumber: Int,
        cumulativeSpentAmount: Decimal,
        createdAt: String? = nil,
        settledAt: String? = nil,
        status: String,
        voucherSignature: String? = nil,
        payerSignature: String? = nil,
        protocolVersion: Int? = 1
    ) {
        self.id = id
        self.paymentId = paymentId
        self.allowanceId = allowanceId
        self.payerAccountId = payerAccountId
        self.payerDeviceId = payerDeviceId
        self.recipientAccountId = recipientAccountId
        self.amount = amount
        self.currency = currency
        self.sequenceNumber = sequenceNumber
        self.cumulativeSpentAmount = cumulativeSpentAmount
        self.createdAt = createdAt
        self.settledAt = settledAt
        self.status = status
        self.voucherSignature = voucherSignature
        self.payerSignature = payerSignature
        self.protocolVersion = protocolVersion
    }
}

