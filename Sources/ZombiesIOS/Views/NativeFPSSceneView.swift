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
    var cachedWorld: TranzitCachedWorld? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(runtimeMesh: runtimeMesh, cachedWorld: cachedWorld, health: $health, ammo: $ammo, kills: $kills)
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

    static func dismantleUIView(_ uiView: SCNView, coordinator: Coordinator) { coordinator.stop() }

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
        private let cachedWorld: TranzitCachedWorld?
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

        init(runtimeMesh: T6RuntimeMesh?, cachedWorld: TranzitCachedWorld?, health: Binding<Int>, ammo: Binding<Int>, kills: Binding<Int>) {
            self.runtimeMesh = runtimeMesh
            self.cachedWorld = cachedWorld
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

        func stop() { displayLink?.invalidate(); displayLink = nil }
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

        private var hasWorld: Bool { cachedWorld != nil || runtimeMesh != nil }

        private func buildScene() {
            scene.physicsWorld.gravity = SCNVector3(0, -20, 0)
            scene.fogStartDistance = hasWorld ? 110 : 35
            scene.fogEndDistance = hasWorld ? 420 : 95
            scene.fogColor = UIColor(red: 0.055, green: 0.050, blue: 0.045, alpha: 1)

            let ambient = SCNLight(); ambient.type = .ambient; ambient.intensity = hasWorld ? 520 : 260; ambient.color = UIColor(white: 0.72, alpha: 1)
            let ambientNode = SCNNode(); ambientNode.light = ambient; scene.rootNode.addChildNode(ambientNode)
            let sun = SCNLight(); sun.type = .directional; sun.intensity = 900; sun.castsShadow = true
            let sunNode = SCNNode(); sunNode.light = sun; sunNode.eulerAngles = SCNVector3(-0.9, -0.55, 0); scene.rootNode.addChildNode(sunNode)

            if let cachedWorld { buildCachedWorld(cachedWorld) }
            else if runtimeMesh != nil { buildDecodedWorld() }
            else { buildSafetyFloor(visible: true); buildFallbackArena() }

            buildPlayer()
            buildEnemies()
        }

        private func buildCachedWorld(_ world: TranzitCachedWorld) {
            guard world.positions.count >= 3, world.indices.count >= 3 else { buildSafetyFloor(visible: true); return }
            let vertices = world.positions.map { SCNVector3($0.x, $0.y, $0.z) }
            let normals = world.normals.map { SCNVector3($0.x, $0.y, $0.z) }
            let tex = world.uvs.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
            var sources = [SCNGeometrySource(vertices: vertices)]
            if normals.count == vertices.count { sources.append(SCNGeometrySource(normals: normals)) }
            if tex.count == vertices.count { sources.append(SCNGeometrySource(textureCoordinates: tex)) }

            let materialByID = Dictionary(uniqueKeysWithValues: world.materials.map { ($0.id, makeMaterial($0)) })
            var elements: [SCNGeometryElement] = []
            var materials: [SCNMaterial] = []
            for submesh in world.submeshes {
                guard submesh.firstIndex >= 0, submesh.indexCount >= 3,
                      submesh.firstIndex + submesh.indexCount <= world.indices.count else { continue }
                let slice = world.indices[submesh.firstIndex..<(submesh.firstIndex + submesh.indexCount)].map(Int32.init)
                let element = SCNGeometryElement(indices: slice, primitiveType: .triangles)
                elements.append(element)
                materials.append(materialByID[submesh.materialID] ?? diagnosticMaterial())
            }
            guard !elements.isEmpty else { buildSafetyFloor(visible: true); return }
            let geometry = SCNGeometry(sources: sources, elements: elements)
            geometry.materials = materials
            let node = SCNNode(geometry: geometry)
            node.name = "t6-native-cache-world"
            node.categoryBitMask = environmentCategory
            scene.rootNode.addChildNode(node)

            // Keep collision intentionally simpler than the full rendered mesh. A broad
            // floor provides stable movement while the visual world can contain 100k+
            // triangles without duplicating that cost into SceneKit physics.
            buildSafetyFloor(visible: false)
        }

        private func makeMaterial(_ cached: TranzitCachedMaterial) -> SCNMaterial {
            let material = SCNMaterial()
            material.name = cached.name
            material.lightingModel = .physicallyBased
            material.roughness.contents = 0.85
            material.metalness.contents = 0.02
            material.isDoubleSided = true
            material.diffuse.wrapS = .repeat; material.diffuse.wrapT = .repeat
            material.normal.wrapS = .repeat; material.normal.wrapT = .repeat

            let textureRoot: URL? = try? TranzitCachePaths.defaultPaths().activeTextures
            if let name = cached.diffuseTexture, let root = textureRoot,
               let image = UIImage(contentsOfFile: root.appendingPathComponent(name).path) {
                material.diffuse.contents = image
            } else {
                material.diffuse.contents = UIColor(red: 0.42, green: 0.38, blue: 0.31, alpha: 1)
            }
            if let name = cached.normalTexture, let root = textureRoot,
               let image = UIImage(contentsOfFile: root.appendingPathComponent(name).path) { material.normal.contents = image }
            if let name = cached.specularTexture, let root = textureRoot,
               let image = UIImage(contentsOfFile: root.appendingPathComponent(name).path) { material.specular.contents = image }
            if cached.alphaCutout { material.transparencyMode = .aOne }
            return material
        }

        private func diagnosticMaterial() -> SCNMaterial {
            let material = SCNMaterial()
            material.diffuse.contents = UIColor(red: 0.42, green: 0.38, blue: 0.31, alpha: 1)
            material.roughness.contents = 0.92
            material.isDoubleSided = true
            return material
        }

        private func buildSafetyFloor(visible: Bool) {
            let floor = SCNFloor(); floor.reflectivity = 0
            floor.firstMaterial?.diffuse.contents = UIColor(red: 0.085, green: 0.075, blue: 0.060, alpha: visible ? 1 : 0)
            floor.firstMaterial?.roughness.contents = 1.0; floor.firstMaterial?.transparency = visible ? 1 : 0
            let node = SCNNode(geometry: floor); node.position.y = visible ? 0 : -0.35; node.categoryBitMask = environmentCategory
            node.physicsBody = SCNPhysicsBody(type: .static, shape: nil); scene.rootNode.addChildNode(node)
        }

        private func buildDecodedWorld() {
            guard let runtimeMesh, runtimeMesh.vertices.count >= 3, runtimeMesh.indices.count >= 3 else { return }
            let source = SCNGeometrySource(vertices: runtimeMesh.vertices.map { SCNVector3($0.x, $0.y, $0.z) })
            let element = SCNGeometryElement(indices: runtimeMesh.indices.map { Int32($0) }, primitiveType: .triangles)
            let geometry = SCNGeometry(sources: [source], elements: [element]); geometry.materials = [diagnosticMaterial()]
            let node = SCNNode(geometry: geometry); node.name = "t6-ps3-diagnostic-world"; node.categoryBitMask = environmentCategory
            scene.rootNode.addChildNode(node); buildSafetyFloor(visible: false)
        }

        private func buildFallbackArena() {
            let material = diagnosticMaterial()
            addBox(20, 4, 1, SCNVector3(0, 2, -10), material)
            addBox(1, 4, 14, SCNVector3(9, 2, -2), material)
            addBox(8, 2.5, 1, SCNVector3(-7, 1.25, 6), material)
        }

        private func addBox(_ width: CGFloat, _ height: CGFloat, _ length: CGFloat, _ position: SCNVector3, _ material: SCNMaterial) {
            let box = SCNBox(width: width, height: height, length: length, chamferRadius: 0.03); box.materials = [material]
            let node = SCNNode(geometry: box); node.position = position; node.categoryBitMask = environmentCategory
            node.physicsBody = SCNPhysicsBody(type: .static, shape: nil); scene.rootNode.addChildNode(node)
        }

        private func buildPlayer() {
            playerNode.position = hasWorld ? SCNVector3(0, 1.65, 20) : SCNVector3(0, 1.65, 12); scene.rootNode.addChildNode(playerNode)
            let camera = SCNCamera(); camera.fieldOfView = 72; camera.zNear = 0.03; camera.zFar = hasWorld ? 520 : 220; camera.wantsHDR = true; camera.bloomIntensity = 0.18
            cameraNode.camera = camera; playerNode.addChildNode(cameraNode)
            let mat = SCNMaterial(); mat.diffuse.contents = UIColor(white: 0.12, alpha: 1); mat.metalness.contents = 0.7; mat.roughness.contents = 0.32
            let receiver = SCNNode(geometry: SCNBox(width: 0.20, height: 0.17, length: 0.48, chamferRadius: 0.03)); receiver.geometry?.materials = [mat]
            let barrel = SCNNode(geometry: SCNCylinder(radius: 0.045, height: 0.36)); barrel.geometry?.materials = [mat]; barrel.eulerAngles.x = .pi / 2; barrel.position = SCNVector3(0, 0.01, -0.40)
            weaponNode.addChildNode(receiver); weaponNode.addChildNode(barrel); weaponNode.position = SCNVector3(0.28, -0.25, -0.62); cameraNode.addChildNode(weaponNode)
        }

        private func buildEnemies() {
            enemies.removeAll()
            for i in 0..<8 {
                let zombie = SCNNode(); zombie.name = "zombie"; zombie.categoryBitMask = zombieCategory
                let angle = Float(i) / 8 * .pi * 2; let radius: Float = 12 + Float(i % 2) * 4
                zombie.position = SCNVector3(cos(angle) * radius, 0, sin(angle) * radius)
                let torsoMat = SCNMaterial(); torsoMat.diffuse.contents = UIColor(red: 0.18, green: 0.22, blue: 0.15, alpha: 1)
                let skinMat = SCNMaterial(); skinMat.diffuse.contents = UIColor(red: 0.32, green: 0.29, blue: 0.22, alpha: 1)
                let torso = SCNNode(geometry: SCNBox(width: 0.62, height: 0.9, length: 0.34, chamferRadius: 0.08)); torso.geometry?.materials = [torsoMat]; torso.position = SCNVector3(0, 1.2, 0)
                let head = SCNNode(geometry: SCNSphere(radius: 0.24)); head.geometry?.materials = [skinMat]; head.position = SCNVector3(0, 1.85, 0)
                zombie.addChildNode(torso); zombie.addChildNode(head); scene.rootNode.addChildNode(zombie); enemies.append(zombie)
            }
        }

        @objc private func step(_ link: CADisplayLink) {
            let dt: Float = lastTimestamp == 0 ? 1 / 60 : Float(min(0.05, link.timestamp - lastTimestamp)); lastTimestamp = link.timestamp
            updateLook(); updateMovement(dt: dt)
            if firing && link.timestamp - lastShotTime > 0.115 { lastShotTime = link.timestamp; fireRay() }
        }

        private func updateLook() {
            let sensitivity: Float = isAiming ? 0.00082 : 0.00122
            yaw -= Float(lookInput.width) * sensitivity; pitch -= Float(lookInput.height) * sensitivity; pitch = max(-1.25, min(1.25, pitch))
            playerNode.eulerAngles.y = yaw; cameraNode.eulerAngles.x = pitch; cameraNode.camera?.fieldOfView = isAiming ? 50 : 72
            weaponNode.position = isAiming ? SCNVector3(0, -0.20, -0.50) : SCNVector3(0.28, -0.25, -0.62)
        }

        private func updateMovement(dt: Float) {
            let nx = Float(moveInput.width / 70.0), ny = Float(-moveInput.height / 70.0), speed: Float = 5.1
            let forward = SCNVector3(-sin(yaw), 0, -cos(yaw)), right = SCNVector3(cos(yaw), 0, -sin(yaw))
            playerNode.position.x += (forward.x * ny + right.x * nx) * speed * dt; playerNode.position.z += (forward.z * ny + right.z * nx) * speed * dt
            let worldLimit: Float = hasWorld ? 90 : 30
            playerNode.position.x = max(-worldLimit, min(worldLimit, playerNode.position.x)); playerNode.position.z = max(-worldLimit, min(worldLimit, playerNode.position.z))
            jumpVelocity -= 14.5 * dt; playerNode.position.y += jumpVelocity * dt
            if playerNode.position.y <= 1.65 { playerNode.position.y = 1.65; jumpVelocity = 0 }
        }

        private func zombieRoot(for node: SCNNode) -> SCNNode? {
            var current: SCNNode? = node
            while let n = current { if n.name == "zombie" { return n }; current = n.parent }
            return nil
        }

        private func fireRay() {
            guard ammoBinding.wrappedValue > 0, let view = scnView else { return }
            ammoBinding.wrappedValue -= 1
            let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            if let zombie = view.hitTest(center, options: nil).compactMap({ zombieRoot(for: $0.node) }).first { killsBinding.wrappedValue += 1; zombie.removeFromParentNode() }
            weaponNode.removeAction(forKey: "recoil")
            weaponNode.runAction(.sequence([.moveBy(x: 0, y: 0.01, z: 0.07, duration: 0.025), .moveBy(x: 0, y: -0.01, z: -0.07, duration: 0.06)]), forKey: "recoil")
        }
    }
}
