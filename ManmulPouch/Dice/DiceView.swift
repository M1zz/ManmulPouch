import SwiftUI

// MARK: - Model

@MainActor
final class DiceModel: ObservableObject {
    struct Die: Identifiable {
        let id = UUID()
        var value: Int = 1
        var rolling = false
        var spin: Double = 0          // tumble angle for rotation3DEffect
        var axis: (x: CGFloat, y: CGFloat) = (1, 0)
        var jitter: CGSize = .zero
    }

    @Published var dice: [Die] = [Die()]
    @Published var isRolling = false

    private var timer: Timer?

    var total: Int { dice.reduce(0) { $0 + $1.value } }

    func setCount(_ count: Int) {
        guard !isRolling else { return }
        let clamped = max(1, min(6, count))
        if clamped > dice.count {
            dice.append(contentsOf: (dice.count..<clamped).map { _ in Die() })
        } else {
            dice = Array(dice.prefix(clamped))
        }
        Haptics.tap()
    }

    func roll() {
        guard !isRolling else { return }
        isRolling = true
        Haptics.thud()

        let start = Date()
        // Each die stops at a slightly different moment, like a real handful.
        let stopTimes: [TimeInterval] = dice.indices.map { 0.75 + Double($0) * 0.14 }

        for index in dice.indices {
            dice[index].rolling = true
        }

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick(start: start, stopTimes: stopTimes) }
        }
    }

    private func tick(start: Date, stopTimes: [TimeInterval]) {
        let elapsed = Date().timeIntervalSince(start)
        var allDone = true

        for index in dice.indices {
            guard dice[index].rolling else { continue }

            if elapsed >= stopTimes[index] {
                // The moment of truth — cryptographically random.
                dice[index].value = FateRandom.die()
                dice[index].rolling = false
                dice[index].spin = 0
                dice[index].jitter = .zero
                SoundEngine.shared.diceClack()
                Haptics.snap()
            } else {
                allDone = false
                dice[index].value = Int.random(in: 1...6)   // visual shuffle only
                dice[index].spin += Double.random(in: 55...120)
                dice[index].axis = (CGFloat.random(in: 0.4...1), CGFloat.random(in: -1...1))
                dice[index].jitter = CGSize(width: .random(in: -7...7),
                                            height: .random(in: -7...7))
                if Bool.random() { SoundEngine.shared.diceClack() }
            }
        }

        if allDone {
            timer?.invalidate()
            timer = nil
            isRolling = false
            Haptics.success()
        }
    }
}

// MARK: - View

