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
    let runtimeMesh: T6RuntimeMesh?

    func makeCoordinator() -> Coordinator {
        Coordinator(runtimeMesh: runtimeMesh, health: $health, ammo: $ammo, kills: $kills)
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

        var moveInput = CGSize.zero
        var lookInput = CGSize.zero
        var isAiming = false

        private let runtimeMesh: T6RuntimeMesh?
        private let healthBinding: Binding<Int>
        private let ammoBinding: Binding<Int>
        private let killsBinding: Binding<Int>
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

        private var worldMin = SCNVector3(-10, 0, -10)
        private var worldMax = SCNVector3(10, 10, 10)
        private var worldCenter = SCNVector3Zero

        init(runtimeMesh: T6RuntimeMesh?, health: Binding<Int>, ammo: Binding<Int>, kills: Binding<Int>) {
            self.runtimeMesh = runtimeMesh
            self.healthBinding = health
            self.ammoBinding = ammo
            self.killsBinding = kills
            super.init()
            buildScene()
        }

        func attach(to view: SCNView) {
            scnView = view
            let link = CADisplayLink(target: self, selector: #selector(step(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
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

            // Debug render path: keep the decoded GfxWorld fully visible regardless of
            // missing T6 materials, lightmaps, fog metadata, winding, or normals.
            if runtimeMesh != nil {
                buildDecodedWorld()
                buildSafetyFloor()
            }

            buildPlayer()
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

        private func buildDecodedWorld() {
            guard let runtimeMesh,
                  runtimeMesh.vertices.count >= 3,
                  runtimeMesh.indices.count >= 3 else {
                return
            }

            let vertices = runtimeMesh.vertices.map { SCNVector3($0.x, $0.y, $0.z) }
            updateWorldBounds(vertices)

            let source = SCNGeometrySource(vertices: vertices)
            let indices = runtimeMesh.indices.map { Int32($0) }
            let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)

            // Solid pass: constant/unlit shading proves that actual decoded triangles
            // are reaching SceneKit without depending on normals, textures, or lights.
            let solidGeometry = SCNGeometry(sources: [source], elements: [element])
            let solidMaterial = SCNMaterial()
            solidMaterial.name = "t6-debug-solid"
            solidMaterial.lightingModel = .constant
            solidMaterial.diffuse.contents = UIColor(white: 0.74, alpha: 1)
            solidMaterial.emission.contents = UIColor(white: 0.22, alpha: 1)
            solidMaterial.isDoubleSided = true
            solidMaterial.readsFromDepthBuffer = true
            solidMaterial.writesToDepthBuffer = true
            solidGeometry.materials = [solidMaterial]

            let solidNode = SCNNode(geometry: solidGeometry)
            solidNode.name = "t6-ps3-tranzit-world-solid"
            solidNode.categoryBitMask = environmentCategory
            scene.rootNode.addChildNode(solidNode)

            // Wireframe pass: makes topology visible even if the solid surfaces overlap,
            // have bad winding, or are packed unusually after PS3 extraction.
            let wireGeometry = SCNGeometry(sources: [source], elements: [element])
            let wireMaterial = SCNMaterial()
            wireMaterial.name = "t6-debug-wireframe"
            wireMaterial.lightingModel = .constant
            wireMaterial.diffuse.contents = UIColor.systemGreen
            wireMaterial.emission.contents = UIColor.systemGreen
            wireMaterial.fillMode = .lines
            wireMaterial.isDoubleSided = true
            wireMaterial.readsFromDepthBuffer = true
            wireMaterial.writesToDepthBuffer = false
            wireGeometry.materials = [wireMaterial]

            let wireNode = SCNNode(geometry: wireGeometry)
            wireNode.name = "t6-ps3-tranzit-world-wire"
            wireNode.categoryBitMask = environmentCategory
            wireNode.renderingOrder = 10
            scene.rootNode.addChildNode(wireNode)

            // Deliberately omit the giant triangle-mesh physics body during this render
            // diagnostic. It can be restored once the real GfxWorld is visibly correct.
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
            worldCenter = SCNVector3(
                (minV.x + maxV.x) * 0.5,
                (minV.y + maxV.y) * 0.5,
                (minV.z + maxV.z) * 0.5
            )
        }

        private func buildPlayer() {
            if runtimeMesh != nil {
                let spanX = max(1, worldMax.x - worldMin.x)
                let spanY = max(1, worldMax.y - worldMin.y)
                let spanZ = max(1, worldMax.z - worldMin.z)
                let horizontalSpan = max(spanX, spanZ)
                let cameraDistance = max(14, horizontalSpan * 0.38)
                let cameraHeight = worldCenter.y + max(4, spanY * 0.20)

                // Start outside the positive-Z edge and look back through the center.
                // This guarantees a useful overview even when the map's original spawn
                // coordinates are not yet reconstructed from the zone.
                playerNode.position = SCNVector3(
                    worldCenter.x,
                    cameraHeight,
                    worldMax.z + cameraDistance
                )

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
            camera.zFar = 1200
            camera.wantsHDR = false
            cameraNode.camera = camera
            cameraNode.eulerAngles.x = pitch
            playerNode.eulerAngles.y = yaw
            playerNode.addChildNode(cameraNode)

            // Real weapon geometry is intentionally not substituted with a box/cylinder.
            // It will be attached here only after the T6 XModel/material pipeline resolves it.
            cameraNode.addChildNode(weaponNode)
        }

        @objc private func step(_ link: CADisplayLink) {
            let dt: Float = lastTimestamp == 0
                ? 1 / 60
                : Float(min(0.05, link.timestamp - lastTimestamp))
            lastTimestamp = link.timestamp

            updateLook()
            updateMovement(dt: dt)

            if firing && link.timestamp - lastShotTime > 0.115 {
                lastShotTime = link.timestamp
                fireRay()
            }
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
            guard runtimeMesh != nil else { return }

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
            guard runtimeMesh != nil,
                  ammoBinding.wrappedValue > 0 else {
                return
            }
            ammoBinding.wrappedValue -= 1
        }
    }
}
