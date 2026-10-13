import Foundation
import MultipeerConnectivity
import SwiftUI

/// Notification posted when a packet is received on Mac companion.
public extension Notification.Name {
    static let macPacketReceived = Notification.Name("com.upimesh.macPacketReceived")
}

/// Service managing Multipeer Connectivity discovery and packet transfer on the macOS Companion.
///
/// Features:
/// - Advertises and browses using identical service type `"upimesh-pay"`.
/// - Discovers and connects to physical iPhones running UPIMesh.
/// - Validates incoming packets (size <= 64 KB, schema v1, invariants, deduplication).
/// - Mathematically verifies RSASSA-PSS digital signatures using sender's public key.
/// - Explicitly marks sender identity as UNVERIFIED OFFLINE.
/// - Persists received packets as `RECEIVED — NOT SETTLED` without mutating balances or calling backend.
public final class MacPeerTransportService: NSObject, ObservableObject, @unchecked Sendable {

    public static let shared = MacPeerTransportService()
    public static let serviceType = "upimesh-pay"

    private let myPeerId: MCPeerID
    private var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser
    private var browser: MCNearbyServiceBrowser

    @Published public private(set) var isDiscovering: Bool = false
    @Published public private(set) var discoveredPeers: [MCPeerID] = []
    @Published public private(set) var connectedPeer: MCPeerID? = nil
    @Published public private(set) var connectionState: String = "Disconnected"
    @Published public private(set) var lastReceivedRecord: MacReceivedPacketRecord? = nil
    @Published public private(set) var statusMessage: String? = nil
    @Published public private(set) var errorMessage: String? = nil
    @Published public private(set) var sendStatus: String? = nil

    // MARK: - Diagnostic Ping State (Non-Financial Connectivity Test)
    @Published public private(set) var pingStatus: PingStatus = .idle
    @Published public private(set) var lastPingLatencyMs: Int? = nil

    private var pendingPingId: String? = nil
    private var pendingPingStartTime: Date? = nil
    private var pendingPingTimeoutTask: Task<Void, Never>? = nil

    public override init() {
        let rawName = Host.current().localizedName ?? "MacBook Air"
        let cleanName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = cleanName.isEmpty ? "MacBook" : String(cleanName.prefix(20))
        self.myPeerId = MCPeerID(displayName: "\(name) (Mac)")

        self.session = MCSession(peer: self.myPeerId, securityIdentity: nil, encryptionPreference: .required)
        self.advertiser = MCNearbyServiceAdvertiser(peer: self.myPeerId, discoveryInfo: nil, serviceType: Self.serviceType)
        self.browser = MCNearbyServiceBrowser(peer: self.myPeerId, serviceType: Self.serviceType)

        super.init()

        self.session.delegate = self
        self.advertiser.delegate = self
        self.browser.delegate = self
    }

    // MARK: - Discovery Controls

