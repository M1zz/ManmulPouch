import QuartzCore
import SwiftUI

/// Physics + state machine for the coin toss.
///
/// The outcome is decided by `FateRandom.coin()` at the moment of the catch
/// (or landing) — never by the animation. The final rotation is then solved
/// backwards so the spin settles on the correct face.
@MainActor
final class CoinModel: NSObject, ObservableObject {

    enum Phase: Equatable {
        case idle
        case air
        case held        // caught, hand closed
        case settle      // rotating to the result face
        case reveal
    }

    // MARK: Published state

    @Published var phase: Phase = .idle
    @Published var rotation: Double = restTilt     // degrees around X
    @Published var altitude: Double = 0            // points above the felt
    @Published var scale: Double = 1
    @Published var spinSpeed: Double = 0           // deg/s, for motion blur
    @Published var outcome: Bool?                  // true = 앞(陽)
    @Published var revealSource: String = ""

    static let restTilt: Double = -14

    // MARK: Physics

    private var displayLink: CADisplayLink?
    private let gravity: Double = 2600             // pt/s²

    private var launchStart: CFTimeInterval = 0
    private var v0: Double = 0
    private var omega: Double = 0
    private var rot0: Double = 0
    private var maxHeight: Double = 1
    private var scaleAmp: Double = 0
    private var airtime: Double = 0

    private var settleStart: CFTimeInterval = 0
    private var settleFrom: Double = 0
    private var settleTo: Double = 0
    private var settleDuration: Double = 0.85
    private var settleBounces = true

    // MARK: Input

    func flick(velocity upwardPointsPerSecond: Double) {
        guard phase == .idle || phase == .reveal else { return }
        outcome = nil
        phase = .air

        v0 = min(1650, max(950, upwardPointsPerSecond * 0.55))
        omega = min(2300, max(1000, upwardPointsPerSecond * 1.1))
        maxHeight = v0 * v0 / (2 * gravity)
        scaleAmp = min(0.5, maxHeight / 460 * 0.55)
        airtime = 2 * v0 / gravity
        rot0 = rotation
        launchStart = CACurrentMediaTime()

        SoundEngine.shared.coinFlick()
        Haptics.tap()
        startLink()
    }

    /// Palm slap while the coin is in the air.
    func catchNow() {
        guard phase == .air else { return }
        stopLink()
        phase = .held
        outcome = FateRandom.coin()
        spinSpeed = 0
        SoundEngine.shared.thud()
        Haptics.snap()
    }

    /// Open the hand: a last half-turn to the decided face.
    func openHand() {
        guard phase == .held, outcome != nil else { return }
        revealSource = "손 안에서 확인"
        beginSettle(duration: 0.48, bounces: false)
    }

    func acknowledgeReveal() {
        if phase == .reveal { phase = .idle }
    }

    // MARK: Display link

    private func startLink() {
        stopLink()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        switch phase {
        case .air:
            let t = now - launchStart
            if t >= airtime {
                land()
                return
            }
            altitude = max(0, v0 * t - 0.5 * gravity * t * t)
            rotation = rot0 + omega * t
            spinSpeed = omega
            scale = 1 + scaleAmp * (altitude / max(1, maxHeight))

        case .settle:
            let p = min(1, (now - settleStart) / settleDuration)
            let eased = 1 - pow(1 - p, 3)
            rotation = settleFrom + (settleTo - settleFrom) * eased
            spinSpeed = (settleTo - settleFrom) / settleDuration * pow(1 - p, 2)
            if settleBounces {
                altitude = abs(sin(p * .pi * 2.5)) * 30 * (1 - p)
            } else {
                altitude = 0
            }
            scale = 1
            if p >= 1 { finishReveal() }

        default:
            stopLink()
        }
    }

    // MARK: Landing / settling

    private func land() {
        outcome = FateRandom.coin()
        revealSource = "바닥에 떨어졌다"
        SoundEngine.shared.thud()
        Haptics.thud()
        beginSettle(duration: 0.85, bounces: true, extraTurns: 1)
    }

    private func beginSettle(duration: Double, bounces: Bool, extraTurns: Int = 0) {
        guard let outcome else { return }
        phase = .settle
        settleFrom = rotation
        settleTo = targetRotation(from: rotation, front: outcome, extraTurns: extraTurns)
        settleDuration = duration
        settleBounces = bounces
        settleStart = CACurrentMediaTime()
        startLink()
    }

    /// Smallest rotation ≥ current (+ extra turns) that shows the result face,
    /// keeping the resting tilt.
    private func targetRotation(from: Double, front: Bool, extraTurns: Int) -> Double {
        let want: Double = front ? 0 : 180
        var target = (from - want) / 360
        target = ceil(target) * 360 + want
        while target < from + 90 { target += 360 }
        return target + Double(extraTurns) * 360 + Self.restTilt
    }

    private func finishReveal() {
        stopLink()
        spinSpeed = 0
        altitude = 0
        phase = .reveal
        SoundEngine.shared.revealChime()
        Haptics.success()
    }
}
