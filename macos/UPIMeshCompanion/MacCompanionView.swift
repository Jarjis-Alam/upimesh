import SwiftUI
import MultipeerConnectivity

/// Native macOS Companion Screen for Testing Offline Peer Packet Transport against iPhone.
public struct MacCompanionView: View {

    @ObservedObject private var transport = MacPeerTransportService.shared
    @State private var receivedPackets: [MacReceivedPacketRecord] = []
    @State private var macIdentity: MacDeviceIdentity? = nil

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
                    .frame(minWidth: 340, idealWidth: 380, maxWidth: 450)

                // Right Panel: Received Packets Inbox
                rightInboxPanel
                    .frame(minWidth: 450, idealWidth: 550)
            }

            // Bottom Alert / Status Bar
            statusBar
        }
        .background(bgDark)
        .onAppear {
            reloadIdentity()
            reloadPackets()
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
                case .received:
                    HStack(spacing: 5) {
                        Circle().fill(amberNotSettled).frame(width: 6, height: 6)
                        Text("RECEIVED — NOT SETTLED")
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
}
