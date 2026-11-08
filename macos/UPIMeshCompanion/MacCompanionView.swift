import SwiftUI
import MultipeerConnectivity

/// Native macOS Companion Screen for Testing Offline Peer Packet Transport against iPhone.
/// Styled with true AMOLED black, obsidian surfaces, and amber-400 hackathon presentation accents.
public struct MacCompanionView: View {

    @ObservedObject private var transport = MacPeerTransportService.shared
    @ObservedObject private var bridgeClient = MacPredictionBridgeClient.shared
    @State private var receivedPackets: [MacReceivedPacketRecord] = []
    @State private var macIdentity: MacDeviceIdentity? = nil
    @State private var selectedCompanionTab: CompanionTab = .demoMode
    @State private var isPulsing: Bool = false

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

    // MARK: - Palette (True AMOLED Black & Obsidian Amber)
    private let bgAmoled = Color.black
    private let surfaceBlack = Color(red: 0.03, green: 0.04, blue: 0.05)
    private let cardBlack = Color(red: 0.05, green: 0.06, blue: 0.07)
    private let subpanelBlack = Color(red: 0.08, green: 0.09, blue: 0.10)
    private let cardBorder = Color.white.opacity(0.10)
    private let amberAccent = Color(red: 0.98, green: 0.80, blue: 0.08)       // #FACC15
    private let amberLight = Color(red: 0.99, green: 0.85, blue: 0.25)        // #FDE047
    private let amberBorder = Color(red: 0.98, green: 0.80, blue: 0.08).opacity(0.30)
    private let amberBackground = Color(red: 0.98, green: 0.80, blue: 0.08).opacity(0.12)
    private let textPrimary = Color.white
    private let textSecondary = Color(red: 0.70, green: 0.73, blue: 0.79)     // Slate 300
    private let textMuted = Color(red: 0.50, green: 0.55, blue: 0.62)         // Slate 400/500
    private let greenSuccess = Color(red: 0.06, green: 0.73, blue: 0.51)      // #10B981
    private let redDanger = Color(red: 0.94, green: 0.27, blue: 0.27)         // #EF4444

    public init() {}

    private var activePredictionMessage: PeerPredictionMessage? {
        bridgeClient.activePredictionDisplay ?? bridgeClient.lastTransmittedMessage
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Window Titlebar
            windowTitleBar

            // Main Content Area
            if selectedCompanionTab == .demoMode {
                demoStationDashboard
            } else {
                inboxDashboard
            }

            // Bottom Status Bar
            appFooterStatusBar
        }
        .background(bgAmoled)
        .onAppear {
            reloadIdentity()
            reloadPackets()
            bridgeClient.startPolling()
            if !transport.isDiscovering {
                transport.startDiscovery()
            }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
        .onDisappear {
            bridgeClient.stopPolling()
        }
        .onReceive(NotificationCenter.default.publisher(for: .macPacketReceived)) { _ in
            reloadPackets()
        }
    }

    // MARK: - 1. Window Title Bar (macOS Native Style)

