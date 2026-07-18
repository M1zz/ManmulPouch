import SwiftUI
import AVFoundation

// MARK: - Blow detection (microphone)

/// Listens to the microphone and publishes a 0...1 "blow level".
/// Blowing into the mic produces a broadband rumble with high RMS,
/// which is all we need — no FFT required.
@MainActor
final class BlowDetector: ObservableObject {
    @Published var level: Double = 0
    @Published var authorized = false

    private let engine = AVAudioEngine()
    private var running = false
    private var hot = 0   // consecutive loud buffers

    var onBlow: (() -> Void)?

    func start() {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                self.authorized = granted
                guard granted else { return }
                self.beginListening()
            }
        }
    }

    private func beginListening() {
        guard !running else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord,
                                 options: [.defaultToSpeaker, .mixWithOthers])
        try? session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self, let data = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<count { sum += data[i] * data[i] }
            let rms = sqrt(sum / Float(max(1, count)))
            Task { @MainActor in self.process(rms: Double(rms)) }
        }

        do {
            try engine.start()
            running = true
        } catch {
            running = false
        }
    }

    private func process(rms: Double) {
        let normalized = min(1, rms * 6)
        // Smooth attack, quicker release
        level = level * 0.6 + normalized * 0.4

        if level > 0.5 {
            hot += 1
            if hot >= 3 {
                hot = 0
                onBlow?()
            }
        } else {
            hot = 0
        }
    }

    func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
        level = 0
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
    }
}

// MARK: - Model

@MainActor
final class CandleModel: ObservableObject {
    struct Candle: Identifiable {
        let id = UUID()
        var lit = false
        var heightFactor: Double = 1.0   // wax melts down to 0.55 while lit
        var smoking = false
    }

    @Published var candles: [Candle] = [Candle()]
    @Published var wishGranted = false

    private var meltTimer: Timer?

    var anyLit: Bool { candles.contains { $0.lit } }

    func setCount(_ count: Int) {
        let clamped = max(1, min(5, count))
        if clamped > candles.count {
            candles.append(contentsOf: (candles.count..<clamped).map { _ in Candle() })
        } else {
            candles = Array(candles.prefix(clamped))
        }
        wishGranted = false
        Haptics.tap()
    }

    func light(_ id: Candle.ID) {
        guard let index = candles.firstIndex(where: { $0.id == id }),
              !candles[index].lit else { return }
        candles[index].lit = true
        candles[index].smoking = false
        wishGranted = false
        SoundEngine.shared.matchStrike()
        Haptics.click(0.8)
        startMelting()
    }

    func lightAll() {
        for index in candles.indices where !candles[index].lit {
            let delay = Double(index) * 0.18
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                self.candles[index].lit = true
                self.candles[index].smoking = false
                SoundEngine.shared.matchStrike()
                Haptics.click(0.8)
            }
        }
        wishGranted = false
        startMelting()
    }

    func extinguish(_ id: Candle.ID, byBreath: Bool) {
        guard let index = candles.firstIndex(where: { $0.id == id }),
              candles[index].lit else { return }
        snuff(index: index, byBreath: byBreath)
    }

    /// A breath puts out every flame, slightly staggered like a real cake.
    func blowAllOut() {
        let litIndices = candles.indices.filter { candles[$0].lit }
        guard !litIndices.isEmpty else { return }
        for (order, index) in litIndices.shuffled().enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(order) * 0.09) { [weak self] in
                self?.snuff(index: index, byBreath: true)
            }
        }
    }

    private func snuff(index: Int, byBreath: Bool) {
        guard candles.indices.contains(index), candles[index].lit else { return }
        candles[index].lit = false
        candles[index].smoking = true
        SoundEngine.shared.puff()
        Haptics.tap()

        let id = candles[index].id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
            guard let self,
                  let i = self.candles.firstIndex(where: { $0.id == id }) else { return }
            self.candles[i].smoking = false
        }

        if byBreath && !anyLit {
            wishGranted = true
            Haptics.success()
        }
        if !anyLit { stopMelting() }
    }

    // MARK: Melting wax

    private func startMelting() {
        guard meltTimer == nil else { return }
        meltTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.melt() }
        }
    }

    private func stopMelting() {
        meltTimer?.invalidate()
        meltTimer = nil
    }

    private func melt() {
        for index in candles.indices where candles[index].lit {
            candles[index].heightFactor = max(0.55, candles[index].heightFactor - 0.012)
        }
        if !anyLit { stopMelting() }
    }
}

