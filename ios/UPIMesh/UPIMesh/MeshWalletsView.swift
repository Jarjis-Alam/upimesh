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
        }
        .refreshable {
            await viewModel.loadLiveAccounts()
        }
        .onReceive(NotificationCenter.default.publisher(for: .meshAccountsUpdated)) { _ in
            Task {
                await viewModel.loadLiveAccounts()
            }
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

                Text("\(APIConfiguration.shared.baseURL.host ?? "192.168.1.100"):8080")
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
}
