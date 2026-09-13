import SwiftUI

struct RootView: View {
    @State private var world: WorldRuntimeAsset?
    @State private var loadError: String?
    @State private var attemptedLoad = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            if let world {
                MetalWorldView(asset: world)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 3) {
                    Text("BO2 QUAKE")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                    Text(world.id)
                        .font(.caption.monospaced())
                    Text("\(world.metadata.surfaceCount) surfaces • \(world.metadata.indexCount / 3) triangles")
                        .font(.caption2.monospaced())
                }
                .padding(10)
                .foregroundStyle(.white)
                .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
                .padding()
            } else {
                VStack(spacing: 12) {
                    Text("BO2 QUAKE")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text(loadError ?? "Loading native GameData…")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
        }
        .onAppear(perform: loadBundledWorldOnce)
    }

    private func loadBundledWorldOnce() {
        guard !attemptedLoad else { return }
        attemptedLoad = true
        do {
            let gameData = try GameDataLoader().loadBundled()
            world = try WorldRuntimeAsset.loadFirst(from: gameData)
        } catch {
            loadError = error.localizedDescription
        }
    }
}
