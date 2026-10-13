import SwiftUI
import MultipeerConnectivity

/// Native macOS Companion Screen for Testing Offline Peer Packet Transport against iPhone.
public struct MacCompanionView: View {

    @ObservedObject private var transport = MacPeerTransportService.shared
    @State private var receivedPackets: [MacReceivedPacketRecord] = []
    @State private var macIdentity: MacDeviceIdentity? = nil

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

                            // Send Test Packet to iPhone button
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
            }

            Divider().background(cardBorder)

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

            Divider().background(cardBorder)

            // Cryptographic Verification & Trust Notice
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

    private func reloadPackets() {
        self.receivedPackets = MacReceivedPacketStore.shared.getAll()
    }

    private func reloadIdentity() {
        self.macIdentity = try? MacDeviceIdentityManager.shared.getOrCreateIdentity()
    }
}
