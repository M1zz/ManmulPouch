import SwiftUI

struct CoinFlipView: View {
    @StateObject private var model = CoinModel()
    @AppStorage("coin.heads") private var headsCount = 0
    @AppStorage("coin.tails") private var tailsCount = 0
    @State private var handClosed = false
    @State private var tallied = false

    private let coinSize: CGFloat = 210

    var body: some View {
        ZStack {
            FeltBackground()

            VStack(spacing: 0) {
                header
                Spacer()
            }

            resultBanner

            coinStage

            VStack {
                Spacer()
                hintText
                    .padding(.bottom, 18)
                tally
                    .padding(.bottom, 12)
            }

            HandOverlay(closed: handClosed)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .gesture(mainGesture)
        .onChange(of: model.phase) { _, phase in
            switch phase {
            case .held:
                withAnimation(.spring(duration: 0.22)) { handClosed = true }
            case .settle, .idle:
                withAnimation(.spring(duration: 0.3)) { handClosed = false }
            case .reveal:
                recordOutcome()
            case .air:
                tallied = false
            }
        }
        .navigationTitle("황금 동전")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    // MARK: Pieces

    private var header: some View {
        VStack(spacing: 6) {
            Text("만물 주머니 · 첫 번째 물건")
                .font(.system(size: 11, weight: .light))
                .tracking(4)
                .foregroundStyle(Pouch.boneDim)
            Text("金貨")
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(Pouch.goldHi)
        }
        .padding(.top, 8)
    }

    private var coinStage: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height * 0.60)
            ZStack {
                // Shadow on the felt
                Ellipse()
                    .fill(
                        RadialGradient(colors: [.black.opacity(0.55), .clear],
                                       center: .center, startRadius: 4,
                                       endRadius: coinSize * 0.55)
                    )
                    .frame(width: coinSize, height: coinSize * 0.28)
                    .scaleEffect(shadowScale)
                    .opacity(shadowOpacity)
                    .position(center)

                CoinView(rotation: model.rotation, spinSpeed: model.spinSpeed)
                    .frame(width: coinSize, height: coinSize)
                    .scaleEffect(model.scale)
                    .position(x: center.x, y: center.y - model.altitude)
            }
        }
    }

    private var shadowScale: CGFloat {
        CGFloat(0.45 + 0.55 * max(0, 1 - model.altitude / 480))
    }

    private var shadowOpacity: Double {
        0.25 + 0.75 * max(0, 1 - model.altitude / 480)
    }

    private var hintText: some View {
        Group {
            switch model.phase {
            case .idle:
                Label("동전을 위로 튕기세요", systemImage: "arrow.up")
                    .foregroundStyle(Pouch.boneDim)
            case .air:
                Text("손바닥으로 화면을 덮어 잡으세요")
                    .foregroundStyle(Pouch.goldHi)
            case .held:
                Text("")
            case .settle:
                Text("")
            case .reveal:
                Label("다시 튕기세요", systemImage: "arrow.up")
                    .foregroundStyle(Pouch.boneDim)
            }
        }
        .font(.system(size: 15, weight: .light))
        .tracking(2)
        .animation(.easeInOut(duration: 0.2), value: model.phase)
    }

    private var tally: some View {
        HStack(spacing: 6) {
            Text("앞")
            Text("\(headsCount)").foregroundStyle(Pouch.goldMid).fontWeight(.medium)
            Text("·")
            Text("뒤")
            Text("\(tailsCount)").foregroundStyle(Pouch.goldMid).fontWeight(.medium)
        }
        .font(.system(size: 12, weight: .light))
        .tracking(3)
        .foregroundStyle(Pouch.boneDim)
    }

    private var resultBanner: some View {
        VStack(spacing: 8) {
            if model.phase == .reveal, let outcome = model.outcome {
                Text(outcome ? "앞面" : "뒤面")
                    .font(.system(size: 58, weight: .bold, design: .serif))
                    .tracking(10)
                    .foregroundStyle(Pouch.goldHi)
                    .shadow(color: Pouch.goldMid.opacity(0.4), radius: 22)
                Text(model.revealSource)
                    .font(.system(size: 12, weight: .light))
                    .tracking(4)
                    .foregroundStyle(Pouch.boneDim)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 90)
        .transition(.opacity)
        .animation(.easeOut(duration: 0.4), value: model.phase)
    }

    // MARK: Input

    @State private var caughtThisTouch = false

    private var mainGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                // A touch-down while airborne is the palm slap.
                if model.phase == .air {
                    model.catchNow()
                    caughtThisTouch = true
                }
            }
            .onEnded { value in
                // Lifting the catching hand must not open it —
                // that takes a separate, deliberate tap.
                if caughtThisTouch {
                    caughtThisTouch = false
                    return
                }
                switch model.phase {
                case .held:
                    model.openHand()
                case .idle, .reveal:
                    let upward = -value.velocity.height
                    if upward > 550 {
                        model.acknowledgeReveal()
                        model.flick(velocity: upward)
                    } else {
                        model.acknowledgeReveal()
                    }
                default:
                    break
                }
            }
    }

    private func recordOutcome() {
        guard !tallied, let outcome = model.outcome else { return }
        tallied = true
        if outcome { headsCount += 1 } else { tailsCount += 1 }
    }
}