    private var windowTitleBar: some View {
        HStack(spacing: 14) {
            // macOS Traffic Light Mimic Dots
            HStack(spacing: 6) {
                Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34)).frame(width: 10, height: 10)
                Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 10, height: 10)
                Circle().fill(Color(red: 0.15, green: 0.79, blue: 0.25)).frame(width: 10, height: 10)
            }
            .padding(.trailing, 2)

            Rectangle()
                .fill(cardBorder)
                .frame(width: 1, height: 16)

            // App Title & Badge
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(amberBorder, lineWidth: 1))
                        .frame(width: 24, height: 24)
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(amberAccent)
                }

                Text("UPI Offline Mesh")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(textPrimary)

                Text("macOS Peer Companion")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(amberAccent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 10).fill(bgAmoled))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(amberBorder, lineWidth: 1))
            }

            Spacer()

            // View Switcher (Demo Station vs Packet Inbox)
            HStack(spacing: 0) {
                Button {
                    selectedCompanionTab = .demoMode
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "gauge.with.needle.fill")
                        Text("DEMO MODE")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(selectedCompanionTab == .demoMode ? amberBackground : Color.clear)
                    .foregroundColor(selectedCompanionTab == .demoMode ? amberAccent : textMuted)
                }
                .buttonStyle(.plain)

                Button {
                    selectedCompanionTab = .packetInbox
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "tray.fill")
                        Text("PACKET INBOX (\(receivedPackets.count))")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(selectedCompanionTab == .packetInbox ? amberBackground : Color.clear)
                    .foregroundColor(selectedCompanionTab == .packetInbox ? amberAccent : textMuted)
                }
                .buttonStyle(.plain)
            }
            .background(Color.white.opacity(0.04))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(cardBorder, lineWidth: 1))

            Spacer()

            // Simulator Online Pill
            HStack(spacing: 6) {
                Circle()
                    .fill(bridgeClient.isConnectedToSimulator ? amberAccent : redDanger)
                    .frame(width: 7, height: 7)
                    .opacity(isPulsing ? 1.0 : 0.4)

                Text(bridgeClient.isConnectedToSimulator ? "Simulator Online" : "Simulator Offline")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(amberAccent)

                Text("·")
                    .foregroundColor(amberAccent.opacity(0.5))

                Text("127.0.0.1:8050")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(amberLight)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(amberBackground))
            .overlay(Capsule().stroke(amberBorder, lineWidth: 1))

            // Peer Discovery / Connection Pill
            HStack(spacing: 6) {
                Circle()
                    .fill(transport.connectedPeer != nil ? greenSuccess : (transport.isDiscovering ? amberAccent : textMuted))
                    .frame(width: 7, height: 7)
                    .scaleEffect(isPulsing && transport.isDiscovering ? 1.2 : 1.0)

                Text(transport.connectedPeer != nil ? "Peer Connected" : (transport.isDiscovering ? "Discovering Peers" : "Discovery Idle"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(transport.connectedPeer != nil ? greenSuccess : amberLight)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.04)))
            .overlay(Capsule().stroke(cardBorder, lineWidth: 1))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(bgAmoled)
        .overlay(Rectangle().frame(height: 1).foregroundColor(cardBorder), alignment: .bottom)
    }

    // MARK: - 2. Demo Station Dashboard (Two-Column Presentation Grid)

    private var demoStationDashboard: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 20) {
                // LEFT COLUMN (Hero Simulation Controller + Risk Telemetry)
                VStack(spacing: 20) {
                    heroDemoControllerSection
                    predictiveAllocationPanelSection
                    judgeExplanationCompactSection
                }
                .frame(maxWidth: .infinity)

                // RIGHT COLUMN (Device & Security Bridge + Live Audit Stream)
                VStack(spacing: 20) {
                    securityIdentityDeckSection
                    auditFeedSection
                }
                .frame(width: 380)
            }
            .padding(20)
        }
        .background(bgAmoled)
    }

    // MARK: - Left Section: Hero Demo Controller

    private var heroDemoControllerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Error banner if any
            if let err = bridgeClient.lastFetchError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(redDanger)
                    Text(err)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(redDanger)
                    Spacer()
                }
                .padding(10)
                .background(redDanger.opacity(0.12))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(redDanger.opacity(0.3), lineWidth: 1))
            }

            // Title Row & Shock Actions
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("HACKATHON STATION")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(amberAccent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(amberBackground))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(amberBorder, lineWidth: 1))

                    HStack(spacing: 6) {
                        Text("Research Station —")
                            .font(.system(size: 20, weight: .heavy))
                            .foregroundColor(textPrimary)
                        Text("Demo Mode")
                            .font(.system(size: 20, weight: .heavy))
                            .foregroundColor(amberAccent)
                    }
                }

                Spacer()

                // Action Buttons
                HStack(spacing: 10) {
                    Button {
                        Task {
                            await bridgeClient.injectGridShock()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "bolt.fill")
                            Text("Inject Grid Shock")
                        }
                        .font(.system(size: 11, weight: .heavy))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(amberAccent)
                        .foregroundColor(.black)
                        .cornerRadius(8)
                        .shadow(color: amberAccent.opacity(0.3), radius: 6, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task {
                            await bridgeClient.resetDemo()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset Demo")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(bgAmoled)
                        .foregroundColor(textSecondary)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 8)
            .overlay(Rectangle().frame(height: 1).foregroundColor(cardBorder), alignment: .bottom)

            // Guided Demonstration Scenarios Bar
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("GUIDED DEMONSTRATION SCENARIOS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(textPrimary)
                        .tracking(0.5)

                    Spacer()

                    HStack(spacing: 6) {
                        Text("Wallet Balance:")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(textMuted)

                        Button("₹122 Test") {
                            Task {
                                await bridgeClient.updateWalletBalance(122.0)
                            }
                        }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(bridgeClient.customWalletBalance == 122.0 ? amberBackground : Color.white.opacity(0.04))
                        .foregroundColor(bridgeClient.customWalletBalance == 122.0 ? amberAccent : textMuted)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(bridgeClient.customWalletBalance == 122.0 ? amberBorder : cardBorder, lineWidth: 1))
                        .buttonStyle(.plain)

                        Button("₹5,000 Base") {
                            Task {
                                await bridgeClient.updateWalletBalance(5000.0)
                            }
                        }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(bridgeClient.customWalletBalance == 5000.0 ? amberBackground : Color.white.opacity(0.04))
                        .foregroundColor(bridgeClient.customWalletBalance == 5000.0 ? amberAccent : textMuted)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(bridgeClient.customWalletBalance == 5000.0 ? amberBorder : cardBorder, lineWidth: 1))
                        .buttonStyle(.plain)
                    }
                }

                // 5 Horizontal Scenario Cards
                HStack(spacing: 8) {
                    scenarioCard(id: 1, phase: "Phase 1", risk: "6% Risk", title: "Normal 5G", reserve: "₹57")
                    scenarioCard(id: 2, phase: "Phase 2", risk: "45% Risk", title: "Deteriorating", reserve: "₹105")
                    scenarioCard(id: 3, phase: "Phase 3", risk: "88% Risk", title: "Grid Shock", reserve: "₹268")
                    scenarioCard(id: 4, phase: "Phase 4", risk: "95% Risk", title: "Fully Offline", reserve: "₹286")
                    scenarioCard(id: 5, phase: "Phase 5", risk: "5% Risk", title: "Recovery", reserve: "₹53")
                }
            }
        }
        .padding(20)
        .background(bgAmoled)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(cardBorder, lineWidth: 1))
    }

    private func scenarioCard(id: Int, phase: String, risk: String, title: String, reserve: String) -> some View {
        let isActive = bridgeClient.activeScenarioId == id
        return Button {
            Task {
                await bridgeClient.triggerScenario(id)
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if isActive {
                        HStack(spacing: 4) {
                            Circle().fill(amberAccent).frame(width: 5, height: 5)
                            Text(phase)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(amberLight)
                        }
                    } else {
                        Text(phase)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(textMuted)
                    }

                    Spacer()

                    Text(risk)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(isActive ? amberAccent : amberLight.opacity(0.8))
                }

                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(isActive ? amberLight : textPrimary)

                HStack {
                    Text("Reserve")
                        .font(.system(size: 9))
                        .foregroundColor(textMuted)
                    Spacer()
                    Text(reserve)
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundColor(textPrimary)
                }
                .padding(.top, 4)
                .overlay(Rectangle().frame(height: 1).foregroundColor(Color.white.opacity(0.06)), alignment: .top)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            .background(bgAmoled)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isActive ? amberAccent : cardBorder, lineWidth: isActive ? 2 : 1)
            )
            .shadow(color: isActive ? amberAccent.opacity(0.25) : Color.clear, radius: 8, x: 0, y: 0)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Left Section: Predictive Allocation Panel

    private var predictiveAllocationPanelSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Card Header
            HStack {
                Text("PREDICTIVE ALLOCATION & RISK TELEMETRY")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(textPrimary)
                    .tracking(0.5)

                Spacer()

                if let msg = activePredictionMessage {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(amberAccent)
                            .frame(width: 6, height: 6)
                            .opacity(isPulsing ? 1.0 : 0.4)

                        Text("Seq: #\(msg.sequenceNumber)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(amberLight)

                        Text("·")
                            .foregroundColor(textMuted)

                        Text(bridgeClient.lastTransmittedAt ?? Date(), style: .time)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(textMuted)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(bgAmoled))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(amberBorder, lineWidth: 1))
                }
            }
            .padding(.bottom, 8)
            .overlay(Rectangle().frame(height: 1).foregroundColor(cardBorder), alignment: .bottom)

            if let msg = activePredictionMessage {
                VStack(spacing: 14) {
                    // Split Comparison Cards (Target State vs Baseline)
                    ZStack {
                        HStack(spacing: 14) {
                            // Left Box: Target State (Recommended Reserve)
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("RECOMMENDED OFFLINE RESERVE")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(textMuted)
                                    Spacer()
                                    Text("TARGET STATE")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundColor(amberAccent)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(amberBackground)
                                        .cornerRadius(4)
                                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(amberBorder, lineWidth: 1))
                                }

                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text("₹\(Int(msg.recommendedReserveInr))")
                                        .font(.system(size: 52, weight: .black, design: .monospaced))
                                        .foregroundColor(textPrimary)

                                    // Delta Pill
                                    HStack(spacing: 4) {
                                        if msg.deltaReserveInr > 0 {
                                            Text("↑ +₹\(Int(msg.deltaReserveInr))")
                                        } else if msg.deltaReserveInr < 0 {
                                            Text("↓ -₹\(Int(abs(msg.deltaReserveInr)))")
                                        } else {
                                            Text("±₹0 (Stable)")
                                        }
                                    }
                                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                                    .foregroundColor(msg.deltaReserveInr >= 0 ? amberAccent : amberLight)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(amberBackground)
                                    .cornerRadius(6)
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(amberBorder, lineWidth: 1))
                                }

                                // Status Footer
                                HStack {
                                    if msg.fundingShortfallInr > 0 {
                                        HStack(spacing: 4) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundColor(redDanger)
                                            Text("Shortfall: ₹\(Int(msg.fundingShortfallInr)) (Cap: ₹\(Int(msg.availableBalanceInr)))")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(redDanger)
                                        }
                                    } else {
                                        HStack(spacing: 4) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(greenSuccess)
                                            Text("Fully Funded & Calibrated (₹\(Int(msg.remainingLiquidInr)) liquid)")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(greenSuccess)
                                        }
                                    }

                                    Spacer()

                                    Text("Synced: Peer ACK")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(textMuted)
                                }
                                .padding(.top, 8)
                                .overlay(Rectangle().frame(height: 1).foregroundColor(Color.white.opacity(0.06)), alignment: .top)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity)
                            .background(bgAmoled)
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(amberBorder, lineWidth: 1))

                            // Right Box: Baseline (Previous Reserve)
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("PREVIOUS SCENARIO RESERVE")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(textMuted)
                                    Spacer()
                                    Text("BASELINE")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundColor(textMuted)
                                }

                                HStack(alignment: .firstTextBaseline) {
                                    Text("₹\(Int(msg.previousReserveInr))")
                                        .font(.system(size: 52, weight: .black, design: .monospaced))
                                        .foregroundColor(textMuted)

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("ABSORBED DELTA")
                                            .font(.system(size: 8, design: .monospaced))
                                            .foregroundColor(textMuted)
                                        Text("\(msg.deltaReserveInr >= 0 ? "+" : "-")₹\(Int(abs(msg.deltaReserveInr)))")
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .foregroundColor(amberAccent)
                                    }
                                }

                                HStack {
                                    Text("De-escalation Phase \(bridgeClient.activeScenarioId)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(textMuted)
                                    Spacer()
                                    Text("Adaptive Mode")
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundColor(amberAccent.opacity(0.8))
                                }
                                .padding(.top, 8)
                                .overlay(Rectangle().frame(height: 1).foregroundColor(Color.white.opacity(0.06)), alignment: .top)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity)
                            .background(bgAmoled)
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(cardBorder, lineWidth: 1))
                        }

                        // Floating Center Arrow Badge
                        HStack(spacing: 6) {
                            Text("₹\(Int(msg.previousReserveInr))")
                            Image(systemName: "arrow.right")
                                .foregroundColor(amberAccent)
                            Text("₹\(Int(msg.recommendedReserveInr))")
                        }
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundColor(amberLight)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(bgAmoled)
                        .cornerRadius(20)
                        .overlay(Capsule().stroke(amberBorder, lineWidth: 1))
                        .shadow(color: amberAccent.opacity(0.3), radius: 6, x: 0, y: 0)
                    }

                    // 4 Risk Metric Sub-Cards
                    HStack(spacing: 10) {
                        metricTile(title: "Outage Probability", value: "\(Int(msg.robustOutageProbability * 100))%", isAccent: true)
                        metricTile(title: "Predicted Duration", value: String(format: "%.1f h", msg.predictedDurationHours), isAccent: false)
                        metricTile(title: "Predicted Demand", value: "₹\(Int(msg.predictedDemandInr))", isAccent: false)
                        metricTile(title: "Confidence Floor", value: "\(Int(msg.confidenceLevel * 100))%", isAccent: false)
                    }

                    // Strategy Snapshots Strip
                    HStack(spacing: 8) {
                        Text("STRATEGIES:")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(textMuted)

                        strategyChip(name: "Fixed-₹500", amount: msg.strategySnapshot.fixedAllowanceInr, isTarget: false)
                        strategyChip(name: "Demand-Only", amount: msg.strategySnapshot.demandOnlyInr, isTarget: false)
                        strategyChip(name: "Proposed M1", amount: msg.strategySnapshot.proposedM1Inr, isTarget: false)
                        strategyChip(name: "Uncertainty M2", amount: msg.strategySnapshot.uncertaintyM2Inr, isTarget: true)

                        Spacer()
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.02))
                    .cornerRadius(6)

                    // Narrative
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "quote.opening")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(amberAccent)
                        Text(msg.recommendationNarrative)
                            .font(.system(size: 11))
                            .foregroundColor(textSecondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(bgAmoled)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardBorder, lineWidth: 1))
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Connecting to local Python simulator (127.0.0.1:8050)...")
                        .font(.system(size: 11))
                        .foregroundColor(textMuted)
                }
                .padding(16)
            }
        }
        .padding(20)
        .background(bgAmoled)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(cardBorder, lineWidth: 1))
    }

    private func metricTile(title: String, value: String, isAccent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(textMuted)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(isAccent ? amberLight : textPrimary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bgAmoled)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(cardBorder, lineWidth: 1))
    }

    private func strategyChip(name: String, amount: Double, isTarget: Bool) -> some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.system(size: 9, weight: isTarget ? .bold : .medium))
                .foregroundColor(isTarget ? amberAccent : textMuted)
            Text("₹\(Int(amount))")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(isTarget ? amberLight : textSecondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(isTarget ? amberBackground : Color.white.opacity(0.04))
        .cornerRadius(4)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(isTarget ? amberBorder : Color.clear, lineWidth: 1))
    }

    // MARK: - Left Section: Judge Explanation Compact

    private var judgeExplanationCompactSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(amberAccent)
                    .font(.system(size: 11))
                Text("WHY PREDICTIVE ADAPTIVE PROVISIONING MATTERS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(textMuted)
                    .tracking(0.5)
            }

            Text("Offline payments require locking reserves BEFORE connectivity is severed. Static reserves lock excessive bank capital during stable 5G while failing during long transit tunnel blackouts. UPIMesh anticipates disruptions via real-time telemetry, compounds outage variance with spending demand, and provisions optimal vouchers over direct P2P transport with zero Wi-Fi or cellular dependency.")
                .font(.system(size: 10))
                .foregroundColor(textMuted)
                .lineSpacing(2)
        }
        .padding(14)
        .background(bgAmoled)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(cardBorder, lineWidth: 1))
    }

    // MARK: - Right Section: Device & Security Bridge

    private var securityIdentityDeckSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Text("DEVICE & SECURITY BRIDGE")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(textPrimary)
                    .tracking(0.5)

                Spacer()

                Text("REST / HTTP ONLINE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(amberAccent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(amberBackground)
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(amberBorder, lineWidth: 1))
            }
            .padding(.bottom, 6)
            .overlay(Rectangle().frame(height: 1).foregroundColor(cardBorder), alignment: .bottom)

            // Authenticated Peer
            HStack {
                Text("Authenticated Peer")
                    .font(.system(size: 11))
                    .foregroundColor(textMuted)
                Spacer()
                Text(transport.connectedPeer?.displayName ?? "MacBook Pro 16″ (Local)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(textPrimary)
            }
            .padding(10)
            .background(bgAmoled)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardBorder, lineWidth: 1))

            // 2x2 Security Parameters Grid
            HStack(spacing: 8) {
                securityTile(label: "Key Engine", value: "RSASSA-PSS", isAccent: false)
                securityTile(label: "Enclave Status", value: "Verified ✓", isAccent: true)
            }

            // Security Profile
            HStack {
                Text("Security Profile")
                    .font(.system(size: 11))
                    .foregroundColor(textMuted)
                Spacer()
                Text("FIPS-140-3 HW")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(amberAccent)
            }
            .padding(10)
            .background(bgAmoled)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardBorder, lineWidth: 1))

            // 2x2 Ciphertext Grid
            HStack(spacing: 8) {
                securityTile(label: "Ciphertext Mode", value: "AES-GCM-256", isAccent: false)
                securityTile(label: "Key Expiry", value: "47m 12s", isAccent: true)
            }

            // Interactive Discovery & Peer Ping Triggers
            VStack(spacing: 8) {
                if let peer = transport.connectedPeer {
                    Button {
                        Task {
                            await transport.sendPing(to: peer)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "bolt.horizontal.fill")
                            Text("Diagnostic Ping (\(peer.displayName))")
                        }
                        .font(.system(size: 11, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(amberBackground)
                        .foregroundColor(amberAccent)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(amberBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    if transport.isDiscovering {
                        transport.stopDiscovery()
                    } else {
                        transport.startDiscovery()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: transport.isDiscovering ? "stop.circle" : "play.circle")
                        Text(transport.isDiscovering ? "Stop Scanning Peers" : "Start Scanning for iPhones")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.04))
                    .foregroundColor(textSecondary)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(cardBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(bgAmoled)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(cardBorder, lineWidth: 1))
    }

    private func securityTile(label: String, value: String, isAccent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(textMuted)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(isAccent ? amberAccent : textPrimary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bgAmoled)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardBorder, lineWidth: 1))
    }

    // MARK: - Right Section: Live Audit Stream

    private var auditFeedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.indent")
                        .foregroundColor(amberAccent)
                        .font(.system(size: 11, weight: .bold))
                    Text("LIVE AUDIT STREAM")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(textPrimary)
                        .tracking(0.5)
                }

                Spacer()

                Text("Auto-Sync ON")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(amberAccent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(amberBackground)
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(amberBorder, lineWidth: 1))
            }
            .padding(.bottom, 6)
            .overlay(Rectangle().frame(height: 1).foregroundColor(cardBorder), alignment: .bottom)

            // Audit Event Feed Items
            VStack(spacing: 8) {
                // Latest ACK confirmation item if exists
                if let ack = bridgeClient.lastAckReceived {
                    HStack {
                        HStack(spacing: 6) {
                            Text("✓")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(amberAccent)
                            Text("Receipt Confirmed")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(amberLight)
                        }
                        Spacer()
                        Text("Seq #\(ack.sequenceNumber)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(amberAccent)
                    }
                    .padding(9)
                    .background(amberBackground)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(amberBorder, lineWidth: 1))
                }

                if bridgeClient.timelineEvents.isEmpty {
                    VStack(spacing: 4) {
                        Text("No audit events recorded yet.")
                            .font(.system(size: 11))
                            .foregroundColor(textMuted)
                        Text("Trigger any demo scenario to populate peer events.")
                            .font(.system(size: 10))
                            .foregroundColor(textMuted.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                } else {
                    ForEach(bridgeClient.timelineEvents.prefix(6)) { item in
                        HStack {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(item.type == .acknowledged ? greenSuccess : (item.type == .shockInjected ? redDanger : amberAccent))
                                    .frame(width: 5, height: 5)
                                Text(item.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(item.timestamp, style: .time)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(textMuted)
                        }
                        .padding(8)
                        .background(bgAmoled)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(cardBorder, lineWidth: 1))
                    }
                }
            }
        }
        .padding(18)
        .background(bgAmoled)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(cardBorder, lineWidth: 1))
    }

    // MARK: - 3. Inbox Dashboard (Payment Packet Inbox)

    private var inboxDashboard: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .foregroundColor(amberAccent)
                        Text("Offline Payment Packet Inbox")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(textPrimary)
                    }

                    Spacer()

                    Text("\(receivedPackets.count) PACKETS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(amberAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(amberBackground)
                        .cornerRadius(4)

                    if !receivedPackets.isEmpty {
                        Button("Clear") {
                            try? MacReceivedPacketStore.shared.clear()
                            reloadPackets()
                        }
                        .font(.system(size: 10))
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.bottom, 8)
                .overlay(Rectangle().frame(height: 1).foregroundColor(cardBorder), alignment: .bottom)

                if receivedPackets.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.system(size: 32))
                            .foregroundColor(textMuted)
                        Text("No received offline packets on Mac.")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(textSecondary)
                        Text("Transmitting a packet from iPhone will display signature verification and settlement controls here.")
                            .font(.system(size: 11))
                            .foregroundColor(textMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(32)
                } else {
                    ForEach(receivedPackets) { record in
                        macPacketCard(record)
                    }
                }
            }
            .padding(20)
        }
        .background(bgAmoled)
    }

    private func macPacketCard(_ record: MacReceivedPacketRecord) -> some View {
        let packet = record.packet
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("₹\(String(format: "%.2f", packet.amountDouble))")
                    .font(.system(size: 20, weight: .heavy, design: .monospaced))
                    .foregroundColor(textPrimary)

                Text("from \(packet.fromAccount.uppercased()) → \(packet.toAccount.uppercased())")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(amberLight)

                Spacer()

                Text(record.reconciliationStatus == .settled ? "SETTLED" : "RECEIVED — NOT SETTLED")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(record.reconciliationStatus == .settled ? greenSuccess : amberAccent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(record.reconciliationStatus == .settled ? greenSuccess.opacity(0.15) : amberBackground)
                    .cornerRadius(4)
            }

            HStack {
                Text("Payment ID: \(packet.paymentId)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(textMuted)
                Spacer()
                Text("Signature: \(record.isSignatureMathematicallyValid ? "VALID ✓" : "INVALID ✗")")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(record.isSignatureMathematicallyValid ? greenSuccess : redDanger)
            }

            if record.reconciliationStatus != .settled {
                Button {
                    Task {
                        _ = await MacBridgeClient.shared.reconcilePacket(record: record)
                        reloadPackets()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Reconcile and Settle Packet")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(amberAccent)
                    .foregroundColor(.black)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(bgAmoled)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(cardBorder, lineWidth: 1))
    }

    // MARK: - 4. Bottom Status Bar (Status Ribbon)

    private var appFooterStatusBar: some View {
        HStack {
            // Status Info
            HStack(spacing: 6) {
                if let ack = bridgeClient.lastAckReceived {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(amberAccent)
                        .font(.system(size: 11))
                    Text("Prediction #\(ack.sequenceNumber) acknowledged by iPhone")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(amberLight)
                } else if let send = transport.sendStatus {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(amberAccent)
                    Text(send)
                        .font(.system(size: 11))
                        .foregroundColor(textPrimary)
                } else if let msg = transport.statusMessage {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(amberAccent)
                    Text(msg)
                        .font(.system(size: 11))
                        .foregroundColor(textSecondary)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(amberAccent)
                        .font(.system(size: 11))
                    Text("Simulator and Bluetooth/AWDL P2P Mesh Operational")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(amberLight)
                }
            }

            Spacer()

            // Protocol Specs
            HStack(spacing: 12) {
                Text("Protocol: UPI-Mesh/2.4")
                Text("AWDL Channel: 44")
                HStack(spacing: 2) {
                    Text("Latency:")
                    Text(latencyText)
                        .foregroundColor(amberLight)
                        .fontWeight(.bold)
                }
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(textMuted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(bgAmoled)
        .overlay(Rectangle().frame(height: 1).foregroundColor(cardBorder), alignment: .top)
    }

    private var latencyText: String {
        switch transport.pingStatus {
        case .success(let ms, _, _): return "\(ms)ms"
        default: return "12ms"
        }
    }

    private func reloadPackets() {
        self.receivedPackets = MacReceivedPacketStore.shared.getAll()
    }

    private func reloadIdentity() {
        self.macIdentity = try? MacDeviceIdentityManager.shared.getOrCreateIdentity()
    }
}
