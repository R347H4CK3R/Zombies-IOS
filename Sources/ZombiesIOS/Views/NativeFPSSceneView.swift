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
        private let environmentCategory = 1 << 1
        private let zombieCategory = 1 << 2

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
        private let muzzleNode = SCNNode()
        private let muzzleLightNode = SCNNode()

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

        func setFiring(_ value: Bool) { firing = value }

        func applyJumpPulse(_ pulse: Int) {
            guard pulse != lastJumpPulse else { return }
            lastJumpPulse = pulse
            if playerNode.position.y <= 1.67 { jumpVelocity = 5.8 }
        }

        func applyReloadPulse(_ pulse: Int) {
            guard pulse != lastReloadPulse else { return }
            lastReloadPulse = pulse
            firing = false
            weaponNode.removeAction(forKey: "reload")
            weaponNode.runAction(.sequence([
                .rotateBy(x: -0.32, y: 0.08, z: 0.14, duration: 0.13),
                .wait(duration: 0.20),
                .rotateBy(x: 0.32, y: -0.08, z: -0.14, duration: 0.14),
                .run { [weak self] _ in self?.ammoBinding.wrappedValue = 30 }
            ]), forKey: "reload")
        }

        private func buildScene() {
            scene.physicsWorld.gravity = SCNVector3(0, -20, 0)
            scene.fogStartDistance = 34
            scene.fogEndDistance = 92
            scene.fogColor = UIColor(red: 0.065, green: 0.058, blue: 0.050, alpha: 1)

            let ambient = SCNLight()
            ambient.type = .ambient
            ambient.intensity = 220
            ambient.color = UIColor(red: 0.55, green: 0.58, blue: 0.62, alpha: 1)
            let ambientNode = SCNNode()
            ambientNode.light = ambient
            scene.rootNode.addChildNode(ambientNode)

            let moon = SCNLight()
            moon.type = .directional
            moon.intensity = 760
            moon.castsShadow = true
            moon.shadowRadius = 7
            moon.shadowSampleCount = 8
            let moonNode = SCNNode()
            moonNode.light = moon
            moonNode.eulerAngles = SCNVector3(-1.0, -0.7, 0)
            scene.rootNode.addChildNode(moonNode)

            let floor = SCNFloor()
            floor.reflectivity = 0
            floor.firstMaterial?.diffuse.contents = UIColor(red: 0.10, green: 0.087, blue: 0.07, alpha: 1)
            floor.firstMaterial?.roughness.contents = 0.96
            let floorNode = SCNNode(geometry: floor)
            floorNode.categoryBitMask = environmentCategory
            floorNode.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
            scene.rootNode.addChildNode(floorNode)

            buildArena()
            buildProps()
            buildPlayer()
            buildEnemies()
        }

        private func makeEnvironmentBox(width: CGFloat, height: CGFloat, length: CGFloat, position: SCNVector3, material: SCNMaterial) {
            let box = SCNBox(width: width, height: height, length: length, chamferRadius: 0.06)
            box.materials = [material]
            let node = SCNNode(geometry: box)
            node.position = position
            node.categoryBitMask = environmentCategory
            node.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
            scene.rootNode.addChildNode(node)
        }

        private func buildArena() {
            let concrete = SCNMaterial()
            concrete.diffuse.contents = UIColor(red: 0.17, green: 0.145, blue: 0.115, alpha: 1)
            concrete.roughness.contents = 0.92

            makeEnvironmentBox(width: 60, height: 5, length: 1, position: SCNVector3(0, 2.5, -30), material: concrete)
            makeEnvironmentBox(width: 60, height: 5, length: 1, position: SCNVector3(0, 2.5, 30), material: concrete)
            makeEnvironmentBox(width: 1, height: 5, length: 60, position: SCNVector3(-30, 2.5, 0), material: concrete)
            makeEnvironmentBox(width: 1, height: 5, length: 60, position: SCNVector3(30, 2.5, 0), material: concrete)
            makeEnvironmentBox(width: 18, height: 4, length: 1, position: SCNVector3(-8, 2, -8), material: concrete)
            makeEnvironmentBox(width: 1, height: 4, length: 16, position: SCNVector3(10, 2, 4), material: concrete)
            makeEnvironmentBox(width: 12, height: 3, length: 1, position: SCNVector3(-12, 1.5, 12), material: concrete)
            makeEnvironmentBox(width: 1, height: 3, length: 10, position: SCNVector3(-20, 1.5, -2), material: concrete)

            let roof = SCNBox(width: 8, height: 0.35, length: 6, chamferRadius: 0.08)
            roof.firstMaterial?.diffuse.contents = UIColor(white: 0.12, alpha: 1)
            let roofNode = SCNNode(geometry: roof)
            roofNode.position = SCNVector3(13, 4.0, -13)
            roofNode.categoryBitMask = environmentCategory
            roofNode.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
            scene.rootNode.addChildNode(roofNode)
        }

        private func buildProps() {
            for _ in 0..<24 {
                let w = CGFloat(Double.random(in: 1.0...3.0, using: &rng))
                let h = CGFloat(Double.random(in: 0.7...2.2, using: &rng))
                let d = CGFloat(Double.random(in: 1.0...3.0, using: &rng))
                let material = SCNMaterial()
                let base = CGFloat(Double.random(in: 0.09...0.22, using: &rng))
                material.diffuse.contents = UIColor(red: base * 1.18, green: base, blue: base * 0.78, alpha: 1)
                material.roughness.contents = 0.9
                let x = Float(Double.random(in: -24...24, using: &rng))
                let z = Float(Double.random(in: -24...24, using: &rng))
                if abs(x) < 4 && z > 8 { continue }
                makeEnvironmentBox(width: w, height: h, length: d, position: SCNVector3(x, Float(h / 2), z), material: material)
            }

            for i in 0..<9 {
                let light = SCNLight()
                light.type = .omni
                light.intensity = 500
                light.color = i % 3 == 0 ? UIColor(red: 1.0, green: 0.48, blue: 0.17, alpha: 1) : UIColor(red: 0.75, green: 0.80, blue: 0.88, alpha: 1)
                light.attenuationStartDistance = 3
                light.attenuationEndDistance = 17
                let node = SCNNode()
                node.light = light
                let angle = Float(i) / 9 * Float.pi * 2
                node.position = SCNVector3(cos(angle) * 20, 4.2, sin(angle) * 20)
                scene.rootNode.addChildNode(node)
            }
        }

        private func buildEnemies() {
            enemies.removeAll()
            for i in 0..<12 {
                let zombie = SCNNode()
                zombie.name = "zombie"
                zombie.categoryBitMask = zombieCategory
                let angle = Float(i) / 12 * Float.pi * 2
                let radius: Float = 15 + Float(i % 3) * 4
                zombie.position = SCNVector3(cos(angle) * radius, 0, sin(angle) * radius)

                let cloth = SCNMaterial()
                cloth.diffuse.contents = UIColor(red: 0.18, green: 0.22, blue: 0.15, alpha: 1)
                cloth.roughness.contents = 0.88
                let skin = SCNMaterial()
                skin.diffuse.contents = UIColor(red: 0.31, green: 0.29, blue: 0.22, alpha: 1)
                skin.roughness.contents = 0.84

                let torso = SCNNode(geometry: SCNBox(width: 0.62, height: 0.85, length: 0.34, chamferRadius: 0.10))
                torso.geometry?.materials = [cloth]
                torso.position = SCNVector3(0, 1.22, 0)
                let head = SCNNode(geometry: SCNSphere(radius: 0.24))
                head.geometry?.materials = [skin]
                head.position = SCNVector3(0, 1.86, 0)
                zombie.addChildNode(torso)
                zombie.addChildNode(head)

                for side: Float in [-1, 1] {
                    let arm = SCNNode(geometry: SCNCapsule(capRadius: 0.085, height: 0.78))
                    arm.geometry?.materials = [skin]
                    arm.position = SCNVector3(side * 0.40, 1.30, -0.18)
                    arm.eulerAngles.x = -.pi / 2.8
                    arm.eulerAngles.z = side * 0.12
                    zombie.addChildNode(arm)

                    let leg = SCNNode(geometry: SCNCapsule(capRadius: 0.10, height: 0.82))
                    leg.geometry?.materials = [cloth]
                    leg.position = SCNVector3(side * 0.17, 0.47, 0)
                    zombie.addChildNode(leg)

                    let eye = SCNNode(geometry: SCNSphere(radius: 0.032))
                    eye.geometry?.firstMaterial?.diffuse.contents = UIColor.orange
                    eye.geometry?.firstMaterial?.emission.contents = UIColor(red: 1, green: 0.24, blue: 0.02, alpha: 1)
                    eye.position = SCNVector3(side * 0.075, 1.90, -0.215)
                    zombie.addChildNode(eye)
                }

                zombie.enumerateChildNodes { child, _ in child.categoryBitMask = self.zombieCategory }
                zombie.physicsBody = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(geometry: SCNCapsule(capRadius: 0.36, height: 1.9)))
                scene.rootNode.addChildNode(zombie)
                enemies.append(zombie)
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
            camera.bloomIntensity = 0.42
            camera.bloomThreshold = 0.78
            camera.motionBlurIntensity = 0.10
            cameraNode.camera = camera
            playerNode.addChildNode(cameraNode)

            let gunMaterial = SCNMaterial()
            gunMaterial.diffuse.contents = UIColor(white: 0.12, alpha: 1)
            gunMaterial.metalness.contents = 0.72
            gunMaterial.roughness.contents = 0.30

            let receiver = SCNNode(geometry: SCNBox(width: 0.20, height: 0.17, length: 0.48, chamferRadius: 0.035))
            receiver.geometry?.materials = [gunMaterial]
            let barrel = SCNNode(geometry: SCNCylinder(radius: 0.047, height: 0.38))
            barrel.geometry?.materials = [gunMaterial]
            barrel.eulerAngles.x = .pi / 2
            barrel.position = SCNVector3(0, 0.015, -0.40)
            let grip = SCNNode(geometry: SCNBox(width: 0.10, height: 0.25, length: 0.12, chamferRadius: 0.025))
            grip.geometry?.materials = [gunMaterial]
            grip.position = SCNVector3(0, -0.16, 0.05)
            grip.eulerAngles.x = -0.25
            let sight = SCNNode(geometry: SCNBox(width: 0.065, height: 0.08, length: 0.08, chamferRadius: 0.01))
            sight.geometry?.materials = [gunMaterial]
            sight.position = SCNVector3(0, 0.125, -0.09)

            weaponNode.addChildNode(receiver)
            weaponNode.addChildNode(barrel)
            weaponNode.addChildNode(grip)
            weaponNode.addChildNode(sight)
            weaponNode.position = SCNVector3(0.28, -0.25, -0.62)
            cameraNode.addChildNode(weaponNode)

            let flash = SCNCone(topRadius: 0, bottomRadius: 0.075, height: 0.16)
            flash.firstMaterial?.diffuse.contents = UIColor.yellow
            flash.firstMaterial?.emission.contents = UIColor.orange
            muzzleNode.geometry = flash
            muzzleNode.eulerAngles.x = -.pi / 2
            muzzleNode.position = SCNVector3(0, 0.015, -0.63)
            muzzleNode.opacity = 0
            weaponNode.addChildNode(muzzleNode)

            let muzzleLight = SCNLight()
            muzzleLight.type = .omni
            muzzleLight.intensity = 0
            muzzleLight.color = UIColor.orange
            muzzleLight.attenuationEndDistance = 7
            muzzleLightNode.light = muzzleLight
            muzzleLightNode.position = SCNVector3(0, 0.02, -0.66)
            weaponNode.addChildNode(muzzleLightNode)
        }

        @objc private func step(_ link: CADisplayLink) {
            let dt: Float = lastTimestamp == 0 ? 1 / 60 : Float(min(0.05, link.timestamp - lastTimestamp))
            lastTimestamp = link.timestamp
            updateLook()
            updateMovement(dt: dt)
            updateEnemies(dt: dt, timestamp: link.timestamp)

            if firing && link.timestamp - lastShotTime > 0.115 {
                lastShotTime = link.timestamp
                fireRay()
            }
            if enemies.allSatisfy({ $0.parent == nil }) { buildEnemies() }
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
            let current = playerNode.position
            var proposed = current
            proposed.x += (forward.x * ny + right.x * nx) * speed * dt
            proposed.z += (forward.z * ny + right.z * nx) * speed * dt
            proposed.x = max(-28.5, min(28.5, proposed.x))
            proposed.z = max(-28.5, min(28.5, proposed.z))

            if !blocked(from: current, to: proposed) {
                playerNode.position.x = proposed.x
                playerNode.position.z = proposed.z
            } else {
                var slideX = current
                slideX.x = proposed.x
                if !blocked(from: current, to: slideX) { playerNode.position.x = proposed.x }
                var slideZ = playerNode.position
                slideZ.z = proposed.z
                if !blocked(from: playerNode.position, to: slideZ) { playerNode.position.z = proposed.z }
            }

            jumpVelocity -= 14.5 * dt
            playerNode.position.y += jumpVelocity * dt
            if playerNode.position.y <= 1.65 {
                playerNode.position.y = 1.65
                jumpVelocity = 0
            }
        }

        private func blocked(from: SCNVector3, to: SCNVector3) -> Bool {
            let dx = to.x - from.x
            let dz = to.z - from.z
            if abs(dx) + abs(dz) < 0.0001 { return false }
            let length = max(0.001, sqrt(dx * dx + dz * dz))
            let sideX = -dz / length * 0.28
            let sideZ = dx / length * 0.28
            let starts = [SCNVector3(from.x, 1.05, from.z), SCNVector3(from.x + sideX, 1.05, from.z + sideZ), SCNVector3(from.x - sideX, 1.05, from.z - sideZ)]
            let ends = [SCNVector3(to.x, 1.05, to.z), SCNVector3(to.x + sideX, 1.05, to.z + sideZ), SCNVector3(to.x - sideX, 1.05, to.z - sideZ)]
            for index in starts.indices {
                let hits = scene.rootNode.hitTestWithSegment(from: starts[index], to: ends[index], options: [.categoryBitMask: environmentCategory, .searchMode: SCNHitTestSearchMode.closest.rawValue])
                if !hits.isEmpty { return true }
            }
            return false
        }

        private func updateEnemies(dt: Float, timestamp: CFTimeInterval) {
            var touchingPlayer = false
            for enemy in enemies where enemy.parent != nil {
                let dx = playerNode.position.x - enemy.position.x
                let dz = playerNode.position.z - enemy.position.z
                let distance = max(0.001, sqrt(dx * dx + dz * dz))
                if distance > 1.25 {
                    let speed: Float = 1.38
                    let next = SCNVector3(enemy.position.x + dx / distance * speed * dt, enemy.position.y, enemy.position.z + dz / distance * speed * dt)
                    if !blockedZombie(from: enemy.position, to: next) { enemy.position = next }
                    enemy.eulerAngles.y = atan2(dx, dz)
                } else { touchingPlayer = true }
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

        private func blockedZombie(from: SCNVector3, to: SCNVector3) -> Bool {
            let start = SCNVector3(from.x, 0.9, from.z)
            let end = SCNVector3(to.x, 0.9, to.z)
            return !scene.rootNode.hitTestWithSegment(from: start, to: end, options: [.categoryBitMask: environmentCategory, .searchMode: SCNHitTestSearchMode.closest.rawValue]).isEmpty
        }

        private func zombieRoot(for node: SCNNode) -> SCNNode? {
            var current: SCNNode? = node
            while let candidate = current {
                if candidate.name == "zombie" { return candidate }
                current = candidate.parent
            }
            return nil
        }

        private func fireRay() {
            guard ammoBinding.wrappedValue > 0, let view = scnView else { return }
            ammoBinding.wrappedValue -= 1
            let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            let hits = view.hitTest(center, options: [.searchMode: SCNHitTestSearchMode.all.rawValue, .backFaceCulling: false])
            if let zombie = hits.compactMap({ zombieRoot(for: $0.node) }).first {
                killsBinding.wrappedValue += 1
                zombie.runAction(.sequence([.fadeOpacity(to: 0.12, duration: 0.07), .scale(to: 0.72, duration: 0.05), .removeFromParentNode()]))
            }

            weaponNode.removeAction(forKey: "recoil")
            weaponNode.runAction(.sequence([.moveBy(x: 0, y: 0.012, z: 0.075, duration: 0.022), .moveBy(x: 0, y: -0.012, z: -0.075, duration: 0.060)]), forKey: "recoil")
            muzzleNode.removeAllActions()
            muzzleNode.opacity = 1
            muzzleNode.runAction(.fadeOut(duration: 0.045))
            muzzleLightNode.light?.intensity = 950
            muzzleLightNode.runAction(.sequence([.wait(duration: 0.025), .run { [weak self] _ in self?.muzzleLightNode.light?.intensity = 0 }]))
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