// MARK: - View

struct CandleView: View {
    @StateObject private var model = CandleModel()
    @StateObject private var blow = BlowDetector()

    var body: some View {
        ZStack {
            FeltBackground()

            // Warm candlelight over the whole room
            RadialGradient(
                colors: [Pouch.goldMid.opacity(model.anyLit ? 0.20 : 0),
                         .clear],
                center: .init(x: 0.5, y: 0.42),
                startRadius: 20, endRadius: 420
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.6), value: model.anyLit)

            VStack(spacing: 0) {
                header
                    .padding(.top, 8)

                countPicker
                    .padding(.top, 22)

                Spacer()

                cakeScene

                Spacer()

                wishBanner

                hintText
                    .padding(.bottom, 16)

                controls
                    .padding(.bottom, 20)
            }
        }
        .onAppear { blow.onBlow = { model.blowAllOut() }; blow.start() }
        .onDisappear { blow.stop() }
        .navigationTitle("생일초")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    // MARK: Pieces

    private var header: some View {
        VStack(spacing: 6) {
            Text("만물 주머니 · 네 번째 물건")
                .font(.system(size: 11, weight: .light))
                .tracking(4)
                .foregroundStyle(Pouch.boneDim)
            Text("燭")
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(Pouch.goldHi)
        }
    }

    private var countPicker: some View {
        HStack(spacing: 10) {
            ForEach(1...5, id: \.self) { count in
                Button {
                    model.setCount(count)
                } label: {
                    Text("\(count)")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background {
                            Circle().fill(model.candles.count == count
                                          ? Pouch.goldMid : Pouch.leather)
                            Circle().strokeBorder(
                                model.candles.count == count
                                    ? Pouch.goldHi : Pouch.goldLow.opacity(0.4),
                                lineWidth: 1
                            )
                        }
                        .foregroundStyle(model.candles.count == count
                                         ? Pouch.feltDeep : Pouch.boneDim)
                }
            }
        }
    }

    private var cakeScene: some View {
        VStack(spacing: -2) {
            HStack(alignment: .bottom, spacing: 26) {
                ForEach(model.candles) { candle in
                    SingleCandleView(candle: candle, blowLevel: blow.level)
                        .onTapGesture {
                            if candle.lit {
                                model.extinguish(candle.id, byBreath: false)
                            } else {
                                model.light(candle.id)
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 24)
                                .onEnded { value in
                                    if abs(value.velocity.width) > 450 {
                                        model.extinguish(candle.id, byBreath: false)
                                    }
                                }
                        )
                }
            }
            .padding(.bottom, 6)
            .zIndex(1)

            CakeView()
        }
    }

