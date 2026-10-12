import SwiftUI

/// Root View for UPI Offline Mesh
///
/// Manages the floating LiquidTabBar and tab-switching between the four core screens:
/// - MeshRadarView (Radar)
/// - OfflinePayView (Pay)
/// - MeshLedgerView (Ledger)
/// - MeshWalletsView (Wallets)
public struct ContentView: View {
    @State private var selectedTab: MeshTab = .radar

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            // Spatial dark glass ambient canvas background
            SpatialCanvasBackground()

            // Active Screen Content
            Group {
                switch selectedTab {
                case .radar:
                    MeshRadarView()
                case .pay:
                    OfflinePayView()
                case .ledger:
                    MeshLedgerView()
                case .wallets:
                    MeshWalletsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Floating Detached Liquid Glass Pill Tab Bar
            LiquidTabBar(selectedTab: $selectedTab)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}
