import SwiftUI

@main
struct UPIMeshCompanionApp: App {
    var body: some Scene {
        WindowGroup {
            MacCompanionView()
                .frame(minWidth: 800, minHeight: 520)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 600)
    }
}
