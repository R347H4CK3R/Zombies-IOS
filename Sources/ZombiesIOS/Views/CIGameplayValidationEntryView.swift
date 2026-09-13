import SwiftUI

struct CIGameplayValidationEntryView: View {
    @State private var heartbeat = 0
    private let package = CIRuntimeMeshFixture.makePackage()

    var body: some View {
        ZStack {
            QuakeGameplayView(package: package)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Text("CI QUAKE RUNTIME VALIDATION")
                        .font(.caption.bold().monospaced())
                        .foregroundStyle(.green)
                    Spacer()
                    Text("METAL / C RUNTIME")
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
                    vertexCount: package.vertices.count,
                    indexCount: package.indices.count,
                    triangleCount: package.indices.count / 3,
                    sceneNodeCount: 1,
                    cameraPosition: CIVector3(0, 2, 0),
                    worldBoundsMin: CIVector3(-8, 0, -8),
                    worldBoundsMax: CIVector3(8, 6, 8),
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
