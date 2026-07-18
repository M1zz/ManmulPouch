# 만물 주머니 (ManmulPouch)

완벽한 소품들을 리얼한 애니메이션으로 구현한 iOS 앱.
운에 맡기고 싶은 사람들을 위한 도구 모음입니다.

## 담긴 물건

| # | 물건 | 인터랙션 |
|---|------|----------|
| 一 | 황금 동전 | 위로 플릭해서 튕기고, 공중에서 손바닥으로 화면을 덮어 잡고, 탭해서 손을 펴 확인. 못 잡으면 바닥에 통통 튀며 스스로 멈춤 |
| 二 | 심판 세트 | 호루라기를 길게 눌러 불기(합성음 + 연속 햅틱), 옐로/레드 카드를 위로 스와이프해 꺼내기 |
| 三 | 주사위 | 1~6개 선택, 굴리기 버튼 또는 기기 흔들기, 개별 정지 타이밍의 텀블링 후 합계 표시 |
| 四 | 생일초 | 초를 탭해서 점화(성냥 긋는 합성음), 마이크에 후— 불면 실제로 꺼짐. 촛농이 서서히 녹아 초가 짧아지고, 끄면 연기가 피어오름 |

## 실행 방법

1. Xcode 16 이상에서 `ManmulPouch.xcodeproj` 열기
2. 타깃 → Signing & Capabilities에서 본인 Team 선택
3. 필요하면 Bundle Identifier(`com.leeo.manmulpouch`) 변경
4. 실기기에서 실행 권장 — 햅틱과 흔들기 감지는 시뮬레이터에서 제한적
   (시뮬레이터 흔들기: Device > Shake)

iOS 17.0+, 외부 의존성 없음, 에셋 없음(사운드는 전부 코드 합성).
생일초의 '불어서 끄기'는 마이크 권한이 필요합니다(거부해도 스와이프로 끌 수 있음).

## 구조

```
ManmulPouch/
├── ManmulPouchApp.swift        # 엔트리 + 홈(주머니) 화면
├── Support/
│   ├── Theme.swift             # 팔레트, FateRandom, 햅틱, 흔들기 감지
│   └── SoundEngine.swift       # AVAudioSourceNode 가산 신디사이저
├── Coin/
│   ├── CoinModel.swift         # CADisplayLink 물리 + 상태 머신
│   └── CoinFlipView.swift      # 3D 동전, 플릭 제스처, 손 오버레이
├── Referee/
│   └── RefereeView.swift       # 호루라기 + 카드 (matchedGeometryEffect)
├── Dice/
│   └── DiceView.swift          # 주사위 모델 + 텀블링 뷰
└── Candle/
    └── CandleView.swift        # 불꽃/연기/촛농 + 마이크 입김 감지(BlowDetector)
```

## 설계 노트

**완벽한 랜덤** — 모든 결과는 `FateRandom`(`SystemRandomNumberGenerator`,
Apple 플랫폼에서 암호학적으로 안전한 `arc4random_buf` 기반)으로 결정됩니다.
동전은 잡는 순간/착지 순간에 결과가 확정되고, 회전은 그 결과 면으로
수렴하도록 역산합니다(`targetRotation`). 애니메이션은 결과에 영향을 주지 않습니다.

**사운드** — 오디오 파일 없이 `SoundEngine`이 사인파 + 화이트노이즈로
동전 울림, 호루라기(38Hz 트레몰로 = 콩알 구르는 소리), 카드 휙,
주사위 딸깍, 성냥 긋기, 촛불 끄는 입김을 실시간 합성합니다. 렌더 스레드에서는 xorshift 노이즈만
사용해 할당이 없습니다.

**네 번째 물건 추가** — `HomeView`에 `NavigationLink` 한 줄과
새 폴더(예: `Straws/`)를 추가하면 됩니다. 프로젝트가
FileSystemSynchronizedRootGroup 방식이라 파일을 폴더에 넣기만 하면
Xcode가 자동으로 타깃에 포함합니다. 다음 후보: 제비뽑기, 사다리타기, 룰렛.
