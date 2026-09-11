import SwiftUI

struct TranzitNativeGameplayView: View {
    let loadedArea: TranzitLoadedArea
    let rootURL: URL
    let sharedContainers: [TranzitLoadedResource]
    let audioBankCount: Int

    @State private var move = CGSize.zero
    @State private var look = CGSize.zero
    @State private var firing = false
    @State private var aiming = false
    @State private var jumpPulse = 0
    @State private var reloadPulse = 0
    @State private var health = 100
    @State private var ammo = 30
    @State private var kills = 0
    @State private var cachedWorld: TranzitCachedWorld?
    @State private var status = "SOURCE CHECK"
    @State private var detail = "Checking native Tranzit cache…"
    @State private var errorMessage: String?
    @State private var generation = 0

    private var resources: [TranzitLoadedResource] {
        var seen = Set<String>()
        return ([loadedArea.fastFile] + sharedContainers).filter { seen.insert($0.relativePath.lowercased()).inserted }
    }

    var body: some View {
        GeometryReader { _ in
            ZStack {
                NativeFPSSceneView(
                    move: move,
                    look: look,
                    firing: firing,
                    aiming: aiming,
                    jumpPulse: jumpPulse,
                    reloadPulse: reloadPulse,
                    health: $health,
                    ammo: $ammo,
                    kills: $kills,
                    mapSeed: generation,
                    runtimeMesh: nil,
                    cachedWorld: cachedWorld
                )
                .id(generation)
                .ignoresSafeArea()

                VStack(spacing: 6) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("TRANZIT").font(.headline.monospaced()).foregroundStyle(.white)
                            Text("SPAWN \(loadedArea.area.displayName.uppercased())").font(.caption2.bold().monospaced()).foregroundStyle(.white.opacity(0.72))
                            Text("HP \(health)").font(.title3.bold().monospaced()).foregroundStyle(health > 35 ? .white : .red)
                            Text("KILLS \(kills)").font(.caption.bold().monospaced()).foregroundStyle(.white.opacity(0.9))
                        }
                        Spacer(minLength: 70)
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("\(ammo) / 30").font(.title2.bold().monospaced()).foregroundStyle(ammo > 5 ? .white : .orange)
                            Text(status).font(.caption2.bold().monospaced()).foregroundStyle(errorMessage == nil ? .green : .orange)
                            Text(detail).lineLimit(2).multilineTextAlignment(.trailing).font(.caption2.monospaced()).foregroundStyle(.white.opacity(0.7))
                        }
                        .padding(.trailing, 92)
                    }
                    .padding(.leading).padding(.top, 6).background(.black.opacity(0.32))

                    if let world = cachedWorld {
                        HStack(spacing: 8) {
                            Text("NATIVE CACHE")
                            Text("SURFACES \(world.surfaceCount)")
                            Text("VERTICES \(world.positions.count)")
                            Text("TRIANGLES \(world.triangleCount)")
                            Text("MATERIALS \(world.materials.count)")
                        }
                        .font(.caption2.bold().monospaced()).foregroundStyle(.green.opacity(0.95))
                        .padding(.horizontal, 8).padding(.vertical, 3).background(.black.opacity(0.4), in: Capsule())
                    }
                    if let errorMessage {
                        Text(errorMessage).font(.caption2).foregroundStyle(.orange).multilineTextAlignment(.center)
                            .padding(6).background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal)
                    }
                    Spacer()
                    Text("+").font(.system(size: aiming ? 22 : 34, weight: .light, design: .monospaced)).foregroundStyle(.white).shadow(radius: 2)
                    Spacer()
                }
                .allowsHitTesting(false)

                HStack(spacing: 0) { controlZone(isMove: true); controlZone(isMove: false) }

                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        stick(position: move, label: "MOVE")
                        Spacer()
                        VStack(spacing: 12) {
                            HStack(spacing: 12) { actionButton("ADS", active: aiming) { aiming.toggle() }; fireButton }
                            HStack(spacing: 12) { actionButton("RELOAD", active: false) { reloadPulse &+= 1 }; actionButton("JUMP", active: false) { jumpPulse &+= 1 } }
                        }
                        stick(position: look, label: "LOOK")
                    }
                    .padding(.horizontal, 16).padding(.bottom, 10)
                }
            }
        }
        .navigationTitle("Tranzit Native")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .task { await loadNativeCache() }
    }

    private var fireButton: some View {
        Text("FIRE").font(.caption.bold()).foregroundStyle(.white).frame(width: 72, height: 52)
            .background(firing ? .white.opacity(0.38) : .black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.4)))
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .gesture(DragGesture(minimumDistance: 0).onChanged { _ in firing = true }.onEnded { _ in firing = false })
    }

    private func loadNativeCache() async {
        do {
            let importer = try TranzitNativeImporter()
            let world = try await importer.loadOrRebuild(rootURL: rootURL, resources: resources) { progress in
                Task { @MainActor in
                    status = progress.stage.rawValue.uppercased()
                    detail = progress.detail
                    if progress.detail.contains("REBUILD FAILED") { errorMessage = progress.detail }
                }
            }
            await MainActor.run {
                cachedWorld = world
                generation &+= 1
                status = "CACHE READY"
                detail = "\(world.surfaceCount) surfaces · \(world.positions.count) vertices · \(world.triangleCount) triangles · \(world.materials.count) materials"
            }
        } catch {
            await MainActor.run {
                status = "NATIVE IMPORT FAILED"
                detail = error.localizedDescription
                errorMessage = error.localizedDescription
            }
        }
    }

    private func controlZone(isMove: Bool) -> some View {
        Color.clear.contentShape(Rectangle()).gesture(
            DragGesture(minimumDistance: 0).onChanged { value in
                let start = value.startLocation, now = value.location
                let delta = CGSize(width: now.x - start.x, height: now.y - start.y)
                if isMove { move = clamp(delta, radius: 62) } else { look = delta }
            }.onEnded { _ in if isMove { move = .zero } else { look = .zero } }
        )
    }

    private func stick(position: CGSize, label: String) -> some View {
        ZStack {
            Circle().fill(.black.opacity(0.30)).overlay(Circle().stroke(.white.opacity(0.28))).frame(width: 104, height: 104)
            Circle().fill(.white.opacity(0.26)).frame(width: 50, height: 50).offset(x: position.width * 0.55, y: position.height * 0.55)
            Text(label).font(.caption2.bold()).foregroundStyle(.white.opacity(0.55)).offset(y: 68)
        }.allowsHitTesting(false)
    }

    private func actionButton(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(.caption.bold()).foregroundStyle(.white).frame(width: 72, height: 42).background(active ? .white.opacity(0.35) : .black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.35))) }
    }

    private func clamp(_ value: CGSize, radius: CGFloat) -> CGSize {
        let length = sqrt(value.width * value.width + value.height * value.height)
        guard length > radius, length > 0 else { return value }
        let scale = radius / length
        return CGSize(width: value.width * scale, height: value.height * scale)
    }
}
