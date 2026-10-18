import Foundation
import MultipeerConnectivity
import SwiftUI

/// Transport connection states between nearby peers.
public enum PeerConnectionState: String, Sendable, Equatable {
    case disconnected = "Disconnected"
    case connecting = "Connecting"
    case connected = "Connected"
}

/// Send operation states for peer packet transfer.
public enum PacketSendStatus: Sendable, Equatable {
    case idle
    case sending(String)
    case success(String)
    case failed(String)
}

/// Notification posted when a new offline payment packet is successfully received and stored in inbox.
public extension Notification.Name {
    static let offlinePacketReceived = Notification.Name("com.upimesh.offlinePacketReceived")
    static let offlinePacketSent = Notification.Name("com.upimesh.offlinePacketSent")
}

/// Service managing direct phone-to-phone discovery and reliable offline packet transfer via Multipeer Connectivity.
///
/// Under the prototype architecture:
/// - Connects two physical iPhones directly using Bluetooth LE discovery + peer-to-peer Wi-Fi (AWDL).
/// - Transmits the immutable signed `OfflinePaymentPacket` inside `PeerTransferMessage`.
/// - Does NOT require cellular, external Wi-Fi, or backend requests during transfer.
/// - Performs full mathematical signature verification against the sender's public key.
/// - Stores received packets in an isolated `ReceivedPacketStore` as `RECEIVED — NOT SETTLED`.
/// - Does NOT mutate account balances or claim settlement finality.
public final class MeshPeerTransportService: NSObject, ObservableObject, @unchecked Sendable {

    /// Shared singleton instance for the app.
    public static let shared = MeshPeerTransportService()

    /// Multipeer service identifier (1-15 ASCII alphanumeric/hyphen characters).
    public static let serviceType = "upimesh-pay"

    private let myPeerId: MCPeerID
    private var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser
    private var browser: MCNearbyServiceBrowser

    private let stateLock = NSLock()

    // MARK: - Published State for SwiftUI

    @Published public private(set) var isDiscovering: Bool = false
    @Published public private(set) var discoveredPeers: [MCPeerID] = []
    @Published public private(set) var connectedPeer: MCPeerID? = nil
    @Published public private(set) var connectionState: PeerConnectionState = .disconnected
    @Published public private(set) var sendStatus: PacketSendStatus = .idle
    @Published public private(set) var lastReceivedRecord: ReceivedPacketRecord? = nil
    @Published public private(set) var statusMessage: String? = nil
    @Published public private(set) var errorMessage: String? = nil

    // MARK: - Diagnostic Ping State (Non-Financial Connectivity Test)
    @Published public private(set) var pingStatus: PingStatus = .idle
    @Published public private(set) var lastPingLatencyMs: Int? = nil
    @Published public private(set) var lastDiagnosticPingAnswered: String? = nil

    private var pendingPingId: String? = nil
    private var pendingPingStartTime: Date? = nil
    private var pendingPingTimeoutTask: Task<Void, Never>? = nil

    public override init() {
        // Derive human-readable peer display name
        let deviceName: String
        #if canImport(UIKit)
        deviceName = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        #else
        deviceName = Host.current().localizedName ?? "iPhone"
        #endif

        let cleanName = deviceName.isEmpty ? "iPhone" : String(deviceName.prefix(20))
        self.myPeerId = MCPeerID(displayName: cleanName)

        self.session = MCSession(peer: self.myPeerId, securityIdentity: nil, encryptionPreference: .optional)
        self.advertiser = MCNearbyServiceAdvertiser(peer: self.myPeerId, discoveryInfo: nil, serviceType: Self.serviceType)
        self.browser = MCNearbyServiceBrowser(peer: self.myPeerId, serviceType: Self.serviceType)

        super.init()

        self.session.delegate = self
        self.advertiser.delegate = self
        self.browser.delegate = self
    }

