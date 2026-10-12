import SwiftUI

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

    @State private var amount: Double = 500.00
    @State private var memo: String = "Lunch payment (Offline)"
    @State private var senderId: String = "alice"
    @State private var recipientId: String = "bob"
    @State private var submissionState: PaymentSubmissionState = .idle
    @State private var showQRModal: Bool = false
    @State private var senderBalance: Double? = nil
    @State private var isLiveBalance: Bool = false

    public init() {}

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

                // Bottom spacer for detached floating tab bar
                Spacer(minLength: 88)
            }
            .padding(.horizontal, DesignTokens.Spacing.margin)
            .padding(.top, 8)
        }
        .task {
            await loadSenderBalance()
        }
        .refreshable {
            await loadSenderBalance()
        }
        .onReceive(NotificationCenter.default.publisher(for: .meshAccountsUpdated)) { _ in
            Task {
                await loadSenderBalance()
            }
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
                        Text("Simulating Mesh Ingestion...")
                            .font(DesignTokens.Typography.headlineSm)
                            .fontWeight(.bold)

                    case .settled:
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20, weight: .bold))
                        Text("Settled on Bridge Ledger!")
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
                    // Step 1: Authenticated Sender (Alice)
                    journeyStepRow(
                        stepNumber: "1",
                        title: "1. Authenticated Sender (\(result.fromAccount.capitalized))",
                        subtitle: "RSA-PSS signed · Verified against SenderKeyRegistry",
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
                        title: "1. Authenticate Sender (Alice)",
                        subtitle: "RSA-PSS signing in backend simulation",
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

    // MARK: - Actions

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
            let result = try await UPIMeshAPIClient.shared.submitMeshTransfer(
                from: senderId,
                to: recipientId,
                amount: amount,
                ttl: 5
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
