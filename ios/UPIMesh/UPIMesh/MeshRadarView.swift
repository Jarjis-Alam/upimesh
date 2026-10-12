import SwiftUI

/// Mesh Radar Screen (`ios_ui/mesh_radar_ios/`)
///
/// Faithfully reproduces the Stitch UI live topology visualizer:
/// - Rotating radar sweeper and concentric range circles.
/// - Node positioning for Alice (You), Carol (Relay), Bob (Merchant), and NPCI Gateway.
/// - Live packet routing animation.
/// - Telemetry stats capsules and peer detail cards.
public struct MeshRadarView: View {
    @State private var sweepAngle: Double = 0
    @State private var packetHopPosition: CGPoint = CGPoint(x: 150, y: 150)
    @State private var routeStatusText: String = "Route: Alice → Carol → Bob"
    @State private var isSimulating: Bool = false
    @State private var isPinging: Bool = false
    @State private var selectedPeerId: String? = nil

    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    public init() {}

    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: DesignTokens.Spacing.md) {

                // MARK: - Header
                headerView

                // MARK: - Subheader & State Pill
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(DesignTokens.Colors.meshGold)
                                .frame(width: 8, height: 8)
                            Text("Live Topology")
                                .font(DesignTokens.Typography.headlineSm)
                                .foregroundColor(DesignTokens.Colors.onSurface)
                        }
                        Text("3 offline peers in range")
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        Image(systemName: "wifi")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(DesignTokens.Colors.meshGold)
                        Text("2.4 GHz MESH")
                            .font(DesignTokens.Typography.labelCaps)
                            .foregroundColor(DesignTokens.Colors.meshGold)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(DesignTokens.Colors.meshGold.opacity(0.12))
                            .overlay(Capsule().stroke(DesignTokens.Colors.meshGold.opacity(0.3), lineWidth: 1))
                    )
                }
                .padding(.horizontal, 4)

                // MARK: - Radar Card
                radarVisualizerCard

                // MARK: - Stats Capsules Row
                statsCapsulesRow

                // MARK: - Peer List Cards
                VStack(spacing: DesignTokens.Spacing.sm) {
                    ForEach(PreviewData.samplePeers) { peer in
                        peerCard(peer)
                    }
                }

                // MARK: - Quick Action Buttons
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Button {
                        triggerPing()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(DesignTokens.Colors.meshGold)
                            Text(isPinging ? "Scanning..." : "Ping Nodes")
                                .font(DesignTokens.Typography.bodyMd)
                                .fontWeight(.semibold)
                                .foregroundColor(DesignTokens.Colors.onSurface)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            Capsule()
                                .fill(DesignTokens.Colors.surfaceContainerHigh.opacity(0.85))
                                .overlay(Capsule().stroke(DesignTokens.Colors.meshGold.opacity(0.35), lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        triggerSimulateHop()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.swap")
                                .font(.system(size: 16, weight: .bold))
                            Text(isSimulating ? "Relaying..." : "Simulate Hop")
                                .font(DesignTokens.Typography.bodyMd)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(DesignTokens.Colors.onMeshGold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            Capsule()
                                .fill(DesignTokens.Colors.meshGold)
                                .shadow(color: DesignTokens.Colors.meshGold.opacity(0.35), radius: 12, x: 0, y: 4)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)

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
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Mesh Radar")
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
                            .fill(DesignTokens.Colors.meshGold.opacity(0.12))
                            .overlay(Capsule().stroke(DesignTokens.Colors.meshGold.opacity(0.3), lineWidth: 1))
                    )
                }

                Text("Offline P2P Protocol")
                    .font(DesignTokens.Typography.caption)
                    .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
            }

            Spacer()

            // User Avatar Indicator
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

    // MARK: - Radar Visualizer Card
    private var radarVisualizerCard: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            // Header inside radar card
            HStack {
                HStack(spacing: 6) {
                    Text("PROXIMITY FIELD")
                        .font(DesignTokens.Typography.labelCaps)
                        .foregroundColor(DesignTokens.Colors.onSurfaceVariant)

                    Text("-42 dBm peak")
                        .font(DesignTokens.Typography.labelNumericSm)
                        .foregroundColor(DesignTokens.Colors.meshGold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(DesignTokens.Colors.surfaceContainerHighest)
                                .overlay(Capsule().stroke(DesignTokens.Colors.meshGold.opacity(0.3), lineWidth: 0.8))
                        )
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 12))
                    Text("Radius: ~18m")
                        .font(DesignTokens.Typography.labelNumericSm)
                }
                .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
            }

            // Radar Geometry Field
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let center = CGPoint(x: w / 2, y: h / 2)

                ZStack {
                    // Concentric Range Rings
                    Circle()
                        .stroke(DesignTokens.Colors.glassStrokeDim, lineWidth: 1)
                        .frame(width: w * 0.94, height: w * 0.94)

                    Circle()
                        .stroke(DesignTokens.Colors.glassStrokeLight.opacity(0.5), lineWidth: 1)
                        .frame(width: w * 0.68, height: w * 0.68)

                    Circle()
                        .stroke(DesignTokens.Colors.glassStrokeLight, lineWidth: 1)
                        .frame(width: w * 0.40, height: w * 0.40)

                    // Sweeper Line
                    Path { path in
                        path.move(to: center)
                        path.addLine(to: CGPoint(
                            x: center.x + (w * 0.47) * cos(CGFloat(sweepAngle * .pi / 180)),
                            y: center.y + (w * 0.47) * sin(CGFloat(sweepAngle * .pi / 180))
                        ))
                    }
                    .stroke(
                        LinearGradient(
                            colors: [DesignTokens.Colors.meshGold.opacity(0.8), DesignTokens.Colors.meshGold.opacity(0.0)],
                            startPoint: .center,
                            endPoint: .trailing
                        ),
                        lineWidth: 2
                    )

                    // Topology Connection Lines
                    let alicePos = center
                    let carolPos = CGPoint(x: w * 0.66, y: h * 0.31)
                    let bobPos = CGPoint(x: w * 0.77, y: h * 0.73)
                    let gatewayPos = CGPoint(x: w * 0.28, y: h * 0.26)

                    Path { path in
                        path.move(to: alicePos)
                        path.addLine(to: carolPos)
                    }
                    .stroke(DesignTokens.Colors.meshGold.opacity(0.7), style: StrokeStyle(lineWidth: 1.8, dash: [4, 3]))

                    Path { path in
                        path.move(to: carolPos)
                        path.addLine(to: bobPos)
                    }
                    .stroke(DesignTokens.Colors.secondary.opacity(0.7), style: StrokeStyle(lineWidth: 1.6, dash: [3, 3]))

                    Path { path in
                        path.move(to: carolPos)
                        path.addLine(to: gatewayPos)
                    }
                    .stroke(DesignTokens.Colors.primary.opacity(0.8), style: StrokeStyle(lineWidth: 2))

                    // Node: Carol (Relay)
                    radarNodeButton(
                        position: carolPos,
                        title: "Carol · 1h",
                        icon: "point.3.filled.connected.trianglepath.dotted",
                        color: DesignTokens.Colors.meshGold
                    ) {
                        routeStatusText = "Carol: 1 Hop away, 0.4ms latency. Forwarding peer."
                    }

                    // Node: Bob (Merchant)
                    radarNodeButton(
                        position: bobPos,
                        title: "Bob · Merchant",
                        icon: "storefront.fill",
                        color: DesignTokens.Colors.secondary
                    ) {
                        routeStatusText = "Bob: Offline Merchant token validated. Ready for payment."
                    }

                    // Node: Gateway (NPCI Bridge)
                    radarNodeButton(
                        position: gatewayPos,
                        title: "Gateway",
                        icon: "building.columns.fill",
                        color: DesignTokens.Colors.primary
                    ) {
                        routeStatusText = "NPCI Gateway Bridge: Ready for immediate clearing."
                    }

                    // Node: Alice (Center / You)
                    VStack(spacing: 2) {
                        Circle()
                            .fill(DesignTokens.Colors.meshGold)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(DesignTokens.Colors.onMeshGold)
                            )
                            .shadow(color: DesignTokens.Colors.meshGold.opacity(0.4), radius: 10, x: 0, y: 2)

                        Text("You (Alice)")
                            .font(DesignTokens.Typography.labelCaps)
                            .foregroundColor(DesignTokens.Colors.meshGold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(DesignTokens.Colors.surfaceContainerLowest.opacity(0.85))
                                    .overlay(Capsule().stroke(DesignTokens.Colors.meshGold.opacity(0.3), lineWidth: 0.8))
                            )
                    }
                    .position(alicePos)

                    // Animated In-Transit Hop Packet Bubble
                    Circle()
                        .fill(DesignTokens.Colors.primary)
                        .frame(width: 9, height: 9)
                        .shadow(color: DesignTokens.Colors.primary, radius: 6)
                        .position(packetHopPosition)
                }
            }
            .frame(height: 290)

            // Tactile Route Toast Inside Card
            HStack {
                Text(routeStatusText)
                    .font(DesignTokens.Typography.bodySm)
                    .foregroundColor(DesignTokens.Colors.onSurface)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                Capsule()
                    .fill(DesignTokens.Colors.surfaceContainerHighest.opacity(0.6))
                    .overlay(Capsule().stroke(DesignTokens.Colors.meshGold.opacity(0.25), lineWidth: 1))
            )
        }
        .padding(DesignTokens.Spacing.md)
        .liquidCard(strokeColor: DesignTokens.Colors.meshGold.opacity(0.25))
    }

    private func radarNodeButton(
        position: CGPoint,
        title: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Circle()
                    .fill(DesignTokens.Colors.surfaceContainerHighest.opacity(0.95))
                    .frame(width: 38, height: 38)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(color)
                    )
                    .overlay(
                        Circle()
                            .stroke(color.opacity(0.4), lineWidth: 1)
                    )
                    .shadow(color: color.opacity(0.25), radius: 6, x: 0, y: 2)

                Text(title)
                    .font(DesignTokens.Typography.labelNumericSm)
                    .foregroundColor(DesignTokens.Colors.onSurface)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(DesignTokens.Colors.surfaceContainerLowest.opacity(0.9))
                    )
            }
        }
        .buttonStyle(.plain)
        .position(position)
    }

    // MARK: - Stats Capsules Row
    private var statsCapsulesRow: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            statCapsule(title: "CONNECTED", value: "4", icon: "network", color: DesignTokens.Colors.meshGold)
            statCapsule(title: "RELAY HOPS", value: "2", icon: "arrow.triangle.branch", color: DesignTokens.Colors.secondary)
            statCapsule(title: "BRIDGE UPLINK", value: "Sync", icon: "checkmark.circle.fill", color: DesignTokens.Colors.primary)
        }
    }

    private func statCapsule(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(color)
                Text(value)
                    .font(DesignTokens.Typography.headlineSm)
                    .fontWeight(.bold)
                    .foregroundColor(DesignTokens.Colors.onSurface)
            }
            Text(title)
                .font(DesignTokens.Typography.labelCaps)
                .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.base, style: .continuous)
                .fill(DesignTokens.Colors.surfaceContainer.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.base, style: .continuous)
                        .stroke(DesignTokens.Colors.glassStrokeLight, lineWidth: 1)
                )
        )
    }

    // MARK: - Peer List Card
    private func peerCard(_ peer: PreviewData.Peer) -> some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
                HStack(alignment: .center, spacing: 12) {
                    Circle()
                        .fill(peer.isBridge ? DesignTokens.Colors.primary.opacity(0.2) : DesignTokens.Colors.meshGold.opacity(0.18))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: peer.isBridge ? "building.columns.fill" : "person.fill")
                                .font(.system(size: 20))
                                .foregroundColor(peer.isBridge ? DesignTokens.Colors.primary : DesignTokens.Colors.meshGold)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(peer.name)
                                .font(DesignTokens.Typography.bodyLg)
                                .fontWeight(.semibold)
                                .foregroundColor(DesignTokens.Colors.onSurface)

                            Text(peer.roleTag)
                                .font(DesignTokens.Typography.labelCaps)
                                .foregroundColor(peer.isBridge ? DesignTokens.Colors.primary : DesignTokens.Colors.meshGold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(peer.isBridge ? DesignTokens.Colors.primary.opacity(0.12) : DesignTokens.Colors.meshGold.opacity(0.12))
                                )
                        }

                        Text(peer.role)
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(peer.signalDbm) dBm")
                            .font(DesignTokens.Typography.labelNumeric)
                            .foregroundColor(peer.isBridge ? DesignTokens.Colors.primary : DesignTokens.Colors.meshGold)
                        Text(peer.signalQuality)
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                    }
                }

                Divider()
                    .background(DesignTokens.Colors.surfaceVariant.opacity(0.4))

                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "battery.75")
                            .font(.system(size: 13))
                            .foregroundColor(DesignTokens.Colors.meshGold)
                        Text("\(peer.batteryPct)%")
                            .font(DesignTokens.Typography.labelNumericSm)
                            .foregroundColor(DesignTokens.Colors.onSurface)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(DesignTokens.Colors.surfaceContainerHighest.opacity(0.6)))

                    Spacer()

                    Text(peer.isBridge ? "Bridge Online" : "Relaying Active")
                        .font(DesignTokens.Typography.labelCaps)
                        .foregroundColor(DesignTokens.Colors.onMeshGold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(peer.isBridge ? DesignTokens.Colors.primary : DesignTokens.Colors.meshGold))
                }
            }
            .padding(DesignTokens.Spacing.md)
            .liquidCard(strokeColor: DesignTokens.Colors.meshGold.opacity(0.2))
    }

    // MARK: - Actions
    private func triggerPing() {
        isPinging = true
        routeStatusText = "Broadcasting 2.4GHz BLE discovery beacon..."
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isPinging = false
            routeStatusText = "3 Peers responded: Carol (-42 dBm), Bob (-68 dBm), Gateway (Online)"
        }
    }

    private func triggerSimulateHop() {
        guard !isSimulating else { return }
        isSimulating = true
        routeStatusText = "Packet dispatched → Carol verified cryptographic proof..."

        withAnimation(.easeInOut(duration: 0.8)) {
            packetHopPosition = CGPoint(x: 230, y: 90)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(.easeInOut(duration: 0.8)) {
                packetHopPosition = CGPoint(x: 100, y: 80)
            }
            routeStatusText = "✓ Settlement packet delivered to NPCI Gateway via Carol!"
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            isSimulating = false
            withAnimation {
                packetHopPosition = CGPoint(x: 150, y: 150)
            }
        }
    }
}