// MARK: - 3D coin

struct CoinView: View {
    let rotation: Double      // degrees around X
    let spinSpeed: Double     // deg/s

    /// Physical thickness of the coin, in points.
    private let thickness: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            let radians = rotation.wrappedDegrees * .pi / 180
            let facing = cos(radians)          // +1 front, -1 back
            let sine = sin(radians)
            let squash = max(CGFloat(abs(facing)), 0.035)
            let isFront = facing >= 0
            // Screen-space vertical offsets of the visible (near) and hidden (far) faces
            let nearY = -(thickness / 2) * CGFloat(sine) * (isFront ? 1 : -1)
            let farY = -nearY
            let slices = 10

            ZStack {
                // Extruded edge: stacked slices from the far face up to the near face
                ForEach(0..<slices, id: \.self) { index in
                    let t = CGFloat(index) / CGFloat(slices - 1)
                    Ellipse()
                        .fill(
                            LinearGradient(colors: [Pouch.goldLow, Pouch.goldDark],
                                           startPoint: .top, endPoint: .bottom)
                        )
                        .frame(width: diameter, height: max(diameter * squash, 2))
                        .offset(y: farY + (nearY - farY) * t)
                }

                // Milled rim highlight along the near edge
                Ellipse()
                    .strokeBorder(Pouch.goldHi.opacity(0.55), lineWidth: 1.2)
                    .frame(width: diameter, height: max(diameter * squash, 2))
                    .offset(y: nearY)

                CoinFaceView(isFront: isFront)
                    .frame(width: diameter, height: diameter)
                    .scaleEffect(x: 1, y: squash)
                    .offset(y: nearY)
                    .brightness(0.12 * facing)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .blur(radius: min(2.5, spinSpeed / 1400))
        .compositingGroup()
    }
}

struct CoinFaceView: View {
    let isFront: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                // Base metal
                Circle()
                    .fill(
                        RadialGradient(
                            colors: isFront
                                ? [Pouch.goldHi, Pouch.goldMid, Pouch.goldLow]
                                : [Color(red: 0.94, green: 0.82, blue: 0.47),
                                   Color(red: 0.75, green: 0.56, blue: 0.18),
                                   Pouch.goldLow],
                            center: .init(x: 0.38, y: 0.32),
                            startRadius: size * 0.05,
                            endRadius: size * 0.75
                        )
                    )

                // Outer ring
                Circle()
                    .strokeBorder(Pouch.goldHi.opacity(0.8), lineWidth: 1.5)
                    .padding(size * 0.035)

                // Beaded rim
                ForEach(0..<12, id: \.self) { index in
                    Circle()
                        .fill(Pouch.goldHi.opacity(0.85))
                        .frame(width: size * 0.022)
                        .offset(y: -size * 0.455)
                        .rotationEffect(.degrees(Double(index) * 30))
                }

                // Inner medallion
                Circle()
                    .fill(isFront
                          ? Color(red: 0.93, green: 0.77, blue: 0.38)
                          : Color(red: 0.73, green: 0.54, blue: 0.17))
                    .overlay(Circle().strokeBorder(Pouch.goldDark.opacity(0.7), lineWidth: 1.2))
                    .padding(size * 0.21)

