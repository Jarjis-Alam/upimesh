import SwiftUI

/// Floating Liquid Glass Pill Tab Bar
///
/// Faithfully reproduces the detached floating dock architecture from `ios_ui/liquid_mesh_upi/DESIGN.md`:
/// - 64-68pt height capsule detached 16pt above safe area bottom.
/// - Frosted obsidian container with specular rim highlight.
/// - Active animated pill highlight with chromatic glow.
public enum MeshTab: String, CaseIterable, Identifiable {
    case radar = "radar"
    case pay = "pay"
    case ledger = "ledger"
    case wallets = "wallets"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .radar: return "Radar"
        case .pay: return "Pay"
        case .ledger: return "Ledger"
        case .wallets: return "Wallets"
        }
    }

    public var iconName: String {
        switch self {
        case .radar: return "dot.radiowaves.left.and.right"
        case .pay: return "indianrupeesign.circle.fill"
        case .ledger: return "doc.text.fill"
        case .wallets: return "wallet.bifold.fill"
        }
    }
}

public struct LiquidTabBar: View {
    @Binding public var selectedTab: MeshTab
    @Namespace private var tabAnimation

    public init(selectedTab: Binding<MeshTab>) {
        self._selectedTab = selectedTab
    }

    public var body: some View {
        HStack(spacing: 8) {
            ForEach(MeshTab.allCases) { tab in
                let isSelected = selectedTab == tab

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 19, weight: isSelected ? .bold : .medium))

                        Text(tab.title)
                            .font(DesignTokens.Typography.labelCaps)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .foregroundColor(isSelected ? DesignTokens.Colors.meshGold : DesignTokens.Colors.onSurfaceVariant)
                    .background(
                        ZStack {
                            if isSelected {
                                Capsule()
                                    .fill(DesignTokens.Colors.meshGold.opacity(0.14))
                                    .matchedGeometryEffect(id: "activeTabPill", in: tabAnimation)
                                    .overlay(
                                        Capsule()
                                            .stroke(DesignTokens.Colors.meshGold.opacity(0.35), lineWidth: 1)
                                    )
                                    .shadow(color: DesignTokens.Colors.meshGold.opacity(0.3), radius: 10, x: 0, y: 2)
                            }
                        }
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(height: 64)
        .background(
            Capsule()
                .fill(DesignTokens.Colors.surfaceContainerLowest.opacity(0.85))
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                )
        )
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [DesignTokens.Colors.glassStrokeLight, DesignTokens.Colors.glassStrokeDim],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.55), radius: 24, x: 0, y: 12)
        .padding(.horizontal, DesignTokens.Spacing.margin)
        .padding(.bottom, 6)
    }
}
