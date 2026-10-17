import Foundation

// MARK: - Account DTO Model

/// Data Transfer Object representing an account from `GET /api/accounts`.
///
/// Matches the backend entity `com.demo.upimesh.model.Account`.
public struct AccountDTO: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let balance: Double
    public let version: Int?

    public init(id: String, balance: Double, version: Int? = nil) {
        self.id = id
        self.balance = balance
        self.version = version
    }
}

// MARK: - Transaction DTO Model

/// Data Transfer Object representing a ledger transaction from `GET /api/transactions`.
///
/// Matches the backend entity `com.demo.upimesh.model.Transaction`.
public struct TransactionDTO: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let fromAccount: String
    public let toAccount: String
    public let amount: Double
    public let timestamp: String
    public let status: String

    public init(id: String, fromAccount: String, toAccount: String, amount: Double, timestamp: String, status: String) {
        self.id = id
        self.fromAccount = fromAccount
        self.toAccount = toAccount
        self.amount = amount
        self.timestamp = timestamp
        self.status = status
    }
}

// MARK: - Mesh Payment Result DTO Model

/// Data Transfer Object representing the end-to-end outcome of a simulated mesh payment
/// from `POST /api/mesh/transfer`.
///
/// Matches the backend record `com.demo.upimesh.model.MeshPaymentResult`.
public struct MeshPaymentResultDTO: Codable, Equatable, Sendable {
    public let success: Bool
    public let paymentId: String
    public let packetId: String
    public let fromAccount: String
    public let toAccount: String
    public let amount: Double
    public let roundsRun: Int
    public let hopsTaken: Int
    public let remainingTtl: Int
    public let routeTrace: [String]
    public let encryptedKeySnippet: String?
    public let ivHex: String?
    public let ciphertextSnippet: String?
    public let status: String
    public let message: String

    public init(
        success: Bool,
        paymentId: String,
        packetId: String,
        fromAccount: String,
        toAccount: String,
        amount: Double,
        roundsRun: Int,
        hopsTaken: Int,
        remainingTtl: Int,
        routeTrace: [String],
        encryptedKeySnippet: String? = nil,
        ivHex: String? = nil,
        ciphertextSnippet: String? = nil,
        status: String,
        message: String
    ) {
        self.success = success
        self.paymentId = paymentId
        self.packetId = packetId
        self.fromAccount = fromAccount
        self.toAccount = toAccount
        self.amount = amount
        self.roundsRun = roundsRun
        self.hopsTaken = hopsTaken
        self.remainingTtl = remainingTtl
        self.routeTrace = routeTrace
        self.encryptedKeySnippet = encryptedKeySnippet
        self.ivHex = ivHex
        self.ciphertextSnippet = ciphertextSnippet
        self.status = status
        self.message = message
    }
}

// MARK: - Key Registration DTO Models

/// Data Transfer Object representing request payload for `POST /api/keys/register`.
///
/// Matches the backend record `com.demo.upimesh.model.KeyRegistrationRequest`.
public struct KeyRegistrationRequestDTO: Codable, Sendable, Equatable {
    public let accountId: String
    public let publicKey: String

    public init(accountId: String, publicKey: String) {
        self.accountId = accountId
        self.publicKey = publicKey
    }
}

/// Data Transfer Object representing response payload from `POST /api/keys/register`.
///
/// Matches the backend record `com.demo.upimesh.model.KeyRegistrationResponse`.
public struct KeyRegistrationResponseDTO: Codable, Sendable, Equatable {
    public let status: String
    public let accountId: String
    public let message: String

    public init(status: String, accountId: String, message: String) {
        self.status = status
        self.accountId = accountId
        self.message = message
    }

    /// Returns true if registered freshly or already registered with the identical key.
    public var isSuccess: Bool {
        status == "REGISTERED" || status == "ALREADY_REGISTERED"
    }
}

// MARK: - Signed Payment & Device Authorization DTO Models

/// Data Transfer Object representing request payload for `POST /api/mesh/submit`.
public struct SignedPaymentRequestDTO: Codable, Sendable, Equatable {
    public let deviceId: String
    public let instruction: PaymentInstruction

