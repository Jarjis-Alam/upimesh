import SwiftUI
import Combine

/// Predictive Adaptive Offline Provisioning Advisory Card.
///
/// Displays real-time research advisory telemetry received from the Mac simulation station
/// over direct AWDL/BLE MultipeerConnectivity peer transport without internet dependency.
///
/// CRITICAL FINANCIAL SAFETY INVARIANT:
/// This view is STRICTLY ADVISORY. It does NOT automatically mutate allowance vouchers,
/// wallet balances, offline escrow, or cryptographic payment records.
public struct PredictiveAdvisoryCardView: View {

    @ObservedObject private var transport = MeshPeerTransportService.shared
    @State private var now: Date = Date()

    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    public init() {}

    public var body: some View {
        Group {
            if let pred = transport.latestPrediction {
                activeAdvisoryContent(pred)
            } else {
                awaitingStationContent
            }
        }
        .liquidCard(
            cornerRadius: DesignTokens.CornerRadius.card,
            strokeColor: strokeColorForCurrentState,
            backgroundColor: DesignTokens.Colors.surfaceContainer.opacity(0.85)
        )
        .onReceive(timer) { newTime in
            self.now = newTime
        }
    }

    // MARK: - Advisory Risk Status Enum

    public enum AdvisoryRiskStatus {
        case normal
        case elevatedRisk
        case highRisk
        case offline
        case staleData

        public var title: String {
            switch self {
            case .normal: return "NORMAL"
            case .elevatedRisk: return "ELEVATED RISK"
            case .highRisk: return "HIGH RISK"
            case .offline: return "OFFLINE"
            case .staleData: return "STALE DATA"
            }
        }

        public var color: Color {
            switch self {
            case .normal: return DesignTokens.Colors.primary
            case .elevatedRisk: return DesignTokens.Colors.meshAmber
            case .highRisk: return DesignTokens.Colors.alertRed
            case .offline: return DesignTokens.Colors.secondary
            case .staleData: return Color.orange
            }
        }
    }

    private func computeRiskStatus(for pred: PeerPredictionMessage) -> AdvisoryRiskStatus {
        if transport.isPredictionStale {
            return .staleData
        }
        if pred.networkStatus.contains("OFFLINE") || pred.networkStatus.contains("OUTAGE") || pred.signalDbm <= -128 {
            return .offline
        }
        if pred.robustOutageProbability >= 0.70 {
            return .highRisk
        }
        if pred.robustOutageProbability >= 0.25 {
            return .elevatedRisk
        }
        return .normal
    }

    // MARK: - Dynamic Card Border Stroke

    private var strokeColorForCurrentState: Color {
        guard let pred = transport.latestPrediction else {
            return DesignTokens.Colors.glassStrokeDim
        }
        let status = computeRiskStatus(for: pred)
        return status.color.opacity(0.4)
    }

    // MARK: - Active Advisory Content

    private func activeAdvisoryContent(_ pred: PeerPredictionMessage) -> some View {
        let status = computeRiskStatus(for: pred)

        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {

            // Header Row: Research Title, Simulated Tag, and Prominent Status Pill
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(status.color)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("RESEARCH ADVISORY")
                            .font(DesignTokens.Typography.labelCaps)
                            .foregroundColor(DesignTokens.Colors.onSurface)
                            .tracking(1.0)

                        Text("SIMULATED RESEARCH TELEMETRY")
                            .font(.system(size: 8, weight: .black))
                            .foregroundColor(DesignTokens.Colors.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(DesignTokens.Colors.secondary.opacity(0.15)))
                    }

                    Text("Network disruption forecast and reserve guidance")
                        .font(DesignTokens.Typography.caption)
                        .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                }

                Spacer()

