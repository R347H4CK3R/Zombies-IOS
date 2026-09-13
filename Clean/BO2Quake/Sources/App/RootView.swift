import SwiftUI

struct RootView: View {
    @State private var world: WorldRuntimeAsset?
    @State private var coordinator: BO2GameCoordinator?
    @State private var loadError: String?
    @State private var attemptedLoad = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let world, let coordinator {
                BO2GameplayView(asset: world, coordinator: coordinator)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 12) {
                    Text("BO2 QUAKE")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text(loadError ?? "Loading self-contained GameData…")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
        }
        .onAppear(perform: loadBundledGameOnce)
    }

    private func loadBundledGameOnce() {
        guard !attemptedLoad else { return }
        attemptedLoad = true
        do {
            let gameData = try GameDataLoader().loadBundled()
            let assets = RuntimeAssetLoader(gameData: gameData)
            let loadedWorld = try assets.firstWorld()
            let weapon = try assets.firstWeapon()
            world = loadedWorld
            coordinator = try BO2GameCoordinator(world: loadedWorld, weaponDefinition: weapon)
        } catch {
            loadError = error.localizedDescription
        }
    }
}
