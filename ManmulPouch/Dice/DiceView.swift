import SwiftUI

// MARK: - View

struct DiceView: View {
    @StateObject private var scene = DiceScene()

    var body: some View {
        ZStack {
            FeltBackground()

            VStack(spacing: 0) {
                header
                    .padding(.top, 8)

                countPicker
                    .padding(.top, 22)

                Spacer(minLength: 0)

                DiceTrayView(scene: scene)
                    .frame(maxWidth: .infinity)
                    .frame(height: 340)
                    .contentShape(Rectangle())
                    .onTapGesture { scene.roll() }

                totalLabel
                    .padding(.top, 4)

                Spacer(minLength: 0)

                rollButton
                    .padding(.bottom, 12)

                Text("기기를 흔들거나 판을 탭해도 굴러갑니다")
                    .font(.system(size: 11, weight: .light))
                    .tracking(2)
                    .foregroundStyle(Pouch.boneDim.opacity(0.7))
                    .padding(.bottom, 12)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
            scene.roll()
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
                    scene.setCount(count)
                } label: {
                    Text("\(count)")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background {
                            Circle().fill(scene.count == count
                                          ? Pouch.goldMid
                                          : Pouch.leather)
                            Circle().strokeBorder(
                                scene.count == count
                                    ? Pouch.goldHi
                                    : Pouch.goldLow.opacity(0.4),
                                lineWidth: 1
                            )
                        }
                        .foregroundStyle(scene.count == count
                                         ? Pouch.feltDeep
                                         : Pouch.boneDim)
                }
                .disabled(scene.isRolling)
            }
        }
    }

    private var totalLabel: some View {
        VStack(spacing: 4) {
            Text("\(scene.total)")
                .font(.system(size: 46, weight: .bold, design: .serif))
                .foregroundStyle(scene.isRolling ? Pouch.boneDim : Pouch.goldHi)
                .contentTransition(.numericText())
                .animation(.snappy, value: scene.total)
            Text(scene.count > 1 ? "합계" : "눈")
                .font(.system(size: 11, weight: .light))
                .tracking(4)
                .foregroundStyle(Pouch.boneDim)
        }
    }

    private var rollButton: some View {
        Button {
            scene.roll()
        } label: {
            Text(scene.isRolling ? "구르는 중…" : "굴리기")
                .font(.system(size: 17, weight: .bold))
                .tracking(4)
                .foregroundStyle(scene.isRolling ? Pouch.boneDim : Pouch.feltDeep)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(scene.isRolling
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
        .disabled(scene.isRolling)
        .padding(.horizontal, 44)
    }
}

// MARK: - Pips (used by the home screen thumbnail)

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
