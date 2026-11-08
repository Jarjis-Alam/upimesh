import SwiftUI

/// Mesh Radar Screen ("Obsidian Kinetic" — `ios 2/mesh_radar_ios/`)
///
/// Faithfully reproduces the Obsidian Kinetic AMOLED Radar interface:
/// - Top telemetry strip with 99.8% Reliability rating.
/// - Segmented filter chips (All Peers, Internet Gateways, Merchants).
/// - Concentric distance circles (0.8m, 2.4m, 4.1m, 8.0m) and rotating amber sweep vector.
/// - Central User Node (You - 16 Pro) and nearby mesh peer nodes.
/// - Selected node inspector card with interactive zero-knowledge ping verification.
/// - Real-time MultipeerConnectivity bridge awareness.
public struct MeshRadarView: View {

    public enum PeerFilter: String, CaseIterable, Identifiable {
        case all = "All Peers (4)"
        case gateway = "Internet Gateways (1)"
        case merchant = "Merchants (2)"

        public var id: String { rawValue }
    }

    public enum NodeType {
        case gateway
        case merchant
        case peer
    }

    public struct RadarNode: Identifiable {
        public let id: String
        public let title: String
        public let role: String
        public let type: NodeType
        public let distance: String
        public let latency: String
        public let protocolStr: String
        public let forwarding: String
        public let icon: String
        public let color: Color
        public let xFraction: CGFloat
        public let yFraction: CGFloat
    }

    @State private var sweepAngle: Double = 0
    @State private var selectedFilter: PeerFilter = .all
    @State private var selectedNodeId: String = "macbook"
    @State private var pingState: PingState = .idle

    public enum PingState: Equatable {
        case idle
        case verifying
        case verified
    }

    private let timer = Timer.publish(every: 0.04, on: .main, in: .common).autoconnect()

    private let nodes: [RadarNode] = [
        RadarNode(
            id: "macbook",
            title: "MacBook Pro 16\"",
            role: "Bridge Peer",
            type: .gateway,
            distance: "Proximity 0.8m · Direct AWDL Link",
            latency: "12 ms",
            protocolStr: "UPI-Mesh/2.4",
            forwarding: "Forwarding Enabled",
            icon: "laptopcomputer",
            color: DesignTokens.Colors.primaryContainer,
            xFraction: 0.62,
            yFraction: 0.37
        ),
        RadarNode(
            id: "pos",
            title: "Metro POS Terminal",
            role: "Merchant Relay",
            type: .merchant,
            distance: "Proximity 2.4m · 2 Hops via Aarav",
            latency: "38 ms",
            protocolStr: "UPI-Mesh/2.4 (Merchant Pay)",
            forwarding: "Isolated (POS Ledger)",
            icon: "cart.fill",
            color: DesignTokens.Colors.secondary,
            xFraction: 0.32,
            yFraction: 0.66
        ),
        RadarNode(
            id: "aarav",
            title: "Aarav's iPhone 15",
            role: "Peer Node",
            type: .peer,
            distance: "Proximity 4.1m · 1 Hop Peer",
            latency: "22 ms",
            protocolStr: "UPI-Mesh/2.4",
            forwarding: "Mesh Relaying Only",
            icon: "iphone",
            color: DesignTokens.Colors.onSurfaceVariant,
            xFraction: 0.24,
            yFraction: 0.23
        ),
        RadarNode(
            id: "beacon",
            title: "Store Transit Beacon",
            role: "Edge Node",
            type: .merchant,
            distance: "Proximity 8.0m · BLE Broadcast",
            latency: "64 ms",
            protocolStr: "UPI-Mesh/Beacon-v1",
            forwarding: "Telemetry Beacon",
            icon: "storefront.fill",
            color: DesignTokens.Colors.secondaryContainer,
            xFraction: 0.80,
            yFraction: 0.84
        )
    ]

    public init() {}