    public init(deviceId: String, instruction: PaymentInstruction) {
        self.deviceId = deviceId
        self.instruction = instruction
    }
}

/// Data Transfer Object representing request payload for `POST /api/devices/authorize`.
public struct DeviceAuthorizationRequestDTO: Codable, Sendable, Equatable {
    public let deviceId: String
    public let accountId: String

    public init(deviceId: String, accountId: String) {
        self.deviceId = deviceId
        self.accountId = accountId
    }
}

/// Data Transfer Object representing response payload from `POST /api/devices/authorize`.
public struct DeviceAuthorizationResponseDTO: Codable, Sendable, Equatable {
    public let status: String
    public let deviceId: String
    public let accountId: String
    public let message: String

    public init(status: String, deviceId: String, accountId: String, message: String) {
        self.status = status
        self.deviceId = deviceId
        self.accountId = accountId
        self.message = message
    }

    public var isSuccess: Bool {
        status == "AUTHORIZED"
    }
}

// MARK: - Allowance DTO Models

public struct AllowanceIssuanceRequestDTO: Codable, Sendable, Equatable {
    public let accountId: String
    public let deviceId: String
    public let amount: Decimal
    public let expiryMinutes: Int?

    public init(accountId: String, deviceId: String, amount: Decimal, expiryMinutes: Int? = 1440) {
        self.accountId = accountId
        self.deviceId = deviceId
        self.amount = amount
        self.expiryMinutes = expiryMinutes
    }
}

public struct OfflineAllowanceVoucherResponseDTO: Codable, Sendable, Equatable {
    public let allowanceId: String
    public let accountId: String
    public let deviceId: String
    public let devicePublicKeyFingerprint: String
    public let currency: String
    public let allocatedAmount: Decimal
    public let issuedAt: String
    public let expiresAt: String
    public let protocolVersion: Int
    public let status: String
    public let voucherSignature: String
    public let bankPublicKeyBase64: String?

    public init(
        allowanceId: String,
        accountId: String,
        deviceId: String,
        devicePublicKeyFingerprint: String,
        currency: String,
        allocatedAmount: Decimal,
        issuedAt: String,
        expiresAt: String,
        protocolVersion: Int,
        status: String,
        voucherSignature: String,
        bankPublicKeyBase64: String? = nil
    ) {
        self.allowanceId = allowanceId
        self.accountId = accountId
        self.deviceId = deviceId
        self.devicePublicKeyFingerprint = devicePublicKeyFingerprint
        self.currency = currency
        self.allocatedAmount = allocatedAmount
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.protocolVersion = protocolVersion
        self.status = status
        self.voucherSignature = voucherSignature
        self.bankPublicKeyBase64 = bankPublicKeyBase64
    }

    public func toVoucher() -> OfflineAllowanceVoucher {
        OfflineAllowanceVoucher(
            allowanceId: allowanceId,
            accountId: accountId,
            deviceId: deviceId,
            devicePublicKeyFingerprint: devicePublicKeyFingerprint,
            currency: currency,
            allocatedAmount: allocatedAmount,
            spentAmount: Decimal.zero,
            lastSequenceNumber: 0,
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            protocolVersion: protocolVersion,
            status: status,
            voucherSignature: voucherSignature,
            bankPublicKeyBase64: bankPublicKeyBase64
        )
    }
}

public struct OfflineAllowanceRefundResultDTO: Codable, Sendable, Equatable {
    public let allowanceId: String
    public let accountId: String
    public let refundedAmount: Decimal
    public let currency: String
    public let status: String
    public let refundedAt: String
    public let message: String
}

// MARK: - Notifications

extension Notification.Name {
    public static let meshAccountsUpdated = Notification.Name("UPIMeshAccountsUpdated")
    public static let deviceKeyRegistered = Notification.Name("UPIMeshDeviceKeyRegistered")
    public static let deviceAuthorized = Notification.Name("UPIMeshDeviceAuthorized")
}

// MARK: - API Errors

