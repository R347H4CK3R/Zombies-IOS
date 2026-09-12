import SwiftUI

@main
struct ZombiesIOSApp: App {
    private var isTranzitRenderTest: Bool {
        ProcessInfo.processInfo.arguments.contains("--tranzit-render-test")
    }

    var body: some Scene {
        WindowGroup {
            if isTranzitRenderTest {
                SyntheticTranzitRenderTestView()
            } else {
                ContentView()
            }
        }
    }
}
