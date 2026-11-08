import Foundation
import Combine
import MultipeerConnectivity

/// Data transfer object parsing the Python research simulator `/api/status` JSON response.
public struct PythonSimulatorStatusDTO: Codable, Sendable {
    public let guided_stage: GuidedStageDTO
    public let network_telemetry: NetworkTelemetryDTO
    public let active_prediction: ActivePredictionDTO
    public let recommendation_diff: RecommendationDiffDTO
    public let strategies: [String: StrategyDecisionDTO]

    public struct GuidedStageDTO: Codable, Sendable {
        public let current_stage: Int
        public let total_stages: Int
    }

    public struct NetworkTelemetryDTO: Codable, Sendable {
        public let status: String
        public let signal_dbm: Int
        public let p_out_slider: Double
        public let duration_slider: Double
        public let is_burst: Bool
        public let simulation_epoch: Int
    }

    public struct ActivePredictionDTO: Codable, Sendable {
        public let point_outage_prob: Double
        public let robust_outage_prob: Double
        public let expected_duration_hours: Double
        public let duration_std_hours: Double
        public let predicted_demand_inr: Double
        public let compound_demand_std_inr: Double
        public let uncertainty_margin_inr: Double
        public let safetyFloor_inr: Double?
        public let safety_floor_inr: Double?
        public let confidence_level: Double

        public var resolvedSafetyFloor: Double {
            safety_floor_inr ?? safetyFloor_inr ?? 0.0
        }
    }

    public struct RecommendationDiffDTO: Codable, Sendable {
        public let previous_reserve: Double
        public let current_reserve: Double
        public let delta_reserve: Double
        public let narrative: String
    }

    public struct StrategyDecisionDTO: Codable, Sendable {
        public let recommended_reserve: Double
        public let predicted_outage_prob: Double
        public let predicted_demand: Double
    }
}

/// A verified event entry in the judge-facing presentation timeline.
public struct DemoTimelineItem: Identifiable, Sendable {
    public let id: String
    public let timestamp: Date
    public let type: EventType
    public let title: String
    public let details: String
    public let isConfirmed: Bool

    public enum EventType: String, Sendable {
        case scenarioStarted = "SCENARIO"
        case conditionChanged = "TELEMETRY"
        case shockInjected = "SHOCK"
        case recalculated = "PREDICTION"
        case sent = "SENT"
        case acknowledged = "ACKNOWLEDGED"
        case restored = "RECOVERY"
    }

    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        type: EventType,
        title: String,
        details: String,
        isConfirmed: Bool = true
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.title = title
        self.details = details
        self.isConfirmed = isConfirmed
    }
}

/// Client bridging the local Python research simulator (http://127.0.0.1:8050)
/// with the macOS Companion's MultipeerConnectivity peer transport.
@MainActor
public final class MacPredictionBridgeClient: ObservableObject {

    public static let shared = MacPredictionBridgeClient()

    @Published public private(set) var isConnectedToSimulator: Bool = false
    @Published public private(set) var lastFetchTime: Date? = nil
    @Published public private(set) var lastFetchError: String? = nil
    @Published public private(set) var lastFetchedStatus: PythonSimulatorStatusDTO? = nil

    @Published public private(set) var lastTransmittedMessage: PeerPredictionMessage? = nil
    @Published public private(set) var lastTransmittedAt: Date? = nil
    @Published public private(set) var lastAckReceived: PeerPredictionAck? = nil
    @Published public private(set) var lastAckPeerName: String? = nil

    @Published public private(set) var activeScenarioId: Int = 1
    @Published public private(set) var isShockActive: Bool = false
    @Published public private(set) var timelineEvents: [DemoTimelineItem] = []
    @Published public var autoSyncEnabled: Bool = true

    private let simulatorBaseURL: URL
    private var sequenceCounter: UInt64 = 0
    private var lastTransmittedReserve: Double? = nil
    private var lastTransmittedStage: Int? = nil
    private var pollingTask: Task<Void, Never>? = nil

    public init(baseURL: URL = URL(string: "http://127.0.0.1:8050")!) {
        self.simulatorBaseURL = baseURL
    }

    // MARK: - Presentation Timeline Logging

    public func logTimeline(type: DemoTimelineItem.EventType, title: String, details: String, isConfirmed: Bool = true) {
        let item = DemoTimelineItem(
            timestamp: Date(),
            type: type,
            title: title,
            details: details,
            isConfirmed: isConfirmed
        )
        timelineEvents.insert(item, at: 0)
        if timelineEvents.count > 60 {
            timelineEvents = Array(timelineEvents.prefix(60))
        }
    }

    /// Records genuine acknowledgement received from an iPhone peer over MultipeerConnectivity.
    public func recordAcknowledgedReceipt(_ ack: PeerPredictionAck, from peerName: String) {
        self.lastAckReceived = ack
        self.lastAckPeerName = peerName
        logTimeline(
            type: .acknowledged,
            title: "iPhone Acknowledged Receipt",
            details: "Prediction #\(ack.sequenceNumber) verified by \(peerName) (Device: \(ack.receiverDeviceId.prefix(12))…)",
            isConfirmed: true
        )
    }

