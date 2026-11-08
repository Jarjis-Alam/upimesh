import Foundation

/// Errors specifically related to predictive provisioning peer wire messages.
public enum PeerPredictionError: LocalizedError, Equatable {
    case payloadTooLarge(Int)
    case malformedPayload(String)
    case unsupportedMessageType(String)
    case unsupportedProtocolVersion(Int)
    case paymentFieldsForbidden
    case staleUpdate(String)
    case outOfOrderSequence(received: UInt64, current: UInt64)

    public var errorDescription: String? {
        switch self {
        case .payloadTooLarge(let bytes):
            return "Prediction payload exceeds maximum allowable size (\(bytes) > \(PeerPredictionMessage.maxPayloadBytes) bytes)."
        case .malformedPayload(let msg):
            return "Malformed prediction message: \(msg)"
        case .unsupportedMessageType(let type):
            return "Unsupported prediction message type: '\(type)'. Expected '\(PeerPredictionMessage.messageType)'."
        case .unsupportedProtocolVersion(let v):
            return "Unsupported prediction protocol version: \(v)."
        case .paymentFieldsForbidden:
            return "Prediction wire message must not contain financial or payment instruction keys."
        case .staleUpdate(let msg):
            return "Stale prediction update discarded: \(msg)"
        case .outOfOrderSequence(let r, let c):
            return "Out-of-order prediction sequence discarded (received #\(r) <= current #\(c))."
        }
    }
}

/// Competing strategies allocation snapshot for on-device comparison.
public struct StrategyRecommendationSnapshot: Sendable, Codable, Equatable {
    public let fixedAllowanceInr: Double
    public let demandOnlyInr: Double
    public let proposedM1Inr: Double
    public let uncertaintyM2Inr: Double

    public init(
        fixedAllowanceInr: Double,
        demandOnlyInr: Double,
        proposedM1Inr: Double,
        uncertaintyM2Inr: Double
    ) {
        self.fixedAllowanceInr = fixedAllowanceInr
        self.demandOnlyInr = demandOnlyInr
        self.proposedM1Inr = proposedM1Inr
        self.uncertaintyM2Inr = uncertaintyM2Inr
    }
}

/// A strictly non-financial advisory wire message carrying network risk predictions,
/// outage forecasts, and recommended offline reserves from the Mac research station to iPhone.
public struct PeerPredictionMessage: Sendable, Codable, Equatable {

    public static let messageType = "PREDICTION_UPDATE"
    public static let currentProtocolVersion = 1
    public static let maxPayloadBytes: Int = 16 * 1024

    /// Keys strictly prohibited in prediction payloads to prevent financial masquerading.
    public static let forbiddenPaymentKeys: Set<String> = [
        "amount", "paymentid", "fromaccount", "toaccount",
        "nonce", "signature", "instruction", "packet", "settlement", "vouchersignature"
    ]

    // MARK: - Message Header
    public let messageType: String
    public let protocolVersion: Int
    public let predictionId: String
    public let sequenceNumber: UInt64
    public let timestamp: String
    public let senderDeviceId: String
    public let isSimulated: Bool

    // MARK: - Environmental Telemetry & Outage Forecast
    public let networkStatus: String
    public let signalDbm: Int
    public let outageProbability: Double
    public let robustOutageProbability: Double
    public let predictedDurationHours: Double
    public let durationStdHours: Double

    // MARK: - Demand & Uncertainty Metrics
    public let predictedDemandInr: Double
    public let compoundDemandStdInr: Double
    public let uncertaintyMarginInr: Double
    public let safetyFloorInr: Double
    public let confidenceLevel: Double

    // MARK: - Recommended Allocation
    public let recommendedReserveInr: Double
    public let previousReserveInr: Double
    public let deltaReserveInr: Double
    public let recommendationNarrative: String

    // MARK: - Strategy Snapshot
    public let strategySnapshot: StrategyRecommendationSnapshot

    public init(
        protocolVersion: Int = currentProtocolVersion,
        predictionId: String = UUID().uuidString.lowercased(),
        sequenceNumber: UInt64,
        timestamp: String = ISO8601DateFormatter().string(from: Date()),
        senderDeviceId: String,
        isSimulated: Bool = true,
        networkStatus: String,
        signalDbm: Int,
        outageProbability: Double,
        robustOutageProbability: Double,
        predictedDurationHours: Double,
        durationStdHours: Double,
        predictedDemandInr: Double,
        compoundDemandStdInr: Double,
        uncertaintyMarginInr: Double,
        safetyFloorInr: Double,
        confidenceLevel: Double = 0.85,
        recommendedReserveInr: Double,
        previousReserveInr: Double,
        deltaReserveInr: Double,
        recommendationNarrative: String,
        strategySnapshot: StrategyRecommendationSnapshot
    ) {
        self.messageType = Self.messageType
        self.protocolVersion = protocolVersion
        self.predictionId = predictionId
        self.sequenceNumber = sequenceNumber
        self.timestamp = timestamp
        self.senderDeviceId = senderDeviceId
        self.isSimulated = isSimulated
        self.networkStatus = networkStatus
        self.signalDbm = signalDbm
        self.outageProbability = outageProbability
        self.robustOutageProbability = robustOutageProbability
        self.predictedDurationHours = predictedDurationHours
        self.durationStdHours = durationStdHours
        self.predictedDemandInr = predictedDemandInr
        self.compoundDemandStdInr = compoundDemandStdInr
        self.uncertaintyMarginInr = uncertaintyMarginInr
        self.safetyFloorInr = safetyFloorInr
        self.confidenceLevel = confidenceLevel
        self.recommendedReserveInr = recommendedReserveInr
        self.previousReserveInr = previousReserveInr
        self.deltaReserveInr = deltaReserveInr
        self.recommendationNarrative = recommendationNarrative
        self.strategySnapshot = strategySnapshot
    }

