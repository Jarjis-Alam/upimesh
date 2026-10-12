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

// MARK: - Notifications

extension Notification.Name {
    public static let meshAccountsUpdated = Notification.Name("UPIMeshAccountsUpdated")
}

// MARK: - API Errors

public enum APIError: LocalizedError, Sendable, Equatable {
    case invalidURL
    case invalidParameters(String)
    case paymentFailed(String)
    case networkError(String)
    case invalidResponse(Int)
    case decodingError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server endpoint URL"
        case .invalidParameters(let details):
            return "Invalid payment parameters: \(details)"
        case .paymentFailed(let message):
            return "Mesh payment settlement rejected: \(message)"
        case .networkError(let details):
            return "Network connection failed: \(details)"
        case .invalidResponse(let code):
            return "Server returned unexpected HTTP status: \(code)"
        case .decodingError(let details):
            return "Failed to decode response: \(details)"
        }
    }
}

// MARK: - API Client

/// Lightweight HTTP API client for UPI Offline Mesh backend integration.
public final class UPIMeshAPIClient: Sendable {
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
}
