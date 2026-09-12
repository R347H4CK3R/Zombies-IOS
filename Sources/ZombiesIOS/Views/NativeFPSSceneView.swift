import SwiftUI
import SceneKit
import UIKit

struct NativeFPSSceneView: UIViewRepresentable {
    var move: CGSize
    var look: CGSize
    var firing: Bool
    var aiming: Bool
    var jumpPulse: Int
    var reloadPulse: Int
    @Binding var health: Int
    @Binding var ammo: Int
    @Binding var kills: Int
    let mapSeed: Int

    // Transitional compatibility: TranzitTouchGameplayView still supplies the
    // legacy mesh until Task 8 switches it to T6RenderableWorld. Legacy meshes
    // are never reported as certifiable.
    let runtimeMesh: T6RuntimeMesh?
    var renderableWorld: T6RenderableWorld? = nil
    var onMetrics: ((RenderValidationMetrics) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(
            runtimeMesh: runtimeMesh,
            renderableWorld: renderableWorld,
            health: $health,
            ammo: $ammo,
            kills: $kills,
            onMetrics: onMetrics
        )
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.cameraNode
        view.backgroundColor = UIColor(white: 0.035, alpha: 1)
        view.isPlaying = true
        view.rendersContinuously = true
        view.preferredFramesPerSecond = 60
        view.antialiasingMode = .multisampling4X
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        let c = context.coordinator
        c.moveInput = move
        c.lookInput = look
        c.isAiming = aiming
        c.setFiring(firing)
        c.applyJumpPulse(jumpPulse)
        c.applyReloadPulse(reloadPulse)
    }