    // MARK: - Polling Engine

    public func startPolling() {
        stopPolling()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollSimulatorOnce()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    public func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    public func pollSimulatorOnce() async {
        let statusURL = simulatorBaseURL.appendingPathComponent("api/status")
        var request = URLRequest(url: statusURL)
        request.timeoutInterval = 3.0
        request.httpMethod = "GET"

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                self.isConnectedToSimulator = false
                self.lastFetchError = "Simulator returned HTTP \(code)"
                return
            }

            let dto = try JSONDecoder().decode(PythonSimulatorStatusDTO.self, from: data)
            self.isConnectedToSimulator = true
            self.lastFetchTime = Date()
            self.lastFetchError = nil
            self.lastFetchedStatus = dto

            let currentReserve = dto.recommendation_diff.current_reserve
            let currentStage = dto.guided_stage.current_stage

            let isReserveChanged = (lastTransmittedReserve == nil || abs(currentReserve - (lastTransmittedReserve ?? 0.0)) >= 1.0)
            let isStageChanged = (lastTransmittedStage == nil || currentStage != (lastTransmittedStage ?? 0))

            if autoSyncEnabled && (isReserveChanged || isStageChanged) {
                await broadcastPrediction(from: dto)
            }
        } catch {
            self.isConnectedToSimulator = false
            self.lastFetchError = "Simulator unavailable at \(simulatorBaseURL.host ?? "localhost"):\(simulatorBaseURL.port ?? 8050)"
        }
    }

    // MARK: - Guided Demo Scenarios

    /// Triggers one of the 5 Judge-Facing Demonstration Scenarios.
    public func triggerScenario(_ scenarioId: Int) async {
        self.activeScenarioId = scenarioId

        let outageP: Double
        let durationH: Double
        let signalDbm: Int
        let isShock: Bool
        let scenarioTitle: String
        let conditionDesc: String

        switch scenarioId {
        case 1:
            // Scenario 1 — Normal Connectivity
            self.isShockActive = false
            outageP = 0.06
            durationH = 0.35
            signalDbm = -68
            isShock = false
            scenarioTitle = "Scenario 1: Normal Connectivity"
            conditionDesc = "Dense urban 5G coverage (-68 dBm). Outage Risk: 6%, expected outage: 0.35h. Minimal reserve required."

        case 2:
            // Scenario 2 — Network Deterioration
            self.isShockActive = false
            outageP = 0.45
            durationH = 1.25
            signalDbm = -98
            isShock = false
            scenarioTitle = "Scenario 2: Network Deterioration"
            conditionDesc = "Transit corridor approach (-98 dBm). Outage Risk climbed to 45%, expected duration: 1.25h."

        case 3:
            // Scenario 3 — Sudden Grid Shock
            self.isShockActive = true
            outageP = 0.88
            durationH = 4.50
            signalDbm = -125
            isShock = true
            scenarioTitle = "Scenario 3: Sudden Grid Shock"
            conditionDesc = "Tunnel power failure (-125 dBm). Outage Risk surged to 88%, expected duration: 4.5h. Safety floor engaged."

        case 4:
            // Scenario 4 — Fully Offline Operation
            self.isShockActive = true
            outageP = 0.95
            durationH = 5.00
            signalDbm = -130
            isShock = true
            scenarioTitle = "Scenario 4: Fully Offline Operation"
            conditionDesc = "Zero cell coverage (-130 dBm, 95% outage). Multipeer AWDL/BLE transport delivers updates with 0 internet."

        case 5:
            // Scenario 5 — Connectivity Recovery
            self.isShockActive = false
            outageP = 0.05
            durationH = 0.30
            signalDbm = -65
            isShock = false
            scenarioTitle = "Scenario 5: Connectivity Recovery"
            conditionDesc = "Power & 5G restored (-65 dBm). Outage Risk down to 5%. Reserve recommendation transitions back to liquid baseline."

        default:
            return
        }

        logTimeline(type: .scenarioStarted, title: scenarioTitle, details: "Initiated presenter scenario.")
        if isShock {
            logTimeline(type: .shockInjected, title: "Grid Shock Injected", details: conditionDesc)
        } else if scenarioId == 5 {
            logTimeline(type: .restored, title: "Connectivity Restored", details: conditionDesc)
        } else {
            logTimeline(type: .conditionChanged, title: "Network Conditions Changed", details: conditionDesc)
        }

        // Post parameters to local Python simulator
        let manualURL = simulatorBaseURL.appendingPathComponent("api/manual_telemetry")
        var request = URLRequest(url: manualURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let bodyDict: [String: Any] = [
            "outage_prob": outageP,
            "duration_hours": durationH,
            "signal_dbm": signalDbm,
            "is_shock": isShock
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: bodyDict)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200,
               let dto = try? JSONDecoder().decode(PythonSimulatorStatusDTO.self, from: data) {
                self.isConnectedToSimulator = true
                self.lastFetchedStatus = dto

                let currentReserve = dto.recommendation_diff.current_reserve
                let deltaReserve = dto.recommendation_diff.delta_reserve

                logTimeline(
                    type: .recalculated,
                    title: "Prediction Recalculated",
                    details: "Recommended Reserve: ₹\(Int(currentReserve)) (Δ \(deltaReserve >= 0 ? "+" : "")₹\(Int(deltaReserve))). \(dto.recommendation_diff.narrative)"
                )

                await broadcastPrediction(from: dto)
            }
        } catch {
            self.lastFetchError = "Failed to update simulator: \(error.localizedDescription)"
        }
    }

    /// One-click trigger for Scenario 3 Sudden Shock.
    public func injectGridShock() async {
        await triggerScenario(3)
    }

    /// Reset demo to initial baseline conditions without modifying payment or wallet state.
    public func resetDemo() async {
        let resetURL = simulatorBaseURL.appendingPathComponent("api/reset")
        var request = URLRequest(url: resetURL)
        request.httpMethod = "POST"

        self.activeScenarioId = 1
        self.isShockActive = false
        self.timelineEvents = []
        self.lastAckReceived = nil
        self.lastAckPeerName = nil

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200,
               let dto = try? JSONDecoder().decode(PythonSimulatorStatusDTO.self, from: data) {
                self.isConnectedToSimulator = true
                self.lastFetchedStatus = dto

                logTimeline(
                    type: .scenarioStarted,
                    title: "Demo Reset",
                    details: "Initial baseline restored (5G coverage, 8% outage risk, ₹54 recommended reserve). Demo history cleared."
                )

                await broadcastPrediction(from: dto)
            }
        } catch {
            logTimeline(
                type: .scenarioStarted,
                title: "Demo Reset (Local)",
                details: "Reset demo state locally. Simulator connection pending."
            )
        }
    }

    // MARK: - Multipeer Wire Broadcast

    /// Builds and broadcasts a `PeerPredictionMessage` to the connected iPhone over AWDL/BLE.
    public func broadcastPrediction(from dto: PythonSimulatorStatusDTO) async {
        guard let peer = MacPeerTransportService.shared.connectedPeer else {
            return
        }

        sequenceCounter += 1
        let deviceId = (try? MacDeviceIdentityManager.shared.getOrCreateIdentity().deviceId) ?? "mac-companion"

        let snapshot = StrategyRecommendationSnapshot(
            fixedAllowanceInr: dto.strategies["Fixed-₹500"]?.recommended_reserve ?? 500.0,
            demandOnlyInr: dto.strategies["Demand-Only"]?.recommended_reserve ?? 790.0,
            proposedM1Inr: dto.strategies["Proposed-JointOpt"]?.recommended_reserve ?? 110.0,
            uncertaintyM2Inr: dto.strategies["Uncertainty-Aware"]?.recommended_reserve ?? dto.recommendation_diff.current_reserve
        )

        let msg = PeerPredictionMessage(
            sequenceNumber: sequenceCounter,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            senderDeviceId: deviceId,
            isSimulated: true,
            networkStatus: dto.network_telemetry.status,
            signalDbm: dto.network_telemetry.signal_dbm,
            outageProbability: dto.active_prediction.point_outage_prob,
            robustOutageProbability: dto.active_prediction.robust_outage_prob,
            predictedDurationHours: dto.active_prediction.expected_duration_hours,
            durationStdHours: dto.active_prediction.duration_std_hours,
            predictedDemandInr: dto.active_prediction.predicted_demand_inr,
            compoundDemandStdInr: dto.active_prediction.compound_demand_std_inr,
            uncertaintyMarginInr: dto.active_prediction.uncertainty_margin_inr,
            safetyFloorInr: dto.active_prediction.resolvedSafetyFloor,
            confidenceLevel: dto.active_prediction.confidence_level,
            recommendedReserveInr: dto.recommendation_diff.current_reserve,
            previousReserveInr: dto.recommendation_diff.previous_reserve,
            deltaReserveInr: dto.recommendation_diff.delta_reserve,
            recommendationNarrative: dto.recommendation_diff.narrative,
            strategySnapshot: snapshot
        )

        do {
            try await MacPeerTransportService.shared.sendPredictionUpdate(msg, to: peer)
            self.lastTransmittedMessage = msg
            self.lastTransmittedAt = Date()
            self.lastTransmittedReserve = dto.recommendation_diff.current_reserve
            self.lastTransmittedStage = dto.guided_stage.current_stage

            logTimeline(
                type: .sent,
                title: "Prediction Transmitted",
                details: "Sent Seq #\(msg.sequenceNumber) (Reserve ₹\(Int(msg.recommendedReserveInr))) to \(peer.displayName) over MultipeerConnectivity.",
                isConfirmed: true
            )
        } catch {
            print("[MacPredictionBridgeClient] Broadcast failed: \(error.localizedDescription)")
        }
    }

    /// Manual trigger to force immediate sync to iPhone.
    public func manualSyncNow() async {
        let statusURL = simulatorBaseURL.appendingPathComponent("api/status")
        guard let (data, _) = try? await URLSession.shared.data(from: statusURL),
              let dto = try? JSONDecoder().decode(PythonSimulatorStatusDTO.self, from: data) else {
            return
        }
        await broadcastPrediction(from: dto)
    }
}
