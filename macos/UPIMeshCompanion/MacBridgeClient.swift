import Foundation

// MARK: - Bridge Request & Response Models

/// Request payload for registering a device public verification key with the backend bridge.
/// Transmitted to `POST /api/keys/register`.
///
/// Under prototype policy, `accountId` is set to the client's hardware `deviceId`.
/// Only the public key (Base64 X.509 SubjectPublicKeyInfo) is transmitted; the private key
/// is strictly kept on-device and never exported, transmitted, or logged.
public struct MacKeyRegistrationRequest: Codable, Sendable, Equatable {
    public let accountId: String
    public let publicKey: String

    public init(accountId: String, publicKey: String) {
        self.accountId = accountId
        self.publicKey = publicKey
    }
}

/// Response payload received from `POST /api/keys/register`.
public struct MacKeyRegistrationResponse: Codable, Sendable, Equatable {
    public let status: String
    public let accountId: String
    public let message: String

    public init(status: String, accountId: String, message: String) {
        self.status = status
        self.accountId = accountId
        self.message = message
    }

    /// Returns true if the key is newly registered or already idempotently registered with the identical key.
    public var isSuccess: Bool {
        status == "REGISTERED" || status == "ALREADY_REGISTERED"
    }

    /// Returns true if this registration call was freshly recorded by the backend.
    public var isNewlyRegistered: Bool {
        status == "REGISTERED"
    }

    /// Returns true if the key was already idempotently registered in the backend registry.
    public var isAlreadyRegistered: Bool {
        status == "ALREADY_REGISTERED"
    }
}

/// Request payload for `POST /api/devices/authorize`.
/// Documented for protocol reference and diagnostic inspection.
public struct MacDeviceAuthorizationRequest: Codable, Sendable, Equatable {
    public let deviceId: String
    public let accountId: String

    public init(deviceId: String, accountId: String) {
        self.deviceId = deviceId
        self.accountId = accountId
    }
}

/// Response payload from `POST /api/devices/authorize`.
public struct MacDeviceAuthorizationResponse: Codable, Sendable, Equatable {
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

// MARK: - Mac Bridge Errors

public enum MacBridgeError: LocalizedError, Sendable, Equatable {
    case invalidURL(String)
    case invalidParameters(String)
    case registrationRejected(String)
    case networkError(String)
    case invalidResponse(Int, String)
    case encodingError(String)
    case decodingError(String)
    case authorizationBlocked(String)
    case settlementRejected(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid Bridge URL: \(url)"
        case .invalidParameters(let details):
            return "Invalid parameters: \(details)"
        case .registrationRejected(let message):
            return "Bridge registration rejected: \(message)"
        case .settlementRejected(let message):
            return "Bridge allowance settlement rejected: \(message)"
        case .networkError(let details):
            return "Network connection failed: \(details)"
        case .invalidResponse(let code, let details):
            return "Bridge returned HTTP \(code): \(details)"
        case .encodingError(let details):
            return "Failed to encode request payload: \(details)"
        case .decodingError(let details):
            return "Failed to decode bridge response: \(details)"
        case .authorizationBlocked(let reason):
            return "Account authorization blocked: \(reason)"
        }
    }
}

// MARK: - Mac Bridge Registering Protocol

public protocol MacBridgeRegistering: Sendable {
    func registerPublicKey(
        deviceId: String,
        publicKeyBase64: String
    ) async throws -> MacKeyRegistrationResponse
}

// MARK: - Mac Bridge Client

/// Client for communicating with the local UPI Offline Mesh backend bridge from macOS.
///
/// CRITICAL SECURITY RULES:
/// 1. Never transmits, exports, logs, or handles the Mac companion private key.
/// 2. Only transmits the public key (`publicKeyBase64X509`) and device ID (`mac-companion-<UUID>`).
/// 3. Never silently replaces an existing device identity or registered public key.
/// 4. Does not automatically authorize debtor accounts (such as Carol).
///
/// NETWORK CONFIGURATION:
/// Default URL: `http://localhost:8080`.
/// IMPORTANT NOTE: `http://localhost:8080` is only valid when the macOS companion runs
/// directly on the same host machine as the Spring Boot backend server.
/// Physical iOS devices connecting over Wi-Fi MUST NOT use localhost (which points to the iPhone itself)
/// and must instead use the host's LAN IP address (e.g. `http://192.168.1.100:8080`).
public final class MacBridgeClient: MacBridgeRegistering, @unchecked Sendable {

    public static let defaultBaseURL = URL(string: "http://localhost:8080")!
    public static let shared = MacBridgeClient()

    private let session: URLSession
    public private(set) var baseURL: URL