    /// Re-creates a fresh MCSession to clear stale socket/DTLS state.
    private func recreateSession() {
        session.delegate = nil
        session.disconnect()
        session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .optional)
        session.delegate = self
    }

    // MARK: - Discovery Controls

    /// Starts both advertising and browsing for nearby peer devices.
    @MainActor
    public func startDiscovery() {
        guard !isDiscovering else { return }

        errorMessage = nil
        statusMessage = "Broadcasting & scanning for nearby iPhones..."
        isDiscovering = true
        discoveredPeers = []

        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    /// Stops both advertising and browsing.
    @MainActor
    public func stopDiscovery() {
        guard isDiscovering else { return }

        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()

        isDiscovering = false
        discoveredPeers = []
        statusMessage = "Peer discovery stopped"
    }

    /// Invites a discovered peer to connect.
    @MainActor
    public func invitePeer(_ peer: MCPeerID) {
        guard connectionState != .connecting else { return }

        errorMessage = nil
        statusMessage = "Inviting \(peer.displayName)..."
        connectionState = .connecting
        browser.invitePeer(peer, to: session, withContext: nil, timeout: 15)
    }

    /// Disconnects the active session and resets connection state.
    @MainActor
    public func disconnect() {
        pendingPingTimeoutTask?.cancel()
        pendingPingTimeoutTask = nil
        pendingPingId = nil
        pendingPingStartTime = nil

        recreateSession()
        connectedPeer = nil
        connectionState = .disconnected
        sendStatus = .idle
        pingStatus = .idle
        statusMessage = "Disconnected from peer"
    }

    /// Clears any active error or status banners.
    @MainActor
    public func clearBanners() {
        errorMessage = nil
        statusMessage = nil
    }

    @MainActor
    public func clearPingStatus() {
        pendingPingTimeoutTask?.cancel()
        pendingPingTimeoutTask = nil
        pendingPingId = nil
        pendingPingStartTime = nil
        pingStatus = .idle
    }

    // MARK: - Diagnostic Ping Round-Trip (Harmless Connectivity Test)

    /// Transmits a non-financial diagnostic PING to the connected peer.
    /// Strictly decoupled from payment processing, Keychain signing, accounts, and settlement.
    @MainActor
    public func sendPing(to peer: MCPeerID, timeoutSeconds: TimeInterval = 5.0) async {
        guard connectionState == .connected, connectedPeer == peer else {
            pingStatus = .failed("Not connected to \(peer.displayName)")
            errorMessage = "Cannot ping: Not connected to \(peer.displayName)"
            return
        }
        guard session.connectedPeers.contains(peer) else {
            pingStatus = .failed("Peer disconnected")
            errorMessage = "Cannot ping: \(peer.displayName) is not connected."
            return
        }

        pendingPingTimeoutTask?.cancel()

        let pingId = UUID().uuidString.lowercased()
        let deviceId = (try? DeviceIdentityManager.shared.getOrCreateIdentity().deviceId) ?? "iphone"
        let pingMessage = PeerDiagnosticMessage(
            messageType: .ping,
            diagnosticId: pingId,
            senderDeviceId: deviceId,
            timestamp: PaymentInstant.now().isoString,
            replyToId: nil
        )

        let startTime = Date()
        pendingPingId = pingId
        pendingPingStartTime = startTime

        pingStatus = .sending(pingId: pingId, startedAt: startTime)
        statusMessage = "Pinging \(peer.displayName)..."

        do {
            let data = try pingMessage.encode()
            try session.send(data, toPeers: [peer], with: .reliable)
        } catch {
            pendingPingId = nil
            pendingPingStartTime = nil

            pingStatus = .failed(error.localizedDescription)
            errorMessage = "Ping send failed: \(error.localizedDescription)"
            return
        }

        // Arm timeout timer
        pendingPingTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
            guard let self = self, !Task.isCancelled else { return }

            if self.pendingPingId == pingId {
                self.pendingPingId = nil
                self.pendingPingStartTime = nil
                self.pingStatus = .failed("Ping timed out after \(Int(timeoutSeconds))s (no response from \(peer.displayName))")
                self.errorMessage = "Diagnostic ping to \(peer.displayName) timed out."
            }
        }
    }

    // MARK: - Packet Transfer

    /// Sends a signed offline payment packet to the currently connected peer.
    ///
    /// - Parameters:
    ///   - packet: The existing signed `OfflinePaymentPacket` to transmit.
    ///   - peer: The target connected `MCPeerID`.
    @MainActor
    public func sendPacket(_ packet: OfflinePaymentPacket, to peer: MCPeerID) async throws {
        guard connectionState == .connected, connectedPeer == peer else {
            throw PeerTransferError.notConnected
        }
        guard session.connectedPeers.contains(peer) else {
            throw PeerTransferError.peerDisconnected
        }

        guard case .sending = sendStatus else {
            // Proceed
            sendStatus = .sending(packet.paymentId)
            statusMessage = "Sending packet to \(peer.displayName)..."

            do {
                // 1. Export local device public key to allow recipient to verify signature mathematically
                let pubKey = try? DeviceIdentityManager.shared.exportPublicKeyBase64X509()

                // 2. Wrap into transport envelope
                let message = PeerTransferMessage(
                    messageVersion: 1,
                    packet: packet,
                    senderPublicKeyBase64X509: pubKey
                )
                try message.validate()

                // 3. Encode to JSON Data
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let data = try encoder.encode(message)

                guard data.count <= PeerTransferMessage.maxPayloadBytes else {
                    throw PeerTransferError.payloadTooLarge(data.count)
                }

                // 4. Transmit reliably via Multipeer Connectivity
                try session.send(data, toPeers: [peer], with: .reliable)

                // Update sender packet status to .sent in OfflinePacketStore
                _ = try? OfflinePacketStore.shared.updateStatus(paymentId: packet.paymentId, status: .sent)

                sendStatus = .success(packet.paymentId)
                statusMessage = "Packet successfully delivered to \(peer.displayName)"
                NotificationCenter.default.post(name: .offlinePacketSent, object: packet)
            } catch {
                sendStatus = .failed(error.localizedDescription)
                errorMessage = "Send failed: \(error.localizedDescription)"
                throw error
            }
            return
        }
    }

    // MARK: - Inbound Ingestion Pipeline

    private func processIncomingData(_ data: Data, from peer: MCPeerID) {
        // 1. Enforce payload size limit (max 64 KB)
        guard data.count <= PeerTransferMessage.maxPayloadBytes else {
            DispatchQueue.main.async {
                self.errorMessage = "Rejected incoming data from \(peer.displayName): exceeds 64 KB limit."
            }
            return
        }

        // 2. Route inbound data safely between diagnostic and payment pipelines
        let route = InboundTransportProbe.probe(data: data)
        switch route {
        case .diagnosticPing:
            handleInboundDiagnosticPing(data, from: peer)
        case .diagnosticPong:
            handleInboundDiagnosticPong(data, from: peer)
        case .paymentAck:
            handleInboundPaymentAck(data, from: peer)
        case .invalidDiagnostic(let type):
            DispatchQueue.main.async {
                self.errorMessage = "Rejected invalid diagnostic message type '\(type)' from \(peer.displayName)"
            }
        case .paymentTransfer:
            handleInboundPaymentPacket(data, from: peer)
        case .unknown:
            DispatchQueue.main.async {
                self.errorMessage = "Rejected unrecognized or malformed payload from \(peer.displayName)"
            }
        }
    }

    // MARK: - Diagnostic Inbound Handlers (Strictly Non-Financial)

    private func handleInboundDiagnosticPing(_ data: Data, from peer: MCPeerID) {
        do {
            let pingMsg = try PeerDiagnosticMessage.decodeAndValidate(from: data)
            let myDeviceId = (try? DeviceIdentityManager.shared.getOrCreateIdentity().deviceId) ?? "iphone"
            let pongMsg = PeerDiagnosticMessage(
                messageType: .pong,
                diagnosticId: UUID().uuidString.lowercased(),
                senderDeviceId: myDeviceId,
                timestamp: PaymentInstant.now().isoString,
                replyToId: pingMsg.diagnosticId
            )
            let pongData = try pongMsg.encode()
            try session.send(pongData, toPeers: [peer], with: .reliable)

            DispatchQueue.main.async {
                self.lastDiagnosticPingAnswered = "Responded to PING from \(peer.displayName) (PONG sent)"
                self.statusMessage = "Responded to diagnostic PING from \(peer.displayName) with PONG ✓"
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Rejected invalid diagnostic PING from \(peer.displayName): \(error.localizedDescription)"
            }
        }
    }

    private func handleInboundDiagnosticPong(_ data: Data, from peer: MCPeerID) {
        do {
            let pongMsg = try PeerDiagnosticMessage.decodeAndValidate(from: data)
            guard let replyTo = pongMsg.replyToId else {
                DispatchQueue.main.async {
                    self.errorMessage = "Rejected PONG from \(peer.displayName): missing replyToId"
                }
                return
            }

            let expectedPingId = pendingPingId
            let startTime = pendingPingStartTime
            if expectedPingId == replyTo, let startTime = startTime {
                pendingPingId = nil
                pendingPingStartTime = nil
                pendingPingTimeoutTask?.cancel()
                pendingPingTimeoutTask = nil

                let durationMs = max(1, Int(Date().timeIntervalSince(startTime) * 1000))
                DispatchQueue.main.async {
                    self.lastPingLatencyMs = durationMs
                    self.pingStatus = .success(
                        roundTripDurationMs: durationMs,
                        peerName: peer.displayName,
                        pingId: replyTo
                    )
                    self.statusMessage = "Ping round-trip: \(durationMs) ms to \(peer.displayName) ✓"
                }
            } else {
                // Unmatched response: ignore safely without marking success
                print("[MeshPeerTransportService] Ignored unmatched PONG referencing '\(replyTo)' (expected: '\(expectedPingId ?? "none")')")
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Rejected invalid diagnostic PONG from \(peer.displayName): \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Inbound Payment Packet Handler

    private func handleInboundPaymentPacket(_ data: Data, from peer: MCPeerID) {
        // Deserialize transport envelope
        let decoder = JSONDecoder()
        let message: PeerTransferMessage
        do {
            message = try decoder.decode(PeerTransferMessage.self, from: data)
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Rejected malformed payload from \(peer.displayName): \(error.localizedDescription)"
            }
            return
        }

        // Validate transport and packet invariants
        do {
            try message.validate()
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Rejected invalid packet from \(peer.displayName): \(error.localizedDescription)"
            }
            return
        }

        let pid = message.packet.paymentId
        let myDeviceId = (try? DeviceIdentityManager.shared.getOrCreateIdentity().deviceId) ?? "iphone"

        // Deduplication protection across both Outgoing Store and Received Inbox
        if OfflinePacketStore.shared.contains(paymentId: pid) || ReceivedPacketStore.shared.contains(paymentId: pid) {
            // Acknowledge receipt as duplicate so sender knows it was already received and persisted
            let ack = PeerTransferAckMessage(
                paymentId: pid,
                recipientDeviceId: myDeviceId,
                isPersisted: true,
                isDuplicate: true
            )
            if let ackData = try? ack.encode() {
                try? session.send(ackData, toPeers: [peer], with: .reliable)
            }
            DispatchQueue.main.async {
                self.errorMessage = "Rejected duplicate packet '\(pid.prefix(8))...' from \(peer.displayName) (already stored)."
            }
            return
        }

        // 5. Cryptographic signature verification
        let isMathValid: Bool
        let trustNote: String

        if let pubKey = message.senderPublicKeyBase64X509, !pubKey.isEmpty {
            let (valid, desc) = DeviceIdentityManager.verifyRemoteRSASSA_PSS(
                publicKeyBase64X509: pubKey,
                message: message.packet.canonicalBytes,
                signatureBase64: message.packet.signature
            )
            guard valid else {
                DispatchQueue.main.async {
                    self.errorMessage = "Rejected packet from \(peer.displayName): RSASSA-PSS signature invalid (\(desc ?? "verification failed"))."
                }
                return
            }
            isMathValid = true
            trustNote = "RSASSA-PSS signature mathematically valid. Sender identity is UNVERIFIED offline (authorization and balance settlement require bridge)."
        } else {
            // No public key provided
            isMathValid = false
            trustNote = "Unverified: No public key provided in transport message. Final verification requires bridge."
        }

        // 6. Transition packet status to RECEIVED (strictly NOT settled)
        let receivedPacket: OfflinePaymentPacket
        do {
            receivedPacket = try message.packet.withStatus(.received)
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Failed to update packet status to RECEIVED: \(error.localizedDescription)"
            }
            return
        }

        // 7. Construct ReceivedPacketRecord
        let record: ReceivedPacketRecord
        do {
            record = try ReceivedPacketRecord(
                packet: receivedPacket,
                receivedAt: PaymentInstant.now(),
                receivedFromPeer: peer.displayName,
                isSignatureMathematicallyValid: isMathValid,
                isSenderIdentityAuthenticated: false, // Explicitly unauthenticated offline
                trustStatusNote: trustNote,
                reconciliationStatus: .received
            )
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Failed to construct received record: \(error.localizedDescription)"
            }
            return
        }

        // 8. Persist to isolated ReceivedPacketStore BEFORE acknowledging receipt
        do {
            try ReceivedPacketStore.shared.save(record)
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Failed to persist received packet: \(error.localizedDescription)"
            }
            return
        }

        // ONLY AFTER SUCCESSFUL DISK PERSISTENCE, send explicit ACK back to peer
        let ack = PeerTransferAckMessage(
            paymentId: pid,
            recipientDeviceId: myDeviceId,
            isPersisted: true,
            isDuplicate: false
        )
        if let ackData = try? ack.encode() {
            try? session.send(ackData, toPeers: [peer], with: .reliable)
        }

        // 9. Update UI on Main thread and post notification
        DispatchQueue.main.async {
            self.lastReceivedRecord = record
            self.statusMessage = "Received ₹\(CurrencyFormatter.format(amount: record.packet.amountDouble)) from \(peer.displayName) (STORED IN INBOX — NOT SETTLED)"
            NotificationCenter.default.post(name: .offlinePacketReceived, object: record)
        }
    }

    // MARK: - Inbound Payment ACK Handler

    private func handleInboundPaymentAck(_ data: Data, from peer: MCPeerID) {
        do {
            let ack = try PeerTransferAckMessage.decodeAndValidate(from: data)
            guard ack.isPersisted else {
                DispatchQueue.main.async {
                    self.errorMessage = "Peer \(peer.displayName) reported persistence failure for payment '\(ack.paymentId.prefix(8))...'"
                }
                return
            }

            if OfflinePacketStore.shared.contains(paymentId: ack.paymentId) {
                _ = try? OfflinePacketStore.shared.updateStatus(paymentId: ack.paymentId, status: .sent)
            }

            DispatchQueue.main.async {
                self.sendStatus = .success(ack.paymentId)
                let dupSuffix = ack.isDuplicate ? " (already persisted)" : ""
                self.statusMessage = "Payment persisted by \(peer.displayName)\(dupSuffix) ✓ [STATUS: SENT]"
                NotificationCenter.default.post(
                    name: .offlinePacketSent,
                    object: nil,
                    userInfo: ["paymentId": ack.paymentId, "isDuplicate": ack.isDuplicate]
                )
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Failed to process payment ACK from \(peer.displayName): \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MeshPeerTransportService: MCNearbyServiceAdvertiserDelegate {
    public func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        // Automatically accept incoming connection invitation into active session
        invitationHandler(true, self.session)
    }

    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async {
            self.errorMessage = "Advertiser failed: \(error.localizedDescription)"
            self.isDiscovering = false
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MeshPeerTransportService: MCNearbyServiceBrowserDelegate {
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async {
            if !self.discoveredPeers.contains(peerID) {
                self.discoveredPeers.append(peerID)
            }
            // Deterministic tie-breaker to prevent simultaneous dual-invite socket collisions:
            // Only auto-invite if we are disconnected and our peer displayName is lexicographically greater.
            if self.connectionState == .disconnected && self.myPeerId.displayName > peerID.displayName {
                self.invitePeer(peerID)
            }
        }
    }

    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.discoveredPeers.removeAll { $0 == peerID }
            if self.connectedPeer == peerID {
                let wasPending = (self.pendingPingId != nil)
                self.pendingPingId = nil
                self.pendingPingStartTime = nil

                self.connectedPeer = nil
                self.connectionState = .disconnected
                if wasPending {
                    self.pingStatus = .failed("Peer disconnected during diagnostic round-trip")
                }
                self.statusMessage = "Peer \(peerID.displayName) went out of range"
            }
        }
    }

    public func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async {
            self.errorMessage = "Browser failed: \(error.localizedDescription)"
            self.isDiscovering = false
        }
    }
}

// MARK: - MCSessionDelegate

extension MeshPeerTransportService: MCSessionDelegate {
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                self.connectedPeer = peerID
                self.connectionState = .connected
                self.statusMessage = "Connected to \(peerID.displayName)"
            case .connecting:
                self.connectionState = .connecting
                self.statusMessage = "Connecting to \(peerID.displayName)..."
            case .notConnected:
                let wasPending = (self.pendingPingId != nil)
                self.pendingPingId = nil
                self.pendingPingStartTime = nil

                let wasConnected = (self.connectedPeer == peerID)
                if wasConnected {
                    self.connectedPeer = nil
                }
                self.connectionState = .disconnected
                if wasPending {
                    self.pingStatus = .failed("Peer disconnected during diagnostic round-trip")
                }
                if wasConnected {
                    self.statusMessage = "Disconnected from \(peerID.displayName)"
                } else {
                    self.statusMessage = "Connection to \(peerID.displayName) failed or was cancelled"
                }
            @unknown default:
                break
            }
        }
    }

    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.processIncomingData(data, from: peerID)
        }
    }

    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Streaming not utilized for discrete payment packets
    }

    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // Resource transfers not utilized
    }

    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // Resource transfers not utilized
    }
}
