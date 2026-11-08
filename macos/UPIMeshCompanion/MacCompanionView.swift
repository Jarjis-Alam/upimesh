import SwiftUI
import MultipeerConnectivity

/// Native macOS Companion Screen for Testing Offline Peer Packet Transport against iPhone.
public struct MacCompanionView: View {

    @ObservedObject private var transport = MacPeerTransportService.shared
    @ObservedObject private var bridgeClient = MacPredictionBridgeClient.shared
    @State private var receivedPackets: [MacReceivedPacketRecord] = []
    @State private var macIdentity: MacDeviceIdentity? = nil
    @State private var selectedCompanionTab: CompanionTab = .demoMode

    public enum CompanionTab: String, CaseIterable, Identifiable {
        case demoMode = "DEMO MODE (Research Station)"
        case packetInbox = "PAYMENT PACKET INBOX"

        public var id: String { self.rawValue }
    }

    // MARK: - Bridge Registration State
    @State private var bridgeRegistrationState: BridgeRegistrationState = .unregistered
    @State private var bridgeErrorMessage: String? = nil
    @State private var bridgeSuccessMessage: String? = nil
    @State private var isRegistering: Bool = false

    public enum BridgeRegistrationState: Equatable, Sendable {
        case unregistered
        case registering
        case registered(isNew: Bool)
        case failed(String)
    }

    private let bgDark = Color(red: 0.04, green: 0.04, blue: 0.05)
    private let cardBg = Color(red: 0.09, green: 0.09, blue: 0.11)
    private let cardBorder = Color.white.opacity(0.08)
    private let meshGold = Color(red: 1.0, green: 0.83, blue: 0.0) // #FFD400
    private let textPrimary = Color.white
    private let textSecondary = Color.white.opacity(0.65)
    private let textMuted = Color.white.opacity(0.4)
    private let amberNotSettled = Color(red: 0.95, green: 0.65, blue: 0.1)

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar

            // Main Split Workspace
            HSplitView {
                // Left Panel: Transport & Connection Controls
                leftTransportPanel
                    .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)

