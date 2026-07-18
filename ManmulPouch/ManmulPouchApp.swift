import SwiftUI

@main
struct ManmulPouchApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Home (the pouch)

struct HomeView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                FeltBackground()

                VStack(spacing: 0) {
                    header
                        .padding(.top, 18)
                        .padding(.bottom, 34)

                    VStack(spacing: 16) {
                        NavigationLink { CoinFlipView() } label: {
                            ItemPlaque(
                                number: "一",
                                title: "황금 동전",
                                subtitle: "운에 맡기고 싶을 때 · 앞 아니면 뒤",
                                icon: { MiniCoinIcon() }
                            )
                        }
                        NavigationLink { RefereeView() } label: {
                            ItemPlaque(
                                number: "二",
                                title: "심판 세트",
                                subtitle: "판정이 필요할 때 · 호루라기와 카드",
                                icon: { MiniRefereeIcon() }
                            )
                        }
                        NavigationLink { DiceView() } label: {
                            ItemPlaque(
                                number: "三",
                                title: "주사위",
                                subtitle: "숫자가 필요할 때 · 하나부터 여섯",
                                icon: { MiniDiceIcon() }
                            )
                        }
                        NavigationLink { CandleView() } label: {
                            ItemPlaque(
                                number: "四",
                                title: "생일초",
                                subtitle: "축하가 필요할 때 · 불어서 끄는 촛불",
                                icon: { MiniCandleIcon() }
                            )
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer()

                    Text("운이 걸린 결과는 모두 암호학적 난수로 결정됩니다")
                        .font(.system(size: 11, weight: .light))
                        .tracking(2)
                        .foregroundStyle(Pouch.boneDim.opacity(0.7))
                        .padding(.bottom, 24)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(Pouch.goldMid)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text("완벽한 소품 상점")
                .font(.system(size: 11, weight: .light))
                .tracking(6)
                .foregroundStyle(Pouch.boneDim)
            Text("만물 주머니")
                .font(.system(size: 34, weight: .bold))
                .tracking(8)
                .foregroundStyle(Pouch.bone)
                .shadow(color: .black.opacity(0.6), radius: 0, y: 1)
            Rectangle()
                .fill(Pouch.goldMid)
                .frame(width: 44, height: 1)
                .padding(.top, 4)
        }
    }
}

// MARK: - Leather plaque row

struct ItemPlaque<Icon: View>: View {
    let number: String
    let title: String
    let subtitle: String
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Pouch.feltDeep, .black.opacity(0.85)],
                            center: .center, startRadius: 2, endRadius: 40
                        )
                    )
                Circle()
                    .strokeBorder(Pouch.goldLow, lineWidth: 1)
                icon()
                    .frame(width: 40, height: 40)
            }
            .frame(width: 62, height: 62)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(number)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Pouch.goldMid)
                    Text(title)
                        .font(.system(size: 19, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(Pouch.bone)
                }
                Text(subtitle)
                    .font(.system(size: 12, weight: .light))
                    .tracking(1)
                    .foregroundStyle(Pouch.boneDim)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Pouch.goldLow)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(
                    LinearGradient(
                        colors: [Pouch.leather, Pouch.leather.opacity(0.75)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.5), radius: 10, y: 5)
            // Stitched border, like a leather pouch seam
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    Pouch.goldLow.opacity(0.55),
                    style: StrokeStyle(lineWidth: 1.2, dash: [4, 5])
                )
                .padding(5)
        }
    }
}

// MARK: - Mini icons

struct MiniCoinIcon: View {
    var body: some View {
        ZStack {
            Circle().fill(
                RadialGradient(colors: [Pouch.goldHi, Pouch.goldMid, Pouch.goldLow],
                               center: .init(x: 0.38, y: 0.32), startRadius: 1, endRadius: 26)
            )
            Circle().strokeBorder(Pouch.goldHi.opacity(0.8), lineWidth: 1).padding(3)
            Text("陽")
                .font(.system(size: 16, weight: .bold, design: .serif))
                .foregroundStyle(Pouch.goldDark)
        }
    }
}

struct MiniRefereeIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color(red: 0.85, green: 0.13, blue: 0.13))
                .frame(width: 15, height: 21)
                .rotationEffect(.degrees(12))
                .offset(x: 8, y: -2)
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color(red: 0.98, green: 0.82, blue: 0.1))
                .frame(width: 15, height: 21)
                .rotationEffect(.degrees(-8))
                .offset(x: -1, y: 1)
            WhistleShape()
                .fill(
                    LinearGradient(colors: [Pouch.goldHi, Pouch.goldLow],
                                   startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 24, height: 16)
                .rotationEffect(.degrees(-16))
                .offset(x: -9, y: 9)
        }
    }
}

struct MiniDiceIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(
                    LinearGradient(colors: [Pouch.bone, Color(red: 0.78, green: 0.74, blue: 0.64)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            PipsView(value: 5, pipColor: Pouch.goldDark)
                .padding(6)
        }
        .frame(width: 32, height: 32)
        .rotationEffect(.degrees(-8))
    }
}

struct MiniCandleIcon: View {
    var body: some View {
        VStack(spacing: 0) {
            FlameShape()
                .fill(
                    LinearGradient(colors: [Color(red: 1.0, green: 0.85, blue: 0.35),
                                            Color(red: 1.0, green: 0.5, blue: 0.1)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 11, height: 16)
            Capsule()
                .fill(.black.opacity(0.8))
                .frame(width: 1.5, height: 3)
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(colors: [Pouch.bone,
                                            Color(red: 0.8, green: 0.73, blue: 0.6)],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .overlay {
                    Rectangle()
                        .fill(Pouch.goldMid.opacity(0.85))
                        .frame(height: 2.5)
                        .rotationEffect(.degrees(-28))
                }
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .frame(width: 8, height: 18)
        }
    }
}

#Preview {
    HomeView()
}