    public init(baseURL: URL = MacBridgeClient.defaultBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// Updates the target bridge base URL.
    public func setBaseURL(_ newURL: URL) {
        self.baseURL = newURL
    }

    /// Registers the Mac companion's public key with the backend bridge via `POST /api/keys/register`.
    ///
    /// - Parameters:
    ///   - deviceId: The hardware/installation device ID (e.g. `mac-companion-...`).
    ///   - publicKeyBase64: The Base64-encoded X.509 SubjectPublicKeyInfo public key.
    /// - Returns: `MacKeyRegistrationResponse` indicating whether newly registered or already registered.
    public func registerPublicKey(
        deviceId: String,
        publicKeyBase64: String
    ) async throws -> MacKeyRegistrationResponse {
        let trimmedDeviceId = deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = publicKeyBase64.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedDeviceId.isEmpty else {
            throw MacBridgeError.invalidParameters("Device ID must not be blank")
        }
        guard !trimmedKey.isEmpty else {
            throw MacBridgeError.invalidParameters("Public key must not be blank")
        }

        guard let url = URL(string: "/api/keys/register", relativeTo: baseURL) else {
            throw MacBridgeError.invalidURL(baseURL.absoluteString)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let payload = MacKeyRegistrationRequest(accountId: trimmedDeviceId, publicKey: trimmedKey)
        do {
            request.httpBody = try JSONEncoder().encode(payload)
        } catch {
            throw MacBridgeError.encodingError(error.localizedDescription)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw MacBridgeError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MacBridgeError.invalidResponse(-1, "Non-HTTP response received")
        }

        let decoder = JSONDecoder()

        if (200...299).contains(httpResponse.statusCode) {
            do {
                return try decoder.decode(MacKeyRegistrationResponse.self, from: data)
            } catch {
                throw MacBridgeError.decodingError(error.localizedDescription)
            }
        } else if httpResponse.statusCode == 400 {
            // Attempt to parse structured KeyRegistrationResponse, or fall back to plaintext error
            if let errorDto = try? decoder.decode(MacKeyRegistrationResponse.self, from: data) {
                throw MacBridgeError.registrationRejected(errorDto.message)
            } else if let errorString = String(data: data, encoding: .utf8), !errorString.isEmpty {
                throw MacBridgeError.registrationRejected(errorString)
            } else {
                throw MacBridgeError.registrationRejected("HTTP 400 Bad Request")
            }
        } else {
            let errorString = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw MacBridgeError.invalidResponse(httpResponse.statusCode, errorString)
        }
    }

    /// Registers the Mac companion identity directly without exposing private keys.
    public func registerIdentity(_ identity: MacDeviceIdentity) async throws -> MacKeyRegistrationResponse {
        return try await registerPublicKey(
            deviceId: identity.deviceId,
            publicKeyBase64: identity.publicKeyBase64X509
        )
    }

    /// Fetches the authoritative Bank Authority public key from the backend bridge.
    public func fetchBankAuthorityPublicKey() async throws -> BankAuthorityPublicKeyResponseDTO {
        guard let url = URL(string: "/api/allowance/bank-public-key", relativeTo: baseURL) else {
            throw MacBridgeError.invalidURL(baseURL.absoluteString)
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
            throw MacBridgeError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MacBridgeError.invalidResponse(-1, "Non-HTTP response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw MacBridgeError.invalidResponse(httpResponse.statusCode, errorMsg)
        }

        do {
            return try JSONDecoder().decode(BankAuthorityPublicKeyResponseDTO.self, from: data)
        } catch {
            throw MacBridgeError.decodingError(error.localizedDescription)
        }
    }

    /// Submits an allowance-backed spend record to the backend bridge via `POST /api/allowance/spend`.
    public func settleAllowanceSpend(
        record: OfflineSpendRecord
    ) async throws -> OfflineSpendPaymentDTO {
        guard let url = URL(string: "/api/allowance/spend", relativeTo: baseURL) else {
            throw MacBridgeError.invalidURL(baseURL.absoluteString)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            request.httpBody = try JSONEncoder().encode(record)
        } catch {
            throw MacBridgeError.encodingError(error.localizedDescription)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw MacBridgeError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MacBridgeError.invalidResponse(-1, "Non-HTTP response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw MacBridgeError.settlementRejected(errorMsg)
        }

        do {
            return try JSONDecoder().decode(OfflineSpendPaymentDTO.self, from: data)
        } catch {
            throw MacBridgeError.decodingError(error.localizedDescription)
        }
    }

// MARK: - Mac Reconciliation Outcome

public enum MacReconciliationOutcome: Sendable, Equatable {
    case settled(paymentId: String, status: String)
    case rejected(paymentId: String, reason: String)
    case retryable(paymentId: String, reason: String)
}

    /// Reconciles a received packet on Mac with the backend bridge.
    public func reconcilePacket(
        record: MacReceivedPacketRecord,
        store: MacReceivedPacketStore = .shared
    ) async -> MacReconciliationOutcome {
        let paymentId = record.packet.paymentId

        // Persist SETTLING status before request
        do {
            try store.updateStatus(paymentId: paymentId, status: .settling)
        } catch {
            return .retryable(paymentId: paymentId, reason: "Failed to persist SETTLING status")
        }

        if let spend = record.packet.allowanceSpend {
            do {
                let paymentDto = try await settleAllowanceSpend(record: spend)
                if paymentDto.status.uppercased() == "SETTLED" {
                    _ = try? store.updateStatus(paymentId: paymentId, status: .settled)
                    return .settled(paymentId: paymentId, status: paymentDto.status)
                } else {
                    return .retryable(paymentId: paymentId, reason: "Bridge returned non-settled status: \(paymentDto.status)")
                }
            } catch let err as MacBridgeError {
                switch err {
                case .settlementRejected(let reason):
                    _ = try? store.updateStatus(paymentId: paymentId, status: .failed, failureReason: reason)
                    return .rejected(paymentId: paymentId, reason: reason)
                default:
                    return .retryable(paymentId: paymentId, reason: err.localizedDescription)
                }
            } catch {
                return .retryable(paymentId: paymentId, reason: error.localizedDescription)
            }
        } else {
            // Legacy packets not supported on standalone Mac companion bridge client
            return .rejected(paymentId: paymentId, reason: "Legacy mesh packets require mobile mesh router")
        }
    }
}