                if isFront {
                    SunEmblem(size: size)
                } else {
                    MoonEmblem(size: size)
                }

                // Sheen
                Circle()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.35), location: 0),
                                .init(color: .clear, location: 0.45),
                                .init(color: .black.opacity(0.18), location: 1)
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.overlay)
            }
        }
    }
}

private struct SunEmblem: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                Capsule()
                    .fill(Pouch.goldDark)
                    .frame(width: size * 0.02, height: size * 0.055)
                    .offset(y: -size * 0.20)
                    .rotationEffect(.degrees(Double(index) * 45))
            }
            Circle()
                .fill(Pouch.goldHi)
                .overlay(Circle().strokeBorder(Pouch.goldDark, lineWidth: size * 0.014))
                .frame(width: size * 0.27)
            Text("陽")
                .font(.system(size: size * 0.15, weight: .bold, design: .serif))
                .foregroundStyle(Pouch.goldDark)
        }
    }
}

private struct MoonEmblem: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            CrescentShape()
                .fill(Pouch.goldHi)
                .overlay(CrescentShape().stroke(Pouch.goldDark, lineWidth: size * 0.012))
                .frame(width: size * 0.34, height: size * 0.34)
                .offset(x: -size * 0.03)
            Image(systemName: "star.fill")
                .font(.system(size: size * 0.075))
                .foregroundStyle(Pouch.goldHi)
                .offset(x: size * 0.14, y: -size * 0.07)
            Text("陰")
                .font(.system(size: size * 0.09, weight: .bold, design: .serif))
                .foregroundStyle(Pouch.goldDark)
                .offset(y: size * 0.235)
        }
    }
}

struct CrescentShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.addArc(center: center, radius: r,
                    startAngle: .degrees(-60), endAngle: .degrees(240), clockwise: false)
        let innerCenter = CGPoint(x: center.x + r * 0.42, y: center.y)
        path.addArc(center: innerCenter, radius: r * 0.82,
                    startAngle: .degrees(240), endAngle: .degrees(-60), clockwise: true)
        path.closeSubpath()
        return path
    }
}

// MARK: - Hand overlay (the catch)

struct HandOverlay: View {
    let closed: Bool

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            VStack(spacing: 0) {
                // Fingertips
                HStack(alignment: .bottom, spacing: proxy.size.width * 0.02) {
                    finger(height: 62)
                    finger(height: 78)
                    finger(height: 74)
                    finger(height: 56)
                }
                .padding(.horizontal, proxy.size.width * 0.06)

                // Palm
                Rectangle()
                    .fill(
                        LinearGradient(colors: [Color(red: 0.17, green: 0.11, blue: 0.08),
                                                Color(red: 0.05, green: 0.03, blue: 0.02)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .overlay(alignment: .top) {
                        VStack(spacing: 14) {
                            Text("손 안에 있다")
                                .font(.system(size: 22, weight: .bold, design: .serif))
                                .tracking(6)
                                .foregroundStyle(Pouch.bone)
                            Text("탭해서 손을 펴세요")
                                .font(.system(size: 12, weight: .light))
                                .tracking(3)
                                .foregroundStyle(Pouch.boneDim)
                        }
                        .padding(.top, height * 0.28)
                    }
            }
            .frame(height: height * 1.1)
            .offset(y: closed ? -height * 0.06 : height * 1.1)
            .shadow(color: .black.opacity(0.6), radius: 20, y: -8)
        }
        .ignoresSafeArea()
    }

    private func finger(height: CGFloat) -> some View {
        UnevenRoundedRectangle(topLeadingRadius: 34, topTrailingRadius: 34)
            .fill(
                LinearGradient(colors: [Color(red: 0.20, green: 0.13, blue: 0.09),
                                        Color(red: 0.10, green: 0.06, blue: 0.04)],
                               startPoint: .top, endPoint: .bottom)
            )
            .frame(maxWidth: .infinity)
            .frame(height: height)
    }
}

#Preview {
    NavigationStack { CoinFlipView() }
}