    /// Validates message invariants before encoding or after decoding.
    public func validate() throws {
        guard messageType == Self.messageType else {
            throw PeerPredictionError.unsupportedMessageType(messageType)
        }
        guard protocolVersion == Self.currentProtocolVersion else {
            throw PeerPredictionError.unsupportedProtocolVersion(protocolVersion)
        }
        guard !predictionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PeerPredictionError.malformedPayload("Prediction ID must not be blank.")
        }
        guard !senderDeviceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PeerPredictionError.malformedPayload("Sender device ID must not be blank.")
        }
        guard !timestamp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PeerPredictionError.malformedPayload("Timestamp must not be blank.")
        }
        guard isSimulated else {
            throw PeerPredictionError.malformedPayload("isSimulated must be true for research advisories.")
        }
        guard outageProbability >= 0.0 && outageProbability <= 1.0 else {
            throw PeerPredictionError.malformedPayload("Outage probability must be between 0.0 and 1.0.")
        }
        guard predictedDurationHours >= 0.0 else {
            throw PeerPredictionError.malformedPayload("Predicted duration must be non-negative.")
        }
        guard predictedDemandInr >= 0.0 else {
            throw PeerPredictionError.malformedPayload("Predicted demand must be non-negative.")
        }
        guard recommendedReserveInr >= 0.0 else {
            throw PeerPredictionError.malformedPayload("Recommended reserve must be non-negative.")
        }
        guard !recommendationNarrative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PeerPredictionError.malformedPayload("Recommendation narrative must not be blank.")
        }
    }

    /// Encodes this message to JSON Data enforcing maximum payload size.
    public func encode() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maxPayloadBytes else {
            throw PeerPredictionError.payloadTooLarge(data.count)
        }
        return data
    }

    /// Decodes and strictly validates a prediction message from raw wire data.
    public static func decodeAndValidate(from data: Data) throws -> PeerPredictionMessage {
        guard data.count <= maxPayloadBytes else {
            throw PeerPredictionError.payloadTooLarge(data.count)
        }

        if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let lowercasedKeys = Set(jsonObject.keys.map { $0.lowercased() })
            let forbiddenFound = lowercasedKeys.intersection(forbiddenPaymentKeys)
            if !forbiddenFound.isEmpty {
                throw PeerPredictionError.paymentFieldsForbidden
            }
        }

        let decoder = JSONDecoder()
        let message: PeerPredictionMessage
        do {
            message = try decoder.decode(PeerPredictionMessage.self, from: data)
        } catch {
            throw PeerPredictionError.malformedPayload(error.localizedDescription)
        }

        try message.validate()
        return message
    }
}

/// Genuine acknowledgement wire message returned by the iPhone upon receiving and validating
/// a simulated prediction advisory update over MultipeerConnectivity.
public struct PeerPredictionAck: Sendable, Codable, Equatable {
    public static let messageType = "PREDICTION_ACK"
    public static let currentProtocolVersion = 1
    public static let maxPayloadBytes: Int = 4 * 1024

    public let messageType: String
    public let protocolVersion: Int
    public let predictionId: String
    public let sequenceNumber: UInt64
    public let receiverDeviceId: String
    public let timestamp: String
    public let isSimulated: Bool

    public init(
        protocolVersion: Int = currentProtocolVersion,
        predictionId: String,
        sequenceNumber: UInt64,
        receiverDeviceId: String,
        timestamp: String = ISO8601DateFormatter().string(from: Date()),
        isSimulated: Bool = true
    ) {
        self.messageType = Self.messageType
        self.protocolVersion = protocolVersion
        self.predictionId = predictionId
        self.sequenceNumber = sequenceNumber
        self.receiverDeviceId = receiverDeviceId
        self.timestamp = timestamp
        self.isSimulated = isSimulated
    }

    public func validate() throws {
        guard messageType == Self.messageType else {
            throw PeerPredictionError.unsupportedMessageType(messageType)
        }
        guard protocolVersion == Self.currentProtocolVersion else {
            throw PeerPredictionError.unsupportedProtocolVersion(protocolVersion)
        }
        guard !predictionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PeerPredictionError.malformedPayload("Prediction ID must not be blank.")
        }
        guard !receiverDeviceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PeerPredictionError.malformedPayload("Receiver device ID must not be blank.")
        }
    }

    public func encode() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maxPayloadBytes else {
            throw PeerPredictionError.payloadTooLarge(data.count)
        }
        return data
    }

    public static func decodeAndValidate(from data: Data) throws -> PeerPredictionAck {
        guard data.count <= maxPayloadBytes else {
            throw PeerPredictionError.payloadTooLarge(data.count)
        }

        if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let lowercasedKeys = Set(jsonObject.keys.map { $0.lowercased() })
            let forbiddenFound = lowercasedKeys.intersection(PeerPredictionMessage.forbiddenPaymentKeys)
            if !forbiddenFound.isEmpty {
                throw PeerPredictionError.paymentFieldsForbidden
            }
        }

        let decoder = JSONDecoder()
        let ack: PeerPredictionAck
        do {
            ack = try decoder.decode(PeerPredictionAck.self, from: data)
        } catch {
            throw PeerPredictionError.malformedPayload(error.localizedDescription)
        }
        try ack.validate()
        return ack
    }
}