    @MainActor
    public func startDiscovery() {
        guard !isDiscovering else { return }

        errorMessage = nil
        statusMessage = "Scanning & advertising for nearby iPhones (AWDL / BLE)..."
        isDiscovering = true
        discoveredPeers = []

        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    @MainActor
    public func stopDiscovery() {
        guard isDiscovering else { return }

        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()

        isDiscovering = false
        discoveredPeers = []
        statusMessage = "Peer discovery stopped"
    }

    @MainActor
    public func invitePeer(_ peer: MCPeerID) {
        errorMessage = nil
        statusMessage = "Inviting \(peer.displayName)..."
        connectionState = "Connecting..."
        browser.invitePeer(peer, to: session, withContext: nil, timeout: 15)
    }

    @MainActor
    public func disconnect() {
        pendingPingTimeoutTask?.cancel()
        pendingPingTimeoutTask = nil
        pendingPingId = nil
        pendingPingStartTime = nil

        session.disconnect()
        connectedPeer = nil
        connectionState = "Disconnected"
        pingStatus = .idle
        statusMessage = "Disconnected from peer"
    }

    @MainActor
    public func clearBanners() {
        errorMessage = nil
        statusMessage = nil
        sendStatus = nil
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

    /// Transmits a non-financial diagnostic PING to the connected iPhone.
    /// Strictly decoupled from payment processing, Keychain signing, accounts, and settlement.
    @MainActor
    public func sendPing(to peer: MCPeerID, timeoutSeconds: TimeInterval = 5.0) async {
        guard connectedPeer == peer, session.connectedPeers.contains(peer) else {
            pingStatus = .failed("Not connected to \(peer.displayName)")
            errorMessage = "Cannot ping: Not connected to \(peer.displayName)"
            return
        }

        pendingPingTimeoutTask?.cancel()

        let pingId = UUID().uuidString.lowercased()
        let deviceId = (try? MacDeviceIdentityManager.shared.getOrCreateIdentity().deviceId) ?? "mac-companion"
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

    // MARK: - Send Test Packet to Connected iPhone

    /// Constructs and sends a sample signed offline packet from Mac to iPhone.
    /// Demonstrates bidirectional transport without sharing iPhone's keys.
    @MainActor
    public func sendTestPacket(to peer: MCPeerID) async {
        guard connectedPeer == peer, session.connectedPeers.contains(peer) else {
            errorMessage = "Not connected to \(peer.displayName)"
            return
        }

        sendStatus = "Signing and sending packet..."

        do {
            let identity = try MacDeviceIdentityManager.shared.getOrCreateIdentity()

            let instruction = try PaymentInstruction(
                paymentId: UUID().uuidString.lowercased(),
                fromAccount: "carol",
                toAccount: "alice",
                amount: Decimal(15.00),
                createdAt: PaymentInstant.now(),
                nonce: UUID().uuidString.lowercased()
            )

            let canonicalBytes = instruction.toCanonicalBytes()
            let sigBase64 = try MacDeviceIdentityManager.shared.signBase64(message: canonicalBytes)
            let signedInstruction = try instruction.withSignature(sigBase64)

            let packet = try OfflinePaymentPacket(
                instruction: signedInstruction,
                deviceId: identity.deviceId,
                status: .queued
            )

            let message = PeerTransferMessage(
                messageVersion: 1,
                packet: packet,
                senderPublicKeyBase64X509: identity.publicKeyBase64X509
            )
            try message.validate()

            let data = try JSONEncoder().encode(message)
            guard data.count <= PeerTransferMessage.maxPayloadBytes else {
                throw PeerTransferError.payloadTooLarge(data.count)
            }

            try session.send(data, toPeers: [peer], with: .reliable)
            sendStatus = "Packet ₹15.00 successfully sent to \(peer.displayName)!"
        } catch {
            sendStatus = nil
            errorMessage = "Failed to send packet: \(error.localizedDescription)"
        }
    }

    // MARK: - Inbound Ingestion Pipeline

    private func processIncomingData(_ data: Data, from peer: MCPeerID) {
        guard data.count <= PeerTransferMessage.maxPayloadBytes else {
            DispatchQueue.main.async {
                self.errorMessage = "Rejected incoming data from \(peer.displayName): exceeds 64 KB limit."
            }
            return
        }

        // Route inbound data safely between diagnostic and payment pipelines
        let route = InboundTransportProbe.probe(data: data)
        switch route {
        case .diagnosticPing:
            handleInboundDiagnosticPing(data, from: peer)
        case .diagnosticPong:
            handleInboundDiagnosticPong(data, from: peer)
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
            let myDeviceId = (try? MacDeviceIdentityManager.shared.getOrCreateIdentity().deviceId) ?? "mac-companion"
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
                print("[MacPeerTransportService] Ignored unmatched PONG referencing '\(replyTo)' (expected: '\(expectedPingId ?? "none")')")
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Rejected invalid diagnostic PONG from \(peer.displayName): \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Inbound Payment Packet Handler

    private func handleInboundPaymentPacket(_ data: Data, from peer: MCPeerID) {
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

        do {
            try message.validate()
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Rejected invalid packet from \(peer.displayName): \(error.localizedDescription)"
            }
            return
        }

        let pid = message.packet.paymentId
        if MacReceivedPacketStore.shared.contains(paymentId: pid) {
            DispatchQueue.main.async {
                self.errorMessage = "Duplicate packet '\(pid.prefix(8))...' already imported on Mac."
            }
            return
        }

        let isMathValid: Bool
        let trustNote: String

        if let pubKey = message.senderPublicKeyBase64X509, !pubKey.isEmpty {
            let (valid, desc) = MacDeviceIdentityManager.verifyRemoteRSASSA_PSS(
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
            trustNote = "RSASSA-PSS signature mathematically valid. Sender identity is UNVERIFIED OFFLINE (authorization and balance settlement require bridge)."
        } else {
            isMathValid = false
            trustNote = "Unverified: No public key provided. Final verification requires bridge."
        }

        let receivedPacket: OfflinePaymentPacket
        do {
            receivedPacket = try message.packet.withStatus(.received)
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Status update failed: \(error.localizedDescription)"
            }
            return
        }

        let record: MacReceivedPacketRecord
        do {
            record = try MacReceivedPacketRecord(
                packet: receivedPacket,
                receivedAt: PaymentInstant.now(),
                receivedFromPeer: peer.displayName,
                isSignatureMathematicallyValid: isMathValid,
                isSenderIdentityAuthenticated: false,
                trustStatusNote: trustNote
            )
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Record creation failed: \(error.localizedDescription)"
            }
            return
        }

        do {
            try MacReceivedPacketStore.shared.save(record)
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Persistence failed: \(error.localizedDescription)"
            }
            return
        }

        DispatchQueue.main.async {
            self.lastReceivedRecord = record
            self.statusMessage = "Received ₹\(String(format: "%.2f", record.packet.amountDouble)) from \(peer.displayName) (RECEIVED — NOT SETTLED)"
            NotificationCenter.default.post(name: .macPacketReceived, object: record)
        }
    }
}

// MARK: - Multipeer Delegates

extension MacPeerTransportService: MCNearbyServiceAdvertiserDelegate {
    public func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        invitationHandler(true, self.session)
    }

    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async {
            self.errorMessage = "Advertiser error: \(error.localizedDescription)"
            self.isDiscovering = false
        }
    }
}

