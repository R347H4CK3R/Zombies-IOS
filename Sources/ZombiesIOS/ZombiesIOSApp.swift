import SwiftUI

@main
struct ZombiesIOSApp: App {
    var body: some Scene {
        WindowGroup {
            if CIValidationMode.isEnabled {
                CIGameplayValidationEntryView()
            } else {
                BO2QuakeRootView()
            }
        }
    }
}