    private var wishBanner: some View {
        Group {
            if model.wishGranted {
                VStack(spacing: 6) {
                    Text("후 ———")
                        .font(.system(size: 15, weight: .light))
                        .tracking(8)
                        .foregroundStyle(Pouch.boneDim)
                    Text("소원이 이루어지길")
                        .font(.system(size: 26, weight: .bold, design: .serif))
                        .tracking(6)
                        .foregroundStyle(Pouch.goldHi)
                        .shadow(color: Pouch.goldMid.opacity(0.4), radius: 18)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(height: 70)
        .animation(.easeOut(duration: 0.5), value: model.wishGranted)
    }

    private var hintText: some View {
        Group {
            if model.anyLit {
                if blow.authorized {
                    Label("마이크를 향해 후— 불어보세요", systemImage: "wind")
                        .foregroundStyle(blow.level > 0.25 ? Pouch.goldHi : Pouch.boneDim)
                } else {
                    Text("촛불을 옆으로 쓸면 꺼집니다")
                        .foregroundStyle(Pouch.boneDim)
                }
            } else {
                Text("초를 탭해서 불을 붙이세요")
                    .foregroundStyle(Pouch.boneDim)
            }
        }
        .font(.system(size: 13, weight: .light))
        .tracking(2)
        .animation(.easeInOut(duration: 0.2), value: model.anyLit)
    }

    private var controls: some View {
        Button {
            model.lightAll()
        } label: {
            Label("성냥으로 모두 켜기", systemImage: "flame")
                .font(.system(size: 15, weight: .bold))
                .tracking(2)
                .foregroundStyle(model.anyLit ? Pouch.boneDim : Pouch.feltDeep)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(model.anyLit
                              ? AnyShapeStyle(Pouch.leather)
                              : AnyShapeStyle(
                                  LinearGradient(colors: [Pouch.goldHi, Pouch.goldMid],
                                                 startPoint: .top, endPoint: .bottom)))
                    RoundedRectangle(cornerRadius: 11)
                        .strokeBorder(Pouch.goldDark.opacity(0.35),
                                      style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
                        .padding(3)
                }
        }
        .disabled(model.candles.allSatisfy(\.lit))
        .padding(.horizontal, 44)
    }
}

// MARK: - One candle

struct SingleCandleView: View {
    let candle: CandleModel.Candle
    let blowLevel: Double

    private let bodyWidth: CGFloat = 22
    private let fullHeight: CGFloat = 92

    var body: some View {
        let height = fullHeight * candle.heightFactor

        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                if candle.smoking {
                    SmokeView()
                        .offset(y: -26)
                }
                if candle.lit {
                    FlameView(blowLevel: blowLevel)
                        .frame(width: 42, height: 62)
                        .offset(y: 6)
                        .transition(.scale(scale: 0.2, anchor: .bottom)
                            .combined(with: .opacity))
                }
            }
            .frame(height: 62)
            .animation(.spring(duration: 0.3), value: candle.lit)

            // Wick
            Capsule()
                .fill(Color.black.opacity(0.85))
                .frame(width: 2.5, height: 8)

            // Spiral wax body
            CandleBodyView(width: bodyWidth, height: height)
        }
        .contentShape(Rectangle().inset(by: -8))
    }
}

struct CandleBodyView: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(colors: [Pouch.bone,
                                            Color(red: 0.82, green: 0.75, blue: 0.62)],
                                   startPoint: .leading, endPoint: .trailing)
                )
            // Spiral stripes
            GeometryReader { proxy in
                let h = proxy.size.height
                ForEach(0..<Int(h / 14) + 2, id: \.self) { index in
                    Rectangle()
                        .fill(Pouch.goldMid.opacity(0.85))
                        .frame(width: proxy.size.width * 2.2, height: 5)
                        .rotationEffect(.degrees(-28))
                        .offset(x: -proxy.size.width * 0.6,
                                y: CGFloat(index) * 14 - 6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))

            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(.black.opacity(0.15), lineWidth: 0.8)
        }
        .frame(width: width, height: height)
        .animation(.linear(duration: 1), value: height)
    }
}

// MARK: - Flame

struct FlameView: View {
    let blowLevel: Double

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let wind = blowLevel * 14
            let sway = sin(t * 7.3) * 1.8 + sin(t * 13.1) * 1.1
                     + sin(t * 23.7) * 0.6 * (1 + blowLevel * 3)
            let lean = wind * (0.7 + 0.3 * sin(t * 19))
            let stretch = 1 + 0.06 * sin(t * 11.4) - blowLevel * 0.28
            let flickerOpacity = 0.92 + 0.08 * sin(t * 17.2)