    private var activeSelectedNode: RadarNode {
        nodes.first(where: { $0.id == selectedNodeId }) ?? nodes[0]
    }

    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: DesignTokens.Spacing.md) {

                // MARK: - Header
                headerView

                // MARK: - Top Radar Telemetry Strip
                telemetryStrip

                // MARK: - Peer Filter Chips
                filterChipsRow

                // MARK: - AMOLED Radar Visual Canvas
                radarVisualCanvas

                // MARK: - Selected Node Inspector Card
                inspectorCard

                // MARK: - Mesh Health Status Footer Bar
                telemetryStrip

                // Bottom spacer for detached floating tab bar
                Spacer(minLength: 88)
            }
            .padding(.horizontal, DesignTokens.Spacing.margin)
            .padding(.top, 8)
        }
        .onReceive(timer) { _ in
            sweepAngle = (sweepAngle + 2.5).truncatingRemainder(dividingBy: 360)
        }
    }

    // MARK: - Header Subview
    private var headerView: some View {
        HStack(alignment: .center) {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(DesignTokens.Colors.primaryContainer)
                        .frame(width: 7, height: 7)
                    Text("OFFLINE MESH")
                        .font(DesignTokens.Typography.labelCaps)
                        .foregroundColor(DesignTokens.Colors.primaryContainer)
                        .tracking(1.0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(DesignTokens.Colors.surfaceContainerHigh.opacity(0.8)))

                HStack(spacing: 4) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 11))
                        .foregroundColor(DesignTokens.Colors.primaryContainer)
                    Text("4 PEERS")
                        .font(DesignTokens.Typography.telemetrySm)
                        .fontWeight(.semibold)
                        .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(DesignTokens.Colors.surfaceContainerLow))
            }

            Spacer()

            Text("Radar")
                .font(DesignTokens.Typography.headlineSm)
                .fontWeight(.bold)
                .foregroundColor(DesignTokens.Colors.onSurface)

            Spacer()

            HStack(spacing: 8) {
                Button {} label: {
                    Circle()
                        .fill(DesignTokens.Colors.surfaceContainer)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(.system(size: 14))
                                .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                        )
                }
                .buttonStyle(.plain)

                Circle()
                    .fill(DesignTokens.Colors.primary)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 14))
                            .foregroundColor(DesignTokens.Colors.onPrimary)
                    )
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Top Telemetry Strip
    private var telemetryStrip: some View {
        HStack(spacing: 6) {
            Spacer()
            Circle()
                .fill(DesignTokens.Colors.primaryContainer)
                .frame(width: 7, height: 7)
            Text("99.8% Reliability")
                .font(DesignTokens.Typography.telemetrySm)
                .fontWeight(.semibold)
                .foregroundColor(DesignTokens.Colors.primary)
                .tracking(0.5)
            Spacer()
        }
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.base)
                .fill(DesignTokens.Colors.surfaceContainerLow)
        )
    }

    // MARK: - Filter Chips Row
    private var filterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PeerFilter.allCases) { filter in
                    let isSelected = selectedFilter == filter
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            selectedFilter = filter
                        }
                    } label: {
                        Text(filter.rawValue)
                            .font(DesignTokens.Typography.bodySm)
                            .fontWeight(isSelected ? .bold : .medium)
                            .foregroundColor(isSelected ? DesignTokens.Colors.onPrimary : DesignTokens.Colors.onSurfaceVariant)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(isSelected ? DesignTokens.Colors.primaryContainer : DesignTokens.Colors.surfaceContainer)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - AMOLED Radar Visual Canvas
    private var radarVisualCanvas: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.base)
                .fill(DesignTokens.Colors.surfaceContainerLowest)
                .frame(height: 330)

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let center = CGPoint(x: w / 2, y: h / 2)

                ZStack {
                    // Concentric Range Rings (0.8m, 2.4m, 4.1m, 8.0m)
                    Circle()
                        .fill(DesignTokens.Colors.surfaceContainerLow.opacity(0.18))
                        .frame(width: w * 0.84, height: w * 0.84)
                    Circle()
                        .fill(DesignTokens.Colors.surfaceContainerLow.opacity(0.25))
                        .frame(width: w * 0.60, height: w * 0.60)
                    Circle()
                        .fill(DesignTokens.Colors.surfaceContainerLow.opacity(0.35))
                        .frame(width: w * 0.36, height: w * 0.36)
                    Circle()
                        .fill(DesignTokens.Colors.surfaceContainerLow.opacity(0.45))
                        .frame(width: w * 0.14, height: w * 0.14)

                    // Ring outline strokes
                    Circle()
                        .stroke(DesignTokens.Colors.glassStrokeDim, lineWidth: 1)
                        .frame(width: w * 0.84, height: w * 0.84)
                    Circle()
                        .stroke(DesignTokens.Colors.glassStrokeDim, lineWidth: 1)
                        .frame(width: w * 0.60, height: w * 0.60)
                    Circle()
                        .stroke(DesignTokens.Colors.glassStrokeDim, lineWidth: 1)
                        .frame(width: w * 0.36, height: w * 0.36)
                    Circle()
                        .stroke(DesignTokens.Colors.glassStrokeLight.opacity(0.4), lineWidth: 1)
                        .frame(width: w * 0.14, height: w * 0.14)

                    // Crosshairs
                    Rectangle()
                        .fill(DesignTokens.Colors.surfaceContainerHigh.opacity(0.4))
                        .frame(width: w, height: 1)
                    Rectangle()
                        .fill(DesignTokens.Colors.surfaceContainerHigh.opacity(0.4))
                        .frame(width: 1, height: h)

                    // Distance Labels
                    Text("8.0m")
                        .font(DesignTokens.Typography.telemetrySm)
                        .foregroundColor(DesignTokens.Colors.outlineVariant)
                        .position(x: center.x + w * 0.36, y: center.y - w * 0.36)

                    Text("4.1m")
                        .font(DesignTokens.Typography.telemetrySm)
                        .foregroundColor(DesignTokens.Colors.outlineVariant)
                        .position(x: center.x + w * 0.25, y: center.y - w * 0.25)

                    Text("2.4m")
                        .font(DesignTokens.Typography.telemetrySm)
                        .foregroundColor(DesignTokens.Colors.outlineVariant)
                        .position(x: center.x + w * 0.15, y: center.y - w * 0.15)

                    Text("0.8m")
                        .font(DesignTokens.Typography.telemetrySm)
                        .foregroundColor(DesignTokens.Colors.primaryContainer.opacity(0.8))
                        .position(x: center.x + w * 0.06, y: center.y - w * 0.06)

                    // Rotating Amber Sweep Vector
                    Path { path in
                        path.move(to: center)
                        let endPoint = CGPoint(
                            x: center.x + (w * 0.42) * cos(CGFloat(sweepAngle * .pi / 180)),
                            y: center.y + (w * 0.42) * sin(CGFloat(sweepAngle * .pi / 180))
                        )
                        path.addLine(to: endPoint)
                    }
                    .stroke(
                        LinearGradient(
                            colors: [DesignTokens.Colors.primaryContainer.opacity(0.9), DesignTokens.Colors.primaryContainer.opacity(0.1)],
                            startPoint: .center,
                            endPoint: .trailing
                        ),
                        lineWidth: 1.5
                    )

                    // Center User Node: You (16 Pro)
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(DesignTokens.Colors.primaryContainer.opacity(0.25))
                                .frame(width: 24, height: 24)

                            Circle()
                                .fill(DesignTokens.Colors.primaryContainer)
                                .frame(width: 14, height: 14)
                                .shadow(color: DesignTokens.Colors.primaryContainer, radius: 8)

                            Circle()
                                .fill(DesignTokens.Colors.onPrimary)
                                .frame(width: 5, height: 5)
                        }

                        Text("You (16 Pro)")
                            .font(DesignTokens.Typography.telemetrySm)
                            .fontWeight(.semibold)
                            .foregroundColor(DesignTokens.Colors.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(DesignTokens.Colors.surfaceContainerHigh.opacity(0.9))
                            )
                    }
                    .position(center)

                    // Peer Nodes
                    ForEach(filteredNodes) { node in
                        let nodePos = CGPoint(x: w * node.xFraction, y: h * node.yFraction)
                        let isSelected = selectedNodeId == node.id

                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                selectedNodeId = node.id
                            }
                        } label: {
                            HStack(spacing: 6) {
                                ZStack {
                                    if isSelected {
                                        Circle()
                                            .fill(node.color.opacity(0.35))
                                            .frame(width: 32, height: 32)
                                    }

                                    Circle()
                                        .fill(DesignTokens.Colors.surfaceContainerHigh)
                                        .frame(width: 26, height: 26)
                                        .overlay(
                                            Image(systemName: node.icon)
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundColor(node.color)
                                        )
                                        .shadow(color: node.color.opacity(0.4), radius: 6)
                                }

                                Text(node.title)
                                    .font(DesignTokens.Typography.bodySm)
                                    .fontWeight(.semibold)
                                    .foregroundColor(DesignTokens.Colors.onSurface)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(DesignTokens.Colors.surfaceContainerLow.opacity(0.95))
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                        .position(nodePos)
                    }
                }
            }
            .frame(height: 330)
        }
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.base)
                .stroke(DesignTokens.Colors.glassStrokeLight, lineWidth: 1)
        )
    }

    private var filteredNodes: [RadarNode] {
        switch selectedFilter {
        case .all:
            return nodes
        case .gateway:
            return nodes.filter { $0.type == .gateway }
        case .merchant:
            return nodes.filter { $0.type == .merchant }
        }
    }

    // MARK: - Selected Node Inspector Card
    private var inspectorCard: some View {
        let node = activeSelectedNode

        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                Circle()
                    .fill(DesignTokens.Colors.surfaceContainerHighest)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: node.icon)
                            .font(.system(size: 18))
                            .foregroundColor(node.color)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(node.title)
                            .font(DesignTokens.Typography.headlineSm)
                            .fontWeight(.bold)
                            .foregroundColor(DesignTokens.Colors.onSurface)

                        Text(node.role)
                            .font(DesignTokens.Typography.labelCaps)
                            .foregroundColor(DesignTokens.Colors.onPrimary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(DesignTokens.Colors.primaryContainer)
                            )
                    }

                    Text(node.distance)
                        .font(DesignTokens.Typography.caption)
                        .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                }

                Spacer()

                Text(node.latency)
                    .font(DesignTokens.Typography.telemetryMd)
                    .fontWeight(.semibold)
                    .foregroundColor(DesignTokens.Colors.primaryContainer)
            }

            // Action Button: Ping Peer
            Button {
                triggerPingAction()
            } label: {
                HStack(spacing: 8) {
                    switch pingState {
                    case .verifying:
                        ProgressView()
                            .tint(DesignTokens.Colors.primaryContainer)
                        Text("Verifying Proof...")
                            .font(DesignTokens.Typography.bodyMd)
                            .fontWeight(.semibold)
                            .foregroundColor(DesignTokens.Colors.primary)

                    case .verified:
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 16))
                            .foregroundColor(DesignTokens.Colors.primaryContainer)
                        Text("Verified · Zero-Knowledge Valid (\(node.latency))")
                            .font(DesignTokens.Typography.bodyMd)
                            .fontWeight(.bold)
                            .foregroundColor(DesignTokens.Colors.primaryContainer)

                    case .idle:
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 15))
                            .foregroundColor(DesignTokens.Colors.primaryContainer)
                        Text("Ping Peer")
                            .font(DesignTokens.Typography.bodyMd)
                            .fontWeight(.semibold)
                            .foregroundColor(DesignTokens.Colors.primary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    Capsule()
                        .fill(DesignTokens.Colors.surfaceContainer)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(DesignTokens.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.base)
                .fill(DesignTokens.Colors.surfaceContainerHigh)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.base)
                .stroke(DesignTokens.Colors.glassStrokeLight, lineWidth: 1)
        )
    }

    private func triggerPingAction() {
        guard pingState == .idle else { return }
        pingState = .verifying
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation {
                pingState = .verified
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                withAnimation {
                    pingState = .idle
                }
            }
        }
    }
}
