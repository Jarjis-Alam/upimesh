import SwiftUI
import MultipeerConnectivity

/// Offline Pay Screen (`ios_ui/offline_pay_ios/`)
///
/// Faithfully reproduces the Stitch UI offline payment interface:
/// - Payment Value Hero readout with quick amount increment chips (+₹100, +₹500, +₹1,000).
/// - Sender and Recipient glass cards showing node balances and paired POS status.
/// - Offline cryptographic memo input and Zero-Trust banner.
/// - Glowing "Inject Payment into Mesh" button connected to backend mesh simulation.
/// - Live Mesh Journey 3-stage pipeline tracker reflecting genuine backend settlement telemetry.
public struct OfflinePayView: View {

    public enum PaymentSubmissionState: Equatable {
        case idle
        case submitting
        case settled(MeshPaymentResultDTO)
        case failed(String)
    }

    public enum OfflinePacketCreationState: Equatable {
        case idle
        case creating
        case created(OfflinePaymentPacket)
        case failed(String)
    }

    @State private var amount: Double = 20.00
    @State private var memo: String = "Lunch payment (Offline)"
    @State private var senderId: String = "alice"
    @State private var recipientId: String = "bob"
    @State private var submissionState: PaymentSubmissionState = .idle
    @State private var offlineCreationState: OfflinePacketCreationState = .idle
    @State private var queuedPackets: [OfflinePaymentPacket] = []
    @ObservedObject private var transportService = MeshPeerTransportService.shared
    @State private var receivedPackets: [ReceivedPacketRecord] = []
    @State private var selectedPacketForTransfer: OfflinePaymentPacket? = nil
    @State private var showQRModal: Bool = false
    @State private var senderBalance: Double? = nil
    @State private var isLiveBalance: Bool = false

    // Reconciliation Service & Interactive State (Stage 6.4B.3)
    private let reconciliationService: OfflineReconciliationService
    @State private var reconcilingPaymentIds: Set<String> = []
    @State private var lastReconciliationOutcome: [String: ReconciliationOutcome] = [:]

    // Offline Allowance Integration (Phase 2B)
    @State private var useAllowance: Bool = false
    @State private var activeAllowance: OfflineAllowanceVoucher? = nil

