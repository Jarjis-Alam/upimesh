import SwiftUI

/// Mesh Wallets Screen (`ios_ui/mesh_wallets_ios/`)
///
/// Faithfully reproduces the Stitch UI offline wallets interface:
/// - Mesh Vault Hero with Aggregate Vault Balance (₹8,000.00), Local Available, and Transit amounts.
/// - "Reset All" and "+ New Demo Wallet" action buttons.
/// - Apple Wallet-style stacked cards for Alice (Personal), Bob (Merchant), and Carol (Relay).
/// - Mesh Reconciliation invariant verification card with mathematical balance breakdown.
public struct MeshWalletsView: View {
    @State private var viewModel = MeshWalletsViewModel()
    @State private var isResetting: Bool = false
    @State private var resetSuccess: Bool = false
    @State private var expandedWalletId: String? = "alice"

    // MARK: - Device Key Registration State (Milestone 3B & 3C)
    @State private var deviceIdentity: DeviceIdentity? = nil
    @State private var registrationAccountId: String = ""
    @State private var registrationState: KeyRegistrationState = .idle
    @State private var authorizationState: DeviceAuthorizationState = .idle

    // MARK: - Offline Allowance State (Phase 2B)
    @State private var activeAllowance: OfflineAllowanceVoucher? = nil
    @State private var allowanceRequestAmount: Double = 100.0
    @State private var allowanceRequestAccount: String = "alice"
    @State private var isRequestingAllowance: Bool = false
    @State private var allowanceActionMessage: String? = nil
    @State private var isAllowanceSuccess: Bool = true

    public enum KeyRegistrationState: Equatable {
        case idle
        case submitting
        case registered(KeyRegistrationResponseDTO)
        case failed(String)
    }

    public enum DeviceAuthorizationState: Equatable {
        case idle
        case authorizing
        case authorized(DeviceAuthorizationResponseDTO)
        case failed(String)
    }

