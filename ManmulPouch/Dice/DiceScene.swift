import SceneKit
import SwiftUI

// MARK: - Physics scene

/// A real 3D dice tray. The dice are rigid bodies thrown with a
/// cryptographically random impulse and spin (SystemRandomNumberGenerator);
/// the result is whatever face physics leaves pointing up — fate decides
/// the throw, gravity decides the rest.
@MainActor
final class DiceScene: NSObject, ObservableObject {

    @Published private(set) var values: [Int] = [1]
    @Published private(set) var isRolling = false

    let scene = SCNScene()

    var count: Int { dieNodes.count }
    var total: Int { values.reduce(0, +) }

    private var dieNodes: [SCNNode] = []
    private var settleTimer: Timer?
    private var elapsed: Double = 0
    private var stableTicks = 0
    private var lastClack: CFTimeInterval = 0

    private enum Category {
        static let tray = 1 << 0
        static let die  = 1 << 1
    }

    override init() {
        super.init()
        buildScene()
        setCountInternal(1)
    }

    // MARK: Public controls

    func setCount(_ count: Int) {
        guard !isRolling else { return }
        let clamped = max(1, min(6, count))
        guard clamped != dieNodes.count else { return }
        setCountInternal(clamped)
        Haptics.tap()
    }

    func roll() {
        guard !isRolling else { return }
        isRolling = true
        Haptics.thud()

        var fate = SystemRandomNumberGenerator()
        for (index, node) in dieNodes.enumerated() {
            guard let body = node.physicsBody else { continue }
            let column = index % 3
            let row = index / 3
            node.position = SCNVector3(
                Float(column - 1) * 1.4 + Float.random(in: -0.15...0.15, using: &fate),
                2.0 + Float(row) * 1.3,
                2.1
            )
            node.eulerAngles = SCNVector3(Float.random(in: 0...(2 * .pi), using: &fate),
                                          Float.random(in: 0...(2 * .pi), using: &fate),
                                          Float.random(in: 0...(2 * .pi), using: &fate))
            body.resetTransform()
            body.clearAllForces()
            body.velocity = SCNVector3(Float.random(in: -2.5...2.5, using: &fate),
                                       Float.random(in: 0.5...2.0, using: &fate),
                                       Float.random(in: -10 ... -7, using: &fate))
            var axis = simd_float3(Float.random(in: -1...1, using: &fate),
                                   Float.random(in: -1...1, using: &fate),
                                   Float.random(in: -1...1, using: &fate))
            if simd_length(axis) < 0.1 { axis = simd_float3(1, 0, 0) }
            axis = simd_normalize(axis)
            body.angularVelocity = SCNVector4(axis.x, axis.y, axis.z,
                                              Float.random(in: 14...26, using: &fate))
        }
        startSettleWatch()
    }

    // MARK: Scene construction

    private func buildScene() {
        scene.background.contents = UIColor.clear
        scene.physicsWorld.gravity = SCNVector3(0, -30, 0)
        scene.physicsWorld.contactDelegate = self

        // Camera: front-top, looking down into the tray
        let camera = SCNCamera()
        camera.fieldOfView = 38
        camera.zNear = 0.1
        camera.zFar = 60
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 8.6, 7.4)
        cameraNode.look(at: SCNVector3(0, 0, 0.4))
        scene.rootNode.addChildNode(cameraNode)

