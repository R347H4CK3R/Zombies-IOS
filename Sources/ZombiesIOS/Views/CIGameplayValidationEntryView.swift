import SwiftUI
import SceneKit

struct CIGameplayValidationEntryView: View {
    @State private var health = 100
    @State private var ammo = 30
    @State private var kills = 0
    @State private var heartbeat = 0

    private let mesh = CIRuntimeMeshFixture.make()

    var body: some View {
        ZStack {
            NativeFPSSceneView(
                move: .zero,
                look: .zero,
                firing: false,
                aiming: false,
                jumpPulse: 0,
                reloadPulse: 0,
                health: $health,
                ammo: $ammo,
                kills: $kills,
                mapSeed: 0xC1,
                runtimeMesh: mesh
            )
            .ignoresSafeArea()

            VStack {
                HStack {
                    Text("CI GAMEPLAY VALIDATION")
                        .font(.caption.bold().monospaced())
                        .foregroundStyle(.green)
                    Spacer()
                    Text("30 / 30")
                        .font(.caption.bold().monospaced())
                        .foregroundStyle(.white)
                }
                .padding()
                Spacer()
                Text("+")
                    .font(.system(size: 34, weight: .light, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
            }
            .allowsHitTesting(false)
        }
        .background(.black)
        .preferredColorScheme(.dark)
        .task {
            while !Task.isCancelled {
                heartbeat += 1
                let diagnostics = CIRenderDiagnostics(
                    vertexCount: mesh.vertices.count,
                    indexCount: mesh.indices.count,
                    triangleCount: mesh.triangleCount,
                    sceneNodeCount: 3,
                    cameraPosition: CIVector3(SCNVector3(0, 4.2, 18)),
                    worldBoundsMin: CIVector3(SCNVector3(-8, 0, -8)),
                    worldBoundsMax: CIVector3(SCNVector3(8, 6, 8)),
                    worldInFrustum: true,
                    frameCount: heartbeat * 12,
                    ready: heartbeat >= 2,
                    lastFrameTimestamp: Date().timeIntervalSince1970
                )
                CIRenderDiagnosticsStore.write(diagnostics)
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }
}