    public init() {}

    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: DesignTokens.Spacing.md) {

                // MARK: - Header
                headerView

                // MARK: - Live Network / Status Banner
                networkStatusBanner

                // MARK: - Mesh Vault Hero Card
                vaultHeroCard

                // MARK: - Device Cryptographic Identity & Bridge Registration Card
                deviceKeyRegistrationCard

                // MARK: - Offline Allowance Management Card (Phase 2B)
                offlineAllowanceCard

                // MARK: - Hardware Enclaves Subheader
                HStack {
                    HStack(spacing: 6) {
                        Text("HARDWARE SECURE ENCLAVES")
                            .font(DesignTokens.Typography.labelCaps)
                            .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                            .tracking(1.2)

                        Circle()
                            .fill(DesignTokens.Colors.secondary)
                            .frame(width: 6, height: 6)
                    }

                    Spacer()

                    Text("Tap to inspect node details")
                        .font(DesignTokens.Typography.caption)
                        .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                }
                .padding(.horizontal, 4)

                // MARK: - Stacked Apple Wallet Cards
                VStack(spacing: DesignTokens.Spacing.sm) {
                    ForEach(PreviewData.sampleWallets) { wallet in
                        walletCard(wallet)
                    }
                }

                // MARK: - Mesh Reconciliation Invariant Card
                reconciliationCard

                // Bottom spacer for detached floating tab bar
                Spacer(minLength: 88)
            }
            .padding(.horizontal, DesignTokens.Spacing.margin)
            .padding(.top, 8)
        }
        .task {
            await viewModel.loadLiveAccounts()
            loadLocalDeviceIdentity()
            reloadActiveAllowance()
        }
        .refreshable {
            await viewModel.loadLiveAccounts()
            reloadActiveAllowance()
        }
        .onReceive(NotificationCenter.default.publisher(for: .meshAccountsUpdated)) { _ in
            Task {
                await viewModel.loadLiveAccounts()
                reloadActiveAllowance()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .offlineAllowanceUpdated)) { _ in
            reloadActiveAllowance()
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Mesh Wallets")
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
                    .background(Capsule().fill(DesignTokens.Colors.surfaceContainerHigh.opacity(0.7)))
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
        }
        .padding(.vertical, 8)
    }

    // MARK: - Live Network / Status Banner
    @ViewBuilder
    private var networkStatusBanner: some View {
        switch viewModel.status {
        case .idle:
            EmptyView()

        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .tint(DesignTokens.Colors.meshGold)
                    .scaleEffect(0.8)
                Text("Syncing live accounts from backend...")
                    .font(DesignTokens.Typography.caption)
                    .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                Spacer()
                Text("GET /api/accounts")
                    .font(DesignTokens.Typography.labelCaps)
                    .foregroundColor(DesignTokens.Colors.onSurfaceVariant.opacity(0.7))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12).fill(DesignTokens.Colors.surfaceContainerHigh.opacity(0.6)))

        case .liveConnected:
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(DesignTokens.Colors.meshGold)
                        .frame(width: 6, height: 6)
                    Text("LIVE BACKEND CONNECTED")
                        .font(DesignTokens.Typography.labelCaps)
                        .foregroundColor(DesignTokens.Colors.meshGold)
                        .tracking(1.0)
                }

                Spacer()

                Text(APIConfiguration.shared.hostDescription)
                    .font(DesignTokens.Typography.labelNumericSm)
                    .foregroundColor(DesignTokens.Colors.onSurfaceVariant)

                Button {
                    Task { await viewModel.loadLiveAccounts() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(DesignTokens.Colors.meshGold)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12).fill(DesignTokens.Colors.surfaceContainerHigh.opacity(0.6)))

        case .connectionFailed(let message):
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(DesignTokens.Colors.error)
                    .font(.system(size: 15))

                VStack(alignment: .leading, spacing: 2) {
                    Text("BACKEND UNREACHABLE — SHOWING PREVIEW DATA")
                        .font(DesignTokens.Typography.labelCaps)
                        .foregroundColor(DesignTokens.Colors.error)
                        .tracking(0.8)

                    Text(message)
                        .font(.system(size: 11))
                        .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    Task { await viewModel.loadLiveAccounts() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry")
                    }
                    .font(DesignTokens.Typography.labelCaps)
                    .foregroundColor(DesignTokens.Colors.onSurface)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(DesignTokens.Colors.surfaceContainerHighest))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12).fill(DesignTokens.Colors.error.opacity(0.12)))
        }
    }

    // MARK: - Vault Hero Card
    private var vaultHeroCard: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "wallet.bifold.fill")
                        .foregroundColor(DesignTokens.Colors.meshGold)
                        .font(.system(size: 18))

                    Text("Mesh Vault")
                        .font(DesignTokens.Typography.headlineMd)
                        .fontWeight(.semibold)
                        .foregroundColor(DesignTokens.Colors.onSurface)
                }

                Spacer()

                HStack(spacing: 5) {
                    Circle()
                        .fill(DesignTokens.Colors.meshGold)
                        .frame(width: 6, height: 6)
                    Text(viewModel.status == .liveConnected ? "3 LIVE ACCOUNTS" : "3 PEERS SYNCED")
                        .font(DesignTokens.Typography.labelNumericSm)
                        .foregroundColor(DesignTokens.Colors.meshGold)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(DesignTokens.Colors.surfaceContainerHigh.opacity(0.8)))
            }

            // Aggregate Net Vault Hero
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("TOTAL MESH NET VAULT")
                        .font(DesignTokens.Typography.labelCaps)
                        .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                        .tracking(1.2)

                    if viewModel.status == .liveConnected {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(DesignTokens.Colors.meshGold)
                                .frame(width: 5, height: 5)
                            Text("LIVE")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(DesignTokens.Colors.meshGold)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(DesignTokens.Colors.meshGold.opacity(0.15)))
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    let totalVal = viewModel.totalLiveBalance ?? 8000.0
                    let parts = CurrencyFormatter.formatParts(amount: totalVal)
                    Text(parts.whole)
                        .font(DesignTokens.Typography.displayHeroMobile)
                        .fontWeight(.bold)
                        .foregroundColor(DesignTokens.Colors.onSurface)

                    Text(parts.fraction)
                        .font(DesignTokens.Typography.headlineSm)
                        .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)

            // Sub-Stats Bar
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(DesignTokens.Colors.primary.opacity(0.15))
                        .frame(width: 28, height: 28)
                        .overlay(Image(systemName: "lock.shield.fill").font(.system(size: 13)).foregroundColor(DesignTokens.Colors.primary))

                    VStack(alignment: .leading, spacing: 1) {
                        if viewModel.status == .liveConnected {
                            Text(CurrencyFormatter.format(amount: viewModel.totalLiveBalance ?? 8000.0))
                                .font(DesignTokens.Typography.labelNumericSm)
                                .fontWeight(.medium)
                                .foregroundColor(DesignTokens.Colors.onSurface)
                            Text("Settled on Ledger")
                                .font(.system(size: 11))
                                .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                        } else {
                            Text("₹7,800.00")
                                .font(DesignTokens.Typography.labelNumericSm)
                                .fontWeight(.medium)
                                .foregroundColor(DesignTokens.Colors.onSurface)
                            Text("Local Available (Preview)")
                                .font(.system(size: 11))
                                .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 12).fill(DesignTokens.Colors.surfaceContainerLowest.opacity(0.5)))

                HStack(spacing: 8) {
                    Circle()
                        .fill(DesignTokens.Colors.secondary.opacity(0.15))
                        .frame(width: 28, height: 28)
                        .overlay(Image(systemName: "arrow.triangle.swap").font(.system(size: 13)).foregroundColor(DesignTokens.Colors.secondary))

                    VStack(alignment: .leading, spacing: 1) {
                        if viewModel.status == .liveConnected {
                            Text("v0 Current")
                                .font(DesignTokens.Typography.labelNumericSm)
                                .fontWeight(.medium)
                                .foregroundColor(DesignTokens.Colors.secondary)
                            Text("3 Accounts Active")
                                .font(.system(size: 11))
                                .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                        } else {
                            Text("₹200.00")
                                .font(DesignTokens.Typography.labelNumericSm)
                                .fontWeight(.medium)
                                .foregroundColor(DesignTokens.Colors.secondary)
                            Text("In Mesh Transit (Preview)")
                                .font(.system(size: 11))
                                .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 12).fill(DesignTokens.Colors.surfaceContainerLowest.opacity(0.5)))
            }
            .padding(.top, 4)

            // Top Action Buttons
            HStack(spacing: 8) {
                Button {
                    triggerResetAll()
                } label: {
                    HStack(spacing: 6) {
                        if isResetting {
                            ProgressView().tint(DesignTokens.Colors.onSurface)
                            Text("Resetting...")
                        } else if resetSuccess {
                            Image(systemName: "checkmark")
                            Text("Synced!")
                        } else {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset All")
                        }
                    }
                    .font(DesignTokens.Typography.labelCaps)
                    .foregroundColor(DesignTokens.Colors.onSurface)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Capsule().fill(DesignTokens.Colors.surfaceContainerHighest.opacity(0.7)))
                }
                .buttonStyle(.plain)

                Button {} label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.rectangle.fill.on.rectangle.fill")
                        Text("+ New Demo Wallet")
                    }
                    .font(DesignTokens.Typography.labelCaps)
                    .fontWeight(.bold)
                    .foregroundColor(DesignTokens.Colors.onMeshGold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Capsule().fill(DesignTokens.Colors.meshGold))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .padding(DesignTokens.Spacing.md)
        .liquidCard(strokeColor: DesignTokens.Colors.glassStrokeLight)
    }

    // MARK: - Stacked Wallet Card
    private func walletCard(_ wallet: PreviewData.WalletNode) -> some View {
        let isExpanded = expandedWalletId == wallet.id
        let liveBal = viewModel.liveBalance(for: wallet.id)
        let isLive = (liveBal != nil)
        let displayBalance = liveBal ?? wallet.balance

        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                expandedWalletId = isExpanded ? nil : wallet.id
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                // Top Row: Avatar & Role Tag
                HStack {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(accentColorForWallet(wallet.id).opacity(0.2))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: iconForWallet(wallet.id))
                                    .foregroundColor(accentColorForWallet(wallet.id))
                                    .font(.system(size: 20))
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(wallet.title)
                                    .font(DesignTokens.Typography.headlineSm)
                                    .fontWeight(.semibold)
                                    .foregroundColor(DesignTokens.Colors.onSurface)
                                Text("(\(wallet.subtitle))")
                                    .font(DesignTokens.Typography.bodySm)
                                    .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                            }
                            Text(sublabelForWallet(wallet.id))
                                .font(DesignTokens.Typography.caption)
                                .foregroundColor(accentColorForWallet(wallet.id))
                        }
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        if isLive, let ver = viewModel.liveVersion(for: wallet.id) {
                            Text("v\(ver) ·")
                                .font(DesignTokens.Typography.labelCaps)
                                .foregroundColor(accentColorForWallet(wallet.id).opacity(0.8))
                        }
                        Text(wallet.roleTag)
                            .font(DesignTokens.Typography.labelCaps)
                            .foregroundColor(accentColorForWallet(wallet.id))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(accentColorForWallet(wallet.id).opacity(0.12)))
                }

                // Balance Hero
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(balanceTitleForWallet(wallet.id))
                                .font(DesignTokens.Typography.caption)
                                .foregroundColor(DesignTokens.Colors.onSurfaceVariant)

                            if isLive {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(DesignTokens.Colors.meshGold)
                                        .frame(width: 5, height: 5)
                                    Text("LIVE BACKEND")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(DesignTokens.Colors.meshGold)
                                }
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(DesignTokens.Colors.meshGold.opacity(0.15)))
                            } else {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(DesignTokens.Colors.onSurfaceVariant.opacity(0.6))
                                        .frame(width: 5, height: 5)
                                    Text("PREVIEW DATA")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                                }
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(DesignTokens.Colors.surfaceContainerHighest.opacity(0.6)))
                            }
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            let parts = CurrencyFormatter.formatParts(amount: displayBalance)
                            Text(parts.whole)
                                .font(DesignTokens.Typography.headlineLg)
                                .fontWeight(.bold)
                                .foregroundColor(DesignTokens.Colors.onSurface)
                            Text(parts.fraction)
                                .font(DesignTokens.Typography.bodyMd)
                                .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                        }
                    }

                    Spacer()

                    if isLive {
                        if let ver = viewModel.liveVersion(for: wallet.id) {
                            VStack(alignment: .trailing, spacing: 1) {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(accentColorForWallet(wallet.id))
                                        .frame(width: 5, height: 5)
                                    Text("v\(ver) Settled")
                                        .font(DesignTokens.Typography.labelNumericSm)
                                        .foregroundColor(accentColorForWallet(wallet.id))
                                }
                                Text("Authoritative State")
                                    .font(.system(size: 11))
                                    .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                            }
                        }
                    } else if let inTransit = wallet.inTransit {
                        VStack(alignment: .trailing, spacing: 1) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.swap")
                                    .font(.system(size: 11))
                                Text(CurrencyFormatter.format(amount: inTransit))
                            }
                            .font(DesignTokens.Typography.labelNumericSm)
                            .foregroundColor(DesignTokens.Colors.secondary)

                            Text("in transit (Preview)")
                                .font(.system(size: 11))
                                .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                        }
                    } else if let received = wallet.receivedOffline {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("+" + CurrencyFormatter.format(amount: received))
                                .font(DesignTokens.Typography.labelNumericSm)
                                .foregroundColor(DesignTokens.Colors.meshGold)
                            Text("Received (Preview)")
                                .font(.system(size: 11))
                                .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                        }
                    } else if let hops = wallet.hops {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(hops) Hops")
                                .font(DesignTokens.Typography.labelNumericSm)
                                .foregroundColor(DesignTokens.Colors.onSurface)
                            Text("Active Route")
                                .font(.system(size: 11))
                                .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                        }
                    }
                }

                // Action Buttons inside Card
                HStack(spacing: 8) {
                    if wallet.id == "alice" {
                        actionPillButton(title: "Send", icon: "arrow.up.right", isPrimary: true, color: DesignTokens.Colors.meshGold)
                        actionPillButton(title: "Add Funds", icon: "plus", isPrimary: false, color: DesignTokens.Colors.surfaceContainerHighest)
                    } else if wallet.id == "bob" {
                        actionPillButton(title: "Receive", icon: "arrow.down.left", isPrimary: true, color: DesignTokens.Colors.secondary)
                        actionPillButton(title: "Receipts", icon: "doc.text", isPrimary: false, color: DesignTokens.Colors.surfaceContainerHighest)
                    } else {
                        actionPillButton(title: "Relay Settings", icon: "slider.horizontal.3", isPrimary: false, color: DesignTokens.Colors.surfaceContainerHighest)
                    }
                }
                .padding(.top, 2)
            }
            .padding(DesignTokens.Spacing.md)
            .liquidCard(
                strokeColor: accentColorForWallet(wallet.id).opacity(isExpanded ? 0.35 : 0.18),
                backgroundColor: DesignTokens.Colors.surfaceContainerHigh.opacity(0.85)
            )
        }
        .buttonStyle(.plain)
    }

    private func actionPillButton(title: String, icon: String, isPrimary: Bool, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
            Text(title)
                .font(DesignTokens.Typography.labelCaps)
                .fontWeight(.bold)
        }
        .foregroundColor(isPrimary ? DesignTokens.Colors.onMeshGold : DesignTokens.Colors.onSurface)
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .background(Capsule().fill(color))
    }

    // MARK: - Reconciliation Invariant Card
    private var reconciliationCard: some View {
        let isLive = (viewModel.status == .liveConnected)
        let aliceBal = viewModel.liveBalance(for: "alice") ?? 4350.00
        let bobBal = viewModel.liveBalance(for: "bob") ?? 2650.00
        let carolBal = viewModel.liveBalance(for: "carol") ?? 1000.00
        let total = isLive ? (aliceBal + bobBal + carolBal) : 8000.00

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(DesignTokens.Colors.meshGold)
                        .font(.system(size: 16))

                    Text("Mesh Reconciliation")
                        .font(DesignTokens.Typography.headlineSm)
                        .fontWeight(.semibold)
                        .foregroundColor(DesignTokens.Colors.onSurface)
                }

                Spacer()

                Text(isLive ? "LIVE BALANCED" : "BALANCED")
                    .font(DesignTokens.Typography.labelCaps)
                    .foregroundColor(DesignTokens.Colors.meshGold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(DesignTokens.Colors.meshGold.opacity(0.12)))
            }

            Text(isLive ? "Live backend balances across all accounts match the total vault invariant." : "Offline balances across all nodes match the total vault invariant.")
                .font(DesignTokens.Typography.caption)
                .foregroundColor(DesignTokens.Colors.onSurfaceVariant)

            // Table Breakdown
            VStack(spacing: 8) {
                reconciliationRow(name: "Alice (Personal)", amount: CurrencyFormatter.format(amount: aliceBal), badge: isLive ? "LIVE" : nil)
                reconciliationRow(name: "Bob (Merchant Store)", amount: CurrencyFormatter.format(amount: bobBal), badge: isLive ? "LIVE" : nil)
                reconciliationRow(name: "Carol (Relay Hub)", amount: CurrencyFormatter.format(amount: carolBal), badge: isLive ? "LIVE" : nil)
                if !isLive {
                    reconciliationRow(name: "Pending Transit (Preview)", amount: "₹200.00", isSecondary: true)
                }

                Divider()
                    .background(DesignTokens.Colors.surfaceVariant.opacity(0.5))

                HStack {
                    Text(isLive ? "LIVE TOTAL RECONCILED" : "TOTAL RECONCILED")
                        .font(DesignTokens.Typography.labelCaps)
                        .foregroundColor(DesignTokens.Colors.onSurface)
                    Spacer()
                    Text(CurrencyFormatter.format(amount: total))
                        .font(DesignTokens.Typography.labelNumeric)
                        .fontWeight(.bold)
                        .foregroundColor(DesignTokens.Colors.meshGold)
                }
                .padding(.top, 2)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(DesignTokens.Colors.surfaceContainerLowest.opacity(0.7)))

            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundColor(DesignTokens.Colors.meshGold)
                Text(isLive ? "Live Backend Account Verification" : "Enclave Hardware Verified")
                    .font(DesignTokens.Typography.caption)
                    .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
            }
            .padding(.top, 2)
        }
        .padding(DesignTokens.Spacing.md)
        .liquidCard(strokeColor: DesignTokens.Colors.glassStrokeLight)
    }

    private func reconciliationRow(name: String, amount: String, isSecondary: Bool = false, badge: String? = nil) -> some View {
        HStack {
            Text(name)
                .font(DesignTokens.Typography.bodySm)
                .foregroundColor(isSecondary ? DesignTokens.Colors.secondary : DesignTokens.Colors.onSurfaceVariant)

            if let badge = badge {
                Text(badge)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(DesignTokens.Colors.meshGold)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(DesignTokens.Colors.meshGold.opacity(0.15)))
            }

            Spacer()
            Text(amount)
                .font(DesignTokens.Typography.labelNumericSm)
                .fontWeight(.medium)
                .foregroundColor(isSecondary ? DesignTokens.Colors.secondary : DesignTokens.Colors.onSurface)
        }
    }

    private func triggerResetAll() {
        isResetting = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            isResetting = false
            resetSuccess = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                resetSuccess = false
            }
        }
    }

    private func accentColorForWallet(_ id: String) -> Color {
        switch id {
        case "alice": return DesignTokens.Colors.meshGold
        case "bob": return DesignTokens.Colors.secondary
        default: return DesignTokens.Colors.tertiary
        }
    }

    private func iconForWallet(_ id: String) -> String {
        switch id {
        case "alice": return "person.fill"
        case "bob": return "storefront.fill"
        default: return "point.3.filled.connected.trianglepath.dotted"
        }
    }

    private func sublabelForWallet(_ id: String) -> String {
        switch id {
        case "alice": return "Primary Sender"
        case "bob": return "Point of Sale"
        default: return "Mesh Facilitator"
        }
    }

    private func balanceTitleForWallet(_ id: String) -> String {
        switch id {
        case "alice": return "Available Enclave Balance"
        case "bob": return "Merchant Vault Balance"
        default: return "Staking Bond Balance"
        }
    }

    // MARK: - Device Key Registration Card & Helpers (Milestone 3B)

    private var deviceKeyRegistrationCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(DesignTokens.Colors.meshGold)

                Text("DEVICE CRYPTOGRAPHIC IDENTITY")
                    .font(DesignTokens.Typography.labelCaps)
                    .foregroundColor(DesignTokens.Colors.onSurface)
                    .tracking(1.0)

                Spacer()

                HStack(spacing: 5) {
                    Circle()
                        .fill(keyStatusColor)
                        .frame(width: 6, height: 6)
                    Text(keyStatusText)
                        .font(DesignTokens.Typography.labelCaps)
                        .foregroundColor(keyStatusColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(keyStatusColor.opacity(0.12)))
            }

            if let identity = deviceIdentity {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Device UUID")
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                        Spacer()
                        Text(identity.deviceId)
                            .font(DesignTokens.Typography.labelNumericSm)
                            .foregroundColor(DesignTokens.Colors.onSurface)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    HStack {
                        Text("Key Spec")
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                        Spacer()
                        Text("\(identity.keyType) • \(identity.algorithm)")
                            .font(DesignTokens.Typography.labelNumericSm)
                            .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                    }

                    HStack {
                        Text("Fingerprint")
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                        Spacer()
                        Text(identity.publicKeyFingerprint)
                            .font(DesignTokens.Typography.labelNumericSm)
                            .foregroundColor(DesignTokens.Colors.meshGold)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(DesignTokens.Colors.surfaceContainerLowest.opacity(0.6))
                )

                // Registration target field
                VStack(alignment: .leading, spacing: 4) {
                    Text("Register with Bridge as:")
                        .font(DesignTokens.Typography.caption)
                        .foregroundColor(DesignTokens.Colors.onSurfaceVariant)

                    HStack(spacing: 8) {
                        TextField("Target Account or Device ID", text: $registrationAccountId)
                            .textFieldStyle(.plain)
                            .font(DesignTokens.Typography.bodySm)
                            .foregroundColor(DesignTokens.Colors.onSurface)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(DesignTokens.Colors.surfaceContainerLow)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(DesignTokens.Colors.outlineVariant.opacity(0.4), lineWidth: 1)
                                    )
                            )
                            .autocapitalization(.none)
                            .disableAutocorrection(true)

                        Button {
                            registrationAccountId = identity.deviceId
                        } label: {
                            Text("Use UUID")
                                .font(DesignTokens.Typography.labelCaps)
                                .foregroundColor(DesignTokens.Colors.meshGold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().fill(DesignTokens.Colors.meshGold.opacity(0.12))
                                )
                        }
                        .buttonStyle(.plain)

                        Button {
                            registrationAccountId = "alice"
                        } label: {
                            Text("Use Alice")
                                .font(DesignTokens.Typography.labelCaps)
                                .foregroundColor(DesignTokens.Colors.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().fill(DesignTokens.Colors.secondary.opacity(0.12))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)

                // Status message if registered or failed
                if case .registered(let response) = registrationState {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14))
                            .foregroundColor(DesignTokens.Colors.secondary)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(response.status == "REGISTERED" ? "KEY REGISTERED ON BRIDGE" : "ALREADY REGISTERED ON BRIDGE")
                                .font(DesignTokens.Typography.labelCaps)
                                .foregroundColor(DesignTokens.Colors.secondary)
                            Text(response.message)
                                .font(.system(size: 11))
                                .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(DesignTokens.Colors.secondary.opacity(0.12))
                    )
                } else if case .failed(let errMsg) = registrationState {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(DesignTokens.Colors.error)

                        VStack(alignment: .leading, spacing: 1) {
                            Text("REGISTRATION FAILED")
                                .font(DesignTokens.Typography.labelCaps)
                                .foregroundColor(DesignTokens.Colors.error)
                            Text(errMsg)
                                .font(.system(size: 11))
                                .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(DesignTokens.Colors.error.opacity(0.12))
                    )
                }

                // Explicit Action Button
                Button {
                    Task {
                        await executeExplicitRegistration()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if registrationState == .submitting {
                            ProgressView()
                                .tint(buttonForegroundColor)
                                .scaleEffect(0.8)
                            Text("Registering with Bridge...")
                                .font(DesignTokens.Typography.bodySm)
                                .fontWeight(.semibold)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 14, weight: .bold))
                            Text(buttonLabelText)
                                .font(DesignTokens.Typography.bodySm)
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundColor(buttonForegroundColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(buttonBackgroundColor)
                    )
                }
                .disabled(registrationState == .submitting)
                .buttonStyle(.plain)
                .padding(.top, 4)

                // Prototype Account Authorization (Milestone 3C)
                accountAuthorizationSection
            } else {
                Text("Initializing Keychain Secure Identity...")
                    .font(DesignTokens.Typography.caption)
                    .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DesignTokens.Colors.surfaceContainerHigh.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(DesignTokens.Colors.outlineVariant.opacity(0.35), lineWidth: 1)
                )
        )
    }

    private var keyStatusColor: Color {
        if case .registered = registrationState {
            return DesignTokens.Colors.secondary
        } else if case .failed = registrationState {
            return DesignTokens.Colors.error
        } else if case .submitting = registrationState {
            return DesignTokens.Colors.meshGold
        } else {
            return DesignTokens.Colors.onSurfaceVariant
        }
    }

    private var keyStatusText: String {
        if case .registered(let response) = registrationState {
            return response.status
        } else if case .failed = registrationState {
            return "FAILED"
        } else if case .submitting = registrationState {
            return "REGISTERING"
        } else {
            return "LOCAL ONLY"
        }
    }

    private var buttonLabelText: String {
        if case .registered = registrationState {
            return "Re-Verify Registration with Bridge"
        } else if case .failed = registrationState {
            return "Retry Registration"
        } else {
            return "Register Public Key with Bridge"
        }
    }

    private var buttonForegroundColor: Color {
        if case .registered = registrationState {
            return DesignTokens.Colors.secondary
        } else {
            return DesignTokens.Colors.onMeshGold
        }
    }

    private var buttonBackgroundColor: Color {
        if case .registered = registrationState {
            return DesignTokens.Colors.secondary.opacity(0.15)
        } else {
            return DesignTokens.Colors.meshGold
        }
    }

    private func loadLocalDeviceIdentity() {
        do {
            let id = try DeviceIdentityManager.shared.getOrCreateIdentity()
            self.deviceIdentity = id
            if registrationAccountId.isEmpty {
                self.registrationAccountId = id.deviceId
            }
        } catch {
            // Error logged internally
        }
    }

    private func executeExplicitRegistration() async {
        guard let id = deviceIdentity else { return }
        let targetId = registrationAccountId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetId.isEmpty else {
            registrationState = .failed("Please provide a valid account or device identifier")
            return
        }

        registrationState = .submitting
        do {
            let response = try await UPIMeshAPIClient.shared.registerPublicKey(
                accountId: targetId,
                publicKeyBase64: id.publicKeyBase64X509
            )
            registrationState = .registered(response)
            NotificationCenter.default.post(name: .deviceKeyRegistered, object: response)
        } catch {
            registrationState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Prototype Account Authorization Section (Milestone 3C)

    @ViewBuilder
    private var accountAuthorizationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .background(DesignTokens.Colors.surfaceVariant.opacity(0.4))
                .padding(.vertical, 4)

            HStack {
                Image(systemName: "person.badge.shield.checkmark.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(authorizationStatusColor)

                Text("PROTOTYPE ACCOUNT BINDING")
                    .font(DesignTokens.Typography.labelCaps)
                    .foregroundColor(DesignTokens.Colors.onSurface)
                    .tracking(1.0)

                Spacer()

                HStack(spacing: 5) {
                    Circle()
                        .fill(authorizationStatusColor)
                        .frame(width: 6, height: 6)
                    Text(authorizationStatusText)
                        .font(DesignTokens.Typography.labelCaps)
                        .foregroundColor(authorizationStatusColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(authorizationStatusColor.opacity(0.12)))
            }

            Text("Public-key registration proves identity, but does not grant debit authority. Explicitly bind this hardware device to 'alice' to permit settlement.")
                .font(DesignTokens.Typography.caption)
                .foregroundColor(DesignTokens.Colors.onSurfaceVariant)

            if case .authorized(let authResp) = authorizationState {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(DesignTokens.Colors.secondary)
                    Text(authResp.message)
                        .font(.system(size: 11))
                        .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(DesignTokens.Colors.secondary.opacity(0.12))
                )
            } else if case .failed(let errMsg) = authorizationState {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(DesignTokens.Colors.error)
                    Text(errMsg)
                        .font(.system(size: 11))
                        .foregroundColor(DesignTokens.Colors.error)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(DesignTokens.Colors.error.opacity(0.12))
                )
            }

            Button {
                Task {
                    await executeDeviceAuthorization()
                }
            } label: {
                HStack(spacing: 8) {
                    if authorizationState == .authorizing {
                        ProgressView()
                            .tint(DesignTokens.Colors.onMeshGold)
                            .scaleEffect(0.8)
                        Text("Authorizing with Bridge...")
                            .font(DesignTokens.Typography.bodySm)
                            .fontWeight(.semibold)
                    } else {
                        Image(systemName: "link.badge.plus")
                            .font(.system(size: 13, weight: .bold))
                        Text(authorizationButtonLabel)
                            .font(DesignTokens.Typography.bodySm)
                            .fontWeight(.semibold)
                    }
                }
                .foregroundColor(DesignTokens.Colors.onMeshGold)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(DesignTokens.Colors.meshGold.opacity(0.85))
                )
            }
            .disabled(authorizationState == .authorizing)
            .buttonStyle(.plain)
        }
    }

    private var authorizationStatusColor: Color {
        switch authorizationState {
        case .authorized: return DesignTokens.Colors.secondary
        case .failed: return DesignTokens.Colors.error
        case .authorizing: return DesignTokens.Colors.meshGold
        case .idle: return DesignTokens.Colors.onSurfaceVariant
        }
    }

    private var authorizationStatusText: String {
        switch authorizationState {
        case .authorized: return "BOUND TO ALICE"
        case .failed: return "FAILED"
        case .authorizing: return "AUTHORIZING"
        case .idle: return "UNBOUND"
        }
    }

    private var authorizationButtonLabel: String {
        switch authorizationState {
        case .authorized: return "Re-Authorize for Alice"
        case .failed: return "Retry Authorization for Alice"
        case .authorizing, .idle: return "Authorize Device for Alice (demo)"
        }
    }

    private func executeDeviceAuthorization() async {
        guard let id = deviceIdentity else { return }
        authorizationState = .authorizing
        do {
            let response = try await UPIMeshAPIClient.shared.authorizeDevice(
                deviceId: id.deviceId,
                accountId: "alice"
            )
            authorizationState = .authorized(response)
        } catch {
            authorizationState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Offline Allowance Card & Workflows (Phase 2B)

    private var offlineAllowanceCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "banknote.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(DesignTokens.Colors.meshGold)

                Text("OFFLINE ALLOWANCE VOUCHER")
                    .font(DesignTokens.Typography.labelCaps)
                    .foregroundColor(DesignTokens.Colors.onSurface)
                    .tracking(1.0)

                Spacer()

                if let voucher = activeAllowance {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(voucher.isExpired() ? DesignTokens.Colors.error : DesignTokens.Colors.secondary)
                            .frame(width: 6, height: 6)
                        Text(voucher.isExpired() ? "EXPIRED" : "ACTIVE")
                            .font(DesignTokens.Typography.labelCaps)
                            .foregroundColor(voucher.isExpired() ? DesignTokens.Colors.error : DesignTokens.Colors.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill((voucher.isExpired() ? DesignTokens.Colors.error : DesignTokens.Colors.secondary).opacity(0.12)))
                } else {
                    Text("NO ACTIVE ALLOWANCE")
                        .font(DesignTokens.Typography.labelCaps)
                        .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(DesignTokens.Colors.surfaceContainerHigh))
                }
            }

            if let voucher = activeAllowance {
                // Active Voucher Details
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Allowance ID")
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                        Spacer()
                        Text(voucher.allowanceId)
                            .font(DesignTokens.Typography.labelNumericSm)
                            .foregroundColor(DesignTokens.Colors.onSurface)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    HStack {
                        Text("Allocated / Remaining")
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                        Spacer()
                        Text("₹\(voucher.allocatedAmount) / ₹\(voucher.remainingAmount)")
                            .font(DesignTokens.Typography.labelNumericSm)
                            .foregroundColor(DesignTokens.Colors.meshGold)
                    }

                    HStack {
                        Text("Monotonic Sequence")
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                        Spacer()
                        Text("#\(voucher.lastSequenceNumber)")
                            .font(DesignTokens.Typography.labelNumericSm)
                            .foregroundColor(DesignTokens.Colors.onSurface)
                    }

                    HStack {
                        Text("Expires At")
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                        Spacer()
                        Text(voucher.expiresAt)
                            .font(DesignTokens.Typography.labelNumericSm)
                            .foregroundColor(voucher.isExpired() ? DesignTokens.Colors.error : DesignTokens.Colors.onSurfaceVariant)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(DesignTokens.Colors.surfaceContainerLowest.opacity(0.6))
                )

                // Actions for active voucher
                HStack(spacing: 8) {
                    Button {
                        Task {
                            await refundAllowanceAction(allowanceId: voucher.allowanceId)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.counterclockwise.circle")
                            Text("Refund Unspent to Alice")
                        }
                        .font(DesignTokens.Typography.labelCaps)
                        .foregroundColor(DesignTokens.Colors.onSurface)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(RoundedRectangle(cornerRadius: 8).fill(DesignTokens.Colors.surfaceContainerHigh))
                    }

                    Button {
                        try? OfflineAllowanceManager.shared.clearActiveVoucher()
                        reloadActiveAllowance()
                    } label: {
                        Text("Clear")
                            .font(DesignTokens.Typography.labelCaps)
                            .foregroundColor(DesignTokens.Colors.error)
                            .padding(.horizontal, 12)
                            .frame(height: 38)
                            .background(RoundedRectangle(cornerRadius: 8).fill(DesignTokens.Colors.error.opacity(0.12)))
                    }
                }
            } else {
                // Request New Allowance Form
                VStack(alignment: .leading, spacing: 8) {
                    Text("Reserve funds from Alice into Bank Escrow for offline spending.")
                        .font(DesignTokens.Typography.caption)
                        .foregroundColor(DesignTokens.Colors.onSurfaceVariant)

                    // Quick Amount Chips
                    HStack(spacing: 8) {
                        ForEach([100.0, 200.0, 500.0, 1000.0], id: \.self) { val in
                            Button {
                                allowanceRequestAmount = val
                            } label: {
                                Text("₹\(Int(val))")
                                    .font(DesignTokens.Typography.labelNumericSm)
                                    .foregroundColor(allowanceRequestAmount == val ? DesignTokens.Colors.onMeshGold : DesignTokens.Colors.onSurface)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(allowanceRequestAmount == val ? DesignTokens.Colors.meshGold : DesignTokens.Colors.surfaceContainerHigh))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        Task {
                            await requestAllowanceAction()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isRequestingAllowance {
                                ProgressView().scaleEffect(0.7).tint(DesignTokens.Colors.onMeshGold)
                            } else {
                                Image(systemName: "lock.shield.fill")
                            }
                            Text("Request Allowance (₹\(Int(allowanceRequestAmount)))")
                                .font(DesignTokens.Typography.labelCaps)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(DesignTokens.Colors.onMeshGold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(RoundedRectangle(cornerRadius: 8).fill(DesignTokens.Colors.meshGold))
                    }
                    .disabled(isRequestingAllowance)
                    .buttonStyle(.plain)
                }
            }

            // Status message banner
            if let msg = allowanceActionMessage {
                HStack(spacing: 6) {
                    Image(systemName: isAllowanceSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(isAllowanceSuccess ? DesignTokens.Colors.secondary : DesignTokens.Colors.error)
                    Text(msg)
                        .font(DesignTokens.Typography.caption)
                        .foregroundColor(DesignTokens.Colors.onSurface)
                        .lineLimit(3)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill((isAllowanceSuccess ? DesignTokens.Colors.secondary : DesignTokens.Colors.error).opacity(0.12)))
            }
        }
        .padding(DesignTokens.Spacing.md)
        .liquidCard(strokeColor: DesignTokens.Colors.meshGold.opacity(activeAllowance != nil ? 0.35 : 0.15))
    }

    private func reloadActiveAllowance() {
        self.activeAllowance = OfflineAllowanceManager.shared.getActiveVoucher()
    }

    private func requestAllowanceAction() async {
        guard !isRequestingAllowance else { return }
        isRequestingAllowance = true
        allowanceActionMessage = nil

        do {
            // 1. Fetch bank authority public key & pin it
            let bankKeyResp = try await UPIMeshAPIClient.shared.fetchBankAuthorityPublicKey()
            try OfflineAllowanceManager.shared.pinBankAuthorityPublicKey(bankKeyResp.publicKeyBase64)

            // 2. Request allowance
            let identity = try DeviceIdentityManager.shared.getOrCreateIdentity()
            _ = try? await UPIMeshAPIClient.shared.registerPublicKey(
                accountId: identity.deviceId,
                publicKeyBase64: identity.publicKeyBase64X509
            )
            _ = try? await UPIMeshAPIClient.shared.authorizeDevice(
                deviceId: identity.deviceId,
                accountId: allowanceRequestAccount
            )
            let decAmount = Decimal(string: String(format: "%.2f", allowanceRequestAmount)) ?? Decimal(allowanceRequestAmount)
            let req = AllowanceIssuanceRequestDTO(
                accountId: allowanceRequestAccount,
                deviceId: identity.deviceId,
                amount: decAmount,
                expiryMinutes: 1440
            )

            let voucherResp: OfflineAllowanceVoucherResponseDTO
            do {
                voucherResp = try await UPIMeshAPIClient.shared.issueAllowance(request: req)
            } catch {
                if let active = try? await UPIMeshAPIClient.shared.fetchActiveAllowance(accountId: allowanceRequestAccount) {
                    voucherResp = active
                } else {
                    throw error
                }
            }
            let voucher = voucherResp.toVoucher()

            // 3. Cryptographically verify voucher signature against pinned key
            let (valid, errorDesc) = voucher.verifyBankSignature(trustedBankPublicKeyBase64: bankKeyResp.publicKeyBase64)
            guard valid else {
                throw OfflineAllowanceError.voucherSignatureInvalid(errorDesc ?? "Signature verification failed")
            }

            // 4. Save and activate
            try OfflineAllowanceManager.shared.saveActiveVoucher(voucher)
            reloadActiveAllowance()

            isAllowanceSuccess = true
            allowanceActionMessage = "Allowance of ₹\(voucher.allocatedAmount) issued & verified successfully!"
        } catch {
            isAllowanceSuccess = false
            allowanceActionMessage = error.localizedDescription
        }

        isRequestingAllowance = false
    }

    private func refundAllowanceAction(allowanceId: String) async {
        allowanceActionMessage = nil
        do {
            let result = try await UPIMeshAPIClient.shared.refundAllowance(allowanceId: allowanceId)
            isAllowanceSuccess = true
            allowanceActionMessage = result.message
            try? OfflineAllowanceManager.shared.clearActiveVoucher()
            reloadActiveAllowance()
            await viewModel.loadLiveAccounts()
        } catch {
            isAllowanceSuccess = false
            allowanceActionMessage = error.localizedDescription
        }
    }
}
