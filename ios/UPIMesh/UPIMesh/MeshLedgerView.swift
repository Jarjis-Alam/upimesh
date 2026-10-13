import SwiftUI

/// Mesh Ledger Screen (`ios_ui/mesh_ledger_ios/`)
///
/// Faithfully reproduces the Stitch UI transaction ledger interface connected to the live backend:
/// - Live network connection banner with sync status and explicit fallback indicators.
/// - Horizontal metric summary carousel (Total, Settled, In Transit, Blocked) dynamically derived from backend and inbox records.
/// - Segmented transaction category filter bar with real-time record counts.
/// - Inset list cards displaying sender, recipient, status pills, amounts, and timestamps from live ledger transactions.
/// - Expandable / selected transaction inspection sheet with truthful 3-step audit trail and receipt action.
/// - Pull-to-refresh and reactive reload on `.meshAccountsUpdated`.
public struct MeshLedgerView: View {
    @State private var viewModel = MeshLedgerViewModel()
    @State private var selectedFilter: String = "all"
    @State private var selectedTx: PreviewData.TransactionItem? = nil

    public init() {}

    private var filteredTransactions: [PreviewData.TransactionItem] {
        viewModel.displayTransactions(for: selectedFilter)
    }

    private var currentSelectedTx: PreviewData.TransactionItem? {
        if let selected = selectedTx, filteredTransactions.contains(where: { $0.id == selected.id }) {
            return selected
        }
        return filteredTransactions.first
    }

    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: DesignTokens.Spacing.md) {

                // MARK: - Header
                headerView

                // MARK: - Live Network / Status Banner
                networkStatusBanner

                // MARK: - Subheader Row
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recent Activity")
                            .font(DesignTokens.Typography.bodyMd)
                            .fontWeight(.semibold)
                            .foregroundColor(DesignTokens.Colors.onSurface)

                        Text(viewModel.isLive ? "Authoritative Ledger State" : "Verifiable Offline State")
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                    }

                    Spacer()

                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 13))
                            .foregroundColor(DesignTokens.Colors.primary)

                        Text(viewModel.isLive ? "LEDGER VERIFIED" : "ZERO-SYNC VALID")
                            .font(DesignTokens.Typography.labelCaps)
                            .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(DesignTokens.Colors.surfaceContainerHigh.opacity(0.8))
                    )
                }

                // MARK: - Metric Summary Carousel
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        metricPill(
                            title: "TOTAL",
                            value: viewModel.totalMetricString,
                            icon: "doc.text.fill",
                            iconColor: DesignTokens.Colors.onSurface,
                            valueColor: DesignTokens.Colors.onSurface
                        )
                        metricPill(
                            title: "SETTLED",
                            value: viewModel.settledMetricString,
                            icon: "checkmark.circle.fill",
                            iconColor: DesignTokens.Colors.primary,
                            valueColor: DesignTokens.Colors.primary
                        )
                        metricPill(
                            title: "IN TRANSIT",
                            value: viewModel.inTransitMetricString,
                            icon: "arrow.triangle.swap",
                            iconColor: DesignTokens.Colors.secondary,
                            valueColor: DesignTokens.Colors.secondary
                        )
                        metricPill(
                            title: "BLOCKED",
                            value: viewModel.blockedMetricString,
                            icon: "exclamationmark.shield.fill",
                            iconColor: DesignTokens.Colors.alertRed,
                            valueColor: DesignTokens.Colors.alertRed
                        )
                    }
                }

                // MARK: - Segmented Filter Bar
                filterBar

                // MARK: - Transaction Cards List
                VStack(spacing: DesignTokens.Spacing.sm) {
                    if filteredTransactions.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "tray")
                                .font(.system(size: 26))
                                .foregroundColor(DesignTokens.Colors.onSurfaceVariant.opacity(0.5))
                            Text(viewModel.status == .loading ? "Syncing transactions..." : "No transactions found")
                                .font(DesignTokens.Typography.bodySm)
                                .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                    } else {
                        ForEach(filteredTransactions) { tx in
                            transactionCard(tx)
                        }
                    }
                }

                // MARK: - Inspection Sheet (Selected Transaction)
                if let tx = currentSelectedTx {
                    inspectionSheet(for: tx)
                }

                // Bottom spacer for detached floating tab bar
                Spacer(minLength: 88)
            }
            .padding(.horizontal, DesignTokens.Spacing.margin)
            .padding(.top, 8)
        }
        .task {
            await viewModel.loadLiveTransactions()
        }
        .refreshable {
            await viewModel.loadLiveTransactions()
        }
        .onReceive(NotificationCenter.default.publisher(for: .meshAccountsUpdated)) { _ in
            Task {
                await viewModel.loadLiveTransactions()
            }
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Mesh Ledger")
                        .font(DesignTokens.Typography.headlineSm)
                        .foregroundColor(DesignTokens.Colors.onSurface)

                    HStack(spacing: 5) {
                        Circle()
                            .fill(DesignTokens.Colors.primary)
                            .frame(width: 6, height: 6)
                        Text(viewModel.isLive ? "LIVE SYNCED" : "MESH ACTIVE")
                            .font(DesignTokens.Typography.labelCaps)
                            .foregroundColor(DesignTokens.Colors.primary)
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
                .fill(DesignTokens.Colors.primary)
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "person.fill")
                        .foregroundColor(DesignTokens.Colors.onPrimary)
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
                    .tint(DesignTokens.Colors.primary)
                    .scaleEffect(0.8)
                Text("Syncing live ledger from backend...")
                    .font(DesignTokens.Typography.caption)
                    .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                Spacer()
                Text("GET /api/transactions")
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
                        .fill(DesignTokens.Colors.primary)
                        .frame(width: 6, height: 6)
                    Text("LIVE LEDGER CONNECTED")
                        .font(DesignTokens.Typography.labelCaps)
                        .foregroundColor(DesignTokens.Colors.primary)
                        .tracking(1.0)
                }

                Spacer()

                Text("\(APIConfiguration.shared.baseURL.host ?? "192.168.1.100"):8080")
                    .font(DesignTokens.Typography.labelNumericSm)
                    .foregroundColor(DesignTokens.Colors.onSurfaceVariant)

                Button {
                    Task { await viewModel.loadLiveTransactions() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(DesignTokens.Colors.primary)
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
                    Text("BACKEND UNREACHABLE — SHOWING DEMO DATA (NOT LIVE)")
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
                    Task { await viewModel.loadLiveTransactions() }
                } label: {
                    Text("Retry")
                        .font(DesignTokens.Typography.labelCaps)
                        .foregroundColor(DesignTokens.Colors.onSurface)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(DesignTokens.Colors.surfaceContainerHighest))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(DesignTokens.Colors.error.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(DesignTokens.Colors.error.opacity(0.3), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Metric Pill
    private func metricPill(title: String, value: String, icon: String, iconColor: Color, valueColor: Color) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(iconColor.opacity(0.18))
                .frame(width: 28, height: 28)
                .overlay(Image(systemName: icon).font(.system(size: 13)).foregroundColor(iconColor))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(DesignTokens.Typography.labelCaps)
                    .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                Text(value)
                    .font(DesignTokens.Typography.labelNumeric)
                    .fontWeight(.semibold)
                    .foregroundColor(valueColor)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(DesignTokens.Colors.surfaceContainerHigh.opacity(0.7))
        )
    }

    // MARK: - Filter Bar
    private var filterBar: some View {
        HStack(spacing: 4) {
            filterButton(id: "all", label: "All (\(viewModel.displayTransactions(for: "all").count))")
            filterButton(id: "settled", label: "Settled (\(viewModel.settledCount))")
            filterButton(id: "transit", label: "In Transit (\(viewModel.inTransitCount))")
            filterButton(id: "blocked", label: "Blocked (\(viewModel.blockedCount))")
        }
        .padding(4)
        .background(
            Capsule()
                .fill(DesignTokens.Colors.surfaceContainerLow.opacity(0.9))
        )
    }

    private func filterButton(id: String, label: String) -> some View {
        let isSelected = selectedFilter == id
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedFilter = id
            }
        } label: {
            Text(label)
                .font(DesignTokens.Typography.labelCaps)
                .foregroundColor(isSelected ? DesignTokens.Colors.primary : DesignTokens.Colors.onSurfaceVariant)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(isSelected ? DesignTokens.Colors.surfaceBright.opacity(0.6) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Transaction Card
    private func transactionCard(_ tx: PreviewData.TransactionItem) -> some View {
        let isSelected = currentSelectedTx?.id == tx.id

        return Button {
            withAnimation {
                selectedTx = tx
            }
        } label: {
            VStack(spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .fill(DesignTokens.Colors.surfaceContainerHighest)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: tx.iconName)
                                .font(.system(size: 18))
                                .foregroundColor(colorForCategory(tx.category))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(tx.title)
                            .font(DesignTokens.Typography.headlineSm)
                            .fontWeight(.semibold)
                            .foregroundColor(DesignTokens.Colors.onSurface)

                        Text(tx.memo)
                            .font(DesignTokens.Typography.bodySm)
                            .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "₹%.2f", tx.amount))
                            .font(DesignTokens.Typography.labelNumeric)
                            .fontWeight(.semibold)
                            .foregroundColor(tx.category == .blocked ? DesignTokens.Colors.alertRed : DesignTokens.Colors.onSurface)
                            .strikethrough(tx.category == .blocked)

                        Text(tx.timeFormatted)
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                    }
                }

                Divider()
                    .background(DesignTokens.Colors.surfaceVariant.opacity(0.4))

                HStack {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(colorForCategory(tx.category))
                            .frame(width: 5, height: 5)

                        Text(tx.statusLabel.uppercased())
                            .font(DesignTokens.Typography.labelCaps)
                            .foregroundColor(colorForCategory(tx.category))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(colorForCategory(tx.category).opacity(0.12)))

                    Spacer()

                    Text(tx.routeLabel)
                        .font(DesignTokens.Typography.caption)
                        .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                }
            }
            .padding(DesignTokens.Spacing.md)
            .liquidCard(
                strokeColor: isSelected ? DesignTokens.Colors.primary.opacity(0.4) : DesignTokens.Colors.glassStrokeLight,
                backgroundColor: DesignTokens.Colors.surfaceContainerHigh.opacity(isSelected ? 0.85 : 0.60)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Inspection Detail Sheet
    private func inspectionSheet(for tx: PreviewData.TransactionItem) -> some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(DesignTokens.Colors.primary)
                        .frame(width: 7, height: 7)

                    Text("VERIFICATION ROUTE")
                        .font(DesignTokens.Typography.labelCaps)
                        .foregroundColor(DesignTokens.Colors.primary)
                        .tracking(1.2)
                }

                Spacer()

                Text(tx.txCode)
                    .font(DesignTokens.Typography.labelNumericSm)
                    .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(DesignTokens.Colors.surfaceVariant))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(tx.title)
                    .font(DesignTokens.Typography.headlineMd)
                    .fontWeight(.semibold)
                    .foregroundColor(DesignTokens.Colors.onSurface)

                HStack {
                    Text(tx.memo)
                        .font(DesignTokens.Typography.bodyMd)
                        .foregroundColor(DesignTokens.Colors.onSurfaceVariant)

                    Spacer()

                    Text(String(format: "₹%.2f", tx.amount))
                        .font(DesignTokens.Typography.displayHeroMobile)
                        .fontWeight(.bold)
                        .foregroundColor(colorForCategory(tx.category))
                }
            }

            // 3-Step Settlement Route Audit Trail
            VStack(alignment: .leading, spacing: 10) {
                Text("SETTLEMENT ROUTE")
                    .font(DesignTokens.Typography.labelCaps)
                    .foregroundColor(DesignTokens.Colors.onSurfaceVariant)

                if tx.category == .inTransit {
                    routeStepItem(icon: "key.fill", title: "Step 1: Signed Offline", subtitle: "Secured via sender local device")
                    routeStepItem(icon: "arrow.triangle.swap", title: "Step 2: Stored in Inbox", subtitle: tx.routeLabel)
                    routeStepItem(icon: "hourglass", title: "Step 3: Awaiting Gateway Settlement", subtitle: "Pending connection to UPI gateway", isLast: true)
                } else if tx.category == .blocked {
                    routeStepItem(icon: "key.fill", title: "Step 1: Signed Offline", subtitle: "Secured via sender local device")
                    routeStepItem(icon: "exclamationmark.triangle.fill", title: "Step 2: Verification Failed", subtitle: tx.routeLabel)
                    routeStepItem(icon: "xmark.seal.fill", title: "Step 3: Settlement Blocked", subtitle: tx.memo, isLast: true)
                } else {
                    routeStepItem(icon: "key.fill", title: "Step 1: Signed Offline", subtitle: "Secured via sender local device")
                    routeStepItem(icon: "arrow.triangle.branch", title: "Step 2: Relayed via Mesh", subtitle: "Forwarded via peer mesh network")
                    routeStepItem(icon: "building.columns.fill", title: "Step 3: Bank Settlement", subtitle: "Completed via UPI gateway", isLast: true)
                }
            }
            .padding(.vertical, 4)

            // Reconciled Badge & Action
            HStack {
                if tx.category == .inTransit {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(DesignTokens.Colors.secondary.opacity(0.2))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Image(systemName: "hourglass")
                                    .foregroundColor(DesignTokens.Colors.secondary)
                                    .font(.system(size: 16))
                            )

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Pending Settlement")
                                .font(DesignTokens.Typography.bodySm)
                                .fontWeight(.semibold)
                                .foregroundColor(DesignTokens.Colors.onSurface)

                            Text("Unsettled Offline Packet")
                                .font(DesignTokens.Typography.caption)
                                .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                        }
                    }
                    Spacer()
                } else if tx.category == .blocked {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(DesignTokens.Colors.alertRed.opacity(0.2))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Image(systemName: "xmark.octagon.fill")
                                    .foregroundColor(DesignTokens.Colors.alertRed)
                                    .font(.system(size: 16))
                            )

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Settlement Rejected")
                                .font(DesignTokens.Typography.bodySm)
                                .fontWeight(.semibold)
                                .foregroundColor(DesignTokens.Colors.onSurface)

                            Text("Dropped by Invariant Guard")
                                .font(DesignTokens.Typography.caption)
                                .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                        }
                    }
                    Spacer()
                } else {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(DesignTokens.Colors.primary.opacity(0.2))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(DesignTokens.Colors.primary)
                                    .font(.system(size: 16))
                            )

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Settlement Confirmed")
                                .font(DesignTokens.Typography.bodySm)
                                .fontWeight(.semibold)
                                .foregroundColor(DesignTokens.Colors.onSurface)

                            Text("NPCI Reconciled")
                                .font(DesignTokens.Typography.caption)
                                .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                        }
                    }

                    Spacer()

                    Button {} label: {
                        HStack(spacing: 4) {
                            Text("Receipt")
                                .font(DesignTokens.Typography.labelCaps)
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(DesignTokens.Colors.onSurface)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(DesignTokens.Colors.surfaceVariant))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.base)
                    .fill(DesignTokens.Colors.surfaceContainerHigh.opacity(0.8))
            )
        }
        .padding(DesignTokens.Spacing.md)
        .liquidCard(strokeColor: DesignTokens.Colors.glassStrokeLight, backgroundColor: DesignTokens.Colors.surfaceContainer.opacity(0.85))
    }

    private func routeStepItem(icon: String, title: String, subtitle: String, isLast: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                Circle()
                    .fill(DesignTokens.Colors.primary.opacity(0.2))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 12))
                            .foregroundColor(DesignTokens.Colors.primary)
                    )

                if !isLast {
                    Rectangle()
                        .fill(DesignTokens.Colors.primary.opacity(0.4))
                        .frame(width: 2, height: 20)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(DesignTokens.Typography.bodyMd)
                    .fontWeight(.semibold)
                    .foregroundColor(DesignTokens.Colors.onSurface)
                Text(subtitle)
                    .font(DesignTokens.Typography.caption)
                    .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
            }

            Spacer()
        }
    }

    private func colorForCategory(_ category: PreviewData.TransactionItem.Category) -> Color {
        switch category {
        case .settled: return DesignTokens.Colors.primary
        case .inTransit: return DesignTokens.Colors.secondary
        case .blocked: return DesignTokens.Colors.alertRed
        }
    }
}
