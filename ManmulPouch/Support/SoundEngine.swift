import AVFoundation

/// A tiny additive synthesizer. Every sound in the app (coin ring, whistle,
/// card whoosh, dice clack) is generated in code, so the project needs no
/// audio assets at all.
final class SoundEngine {
    static let shared = SoundEngine()

    // MARK: Voice

    private final class Voice {
        enum Kind {
            case sine(freq: Double)
            case noise
            case whistle(freq: Double)   // sustained, with pea-roll tremolo
        }
        let kind: Kind
        var phase: Double = 0
        var amp: Double
        var decayPerSample: Double       // multiplied every sample (1.0 = sustain)
        var t: Double = 0                // voice-local time in seconds
        var released = false

        init(kind: Kind, amp: Double, decayPerSample: Double) {
            self.kind = kind
            self.amp = amp
            self.decayPerSample = decayPerSample
        }
    }

    // MARK: State

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode!
    private var sampleRate: Double = 44100
    private var voices: [Voice] = []
    private let lock = NSLock()
    private var started = false
    private var noiseSeed: UInt64 = 0x9E3779B97F4A7C15

    var isMuted = false

    // MARK: Setup

    private init() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)

        let outputFormat = engine.outputNode.outputFormat(forBus: 0)
        sampleRate = outputFormat.sampleRate

        sourceNode = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)

            self.lock.lock()
            defer { self.lock.unlock() }

            let dt = 1.0 / self.sampleRate

            for frame in 0..<Int(frameCount) {
                var sample: Double = 0
                for voice in self.voices where voice.amp > 0.00005 {
                    switch voice.kind {
                    case .sine(let freq):
                        sample += sin(2 * .pi * voice.phase) * voice.amp
                        voice.phase += freq * dt
                        voice.amp *= voice.decayPerSample

                    case .noise:
                        sample += self.nextNoise() * voice.amp
                        voice.amp *= voice.decayPerSample

                    case .whistle(let freq):
                        // Pea-roll tremolo ~38 Hz + slight pitch flutter
                        let tremolo = 0.72 + 0.28 * sin(2 * .pi * 38 * voice.t)
                        let flutter = 1.0 + 0.004 * sin(2 * .pi * 6.5 * voice.t)
                        sample += sin(2 * .pi * voice.phase) * voice.amp * tremolo
                        sample += self.nextNoise() * voice.amp * 0.06
                        voice.phase += freq * flutter * dt
                        if voice.released {
                            voice.amp *= voice.decayPerSample
                        }
                    }
                    voice.t += dt
                }

                let clipped = Float(max(-1, min(1, sample)))
                for buffer in ablPointer {
                    let buf = UnsafeMutableBufferPointer<Float>(buffer)
                    buf[frame] = clipped
                }
            }

            self.voices.removeAll { $0.amp <= 0.00005 }
            return noErr
        }

        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: outputFormat)
        engine.mainMixerNode.outputVolume = 0.9
    }

    private func nextNoise() -> Double {
        // xorshift64* — cheap white noise, safe on the render thread
        noiseSeed ^= noiseSeed >> 12
        noiseSeed ^= noiseSeed << 25
        noiseSeed ^= noiseSeed >> 27
        let value = noiseSeed &* 0x2545F4914F6CDD1D
        return (Double(value >> 11) / Double(1 << 53)) * 2 - 1
    }

    private func ensureRunning() {
        if !engine.isRunning {
            try? engine.start()
        }
        started = engine.isRunning
    }

    private func decay(seconds: Double) -> Double {
        // amp reaches ~0.001 after `seconds`
        pow(0.001, 1.0 / (seconds * sampleRate))
    }

    private func add(_ voice: Voice) {
        guard !isMuted else { return }
        ensureRunning()
        lock.lock()
        if voices.count < 48 { voices.append(voice) }
        lock.unlock()
    }

    // MARK: Public sounds

    /// Bright metallic ring: coin flick / catch reveal.
    func ping(_ freqs: [Double], gain: Double = 0.05, decaySeconds: Double = 0.8) {
        for (index, freq) in freqs.enumerated() {
            add(Voice(kind: .sine(freq: freq),
                      amp: gain / Double(index + 1),
                      decayPerSample: decay(seconds: decaySeconds)))
        }
    }

    /// Short filtered-ish noise burst.
    func noiseBurst(gain: Double = 0.08, decaySeconds: Double = 0.08) {
        add(Voice(kind: .noise, amp: gain, decayPerSample: decay(seconds: decaySeconds)))
    }

    func coinFlick() { ping([2350, 3520, 4700], gain: 0.045, decaySeconds: 0.9) }

    func thud() {
        ping([130, 82], gain: 0.16, decaySeconds: 0.13)
        noiseBurst(gain: 0.05, decaySeconds: 0.05)
    }

    func revealChime() {
        ping([1568, 2093], gain: 0.045, decaySeconds: 0.55)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { [weak self] in
            self?.ping([2637], gain: 0.035, decaySeconds: 0.6)
        }
    }

    func cardWhoosh() { noiseBurst(gain: 0.10, decaySeconds: 0.22) }

    func cardSnap() {
        ping([880], gain: 0.08, decaySeconds: 0.06)
        noiseBurst(gain: 0.07, decaySeconds: 0.04)
    }

    func diceClack() {
        noiseBurst(gain: 0.08, decaySeconds: 0.045)
        ping([1500 + Double.random(in: 0...600)], gain: 0.035, decaySeconds: 0.07)
    }

    /// Match strike: a scratchy noise swell followed by a soft ignition pop.
    func matchStrike() {
        noiseBurst(gain: 0.09, decaySeconds: 0.16)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
            self?.ping([420, 640], gain: 0.05, decaySeconds: 0.18)
            self?.noiseBurst(gain: 0.04, decaySeconds: 0.30)
        }
    }

    /// A candle being snuffed: a short, breathy puff.
    func puff() {
        noiseBurst(gain: 0.07, decaySeconds: 0.18)
        ping([220], gain: 0.02, decaySeconds: 0.12)
    }

    // MARK: Whistle (sustained)

    private var whistleVoice: Voice?

    func startWhistle() {
        guard whistleVoice == nil, !isMuted else { return }
        ensureRunning()
        let voice = Voice(kind: .whistle(freq: 2280), amp: 0.10,
                          decayPerSample: decay(seconds: 0.12))
        lock.lock()
        voices.append(voice)
        whistleVoice = voice
        lock.unlock()
    }

    func stopWhistle() {
        lock.lock()
        whistleVoice?.released = true
        whistleVoice = nil
        lock.unlock()
    }
}