    static func dismantleUIView(_ uiView: SCNView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator: NSObject {
        private let environmentCategory = 1 << 1

        let scene = SCNScene()
        let playerNode = SCNNode()
        let cameraNode = SCNNode()
        let weaponNode = SCNNode()
        private let worldRootNode = SCNNode()

        var moveInput = CGSize.zero
        var lookInput = CGSize.zero
        var isAiming = false

        private let runtimeMesh: T6RuntimeMesh?
        private let renderableWorld: T6RenderableWorld?
        private let healthBinding: Binding<Int>
        private let ammoBinding: Binding<Int>
        private let killsBinding: Binding<Int>
        private let onMetrics: ((RenderValidationMetrics) -> Void)?
        private weak var scnView: SCNView?
        private var displayLink: CADisplayLink?
        private var lastTimestamp: CFTimeInterval = 0
        private var yaw: Float = 0
        private var pitch: Float = 0
        private var firing = false
        private var lastShotTime: CFTimeInterval = 0
        private var jumpVelocity: Float = 0
        private var lastJumpPulse = 0
        private var lastReloadPulse = 0
        private var measuredFirstFrame = false
        private var renderedSurfaceCount = 0
        private var renderedTextureCount = 0
        private var renderedRealMaterialIDs = Set<T6AssetID>()
        private var renderedTriangleCount = 0
        private var renderedPropCount = 0

        private var worldMin = SCNVector3(-10, 0, -10)
        private var worldMax = SCNVector3(10, 10, 10)
        private var worldCenter = SCNVector3Zero

        init(
            runtimeMesh: T6RuntimeMesh?,
            renderableWorld: T6RenderableWorld?,
            health: Binding<Int>,
            ammo: Binding<Int>,
            kills: Binding<Int>,
            onMetrics: ((RenderValidationMetrics) -> Void)?
        ) {
            self.runtimeMesh = runtimeMesh
            self.renderableWorld = renderableWorld
            self.healthBinding = health
            self.ammoBinding = ammo
            self.killsBinding = kills
            self.onMetrics = onMetrics
            super.init()
            buildScene()
        }

        func attach(to view: SCNView) {
            scnView = view
            let link = CADisplayLink(target: self, selector: #selector(step(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
            emitMetrics(blackPixelRatio: 1.0)
        }

        func stop() {
            displayLink?.invalidate()
            displayLink = nil
        }

        func setFiring(_ value: Bool) {
            firing = value
        }

        func applyJumpPulse(_ pulse: Int) {
            guard pulse != lastJumpPulse else { return }
            lastJumpPulse = pulse
            if playerNode.position.y <= worldMin.y + 2.0 {
                jumpVelocity = 5.6
            }
        }

        func applyReloadPulse(_ pulse: Int) {
            guard pulse != lastReloadPulse else { return }
            lastReloadPulse = pulse
            firing = false
            ammoBinding.wrappedValue = 30
        }

        private func buildScene() {
            scene.physicsWorld.gravity = SCNVector3(0, -20, 0)
            scene.rootNode.addChildNode(worldRootNode)

            if let renderableWorld {
                buildRenderableWorld(renderableWorld)
                buildLighting()
                buildSafetyFloor()
            } else if runtimeMesh != nil {
                buildLegacyDecodedWorld()
                buildSafetyFloor()
            }

            buildPlayer()
        }

        private func buildRenderableWorld(_ world: T6RenderableWorld) {
            let allVertices = world.surfaces.flatMap(\.vertices).map { SCNVector3($0.x, $0.z, -$0.y) }
            guard !allVertices.isEmpty else { return }
            updateWorldBounds(allVertices)

            let transform = worldNormalizationTransform(vertices: allVertices)
            worldRootNode.position = transform.position
            worldRootNode.scale = SCNVector3(transform.scale, transform.scale, transform.scale)

            var textureIDs = Set<T6AssetID>()
            for surface in world.surfaces where surface.vertices.count >= 3 && surface.indices.count >= 3 {
                let vertices = surface.vertices.map { SCNVector3($0.x, $0.z, -$0.y) }
                let normals = surface.normals.map { SCNVector3($0.x, $0.z, -$0.y) }
                let texcoords = surface.uvs.map { CGPoint(x: CGFloat($0.x), y: CGFloat(1 - $0.y)) }
                let vertexSource = SCNGeometrySource(vertices: vertices)
                let normalSource = SCNGeometrySource(normals: normals)
                let uvSource = SCNGeometrySource(textureCoordinates: texcoords)
                let element = SCNGeometryElement(indices: surface.indices.map(Int32.init), primitiveType: .triangles)
                let geometry = SCNGeometry(sources: [vertexSource, normalSource, uvSource], elements: [element])

                let material = makeMaterial(surface: surface, world: world, textureIDs: &textureIDs)
                geometry.materials = [material]

                let node = SCNNode(geometry: geometry)
                node.name = "t6-world-surface-\(surface.sourceSurfaceIndex)"
                node.categoryBitMask = environmentCategory
                worldRootNode.addChildNode(node)

                renderedSurfaceCount += 1
                renderedTriangleCount += surface.indices.count / 3
            }
            renderedTextureCount = textureIDs.count

            // Props and first-person weapon are only rendered once their decoded
            // geometry is present. Never synthesize substitute geometry here.
            renderedPropCount = 0
        }

        private func makeMaterial(
            surface: T6WorldSurface,
            world: T6RenderableWorld,
            textureIDs: inout Set<T6AssetID>
        ) -> SCNMaterial {
            let result = SCNMaterial()
            result.isDoubleSided = true
            result.lightingModel = .physicallyBased
            result.roughness.contents = 0.8
            result.metalness.contents = 0.0

            guard let materialID = surface.materialID,
                  let material = world.materials[materialID],
                  !material.isFallback else {
                result.name = "t6-diagnostic-missing-material"
                result.diffuse.contents = UIColor.magenta
                result.emission.contents = UIColor(red: 0.25, green: 0, blue: 0.25, alpha: 1)
                return result
            }

            renderedRealMaterialIDs.insert(materialID)
            result.name = "t6-material-\(materialID.assetIndex)"
            if let texture = material.baseColorTexture,
               let image = makeImage(texture) {
                result.diffuse.contents = image
                result.diffuse.wrapS = .repeat
                result.diffuse.wrapT = .repeat
                textureIDs.insert(texture.imageID)
            } else {
                result.diffuse.contents = UIColor(white: 0.55, alpha: 1)
            }

            switch material.alphaMode {
            case .opaque:
                result.transparencyMode = .aOne
            case .mask:
                result.transparencyMode = .aOne
                result.transparency = 1
            case .blend:
                result.transparencyMode = .dualLayer
            }
            return result
        }

        private func makeImage(_ texture: T6DecodedTexture) -> UIImage? {
            guard texture.depth == 1,
                  texture.width > 0,
                  texture.height > 0,
                  texture.rgba8.count >= texture.width * texture.height * 4 else { return nil }
            guard let provider = CGDataProvider(data: texture.rgba8 as CFData) else { return nil }
            let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
            guard let cgImage = CGImage(
                width: texture.width,
                height: texture.height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: texture.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: info,
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
            ) else { return nil }
            return UIImage(cgImage: cgImage)
        }

        private func worldNormalizationTransform(vertices: [SCNVector3]) -> (position: SCNVector3, scale: Float) {
            guard let first = vertices.first else { return (SCNVector3Zero, 1) }
            var minV = first
            var maxV = first
            for v in vertices.dropFirst() {
                minV.x = min(minV.x, v.x)
                minV.y = min(minV.y, v.y)
                minV.z = min(minV.z, v.z)
                maxV.x = max(maxV.x, v.x)
                maxV.y = max(maxV.y, v.y)
                maxV.z = max(maxV.z, v.z)
            }
            let span = SCNVector3(maxV.x - minV.x, maxV.y - minV.y, maxV.z - minV.z)
            let largest = max(0.0001, max(span.x, max(span.y, span.z)))
            let scale: Float = 115 / largest
            let centerX = (minV.x + maxV.x) * 0.5
            let centerZ = (minV.z + maxV.z) * 0.5
            let position = SCNVector3(-centerX * scale, -minV.y * scale, -centerZ * scale)

            worldMin = SCNVector3((minV.x - centerX) * scale, 0, (minV.z - centerZ) * scale)
            worldMax = SCNVector3((maxV.x - centerX) * scale, (maxV.y - minV.y) * scale, (maxV.z - centerZ) * scale)
            worldCenter = SCNVector3(
                (worldMin.x + worldMax.x) * 0.5,
                (worldMin.y + worldMax.y) * 0.5,
                (worldMin.z + worldMax.z) * 0.5
            )
            return (position, scale)
        }

        private func buildLighting() {
            let ambient = SCNLight()
            ambient.type = .ambient
            ambient.intensity = 420
            ambient.color = UIColor(white: 0.42, alpha: 1)
            let ambientNode = SCNNode()
            ambientNode.light = ambient
            scene.rootNode.addChildNode(ambientNode)

            let key = SCNLight()
            key.type = .directional
            key.intensity = 1_050
            key.color = UIColor(red: 1.0, green: 0.82, blue: 0.63, alpha: 1)
            key.castsShadow = true
            let keyNode = SCNNode()
            keyNode.light = key
            keyNode.eulerAngles = SCNVector3(-0.85, -0.55, 0)
            scene.rootNode.addChildNode(keyNode)

            scene.fogColor = UIColor(red: 0.22, green: 0.15, blue: 0.10, alpha: 1)
            scene.fogStartDistance = 75
            scene.fogEndDistance = 190
        }

        private func buildSafetyFloor() {
            let floor = SCNFloor()
            floor.reflectivity = 0
            floor.firstMaterial?.diffuse.contents = UIColor.clear
            floor.firstMaterial?.transparency = 0
            let node = SCNNode(geometry: floor)
            node.position.y = worldMin.y - 0.35
            node.categoryBitMask = environmentCategory
            node.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
            scene.rootNode.addChildNode(node)
        }

        private func buildLegacyDecodedWorld() {
            guard let runtimeMesh,
                  runtimeMesh.vertices.count >= 3,
                  runtimeMesh.indices.count >= 3 else { return }

            let vertices = runtimeMesh.vertices.map { SCNVector3($0.x, $0.y, $0.z) }
            updateWorldBounds(vertices)
            let source = SCNGeometrySource(vertices: vertices)
            let element = SCNGeometryElement(indices: runtimeMesh.indices.map { Int32($0) }, primitiveType: .triangles)
            let geometry = SCNGeometry(sources: [source], elements: [element])
            let material = SCNMaterial()
            material.name = "legacy-noncertifying-debug"
            material.lightingModel = .constant
            material.diffuse.contents = UIColor(white: 0.55, alpha: 1)
            material.isDoubleSided = true
            geometry.materials = [material]
            let node = SCNNode(geometry: geometry)
            node.name = "legacy-t6-world"
            scene.rootNode.addChildNode(node)
        }

        private func updateWorldBounds(_ vertices: [SCNVector3]) {
            guard let first = vertices.first else { return }
            var minV = first
            var maxV = first
            for v in vertices.dropFirst() {
                minV.x = min(minV.x, v.x)
                minV.y = min(minV.y, v.y)
                minV.z = min(minV.z, v.z)
                maxV.x = max(maxV.x, v.x)
                maxV.y = max(maxV.y, v.y)
                maxV.z = max(maxV.z, v.z)
            }
            worldMin = minV
            worldMax = maxV
            worldCenter = SCNVector3((minV.x + maxV.x) * 0.5, (minV.y + maxV.y) * 0.5, (minV.z + maxV.z) * 0.5)
        }

        private func buildPlayer() {
            let hasWorld = renderableWorld != nil || runtimeMesh != nil
            if hasWorld {
                let spanX = max(1, worldMax.x - worldMin.x)
                let spanY = max(1, worldMax.y - worldMin.y)
                let spanZ = max(1, worldMax.z - worldMin.z)
                let horizontalSpan = max(spanX, spanZ)
                let cameraDistance = max(14, horizontalSpan * 0.30)
                let cameraHeight = worldCenter.y + max(3.2, spanY * 0.13)
                playerNode.position = SCNVector3(worldCenter.x, cameraHeight, worldMax.z + cameraDistance)
                let dz = max(0.001, playerNode.position.z - worldCenter.z)
                pitch = atan2(worldCenter.y - playerNode.position.y, dz)
                yaw = 0
            } else {
                playerNode.position = SCNVector3(0, 1.65, 0)
            }

            scene.rootNode.addChildNode(playerNode)
            let camera = SCNCamera()
            camera.fieldOfView = 72
            camera.zNear = 0.03
            camera.zFar = 1_200
            camera.wantsHDR = true
            cameraNode.camera = camera
            cameraNode.eulerAngles.x = pitch
            playerNode.eulerAngles.y = yaw
            playerNode.addChildNode(cameraNode)

            // Weapon node remains empty until decoded XModel sections are available.
            // No project-authored substitute geometry is allowed to satisfy validation.
            cameraNode.addChildNode(weaponNode)
        }

        @objc private func step(_ link: CADisplayLink) {
            let dt: Float = lastTimestamp == 0 ? 1 / 60 : Float(min(0.05, link.timestamp - lastTimestamp))
            lastTimestamp = link.timestamp
            updateLook()
            updateMovement(dt: dt)

            if firing && link.timestamp - lastShotTime > 0.115 {
                lastShotTime = link.timestamp
                fireRay()
            }

            if !measuredFirstFrame, link.timestamp > 0.25, let view = scnView {
                measuredFirstFrame = true
                let ratio = Self.blackPixelRatio(image: view.snapshot())
                emitMetrics(blackPixelRatio: ratio)
            }
        }

        private func emitMetrics(blackPixelRatio: Double) {
            guard let onMetrics else { return }
            let metrics: RenderValidationMetrics
            if renderableWorld != nil {
                metrics = RenderValidationMetrics(
                    submittedTriangles: renderedTriangleCount,
                    drawnSurfaces: renderedSurfaceCount,
                    nonFallbackMaterials: renderedRealMaterialIDs.count,
                    residentTextures: renderedTextureCount,
                    renderedProps: renderedPropCount,
                    validCamera: cameraNode.camera != nil,
                    blackPixelRatio: blackPixelRatio
                )
            } else {
                metrics = .zero
            }
            DispatchQueue.main.async { onMetrics(metrics) }
        }

        private static func blackPixelRatio(image: UIImage) -> Double {
            guard let cgImage = image.cgImage else { return 1.0 }
            let width = cgImage.width
            let height = cgImage.height
            guard width > 0, height > 0 else { return 1.0 }

            let sampleWidth = min(width, 256)
            let sampleHeight = min(height, 144)
            let bytesPerRow = sampleWidth * 4
            var pixels = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * 4)
            guard let context = CGContext(
                data: &pixels,
                width: sampleWidth,
                height: sampleHeight,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return 1.0 }
            context.interpolationQuality = .low
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

            var black = 0
            let pixelCount = sampleWidth * sampleHeight
            for index in stride(from: 0, to: pixels.count, by: 4) {
                if pixels[index] < 18 && pixels[index + 1] < 18 && pixels[index + 2] < 18 {
                    black += 1
                }
            }
            return Double(black) / Double(max(1, pixelCount))
        }

        private func updateLook() {
            let sensitivity: Float = isAiming ? 0.00082 : 0.00122
            yaw -= Float(lookInput.width) * sensitivity
            pitch -= Float(lookInput.height) * sensitivity
            pitch = max(-1.25, min(1.25, pitch))
            playerNode.eulerAngles.y = yaw
            cameraNode.eulerAngles.x = pitch
            cameraNode.camera?.fieldOfView = isAiming ? 50 : 72
        }

        private func updateMovement(dt: Float) {
            guard renderableWorld != nil || runtimeMesh != nil else { return }
            let nx = Float(moveInput.width / 70.0)
            let ny = Float(-moveInput.height / 70.0)
            let speed: Float = 5.1
            let forward = SCNVector3(-sin(yaw), 0, -cos(yaw))
            let right = SCNVector3(cos(yaw), 0, -sin(yaw))
            playerNode.position.x += (forward.x * ny + right.x * nx) * speed * dt
            playerNode.position.z += (forward.z * ny + right.z * nx) * speed * dt

            let pad: Float = 30
            playerNode.position.x = max(worldMin.x - pad, min(worldMax.x + pad, playerNode.position.x))
            playerNode.position.z = max(worldMin.z - pad, min(worldMax.z + pad, playerNode.position.z))
            jumpVelocity -= 14.5 * dt
            playerNode.position.y += jumpVelocity * dt
            let floorY = worldMin.y + 1.65
            if playerNode.position.y <= floorY {
                playerNode.position.y = floorY
                jumpVelocity = 0
            }
        }

        private func fireRay() {
            guard (renderableWorld != nil || runtimeMesh != nil), ammoBinding.wrappedValue > 0 else { return }
            ammoBinding.wrappedValue -= 1
        }
    }
}
