import SwiftUI
import MetalKit
import simd

struct MetalWorldView: UIViewRepresentable {
    let asset: WorldRuntimeAsset
    let playerPosition: SIMD3<Float>
    let yaw: Float
    let pitch: Float

    func makeCoordinator() -> Coordinator {
        Coordinator(asset: asset, playerPosition: playerPosition, yaw: yaw, pitch: pitch)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = MTLClearColorMake(0.015, 0.018, 0.025, 1.0)
        view.preferredFramesPerSecond = 60
        context.coordinator.configure(view: view)
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.playerPosition = playerPosition
        context.coordinator.yaw = yaw
        context.coordinator.pitch = pitch
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        private struct CameraUniforms {
            var position: SIMD4<Float>
            var params: SIMD4<Float>
        }

        private let asset: WorldRuntimeAsset
        private var commandQueue: MTLCommandQueue?
        private var pipeline: MTLRenderPipelineState?
        private var depthState: MTLDepthStencilState?
        private var vertexBuffer: MTLBuffer?
        private var indexBuffer: MTLBuffer?
        var playerPosition: SIMD3<Float>
        var yaw: Float
        var pitch: Float

        init(asset: WorldRuntimeAsset, playerPosition: SIMD3<Float>, yaw: Float, pitch: Float) {
            self.asset = asset
            self.playerPosition = playerPosition
            self.yaw = yaw
            self.pitch = pitch
        }

        func configure(view: MTKView) {
            guard let device = view.device else { return }
            commandQueue = device.makeCommandQueue()
            vertexBuffer = asset.vertexData.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return nil }
                return device.makeBuffer(bytes: base, length: raw.count, options: .storageModeShared)
            }
            indexBuffer = asset.indexData.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return nil }
                return device.makeBuffer(bytes: base, length: raw.count, options: .storageModeShared)
            }

            let source = """
            #include <metal_stdlib>
            using namespace metal;
            struct RuntimeVertex {
                packed_float3 position;
                float binormalSign;
                uchar4 color;
                float2 uv;
                float2 lightmapUV;
                uint normalPacked;
                uint tangentPacked;
            };
            struct Camera { float4 position; float4 params; };
            struct VOut { float4 position [[position]]; float4 color; };
            vertex VOut vmain(device const RuntimeVertex *vertices [[buffer(0)]], constant Camera& camera [[buffer(1)]], uint id [[vertex_id]]) {
                RuntimeVertex v = vertices[id];
                float3 d = float3(v.position) - camera.position.xyz;
                float sy = sin(camera.params.x), cy = cos(camera.params.x);
                float sp = sin(camera.params.y), cp = cos(camera.params.y);
                float vx = cy * d.x - sy * d.z;
                float vz0 = sy * d.x + cy * d.z;
                float vy = cp * d.y - sp * vz0;
                float vz = sp * d.y + cp * vz0;
                float aspect = max(camera.params.z, 0.1);
                float tanHalfFov = max(camera.params.w, 0.1);
                float nearZ = 1.0, farZ = 50000.0;
                VOut o;
                o.position = float4(vx / (aspect * tanHalfFov), vy / tanHalfFov, (farZ/(farZ-nearZ))*vz-(farZ*nearZ/(farZ-nearZ)), vz);
                o.color = max(float4(v.color) / 255.0f, float4(0.15f,0.15f,0.15f,1.0f));
                return o;
            }
            fragment float4 fmain(VOut in [[stage_in]]) { return float4(in.color.rgb, 1.0f); }
            """
            do {
                let library = try device.makeLibrary(source: source, options: nil)
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = library.makeFunction(name: "vmain")
                descriptor.fragmentFunction = library.makeFunction(name: "fmain")
                descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
                descriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
                pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
                let depth = MTLDepthStencilDescriptor()
                depth.isDepthWriteEnabled = true
                depth.depthCompareFunction = .less
                depthState = device.makeDepthStencilState(descriptor: depth)
            } catch {
                print("Metal world pipeline failed: \(error)")
            }
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let pass = view.currentRenderPassDescriptor,
                  let commandQueue, let pipeline, let vertexBuffer, let indexBuffer,
                  let command = commandQueue.makeCommandBuffer(),
                  let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
            let aspect = Float(max(view.drawableSize.width, 1) / max(view.drawableSize.height, 1))
            let radians = Float.pi / 180
            var camera = CameraUniforms(
                position: SIMD4<Float>(playerPosition, 1),
                params: SIMD4<Float>(yaw * radians, pitch * radians, aspect, tan(70 * radians * 0.5))
            )
            encoder.setRenderPipelineState(pipeline)
            if let depthState { encoder.setDepthStencilState(depthState) }
            encoder.setCullMode(.none)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&camera, length: MemoryLayout<CameraUniforms>.stride, index: 1)
            for surface in asset.metadata.surfaces where surface.indexCount > 0 {
                encoder.drawIndexedPrimitives(type: .triangle, indexCount: surface.indexCount, indexType: .uint32, indexBuffer: indexBuffer, indexBufferOffset: surface.firstIndex * 4)
            }
            encoder.endEncoding()
            command.present(drawable)
            command.commit()
        }
    }
}
