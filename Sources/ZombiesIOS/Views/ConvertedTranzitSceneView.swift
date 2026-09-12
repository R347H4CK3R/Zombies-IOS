import SwiftUI
import SceneKit
import UIKit

struct ConvertedTranzitSceneView: UIViewRepresentable {
    let package: ConvertedRuntimePackage
    var move: CGSize
    var look: CGSize
    var firing: Bool
    var aiming: Bool
    var jumpPulse: Int
    var reloadPulse: Int
    @Binding var health: Int
    @Binding var ammo: Int
    @Binding var kills: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(package: package, health: $health, ammo: $ammo, kills: $kills)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.cameraNode
        view.backgroundColor = UIColor(white: 0.025, alpha: 1)
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

        private let package: ConvertedRuntimePackage
        private let healthBinding: Binding<Int>
        private let ammoBinding: Binding<Int>
        private let killsBinding: Binding<Int>
        private var displayLink: CADisplayLink?
        private var lastTimestamp: CFTimeInterval = 0
        private var yaw: Float = 0
        private var pitch: Float = 0
        private var firing = false
        private var lastShotTime: CFTimeInterval = 0
        private var jumpVelocity: Float = 0
        private var lastJumpPulse = 0
        private var lastReloadPulse = 0
        private var worldMin = SCNVector3Zero
        private var worldMax = SCNVector3Zero
        private var worldCenter = SCNVector3Zero

        init(
            package: ConvertedRuntimePackage,
            health: Binding<Int>,
            ammo: Binding<Int>,
            kills: Binding<Int>
        ) {
            self.package = package
            self.healthBinding = health
            self.ammoBinding = ammo
            self.killsBinding = kills
            super.init()
            buildScene()
        }

