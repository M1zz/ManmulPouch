import SwiftUI

struct RefereeView: View {
    enum CardKind: String, Identifiable {
        case yellow, red
        var id: String { rawValue }

        var color: Color {
            switch self {
            case .yellow: Color(red: 0.98, green: 0.82, blue: 0.10)
            case .red:    Color(red: 0.85, green: 0.13, blue: 0.13)
            }
        }
        var title: String {
            switch self {
            case .yellow: "경고"
            case .red:    "퇴장"
            }
        }
        var subtitle: String {
            switch self {
            case .yellow: "CAUTION"
            case .red:    "SENDING OFF"
            }
        }
    }

    @State private var whistling = false
    @State private var wavePhase = false
    @State private var presentedCard: CardKind?
    @State private var yellowDragOffset: CGFloat = 0
    @State private var redDragOffset: CGFloat = 0
    @Namespace private var cardSpace
    @AppStorage("ref.yellow") private var yellowCount = 0
    @AppStorage("ref.red") private var redCount = 0

    @State private var hapticTimer: Timer?

    var body: some View {
        ZStack {
            FeltBackground()

            VStack(spacing: 0) {
                header
                    .padding(.top, 8)

                Spacer()

                whistleSection

                Spacer()

                Text(presentedCard == nil ? "카드를 위로 밀어 꺼내세요" : "")
                    .font(.system(size: 13, weight: .light))
                    .tracking(2)
                    .foregroundStyle(Pouch.boneDim)
                    .padding(.bottom, 14)

                cardPocket
                    .padding(.bottom, 8)

                tally
                    .padding(.bottom, 12)
            }

            if let card = presentedCard {
                presentedCardView(card)
            }
        }
        .navigationTitle("심판 세트")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 6) {
            Text("만물 주머니 · 두 번째 물건")
                .font(.system(size: 11, weight: .light))
                .tracking(4)
                .foregroundStyle(Pouch.boneDim)
            Text("審判")
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(Pouch.goldHi)
        }
    }

    // MARK: Whistle

    private var whistleSection: some View {
        ZStack {
            // Sound rings while blowing
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(Pouch.goldMid.opacity(whistling ? 0 : 0.5), lineWidth: 1.5)
                    .frame(width: 130, height: 130)
                    .scaleEffect(whistling ? 2.4 + Double(index) * 0.4 : 1)
                    .animation(
                        whistling
                            ? .easeOut(duration: 1.0)
                                .repeatForever(autoreverses: false)
                                .delay(Double(index) * 0.33)
                            : .default,
                        value: whistling
                    )
            }

            VStack(spacing: 20) {
                WhistleShape()
                    .fill(
                        LinearGradient(colors: [Pouch.goldHi, Pouch.goldMid, Pouch.goldLow],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .overlay(WhistleShape().stroke(Pouch.goldDark.opacity(0.6), lineWidth: 1))
                    .overlay {
                        // Air hole
                        Circle()
                            .fill(Pouch.goldDark.opacity(0.85))
                            .frame(width: 20, height: 20)
                            .offset(x: 12, y: 8)
                    }
                    .frame(width: 150, height: 100)
                    .rotationEffect(.degrees(-14))
                    .scaleEffect(whistling ? 0.94 : 1)
                    .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
                    .animation(.spring(duration: 0.15), value: whistling)

                Text(whistling ? "삑 ———" : "길게 눌러 부세요")
                    .font(.system(size: 14, weight: whistling ? .bold : .light))
                    .tracking(3)
                    .foregroundStyle(whistling ? Pouch.goldHi : Pouch.boneDim)
            }
        }
        .frame(height: 260)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in startWhistle() }
                .onEnded { _ in stopWhistle() }
        )
    }

    private func startWhistle() {
        guard !whistling else { return }
        whistling = true
        SoundEngine.shared.startWhistle()
        Haptics.thud()
        hapticTimer = Timer.scheduledTimer(withTimeInterval: 0.055, repeats: true) { _ in
            Task { @MainActor in Haptics.click(0.55) }
        }
    }

    private func stopWhistle() {
        whistling = false
        SoundEngine.shared.stopWhistle()
        hapticTimer?.invalidate()
        hapticTimer = nil
    }

    // MARK: Card pocket

    private var cardPocket: some View {
        HStack(spacing: 26) {
            pocketCard(.yellow, offset: $yellowDragOffset)
            pocketCard(.red, offset: $redDragOffset)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 34)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(Pouch.leather)
                .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Pouch.goldLow.opacity(0.5),
                              style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
                .padding(4)
        }
    }

    @ViewBuilder
    private func pocketCard(_ kind: CardKind, offset: Binding<CGFloat>) -> some View {
        if presentedCard != kind {
            cardFace(kind, corner: 7)
                .matchedGeometryEffect(id: kind.id, in: cardSpace)
                .frame(width: 74, height: 104)
                .rotationEffect(.degrees(kind == .yellow ? -3 : 3))
                .offset(y: offset.wrappedValue)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            offset.wrappedValue = min(0, value.translation.height)
                        }
                        .onEnded { value in
                            let pulled = value.translation.height < -70
                                || value.velocity.height < -600
                            offset.wrappedValue = 0
                            if pulled { present(kind) }
                        }
                )
        } else {
            Color.clear.frame(width: 74, height: 104)
        }
    }

    private func present(_ kind: CardKind) {
        SoundEngine.shared.cardWhoosh()
        Haptics.warning()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.74)) {
            presentedCard = kind
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            SoundEngine.shared.cardSnap()
            Haptics.snap()
        }
        switch kind {
        case .yellow: yellowCount += 1
        case .red:    redCount += 1
        }
    }

    // MARK: Raised card

    private func presentedCardView(_ kind: CardKind) -> some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(spacing: 26) {
                cardFace(kind, corner: 16)
                    .matchedGeometryEffect(id: kind.id, in: cardSpace)
                    .frame(width: 248, height: 368)
                    .rotationEffect(.degrees(-4))
                    .shadow(color: .black.opacity(0.6), radius: 26, y: 14)

                VStack(spacing: 8) {
                    Text(kind.title)
                        .font(.system(size: 34, weight: .bold, design: .serif))
                        .tracking(10)
                        .foregroundStyle(Pouch.bone)
                    Text(kind.subtitle)
                        .font(.system(size: 12, weight: .light))
                        .tracking(6)
                        .foregroundStyle(Pouch.boneDim)
                }

                Text("탭해서 집어넣기")
                    .font(.system(size: 12, weight: .light))
                    .tracking(3)
                    .foregroundStyle(Pouch.boneDim.opacity(0.8))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                presentedCard = nil
            }
        }
    }

    private func cardFace(_ kind: CardKind, corner: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: corner)
            .fill(
                LinearGradient(
                    colors: [kind.color, kind.color.opacity(0.82)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: corner)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 1)
            }
            .overlay(alignment: .bottomTrailing) {
                Text("만물 주머니")
                    .font(.system(size: 7, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(.black.opacity(0.3))
                    .padding(8)
            }
    }

    // MARK: Tally

    private var tally: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(CardKind.yellow.color)
                .frame(width: 8, height: 11)
            Text("\(yellowCount)").foregroundStyle(Pouch.goldMid).fontWeight(.medium)
            Text("·")
            RoundedRectangle(cornerRadius: 1.5)
                .fill(CardKind.red.color)
                .frame(width: 8, height: 11)
            Text("\(redCount)").foregroundStyle(Pouch.goldMid).fontWeight(.medium)
        }
        .font(.system(size: 12, weight: .light))
        .foregroundStyle(Pouch.boneDim)
    }
}

// MARK: - Whistle shape

struct WhistleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let bodyRadius = h * 0.42
        let bodyCenter = CGPoint(x: w * 0.62, y: h * 0.58)

        // Mouthpiece (rounded bar, top-left)
        let mouth = CGRect(x: 0, y: h * 0.08, width: w * 0.62, height: h * 0.30)
        path.addRoundedRect(in: mouth, cornerSize: CGSize(width: h * 0.12, height: h * 0.12))

        // Round chamber
        path.addArc(center: bodyCenter, radius: bodyRadius,
                    startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)

        return path
    }
}

#Preview {
    NavigationStack { RefereeView() }
}