public enum APIError: LocalizedError, Sendable, Equatable {
    case invalidURL
    case invalidParameters(String)
    case paymentFailed(String)
    case registrationFailed(String)
    case authorizationFailed(String)
    case allowanceError(String)
    case networkError(String)
    case invalidResponse(Int)
    case encodingError(String)
    case decodingError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server endpoint URL"
        case .invalidParameters(let details):
            return "Invalid parameters: \(details)"
        case .paymentFailed(let message):
            return "Mesh payment settlement rejected: \(message)"
        case .registrationFailed(let message):
            return "Device public key registration rejected: \(message)"
        case .authorizationFailed(let message):
            return "Device account authorization rejected: \(message)"
        case .allowanceError(let message):
            return "Allowance operation rejected: \(message)"
        case .networkError(let details):
            return "Network connection failed: \(details)"
        case .invalidResponse(let code):
            return "Server returned unexpected HTTP status: \(code)"
        case .encodingError(let details):
            return "Failed to encode request payload: \(details)"
        case .decodingError(let details):
            return "Failed to decode response: \(details)"
        }
    }
}

// MARK: - Payment Status Response DTO

/// Data Transfer Object representing authoritative payment status from `GET /api/mesh/status/{paymentId}`.
public struct PaymentStatusResponseDTO: Codable, Sendable, Equatable {
    public let found: Bool
    public let paymentId: String
    public let status: String
    public let fromAccount: String?
    public let toAccount: String?
    public let amount: Double?
    public let packetHash: String?
    public let settledAt: String?
    public let message: String

    public init(
        found: Bool,
        paymentId: String,
        status: String,
        fromAccount: String? = nil,
        toAccount: String? = nil,
        amount: Double? = nil,
        packetHash: String? = nil,
        settledAt: String? = nil,
        message: String
    ) {
        self.found = found
        self.paymentId = paymentId
        self.status = status
        self.fromAccount = fromAccount
        self.toAccount = toAccount
        self.amount = amount
        self.packetHash = packetHash
        self.settledAt = settledAt
        self.message = message
    }
}

// MARK: - Mesh Payment Submitting Protocol

/// Abstraction for submitting client-constructed, device-signed payment instructions to the bridge.
/// Enables mock injection and unit testing without network dependencies.
public protocol MeshPaymentSubmitting: Sendable {
    func submitSignedMeshPayment(
        instruction: PaymentInstruction,
        deviceId: String
    ) async throws -> MeshPaymentResultDTO

    func queryPaymentStatus(
        paymentId: String
    ) async throws -> PaymentStatusResponseDTO

    func submitAllowanceSpend(
        record: OfflineSpendRecord
    ) async throws -> OfflineSpendPaymentDTO
}

public extension MeshPaymentSubmitting {
    func queryPaymentStatus(paymentId: String) async throws -> PaymentStatusResponseDTO {
        return PaymentStatusResponseDTO(
            found: false,
            paymentId: paymentId,
            status: "NOT_FOUND",
            message: "Status query not implemented in mock submitter"
        )
    }

    func submitAllowanceSpend(
        record: OfflineSpendRecord
    ) async throws -> OfflineSpendPaymentDTO {
        throw APIError.paymentFailed("submitAllowanceSpend not implemented in mock submitter")
    }
}

// MARK: - Mesh Transaction Fetching Protocol

/// Abstraction for fetching authoritative ledger transactions from the backend bridge.
/// Enables mock injection and unit testing without network dependencies.
public protocol MeshTransactionFetching: Sendable {
    func fetchTransactions() async throws -> [TransactionDTO]
}

// MARK: - API Client

/// Lightweight HTTP API client for UPI Offline Mesh backend integration.
public final class UPIMeshAPIClient: MeshPaymentSubmitting, MeshTransactionFetching, Sendable {
    public static let shared = UPIMeshAPIClient()

    private let session: URLSession
    private let config: APIConfiguration

    public init(session: URLSession = .shared, config: APIConfiguration = .shared) {
        self.session = session
        self.config = config
    }

