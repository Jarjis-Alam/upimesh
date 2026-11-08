import SwiftUI

/// Floating Liquid Glass Pill Tab Bar ("Obsidian Kinetic")
///
/// Faithfully reproduces the detached floating dock architecture from `ios 2/obsidian_kinetic/` and screen prototypes:
/// - Order: Wallets, Pay, Radar, Ledger.
/// - 64pt height capsule detached 16pt above safe area bottom.
/// - Frosted obsidian container with specular rim highlight.
/// - Active kinetic amber pill highlight with intense glow.
public enum MeshTab: String, CaseIterable, Identifiable {
    case wallets = "wallets"
    case pay = "pay"
    case radar = "radar"
    case ledger = "ledger"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .wallets: return "Wallets"
        case .pay: return "Pay"
        case .radar: return "Radar"
        case .ledger: return "Ledger"
        }
    }

    public var iconName: String {
        switch self {
        case .wallets: return "creditcard.fill"
        case .pay: return "bolt.fill"
        case .radar: return "antenna.radiowaves.left.and.right"
        case .ledger: return "doc.text.fill"
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
                            .fontWeight(isSelected ? .bold : .medium)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .foregroundColor(isSelected ? DesignTokens.Colors.onMeshGold : DesignTokens.Colors.onSurfaceVariant)
                    .background(
                        ZStack {
                            if isSelected {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: "FDE047"), Color(hex: "FACC15"), Color(hex: "EAB308")],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .matchedGeometryEffect(id: "activeTabPill", in: tabAnimation)
                                    .overlay(
                                        Capsule()
                                            .stroke(
                                                LinearGradient(
                                                    colors: [Color.white.opacity(0.6), Color.white.opacity(0.15)],
                                                    startPoint: .top,
                                                    endPoint: .bottom
                                                ),
                                                lineWidth: 1
                                            )
                                    )
                                    .shadow(color: DesignTokens.Colors.primaryContainer.opacity(0.65), radius: 14, x: 0, y: 2)
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
                .fill(DesignTokens.Colors.surfaceContainerHigh.opacity(0.65))
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                )
        )
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.75), radius: 24, x: 0, y: 12)
        .shadow(color: DesignTokens.Colors.primaryContainer.opacity(0.10), radius: 20, x: 0, y: 0)
        .padding(.horizontal, DesignTokens.Spacing.margin)
        .padding(.bottom, 6)
    }
}
