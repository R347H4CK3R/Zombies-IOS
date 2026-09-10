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

    func makeCoordinator() -> Coordinator {
        Coordinator(mapSeed: mapSeed, health: $health, ammo: $ammo, kills: $kills)
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
        let coordinator = context.coordinator
        coordinator.moveInput = move
        coordinator.lookInput = look
        coordinator.isAiming = aiming
        coordinator.setFiring(firing)
        coordinator.applyJumpPulse(jumpPulse)
        coordinator.applyReloadPulse(reloadPulse)
    }

    static func dismantleUIView(_ uiView: SCNView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator: NSObject {
        let scene = SCNScene()
        let playerNode = SCNNode()
        let cameraNode = SCNNode()
        let weaponNode = SCNNode()

        var moveInput = CGSize.zero
        var lookInput = CGSize.zero
        var isAiming = false

        private let healthBinding: Binding<Int>
        private let ammoBinding: Binding<Int>
        private let killsBinding: Binding<Int>
        private var displayLink: CADisplayLink?
        private var lastTimestamp: CFTimeInterval = 0
        private var yaw: Float = 0
        private var pitch: Float = 0
        private var firing = false
        private var lastShotTime: CFTimeInterval = 0
        private var lastDamageTime: CFTimeInterval = 0
        private var jumpVelocity: Float = 0
        private var lastJumpPulse = 0
        private var lastReloadPulse = 0
        private var enemies: [SCNNode] = []
        private var rng: SeededGenerator
        private weak var scnView: SCNView?

        init(mapSeed: Int, health: Binding<Int>, ammo: Binding<Int>, kills: Binding<Int>) {
            healthBinding = health
            ammoBinding = ammo
            killsBinding = kills
            rng = SeededGenerator(seed: UInt64(bitPattern: Int64(mapSeed == 0 ? 0xB02 : mapSeed)))
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
                jumpVelocity = 5.8
            }
        }

        func applyReloadPulse(_ pulse: Int) {
            guard pulse != lastReloadPulse else { return }
            lastReloadPulse = pulse
            ammoBinding.wrappedValue = 30
            weaponNode.runAction(.sequence([
                .rotateBy(x: -0.28, y: 0, z: 0.12, duration: 0.12),
                .wait(duration: 0.18),
                .rotateBy(x: 0.28, y: 0, z: -0.12, duration: 0.12)
            ]))
        }

        private func buildScene() {
            scene.physicsWorld.gravity = SCNVector3(0, -20, 0)
            scene.fogStartDistance = 38
            scene.fogEndDistance = 95
            scene.fogColor = UIColor(red: 0.07, green: 0.065, blue: 0.055, alpha: 1)

            let ambient = SCNLight()
            ambient.type = .ambient
            ambient.intensity = 260
            ambient.color = UIColor(white: 0.50, alpha: 1)
            let ambientNode = SCNNode()
            ambientNode.light = ambient
            scene.rootNode.addChildNode(ambientNode)

            let moon = SCNLight()
            moon.type = .directional
            moon.intensity = 880
            moon.castsShadow = true
            moon.shadowRadius = 6
            let moonNode = SCNNode()
            moonNode.light = moon
            moonNode.eulerAngles = SCNVector3(-1.0, -0.7, 0)
            scene.rootNode.addChildNode(moonNode)

            let floor = SCNFloor()
            floor.reflectivity = 0
            floor.firstMaterial?.diffuse.contents = UIColor(red: 0.11, green: 0.10, blue: 0.085, alpha: 1)
            floor.firstMaterial?.roughness.contents = 0.94
            let floorNode = SCNNode(geometry: floor)
            floorNode.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
            scene.rootNode.addChildNode(floorNode)

            buildArena()
            buildProps()
            buildEnemies()
            buildPlayer()
        }

        private func buildArena() {
            let wallMaterial = SCNMaterial()
            wallMaterial.diffuse.contents = UIColor(red: 0.19, green: 0.17, blue: 0.14, alpha: 1)
            wallMaterial.roughness.contents = 0.86

            func wall(_ width: CGFloat, _ height: CGFloat, _ length: CGFloat, _ pos: SCNVector3) {
                let box = SCNBox(width: width, height: height, length: length, chamferRadius: 0.08)
                box.materials = [wallMaterial]
                let node = SCNNode(geometry: box)
                node.position = pos
                node.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
                scene.rootNode.addChildNode(node)
            }

            wall(60, 5, 1, SCNVector3(0, 2.5, -30))
            wall(60, 5, 1, SCNVector3(0, 2.5, 30))
            wall(1, 5, 60, SCNVector3(-30, 2.5, 0))
            wall(1, 5, 60, SCNVector3(30, 2.5, 0))

            wall(18, 4, 1, SCNVector3(-8, 2, -8))
            wall(1, 4, 16, SCNVector3(10, 2, 4))
            wall(12, 3, 1, SCNVector3(-12, 1.5, 12))
            wall(1, 3, 10, SCNVector3(-20, 1.5, -2))

            let shelter = SCNBox(width: 8, height: 0.35, length: 6, chamferRadius: 0.08)
            shelter.firstMaterial?.diffuse.contents = UIColor(white: 0.13, alpha: 1)
            let roof = SCNNode(geometry: shelter)
            roof.position = SCNVector3(13, 4.0, -13)
            scene.rootNode.addChildNode(roof)
        }

        private func buildProps() {
            for _ in 0..<28 {
                let w = CGFloat(Double.random(in: 1.2...3.4, using: &rng))
                let h = CGFloat(Double.random(in: 1.0...2.8, using: &rng))
                let d = CGFloat(Double.random(in: 1.2...3.4, using: &rng))
                let box = SCNBox(width: w, height: h, length: d, chamferRadius: 0.12)
                let base = CGFloat(Double.random(in: 0.10...0.25, using: &rng))
                box.firstMaterial?.diffuse.contents = UIColor(red: base * 1.1, green: base, blue: base * 0.82, alpha: 1)
                box.firstMaterial?.roughness.contents = 0.88
                let node = SCNNode(geometry: box)
                node.position = SCNVector3(
                    Float(Double.random(in: -25...25, using: &rng)),
                    Float(h / 2),
                    Float(Double.random(in: -25...25, using: &rng))
                )
                node.eulerAngles.y = Float(Double.random(in: -Double.pi...Double.pi, using: &rng))
                node.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
                scene.rootNode.addChildNode(node)
            }

            for i in 0..<9 {
                let light = SCNLight()
                light.type = .omni
                light.intensity = 520
                light.color = i % 3 == 0 ? UIColor(red: 1.0, green: 0.58, blue: 0.22, alpha: 1) : UIColor(white: 0.9, alpha: 1)
                light.attenuationStartDistance = 4
                light.attenuationEndDistance = 16
                let lightNode = SCNNode()
                lightNode.light = light
                let angle = Float(i) / 9 * Float.pi * 2
                lightNode.position = SCNVector3(cos(angle) * 20, 4, sin(angle) * 20)
                scene.rootNode.addChildNode(lightNode)
            }
        }

        private func buildEnemies() {
            enemies.removeAll()
            for i in 0..<12 {
                let body = SCNCapsule(capRadius: 0.38, height: 1.8)
                body.firstMaterial?.diffuse.contents = UIColor(red: 0.25, green: 0.31, blue: 0.20, alpha: 1)
                body.firstMaterial?.roughness.contents = 0.78
                let node = SCNNode(geometry: body)
                let angle = Float(i) / 12 * Float.pi * 2
                let radius: Float = 14 + Float(i % 3) * 4
                node.position = SCNVector3(cos(angle) * radius, 0.9, sin(angle) * radius)
                node.name = "zombie"
                node.physicsBody = SCNPhysicsBody(type: .kinematic, shape: nil)
                scene.rootNode.addChildNode(node)
                enemies.append(node)
            }
        }

        private func buildPlayer() {
            playerNode.position = SCNVector3(0, 1.65, 12)
            scene.rootNode.addChildNode(playerNode)

            let camera = SCNCamera()
            camera.fieldOfView = 72
            camera.zNear = 0.03
            camera.zFar = 160
            camera.wantsHDR = true
            camera.bloomIntensity = 0.38
            camera.bloomThreshold = 0.8
            camera.motionBlurIntensity = 0.12
            cameraNode.camera = camera
            playerNode.addChildNode(cameraNode)

            let gun = SCNBox(width: 0.18, height: 0.16, length: 0.75, chamferRadius: 0.04)
            gun.firstMaterial?.diffuse.contents = UIColor(white: 0.14, alpha: 1)
            gun.firstMaterial?.metalness.contents = 0.68
            gun.firstMaterial?.roughness.contents = 0.32
            weaponNode.geometry = gun
            weaponNode.position = SCNVector3(0.28, -0.25, -0.62)
            cameraNode.addChildNode(weaponNode)
        }

        @objc private func step(_ link: CADisplayLink) {
            let dt: Float
            if lastTimestamp == 0 { dt = 1 / 60 } else { dt = Float(min(0.05, link.timestamp - lastTimestamp)) }
            lastTimestamp = link.timestamp

            updateLook(dt: dt)
            updateMovement(dt: dt)
            updateEnemies(dt: dt, timestamp: link.timestamp)

            if firing && link.timestamp - lastShotTime > 0.115 {
                lastShotTime = link.timestamp
                fireRay()
            }

            if enemies.allSatisfy({ $0.parent == nil }) {
                buildEnemies()
            }
        }

        private func updateLook(dt: Float) {
            let sensitivity: Float = isAiming ? 0.00082 : 0.00122
            yaw -= Float(lookInput.width) * sensitivity
            pitch -= Float(lookInput.height) * sensitivity
            pitch = max(-1.25, min(1.25, pitch))
            playerNode.eulerAngles.y = yaw
            cameraNode.eulerAngles.x = pitch
            cameraNode.camera?.fieldOfView = isAiming ? 50 : 72
            weaponNode.position.z = isAiming ? -0.46 : -0.62
        }

        private func updateMovement(dt: Float) {
            let nx = Float(moveInput.width / 70.0)
            let ny = Float(-moveInput.height / 70.0)
            let speed: Float = 5.1
            let forward = SCNVector3(-sin(yaw), 0, -cos(yaw))
            let right = SCNVector3(cos(yaw), 0, -sin(yaw))
            var p = playerNode.position
            p.x += (forward.x * ny + right.x * nx) * speed * dt
            p.z += (forward.z * ny + right.z * nx) * speed * dt

            jumpVelocity -= 14.5 * dt
            p.y += jumpVelocity * dt
            if p.y <= 1.65 {
                p.y = 1.65
                jumpVelocity = 0
            }

            p.x = max(-28, min(28, p.x))
            p.z = max(-28, min(28, p.z))
            playerNode.position = p
        }

        private func updateEnemies(dt: Float, timestamp: CFTimeInterval) {
            var touchingPlayer = false
            for enemy in enemies where enemy.parent != nil {
                let dx = playerNode.position.x - enemy.position.x
                let dz = playerNode.position.z - enemy.position.z
                let distance = max(0.001, sqrt(dx * dx + dz * dz))
                if distance > 1.25 {
                    let speed: Float = 1.38
                    enemy.position.x += dx / distance * speed * dt
                    enemy.position.z += dz / distance * speed * dt
                    enemy.eulerAngles.y = atan2(dx, dz)
                } else {
                    touchingPlayer = true
                }
            }

            if touchingPlayer && timestamp - lastDamageTime > 0.48 {
                lastDamageTime = timestamp
                let nextHealth = max(0, healthBinding.wrappedValue - 12)
                healthBinding.wrappedValue = nextHealth
                if nextHealth == 0 {
                    healthBinding.wrappedValue = 100
                    ammoBinding.wrappedValue = 30
                    playerNode.position = SCNVector3(0, 1.65, 12)
                }
            }
        }

        private func fireRay() {
            guard ammoBinding.wrappedValue > 0, let view = scnView else { return }
            ammoBinding.wrappedValue -= 1

            let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            let hits = view.hitTest(center, options: [
                SCNHitTestOption.searchMode: SCNHitTestSearchMode.all.rawValue,
                SCNHitTestOption.backFaceCulling: false
            ])
            if let hit = hits.first(where: { $0.node.name == "zombie" }) {
                let node = hit.node
                killsBinding.wrappedValue += 1
                node.runAction(.sequence([
                    .fadeOpacity(to: 0.12, duration: 0.07),
                    .scale(to: 0.72, duration: 0.05),
                    .removeFromParentNode()
                ]))
            }

            weaponNode.runAction(.sequence([
                .moveBy(x: 0, y: 0, z: 0.07, duration: 0.025),
                .moveBy(x: 0, y: 0, z: -0.07, duration: 0.055)
            ]))
        }
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