            ZStack {
                // Glow
                Circle()
                    .fill(
                        RadialGradient(colors: [Color(red: 1, green: 0.72, blue: 0.25).opacity(0.55),
                                                .clear],
                                       center: .center, startRadius: 2, endRadius: 42)
                    )
                    .frame(width: 84, height: 84)
                    .offset(y: -6)
                    .blendMode(.screen)

                // Outer flame
                FlameShape()
                    .fill(
                        LinearGradient(colors: [Color(red: 1.0, green: 0.45, blue: 0.08),
                                                Color(red: 1.0, green: 0.72, blue: 0.15)],
                                       startPoint: .bottom, endPoint: .top)
                    )
                    .frame(width: 26, height: 44)
                    .blur(radius: 0.6)

                // Inner flame
                FlameShape()
                    .fill(
                        LinearGradient(colors: [Color(red: 1.0, green: 0.85, blue: 0.35),
                                                Color(red: 1.0, green: 0.97, blue: 0.75)],
                                       startPoint: .bottom, endPoint: .top)
                    )
                    .frame(width: 14, height: 26)
                    .offset(y: 6)

                // Blue base
                Ellipse()
                    .fill(Color(red: 0.35, green: 0.55, blue: 1.0).opacity(0.7))
                    .frame(width: 10, height: 7)
                    .offset(y: 18)
                    .blur(radius: 1.5)
            }
            .scaleEffect(x: 1, y: max(0.5, stretch), anchor: .bottom)
            .rotationEffect(.degrees(sway + lean), anchor: .bottom)
            .offset(x: sway * 0.6)
            .opacity(flickerOpacity)
        }
    }
}

struct FlameShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w / 2, y: 0))                       // tip
        path.addCurve(to: CGPoint(x: w / 2, y: h),                   // right side down
                      control1: CGPoint(x: w * 1.05, y: h * 0.42),
                      control2: CGPoint(x: w * 0.92, y: h * 0.96))
        path.addCurve(to: CGPoint(x: w / 2, y: 0),                   // left side up
                      control1: CGPoint(x: w * 0.08, y: h * 0.96),
                      control2: CGPoint(x: -w * 0.05, y: h * 0.42))
        path.closeSubpath()
        return path
    }
}

// MARK: - Smoke

struct SmokeView: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    let phase = t * 0.9 + Double(index) * 0.7
                    let cycle = phase.truncatingRemainder(dividingBy: 2.2) / 2.2
                    Circle()
                        .fill(Color.gray.opacity(0.35 * (1 - cycle)))
                        .frame(width: 8 + cycle * 16)
                        .offset(
                            x: sin(phase * 2.4) * 8 * cycle,
                            y: -cycle * 70
                        )
                        .blur(radius: 2 + cycle * 4)
                }
            }
        }
        .frame(width: 50, height: 90)
        .allowsHitTesting(false)
    }
}

// MARK: - Cake

struct CakeView: View {
    var body: some View {
        ZStack(alignment: .top) {
            // Cake body
            UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10)
                .fill(
                    LinearGradient(colors: [Color(red: 0.55, green: 0.35, blue: 0.22),
                                            Color(red: 0.42, green: 0.25, blue: 0.15)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 250, height: 72)
                .padding(.top, 12)

            // Frosting with dripping scallops
            VStack(spacing: -8) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Pouch.bone)
                    .frame(width: 258, height: 22)
                HStack(spacing: 9) {
                    ForEach(0..<12, id: \.self) { index in
                        Capsule()
                            .fill(Pouch.bone)
                            .frame(width: 13,
                                   height: index % 3 == 0 ? 26 : (index % 3 == 1 ? 18 : 22))
                    }
                }
                .frame(width: 250)
                .clipped()
            }

            // Plate
            Ellipse()
                .fill(
                    LinearGradient(colors: [Pouch.goldMid, Pouch.goldLow],
                                   startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 300, height: 22)
                .offset(y: 76)
                .shadow(color: .black.opacity(0.5), radius: 10, y: 6)
        }
        .frame(height: 100)
    }
}

#Preview {
    NavigationStack { CandleView() }
}
