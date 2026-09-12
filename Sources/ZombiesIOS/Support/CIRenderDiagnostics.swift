import Foundation
import SceneKit

struct CIVector3: Codable {
    let x: Float
    let y: Float
    let z: Float

    init(_ v: SCNVector3) {
        x = v.x
        y = v.y
        z = v.z
    }
}

struct CIRenderDiagnostics: Codable {
    var vertexCount: Int = 0
    var indexCount: Int = 0
    var triangleCount: Int = 0
    var sceneNodeCount: Int = 0
    var cameraPosition = CIVector3(SCNVector3Zero)
    var worldBoundsMin = CIVector3(SCNVector3Zero)
    var worldBoundsMax = CIVector3(SCNVector3Zero)
    var worldInFrustum = false
    var frameCount = 0
    var ready = false
    var lastFrameTimestamp: Double = 0
}

enum CIRenderDiagnosticsStore {
    static var url: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("ci-render-diagnostics.json")
    }

    static func write(_ diagnostics: CIRenderDiagnostics) {
        guard CIValidationMode.isEnabled else { return }
        do {
            let data = try JSONEncoder().encode(diagnostics)
            let target = url
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let tmp = target.appendingPathExtension("tmp")
            try data.write(to: tmp, options: .atomic)
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: tmp, to: target)
        } catch {
            print("CI_DIAGNOSTICS_WRITE_FAILED \(error.localizedDescription)")
        }
    }
}