        func attach(to view: SCNView) {
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
            if playerNode.position.y <= worldMin.y + 1.7 {
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
            buildWorld()
            buildCollision()
            buildPlayerAndCamera()
            buildWeapon()
        }

        private func buildWorld() {
            let mesh = package.worldMesh
            worldMin = SCNVector3(mesh.boundsMin.x, mesh.boundsMin.y, mesh.boundsMin.z)
            worldMax = SCNVector3(mesh.boundsMax.x, mesh.boundsMax.y, mesh.boundsMax.z)
            worldCenter = SCNVector3(
                (worldMin.x + worldMax.x) * 0.5,
                (worldMin.y + worldMax.y) * 0.5,
                (worldMin.z + worldMax.z) * 0.5
            )

            let source = SCNGeometrySource(vertices: mesh.positions.map { SCNVector3($0.x, $0.y, $0.z) })
            let elements = materialElements(mesh)
            let geometry = SCNGeometry(sources: [source], elements: elements)
            geometry.materials = worldMaterials(for: mesh)

            let node = SCNNode(geometry: geometry)
            node.name = "converted-tranzit-world"
            scene.rootNode.addChildNode(node)
        }

        private func materialElements(_ mesh: ConvertedMesh) -> [SCNGeometryElement] {
            if mesh.materialGroups.isEmpty {
                return [SCNGeometryElement(indices: mesh.indices.map(Int32.init), primitiveType: .triangles)]
            }
            return mesh.materialGroups.compactMap { group in
                let start = Int(group.firstIndex)
                let end = min(mesh.indices.count, start + Int(group.indexCount))
                guard start >= 0, start < end else { return nil }
                return SCNGeometryElement(
                    indices: mesh.indices[start..<end].map(Int32.init),
                    primitiveType: .triangles
                )
            }
        }

        private func worldMaterials(for mesh: ConvertedMesh) -> [SCNMaterial] {
            let recordsByID = Dictionary(uniqueKeysWithValues: package.materialManifest.materials.map { ($0.id, $0) })
            let groups = mesh.materialGroups.isEmpty
                ? [ConvertedMaterialGroup(materialID: 0, firstIndex: 0, indexCount: UInt32(mesh.indices.count))]
                : mesh.materialGroups

            return groups.map { group in
                let record = recordsByID[Int(group.materialID)]
                let material = SCNMaterial()
                material.lightingModel = .physicallyBased
                material.isDoubleSided = record?.doubleSided ?? true

                if let record,
                   let textureURL = package.textureURL(for: record),
                   let image = UIImage(contentsOfFile: textureURL.path) {
                    material.diffuse.contents = image
                } else {
                    // Explicit visible fallback: the import report records why source
                    // material conversion failed; gameplay never falls back to black.
                    material.diffuse.contents = UIColor(white: 0.58, alpha: 1)
                    material.roughness.contents = 0.82
                }
                return material
            }
        }

        private func buildCollision() {
            let mesh = package.collisionMesh
            let source = SCNGeometrySource(vertices: mesh.positions.map { SCNVector3($0.x, $0.y, $0.z) })
            let element = SCNGeometryElement(indices: mesh.indices.map(Int32.init), primitiveType: .triangles)
            let geometry = SCNGeometry(sources: [source], elements: [element])
            let node = SCNNode(geometry: geometry)
            node.name = "converted-tranzit-collision"
            node.geometry?.firstMaterial?.transparency = 0
            let shape = SCNPhysicsShape(geometry: geometry, options: [.type: SCNPhysicsShape.ShapeType.concavePolyhedron])
            node.physicsBody = SCNPhysicsBody(type: .static, shape: shape)
            scene.rootNode.addChildNode(node)
        }

        private func buildPlayerAndCamera() {
            let spanX = max(1, worldMax.x - worldMin.x)
            let spanY = max(1, worldMax.y - worldMin.y)
            let spanZ = max(1, worldMax.z - worldMin.z)
            let horizontalSpan = max(spanX, spanZ)
            let cameraDistance = max(14, horizontalSpan * 0.30)
            let cameraHeight = worldCenter.y + max(3, spanY * 0.12)

            playerNode.position = SCNVector3(worldCenter.x, cameraHeight, worldMax.z + cameraDistance)
            let dz = max(0.001, playerNode.position.z - worldCenter.z)
            pitch = atan2(worldCenter.y - playerNode.position.y, dz)
            yaw = 0
            scene.rootNode.addChildNode(playerNode)

            let camera = SCNCamera()
            camera.fieldOfView = 72
            camera.zNear = 0.03
            camera.zFar = max(1200, Double(horizontalSpan * 8))
            camera.wantsHDR = false
            cameraNode.camera = camera
            cameraNode.eulerAngles.x = pitch
            playerNode.addChildNode(cameraNode)
        }

        private func buildWeapon() {
            let mesh = package.weaponMesh
            let source = SCNGeometrySource(vertices: mesh.positions.map { SCNVector3($0.x, $0.y, $0.z) })
            let element = SCNGeometryElement(indices: mesh.indices.map(Int32.init), primitiveType: .triangles)
            let geometry = SCNGeometry(sources: [source], elements: [element])
            let material = SCNMaterial()
            material.lightingModel = .physicallyBased

            if let path = package.weaponMaterial.diffuseTexturePath,
               let image = UIImage(contentsOfFile: package.rootURL.appendingPathComponent(path).path) {
                material.diffuse.contents = image
            } else {
                material.diffuse.contents = UIColor(white: 0.32, alpha: 1)
            }
            geometry.materials = [material]
            weaponNode.geometry = geometry

            let transform = package.weaponMaterial.transform
            weaponNode.position = SCNVector3(
                transform.firstPersonPosition.x,
                transform.firstPersonPosition.y,
                transform.firstPersonPosition.z
            )
            weaponNode.eulerAngles = SCNVector3(
                transform.firstPersonEulerAngles.x,
                transform.firstPersonEulerAngles.y,
                transform.firstPersonEulerAngles.z
            )
            weaponNode.scale = SCNVector3(transform.scale, transform.scale, transform.scale)
            cameraNode.addChildNode(weaponNode)
        }

        @objc private func step(_ link: CADisplayLink) {
            let dt: Float = lastTimestamp == 0
                ? 1 / 60
                : Float(min(0.05, link.timestamp - lastTimestamp))
            lastTimestamp = link.timestamp
            updateLook()
            updateMovement(dt: dt)

            if firing, ammoBinding.wrappedValue > 0, link.timestamp - lastShotTime > 0.115 {
                lastShotTime = link.timestamp
                ammoBinding.wrappedValue -= 1
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
            let nx = Float(moveInput.width / 70.0)
            let ny = Float(-moveInput.height / 70.0)
            let speed: Float = 5.1
            let forward = SCNVector3(-sin(yaw), 0, -cos(yaw))
            let right = SCNVector3(cos(yaw), 0, -sin(yaw))
            playerNode.position.x += (forward.x * ny + right.x * nx) * speed * dt
            playerNode.position.z += (forward.z * ny + right.z * nx) * speed * dt

            jumpVelocity -= 14.5 * dt
            playerNode.position.y += jumpVelocity * dt
            let floorY = worldMin.y + 1.65
            if playerNode.position.y <= floorY {
                playerNode.position.y = floorY
                jumpVelocity = 0
            }
        }
    }
}
