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
        view.backgroundColor = .black
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
            if playerNode.position.y <= 1.67 {
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
            scene.fogStartDistance = 110
            scene.fogEndDistance = 360
            scene.fogColor = UIColor(red: 0.055, green: 0.050, blue: 0.045, alpha: 1)

            let ambient = SCNLight()
            ambient.type = .ambient
            ambient.intensity = 520
            ambient.color = UIColor(white: 0.72, alpha: 1)
            let ambientNode = SCNNode()
            ambientNode.light = ambient
            scene.rootNode.addChildNode(ambientNode)

            let sun = SCNLight()
            sun.type = .directional
            sun.intensity = 900
            sun.castsShadow = true
            let sunNode = SCNNode()
            sunNode.light = sun
            sunNode.eulerAngles = SCNVector3(-0.9, -0.55, 0)
            scene.rootNode.addChildNode(sunNode)

            if runtimeMesh != nil {
                buildSafetyFloor()
                buildDecodedWorld()
            }

            buildPlayer()
        }

        private func buildSafetyFloor() {
            let floor = SCNFloor()
            floor.reflectivity = 0
            floor.firstMaterial?.diffuse.contents = UIColor.clear
            floor.firstMaterial?.transparency = 0
            let node = SCNNode(geometry: floor)
            node.position.y = -0.35
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
            let source = SCNGeometrySource(vertices: vertices)
            let indices = runtimeMesh.indices.map { Int32($0) }
            let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
            let geometry = SCNGeometry(sources: [source], elements: [element])

            let material = SCNMaterial()
            material.diffuse.contents = UIColor(red: 0.42, green: 0.38, blue: 0.31, alpha: 1)
            material.ambient.contents = UIColor(red: 0.20, green: 0.18, blue: 0.15, alpha: 1)
            material.roughness.contents = 0.92
            material.metalness.contents = 0.02
            material.isDoubleSided = true
            geometry.materials = [material]

            let node = SCNNode(geometry: geometry)
            node.name = "t6-ps3-tranzit-world"
            node.position = SCNVector3Zero
            node.categoryBitMask = environmentCategory
            node.physicsBody = SCNPhysicsBody(
                type: .static,
                shape: SCNPhysicsShape(geometry: geometry, options: nil)
            )
            scene.rootNode.addChildNode(node)
        }

        private func buildPlayer() {
            playerNode.position = SCNVector3(0, 1.65, runtimeMesh == nil ? 0 : 20)
            scene.rootNode.addChildNode(playerNode)

            let camera = SCNCamera()
            camera.fieldOfView = 72
            camera.zNear = 0.03
            camera.zFar = 520
            camera.wantsHDR = true
            camera.bloomIntensity = 0.18
            cameraNode.camera = camera
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
            let worldLimit: Float = 70
            playerNode.position.x = max(-worldLimit, min(worldLimit, playerNode.position.x))
            playerNode.position.z = max(-worldLimit, min(worldLimit, playerNode.position.z))

            jumpVelocity -= 14.5 * dt
            playerNode.position.y += jumpVelocity * dt
            if playerNode.position.y <= 1.65 {
                playerNode.position.y = 1.65
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
