import Foundation

/// Errors that can occur during `PaymentInstruction` validation and canonicalization.
public enum PaymentInstructionError: LocalizedError, Equatable {
    case blankField(String)
    case invalidAccounts(String)
    case invalidAmount(String)
    case invalidTimestamp(String)

    public var errorDescription: String? {
        switch self {
        case .blankField(let field):
            return "\(field) must not be blank"
        case .invalidAccounts(let msg):
            return msg
        case .invalidAmount(let msg):
            return msg
        case .invalidTimestamp(let msg):
            return msg
        }
    }
}

/// A nanosecond-precision UTC timestamp matching OpenJDK's `java.time.Instant`.
///
/// Implements deterministic serialization matching OpenJDK's `DateTimeFormatter.ISO_INSTANT`
/// where fractional seconds are omitted when 0, formatted to 3 digits for milliseconds,
/// 6 digits for microseconds, or 9 digits for nanoseconds.
public struct PaymentInstant: Sendable, Codable, Equatable, Comparable, CustomStringConvertible {
    public let epochSecond: Int64
    public let nano: Int32

    public init(epochSecond: Int64, nano: Int32 = 0) {
        var sec = epochSecond
        var n = nano
        if n >= 1_000_000_000 {
            sec += Int64(n / 1_000_000_000)
            n = n % 1_000_000_000
        } else if n < 0 {
            let borrow = (abs(n) + 999_999_999) / 1_000_000_000
            sec -= Int64(borrow)
            n += borrow * 1_000_000_000
        }
        self.epochSecond = sec
        self.nano = n
    }

    public init(date: Date) {
        let timeInterval = date.timeIntervalSince1970
        let sec = Int64(floor(timeInterval))
        let n = Int32(round((timeInterval - Double(sec)) * 1_000_000_000))
        self.init(epochSecond: sec, nano: n)
    }

    public static func now() -> PaymentInstant {
        var tv = timeval()
        gettimeofday(&tv, nil)
        let sec = Int64(tv.tv_sec)
        let nano = Int32(tv.tv_usec) * 1_000
        return PaymentInstant(epochSecond: sec, nano: nano)
    }

    /// Formats the instant into standard ISO-8601 UTC string matching OpenJDK's `Instant.toString()`.
    public var isoString: String {
        let date = Date(timeIntervalSince1970: Double(epochSecond))
        let calendar = Calendar(identifier: .gregorian)
        let comp = calendar.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: date)

        let year = comp.year ?? 1970
        let month = comp.month ?? 1
        let day = comp.day ?? 1
        let hour = comp.hour ?? 0
        let minute = comp.minute ?? 0
        let second = comp.second ?? 0

        let base = String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d",
            year, month, day, hour, minute, second
        )

        if nano == 0 {
            return "\(base)Z"
        } else if nano % 1_000_000 == 0 {
            return "\(base).\(String(format: "%03d", nano / 1_000_000))Z"
        } else if nano % 1_000 == 0 {
            return "\(base).\(String(format: "%06d", nano / 1_000))Z"
        } else {
            return "\(base).\(String(format: "%09d", nano))Z"
        }
    }

    public var description: String {
        isoString
    }

    /// Parses an ISO-8601 UTC instant string (e.g. "2026-10-12T12:00:00Z" or "2026-10-12T12:00:00.123456Z").
    public static func parse(_ string: String) throws -> PaymentInstant {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix("Z") else {
            throw PaymentInstructionError.invalidTimestamp("Expected UTC timestamp ending with 'Z': \(string)")
        }

        let withoutZ = String(trimmed.dropLast())
        let parts = withoutZ.split(separator: ".")

        let mainPart = String(parts[0])
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

        guard let parsedDate = formatter.date(from: mainPart) else {
            throw PaymentInstructionError.invalidTimestamp("Invalid ISO-8601 date-time format: \(string)")
        }

        let epochSec = Int64(parsedDate.timeIntervalSince1970)
        var nanoVal: Int32 = 0

        if parts.count > 1 {
            let fracStr = String(parts[1])
            guard !fracStr.isEmpty, fracStr.allSatisfy({ $0.isNumber }) else {
                throw PaymentInstructionError.invalidTimestamp("Invalid fractional second: \(string)")
            }
            let padded = fracStr.padding(toLength: 9, withPad: "0", startingAt: 0)
            let prefix9 = String(padded.prefix(9))
            if let parsedNano = Int32(prefix9) {
                nanoVal = parsedNano
            }
        }

        return PaymentInstant(epochSecond: epochSec, nano: nanoVal)
    }

    public static func < (lhs: PaymentInstant, rhs: PaymentInstant) -> Bool {
        if lhs.epochSecond != rhs.epochSecond {
            return lhs.epochSecond < rhs.epochSecond
        }
        return lhs.nano < rhs.nano
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let str = try container.decode(String.self)
        self = try PaymentInstant.parse(str)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(isoString)
    }
}

/// Represents an immutable UPI Offline Mesh Payment Instruction.
///
/// Matches the exact Java record `com.demo.upimesh.model.PaymentInstruction` byte-for-byte:
/// - Deterministic canonical byte serialization for RSASSA-PSS digital signature generation and verification.
/// - Unambiguous length-prefixed ASCII/UTF-8 structure (`UPI-MESH-INSTRUCTION-V1`).
/// - Strict business invariant validation.
public struct PaymentInstruction: Sendable, Codable, Equatable {
    public let paymentId: String
    public let fromAccount: String
    public let toAccount: String
    public let amount: Decimal
    public let createdAt: PaymentInstant
    public let nonce: String
    public let signature: String?