        // Key light with soft shadows
        let key = SCNLight()
        key.type = .directional
        key.intensity = 900
        key.castsShadow = true
        key.shadowMode = .deferred
        key.shadowColor = UIColor.black.withAlphaComponent(0.45)
        key.shadowRadius = 7
        key.shadowSampleCount = 16
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-Float.pi / 2.6, -0.35, 0)
        scene.rootNode.addChildNode(keyNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 450
        ambient.color = UIColor(white: 0.9, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        // Shadow-catching floor: invisible except for the shadows it receives,
        // so the felt background shows through. Top surface sits at y = 0.
        let floorGeometry = SCNBox(width: 16, height: 1, length: 16, chamferRadius: 0)
        let floorMaterial = SCNMaterial()
        floorMaterial.lightingModel = .shadowOnly
        floorGeometry.materials = [floorMaterial]
        let floor = SCNNode(geometry: floorGeometry)
        floor.position = SCNVector3(0, -0.5, 0)
        floor.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
        floor.physicsBody?.friction = 0.9
        floor.physicsBody?.restitution = 0.3
        floor.physicsBody?.categoryBitMask = Category.tray
        scene.rootNode.addChildNode(floor)

        // Invisible tray walls + ceiling keep the dice in view
        addWall(width: 0.4, height: 8, length: 6.4, at: SCNVector3(-3.9, 4, 0))
        addWall(width: 0.4, height: 8, length: 6.4, at: SCNVector3(3.9, 4, 0))
        addWall(width: 8, height: 8, length: 0.4, at: SCNVector3(0, 4, -3.0))
        addWall(width: 8, height: 8, length: 0.4, at: SCNVector3(0, 4, 3.0))
        addWall(width: 8, height: 0.4, length: 6.4, at: SCNVector3(0, 7.5, 0))
    }

    private func addWall(width: CGFloat, height: CGFloat, length: CGFloat, at position: SCNVector3) {
        let shape = SCNPhysicsShape(
            geometry: SCNBox(width: width, height: height, length: length, chamferRadius: 0)
        )
        let node = SCNNode()
        node.position = position
        node.physicsBody = SCNPhysicsBody(type: .static, shape: shape)
        node.physicsBody?.restitution = 0.4
        node.physicsBody?.categoryBitMask = Category.tray
        scene.rootNode.addChildNode(node)
    }

    // MARK: Dice nodes

    private func setCountInternal(_ count: Int) {
        while dieNodes.count > count {
            dieNodes.removeLast().removeFromParentNode()
        }
        while dieNodes.count < count {
            let node = Self.makeDieNode()
            dieNodes.append(node)
            scene.rootNode.addChildNode(node)
        }

        // Rest the dice in a tidy grid, face 1 up
        for (index, node) in dieNodes.enumerated() {
            let column = index % 3
            let row = index / 3
            let columnsInRow = min(count - row * 3, 3)
            node.position = SCNVector3(
                (Float(column) - Float(columnsInRow - 1) / 2) * 1.5,
                0.5,
                Float(row) * 1.5 - 0.75
            )
            node.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
            node.physicsBody?.clearAllForces()
            node.physicsBody?.velocity = SCNVector3Zero
            node.physicsBody?.angularVelocity = SCNVector4Zero
            node.physicsBody?.resetTransform()
        }
        values = Array(repeating: 1, count: count)
    }

    private static func makeDieNode() -> SCNNode {
        let box = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0.09)
        box.materials = dieMaterials
        let node = SCNNode(geometry: box)
        let body = SCNPhysicsBody(
            type: .dynamic,
            shape: SCNPhysicsShape(geometry: box,
                                   options: [.type: SCNPhysicsShape.ShapeType.convexHull])
        )
        body.mass = 1
        body.friction = 0.8
        body.restitution = 0.32
        body.rollingFriction = 0.25
        body.angularDamping = 0.12
        body.damping = 0.1
        body.categoryBitMask = Category.die
        body.contactTestBitMask = Category.die | Category.tray
        node.physicsBody = body
        return node
    }

    // SCNBox material order: +z, +x, -z, -x, +y, -y.
    // Opposite faces sum to 7, like a real die.
    private static let dieMaterials: [SCNMaterial] = [1, 3, 6, 4, 2, 5].map { value in
        let material = SCNMaterial()
        material.diffuse.contents = faceImage(value: value)
        material.lightingModel = .blinn
        material.specular.contents = UIColor(white: 0.35, alpha: 1)
        return material
    }

    private static func faceImage(value: Int) -> UIImage {
        let size: CGFloat = 256
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { context in
            let bone = UIColor(red: 0.914, green: 0.878, blue: 0.788, alpha: 1)
            let boneEdge = UIColor(red: 0.795, green: 0.755, blue: 0.650, alpha: 1)
            let pip = UIColor(red: 0.298, green: 0.196, blue: 0.031, alpha: 1)

            boneEdge.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
            bone.setFill()
            context.fill(CGRect(x: 7, y: 7, width: size - 14, height: size - 14))

            pip.setFill()
            let pipDiameter = size * 0.19
            let offset = size * 0.26
            let center = size / 2
            for position in pipLayout(value) {
                context.cgContext.fillEllipse(in: CGRect(
                    x: center + position.x * offset - pipDiameter / 2,
                    y: center + position.y * offset - pipDiameter / 2,
                    width: pipDiameter,
                    height: pipDiameter
                ))
            }
        }
    }

    private static func pipLayout(_ value: Int) -> [CGPoint] {
        switch value {
        case 1: [.init(x: 0, y: 0)]
        case 2: [.init(x: -1, y: -1), .init(x: 1, y: 1)]
        case 3: [.init(x: -1, y: -1), .init(x: 0, y: 0), .init(x: 1, y: 1)]
        case 4: [.init(x: -1, y: -1), .init(x: 1, y: -1),
                 .init(x: -1, y: 1), .init(x: 1, y: 1)]
        case 5: [.init(x: -1, y: -1), .init(x: 1, y: -1), .init(x: 0, y: 0),
                 .init(x: -1, y: 1), .init(x: 1, y: 1)]
        default: [.init(x: -1, y: -1), .init(x: 1, y: -1),
                  .init(x: -1, y: 0), .init(x: 1, y: 0),
                  .init(x: -1, y: 1), .init(x: 1, y: 1)]
        }
    }

    // MARK: Settling

    private func startSettleWatch() {
        settleTimer?.invalidate()
        elapsed = 0
        stableTicks = 0
        settleTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard self != nil else {
                timer.invalidate()
                return
            }
            Task { @MainActor in self?.settleTick() }
        }
    }

    private func settleTick() {
        elapsed += 0.1
        let allResting = dieNodes.allSatisfy { node in
            guard let body = node.physicsBody else { return true }
            let velocity = body.velocity
            let speed = sqrt(velocity.x * velocity.x
                             + velocity.y * velocity.y
                             + velocity.z * velocity.z)
            return speed < 0.12 && abs(body.angularVelocity.w) < 0.35
        }
        stableTicks = allResting ? stableTicks + 1 : 0
        if stableTicks >= 3 || elapsed > 6 {
            settleTimer?.invalidate()
            settleTimer = nil
            finishRoll()
        }
    }

    private func finishRoll() {
        values = dieNodes.map(Self.upValue(of:))
        isRolling = false
        SoundEngine.shared.diceClack()
        Haptics.success()
    }

    /// The face value whose outward normal points closest to world-up.
    private static func upValue(of node: SCNNode) -> Int {
        let transform = node.presentation.simdWorldTransform
        let candidates: [(Float, Int)] = [
            (transform.columns.0.y, 3), (-transform.columns.0.y, 4),
            (transform.columns.1.y, 2), (-transform.columns.1.y, 5),
            (transform.columns.2.y, 1), (-transform.columns.2.y, 6),
        ]
        return candidates.max(by: { $0.0 < $1.0 })!.1
    }

    // MARK: Contact sounds

    fileprivate func clack(impulse: CGFloat) {
        let now = CACurrentMediaTime()
        guard now - lastClack > 0.09 else { return }
        lastClack = now
        SoundEngine.shared.diceClack()
        Haptics.click(min(0.6, 0.25 + impulse * 0.05))
    }
}

extension DiceScene: SCNPhysicsContactDelegate {
    nonisolated func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        let impulse = contact.collisionImpulse
        guard impulse > 0.5 else { return }
        Task { @MainActor in self.clack(impulse: impulse) }
    }
}

// MARK: - SwiftUI wrapper

struct DiceTrayView: UIViewRepresentable {
    let scene: DiceScene

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = scene.scene
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.isPlaying = true
        view.allowsCameraControl = false
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {}
}
