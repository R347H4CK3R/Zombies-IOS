import SwiftUI
import MetalKit
import simd

struct MetalWorldView: UIViewRepresentable {
    let asset: WorldRuntimeAsset

    func makeCoordinator() -> Coordinator {
        Coordinator(asset: asset)
    }

    func makeUIView(context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return MTKView(frame: .zero)
        }
        let view = MTKView(frame: .zero, device: device)
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0.015, 0.018, 0.025, 1.0)
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        context.coordinator.configure(view: view, device: device)
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}

    final class Coordinator: NSObject, MTKViewDelegate {
        private let asset: WorldRuntimeAsset
        private var commandQueue: MTLCommandQueue?
        private var pipeline: MTLRenderPipelineState?
        private var vertexBuffer: MTLBuffer?
        private var indexBuffer: MTLBuffer?

        init(asset: WorldRuntimeAsset) {
            self.asset = asset
        }

        func configure(view: MTKView, device: MTLDevice) {
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

            struct Uniforms {
                float3 center;
                float radius;
                float aspect;
            };

            struct VertexOut {
                float4 position [[position]];
                float4 color;
            };

            vertex VertexOut worldVertex(
                uint vertexID [[vertex_id]],
                device const RuntimeVertex *vertices [[buffer(0)]],
                constant Uniforms &uniforms [[buffer(1)]])
            {
                RuntimeVertex v = vertices[vertexID];
                float3 p = (float3(v.position) - uniforms.center) / max(uniforms.radius, 1.0f);
                VertexOut out;
                out.position = float4(p.x / max(uniforms.aspect, 0.25f), p.z, 0.5f, 1.0f);
                out.color = max(float4(v.color) / 255.0f, float4(0.18f, 0.18f, 0.18f, 1.0f));
                return out;
            }

            fragment float4 worldFragment(VertexOut in [[stage_in]]) {
                return float4(in.color.rgb, 1.0f);
            }
            """

            do {
                let library = try device.makeLibrary(source: source, options: nil)
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = library.makeFunction(name: "worldVertex")
                descriptor.fragmentFunction = library.makeFunction(name: "worldFragment")
                descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
                pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            } catch {
                pipeline = nil
                print("Metal world pipeline failed: \(error)")
            }
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let pass = view.currentRenderPassDescriptor,
                  let queue = commandQueue,
                  let pipeline,
                  let vertexBuffer,
                  let indexBuffer,
                  let commandBuffer = queue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
                return
            }

            let width = max(Float(view.drawableSize.width), 1)
            let height = max(Float(view.drawableSize.height), 1)
            var uniforms = RuntimeWorldUniforms(
                center: asset.center,
                radius: asset.radius,
                aspect: width / height
            )

            encoder.setRenderPipelineState(pipeline)
            encoder.setCullMode(.none)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<RuntimeWorldUniforms>.stride, index: 1)

            for surface in asset.metadata.surfaces where surface.indexCount > 0 {
                encoder.drawIndexedPrimitives(
                    type: .triangle,
                    indexCount: surface.indexCount,
                    indexType: .uint32,
                    indexBuffer: indexBuffer,
                    indexBufferOffset: surface.firstIndex * MemoryLayout<UInt32>.size
                )
            }

            encoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}

private struct RuntimeWorldUniforms {
    var center: SIMD3<Float>
    var radius: Float
    var aspect: Float
}
