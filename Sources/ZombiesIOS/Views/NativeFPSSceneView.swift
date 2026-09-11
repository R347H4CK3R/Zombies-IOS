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
        private let zombieCategory = 1 << 2

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
        private var enemies: [SCNNode] = []

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

        func setFiring(_ value: Bool) { firing = value }

        func applyJumpPulse(_ pulse: Int) {
            guard pulse != lastJumpPulse else { return }
            lastJumpPulse = pulse
            if playerNode.position.y <= 1.67 { jumpVelocity = 5.6 }
        }

        func applyReloadPulse(_ pulse: Int) {
            guard pulse != lastReloadPulse else { return }
            lastReloadPulse = pulse
            firing = false
            ammoBinding.wrappedValue = 30
        }

        private func buildScene() {
            scene.physicsWorld.gravity = SCNVector3(0, -20, 0)
            scene.fogStartDistance = runtimeMesh == nil ? 35 : 55
            scene.fogEndDistance = runtimeMesh == nil ? 95 : 150
            scene.fogColor = UIColor(red: 0.055, green: 0.050, blue: 0.045, alpha: 1)

            let ambient = SCNLight()
            ambient.type = .ambient
            ambient.intensity = runtimeMesh == nil ? 260 : 520
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

            buildFloor()
            if runtimeMesh != nil {
                buildDecodedWorld()
            } else {
                buildFallbackArena()
            }
            buildPlayer()
            buildEnemies()
        }

        private func buildFloor() {
            let floor = SCNFloor()
            floor.reflectivity = 0
            floor.firstMaterial?.diffuse.contents = UIColor(red: 0.085, green: 0.075, blue: 0.060, alpha: 1)
            floor.firstMaterial?.roughness.contents = 1.0
            let node = SCNNode(geometry: floor)
            node.categoryBitMask = environmentCategory
            node.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
            scene.rootNode.addChildNode(node)
        }

        private func buildDecodedWorld() {
            guard let runtimeMesh,
                  runtimeMesh.vertices.count >= 3,
                  runtimeMesh.indices.count >= 3 else { return }

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
            node.name = "t6-ps3-world"
            node.position = SCNVector3Zero
            node.categoryBitMask = environmentCategory
            node.physicsBody = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: geometry, options: nil))
            scene.rootNode.addChildNode(node)
        }

        private func buildFallbackArena() {
            let material = SCNMaterial()
            material.diffuse.contents = UIColor(red: 0.17, green: 0.145, blue: 0.115, alpha: 1)
            material.roughness.contents = 0.95
            addBox(20, 4, 1, SCNVector3(0, 2, -10), material)
            addBox(1, 4, 14, SCNVector3(9, 2, -2), material)
            addBox(8, 2.5, 1, SCNVector3(-7, 1.25, 6), material)
        }

        private func addBox(_ width: CGFloat, _ height: CGFloat, _ length: CGFloat, _ position: SCNVector3, _ material: SCNMaterial) {
            let box = SCNBox(width: width, height: height, length: length, chamferRadius: 0.03)
            box.materials = [material]
            let node = SCNNode(geometry: box)
            node.position = position
            node.categoryBitMask = environmentCategory
            node.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
            scene.rootNode.addChildNode(node)
        }

        private func buildPlayer() {
            playerNode.position = runtimeMesh == nil ? SCNVector3(0, 1.65, 12) : SCNVector3(0, 1.65, 16)
            scene.rootNode.addChildNode(playerNode)

            let camera = SCNCamera()
            camera.fieldOfView = 72
            camera.zNear = 0.03
            camera.zFar = 220
            camera.wantsHDR = true
            camera.bloomIntensity = 0.18
            cameraNode.camera = camera
            playerNode.addChildNode(cameraNode)

            let mat = SCNMaterial()
            mat.diffuse.contents = UIColor(white: 0.12, alpha: 1)
            mat.metalness.contents = 0.7
            mat.roughness.contents = 0.32
            let receiver = SCNNode(geometry: SCNBox(width: 0.20, height: 0.17, length: 0.48, chamferRadius: 0.03))
            receiver.geometry?.materials = [mat]
            let barrel = SCNNode(geometry: SCNCylinder(radius: 0.045, height: 0.36))
            barrel.geometry?.materials = [mat]
            barrel.eulerAngles.x = .pi / 2
            barrel.position = SCNVector3(0, 0.01, -0.40)
            weaponNode.addChildNode(receiver)
            weaponNode.addChildNode(barrel)
            weaponNode.position = SCNVector3(0.28, -0.25, -0.62)
            cameraNode.addChildNode(weaponNode)
        }

        private func buildEnemies() {
            enemies.removeAll()
            for i in 0..<8 {
                let zombie = SCNNode()
                zombie.name = "zombie"
                zombie.categoryBitMask = zombieCategory
                let angle = Float(i) / 8 * .pi * 2
                let radius: Float = 12 + Float(i % 2) * 4
                zombie.position = SCNVector3(cos(angle) * radius, 0, sin(angle) * radius)

                let torsoMat = SCNMaterial()
                torsoMat.diffuse.contents = UIColor(red: 0.18, green: 0.22, blue: 0.15, alpha: 1)
                let skinMat = SCNMaterial()
                skinMat.diffuse.contents = UIColor(red: 0.32, green: 0.29, blue: 0.22, alpha: 1)

                let torso = SCNNode(geometry: SCNBox(width: 0.62, height: 0.9, length: 0.34, chamferRadius: 0.08))
                torso.geometry?.materials = [torsoMat]
                torso.position = SCNVector3(0, 1.2, 0)
                let head = SCNNode(geometry: SCNSphere(radius: 0.24))
                head.geometry?.materials = [skinMat]
                head.position = SCNVector3(0, 1.85, 0)
                zombie.addChildNode(torso)
                zombie.addChildNode(head)
                scene.rootNode.addChildNode(zombie)
                enemies.append(zombie)
            }
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
        }

        private func updateLook() {
            let sensitivity: Float = isAiming ? 0.00082 : 0.00122
            yaw -= Float(lookInput.width) * sensitivity
            pitch -= Float(lookInput.height) * sensitivity
            pitch = max(-1.25, min(1.25, pitch))
            playerNode.eulerAngles.y = yaw
            cameraNode.eulerAngles.x = pitch
            cameraNode.camera?.fieldOfView = isAiming ? 50 : 72
            weaponNode.position = isAiming ? SCNVector3(0, -0.20, -0.50) : SCNVector3(0.28, -0.25, -0.62)
        }

        private func updateMovement(dt: Float) {
            let nx = Float(moveInput.width / 70.0)
            let ny = Float(-moveInput.height / 70.0)
            let speed: Float = 5.1
            let forward = SCNVector3(-sin(yaw), 0, -cos(yaw))
            let right = SCNVector3(cos(yaw), 0, -sin(yaw))

            playerNode.position.x += (forward.x * ny + right.x * nx) * speed * dt
            playerNode.position.z += (forward.z * ny + right.z * nx) * speed * dt
            playerNode.position.x = max(-30, min(30, playerNode.position.x))
            playerNode.position.z = max(-30, min(30, playerNode.position.z))

            jumpVelocity -= 14.5 * dt
            playerNode.position.y += jumpVelocity * dt
            if playerNode.position.y <= 1.65 {
                playerNode.position.y = 1.65
                jumpVelocity = 0
            }
        }

        private func zombieRoot(for node: SCNNode) -> SCNNode? {
            var current: SCNNode? = node
            while let n = current {
                if n.name == "zombie" { return n }
                current = n.parent
            }
            return nil
        }

        private func fireRay() {
            guard ammoBinding.wrappedValue > 0, let view = scnView else { return }
            ammoBinding.wrappedValue -= 1
            let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            if let zombie = view.hitTest(center, options: nil).compactMap({ zombieRoot(for: $0.node) }).first {
                killsBinding.wrappedValue += 1
                zombie.removeFromParentNode()
            }
            weaponNode.removeAction(forKey: "recoil")
            weaponNode.runAction(.sequence([
                .moveBy(x: 0, y: 0.01, z: 0.07, duration: 0.025),
                .moveBy(x: 0, y: -0.01, z: -0.07, duration: 0.06)
            ]), forKey: "recoil")
        }
    }
}
