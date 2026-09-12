import SwiftUI

struct SyntheticTranzitRenderTestView: View {
    @State private var health = 100
    @State private var ammo = 30
    @State private var kills = 0
    @State private var metrics = RenderValidationMetrics.zero

    private let world = Self.makeWorld()

    var body: some View {
        ZStack(alignment: .topLeading) {
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
                mapSeed: 0xB02,
                runtimeMesh: nil,
                renderableWorld: world,
                onMetrics: receiveMetrics
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 3) {
                Text("SYNTHETIC TRANZIT RENDER TEST")
                    .font(.caption.bold().monospaced())
                Text("SURF \(metrics.drawnSurfaces) TRI \(metrics.submittedTriangles)")
                    .font(.caption2.monospaced())
                Text("MAT \(metrics.nonFallbackMaterials) TEX \(metrics.residentTextures)")
                    .font(.caption2.monospaced())
            }
            .foregroundStyle(.white)
            .padding(8)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
            .padding(8)
        }
        .preferredColorScheme(.dark)
    }

    private func receiveMetrics(_ value: RenderValidationMetrics) {
        metrics = value
        Self.writeMetrics(value)
    }

    private static func writeMetrics(_ value: RenderValidationMetrics) {
        do {
            guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(value)
            try data.write(to: documents.appendingPathComponent("render-metrics.json"), options: .atomic)
        } catch {
            fputs("Synthetic render metrics write failed: \(error)\n", stderr)
        }
    }

    private static func makeWorld() -> T6RenderableWorld {
        let imageID = T6AssetID(zoneName: "synthetic-ci", typeID: 8, assetIndex: 0, tableOffset: 0)
        let materialID = T6AssetID(zoneName: "synthetic-ci", typeID: 6, assetIndex: 0, tableOffset: 0)

        let pixels = Data([
            220, 94, 35, 255,   52, 100, 170, 255,
            44, 155, 92, 255,   205, 174, 61, 255
        ])
        let texture = T6DecodedTexture(
            imageID: imageID,
            width: 2,
            height: 2,
            depth: 1,
            mipCount: 1,
            format: .rgba8Unorm,
            hasAlpha: false,
            rgba8: pixels
        )
        let material = T6RenderableMaterial(
            materialID: materialID,
            baseColorTexture: texture,
            alphaMode: .opaque,
            isFallback: false
        )

        let floor = T6WorldSurface(
            vertices: [
                SIMD3<Float>(-8, 0, -8), SIMD3<Float>(8, 0, -8),
                SIMD3<Float>(8, 0, 8), SIMD3<Float>(-8, 0, 8)
            ],
            normals: Array(repeating: SIMD3<Float>(0, 1, 0), count: 4),
            uvs: [SIMD2<Float>(0, 0), SIMD2<Float>(4, 0), SIMD2<Float>(4, 4), SIMD2<Float>(0, 4)],
            indices: [0, 1, 2, 0, 2, 3],
            materialID: materialID,
            rawMaterialPointer: 1,
            sourceSurfaceIndex: 0
        )
        let wall = T6WorldSurface(
            vertices: [
                SIMD3<Float>(-8, 0, -8), SIMD3<Float>(8, 0, -8),
                SIMD3<Float>(8, 7, -8), SIMD3<Float>(-8, 7, -8)
            ],
            normals: Array(repeating: SIMD3<Float>(0, 0, 1), count: 4),
            uvs: [SIMD2<Float>(0, 0), SIMD2<Float>(4, 0), SIMD2<Float>(4, 2), SIMD2<Float>(0, 2)],
            indices: [0, 2, 1, 0, 3, 2],
            materialID: materialID,
            rawMaterialPointer: 1,
            sourceSurfaceIndex: 1
        )

        return T6RenderableWorld(
            surfaces: [floor, wall],
            materials: [materialID: material],
            props: [],
            firstPersonWeapon: nil,
            spawnPosition: SIMD3<Float>(0, 1.7, 5),
            spawnForward: SIMD3<Float>(0, 0, -1),
            usesDiagnosticGeometry: false,
            diagnostics: T6RenderDiagnostics(
                unresolvedMaterialPointers: [],
                unsupportedTextureFormats: [],
                notes: ["redistribution-safe synthetic CI fixture"]
            )
        )
    }
}
