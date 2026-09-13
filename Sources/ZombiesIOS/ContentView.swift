import SwiftUI

/// Compatibility entry point retained for older navigation/tests.
/// Production gameplay is owned by BO2QuakeRootView -> QuakeGameplayView.
struct ContentView: View {
    var body: some View {
        BO2QuakeRootView()
    }

    @ViewBuilder
    private func quakeGameplay(for package: BO2RuntimePackage) -> some View {
        QuakeGameplayView(package: package)
    }
}