struct DiceView: View {
    @StateObject private var model = DiceModel()

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 18)]

    var body: some View {
        ZStack {
            FeltBackground()

            VStack(spacing: 0) {
                header
                    .padding(.top, 8)

                countPicker
                    .padding(.top, 26)

                Spacer()

                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(model.dice) { die in
                        DieView(die: die)
                    }
                }
                .padding(.horizontal, 36)

                totalLabel
                    .padding(.top, 30)

                Spacer()

                rollButton
                    .padding(.bottom, 12)

                Text("기기를 흔들어도 굴러갑니다")
                    .font(.system(size: 11, weight: .light))
                    .tracking(2)
                    .foregroundStyle(Pouch.boneDim.opacity(0.7))
                    .padding(.bottom, 12)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
            model.roll()
        }
        .navigationTitle("주사위")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("만물 주머니 · 세 번째 물건")
                .font(.system(size: 11, weight: .light))
                .tracking(4)
                .foregroundStyle(Pouch.boneDim)
            Text("骰子")
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(Pouch.goldHi)
        }
    }

    private var countPicker: some View {
        HStack(spacing: 10) {
            ForEach(1...6, id: \.self) { count in
                Button {
                    model.setCount(count)
                } label: {
                    Text("\(count)")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background {
                            Circle().fill(model.dice.count == count
                                          ? Pouch.goldMid
                                          : Pouch.leather)
                            Circle().strokeBorder(
                                model.dice.count == count
                                    ? Pouch.goldHi
                                    : Pouch.goldLow.opacity(0.4),
                                lineWidth: 1
                            )
                        }
                        .foregroundStyle(model.dice.count == count
                                         ? Pouch.feltDeep
                                         : Pouch.boneDim)
                }
                .disabled(model.isRolling)
            }
        }
    }

    private var totalLabel: some View {
        VStack(spacing: 4) {
            Text("\(model.total)")
                .font(.system(size: 46, weight: .bold, design: .serif))
                .foregroundStyle(model.isRolling ? Pouch.boneDim : Pouch.goldHi)
                .contentTransition(.numericText())
                .animation(.snappy, value: model.total)
            Text(model.dice.count > 1 ? "합계" : "눈")
                .font(.system(size: 11, weight: .light))
                .tracking(4)
                .foregroundStyle(Pouch.boneDim)
        }
    }

    private var rollButton: some View {
        Button {
            model.roll()
        } label: {
            Text(model.isRolling ? "구르는 중…" : "굴리기")
                .font(.system(size: 17, weight: .bold))
                .tracking(4)
                .foregroundStyle(model.isRolling ? Pouch.boneDim : Pouch.feltDeep)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(model.isRolling
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
        .disabled(model.isRolling)
        .padding(.horizontal, 44)
    }
}

// MARK: - One die

struct DieView: View {
    let die: DiceModel.Die

    /// Front face side length and oblique extrusion depth of the cube.
    private let face: CGFloat = 74
    private let depth: CGFloat = 20

    var body: some View {
        ZStack(alignment: .topLeading) {
            topFace
            rightFace
            frontFace
        }
        .frame(width: face + depth, height: face + depth)
        .compositingGroup()
        .shadow(color: .black.opacity(0.45), radius: 8, y: 5)
        .rotation3DEffect(
            .degrees(die.spin),
            axis: (x: die.axis.x, y: die.axis.y, z: 0.3),
            perspective: 0.5
        )
        .offset(die.jitter)
        .animation(.easeOut(duration: 0.07), value: die.spin)
        .animation(.spring(duration: 0.25), value: die.rolling)
    }

    /// Values on the two partially visible faces: both adjacent to the front
    /// face (never its opposite, which sums to 7) and adjacent to each other.
    private var hiddenFaces: (top: Int, side: Int) {
        let value = die.value
        let adjacent = (1...6).filter { $0 != value && $0 != 7 - value }
        let top = adjacent[0]
        let side = adjacent.first { $0 != top && $0 != 7 - top } ?? adjacent[1]
        return (top, side)
    }

    private var frontFace: some View {
        ZStack {
            Rectangle()
                .fill(
                    LinearGradient(colors: [Pouch.bone,
                                            Color(red: 0.78, green: 0.74, blue: 0.63)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            Rectangle()
                .strokeBorder(.white.opacity(0.35), lineWidth: 1)
            PipsView(value: die.value, pipColor: Pouch.goldDark)
                .padding(13)
        }
        .frame(width: face, height: face)
        .offset(y: depth)
    }

    private var topFace: some View {
        let quad = Path { path in
            path.move(to: CGPoint(x: depth, y: 0))
            path.addLine(to: CGPoint(x: face + depth, y: 0))
            path.addLine(to: CGPoint(x: face, y: depth))
            path.addLine(to: CGPoint(x: 0, y: depth))
            path.closeSubpath()
        }
        return ZStack(alignment: .topLeading) {
            quad.fill(
                LinearGradient(colors: [Color(red: 0.96, green: 0.93, blue: 0.85),
                                        Pouch.bone],
                               startPoint: .top, endPoint: .bottom)
            )
            quad.stroke(.white.opacity(0.3), lineWidth: 1)
            PipsView(value: hiddenFaces.top, pipColor: Pouch.goldDark.opacity(0.75))
                .padding(13)
                .frame(width: face, height: face)
                .transformEffect(
                    CGAffineTransform(a: 1, b: 0,
                                      c: -depth / face, d: depth / face,
                                      tx: depth, ty: 0)
                )
        }
    }

    private var rightFace: some View {
        let quad = Path { path in
            path.move(to: CGPoint(x: face, y: depth))
            path.addLine(to: CGPoint(x: face + depth, y: 0))
            path.addLine(to: CGPoint(x: face + depth, y: face))
            path.addLine(to: CGPoint(x: face, y: face + depth))
            path.closeSubpath()
        }
        return ZStack(alignment: .topLeading) {
            quad.fill(
                LinearGradient(colors: [Color(red: 0.66, green: 0.62, blue: 0.51),
                                        Color(red: 0.54, green: 0.50, blue: 0.40)],
                               startPoint: .top, endPoint: .bottom)
            )
            quad.stroke(.white.opacity(0.18), lineWidth: 1)
            PipsView(value: hiddenFaces.side, pipColor: Pouch.goldDark.opacity(0.75))
                .padding(13)
                .frame(width: face, height: face)
                .transformEffect(
                    CGAffineTransform(a: depth / face, b: -depth / face,
                                      c: 0, d: 1,
                                      tx: face, ty: depth)
                )
        }
    }
}

// MARK: - Pips

struct PipsView: View {
    let value: Int
    var pipColor: Color = .black

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let pip = size * 0.22
            let offset = size * 0.30

            ZStack {
                ForEach(Array(positions.enumerated()), id: \.offset) { _, position in
                    Circle()
                        .fill(
                            RadialGradient(colors: [pipColor, pipColor.opacity(0.75)],
                                           center: .init(x: 0.35, y: 0.3),
                                           startRadius: 0, endRadius: pip / 2)
                        )
                        .frame(width: pip, height: pip)
                        .offset(x: position.x * offset, y: position.y * offset)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var positions: [CGPoint] {
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
}

#Preview {
    NavigationStack { DiceView() }
}
