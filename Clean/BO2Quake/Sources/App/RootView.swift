import SwiftUI

struct RootView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 12) {
                Text("BO2 QUAKE")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("Clean native runtime")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