                // Right Panel: Demo Mode Station OR Received Packets Inbox
                if selectedCompanionTab == .demoMode {
                    demoStationPanel
                        .frame(minWidth: 500, idealWidth: 620)
                } else {
                    rightInboxPanel
                        .frame(minWidth: 450, idealWidth: 550)
                }
            }

            // Bottom Alert / Status Bar
            statusBar
        }
        .background(bgDark)
        .onAppear {
            reloadIdentity()
            reloadPackets()
            bridgeClient.startPolling()
            if !transport.isDiscovering {
                transport.startDiscovery()
            }
        }
        .onDisappear {
            bridgeClient.stopPolling()
        }
        .onReceive(NotificationCenter.default.publisher(for: .macPacketReceived)) { _ in
            reloadPackets()
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundColor(meshGold)
                .font(.system(size: 18, weight: .bold))

            VStack(alignment: .leading, spacing: 1) {
                Text("UPI Offline Mesh — macOS Peer Test Companion")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(textPrimary)

                if let id = macIdentity {
                    Text("Mac Device: \(id.deviceId) · Key: \(id.publicKeyFingerprint.prefix(17))…")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(textMuted)
                }
            }

            Spacer()

            // Prominent View Mode Switcher
            HStack(spacing: 0) {
                Button {
                    selectedCompanionTab = .demoMode
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "gauge.with.needle.fill")
                        Text("DEMO MODE")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(selectedCompanionTab == .demoMode ? Color.cyan.opacity(0.3) : Color.clear)
                    .foregroundColor(selectedCompanionTab == .demoMode ? Color.cyan : textMuted)
                }
                .buttonStyle(.plain)

                Button {
                    selectedCompanionTab = .packetInbox
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "tray.fill")
                        Text("PACKET INBOX (\(receivedPackets.count))")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(selectedCompanionTab == .packetInbox ? meshGold.opacity(0.25) : Color.clear)
                    .foregroundColor(selectedCompanionTab == .packetInbox ? meshGold : textMuted)
                }
                .buttonStyle(.plain)
            }
            .background(Color.white.opacity(0.06))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.15), lineWidth: 1))

            Spacer()

            // Discovery State Indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(transport.isDiscovering ? meshGold : Color.gray)
                    .frame(width: 7, height: 7)

                Text(transport.isDiscovering ? "DISCOVERING PEERS" : "DISCOVERY IDLE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(transport.isDiscovering ? meshGold : textMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(transport.isDiscovering ? meshGold.opacity(0.15) : Color.white.opacity(0.05)))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.4))
        .overlay(Rectangle().frame(height: 1).foregroundColor(cardBorder), alignment: .bottom)
    }

    // MARK: - Left Transport Panel

    private var leftTransportPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Predictive Provisioning Research Bridge Card
                predictiveResearchBridgeCard

                // Bridge Registration Card
                bridgeRegistrationCard

                // Discovery Action Card
                VStack(alignment: .leading, spacing: 10) {
                    Text("NEARBY DEVICE DISCOVERY (AWDL / BLE)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(textMuted)

                    Button {
                        if transport.isDiscovering {
                            transport.stopDiscovery()
                        } else {
                            transport.startDiscovery()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: transport.isDiscovering ? "stop.circle.fill" : "play.circle.fill")
                                .foregroundColor(transport.isDiscovering ? Color.red : meshGold)
                            Text(transport.isDiscovering ? "Stop Scanning & Advertising" : "Start Scanning for iPhones")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(transport.isDiscovering ? Color.red.opacity(0.8) : meshGold)
                    .foregroundColor(transport.isDiscovering ? .white : .black)

                    Text("Matches service type 'upimesh-pay' with zero-configuration peer-to-peer Wi-Fi.")
                        .font(.system(size: 11))
                        .foregroundColor(textMuted)
                }
                .padding(14)
                .background(cardBg)
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(cardBorder, lineWidth: 1))

                // Connection State Card
                VStack(alignment: .leading, spacing: 10) {
                    Text("ACTIVE CONNECTION")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(textMuted)

                    if let peer = transport.connectedPeer {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "iphone.gen3")
                                    .foregroundColor(meshGold)
                                Text(peer.displayName)
                                    .fontWeight(.bold)
                                    .foregroundColor(textPrimary)
                                Spacer()
                                Button("Disconnect") {
                                    transport.disconnect()
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                                .font(.system(size: 11))
                            }

                            Text("Status: \(transport.connectionState)")
                                .font(.system(size: 11))
                                .foregroundColor(meshGold)

                            Divider().background(cardBorder)

                            // Diagnostic Peer Connectivity Section (Non-Financial Ping Test)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("PEER CONNECTIVITY TEST")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(textMuted)
                                    Spacer()
                                    Text("NON-FINANCIAL")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(Color.cyan)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.cyan.opacity(0.15)))
                                }

                                Button {
                                    Task {
                                        await transport.sendPing(to: peer)
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        if transport.pingStatus.isSending {
                                            ProgressView()
                                                .controlSize(.small)
                                            Text("Pinging \(peer.displayName)...")
                                        } else {
                                            Image(systemName: "bolt.horizontal.fill")
                                            Text("Ping Peer")
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Color.cyan)
                                .foregroundColor(.black)
                                .font(.system(size: 11, weight: .bold))
                                .disabled(transport.pingStatus.isSending)

                                // Diagnostic Ping Status Display (Idle / Sending / Success / Failed)
                                switch transport.pingStatus {
                                case .idle:
                                    Text("Transmits a harmless PING/PONG diagnostic message to measure round-trip latency without creating payments, altering balances, or contacting the ledger.")
                                        .font(.system(size: 10))
                                        .foregroundColor(textMuted)
                                case .sending:
                                    HStack(spacing: 5) {
                                        ProgressView().controlSize(.small)
                                        Text("Transmitting PING to \(peer.displayName) and awaiting PONG...")
                                            .font(.system(size: 10))
                                            .foregroundColor(textSecondary)
                                    }
                                case .success(let ms, let peerName, _):
                                    HStack {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.system(size: 11))
                                        Text("PONG received · Round-trip: \(ms) ms to \(peerName) ✓")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.green)
                                        Spacer()
                                        Button("Clear") {
                                            transport.clearPingStatus()
                                        }
                                        .buttonStyle(.plain)
                                        .font(.system(size: 9))
                                        .foregroundColor(textMuted)
                                    }
                                    .padding(6)
                                    .background(Color.green.opacity(0.12))
                                    .cornerRadius(6)
                                case .failed(let err):
                                    HStack {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.red)
                                            .font(.system(size: 11))
                                        Text("Ping failed: \(err)")
                                            .font(.system(size: 10))
                                            .foregroundColor(.red)
                                        Spacer()
                                        Button("Clear") {
                                            transport.clearPingStatus()
                                        }
                                        .buttonStyle(.plain)
                                        .font(.system(size: 9))
                                        .foregroundColor(textMuted)
                                    }
                                    .padding(6)
                                    .background(Color.red.opacity(0.12))
                                    .cornerRadius(6)
                                }
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.03))
                            .cornerRadius(8)

                            Divider().background(cardBorder)

                            // Send Test Packet to iPhone button (Offline Payment Prototype)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("OFFLINE PAYMENT TEST PACKET")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(textMuted)

                                Button {
                                    Task {
                                        await transport.sendTestPacket(to: peer)
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "paperplane.fill")
                                        Text("Send Test Packet (₹15.00) to iPhone")
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .tint(meshGold)
                                .font(.system(size: 11, weight: .semibold))
                            }
                        }
                    } else {
                        HStack {
                            Image(systemName: "link.badge.plus")
                                .foregroundColor(textMuted)
                            Text(transport.connectionState)
                                .foregroundColor(textSecondary)
                            if transport.connectionState.hasPrefix("Connecting") {
                                Spacer()
                                Button("Cancel") {
                                    transport.disconnect()
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                                .font(.system(size: 10, weight: .semibold))
                            }
                        }
                        .font(.system(size: 12))
                    }
                }
                .padding(14)
                .background(cardBg)
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(cardBorder, lineWidth: 1))

                // Discovered Nearby Peers List
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("DISCOVERED PEERS")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(textMuted)
                        Spacer()
                        Text("\(transport.discoveredPeers.count) in range")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(meshGold)
                    }

                    if transport.discoveredPeers.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(.system(size: 20))
                                .foregroundColor(textMuted)
                            Text(transport.isDiscovering ? "Searching for nearby iPhones..." : "Discovery idle. Tap 'Start Scanning'.")
                                .font(.system(size: 12))
                                .foregroundColor(textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(transport.discoveredPeers, id: \.self) { peer in
                                HStack {
                                    Image(systemName: "iphone.gen3")
                                        .foregroundColor(meshGold)
                                    Text(peer.displayName)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(textPrimary)
                                    Spacer()
                                    Button("Connect") {
                                        transport.invitePeer(peer)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(meshGold)
                                    .foregroundColor(.black)
                                    .font(.system(size: 11, weight: .bold))
                                }
                                .padding(10)
                                .background(Color.white.opacity(0.04))
                                .cornerRadius(8)
                            }
                        }
                    }
                }
                .padding(14)
                .background(cardBg)
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(cardBorder, lineWidth: 1))
            }
            .padding(16)
        }
    }

    // MARK: - Right Inbox Panel

    private var rightInboxPanel: some View {
        VStack(spacing: 0) {
            // Inbox Title Row
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .foregroundColor(meshGold)
                    Text("Received Packets Inbox")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(textPrimary)
                }

                Spacer()

                HStack(spacing: 4) {
                    Circle().fill(amberNotSettled).frame(width: 6, height: 6)
                    Text("\(receivedPackets.count) RECEIVED")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(amberNotSettled)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(amberNotSettled.opacity(0.18)))

                if !receivedPackets.isEmpty {
                    Button("Clear") {
                        try? MacReceivedPacketStore.shared.clear()
                        reloadPackets()
                    }
                    .buttonStyle(.bordered)
                    .font(.system(size: 10))
                }
            }
            .padding(14)
            .background(Color.black.opacity(0.2))
            .overlay(Rectangle().frame(height: 1).foregroundColor(cardBorder), alignment: .bottom)

            // Inbox Content
            if receivedPackets.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 36))
                        .foregroundColor(textMuted)
                    Text("No received offline packets on Mac")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(textSecondary)
                    Text("When you tap 'Send Packet to [MacBook]' on your iPhone, the cryptographically signed packet will arrive here over direct Multipeer transport.")
                        .font(.system(size: 12))
                        .foregroundColor(textMuted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(20)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(receivedPackets) { record in
                            macPacketCard(record)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private func macPacketCard(_ record: MacReceivedPacketRecord) -> some View {
        let packet = record.packet
        return VStack(alignment: .leading, spacing: 10) {
            // Header Row: Amount + Prominent Status
            HStack {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("₹\(String(format: "%.2f", packet.amountDouble))")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundColor(textPrimary)

                    Text("from \(packet.fromAccount.uppercased()) → \(packet.toAccount.uppercased())")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(meshGold)
                }

                Spacer()

                // PROMINENT REQUIRED STATUS BADGE
                switch record.reconciliationStatus {
                case .received, .pendingReconciliation:
                    HStack(spacing: 5) {
                        Circle().fill(amberNotSettled).frame(width: 6, height: 6)
                        Text(record.reconciliationStatus == .pendingReconciliation ? "PENDING RECONCILIATION — NOT SETTLED" : "RECEIVED — NOT SETTLED")
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(amberNotSettled)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(amberNotSettled.opacity(0.2)))
                    .overlay(Capsule().stroke(amberNotSettled.opacity(0.4), lineWidth: 1))

                case .settling:
                    HStack(spacing: 5) {
                        ProgressView().scaleEffect(0.6).tint(.cyan)
                        Text("SETTLING...")
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(.cyan)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.cyan.opacity(0.2)))
                    .overlay(Capsule().stroke(Color.cyan.opacity(0.4), lineWidth: 1))

                case .settled:
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.system(size: 10))
                        Text("SETTLED ON LEDGER")
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.green.opacity(0.2)))
                    .overlay(Capsule().stroke(Color.green.opacity(0.4), lineWidth: 1))

                case .failed:
                    HStack(spacing: 5) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.red).font(.system(size: 10))
                        Text("SETTLEMENT REJECTED")
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(.red)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.red.opacity(0.2)))
                    .overlay(Capsule().stroke(Color.red.opacity(0.4), lineWidth: 1))
                }
            }

            Divider().background(cardBorder)

            // Allowance Badge if allowance-backed
            if let spend = packet.allowanceSpend {
                HStack(spacing: 8) {
                    Image(systemName: "banknote.fill")
                        .foregroundColor(meshGold)
                        .font(.system(size: 12))
                    Text("ALLOWANCE-BACKED SPEND")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(meshGold)
                    Text("·")
                        .foregroundColor(textMuted)
                    Text("Seq #\(spend.sequenceNumber)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(textSecondary)
                    Text("·")
                        .foregroundColor(textMuted)
                    Text("Cumulative: ₹\(String(format: "%.2f", spend.cumulativeSpentDouble))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(textSecondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(meshGold.opacity(0.12)))

                Divider().background(cardBorder)
            }

            // Metadata Grid
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Text("Payment ID:")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(textMuted)
                    Text(packet.paymentId)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(textPrimary)
                }
                if let spend = packet.allowanceSpend {
                    GridRow {
                        Text("Allowance ID:")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(textMuted)
                        Text(spend.allowanceId)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(textSecondary)
                    }
                }
                GridRow {
                    Text("Created At:")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(textMuted)
                    Text(packet.createdAt.isoString)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(textSecondary)
                }
                GridRow {
                    Text("Signer Device ID:")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(textMuted)
                    Text(packet.deviceId)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(textSecondary)
                }
                GridRow {
                    Text("Received From:")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(textMuted)
                    Text("\(record.receivedFromPeer) at \(record.receivedAt.isoString)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(textSecondary)
                }
            }

            if let reason = record.failureReason {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red).font(.system(size: 11))
                    Text("Rejection Reason: \(reason)")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(0.12)))
            }

            Divider().background(cardBorder)

            // Cryptographic Verification & Trust Notice
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: record.isSignatureMathematicallyValid ? "checkmark.seal.fill" : "xmark.seal.fill")
                            .foregroundColor(record.isSignatureMathematicallyValid ? Color.green : Color.red)
                            .font(.system(size: 12))

                        Text(record.isSignatureMathematicallyValid ? "RSASSA-PSS SHA-256: Mathematically Valid ✓" : "Signature Verification Failed")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(record.isSignatureMathematicallyValid ? Color.green : Color.red)

                        Text("·")
                            .foregroundColor(textMuted)

                        Text("Sender Identity: UNVERIFIED OFFLINE")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(amberNotSettled)
                    }

                    Text("Trust Note: Mathematical verification confirms genuine private-key signing. Bank account authorization and balance settlement require backend bridge settlement.")
                        .font(.system(size: 10))
                        .foregroundColor(textMuted)
                }

                Spacer()

                // Bridge Reconcile Button
                if record.reconciliationStatus != .settled {
                    Button {
                        Task {
                            _ = await MacBridgeClient.shared.reconcilePacket(record: record)
                            reloadPackets()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Settle on Bridge")
                        }
                        .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(meshGold)
                    .foregroundColor(.black)
                }
            }
        }
        .padding(14)
        .background(cardBg)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(cardBorder, lineWidth: 1))
    }

    // MARK: - Bottom Status Bar

    private var statusBar: some View {
        HStack {
            if let err = transport.errorMessage {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                Text(err).font(.system(size: 11)).foregroundColor(.red)
            } else if let send = transport.sendStatus {
                Image(systemName: "paperplane.fill").foregroundColor(meshGold)
                Text(send).font(.system(size: 11)).foregroundColor(textPrimary)
            } else if let msg = transport.statusMessage {
                Image(systemName: "info.circle.fill").foregroundColor(meshGold)
                Text(msg).font(.system(size: 11)).foregroundColor(textSecondary)
            } else {
                Text("Ready").font(.system(size: 11)).foregroundColor(textMuted)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.6))
        .overlay(Rectangle().frame(height: 1).foregroundColor(cardBorder), alignment: .top)
    }

    // MARK: - Bridge & Device Authorization Card

    private var bridgeRegistrationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("MAC IDENTITY & BACKEND BRIDGE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(textMuted)
                Spacer()
                Text("REST / HTTP")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(meshGold.opacity(0.8))
            }

            // Identity Metadata
            if let id = macIdentity {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top) {
                        Text("Device ID:")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(textMuted)
                            .frame(width: 72, alignment: .leading)
                        Text(id.deviceId)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(textPrimary)
                    }

                    HStack(alignment: .top) {
                        Text("Key Spec:")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(textMuted)
                            .frame(width: 72, alignment: .leading)
                        Text("\(id.algorithm) · \(id.keyType)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(textSecondary)
                    }

                    HStack(alignment: .top) {
                        Text("Fingerprint:")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(textMuted)
                            .frame(width: 72, alignment: .leading)
                        Text(id.publicKeyFingerprint)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(textSecondary)
                            .lineLimit(2)
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.03))
                .cornerRadius(6)
            }

            Divider().background(cardBorder)

            // Step 1: Public Key Registration
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("1. PUBLIC KEY REGISTRATION")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(textMuted)
                    Spacer()
                    keyStatusBadge
                }

                Text("Registers this Mac's public verification key with POST /api/keys/register. Does not transmit private key.")
                    .font(.system(size: 10))
                    .foregroundColor(textMuted)

                Button {
                    registerMacPublicKey()
                } label: {
                    HStack(spacing: 6) {
                        if isRegistering {
                            ProgressView()
                                .controlSize(.small)
                            Text("Registering Key...")
                        } else {
                            Image(systemName: "key.fill")
                            Text("Register Mac Public Key")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(meshGold)
                .foregroundColor(.black)
                .font(.system(size: 11, weight: .bold))
                .disabled(isRegistering || macIdentity == nil)

                if let success = bridgeSuccessMessage {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 10))
                        Text(success)
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                    }
                }

                if let err = bridgeErrorMessage {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 10))
                        Text(err)
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                    }
                }
            }

            Divider().background(cardBorder)

            // Step 2: Account Authorization Status (Security Diagnostics)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("2. CAROL ACCOUNT AUTHORIZATION")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(textMuted)
                    Spacer()
                    HStack(spacing: 4) {
                        Circle().fill(Color.orange).frame(width: 5, height: 5)
                        Text("BLOCKED — UNAUTHENTICATED")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color.orange)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.15)))
                }

                Text("Security Boundary Note: Public key registration confirms the Mac holds a genuine RSA keypair, but does NOT grant debit authority over bank account 'carol'. Prototype endpoint /api/devices/authorize currently lacks account-owner proof (OTP/signature). In accordance with Stage 6.4B.6 security policy, Carol debit authorization is explicitly blocked.")
                    .font(.system(size: 10))
                    .foregroundColor(textMuted)
            }
        }
        .padding(14)
        .background(cardBg)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(cardBorder, lineWidth: 1))
    }

    private var keyStatusBadge: some View {
        HStack(spacing: 4) {
            switch bridgeRegistrationState {
            case .unregistered:
                Circle().fill(Color.gray).frame(width: 5, height: 5)
                Text("UNREGISTERED")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color.gray)
            case .registering:
                Circle().fill(meshGold).frame(width: 5, height: 5)
                Text("REGISTERING")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(meshGold)
            case .registered(let isNew):
                Circle().fill(Color.green).frame(width: 5, height: 5)
                Text(isNew ? "REGISTERED (NEW)" : "REGISTERED (IDEMPOTENT)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color.green)
            case .failed:
                Circle().fill(Color.red).frame(width: 5, height: 5)
                Text("FAILED")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color.red)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    private func registerMacPublicKey() {
        guard let identity = macIdentity else {
            self.bridgeErrorMessage = "Mac identity not loaded"
            return
        }
        guard !isRegistering else { return }

        isRegistering = true
        bridgeErrorMessage = nil
        bridgeSuccessMessage = nil
        bridgeRegistrationState = .registering

        Task { @MainActor in
            do {
                let response = try await MacBridgeClient.shared.registerIdentity(identity)
                self.isRegistering = false
                self.bridgeRegistrationState = .registered(isNew: response.isNewlyRegistered)
                self.bridgeSuccessMessage = response.message
            } catch {
                self.isRegistering = false
                let desc = error.localizedDescription
                self.bridgeRegistrationState = .failed(desc)
                self.bridgeErrorMessage = desc
            }
        }
    }

    private func reloadPackets() {
        self.receivedPackets = MacReceivedPacketStore.shared.getAll()
    }

    private func reloadIdentity() {
        self.macIdentity = try? MacDeviceIdentityManager.shared.getOrCreateIdentity()
    }

    // MARK: - Demo Mode Station Panel (Judge-Ready Presentation)

    private var demoStationPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Top Demo Header & Quick Controls
                demoTopHeaderBar

                // 1. Guided Scenario Selector (5 Scenarios)
                guidedScenariosCard

                // 2. Live Telemetry Matrix & Strategy Allocations
                liveTelemetryMatrixCard

                // 3. Presentation Timeline Event Log
                presentationTimelineCard

                // 4. Judge-Facing Explanation
                judgeExplanationCard
            }
            .padding(16)
        }
        .background(Color(red: 0.06, green: 0.07, blue: 0.09))
    }

    // MARK: - Demo Top Header Bar

    private var demoTopHeaderBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Image(systemName: "gauge.with.needle.fill")
                        .foregroundColor(Color.cyan)
                    Text("RESEARCH STATION — DEMO MODE")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(textPrimary)

                    Text("HACKATHON JUDGE STATION")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(Color.cyan)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.cyan.opacity(0.15)))
                }

                Text("Simulates changing cellular conditions and streams predictive offline reserves to iPhone via Bluetooth/AWDL.")
                    .font(.system(size: 11))
                    .foregroundColor(textSecondary)
            }

            Spacer()

            // Quick Actions: Shock & Reset
            HStack(spacing: 8) {
                Button {
                    Task {
                        await bridgeClient.injectGridShock()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                        Text("Inject Grid Shock")
                    }
                    .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.red.opacity(0.85))

                Button {
                    Task {
                        await bridgeClient.resetDemo()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset Demo")
                    }
                    .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.bordered)
                .tint(Color.cyan)
            }
        }
        .padding(12)
        .background(cardBg)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardBorder, lineWidth: 1))
    }

    // MARK: - Active Prediction Helper

    private var activePredictionMessage: PeerPredictionMessage? {
        bridgeClient.activePredictionDisplay ?? bridgeClient.lastTransmittedMessage
    }

    // MARK: - 1. Guided Scenario Selector (5 Scenarios)

    private var guidedScenariosCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Error banner if bridge connection failed
            if let err = bridgeClient.lastFetchError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Color.red)
                    Text(err)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.red)
                    Spacer()
                }
                .padding(8)
                .background(Color.red.opacity(0.15))
                .cornerRadius(6)
            }

            HStack {
                Text("GUIDED DEMONSTRATION SCENARIOS (5 PHASES)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(textMuted)
                    .tracking(0.8)

                Spacer()

                HStack(spacing: 6) {
                    Text("Wallet:")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(textSecondary)
                    Text("₹\(Int(bridgeClient.customWalletBalance))")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Color.yellow)

                    Button("₹122 Test") {
                        Task {
                            await bridgeClient.updateWalletBalance(122.0)
                        }
                    }
                    .font(.system(size: 9, weight: .bold))
                    .buttonStyle(.bordered)
                    .tint(bridgeClient.customWalletBalance == 122.0 ? Color.yellow : Color.gray)

                    Button("₹5,000 Base") {
                        Task {
                            await bridgeClient.updateWalletBalance(5000.0)
                        }
                    }
                    .font(.system(size: 9, weight: .bold))
                    .buttonStyle(.bordered)
                    .tint(bridgeClient.customWalletBalance == 5000.0 ? Color.cyan : Color.gray)
                }
            }

            // 5 Scenario Cards Grid
            HStack(spacing: 8) {
                scenarioButton(
                    id: 1,
                    title: "1. Normal 5G",
                    subtitle: "Dense Urban",
                    risk: "6% Risk · 0.35h",
                    reserve: "₹57",
                    tint: Color.green
                )

                scenarioButton(
                    id: 2,
                    title: "2. Deteriorating",
                    subtitle: "Transit Corridor",
                    risk: "45% Risk · 1.25h",
                    reserve: "₹105",
                    tint: Color.yellow
                )

                scenarioButton(
                    id: 3,
                    title: "3. Grid Shock",
                    subtitle: "Tunnel Blackout",
                    risk: "88% Risk · 4.5h",
                    reserve: "₹268",
                    tint: Color.red
                )

                scenarioButton(
                    id: 4,
                    title: "4. Fully Offline",
                    subtitle: "0 Internet P2P",
                    risk: "95% Risk · 5.0h",
                    reserve: "₹286",
                    tint: Color.purple
                )

                scenarioButton(
                    id: 5,
                    title: "5. Recovery",
                    subtitle: "Restored to 5G",
                    risk: "5% Risk · 0.30h",
                    reserve: "₹53",
                    tint: Color.cyan
                )
            }
        }
        .padding(12)
        .background(cardBg)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardBorder, lineWidth: 1))
    }

    private func scenarioButton(id: Int, title: String, subtitle: String, risk: String, reserve: String, tint: Color) -> some View {
        let isActive = bridgeClient.activeScenarioId == id
        return Button {
            Task {
                await bridgeClient.triggerScenario(id)
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(isActive ? tint : textPrimary)
                    Spacer()
                    if isActive {
                        Circle().fill(tint).frame(width: 5, height: 5)
                    }
                }

                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundColor(textSecondary)

                Spacer(minLength: 2)

                Text(risk)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(textMuted)

                HStack {
                    Text("Reserve:")
                        .font(.system(size: 8))
                        .foregroundColor(textMuted)
                    Text(reserve)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(isActive ? tint : textPrimary)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
            .background(isActive ? tint.opacity(0.12) : Color.white.opacity(0.02))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isActive ? tint : Color.white.opacity(0.06), lineWidth: isActive ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 2. Live Telemetry Matrix & Strategy Allocations

    private var liveTelemetryMatrixCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ACTIVE PREDICTIVE ALLOCATION & RISK TELEMETRY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(textMuted)
                    .tracking(0.8)

                Spacer()

                if let msg = activePredictionMessage {
                    HStack(spacing: 4) {
                        Circle().fill(bridgeClient.lastTransmittedMessage != nil ? Color.green : Color.orange).frame(width: 5, height: 5)
                        Text(bridgeClient.lastTransmittedMessage != nil ? "Seq #\(msg.sequenceNumber) · Broadcast at \(bridgeClient.lastTransmittedAt ?? Date(), style: .time)" : "Active Prediction · Awaiting iPhone Sync")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(textMuted)
                    }
                }
            }

            if let msg = activePredictionMessage {
                VStack(spacing: 8) {
                    // Hero Row: Recommended Reserve M2 vs Baseline
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("RECOMMENDED OFFLINE RESERVE (UNCERTAINTY-AWARE M2)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(Color.cyan)

                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("₹\(Int(msg.recommendedReserveInr))")
                                    .font(.system(size: 26, weight: .bold, design: .rounded))
                                    .foregroundColor(Color.green)

                                HStack(spacing: 3) {
                                    if msg.deltaReserveInr > 0 {
                                        Image(systemName: "arrow.up.right")
                                        Text("+₹\(Int(msg.deltaReserveInr))")
                                    } else if msg.deltaReserveInr < 0 {
                                        Image(systemName: "arrow.down.right")
                                        Text("-₹\(Int(abs(msg.deltaReserveInr)))")
                                    } else {
                                        Text("Baseline")
                                    }
                                }
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(msg.deltaReserveInr > 0 ? Color.orange : (msg.deltaReserveInr < 0 ? Color.cyan : textMuted))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.white.opacity(0.06)))
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("PREVIOUS RESERVE")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(textMuted)
                            Text("₹\(Int(msg.previousReserveInr))")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(textSecondary)
                        }
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.02))
                    .cornerRadius(6)

                    // Wallet Balance & Funding Status Row
                    HStack(spacing: 6) {
                        if msg.fundingShortfallInr > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color.red)
                                Text("WALLET SHORTFALL: ₹\(Int(msg.fundingShortfallInr))")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(Color.red)
                                Text("(Available: ₹\(Int(msg.availableBalanceInr)) · Unfunded: ₹\(Int(msg.fundingShortfallInr)))")
                                    .font(.system(size: 9))
                                    .foregroundColor(textMuted)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.12))
                            .cornerRadius(4)
                        } else if msg.availableBalanceInr > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color.green)
                                Text("FULLY FUNDED")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(Color.green)
                                Text("(₹\(Int(msg.remainingLiquidInr)) liquid balance retained · Wallet: ₹\(Int(msg.availableBalanceInr)))")
                                    .font(.system(size: 9))
                                    .foregroundColor(textMuted)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.12))
                            .cornerRadius(4)
                        }
                        Spacer()
                    }

                    // 4 Telemetry Metrics
                    HStack(spacing: 8) {
                        metricBox(
                            title: "OUTAGE PROBABILITY",
                            value: "\(Int(msg.robustOutageProbability * 100))%",
                            sub: "Point: \(Int(msg.outageProbability * 100))% · \(msg.signalDbm) dBm",
                            tint: msg.robustOutageProbability >= 0.70 ? Color.red : (msg.robustOutageProbability >= 0.30 ? Color.orange : Color.green)
                        )

                        metricBox(
                            title: "PREDICTED DURATION",
                            value: String(format: "%.1fh", msg.predictedDurationHours),
                            sub: String(format: "±%.1fh duration variance", msg.durationStdHours),
                            tint: Color.cyan
                        )

                        metricBox(
                            title: "PREDICTED DEMAND",
                            value: "₹\(Int(msg.predictedDemandInr))",
                            sub: "σ = ₹\(Int(msg.compoundDemandStdInr)) compound",
                            tint: Color.blue
                        )

                        metricBox(
                            title: "UNCERTAINTY MARGIN",
                            value: "+₹\(Int(msg.uncertaintyMarginInr))",
                            sub: "Floor: ₹\(Int(msg.safetyFloorInr)) · Conf: \(Int(msg.confidenceLevel * 100))%",
                            tint: Color.yellow
                        )
                    }

                    // Strategy Benchmark Allocations Strip
                    HStack(spacing: 8) {
                        Text("STRATEGIES:")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(textMuted)

                        strategyBadge("Fixed ₹500", amount: msg.strategySnapshot.fixedAllowanceInr, isActive: false)
                        strategyBadge("Demand-Only", amount: msg.strategySnapshot.demandOnlyInr, isActive: false)
                        strategyBadge("Proposed M1", amount: msg.strategySnapshot.proposedM1Inr, isActive: false)
                        strategyBadge("Uncertainty M2", amount: msg.strategySnapshot.uncertaintyM2Inr, isActive: true)

                        Spacer()
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.2))
                    .cornerRadius(4)

                    // Narrative explanation
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "quote.opening")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color.cyan)
                        Text(msg.recommendationNarrative)
                            .font(.system(size: 10))
                            .foregroundColor(textSecondary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.02))
                    .cornerRadius(6)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Connecting to local Python simulator on 127.0.0.1:8050 to pull initial telemetry...")
                        .font(.system(size: 11))
                        .foregroundColor(textMuted)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.02))
                .cornerRadius(6)
            }
        }
        .padding(12)
        .background(cardBg)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardBorder, lineWidth: 1))
    }

    private func metricBox(title: String, value: String, sub: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(textMuted)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(tint)
            Text(sub)
                .font(.system(size: 8))
                .foregroundColor(textSecondary)
                .lineLimit(1)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.02))
        .cornerRadius(6)
    }

    private func strategyBadge(_ name: String, amount: Double, isActive: Bool) -> some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.system(size: 8, weight: isActive ? .bold : .medium))
                .foregroundColor(isActive ? Color.green : textMuted)
            Text("₹\(Int(amount))")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(isActive ? Color.green : textSecondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(isActive ? Color.green.opacity(0.15) : Color.white.opacity(0.04)))
    }

    // MARK: - 3. Presentation Timeline Event Log

    private var presentationTimelineCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.indent")
                        .foregroundColor(Color.cyan)
                    Text("PRESENTATION TIMELINE (REAL-TIME AUDIT LOG)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(textMuted)
                        .tracking(0.8)
                }

                Spacer()

                if let ack = bridgeClient.lastAckReceived {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(Color.green)
                            .font(.system(size: 10))
                        Text("Confirmed Receipt: Seq #\(ack.sequenceNumber)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color.green)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.green.opacity(0.12)))
                }
            }

            if bridgeClient.timelineEvents.isEmpty {
                VStack(spacing: 4) {
                    Text("No scenario events recorded yet.")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(textSecondary)
                    Text("Trigger any of the 5 scenarios above or tap 'Inject Grid Shock' to generate verified presentation timeline events.")
                        .font(.system(size: 10))
                        .foregroundColor(textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.white.opacity(0.01))
                .cornerRadius(6)
            } else {
                VStack(spacing: 6) {
                    ForEach(bridgeClient.timelineEvents) { item in
                        timelineRow(item)
                    }
                }
            }
        }
        .padding(12)
        .background(cardBg)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardBorder, lineWidth: 1))
    }

    private func timelineRow(_ item: DemoTimelineItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp
            Text(item.timestamp, style: .time)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(textMuted)
                .frame(width: 58, alignment: .leading)

            // Category badge
            Text(item.type.rawValue)
                .font(.system(size: 8, weight: .black))
                .foregroundColor(badgeColor(for: item.type))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(badgeColor(for: item.type).opacity(0.15)))
                .frame(width: 82, alignment: .leading)

            // Content
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(textPrimary)

                    if item.type == .acknowledged {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color.green)
                            .font(.system(size: 9))
                    }
                }

                Text(item.details)
                    .font(.system(size: 9))
                    .foregroundColor(textSecondary)
            }

            Spacer()
        }
        .padding(6)
        .background(Color.white.opacity(0.02))
        .cornerRadius(4)
    }

    private func badgeColor(for type: DemoTimelineItem.EventType) -> Color {
        switch type {
        case .scenarioStarted: return Color.cyan
        case .conditionChanged: return Color.yellow
        case .shockInjected: return Color.red
        case .recalculated: return Color.blue
        case .sent: return Color.purple
        case .acknowledged: return Color.green
        case .restored: return Color.mint
        }
    }

    // MARK: - 4. Judge-Facing Explanation

    private var judgeExplanationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(Color.yellow)
                    .font(.system(size: 11))
                Text("WHAT MAKES THIS DEMONSTRATION INTERESTING?")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(textMuted)
                    .tracking(0.8)
            }

            VStack(alignment: .leading, spacing: 6) {
                bulletPoint(
                    number: "1",
                    title: "Advance Capital Preparation",
                    desc: "Offline payment systems must lock reserves BEFORE connectivity drops. Once disconnected, no bank or server can approve an increase."
                )

                bulletPoint(
                    number: "2",
                    title: "Opportunity Cost of Fixed Reserves",
                    desc: "A static reserve (e.g., ₹500) unnecessarily locks liquid funds during reliable 5G coverage, while risking failure during prolonged transit outages."
                )

                bulletPoint(
                    number: "3",
                    title: "Joint Risk & Demand Modeling",
                    desc: "Predictive provisioning estimates disruption probability, predicted outage duration, and expected payment demand simultaneously."
                )

                bulletPoint(
                    number: "4",
                    title: "Uncertainty-Aware Safety Margin",
                    desc: "When predictions have high variance or during grid shocks, the model compounds duration uncertainty and activates an emergency safety floor."
                )

                bulletPoint(
                    number: "5",
                    title: "Zero-Internet Delivery Over P2P Transport",
                    desc: "Advisories reach the user's iPhone over direct Apple AWDL/BLE peer transport. The iPhone requires zero Wi-Fi router or cellular data."
                )
            }

            Divider().background(cardBorder)

            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.system(size: 9))
                    .foregroundColor(textMuted)
                Text("Research Prototype with Simulated Telemetry. Production payment settlement, cryptographic verification, and local enclaves remain strictly isolated.")
                    .font(.system(size: 9))
                    .foregroundColor(textMuted)
            }
        }
        .padding(12)
        .background(cardBg)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardBorder, lineWidth: 1))
    }

    private func bulletPoint(number: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(number)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(Color.cyan)
                .frame(width: 12, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(textPrimary)
                Text(desc)
                    .font(.system(size: 9))
                    .foregroundColor(textSecondary)
            }
        }
    }

    // MARK: - Predictive Provisioning Research Bridge Card (Left Panel)

    private var predictiveResearchBridgeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundColor(Color.cyan)
                    Text("RESEARCH STATION BRIDGE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(textMuted)
                }
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(bridgeClient.isConnectedToSimulator ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(bridgeClient.isConnectedToSimulator ? "SIMULATOR ONLINE" : "SIMULATOR OFFLINE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(bridgeClient.isConnectedToSimulator ? Color.green : Color.orange)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(bridgeClient.isConnectedToSimulator ? Color.green.opacity(0.12) : Color.orange.opacity(0.12)))
            }

            Text("Connects local Python simulation engine (127.0.0.1:8050) to the iPhone via Bluetooth/AWDL Multipeer session.")
                .font(.system(size: 10))
                .foregroundColor(textMuted)

            Divider().background(cardBorder)

            // Controls
            HStack {
                Toggle(isOn: $bridgeClient.autoSyncEnabled) {
                    Text("Auto-Broadcast on Change")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(textPrimary)
                }
                .toggleStyle(.checkbox)

                Spacer()

                Button {
                    Task {
                        await bridgeClient.manualSyncNow()
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Sync")
                    }
                    .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.bordered)
                .tint(Color.cyan)
                .disabled(!bridgeClient.isConnectedToSimulator || transport.connectedPeer == nil)
            }

            // 5 Guided Scenarios Quick Trigger List
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("DEMO SCENARIOS (5 PHASES)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.cyan)
                    Spacer()
                    Text("TAP TO RUN")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(textMuted)
                }

                VStack(spacing: 4) {
                    leftScenarioRow(id: 1, name: "1. Normal 5G", reserve: "₹57", tint: .green)
                    leftScenarioRow(id: 2, name: "2. Deteriorating", reserve: "₹105", tint: .yellow)
                    leftScenarioRow(id: 3, name: "3. Grid Shock", reserve: "₹268", tint: .red)
                    leftScenarioRow(id: 4, name: "4. Fully Offline", reserve: "₹286", tint: .purple)
                    leftScenarioRow(id: 5, name: "5. Recovery", reserve: "₹53", tint: .cyan)
                }
            }
            .padding(6)
            .background(Color.black.opacity(0.2))
            .cornerRadius(6)

            // Quick Shock & Reset on Left Panel
            HStack(spacing: 6) {
                Button {
                    Task {
                        await bridgeClient.injectGridShock()
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill")
                        Text("Grid Shock")
                    }
                    .font(.system(size: 9, weight: .bold))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.red.opacity(0.85))

                Button {
                    Task {
                        await bridgeClient.resetDemo()
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset Demo")
                    }
                    .font(.system(size: 9, weight: .bold))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Color.cyan)
            }

            // Switch to full Demo Mode if in Packet Inbox
            if selectedCompanionTab != .demoMode {
                Button {
                    selectedCompanionTab = .demoMode
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gauge.with.needle.fill")
                        Text("Open Full Judge Demo Dashboard")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .tint(Color.cyan)
            }

            // Latest Broadcast Status
            if let msg = activePredictionMessage {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(bridgeClient.lastTransmittedMessage != nil ? "LAST BROADCAST (Seq #\(msg.sequenceNumber))" : "ACTIVE PREDICTION (LOCAL)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(Color.cyan)
                        Spacer()
                        if let sentAt = bridgeClient.lastTransmittedAt {
                            Text(sentAt, style: .time)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(textMuted)
                        }
                    }

                    HStack(spacing: 8) {
                        Text("₹\(Int(msg.recommendedReserveInr))")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(Color.green)

                        Text(msg.deltaReserveInr >= 0 ? "+₹\(Int(msg.deltaReserveInr))" : "-₹\(Int(abs(msg.deltaReserveInr)))")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(msg.deltaReserveInr > 0 ? Color.orange : (msg.deltaReserveInr < 0 ? Color.cyan : textMuted))

                        Spacer()

                        Text("\(Int(msg.robustOutageProbability * 100))% · \(String(format: "%.1f", msg.predictedDurationHours))h")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(msg.robustOutageProbability > 0.4 ? Color.red : Color.yellow)
                    }
                }
                .padding(8)
                .background(Color.white.opacity(0.03))
                .cornerRadius(6)
            }
        }
        .padding(12)
        .background(cardBg)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cyan.opacity(0.3), lineWidth: 1))
    }

    private func leftScenarioRow(id: Int, name: String, reserve: String, tint: Color) -> some View {
        let isActive = bridgeClient.activeScenarioId == id
        return Button {
            Task {
                await bridgeClient.triggerScenario(id)
            }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(isActive ? tint : textMuted).frame(width: 5, height: 5)
                Text(name)
                    .font(.system(size: 9, weight: isActive ? .bold : .medium))
                    .foregroundColor(isActive ? tint : textPrimary)
                Spacer()
                Text(reserve)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(isActive ? tint : textSecondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(isActive ? tint.opacity(0.15) : Color.white.opacity(0.02))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}
