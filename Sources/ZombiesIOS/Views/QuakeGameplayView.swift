import SwiftUI
import MetalKit
import simd

struct QuakeGameplayView: UIViewRepresentable {
    var move: CGSize
    var look: CGSize
    var firing: Bool
    var aiming: Bool
    var jumpPulse: Int
    var reloadPulse: Int
    let package: BO2RuntimePackage

    func makeCoordinator() -> Coordinator { Coordinator(package: package) }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = MTLClearColor(red: 0.025, green: 0.028, blue: 0.032, alpha: 1)
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.setInput(
            move: move,
            look: look,
            firing: firing,
            aiming: aiming,
            jumpPulse: jumpPulse,
            reloadPulse: reloadPulse
        )
    }

    static func dismantleUIView(_ uiView: MTKView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        private struct Uniforms { var mvp: simd_float4x4 }

        private let package: BO2RuntimePackage
        private let runtime: QuakeRuntimeController?
        private var loadError: Error?
        private var commandQueue: MTLCommandQueue?
        private var pipeline: MTLRenderPipelineState?
        private var depthState: MTLDepthStencilState?
        private var vertexBuffer: MTLBuffer?
        private var indexBuffer: MTLBuffer?
        private var lastTimestamp = CACurrentMediaTime()
        private var frameCount = 0
        private var move = CGSize.zero
        private var look = CGSize.zero
        private var firing = false
        private var aiming = false
        private var jumpPulse = 0
        private var reloadPulse = 0

        init(package: BO2RuntimePackage) {
            self.package = package
            do {
                runtime = try QuakeRuntimeController(package: package)
            } catch {
                runtime = nil
                loadError = error
            }
            super.init()
        }

        func attach(to view: MTKView) {
            guard let device = view.device else { return }
            commandQueue = device.makeCommandQueue()
            buildBuffers(device: device)
            buildPipeline(device: device, pixelFormat: view.colorPixelFormat, depthFormat: view.depthStencilPixelFormat)
            view.delegate = self
        }

        func stop() { }

        func setInput(move: CGSize, look: CGSize, firing: Bool, aiming: Bool, jumpPulse: Int, reloadPulse: Int) {
            self.move = move
            self.look = look
            self.firing = firing
            self.aiming = aiming
            self.jumpPulse = jumpPulse
            self.reloadPulse = reloadPulse
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }

        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let descriptor = view.currentRenderPassDescriptor,
                  let queue = commandQueue,
                  let pipeline,
                  let vertexBuffer,
                  let indexBuffer else { return }

            let now = CACurrentMediaTime()
            let dt = Float(min(0.05, max(1.0 / 240.0, now - lastTimestamp)))
            lastTimestamp = now

            runtime?.setInput(
                move: move,
                look: look,
                firing: firing,
                aiming: aiming,
                jumpPulse: jumpPulse,
                reloadPulse: reloadPulse
            )
            let state = runtime?.step(deltaSeconds: dt) ?? fallbackState()

            let aspect = max(0.1, Float(view.drawableSize.width / max(1, view.drawableSize.height)))
            let projection = Self.perspective(fovyRadians: aiming ? 0.87 : 1.22, aspect: aspect, near: 0.1, far: farPlane())
            let viewMatrix = Self.viewMatrix(position: state.position, yaw: state.yaw, pitch: state.pitch)
            var uniforms = Uniforms(mvp: projection * viewMatrix)

            guard let buffer = queue.makeCommandBuffer(),
                  let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
            encoder.setRenderPipelineState(pipeline)
            if let depthState { encoder.setDepthStencilState(depthState) }
            encoder.setCullMode(.none)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: package.indices.count,
                indexType: .uint32,
                indexBuffer: indexBuffer,
                indexBufferOffset: 0
            )
            encoder.endEncoding()
            buffer.present(drawable)
            buffer.commit()

            frameCount += 1
            if CIValidationMode.isEnabled && frameCount % 12 == 0 {
                writeDiagnostics(state: state)
            }
        }

        private func buildBuffers(device: MTLDevice) {
            let positions: [SIMD4<Float>] = package.vertices.map { SIMD4<Float>($0.x, $0.y, $0.z, 1) }
            vertexBuffer = positions.withUnsafeBytes {
                device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared)
            }
            indexBuffer = package.indices.withUnsafeBytes {
                device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared)
            }
        }

        private func buildPipeline(device: MTLDevice, pixelFormat: MTLPixelFormat, depthFormat: MTLPixelFormat) {
            let source = """
            #include <metal_stdlib>
            using namespace metal;
            struct Uniforms { float4x4 mvp; };
            vertex float4 zq3_vertex(uint id [[vertex_id]], const device float4 *positions [[buffer(0)]], constant Uniforms &u [[buffer(1)]]) {
                return u.mvp * positions[id];
            }
            fragment half4 zq3_fragment() { return half4(0.70h, 0.76h, 0.68h, 1.0h); }
            """
            guard let library = try? device.makeLibrary(source: source, options: nil),
                  let vertex = library.makeFunction(name: "zq3_vertex"),
                  let fragment = library.makeFunction(name: "zq3_fragment") else { return }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            descriptor.colorAttachments[0].pixelFormat = pixelFormat
            descriptor.depthAttachmentPixelFormat = depthFormat
            pipeline = try? device.makeRenderPipelineState(descriptor: descriptor)

            let depth = MTLDepthStencilDescriptor()
            depth.isDepthWriteEnabled = true
            depth.depthCompareFunction = .lessEqual
            depthState = device.makeDepthStencilState(descriptor: depth)
        }

        private func fallbackState() -> QuakeRuntimeController.PlayerState {
            let b = package.bounds
            return QuakeRuntimeController.PlayerState(
                position: SIMD3<Float>((b.min.x + b.max.x) * 0.5, b.max.y + 64, (b.min.z + b.max.z) * 0.5),
                yaw: 0,
                pitch: -0.25,
                grounded: false,
                frameNumber: UInt64(frameCount)
            )
        }

        private func farPlane() -> Float {
            let d = package.bounds.max.simd - package.bounds.min.simd
            return max(2048, simd_length(d) * 3.0)
        }

        private func writeDiagnostics(state: QuakeRuntimeController.PlayerState) {
            let diag = CIRenderDiagnostics(
                vertexCount: package.vertices.count,
                indexCount: package.indices.count,
                triangleCount: package.triangleCount,
                sceneNodeCount: 1,
                cameraPosition: CIVector3(state.position),
                worldBoundsMin: CIVector3(package.bounds.min.simd),
                worldBoundsMax: CIVector3(package.bounds.max.simd),
                worldInFrustum: package.triangleCount > 0,
                frameCount: frameCount,
                ready: pipeline != nil && runtime != nil && loadError == nil,
                lastFrameTimestamp: Date().timeIntervalSince1970
            )
            CIRenderDiagnosticsStore.write(diag)
        }

        private static func perspective(fovyRadians: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
            let y = 1 / tan(fovyRadians * 0.5)
            let x = y / aspect
            let z = far / (near - far)
            return simd_float4x4(
                SIMD4<Float>(x, 0, 0, 0),
                SIMD4<Float>(0, y, 0, 0),
                SIMD4<Float>(0, 0, z, -1),
                SIMD4<Float>(0, 0, z * near, 0)
            )
        }

        private static func viewMatrix(position: SIMD3<Float>, yaw: Float, pitch: Float) -> simd_float4x4 {
            let cp = cos(pitch)
            let forward = simd_normalize(SIMD3<Float>(-sin(yaw) * cp, -sin(pitch), -cos(yaw) * cp))
            var right = simd_cross(forward, SIMD3<Float>(0, 1, 0))
            if simd_length_squared(right) < 0.0001 { right = SIMD3<Float>(1, 0, 0) }
            right = simd_normalize(right)
            let up = simd_normalize(simd_cross(right, forward))
            return simd_float4x4(
                SIMD4<Float>(right.x, up.x, -forward.x, 0),
                SIMD4<Float>(right.y, up.y, -forward.y, 0),
                SIMD4<Float>(right.z, up.z, -forward.z, 0),
                SIMD4<Float>(-simd_dot(right, position), -simd_dot(up, position), simd_dot(forward, position), 1)
            )
        }
    }
}
