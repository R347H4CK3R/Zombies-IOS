import SwiftUI
import SceneKit

struct NativeFPSSceneView: UIViewRepresentable {
    var move: CGSize
    var look: CGSize
    var firing: Bool
    var aiming: Bool
    let mapSeed: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(mapSeed: mapSeed)
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
        context.coordinator.moveInput = move
        context.coordinator.lookInput = look
        context.coordinator.isAiming = aiming
        context.coordinator.setFiring(firing)
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

        private var displayLink: CADisplayLink?
        private var lastTimestamp: CFTimeInterval = 0
        private var yaw: Float = 0
        private var pitch: Float = 0
        private var firing = false
        private var lastShotTime: CFTimeInterval = 0
        private var enemies: [SCNNode] = []
        private var rng: SeededGenerator
        private weak var scnView: SCNView?

        init(mapSeed: Int) {
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

        private func buildScene() {
            scene.physicsWorld.gravity = SCNVector3(0, -20, 0)
            scene.fogStartDistance = 45
            scene.fogEndDistance = 110
            scene.fogColor = UIColor(white: 0.09, alpha: 1)

            let ambient = SCNLight()
            ambient.type = .ambient
            ambient.intensity = 280
            ambient.color = UIColor(white: 0.55, alpha: 1)
            let ambientNode = SCNNode()
            ambientNode.light = ambient
            scene.rootNode.addChildNode(ambientNode)

            let moon = SCNLight()
            moon.type = .directional
            moon.intensity = 900
            moon.castsShadow = true
            moon.shadowRadius = 6
            let moonNode = SCNNode()
            moonNode.light = moon
            moonNode.eulerAngles = SCNVector3(-1.0, -0.7, 0)
            scene.rootNode.addChildNode(moonNode)

            let floor = SCNFloor()
            floor.reflectivity = 0
            floor.firstMaterial?.diffuse.contents = UIColor(white: 0.12, alpha: 1)
            floor.firstMaterial?.roughness.contents = 0.9
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
            wallMaterial.diffuse.contents = UIColor(white: 0.18, alpha: 1)
            wallMaterial.roughness.contents = 0.8

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
        }

        private func buildProps() {
            for _ in 0..<24 {
                let w = CGFloat(Double.random(in: 1.2...3.4, using: &rng))
                let h = CGFloat(Double.random(in: 1.0...2.8, using: &rng))
                let d = CGFloat(Double.random(in: 1.2...3.4, using: &rng))
                let box = SCNBox(width: w, height: h, length: d, chamferRadius: 0.12)
                box.firstMaterial?.diffuse.contents = UIColor(white: CGFloat(Double.random(in: 0.10...0.28, using: &rng)), alpha: 1)
                box.firstMaterial?.roughness.contents = 0.85
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

            for i in 0..<8 {
                let light = SCNLight()
                light.type = .omni
                light.intensity = 520
                light.attenuationStartDistance = 4
                light.attenuationEndDistance = 16
                let lightNode = SCNNode()
                lightNode.light = light
                let angle = Float(i) / 8 * Float.pi * 2
                lightNode.position = SCNVector3(cos(angle) * 20, 4, sin(angle) * 20)
                scene.rootNode.addChildNode(lightNode)
            }
        }

        private func buildEnemies() {
            for i in 0..<10 {
                let body = SCNCapsule(capRadius: 0.38, height: 1.8)
                body.firstMaterial?.diffuse.contents = UIColor(red: 0.26, green: 0.34, blue: 0.24, alpha: 1)
                body.firstMaterial?.roughness.contents = 0.75
                let node = SCNNode(geometry: body)
                let angle = Float(i) / 10 * Float.pi * 2
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
            camera.bloomIntensity = 0.35
            camera.bloomThreshold = 0.8
            camera.motionBlurIntensity = 0.15
            cameraNode.camera = camera
            playerNode.addChildNode(cameraNode)

            let gun = SCNBox(width: 0.18, height: 0.16, length: 0.75, chamferRadius: 0.04)
            gun.firstMaterial?.diffuse.contents = UIColor(white: 0.15, alpha: 1)
            gun.firstMaterial?.metalness.contents = 0.65
            gun.firstMaterial?.roughness.contents = 0.35
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
            updateEnemies(dt: dt)

            if firing && link.timestamp - lastShotTime > 0.13 {
                lastShotTime = link.timestamp
                fireRay()
            }
        }

        private func updateLook(dt: Float) {
            let sensitivity: Float = isAiming ? 0.00085 : 0.00125
            yaw -= Float(lookInput.width) * sensitivity
            pitch -= Float(lookInput.height) * sensitivity
            pitch = max(-1.25, min(1.25, pitch))
            playerNode.eulerAngles.y = yaw
            cameraNode.eulerAngles.x = pitch
            cameraNode.camera?.fieldOfView = isAiming ? 52 : 72
            weaponNode.position.z = isAiming ? -0.46 : -0.62
        }

        private func updateMovement(dt: Float) {
            let nx = Float(moveInput.width / 70.0)
            let ny = Float(-moveInput.height / 70.0)
            let speed: Float = 5.2
            let forward = SCNVector3(-sin(yaw), 0, -cos(yaw))
            let right = SCNVector3(cos(yaw), 0, -sin(yaw))
            var p = playerNode.position
            p.x += (forward.x * ny + right.x * nx) * speed * dt
            p.z += (forward.z * ny + right.z * nx) * speed * dt
            p.x = max(-28, min(28, p.x))
            p.z = max(-28, min(28, p.z))
            playerNode.position = p
        }

        private func updateEnemies(dt: Float) {
            for enemy in enemies where enemy.parent != nil {
                let dx = playerNode.position.x - enemy.position.x
                let dz = playerNode.position.z - enemy.position.z
                let distance = max(0.001, sqrt(dx * dx + dz * dz))
                if distance > 1.3 {
                    let speed: Float = 1.25
                    enemy.position.x += dx / distance * speed * dt
                    enemy.position.z += dz / distance * speed * dt
                    enemy.eulerAngles.y = atan2(dx, dz)
                }
            }
        }

        private func fireRay() {
            guard let view = scnView else { return }
            let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            let hits = view.hitTest(center, options: [
                SCNHitTestOption.searchMode: SCNHitTestSearchMode.all.rawValue,
                SCNHitTestOption.backFaceCulling: false
            ])
            if let hit = hits.first(where: { $0.node.name == "zombie" }) {
                let node = hit.node
                node.runAction(.sequence([
                    .fadeOpacity(to: 0.15, duration: 0.08),
                    .removeFromParentNode()
                ]))
            }

            weaponNode.runAction(.sequence([
                .moveBy(x: 0, y: 0, z: 0.06, duration: 0.035),
                .moveBy(x: 0, y: 0, z: -0.06, duration: 0.06)
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
