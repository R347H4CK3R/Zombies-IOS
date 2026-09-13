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
            QuakeMetalWorldView(package: controller.package)
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

    func makeCoordinator() -> Renderer { Renderer(package: package) }

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

    func updateUIView(_ uiView: MTKView, context: Context) {}

    final class Renderer: NSObject, MTKViewDelegate {
        private var queue: MTLCommandQueue?
        private var pipeline: MTLRenderPipelineState?
        private var vertexBuffer: MTLBuffer?
        private var indexBuffer: MTLBuffer?
        private var indexCount = 0
        private let package: BO2RuntimePackage

        init(package: BO2RuntimePackage) { self.package = package }

        func attach(to view: MTKView) {
            guard let device = view.device else { return }
            queue = device.makeCommandQueue()
            let source = """
            #include <metal_stdlib>
            using namespace metal;
            struct VOut { float4 position [[position]]; float3 color; };
            vertex VOut vmain(const device float3 *p [[buffer(0)]], uint id [[vertex_id]]) {
                VOut o; float3 q = p[id] * 0.022; o.position=float4(q.x, q.y, q.z, 1.0); o.color=float3(0.55+q.y*0.2,0.68,0.78); return o;
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

            var vertices = package.vertices.map { SIMD3<Float>($0.x, $0.y, $0.z) }
            var indices = package.indices
            vertexBuffer = device.makeBuffer(bytes: &vertices, length: MemoryLayout<SIMD3<Float>>.stride * vertices.count)
            indexBuffer = device.makeBuffer(bytes: &indices, length: MemoryLayout<UInt32>.stride * indices.count)
            indexCount = indices.count
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard indexCount > 0, let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor,
                  let queue, let pipeline, let vertexBuffer, let indexBuffer,
                  let command = queue.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: indexCount, indexType: .uint32, indexBuffer: indexBuffer, indexBufferOffset: 0)
            encoder.endEncoding()
            command.present(drawable)
            command.commit()
        }
    }
}
