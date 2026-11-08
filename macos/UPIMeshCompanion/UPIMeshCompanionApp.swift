import SwiftUI

@main
struct UPIMeshCompanionApp: App {
    var body: some Scene {
        WindowGroup {
            MacCompanionView()
                .frame(minWidth: 1040, minHeight: 640)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1300, height: 820)
    }
}