    /// Fetches the authoritative accounts list from `GET /api/accounts`.
    public func fetchAccounts() async throws -> [AccountDTO] {
        guard let url = URL(string: "/api/accounts", relativeTo: config.baseURL) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10.0
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = config.authToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(-1)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse(httpResponse.statusCode)
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode([AccountDTO].self, from: data)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    /// Fetches the transaction ledger records from `GET /api/transactions`.
    public func fetchTransactions() async throws -> [TransactionDTO] {
        guard let url = URL(string: "/api/transactions", relativeTo: config.baseURL) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10.0
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = config.authToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(-1)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse(httpResponse.statusCode)
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode([TransactionDTO].self, from: data)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    /// Submits a simulated mesh payment transfer via `POST /api/mesh/transfer`.
    ///
    /// Validates parameters locally and uses URLComponents for safe query encoding.
    public func submitMeshTransfer(
        from: String,
        to: String,
        amount: Double,
        ttl: Int = 5
    ) async throws -> MeshPaymentResultDTO {
        let trimmedFrom = from.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTo = to.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedFrom.isEmpty, !trimmedTo.isEmpty else {
            throw APIError.invalidParameters("Sender and recipient must not be empty")
        }
        guard trimmedFrom.caseInsensitiveCompare(trimmedTo) != .orderedSame else {
            throw APIError.invalidParameters("Sender and recipient must be different")
        }
        guard amount > 0 else {
            throw APIError.invalidParameters("Transfer amount must be strictly greater than zero")
        }

        guard var components = URLComponents(url: config.baseURL, resolvingAgainstBaseURL: true) else {
            throw APIError.invalidURL
        }
        components.path = "/api/mesh/transfer"
        components.queryItems = [
            URLQueryItem(name: "from", value: trimmedFrom),
            URLQueryItem(name: "to", value: trimmedTo),
            URLQueryItem(name: "amount", value: String(format: "%.2f", amount)),
            URLQueryItem(name: "ttl", value: String(ttl))
        ]

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15.0
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(-1)
        }

        let decoder = JSONDecoder()

        if (200...299).contains(httpResponse.statusCode) {
            do {
                return try decoder.decode(MeshPaymentResultDTO.self, from: data)
            } catch {
                throw APIError.decodingError(error.localizedDescription)
            }
        } else if httpResponse.statusCode == 400 {
            // Attempt to decode error response from MeshPaymentResultDTO or raw text
            if let errorResult = try? decoder.decode(MeshPaymentResultDTO.self, from: data) {
                throw APIError.paymentFailed(errorResult.message)
            } else if let errorString = String(data: data, encoding: .utf8), !errorString.isEmpty {
                throw APIError.paymentFailed(errorString)
            } else {
                throw APIError.invalidResponse(httpResponse.statusCode)
            }
        } else {
            throw APIError.invalidResponse(httpResponse.statusCode)
        }
    }

    /// Registers an exported device public key with the backend bridge via `POST /api/keys/register`.
    ///
    /// Transmits only the Base64 X.509 SubjectPublicKeyInfo public key; never transmits private keys.
    public func registerPublicKey(
        accountId: String,
        publicKeyBase64: String
    ) async throws -> KeyRegistrationResponseDTO {
        let trimmedId = accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = publicKeyBase64.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedId.isEmpty else {
            throw APIError.invalidParameters("Account or device identifier must not be blank")
        }
        guard !trimmedKey.isEmpty else {
            throw APIError.invalidParameters("Public key must not be blank")
        }

        guard let url = URL(string: "/api/keys/register", relativeTo: config.baseURL) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let requestDTO = KeyRegistrationRequestDTO(accountId: trimmedId, publicKey: trimmedKey)
        do {
            request.httpBody = try JSONEncoder().encode(requestDTO)
        } catch {
            throw APIError.invalidParameters("Failed to encode key registration request: \(error.localizedDescription)")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(-1)
        }

        let decoder = JSONDecoder()

        if (200...299).contains(httpResponse.statusCode) {
            do {
                return try decoder.decode(KeyRegistrationResponseDTO.self, from: data)
            } catch {
                throw APIError.decodingError(error.localizedDescription)
            }
        } else if httpResponse.statusCode == 400 {
            // Backend returns plaintext error message on HTTP 400
            if let errorString = String(data: data, encoding: .utf8), !errorString.isEmpty {
                throw APIError.registrationFailed(errorString)
            } else {
                throw APIError.invalidResponse(httpResponse.statusCode)
            }
        } else {
            throw APIError.invalidResponse(httpResponse.statusCode)
        }
    }

    /// Submits a client-constructed, device-signed PaymentInstruction via `POST /api/mesh/submit`.
    ///
    /// The private key never leaves the device Keychain. Only the signed instruction and deviceId are transmitted.
    public func submitSignedMeshPayment(
        instruction: PaymentInstruction,
        deviceId: String
    ) async throws -> MeshPaymentResultDTO {
        let trimmedDeviceId = deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDeviceId.isEmpty else {
            throw APIError.invalidParameters("Device ID must not be empty")
        }
        guard instruction.signature != nil else {
            throw APIError.invalidParameters("PaymentInstruction must have a non-nil digital signature")
        }

        let url = config.baseURL.appendingPathComponent("api/mesh/submit")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("true", forHTTPHeaderField: "X-Idempotent-Replay")

        let payload = SignedPaymentRequestDTO(deviceId: trimmedDeviceId, instruction: instruction)
        do {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(payload)
        } catch {
            throw APIError.encodingError(error.localizedDescription)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(-1)
        }

        let decoder = JSONDecoder()

        if (200...299).contains(httpResponse.statusCode) {
            do {
                return try decoder.decode(MeshPaymentResultDTO.self, from: data)
            } catch {
                throw APIError.decodingError(error.localizedDescription)
            }
        } else if httpResponse.statusCode == 400 || httpResponse.statusCode == 403 {
            if let errorResult = try? decoder.decode(MeshPaymentResultDTO.self, from: data) {
                throw APIError.paymentFailed(errorResult.message)
            } else if let errorString = String(data: data, encoding: .utf8), !errorString.isEmpty {
                throw APIError.paymentFailed(errorString)
            } else {
                throw APIError.invalidResponse(httpResponse.statusCode)
            }
        } else {
            throw APIError.invalidResponse(httpResponse.statusCode)
        }
    }

    /// Authoritatively queries the status of a payment instruction via `GET /api/mesh/status/{paymentId}`.
    public func queryPaymentStatus(paymentId: String) async throws -> PaymentStatusResponseDTO {
        let cleanId = paymentId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty else {
            throw APIError.invalidParameters("Payment ID must not be empty")
        }

        let url = config.baseURL.appendingPathComponent("api/mesh/status/\(cleanId)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10.0
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(-1)
        }

        let decoder = JSONDecoder()
        if (200...299).contains(httpResponse.statusCode) {
            do {
                return try decoder.decode(PaymentStatusResponseDTO.self, from: data)
            } catch {
                throw APIError.decodingError(error.localizedDescription)
            }
        } else if httpResponse.statusCode == 404 {
            if let notFoundDto = try? decoder.decode(PaymentStatusResponseDTO.self, from: data) {
                return notFoundDto
            }
            return PaymentStatusResponseDTO(
                found: false,
                paymentId: cleanId,
                status: "NOT_FOUND",
                message: "Payment instruction not found on ledger"
            )
        } else {
            throw APIError.invalidResponse(httpResponse.statusCode)
        }
    }

    /// Authorizes a registered device ID to debit a specific account via `POST /api/devices/authorize`.
    public func authorizeDevice(
        deviceId: String,
        accountId: String
    ) async throws -> DeviceAuthorizationResponseDTO {
        let trimmedDeviceId = deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAccountId = accountId.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedDeviceId.isEmpty else {
            throw APIError.invalidParameters("Device ID must not be blank")
        }
        guard !trimmedAccountId.isEmpty else {
            throw APIError.invalidParameters("Account ID must not be blank")
        }

        let url = config.baseURL.appendingPathComponent("api/devices/authorize")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = config.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(token, forHTTPHeaderField: "X-Admin-Token")
        }

        let payload = DeviceAuthorizationRequestDTO(deviceId: trimmedDeviceId, accountId: trimmedAccountId)
        do {
            request.httpBody = try JSONEncoder().encode(payload)
        } catch {
            throw APIError.encodingError(error.localizedDescription)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(-1)
        }

        let decoder = JSONDecoder()
        if (200...299).contains(httpResponse.statusCode) {
            do {
                let dto = try decoder.decode(DeviceAuthorizationResponseDTO.self, from: data)
                NotificationCenter.default.post(name: .deviceAuthorized, object: dto)
                return dto
            } catch {
                throw APIError.decodingError(error.localizedDescription)
            }
        } else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw APIError.registrationFailed(errorMsg)
        }
    }

    // MARK: - Offline Allowance Endpoints

    /// Fetches the authoritative Bank Authority public key from `GET /api/allowance/bank-public-key`.
    public func fetchBankAuthorityPublicKey() async throws -> BankAuthorityPublicKeyResponseDTO {
        let url = config.baseURL.appendingPathComponent("api/allowance/bank-public-key")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10.0
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(-1)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw APIError.allowanceError("Failed to fetch bank public key: \(errorMsg)")
        }

        do {
            return try JSONDecoder().decode(BankAuthorityPublicKeyResponseDTO.self, from: data)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    /// Atomically issues an offline allowance and reserves escrow via `POST /api/allowance/issue`.
    public func issueAllowance(
        request: AllowanceIssuanceRequestDTO
    ) async throws -> OfflineAllowanceVoucherResponseDTO {
        let url = config.baseURL.appendingPathComponent("api/allowance/issue")
        var urlReq = URLRequest(url: url)
        urlReq.httpMethod = "POST"
        urlReq.timeoutInterval = 10.0
        urlReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlReq.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            urlReq.httpBody = try JSONEncoder().encode(request)
        } catch {
            throw APIError.encodingError(error.localizedDescription)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlReq)
        } catch {
            throw APIError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(-1)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw APIError.allowanceError("Allowance issuance failed: \(errorMsg)")
        }

        do {
            return try JSONDecoder().decode(OfflineAllowanceVoucherResponseDTO.self, from: data)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    /// Submits a signed offline spend record to settle against escrow via `POST /api/allowance/spend`.
    public func submitAllowanceSpend(
        record: OfflineSpendRecord
    ) async throws -> OfflineSpendPaymentDTO {
        let url = config.baseURL.appendingPathComponent("api/allowance/spend")
        var urlReq = URLRequest(url: url)
        urlReq.httpMethod = "POST"
        urlReq.timeoutInterval = 10.0
        urlReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlReq.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            urlReq.httpBody = try JSONEncoder().encode(record)
        } catch {
            throw APIError.encodingError(error.localizedDescription)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlReq)
        } catch {
            throw APIError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(-1)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw APIError.paymentFailed("Allowance spend settlement failed: \(errorMsg)")
        }

        do {
            return try JSONDecoder().decode(OfflineSpendPaymentDTO.self, from: data)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    /// Refunds unspent allowance funds from escrow back to payer via `POST /api/allowance/refund`.
    public func refundAllowance(
        allowanceId: String
    ) async throws -> OfflineAllowanceRefundResultDTO {
        var components = URLComponents(url: config.baseURL.appendingPathComponent("api/allowance/refund"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "allowanceId", value: allowanceId)]
        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var urlReq = URLRequest(url: url)
        urlReq.httpMethod = "POST"
        urlReq.timeoutInterval = 10.0
        urlReq.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlReq)
        } catch {
            throw APIError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(-1)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw APIError.allowanceError("Allowance refund failed: \(errorMsg)")
        }

        do {
            return try JSONDecoder().decode(OfflineAllowanceRefundResultDTO.self, from: data)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    /// Queries the currently active allowance for an account via `GET /api/allowance/active`.
    public func fetchActiveAllowance(
        accountId: String
    ) async throws -> OfflineAllowanceVoucherResponseDTO? {
        var components = URLComponents(url: config.baseURL.appendingPathComponent("api/allowance/active"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "accountId", value: accountId)]
        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var urlReq = URLRequest(url: url)
        urlReq.httpMethod = "GET"
        urlReq.timeoutInterval = 10.0
        urlReq.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlReq)
        } catch {
            throw APIError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(-1)
        }

        if httpResponse.statusCode == 404 {
            return nil
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw APIError.allowanceError("Failed to fetch active allowance: \(errorMsg)")
        }

        do {
            return try JSONDecoder().decode(OfflineAllowanceVoucherResponseDTO.self, from: data)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }
}
