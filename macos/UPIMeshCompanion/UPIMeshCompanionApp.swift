import SwiftUI

@main
struct UPIMeshCompanionApp: App {
    var body: some Scene {
        WindowGroup {
            MacCompanionView()
                .frame(minWidth: 920, minHeight: 580)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1180, height: 760)
    }
}