    public init(reconciliationService: OfflineReconciliationService = .shared) {
        self.reconciliationService = reconciliationService
    }

    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: DesignTokens.Spacing.md) {

                // MARK: - Header
                headerView

                // MARK: - Payment Terminal Card
                terminalCard

                // MARK: - Security Notice Banner
                securityBanner

                // MARK: - Primary & Secondary Actions
                actionButtons

                // MARK: - Live Mesh Journey Telemetry
                journeyTelemetryCard

                // MARK: - Locally Stored Queued Offline Packets (Stage 6.2)
                queuedPacketsSection

                // MARK: - Nearby Mesh Peer Discovery & Transport (Stage 6.3B)
                peerTransportSection

                // MARK: - Received Packets Inbox (Stage 6.3B)
                receivedPacketsInboxSection

                // Bottom spacer for detached floating tab bar
                Spacer(minLength: 88)
            }
            .padding(.horizontal, DesignTokens.Spacing.margin)
            .padding(.top, 8)
        }
        .task {
            await loadSenderBalance()
            reloadQueuedPackets()
            reloadReceivedPackets()
            reloadActiveAllowance()
        }
        .onAppear {
            reloadQueuedPackets()
            reloadReceivedPackets()
            reloadActiveAllowance()
            if !transportService.isDiscovering {
                transportService.startDiscovery()
            }
        }
        .refreshable {
            await loadSenderBalance()
            reloadQueuedPackets()
            reloadReceivedPackets()
            reloadActiveAllowance()
        }
        .onReceive(transportService.$connectionState) { state in
            if state == .connected, let peer = transportService.connectedPeer {
                Task {
                    if queuedPackets.first(where: { $0.allowanceSpend?.allowanceId == activeAllowance?.allowanceId }) == nil {
                        await createOfflinePacketAction()
                    }
                    if let pkt = selectedPacketForTransfer ?? queuedPackets.last {
                        try? await transportService.sendPacket(pkt, to: peer)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .meshAccountsUpdated)) { _ in
            Task {
                await loadSenderBalance()
                reloadQueuedPackets()
                reloadReceivedPackets()
                reloadActiveAllowance()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .offlinePacketReceived)) { _ in
            reloadReceivedPackets()
        }
        .onReceive(NotificationCenter.default.publisher(for: .offlinePacketSent)) { _ in
            reloadQueuedPackets()
            reloadActiveAllowance()
        }
        .onReceive(NotificationCenter.default.publisher(for: .offlineAllowanceUpdated)) { _ in
            reloadActiveAllowance()
        }
    }

    // MARK: - Header Subview
    private var headerView: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Offline Pay")
                        .font(DesignTokens.Typography.headlineSm)
                        .foregroundColor(DesignTokens.Colors.onSurface)

                    HStack(spacing: 5) {
                        Circle()
                            .fill(DesignTokens.Colors.meshGold)
                            .frame(width: 6, height: 6)
                        Text("MESH ACTIVE")
                            .font(DesignTokens.Typography.labelCaps)
                            .foregroundColor(DesignTokens.Colors.meshGold)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(DesignTokens.Colors.surfaceContainerHigh.opacity(0.7))
                    )
                }

                Text("Offline P2P Protocol")
                    .font(DesignTokens.Typography.caption)
                    .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
            }

            Spacer()

            Circle()
                .fill(DesignTokens.Colors.meshGold)
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "person.fill")
                        .foregroundColor(DesignTokens.Colors.onMeshGold)
                        .font(.system(size: 17, weight: .bold))
                )
                .shadow(color: DesignTokens.Colors.meshGold.opacity(0.35), radius: 8, x: 0, y: 2)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Terminal Card
    private var terminalCard: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            // Amount Hero Section
            VStack(spacing: 4) {
                Text("PAYMENT VALUE")
                    .font(DesignTokens.Typography.labelCaps)
                    .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                    .tracking(1.5)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("₹")
                        .font(DesignTokens.Typography.displayHeroMobile)
                        .foregroundColor(DesignTokens.Colors.meshGold)
                        .fontWeight(.bold)

                    Text(String(format: "%.2f", amount))
                        .font(DesignTokens.Typography.displayHero)
                        .foregroundColor(DesignTokens.Colors.onSurface)
                        .fontWeight(.bold)

                    Rectangle()
                        .fill(DesignTokens.Colors.meshGold)
                        .frame(width: 2, height: 30)
                }

                // Quick Amount Chips
                HStack(spacing: 8) {
                    amountChip(delta: 100, label: "+₹100")
                    amountChip(delta: 500, label: "+₹500")
                    amountChip(delta: 1000, label: "+₹1,000")
                }
                .padding(.top, 4)
            }
            .padding(.vertical, 8)

            // Sender & Recipient Pickers
            VStack(spacing: 8) {
                // Sender Card (Alice)
                HStack(spacing: 10) {
                    Circle()
                        .fill(DesignTokens.Colors.meshGold.opacity(0.2))
                        .frame(width: 38, height: 38)
                        .overlay(
                            Image(systemName: "person.circle.fill")
                                .foregroundColor(DesignTokens.Colors.meshGold)
                                .font(.system(size: 20))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("From (Local Node)")
                                .font(DesignTokens.Typography.caption)
                                .foregroundColor(DesignTokens.Colors.onSurfaceVariant)

                            if isLiveBalance {
                                Text("LIVE")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(DesignTokens.Colors.meshGold)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(DesignTokens.Colors.meshGold.opacity(0.15)))
                            }
                        }

                        Text("Alice")
                            .font(DesignTokens.Typography.bodyMd)
                            .fontWeight(.medium)
                            .foregroundColor(DesignTokens.Colors.onSurface)
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "wallet.bifold.fill")
                            .font(.system(size: 13))
                            .foregroundColor(DesignTokens.Colors.meshGold)

                        if let balance = senderBalance {
                            Text(CurrencyFormatter.format(amount: balance))
                                .font(DesignTokens.Typography.labelNumericSm)
                                .foregroundColor(DesignTokens.Colors.onSurface)
                        } else {
                            Text("₹5,000.00")
                                .font(DesignTokens.Typography.labelNumericSm)
                                .foregroundColor(DesignTokens.Colors.onSurface)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(DesignTokens.Colors.surfaceContainerHigh.opacity(0.7)))
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.base)
                        .fill(DesignTokens.Colors.surfaceContainerLow.opacity(0.8))
                )

                // Recipient Card (Bob)
                HStack(spacing: 10) {
                    Circle()
                        .fill(DesignTokens.Colors.secondary.opacity(0.2))
                        .frame(width: 38, height: 38)
                        .overlay(
                            Image(systemName: "storefront.fill")
                                .foregroundColor(DesignTokens.Colors.secondary)
                                .font(.system(size: 18))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Bob")
                                .font(DesignTokens.Typography.bodyMd)
                                .fontWeight(.medium)
                                .foregroundColor(DesignTokens.Colors.onSurface)

                            Text("MERCHANT")
                                .font(DesignTokens.Typography.labelCaps)
                                .foregroundColor(DesignTokens.Colors.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(DesignTokens.Colors.secondaryContainer.opacity(0.25)))
                        }
                        Text("Node ID: #B-240 · Signal -68dBm")
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14))
                            .foregroundColor(DesignTokens.Colors.meshGold)
                        Text("PAIRED")
                            .font(DesignTokens.Typography.labelCaps)
                            .foregroundColor(DesignTokens.Colors.meshGold)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.base)
                        .fill(DesignTokens.Colors.surfaceContainerLow.opacity(0.8))
                )
            }

            // Memo Input Pill
            HStack(spacing: 10) {
                Image(systemName: "pencil.line")
                    .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                    .font(.system(size: 16))

                TextField("Add payment memo...", text: $memo)
                    .font(DesignTokens.Typography.bodySm)
                    .foregroundColor(DesignTokens.Colors.onSurface)

                Image(systemName: "lock.fill")
                    .foregroundColor(DesignTokens.Colors.meshGold)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(DesignTokens.Colors.surfaceContainerLow.opacity(0.6))
            )
        }
        .padding(DesignTokens.Spacing.md)
        .liquidCard(strokeColor: DesignTokens.Colors.glassStrokeLight)
    }

    private func amountChip(delta: Double, label: String) -> some View {
        Button {
            amount += delta
        } label: {
            Text(label)
                .font(DesignTokens.Typography.labelNumericSm)
                .foregroundColor(DesignTokens.Colors.onSurface)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(DesignTokens.Colors.surfaceContainerHighest.opacity(0.6))
                        .overlay(Capsule().stroke(DesignTokens.Colors.glassStrokeDim, lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Security Notice Banner
    private var securityBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(DesignTokens.Colors.surfaceContainerHigh)
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "shield.checkerboard")
                        .foregroundColor(DesignTokens.Colors.meshGold)
                        .font(.system(size: 16))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Zero-Trust Cryptographic Payload")
                    .font(DesignTokens.Typography.bodySm)
                    .fontWeight(.medium)
                    .foregroundColor(DesignTokens.Colors.onSurface)

                Text("Encrypted via RSA-OAEP + AES-256-GCM. Settled through backend mesh gateway simulation.")
                    .font(DesignTokens.Typography.caption)
                    .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.base)
                .fill(DesignTokens.Colors.surfaceContainerLow.opacity(0.6))
        )
    }

    // MARK: - Primary and Secondary Actions
    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                Task {
                    await executeMeshPayment()
                }
            } label: {
                HStack(spacing: 8) {
                    switch submissionState {
                    case .submitting:
                        ProgressView()
                            .tint(DesignTokens.Colors.onMeshGold)
                        Text("Signing & Submitting to Mesh...")
                            .font(DesignTokens.Typography.headlineSm)
                            .fontWeight(.bold)

                    case .settled:
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20, weight: .bold))
                        Text("Device-Signed & Settled!")
                            .font(DesignTokens.Typography.headlineSm)
                            .fontWeight(.bold)

                    case .failed:
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 20, weight: .bold))
                        Text("Payment Failed — Tap to Retry")
                            .font(DesignTokens.Typography.headlineSm)
                            .fontWeight(.bold)

                    case .idle:
                        Image(systemName: "arrow.triangle.swap")
                            .font(.system(size: 18, weight: .bold))
                        Text("Inject Payment into Mesh")
                            .font(DesignTokens.Typography.headlineSm)
                            .fontWeight(.bold)
                    }
                }
                .foregroundColor(buttonForegroundColor)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    Capsule()
                        .fill(buttonBackgroundColor)
                        .shadow(
                            color: buttonShadowColor,
                            radius: 14, x: 0, y: 5
                        )
                )
            }
            .disabled(submissionState == .submitting || amount <= 0)
            .buttonStyle(.plain)

            // Inline Error Banner if failed
            if case .failed(let errorMsg) = submissionState {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(DesignTokens.Colors.error)
                        .font(.system(size: 14))

                    Text(errorMsg)
                        .font(DesignTokens.Typography.caption)
                        .foregroundColor(DesignTokens.Colors.onSurface)
                        .lineLimit(2)

                    Spacer()
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(DesignTokens.Colors.error.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(DesignTokens.Colors.error.opacity(0.3), lineWidth: 1))
                )
            }

            // Inline Settlement Confirmation if settled
            if case .settled(let result) = submissionState {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(DesignTokens.Colors.meshGold)
                        .font(.system(size: 14))

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Settled: \(CurrencyFormatter.format(amount: result.amount)) to \(result.toAccount.capitalized)")
                            .font(DesignTokens.Typography.labelNumericSm)
                            .foregroundColor(DesignTokens.Colors.onSurface)

                        Text("Payment ID: \(result.paymentId)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(DesignTokens.Colors.surfaceContainerHigh.opacity(0.7))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(DesignTokens.Colors.meshGold.opacity(0.3), lineWidth: 1))
                )
            }

            // MARK: - Allowance Payment Option (Phase 2B)
            if let voucher = activeAllowance, !voucher.isExpired() {
                Toggle(isOn: $useAllowance) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Image(systemName: "banknote.fill")
                                .foregroundColor(DesignTokens.Colors.meshGold)
                            Text("Use Offline Allowance")
                                .font(DesignTokens.Typography.bodySm)
                                .fontWeight(.semibold)
                                .foregroundColor(DesignTokens.Colors.onSurface)
                        }
                        Text("Available: ₹\(voucher.remainingAmount) · Escrow-Backed")
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: DesignTokens.Colors.meshGold))
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(DesignTokens.Colors.surfaceContainerHigh.opacity(0.6))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(DesignTokens.Colors.meshGold.opacity(useAllowance ? 0.4 : 0.1), lineWidth: 1))
                )
            }

            // MARK: - Create Offline Packet Action (Stage 6.2 / 2B)
            Button {
                Task {
                    await createOfflinePacketAction()
                }
            } label: {
                HStack(spacing: 8) {
                    switch offlineCreationState {
                    case .creating:
                        ProgressView()
                            .tint(DesignTokens.Colors.secondary)
                        Text(useAllowance ? "Signing Allowance Spend..." : "Signing & Storing Offline...")
                            .font(DesignTokens.Typography.bodyMd)
                            .fontWeight(.semibold)

                    case .created:
                        Image(systemName: useAllowance ? "banknote.fill" : "tray.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(DesignTokens.Colors.meshGold)
                        Text(useAllowance ? "Allowance Spend Queued!" : "Packet Queued Locally!")
                            .font(DesignTokens.Typography.bodyMd)
                            .fontWeight(.semibold)

                    case .failed:
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(DesignTokens.Colors.error)
                        Text("Queue Failed — Tap to Retry")
                            .font(DesignTokens.Typography.bodyMd)
                            .fontWeight(.semibold)

                    case .idle:
                        Image(systemName: useAllowance ? "banknote.fill" : "tray.and.arrow.down.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(useAllowance ? DesignTokens.Colors.meshGold : DesignTokens.Colors.secondary)
                        Text(useAllowance ? "Create Allowance Spend Packet" : "Create Offline Packet")
                            .font(DesignTokens.Typography.bodyMd)
                            .fontWeight(.semibold)
                    }
                }
                .foregroundColor(offlineButtonForegroundColor)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    Capsule()
                        .fill(DesignTokens.Colors.surfaceContainerHigh.opacity(0.85))
                        .overlay(
                            Capsule()
                                .stroke(offlineButtonStrokeColor, lineWidth: 1.5)
                        )
                )
            }
            .disabled(offlineCreationState == .creating || submissionState == .submitting || amount <= 0)
            .buttonStyle(.plain)

            // Inline Feedback for Offline Packet Creation
            if case .created(let packet) = offlineCreationState {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "tray.fill")
                        .foregroundColor(DesignTokens.Colors.meshGold)
                        .font(.system(size: 16))
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("Packet Queued Locally")
                                .font(DesignTokens.Typography.bodySm)
                                .fontWeight(.bold)
                                .foregroundColor(DesignTokens.Colors.onSurface)

                            Text("NOT SETTLED")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(DesignTokens.Colors.meshGold)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(DesignTokens.Colors.meshGold.opacity(0.15)))
                        }

                        Text("Payment of \(CurrencyFormatter.format(amount: packet.amountDouble)) to \(packet.toAccount.capitalized) was cryptographically signed and stored in local device storage. It will remain queued until propagated across the mesh.")
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Payment ID: \(packet.paymentId)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(DesignTokens.Colors.onSurfaceVariant.opacity(0.8))
                            .lineLimit(1)
                            .padding(.top, 2)
                    }

                    Spacer()

                    Button {
                        withAnimation {
                            offlineCreationState = .idle
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                            .padding(6)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.base)
                        .fill(DesignTokens.Colors.surfaceContainerHigh.opacity(0.7))
                        .overlay(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.base).stroke(DesignTokens.Colors.meshGold.opacity(0.35), lineWidth: 1))
                )
            }

            if case .failed(let errorMsg) = offlineCreationState {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(DesignTokens.Colors.error)
                        .font(.system(size: 14))

                    Text(errorMsg)
                        .font(DesignTokens.Typography.caption)
                        .foregroundColor(DesignTokens.Colors.onSurface)
                        .lineLimit(2)

                    Spacer()

                    Button {
                        withAnimation {
                            offlineCreationState = .idle
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(DesignTokens.Colors.error.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(DesignTokens.Colors.error.opacity(0.3), lineWidth: 1))
                )
            }

            Button {
                showQRModal.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 18))
                        .foregroundColor(DesignTokens.Colors.secondary)
                    Text("Show Offline QR Code")
                        .font(DesignTokens.Typography.bodyMd)
                        .fontWeight(.medium)
                        .foregroundColor(DesignTokens.Colors.onSurface)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    Capsule()
                        .fill(DesignTokens.Colors.surfaceContainerHigh.opacity(0.6))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var buttonForegroundColor: Color {
        if case .failed = submissionState {
            return DesignTokens.Colors.onError
        }
        return DesignTokens.Colors.onMeshGold
    }

    private var buttonBackgroundColor: Color {
        switch submissionState {
        case .submitting:
            return DesignTokens.Colors.meshGold.opacity(0.75)
        case .settled:
            return DesignTokens.Colors.primary
        case .failed:
            return DesignTokens.Colors.error
        case .idle:
            return DesignTokens.Colors.meshGold
        }
    }

    private var buttonShadowColor: Color {
        if case .failed = submissionState {
            return DesignTokens.Colors.error.opacity(0.3)
        }
        return DesignTokens.Colors.meshGold.opacity(0.35)
    }

    // MARK: - Live Mesh Journey Telemetry
    private var journeyTelemetryCard: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundColor(DesignTokens.Colors.secondary)
                        .font(.system(size: 16))
                    Text("Live Mesh Journey")
                        .font(DesignTokens.Typography.bodyMd)
                        .fontWeight(.semibold)
                        .foregroundColor(DesignTokens.Colors.onSurface)
                }

                Spacer()

                if case .settled(let result) = submissionState {
                    Text("\(result.hopsTaken) Hops · \(result.roundsRun) Rounds · \(result.status)")
                        .font(DesignTokens.Typography.caption)
                        .foregroundColor(DesignTokens.Colors.meshGold)
                        .fontWeight(.semibold)
                } else {
                    Text("Backend Simulation · 2 Hops")
                        .font(DesignTokens.Typography.caption)
                        .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                if case .settled(let result) = submissionState {
                    // Step 1: Device Cryptographic Signer (Alice)
                    journeyStepRow(
                        stepNumber: "1",
                        title: "1. Device Cryptographic Signer (\(result.fromAccount.capitalized))",
                        subtitle: "RSASSA-PSS-SHA256 device-signed · Verified with registered public key",
                        icon: "checkmark",
                        iconBg: DesignTokens.Colors.meshGold,
                        iconFg: DesignTokens.Colors.onMeshGold,
                        isConnectorActive: true
                    )

                    // Step 2: Relayed via Topology
                    let routeNodes = result.routeTrace.dropFirst().dropLast().joined(separator: ", ")
                    journeyStepRow(
                        stepNumber: "2",
                        title: "2. Relayed via \(routeNodes.isEmpty ? "Direct Hop" : routeNodes.capitalized)",
                        subtitle: "Route: \(result.routeTrace.joined(separator: " → ")) · \(result.hopsTaken) Hops",
                        icon: "dot.radiowaves.left.and.right",
                        iconBg: DesignTokens.Colors.secondary,
                        iconFg: DesignTokens.Colors.onSecondary,
                        isConnectorActive: true
                    )

                    // Step 3: Settled at Gateway Bridge
                    journeyStepRow(
                        stepNumber: "3",
                        title: "3. Settled at Gateway Bridge",
                        subtitle: "Payment ID: \(result.paymentId)\nPacket: \(result.packetId)",
                        icon: "building.columns.fill",
                        iconBg: DesignTokens.Colors.primary,
                        iconFg: DesignTokens.Colors.onPrimary,
                        isConnectorActive: true,
                        showBottomConnector: false
                    )
                } else {
                    // Idle / Submitting State
                    journeyStepRow(
                        stepNumber: "1",
                        title: "1. Hardware Enclave / Keychain Signer",
                        subtitle: "RSASSA-PSS-SHA256 signing on-device · Canonical V1 bytes",
                        icon: submissionState == .submitting ? "arrow.triangle.2.circlepath" : "lock.shield",
                        iconBg: DesignTokens.Colors.meshGold,
                        iconFg: DesignTokens.Colors.onMeshGold,
                        isConnectorActive: submissionState == .submitting
                    )

                    journeyStepRow(
                        stepNumber: "2",
                        title: "2. Forward via Relay Topology",
                        subtitle: "Multi-hop routing (Alice → Carol → Bridge)",
                        icon: "dot.radiowaves.left.and.right",
                        iconBg: submissionState == .submitting ? DesignTokens.Colors.secondary : DesignTokens.Colors.surfaceContainerHighest,
                        iconFg: submissionState == .submitting ? DesignTokens.Colors.onSecondary : DesignTokens.Colors.outline,
                        isConnectorActive: false
                    )

                    journeyStepRow(
                        stepNumber: "3",
                        title: "3. Gateway Settlement",
                        subtitle: "Atomic H2 ledger credit & deduplication",
                        icon: "building.columns.fill",
                        iconBg: DesignTokens.Colors.surfaceContainerHighest,
                        iconFg: DesignTokens.Colors.outline,
                        isConnectorActive: false,
                        showBottomConnector: false
                    )
                }
            }
            .padding(.leading, 4)
        }
        .padding(DesignTokens.Spacing.md)
        .liquidCard(strokeColor: DesignTokens.Colors.glassStrokeLight)
    }

    private func journeyStepRow(
        stepNumber: String,
        title: String,
        subtitle: String,
        icon: String,
        iconBg: Color,
        iconFg: Color,
        isConnectorActive: Bool,
        showBottomConnector: Bool = true
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                Circle()
                    .fill(iconBg)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(iconFg)
                    )

                if showBottomConnector {
                    Rectangle()
                        .fill(isConnectorActive ? DesignTokens.Colors.meshGold.opacity(0.4) : DesignTokens.Colors.surfaceVariant)
                        .frame(width: 2, height: 24)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignTokens.Typography.bodySm)
                    .fontWeight(.medium)
                    .foregroundColor(DesignTokens.Colors.onSurface)

                Text(subtitle)
                    .font(DesignTokens.Typography.caption)
                    .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
            }

            Spacer()
        }
    }

    private var offlineButtonForegroundColor: Color {
        if case .failed = offlineCreationState {
            return DesignTokens.Colors.error
        }
        return DesignTokens.Colors.onSurface
    }

    private var offlineButtonStrokeColor: Color {
        switch offlineCreationState {
        case .created:
            return DesignTokens.Colors.meshGold.opacity(0.6)
        case .creating:
            return DesignTokens.Colors.secondary.opacity(0.6)
        case .failed:
            return DesignTokens.Colors.error.opacity(0.6)
        case .idle:
            return DesignTokens.Colors.secondary.opacity(0.4)
        }
    }

    // MARK: - Locally Stored Queued Offline Packets Section (Stage 6.2)
    private var queuedPacketsSection: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "tray.full.fill")
                        .foregroundColor(DesignTokens.Colors.meshGold)
                        .font(.system(size: 16))
                    Text("Local Queued Packets")
                        .font(DesignTokens.Typography.bodyMd)
                        .fontWeight(.semibold)
                        .foregroundColor(DesignTokens.Colors.onSurface)
                }

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(DesignTokens.Colors.meshGold)
                        .frame(width: 6, height: 6)
                    Text("\(queuedPackets.count) QUEUED")
                        .font(DesignTokens.Typography.labelCaps)
                        .foregroundColor(DesignTokens.Colors.meshGold)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(DesignTokens.Colors.meshGold.opacity(0.15))
                )
            }

            if queuedPackets.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray")
                        .font(.system(size: 24))
                        .foregroundColor(DesignTokens.Colors.onSurfaceVariant.opacity(0.6))
                    Text("No offline packets in local queue")
                        .font(DesignTokens.Typography.bodySm)
                        .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                    Text("Tap 'Create Offline Packet' above to sign and persist a payment locally without network.")
                        .font(DesignTokens.Typography.caption)
                        .foregroundColor(DesignTokens.Colors.onSurfaceVariant.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 8) {
                    ForEach(queuedPackets) { packet in
                        queuedPacketRow(packet)
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .liquidCard(strokeColor: DesignTokens.Colors.glassStrokeLight)
    }

    private func queuedPacketRow(_ packet: OfflinePaymentPacket) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    Text(CurrencyFormatter.format(amount: packet.amountDouble))
                        .font(DesignTokens.Typography.headlineSm)
                        .fontWeight(.bold)
                        .foregroundColor(DesignTokens.Colors.onSurface)

                    Text("→ \(packet.toAccount.capitalized)")
                        .font(DesignTokens.Typography.bodySm)
                        .fontWeight(.medium)
                        .foregroundColor(DesignTokens.Colors.secondary)
                }

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(packetStatusColor(packet.status))
                        .frame(width: 6, height: 6)
                    Text(packet.status.displayName)
                        .font(DesignTokens.Typography.labelCaps)
                        .foregroundColor(packetStatusColor(packet.status))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(DesignTokens.Colors.surfaceContainerHighest)
                )
            }

            HStack {
                Text("ID: \(packet.paymentId)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                    .lineLimit(1)

                Spacer()

                Text(packet.createdAt.isoString)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
            }

            HStack {
                Text("From: \(packet.fromAccount.capitalized) · Local Signed Packet · Awaiting Mesh / Bridge")
                    .font(.system(size: 10))
                    .foregroundColor(DesignTokens.Colors.onSurfaceVariant.opacity(0.8))

                if packet.isAllowanceBacked, let spend = packet.allowanceSpend {
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "banknote.fill").font(.system(size: 9)).foregroundColor(DesignTokens.Colors.meshGold)
                        Text("ALLOWANCE #\(spend.sequenceNumber)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(DesignTokens.Colors.meshGold)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(DesignTokens.Colors.meshGold.opacity(0.15)))
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.base)
                .fill(DesignTokens.Colors.surfaceContainerLow.opacity(0.8))
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.base).stroke(DesignTokens.Colors.glassStrokeDim, lineWidth: 1))
        )
    }

    // MARK: - Nearby Mesh Peer Discovery & Transport (Stage 6.3B)
    private var peerTransportSection: some View {
        VStack(spacing: 12) {
            // Header Row
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundColor(DesignTokens.Colors.meshGold)
                        .font(.system(size: 16))
                    Text("Nearby Peer Transport")
                        .font(DesignTokens.Typography.bodyMd)
                        .fontWeight(.semibold)
                        .foregroundColor(DesignTokens.Colors.onSurface)
                }

                Spacer()

                // Discovery status badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(transportService.isDiscovering ? DesignTokens.Colors.meshGold : DesignTokens.Colors.onSurfaceVariant)
                        .frame(width: 6, height: 6)
                    Text(transportService.isDiscovering ? "DISCOVERING" : "IDLE")
                        .font(DesignTokens.Typography.labelCaps)
                        .foregroundColor(transportService.isDiscovering ? DesignTokens.Colors.meshGold : DesignTokens.Colors.onSurfaceVariant)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(transportService.isDiscovering ? DesignTokens.Colors.meshGold.opacity(0.15) : DesignTokens.Colors.surfaceContainerHighest)
                )
            }

            // Connection State Capsule
            HStack(spacing: 8) {
                Image(systemName: transportService.connectedPeer != nil ? "link.circle.fill" : "link.badge.plus")
                    .foregroundColor(transportService.connectedPeer != nil ? DesignTokens.Colors.primary : DesignTokens.Colors.onSurfaceVariant)
                    .font(.system(size: 15))

                if let peer = transportService.connectedPeer {
                    Text("Connected to \(peer.displayName)")
                        .font(DesignTokens.Typography.bodySm)
                        .fontWeight(.medium)
                        .foregroundColor(DesignTokens.Colors.onSurface)

                    Spacer()

                    Button {
                        transportService.disconnect()
                    } label: {
                        Text("Disconnect")
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(DesignTokens.Colors.error)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(DesignTokens.Colors.error.opacity(0.15)))
                    }
                } else {
                    Text(transportService.connectionState == .connecting ? "Connecting to peer..." : "Not connected to any peer")
                        .font(DesignTokens.Typography.bodySm)
                        .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                    Spacer()
                    if transportService.connectionState == .connecting {
                        Button {
                            transportService.disconnect()
                        } label: {
                            Text("Cancel")
                                .font(DesignTokens.Typography.caption)
                                .foregroundColor(DesignTokens.Colors.error)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(DesignTokens.Colors.error.opacity(0.15)))
                        }
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.base)
                    .fill(DesignTokens.Colors.surfaceContainerLow.opacity(0.7))
            )

            // Discovery Controls & Discovered Peers
            if transportService.connectedPeer == nil {
                VStack(spacing: 8) {
                    Button {
                        if transportService.isDiscovering {
                            transportService.stopDiscovery()
                        } else {
                            transportService.startDiscovery()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: transportService.isDiscovering ? "stop.circle.fill" : "play.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(transportService.isDiscovering ? DesignTokens.Colors.error : DesignTokens.Colors.meshGold)
                            Text(transportService.isDiscovering ? "Stop Discovery" : "Scan for Nearby iPhones")
                                .font(DesignTokens.Typography.bodySm)
                                .fontWeight(.semibold)
                                .foregroundColor(DesignTokens.Colors.onSurface)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(
                            Capsule()
                                .fill(DesignTokens.Colors.surfaceContainerHigh.opacity(0.8))
                                .overlay(Capsule().stroke(DesignTokens.Colors.meshGold.opacity(0.3), lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)

                    if transportService.isDiscovering {
                        if transportService.discoveredPeers.isEmpty {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(DesignTokens.Colors.meshGold)
                                Text("Looking for nearby iPhones (AWDL / BLE)...")
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                            }
                            .padding(.vertical, 6)
                        } else {
                            VStack(spacing: 6) {
                                ForEach(transportService.discoveredPeers, id: \.self) { peer in
                                    HStack {
                                        Image(systemName: "iphone.gen3")
                                            .foregroundColor(DesignTokens.Colors.meshGold)
                                            .font(.system(size: 14))
                                        Text(peer.displayName)
                                            .font(DesignTokens.Typography.bodySm)
                                            .foregroundColor(DesignTokens.Colors.onSurface)

                                        Spacer()

                                        Button {
                                            transportService.invitePeer(peer)
                                        } label: {
                                            Text("Connect")
                                                .font(DesignTokens.Typography.caption)
                                                .fontWeight(.semibold)
                                                .foregroundColor(DesignTokens.Colors.onMeshGold)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 4)
                                                .background(Capsule().fill(DesignTokens.Colors.meshGold))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(8)
                                    .background(
                                        RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.base)
                                            .fill(DesignTokens.Colors.surfaceContainerHigh.opacity(0.5))
                                    )
                                }
                            }
                        }
                    }
                }
            } else if let peer = transportService.connectedPeer {
                // Connected Actions: Diagnostic Ping & Packet Transfer
                VStack(spacing: 12) {
                    // Diagnostic Peer Connectivity Section (Non-Financial Ping Test)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("PEER CONNECTIVITY TEST")
                                .font(DesignTokens.Typography.labelCaps)
                                .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                            Spacer()
                            Text("NON-FINANCIAL")
                                .font(DesignTokens.Typography.labelCaps)
                                .foregroundColor(DesignTokens.Colors.primary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(DesignTokens.Colors.primary.opacity(0.15)))
                        }

                        Button {
                            Task {
                                await transportService.sendPing(to: peer)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if transportService.pingStatus.isSending {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .tint(DesignTokens.Colors.onPrimary)
                                    Text("Pinging \(peer.displayName)...")
                                        .font(DesignTokens.Typography.bodySm)
                                        .fontWeight(.semibold)
                                        .foregroundColor(DesignTokens.Colors.onPrimary)
                                } else {
                                    Image(systemName: "bolt.horizontal.fill")
                                        .font(.system(size: 13))
                                        .foregroundColor(DesignTokens.Colors.onPrimary)
                                    Text("Ping Peer")
                                        .font(DesignTokens.Typography.bodySm)
                                        .fontWeight(.semibold)
                                        .foregroundColor(DesignTokens.Colors.onPrimary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(Capsule().fill(DesignTokens.Colors.primary))
                        }
                        .buttonStyle(.plain)
                        .disabled(transportService.pingStatus.isSending)

                        // Diagnostic Ping Status Display (Idle / Sending / Success / Failed)
                        switch transportService.pingStatus {
                        case .idle:
                            if let answered = transportService.lastDiagnosticPingAnswered {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.uturn.backward.circle.fill")
                                        .foregroundColor(DesignTokens.Colors.primary)
                                        .font(.system(size: 11))
                                    Text("Last inbound: \(answered)")
                                        .font(DesignTokens.Typography.caption)
                                        .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                                }
                            } else {
                                Text("Transmits a non-financial diagnostic PING/PONG to test transport latency.")
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                            }
                        case .sending:
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.7)
                                Text("Awaiting diagnostic PONG response from \(peer.displayName)...")
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                            }
                        case .success(let ms, let peerName, _):
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(DesignTokens.Colors.primary)
                                    .font(.system(size: 12))
                                Text("PONG received · \(ms) ms round-trip to \(peerName) ✓")
                                    .font(DesignTokens.Typography.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(DesignTokens.Colors.primary)
                                Spacer()
                                Button("Clear") {
                                    transportService.clearPingStatus()
                                }
                                .font(DesignTokens.Typography.caption)
                                .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(DesignTokens.Colors.primary.opacity(0.15)))
                        case .failed(let err):
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(DesignTokens.Colors.error)
                                    .font(.system(size: 12))
                                Text("Ping failed: \(err)")
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundColor(DesignTokens.Colors.error)
                                Spacer()
                                Button("Clear") {
                                    transportService.clearPingStatus()
                                }
                                .font(DesignTokens.Typography.caption)
                                .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(DesignTokens.Colors.error.opacity(0.15)))
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.base)
                            .fill(DesignTokens.Colors.surfaceContainerHigh.opacity(0.4))
                    )

                    // Offline Payment Packet Transfer Section
                    if queuedPackets.isEmpty {
                        Text("No queued offline packets available. Create one above to transfer.")
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                            .padding(.vertical, 4)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("SELECT PACKET TO TRANSMIT:")
                                .font(DesignTokens.Typography.labelCaps)
                                .foregroundColor(DesignTokens.Colors.onSurfaceVariant)

                            let targetPacket = selectedPacketForTransfer ?? queuedPackets.last
                            ForEach(queuedPackets) { packet in
                                let isSelected = (targetPacket?.paymentId == packet.paymentId)
                                Button {
                                    selectedPacketForTransfer = packet
                                } label: {
                                    HStack {
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(isSelected ? DesignTokens.Colors.meshGold : DesignTokens.Colors.onSurfaceVariant)
                                            .font(.system(size: 16))

                                        Text(CurrencyFormatter.format(amount: packet.amountDouble))
                                            .font(DesignTokens.Typography.bodySm)
                                            .fontWeight(.bold)
                                            .foregroundColor(DesignTokens.Colors.onSurface)

                                        Text("→ \(packet.toAccount.capitalized)")
                                            .font(DesignTokens.Typography.caption)
                                            .foregroundColor(DesignTokens.Colors.secondary)

                                        Spacer()

                                        Text(packet.paymentId.prefix(8) + "…")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                                    }
                                    .padding(8)
                                    .background(
                                        RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.base)
                                            .fill(isSelected ? DesignTokens.Colors.meshGold.opacity(0.12) : DesignTokens.Colors.surfaceContainerHigh.opacity(0.4))
                                            .overlay(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.base).stroke(isSelected ? DesignTokens.Colors.meshGold.opacity(0.5) : Color.clear, lineWidth: 1))
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            // Send Button
                            Button {
                                if let pkt = targetPacket {
                                    Task {
                                        try? await transportService.sendPacket(pkt, to: peer)
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    if case .sending = transportService.sendStatus {
                                        ProgressView()
                                            .tint(DesignTokens.Colors.onMeshGold)
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "paperplane.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(DesignTokens.Colors.onMeshGold)
                                    }
                                    Text("Send Packet to \(peer.displayName)")
                                        .font(DesignTokens.Typography.bodySm)
                                        .fontWeight(.semibold)
                                        .foregroundColor(DesignTokens.Colors.onMeshGold)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 42)
                                .background(
                                    Capsule()
                                        .fill(DesignTokens.Colors.meshGold)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(targetPacket == nil || transportService.sendStatus == .sending(targetPacket?.paymentId ?? ""))
                        }
                    }
                }
            }

            // Transport Status & Error Banners
            if let err = transportService.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(DesignTokens.Colors.error)
                        .font(.system(size: 12))
                    Text(err)
                        .font(DesignTokens.Typography.caption)
                        .foregroundColor(DesignTokens.Colors.error)
                    Spacer()
                    Button { transportService.clearBanners() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                            .foregroundColor(DesignTokens.Colors.error)
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(DesignTokens.Colors.error.opacity(0.12)))
            } else if let msg = transportService.statusMessage {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(DesignTokens.Colors.meshGold)
                        .font(.system(size: 12))
                    Text(msg)
                        .font(DesignTokens.Typography.caption)
                        .foregroundColor(DesignTokens.Colors.onSurface)
                    Spacer()
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(DesignTokens.Colors.surfaceContainerHigh.opacity(0.6)))
            }
        }
        .padding(DesignTokens.Spacing.md)
        .liquidCard(strokeColor: DesignTokens.Colors.glassStrokeLight)
    }

    // MARK: - Received Packets Inbox Section (Stage 6.3B / 6.4B.3)
    private var receivedPacketsInboxSection: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .foregroundColor(DesignTokens.Colors.secondary)
                        .font(.system(size: 16))
                    Text("Received Packets Inbox")
                        .font(DesignTokens.Typography.bodyMd)
                        .fontWeight(.semibold)
                        .foregroundColor(DesignTokens.Colors.onSurface)
                }

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(DesignTokens.Colors.secondary)
                        .frame(width: 6, height: 6)
                    Text("\(receivedPackets.count) RECEIVED")
                        .font(DesignTokens.Typography.labelCaps)
                        .foregroundColor(DesignTokens.Colors.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(DesignTokens.Colors.secondary.opacity(0.15))
                )
            }

            // Trust Boundary Banner (Stage 6.4B.3)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundColor(Color(red: 0.95, green: 0.65, blue: 0.1))
                    .font(.system(size: 13))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Offline Trust Boundary")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(DesignTokens.Colors.onSurface)
                    Text("An offline packet is not guaranteed payment until settled by the backend bridge. Balances credit only upon authoritative ledger confirmation.")
                        .font(.system(size: 10))
                        .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(red: 0.95, green: 0.65, blue: 0.1).opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(red: 0.95, green: 0.65, blue: 0.1).opacity(0.25), lineWidth: 1))
            )

            if receivedPackets.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray")
                        .font(.system(size: 24))
                        .foregroundColor(DesignTokens.Colors.onSurfaceVariant.opacity(0.6))
                    Text("No received offline packets in inbox")
                        .font(DesignTokens.Typography.bodySm)
                        .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                    Text("When a nearby iPhone transfers an offline packet to you, it will appear here awaiting bridge settlement.")
                        .font(DesignTokens.Typography.caption)
                        .foregroundColor(DesignTokens.Colors.onSurfaceVariant.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 8) {
                    ForEach(receivedPackets) { record in
                        receivedPacketRow(record)
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .liquidCard(strokeColor: DesignTokens.Colors.glassStrokeLight)
    }

    private func receivedPacketRow(_ record: ReceivedPacketRecord) -> some View {
        let packet = record.packet
        let isReconciling = reconcilingPaymentIds.contains(record.id)
        let outcome = lastReconciliationOutcome[record.id]

        return VStack(alignment: .leading, spacing: 8) {
            // Header: Amount, Sender & Status Badge
            HStack {
                HStack(spacing: 6) {
                    Text(CurrencyFormatter.format(amount: packet.amountDouble))
                        .font(DesignTokens.Typography.headlineSm)
                        .fontWeight(.bold)
                        .foregroundColor(DesignTokens.Colors.onSurface)

                    Text("from \(packet.fromAccount.capitalized)")
                        .font(DesignTokens.Typography.bodySm)
                        .fontWeight(.medium)
                        .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                }

                Spacer()

                reconciliationStatusBadge(record.reconciliationStatus)
            }

            // Peer & ID Metadata
            HStack {
                Text("Peer: \(record.receivedFromPeer) · ID: \(packet.paymentId.prefix(12))…")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                    .lineLimit(1)

                Spacer()

                Text(record.receivedAt.isoString)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
            }

            if packet.isAllowanceBacked, let spend = packet.allowanceSpend {
                HStack(spacing: 6) {
                    Image(systemName: "banknote.fill").foregroundColor(DesignTokens.Colors.meshGold).font(.system(size: 9))
                    Text("ALLOWANCE-BACKED SPEND · Seq #\(spend.sequenceNumber) · Cum: ₹\(String(format: "%.2f", spend.cumulativeSpentDouble))")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(DesignTokens.Colors.meshGold)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(DesignTokens.Colors.meshGold.opacity(0.15)))
            }

            // Trust & Cryptographic Status Breakdown
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: record.isSignatureMathematicallyValid ? "checkmark.shield.fill" : "xmark.shield.fill")
                        .font(.system(size: 10))
                        .foregroundColor(record.isSignatureMathematicallyValid ? DesignTokens.Colors.primary : DesignTokens.Colors.error)
                    Text(record.isSignatureMathematicallyValid ? "Signature: Mathematically Valid" : "Signature Invalid")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(record.isSignatureMathematicallyValid ? DesignTokens.Colors.primary : DesignTokens.Colors.error)

                    Text("·")
                        .foregroundColor(DesignTokens.Colors.onSurfaceVariant)

                    Text("Signer: \(packet.deviceId.prefix(12))…")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                }

                reconciliationStatusExplanation(record.reconciliationStatus)
            }

            // Failure Reason if status is FAILED
            if record.reconciliationStatus == .failed, let reason = record.failureReason, !reason.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "xmark.octagon.fill")
                        .font(.system(size: 11))
                        .foregroundColor(DesignTokens.Colors.error)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Terminal Rejection")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(DesignTokens.Colors.error)
                        Text(reason)
                            .font(.system(size: 9))
                            .foregroundColor(DesignTokens.Colors.onSurface)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(DesignTokens.Colors.error.opacity(0.12))
                )
            }

            // Reconciliation Actions
            if record.reconciliationStatus == .received || record.reconciliationStatus == .pendingReconciliation {
                Button {
                    Task {
                        await reconcileReceivedPacket(paymentId: record.id)
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isReconciling {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: DesignTokens.Colors.onPrimary))
                                .scaleEffect(0.7)
                            Text("Reconciling with Bridge…")
                                .font(.system(size: 11, weight: .semibold))
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                                .font(.system(size: 12))
                            Text("Reconcile with Bridge")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .foregroundColor(DesignTokens.Colors.onPrimary)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isReconciling ? DesignTokens.Colors.primary.opacity(0.5) : DesignTokens.Colors.primary)
                    )
                }
                .disabled(isReconciling)
                .padding(.top, 2)
            } else if record.reconciliationStatus == .settling {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Confirmation pending or previous attempt dropped. Tap to re-check ledger or retry submission.")
                        .font(.system(size: 9))
                        .foregroundColor(DesignTokens.Colors.secondary)

                    Button {
                        Task {
                            await reconcileReceivedPacket(paymentId: record.id)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isReconciling {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: DesignTokens.Colors.onSecondary))
                                    .scaleEffect(0.7)
                                Text("Verifying with Bridge…")
                                    .font(.system(size: 11, weight: .semibold))
                            } else {
                                Image(systemName: "arrow.clockwise.circle.fill")
                                    .font(.system(size: 12))
                                Text("Retry Settlement Verification")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .foregroundColor(DesignTokens.Colors.onSecondary)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isReconciling ? DesignTokens.Colors.secondary.opacity(0.5) : DesignTokens.Colors.secondary)
                        )
                    }
                    .disabled(isReconciling)
                }
                .padding(.top, 2)
            } else if record.reconciliationStatus == .settled {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12))
                        .foregroundColor(DesignTokens.Colors.primary)
                    Text("Settled on Authoritative Ledger · Balance Credited")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DesignTokens.Colors.primary)
                }
                .padding(.vertical, 2)
            } else if record.reconciliationStatus == .failed {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.seal.fill")
                        .font(.system(size: 12))
                        .foregroundColor(DesignTokens.Colors.error)
                    Text("Settlement Rejected · Unsettled")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DesignTokens.Colors.error)
                }
                .padding(.vertical, 2)
            }

            // Outcome banner for immediate interactive feedback
            if let outcome = outcome {
                reconciliationOutcomeBanner(outcome, record: record)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.base)
                .fill(DesignTokens.Colors.surfaceContainerLow.opacity(0.8))
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.base).stroke(DesignTokens.Colors.glassStrokeDim, lineWidth: 1))
        )
    }

    private func packetStatusColor(_ status: OfflinePacketStatus) -> Color {
        switch status {
        case .created:
            return Color.cyan
        case .queued:
            return DesignTokens.Colors.meshGold
        case .sent:
            return DesignTokens.Colors.secondary
        case .received:
            return Color(red: 0.95, green: 0.65, blue: 0.1)
        case .settled:
            return DesignTokens.Colors.primary
        case .failed:
            return DesignTokens.Colors.error
        }
    }

    @ViewBuilder
    private func reconciliationStatusBadge(_ status: ReceivedReconciliationStatus) -> some View {
        switch status {
        case .received, .pendingReconciliation:
            HStack(spacing: 4) {
                Circle()
                    .fill(Color(red: 0.95, green: 0.65, blue: 0.1))
                    .frame(width: 6, height: 6)
                Text(status == .pendingReconciliation ? "PENDING RECONCILIATION — NOT SETTLED" : "RECEIVED — NOT SETTLED")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color(red: 0.95, green: 0.65, blue: 0.1))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color(red: 0.95, green: 0.65, blue: 0.1).opacity(0.18)))

        case .settling:
            HStack(spacing: 4) {
                Circle()
                    .fill(DesignTokens.Colors.secondary)
                    .frame(width: 6, height: 6)
                Text("SETTLING — CONFIRMATION PENDING")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(DesignTokens.Colors.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(DesignTokens.Colors.secondary.opacity(0.18)))

        case .settled:
            HStack(spacing: 4) {
                Circle()
                    .fill(DesignTokens.Colors.primary)
                    .frame(width: 6, height: 6)
                Text("SETTLED ON LEDGER")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(DesignTokens.Colors.primary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(DesignTokens.Colors.primary.opacity(0.18)))

        case .failed:
            HStack(spacing: 4) {
                Circle()
                    .fill(DesignTokens.Colors.error)
                    .frame(width: 6, height: 6)
                Text("FAILED — NOT SETTLED")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(DesignTokens.Colors.error)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(DesignTokens.Colors.error.opacity(0.18)))
        }
    }

    @ViewBuilder
    private func reconciliationStatusExplanation(_ status: ReceivedReconciliationStatus) -> some View {
        switch status {
        case .received, .pendingReconciliation:
            Text("Held in local inbox. Does not update account balance until submitted to bridge.")
                .font(.system(size: 9))
                .foregroundColor(DesignTokens.Colors.onSurfaceVariant.opacity(0.8))
        case .settling:
            Text("In-flight or interrupted. Awaiting authoritative ledger proof. Safe to retry check.")
                .font(.system(size: 9))
                .foregroundColor(DesignTokens.Colors.secondary.opacity(0.9))
        case .settled:
            Text("Confirmed on double-entry ledger. Account balance updated.")
                .font(.system(size: 9))
                .foregroundColor(DesignTokens.Colors.primary.opacity(0.9))
        case .failed:
            Text("Terminal rejection confirmed by bank bridge. Not credited.")
                .font(.system(size: 9))
                .foregroundColor(DesignTokens.Colors.error.opacity(0.9))
        }
    }

    @ViewBuilder
    private func reconciliationOutcomeBanner(_ outcome: ReconciliationOutcome, record: ReceivedPacketRecord) -> some View {
        switch outcome {
        case .settled(_, let result):
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(DesignTokens.Colors.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Settlement Confirmed")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(DesignTokens.Colors.primary)
                    Text("₹\(CurrencyFormatter.format(amount: record.packet.amountDouble)) settled on ledger. Ref: \(result.paymentId.prefix(12))…")
                        .font(.system(size: 9))
                        .foregroundColor(DesignTokens.Colors.onSurface)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(DesignTokens.Colors.primary.opacity(0.12)))

        case .rejected(_, let reason):
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(DesignTokens.Colors.error)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reconciliation Rejected")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(DesignTokens.Colors.error)
                    Text(reason)
                        .font(.system(size: 9))
                        .foregroundColor(DesignTokens.Colors.onSurface)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(DesignTokens.Colors.error.opacity(0.12)))

        case .retryable(_, let reason):
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Color(red: 0.95, green: 0.65, blue: 0.1))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Retryable / Ambiguous Result")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(red: 0.95, green: 0.65, blue: 0.1))
                    Text(reason)
                        .font(.system(size: 9))
                        .foregroundColor(DesignTokens.Colors.onSurface)
                    Text("Bridge host: \(APIConfiguration.shared.baseURL.absoluteString). Record kept in SETTLING.")
                        .font(.system(size: 8))
                        .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.95, green: 0.65, blue: 0.1).opacity(0.12)))

        case .invalidState(_, let currentStatus, let reason):
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(DesignTokens.Colors.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Action Ineligible (\(currentStatus.rawValue))")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(DesignTokens.Colors.secondary)
                    Text(reason)
                        .font(.system(size: 9))
                        .foregroundColor(DesignTokens.Colors.onSurface)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(DesignTokens.Colors.secondary.opacity(0.12)))
        }
    }

    @MainActor
    private func reloadReceivedPackets() {
        self.receivedPackets = ReceivedPacketStore.shared.getAll()
    }

    @MainActor
    private func reconcileReceivedPacket(paymentId: String) async {
        guard !reconcilingPaymentIds.contains(paymentId) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            reconcilingPaymentIds.insert(paymentId)
        }

        let outcome = await reconciliationService.reconcile(paymentId: paymentId)

        withAnimation(.easeInOut(duration: 0.25)) {
            reconcilingPaymentIds.remove(paymentId)
            lastReconciliationOutcome[paymentId] = outcome
            reloadReceivedPackets()
        }

        if case .settled = outcome {
            NotificationCenter.default.post(name: .meshAccountsUpdated, object: nil)
        }
    }

    // MARK: - Actions

    @MainActor
    private func createOfflinePacketAction() async {
        guard offlineCreationState != .creating else { return }

        guard amount > 0 else {
            withAnimation(.easeInOut(duration: 0.2)) {
                offlineCreationState = .failed("Transfer amount must be strictly greater than zero.")
            }
            return
        }
        guard senderId.caseInsensitiveCompare(recipientId) != .orderedSame else {
            withAnimation(.easeInOut(duration: 0.2)) {
                offlineCreationState = .failed("Sender and recipient accounts must be different.")
            }
            return
        }

        // Branch: Allowance-backed offline spending
        if useAllowance {
            guard let voucher = activeAllowance else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    offlineCreationState = .failed("No active allowance voucher found.")
                }
                return
            }

            let decAmount = Decimal(string: String(format: "%.2f", amount)) ?? Decimal(amount)
            if decAmount > voucher.remainingAmount {
                withAnimation(.easeInOut(duration: 0.2)) {
                    offlineCreationState = .failed("Requested amount (₹\(String(format: "%.2f", amount))) exceeds remaining allowance of ₹\(voucher.remainingAmount).")
                }
                return
            }

            withAnimation(.easeInOut(duration: 0.2)) {
                offlineCreationState = .creating
            }

            do {
                let packet = try OfflineAllowanceManager.shared.createAndQueueAllowanceSpend(
                    toAccount: recipientId,
                    amount: decAmount,
                    memo: memo
                )
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    offlineCreationState = .created(packet)
                    selectedPacketForTransfer = packet
                }
                reloadQueuedPackets()
                reloadActiveAllowance()
            } catch {
                withAnimation(.easeInOut(duration: 0.2)) {
                    offlineCreationState = .failed(error.localizedDescription)
                }
            }
            return
        }

        // Legacy offline packet creation
        withAnimation(.easeInOut(duration: 0.2)) {
            offlineCreationState = .creating
        }

        do {
            let packet = try OfflinePaymentService.shared.createAndQueueOfflinePayment(
                fromAccount: senderId,
                toAccount: recipientId,
                amount: amount,
                memo: memo
            )

            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                offlineCreationState = .created(packet)
                selectedPacketForTransfer = packet
            }
            reloadQueuedPackets()
        } catch {
            withAnimation(.easeInOut(duration: 0.2)) {
                offlineCreationState = .failed(error.localizedDescription)
            }
        }
    }

    @MainActor
    private func reloadQueuedPackets() {
        self.queuedPackets = OfflinePaymentService.shared.getQueuedPackets()
    }

    @MainActor
    private func reloadActiveAllowance() {
        self.activeAllowance = OfflineAllowanceManager.shared.getActiveVoucher()
        if let voucher = self.activeAllowance, !voucher.isExpired() {
            self.useAllowance = true
        }
    }

    @MainActor
    private func executeMeshPayment() async {
        guard submissionState != .submitting else { return }

        guard amount > 0 else {
            submissionState = .failed("Transfer amount must be strictly greater than zero.")
            return
        }
        guard senderId.caseInsensitiveCompare(recipientId) != .orderedSame else {
            submissionState = .failed("Sender and recipient accounts must be different.")
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            submissionState = .submitting
        }

        do {
            // 1. Obtain local device identity with hardware-backed RSA key
            let identity = try DeviceIdentityManager.shared.getOrCreateIdentity()

            // 2. Construct canonical PaymentInstruction
            let instruction = try PaymentInstruction.create(
                fromAccount: senderId,
                toAccount: recipientId,
                amountDouble: amount
            )

            // 3. Digitally sign the exact canonical UTF-8 bytes using device's private key
            let canonicalBytes = instruction.toCanonicalBytes()
            let signatureBase64 = try DeviceIdentityManager.shared.signBase64(message: canonicalBytes)

            // 4. Attach signature to instruction
            let signedInstruction = try instruction.withSignature(signatureBase64)

            // 5. Submit signed instruction via structured API path (POST /api/mesh/submit)
            let result = try await UPIMeshAPIClient.shared.submitSignedMeshPayment(
                instruction: signedInstruction,
                deviceId: identity.deviceId
            )

            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                submissionState = .settled(result)
            }

            // Immediately refresh local sender balance
            await loadSenderBalance()

            // Broadcast notification so MeshWalletsView and other views refresh their live state
            NotificationCenter.default.post(name: .meshAccountsUpdated, object: nil)
        } catch {
            withAnimation(.easeInOut(duration: 0.2)) {
                submissionState = .failed(error.localizedDescription)
            }
        }
    }

    @MainActor
    private func loadSenderBalance() async {
        do {
            let accounts = try await UPIMeshAPIClient.shared.fetchAccounts()
            if let alice = accounts.first(where: { $0.id.caseInsensitiveCompare(senderId) == .orderedSame }) {
                self.senderBalance = alice.balance
                self.isLiveBalance = true
            }
        } catch {
            self.isLiveBalance = false
        }
    }
}
