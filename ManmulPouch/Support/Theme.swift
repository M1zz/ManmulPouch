import SwiftUI
import UIKit

// MARK: - Palette (felt table & antique gold)

enum Pouch {
    static let felt     = Color(red: 0.059, green: 0.118, blue: 0.094)   // #0F1E18
    static let feltMid  = Color(red: 0.102, green: 0.200, blue: 0.157)
    static let feltDeep = Color(red: 0.027, green: 0.063, blue: 0.035)
    static let goldHi   = Color(red: 0.976, green: 0.875, blue: 0.541)   // #F9DF8A
    static let goldMid  = Color(red: 0.824, green: 0.627, blue: 0.224)   // #D2A039
    static let goldLow  = Color(red: 0.541, green: 0.369, blue: 0.090)   // #8A5E17
    static let goldDark = Color(red: 0.298, green: 0.196, blue: 0.031)   // #4C3208
    static let bone     = Color(red: 0.914, green: 0.878, blue: 0.788)   // #E9E0C9
    static let boneDim  = Color(red: 0.608, green: 0.627, blue: 0.545)   // #9BA08B
    static let leather  = Color(red: 0.169, green: 0.106, blue: 0.078)   // #2B1B14
}

struct FeltBackground: View {
    var body: some View {
        RadialGradient(
            colors: [Pouch.feltMid, Pouch.felt, Pouch.feltDeep],
            center: .init(x: 0.5, y: 0.22),
            startRadius: 40,
            endRadius: 700
        )
        .ignoresSafeArea()
    }
}

// MARK: - Perfect randomness
//
// SystemRandomNumberGenerator is backed by a cryptographically secure
// source on Apple platforms (arc4random_buf). No seeds, no bias.

enum FateRandom {
    static func coin() -> Bool {
        var g = SystemRandomNumberGenerator()
        return Bool.random(using: &g)
    }

    static func die(sides: Int = 6) -> Int {
        var g = SystemRandomNumberGenerator()
        return Int.random(in: 1...sides, using: &g)
    }
}

// MARK: - Haptics

enum Haptics {
    private static let light  = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let heavy  = UIImpactFeedbackGenerator(style: .heavy)
    private static let rigid  = UIImpactFeedbackGenerator(style: .rigid)
    private static let notify = UINotificationFeedbackGenerator()

    static func tap()    { light.impactOccurred() }
    static func thud()   { heavy.impactOccurred() }
    static func snap()   { rigid.impactOccurred(intensity: 1.0) }
    static func click(_ intensity: CGFloat = 0.7) { medium.impactOccurred(intensity: intensity) }
    static func success() { notify.notificationOccurred(.success) }
    static func warning() { notify.notificationOccurred(.warning) }
}

// MARK: - Shake detection (for dice)

extension Notification.Name {
    static let deviceDidShake = Notification.Name("deviceDidShake")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}

// MARK: - Small helpers

extension Double {
    /// Normalized to 0..<360
    var wrappedDegrees: Double {
        let r = truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }
}