                // Status Pill: NORMAL / ELEVATED RISK / HIGH RISK / OFFLINE / STALE DATA
                HStack(spacing: 5) {
                    Circle()
                        .fill(status.color)
                        .frame(width: 6, height: 6)
                    Text(status.title)
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(status.color)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(status.color.opacity(0.14)))
            }

            Divider()
                .background(DesignTokens.Colors.glassStrokeDim)
                .padding(.vertical, 2)

            // Recommended Reserve Hero — MOST PROMINENT ELEMENT
            VStack(alignment: .leading, spacing: 3) {
                Text("RECOMMENDED OFFLINE RESERVE")
                    .font(DesignTokens.Typography.labelCaps)
                    .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                    .tracking(0.8)

                HStack(alignment: .firstTextBaseline) {
                    // Massive prominent currency display
                    Text(String(format: "₹%.0f", pred.recommendedReserveInr))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(DesignTokens.Colors.primary)

                    // Delta indicator badge
                    deltaBadge(pred.deltaReserveInr)

                    Spacer()

                    // Previous reserve comparison
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("PREVIOUS")
                            .font(DesignTokens.Typography.labelCaps)
                            .foregroundColor(DesignTokens.Colors.onSurfaceVariant)

                        Text(String(format: "₹%.0f", pred.previousReserveInr))
                            .font(DesignTokens.Typography.labelNumericLg)
                            .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                    }
                }
            }
            .padding(10)
            .background(DesignTokens.Colors.surfaceContainerLowest.opacity(0.5))
            .cornerRadius(DesignTokens.CornerRadius.sm)

            // Telemetry Metric Grid (4 Cells)
            VStack(spacing: DesignTokens.Spacing.xs) {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    metricCell(
                        title: "OUTAGE PROBABILITY",
                        value: String(format: "%.0f%%", pred.robustOutageProbability * 100),
                        subtitle: String(format: "Point: %.0f%% · %d dBm", pred.outageProbability * 100, pred.signalDbm),
                        icon: "antenna.radiowaves.left.and.right",
                        tint: outageColor(pred.robustOutageProbability)
                    )

                    metricCell(
                        title: "PREDICTED OUTAGE DURATION",
                        value: String(format: "%.1fh", pred.predictedDurationHours),
                        subtitle: String(format: "±%.1fh duration variance", pred.durationStdHours),
                        icon: "clock.badge.exclamationmark",
                        tint: DesignTokens.Colors.secondary
                    )
                }

                HStack(spacing: DesignTokens.Spacing.xs) {
                    metricCell(
                        title: "EXPECTED OFFLINE DEMAND",
                        value: String(format: "₹%.0f", pred.predictedDemandInr),
                        subtitle: String(format: "σ = ₹%.0f compound variance", pred.compoundDemandStdInr),
                        icon: "cart.fill",
                        tint: DesignTokens.Colors.tertiary
                    )

                    metricCell(
                        title: "UNCERTAINTY & CONFIDENCE",
                        value: String(format: "+₹%.0f", pred.uncertaintyMarginInr),
                        subtitle: String(format: "Floor: ₹%.0f · Conf: %.0f%%", pred.safetyFloorInr, pred.confidenceLevel * 100),
                        icon: "shield.lefthalf.filled",
                        tint: DesignTokens.Colors.meshGold
                    )
                }
            }

            // Strategy Comparison Benchmark Strip
            VStack(alignment: .leading, spacing: 4) {
                Text("STRATEGY BENCHMARK ALLOCATIONS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                    .tracking(0.6)

                HStack(spacing: 6) {
                    strategyPill(name: "Fixed ₹500", amount: pred.strategySnapshot.fixedAllowanceInr, isActive: false)
                    strategyPill(name: "Demand-Only", amount: pred.strategySnapshot.demandOnlyInr, isActive: false)
                    strategyPill(name: "Proposed M1", amount: pred.strategySnapshot.proposedM1Inr, isActive: false)
                    strategyPill(name: "Uncertainty M2", amount: pred.strategySnapshot.uncertaintyM2Inr, isActive: true)
                }
            }
            .padding(8)
            .background(DesignTokens.Colors.surfaceContainerLowest.opacity(0.6))
            .cornerRadius(DesignTokens.CornerRadius.sm)

            // Plain-English Recommendation Narrative
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(DesignTokens.Colors.secondary)
                    .padding(.top, 2)

                Text(pred.recommendationNarrative)
                    .font(DesignTokens.Typography.bodySm)
                    .foregroundColor(DesignTokens.Colors.onSurface)
                    .lineSpacing(2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignTokens.Colors.surfaceContainerHigh.opacity(0.5))
            .cornerRadius(DesignTokens.CornerRadius.sm)

            // Transport Status & Sequence Metadata Footer
            HStack(alignment: .center) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(transport.connectedPeer != nil ? DesignTokens.Colors.primary : DesignTokens.Colors.onSurfaceVariant)
                        .frame(width: 5, height: 5)

                    Text(connectionStatusLabel)
                        .font(DesignTokens.Typography.labelNumericSm)
                        .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                }

                Spacer()

                HStack(spacing: 6) {
                    Text("Seq #\(pred.sequenceNumber)")
                        .font(DesignTokens.Typography.labelNumericSm)
                        .foregroundColor(DesignTokens.Colors.onSurfaceVariant)

                    Text("·")
                        .foregroundColor(DesignTokens.Colors.onSurfaceVariant)

                    Text(elapsedTimeString)
                        .font(DesignTokens.Typography.labelNumericSm)
                        .foregroundColor(transport.isPredictionStale ? DesignTokens.Colors.meshAmber : DesignTokens.Colors.onSurfaceVariant)
                }
            }

            // Financial Safety Disclaimer
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(DesignTokens.Colors.meshGold)

                Text("Advisory only. Does not alter your bank allowance voucher, local ledger, or wallet balance.")
                    .font(.system(size: 10))
                    .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
            }
            .padding(.top, 2)
        }
        .padding(DesignTokens.Spacing.md)
    }

    // MARK: - Awaiting Mac Station Content

    private var awaitingStationContent: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis.circle")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(DesignTokens.Colors.onSurfaceVariant)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("RESEARCH ADVISORY")
                            .font(DesignTokens.Typography.labelCaps)
                            .foregroundColor(DesignTokens.Colors.onSurface)
                            .tracking(1.0)

                        Text("SIMULATED RESEARCH TELEMETRY")
                            .font(.system(size: 8, weight: .black))
                            .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(DesignTokens.Colors.surfaceContainerHigh))
                    }

                    Text("Predictive Adaptive Offline Provisioning")
                        .font(DesignTokens.Typography.caption)
                        .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                }

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(DesignTokens.Colors.onSurfaceVariant.opacity(0.5))
                        .frame(width: 6, height: 6)

                    Text("STATION IDLE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(DesignTokens.Colors.surfaceContainerHigh))
            }

            Text("Connect this iPhone to the macOS Research Station over AWDL / Bluetooth (Peer Transport) to stream predictive outage forecasts and uncertainty-aware offline reserve recommendations.")
                .font(DesignTokens.Typography.bodySm)
                .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                .lineSpacing(2)

            HStack(spacing: 6) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 10))
                    .foregroundColor(DesignTokens.Colors.secondary)

                Text("Non-financial research advisory. Production vouchers and balances remain isolated.")
                    .font(.system(size: 10))
                    .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
            }
        }
        .padding(DesignTokens.Spacing.md)
    }

    // MARK: - Helper Views & Components

    private var connectionStatusLabel: String {
        if let peer = transport.connectedPeer {
            return "AWDL Mesh: \(peer.displayName) (0 Internet)"
        } else {
            return "AWDL Mesh: Station Disconnected"
        }
    }

    private func deltaBadge(_ delta: Double) -> some View {
        HStack(spacing: 3) {
            if delta > 0 {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
                Text(String(format: "+₹%.0f", delta))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
            } else if delta < 0 {
                Image(systemName: "arrow.down.right")
                    .font(.system(size: 9, weight: .bold))
                Text(String(format: "-₹%.0f", abs(delta)))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
            } else {
                Image(systemName: "equal")
                    .font(.system(size: 9, weight: .bold))
                Text("Baseline")
                    .font(.system(size: 10, weight: .medium))
            }
        }
        .foregroundColor(delta > 0 ? DesignTokens.Colors.meshAmber : (delta < 0 ? DesignTokens.Colors.secondary : DesignTokens.Colors.onSurfaceVariant))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(
                delta > 0 ? DesignTokens.Colors.meshAmber.opacity(0.15) :
                (delta < 0 ? DesignTokens.Colors.secondary.opacity(0.15) : DesignTokens.Colors.surfaceContainerHigh)
            )
        )
    }

    private func metricCell(title: String, value: String, subtitle: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(tint)
                Text(title)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                    .lineLimit(1)
            }

            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(DesignTokens.Colors.onSurface)

            Text(subtitle)
                .font(.system(size: 9, weight: .regular))
                .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                .lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Colors.surfaceContainerLow)
        .cornerRadius(DesignTokens.CornerRadius.sm)
    }

    private func strategyPill(name: String, amount: Double, isActive: Bool) -> some View {
        VStack(spacing: 2) {
            Text(name)
                .font(.system(size: 8, weight: isActive ? .bold : .medium))
                .foregroundColor(isActive ? DesignTokens.Colors.primary : DesignTokens.Colors.onSurfaceVariant)
                .lineLimit(1)

            Text(String(format: "₹%.0f", amount))
                .font(.system(size: 11, weight: isActive ? .bold : .medium, design: .monospaced))
                .foregroundColor(isActive ? DesignTokens.Colors.primary : DesignTokens.Colors.onSurface)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isActive ? DesignTokens.Colors.primary.opacity(0.15) : DesignTokens.Colors.surfaceContainerHigh.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isActive ? DesignTokens.Colors.primary.opacity(0.4) : Color.clear, lineWidth: 1)
        )
    }

    private func outageColor(_ prob: Double) -> Color {
        if prob >= 0.70 {
            return DesignTokens.Colors.alertRed
        } else if prob >= 0.25 {
            return DesignTokens.Colors.meshAmber
        } else {
            return DesignTokens.Colors.primary
        }
    }

    private var elapsedTimeString: String {
        guard let receivedAt = transport.lastPredictionReceivedAt else {
            return "No updates"
        }
        let elapsed = Int(now.timeIntervalSince(receivedAt))
        if elapsed < 5 {
            return "Updated just now"
        } else if elapsed < 60 {
            return "Updated \(elapsed)s ago"
        } else {
            let mins = elapsed / 60
            return "Updated \(mins)m ago"
        }
    }
}
