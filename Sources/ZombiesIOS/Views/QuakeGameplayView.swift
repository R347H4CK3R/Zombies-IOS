import SwiftUI
import MetalKit
import Combine

struct QuakeGameplayView: View {
    @StateObject private var controller: QuakeRuntimeController
    @State private var input = QuakeRuntimeController.InputState()
    private let ticker = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    init(package: BO2RuntimePackage) {
        _controller = StateObject(wrappedValue: QuakeRuntimeController(package: package))
    }

    var body: some View {
        ZStack {
            QuakeMetalWorldView(package: controller.package, playerState: controller.playerState)
                .ignoresSafeArea()

            HStack(spacing: 0) {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        input.right = Float(max(-1, min(1, value.translation.width / 70)))
                        input.forward = Float(max(-1, min(1, -value.translation.height / 70)))
                    }.onEnded { _ in
                        input.right = 0; input.forward = 0
                    })
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        input.yawDelta = Float(value.translation.width) * 0.015
                        input.pitchDelta = Float(-value.translation.height) * 0.012
                    }.onEnded { _ in
                        input.yawDelta = 0; input.pitchDelta = 0
                    })
            }

            VStack {
                HStack {
                    Text("BO2 • QUAKE RUNTIME")
                        .font(.caption.bold()).padding(8)
                        .background(.black.opacity(0.55), in: Capsule())
                    Spacer()
                    if let error = controller.runtimeError {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }.padding()
                Spacer()
                HStack(alignment: .bottom) {
                    Text("MOVE")
                        .font(.caption2.bold()).padding(14)
                        .background(.ultraThinMaterial, in: Circle())
                    Spacer()
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            holdButton("AIM") { input.aim = $0 }
                            holdButton("FIRE") { input.fire = $0 }
                        }
                        HStack(spacing: 10) {
                            Button("RELOAD") { input.reload = true }
                                .buttonStyle(RuntimeButtonStyle())
                            Button("JUMP") { input.jump = true }
                                .buttonStyle(RuntimeButtonStyle())
                        }
                    }
                }.padding()
            }
        }
        .foregroundStyle(.white)
        .background(.black)
        .onReceive(ticker) { _ in
            controller.submit(input)
            controller.step()
            input.jump = false
            input.reload = false
            input.yawDelta = 0
            input.pitchDelta = 0
        }
    }

    private func holdButton(_ title: String, set: @escaping (Bool) -> Void) -> some View {
        Text(title).font(.caption.bold()).frame(width: 68, height: 50)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .gesture(DragGesture(minimumDistance: 0).onChanged { _ in set(true) }.onEnded { _ in set(false) })
    }
}

private struct RuntimeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.caption.bold()).frame(width: 68, height: 44)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

struct QuakeMetalWorldView: UIViewRepresentable {
    let package: BO2RuntimePackage
    let playerState: zq3_player_state

    func makeCoordinator() -> Renderer { Renderer(package: package, playerState: playerState) }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.preferredFramesPerSecond = 60
        view.clearColor = MTLClearColorMake(0.025, 0.03, 0.04, 1)
        context.coordinator.attach(to: view)
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.playerState = playerState
    }

    final class Renderer: NSObject, MTKViewDelegate {
        private struct CameraUniforms {
            var position: SIMD4<Float>
            var params: SIMD4<Float> // yaw radians, pitch radians, aspect, vertical FOV tangent
        }

        private var queue: MTLCommandQueue?
        private var pipeline: MTLRenderPipelineState?
        private var depthState: MTLDepthStencilState?
        private var vertexBuffer: MTLBuffer?
        private var indexBuffer: MTLBuffer?
        private var indexCount = 0
        private let package: BO2RuntimePackage
        var playerState: zq3_player_state

        init(package: BO2RuntimePackage, playerState: zq3_player_state) {
            self.package = package
            self.playerState = playerState
        }

        func attach(to view: MTKView) {
            guard let device = view.device else { return }
            queue = device.makeCommandQueue()
            let source = """
            #include <metal_stdlib>
            using namespace metal;
            struct Camera { float4 position; float4 params; };
            struct VOut { float4 position [[position]]; float3 color; };
            vertex VOut vmain(const device float3 *p [[buffer(0)]], constant Camera& camera [[buffer(1)]], uint id [[vertex_id]]) {
                float3 d = p[id] - camera.position.xyz;
                float sy = sin(camera.params.x), cy = cos(camera.params.x);
                float sp = sin(camera.params.y), cp = cos(camera.params.y);
                float vx = cy * d.x - sy * d.z;
                float vz0 = sy * d.x + cy * d.z;
                float vy = cp * d.y - sp * vz0;
                float vz = sp * d.y + cp * vz0;
                float aspect = max(camera.params.z, 0.1);
                float tanHalfFov = max(camera.params.w, 0.1);
                float nearZ = 0.05;
                float farZ = 10000.0;
                VOut o;
                o.position = float4(vx / (aspect * tanHalfFov), vy / tanHalfFov, (farZ / (farZ-nearZ)) * vz - (farZ*nearZ / (farZ-nearZ)), vz);
                o.color = float3(0.42 + clamp(p[id].y * 0.004, -0.15, 0.30), 0.66, 0.78);
                return o;
            }
            fragment float4 fmain(VOut in [[stage_in]]) { return float4(in.color,1.0); }
            """
            guard let library = try? device.makeLibrary(source: source, options: nil),
                  let v = library.makeFunction(name: "vmain"), let f = library.makeFunction(name: "fmain") else { return }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = v
            descriptor.fragmentFunction = f
            descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
            descriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
            pipeline = try? device.makeRenderPipelineState(descriptor: descriptor)

            let depth = MTLDepthStencilDescriptor()
            depth.isDepthWriteEnabled = true
            depth.depthCompareFunction = .less
            depthState = device.makeDepthStencilState(descriptor: depth)

            let vertices = package.vertices.map { SIMD3<Float>($0.x, $0.y, $0.z) }
            let indices = package.indices
            vertexBuffer = vertices.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return nil }
                return device.makeBuffer(bytes: base, length: raw.count)
            }
            indexBuffer = indices.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return nil }
                return device.makeBuffer(bytes: base, length: raw.count)
            }
            indexCount = indices.count
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard indexCount > 0, let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor,
                  let queue, let pipeline, let vertexBuffer, let indexBuffer,
                  let command = queue.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
            let aspect = Float(max(view.drawableSize.width, 1) / max(view.drawableSize.height, 1))
            let degreesToRadians = Float.pi / 180
            var camera = CameraUniforms(
                position: SIMD4<Float>(playerState.origin.x, playerState.origin.y, playerState.origin.z, 1),
                params: SIMD4<Float>(playerState.yaw * degreesToRadians, playerState.pitch * degreesToRadians, aspect, tan(70 * degreesToRadians * 0.5))
            )
            encoder.setRenderPipelineState(pipeline)
            if let depthState { encoder.setDepthStencilState(depthState) }
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&camera, length: MemoryLayout<CameraUniforms>.stride, index: 1)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: indexCount, indexType: .uint32, indexBuffer: indexBuffer, indexBufferOffset: 0)
            encoder.endEncoding()
            command.present(drawable)
            command.commit()
        }
    }
}