    /// Canonical constructor validating all business rules.
    public init(
        paymentId: String,
        fromAccount: String,
        toAccount: String,
        amount: Decimal,
        createdAt: PaymentInstant,
        nonce: String,
        signature: String? = nil
    ) throws {
        if paymentId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw PaymentInstructionError.blankField("paymentId")
        }
        if fromAccount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw PaymentInstructionError.blankField("fromAccount")
        }
        if toAccount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw PaymentInstructionError.blankField("toAccount")
        }
        if fromAccount == toAccount {
            throw PaymentInstructionError.invalidAccounts("Sender and receiver must be different")
        }
        if amount <= 0 {
            throw PaymentInstructionError.invalidAmount("Transfer amount must be greater than zero")
        }
        if nonce.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw PaymentInstructionError.blankField("nonce")
        }

        self.paymentId = paymentId
        self.fromAccount = fromAccount
        self.toAccount = toAccount
        self.amount = amount
        self.createdAt = createdAt
        self.nonce = nonce
        self.signature = signature
    }

    /// Convenience constructor accepting a standard `Date`.
    public init(
        paymentId: String,
        fromAccount: String,
        toAccount: String,
        amount: Decimal,
        createdAtDate: Date,
        nonce: String,
        signature: String? = nil
    ) throws {
        try self.init(
            paymentId: paymentId,
            fromAccount: fromAccount,
            toAccount: toAccount,
            amount: amount,
            createdAt: PaymentInstant(date: createdAtDate),
            nonce: nonce,
            signature: signature
        )
    }

    /// Convenience constructor accepting a `Double` amount.
    public init(
        paymentId: String,
        fromAccount: String,
        toAccount: String,
        amountDouble: Double,
        createdAt: PaymentInstant,
        nonce: String,
        signature: String? = nil
    ) throws {
        try self.init(
            paymentId: paymentId,
            fromAccount: fromAccount,
            toAccount: toAccount,
            amount: Decimal(string: String(format: "%.2f", amountDouble)) ?? Decimal(amountDouble),
            createdAt: createdAt,
            nonce: nonce,
            signature: signature
        )
    }

    /// Factory method to create an unsigned PaymentInstruction with generated UUIDs and the current timestamp.
    ///
    /// Matches Java's `PaymentInstruction.create(fromAccount, toAccount, amount)`.
    public static func create(
        fromAccount: String,
        toAccount: String,
        amount: Decimal
    ) throws -> PaymentInstruction {
        try PaymentInstruction(
            paymentId: UUID().uuidString.lowercased(),
            fromAccount: fromAccount,
            toAccount: toAccount,
            amount: amount,
            createdAt: PaymentInstant.now(),
            nonce: UUID().uuidString.lowercased(),
            signature: nil
        )
    }

    /// Factory method overload accepting `Double`.
    public static func create(
        fromAccount: String,
        toAccount: String,
        amountDouble: Double
    ) throws -> PaymentInstruction {
        let dec = Decimal(string: String(format: "%.2f", amountDouble)) ?? Decimal(amountDouble)
        return try create(fromAccount: fromAccount, toAccount: toAccount, amount: dec)
    }

    /// Returns a copy of this payment instruction with the specified digital signature.
    ///
    /// Matches Java's `PaymentInstruction.withSignature(signature)`.
    public func withSignature(_ newSignature: String) throws -> PaymentInstruction {
        try PaymentInstruction(
            paymentId: self.paymentId,
            fromAccount: self.fromAccount,
            toAccount: self.toAccount,
            amount: self.amount,
            createdAt: self.createdAt,
            nonce: self.nonce,
            signature: newSignature
        )
    }

    // MARK: - Canonical Serialization

    /// Formats amount matching Java's `PaymentInstruction.canonicalAmount(BigDecimal)`.
    ///
    /// If scale <= 2 (standard currency), it enforces 2 decimal places (e.g. "100.00", "50.50").
    /// If scale > 2, it preserves higher precision while stripping trailing zeros (e.g. "100.555").
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

    /// Produces the deterministic length-prefixed canonical UTF-8 representation of the payment instruction
    /// used for digital signature generation and verification.
    ///
    /// Format:
    /// ```text
    /// UPI-MESH-INSTRUCTION-V1\n
    /// paymentId:<len>:<paymentId>\n
    /// fromAccount:<len>:<from.lowercased()>\n
    /// toAccount:<len>:<to.lowercased()>\n
    /// amount:<len>:<canonicalAmount>\n
    /// createdAt:<len>:<createdAt.isoString>\n
    /// nonce:<len>:<nonce>\n
    /// ```
    public func toCanonicalBytes() -> Data {
        let amtStr = Self.canonicalAmount(amount)
        let timeStr = createdAt.isoString
        let from = fromAccount.lowercased()
        let to = toAccount.lowercased()

        var sb = ""
        sb.append("UPI-MESH-INSTRUCTION-V1\n")
        sb.append("paymentId:\(paymentId.utf16.count):\(paymentId)\n")
        sb.append("fromAccount:\(from.utf16.count):\(from)\n")
        sb.append("toAccount:\(to.utf16.count):\(to)\n")
        sb.append("amount:\(amtStr.utf16.count):\(amtStr)\n")
        sb.append("createdAt:\(timeStr.utf16.count):\(timeStr)\n")
        sb.append("nonce:\(nonce.utf16.count):\(nonce)\n")

        return Data(sb.utf8)
    }

    /// Helper returning the canonical string prior to UTF-8 encoding.
    public func toCanonicalString() -> String {
        String(data: toCanonicalBytes(), encoding: .utf8) ?? ""
    }
}