extension MacPeerTransportService: MCNearbyServiceBrowserDelegate {
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async {
            if !self.discoveredPeers.contains(peerID) {
                self.discoveredPeers.append(peerID)
            }
        }
    }

    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.discoveredPeers.removeAll { $0 == peerID }
            if self.connectedPeer == peerID {
                self.pendingPingTimeoutTask?.cancel()
                self.pendingPingTimeoutTask = nil
                let wasPending = (self.pendingPingId != nil)
                self.pendingPingId = nil
                self.pendingPingStartTime = nil

                self.connectedPeer = nil
                self.connectionState = "Disconnected"
                if wasPending {
                    self.pingStatus = .failed("Peer disconnected during diagnostic round-trip")
                }
                self.statusMessage = "\(peerID.displayName) disconnected"
            }
        }
    }

    public func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async {
            self.errorMessage = "Browser error: \(error.localizedDescription)"
            self.isDiscovering = false
        }
    }
}

extension MacPeerTransportService: MCSessionDelegate {
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                self.connectedPeer = peerID
                self.connectionState = "Connected to \(peerID.displayName)"
                self.statusMessage = "Connected to \(peerID.displayName)"
            case .connecting:
                self.connectionState = "Connecting to \(peerID.displayName)..."
            case .notConnected:
                if self.connectedPeer == peerID {
                    self.pendingPingTimeoutTask?.cancel()
                    self.pendingPingTimeoutTask = nil
                    let wasPending = (self.pendingPingId != nil)
                    self.pendingPingId = nil
                    self.pendingPingStartTime = nil

                    self.connectedPeer = nil
                    self.connectionState = "Disconnected"
                    if wasPending {
                        self.pingStatus = .failed("Peer disconnected during diagnostic round-trip")
                    }
                    self.statusMessage = "Disconnected from \(peerID.displayName)"
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

    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
