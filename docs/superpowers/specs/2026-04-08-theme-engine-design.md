# CCMaxOK 메뉴바 테마 엔진 설계

## Context

현재 CCMaxOK 메뉴바는 6개의 하드코딩된 `MenuBarStyle` enum으로 표시 방식을 선택한다. 스타일을 추가할 때마다 enum case + switch 분기 + Settings 라디오버튼이 늘어나는 구조. 이걸 "표현 엔진"으로 전환하여 사용자가 렌더러 종류, 색상, 문자, 세그먼트 수, 이미지 등을 자유롭게 조합할 수 있게 한다.

### macOS 메뉴바 label 제약 (검증 완료)

- `MenuBarExtra` label은 `Text`, `Image(systemName:)`, `HStack` 정도만 렌더링됨
- 커스텀 Shape(`RoundedRectangle`, `Canvas`, `ZStack` 등)은 **렌더링되지 않음** (battery 이슈로 확인)
- `TimelineView`도 label 안에서는 **동작하지 않음** (메뉴바 안 보이는 이슈로 확인)
- `NSImage`를 `Image(nsImage:)`로 넘기면 커스텀 이미지 렌더링 **가능**
- 애니메이션은 label에서 불가 → NSStatusBarButton 직접 제어 필요 (Phase 3)

### 현재 구조 (변경 대상)

```
ccmaxokApp.swift
├── enum MenuBarStyle (6 cases, 하드코딩)
├── menuBarLabel (switch 6분기)
├── batteryIconName(), shortTime() (헬퍼)
└── iconColor, sevenDayColor (computed)

SettingsView.swift
├── Picker with radioGroup (6개 고정 라벨)
└── 알림/임계값 설정
```

---

## Phase 1 — 렌더러 프로토콜 + 가벼운 커스텀

**목표**: enum switch 분기를 프로토콜 기반으로 리팩터링하고, 색상/문자/칸수 개인화를 추가한다.

### 1-1. 렌더러 프로토콜 도입

**파일**: `Sources/CCMaxOKCore/Rendering/UsageRenderer.swift` (신규)

```swift
protocol UsageRenderer {
    var id: String { get }
    var displayName: String { get }
    func render(context: RenderContext) -> RenderedOutput
}

struct RenderContext {
    let remainPct: Double        // 5시간 잔여%
    let sevenDayRemainPct: Double // 7일 잔여%
    let fiveHourResetsAt: Date
    let sevenDayResetsAt: Date
    let alertLevel: AlertLevel
}

enum RenderedOutput {
    case text(String)                    // Text로 렌더링
    case symbolAndText(String, String)   // Image(systemName:) + Text
    case image(NSImage)                  // 커스텀 이미지 (Phase 2)
}
```

### 1-2. 기본 렌더러 구현 (기존 6개 스타일 마이그레이션)

**파일**: `Sources/CCMaxOKCore/Rendering/` 디렉토리

| 렌더러 | 클래스 | 설명 |
|---|---|---|
| SimpleRenderer | `simple` | ● 85% |
| TimeRenderer | `withTime` | ● 85% · 2h30m |
| CompactRenderer | `compact` | 85% ↻2:30 |
| BlockRenderer | `block` | ■■■■■■■■□□ 85% |
| BatteryRenderer | `battery` | 🔋 85% |
| DualRenderer | `dual` | ● 85% · ● 4d12h |

### 1-3. BlockRenderer 커스텀 옵션

**저장**: `UserDefaults` (기존 패턴 유지)

| 옵션 | 키 | 기본값 | 범위 |
|---|---|---|---|
| 세그먼트 수 | `block_segment_count` | 10 | 5, 10, 20 |
| 채움 문자 | `block_filled_char` | `■` | ■, ●, ★, 🟩, ❤️, 🔥 등 |
| 빈칸 문자 | `block_empty_char` | `□` | □, ○, ☆, ⬜, 🤍, · 등 |
| % 텍스트 표시 | `block_show_percent` | true | bool |

### 1-4. 전역 색상 커스텀

| 옵션 | 키 | 기본값 |
|---|---|---|
| 정상 색상 | `color_normal` | green |
| 경고 색상 | `color_warning` | yellow |
| 위험 색상 | `color_critical` | red |
| 시스템 accent 연동 | `color_use_accent` | false |

### 1-5. Settings UI 변경

현재 라디오 6개 → 렌더러 선택 Picker + 선택된 렌더러별 옵션 패널

```
[메뉴바 표시]
  렌더러: [Simple ▾]
  
  [Simple 옵션]           ← 렌더러 선택에 따라 동적 변경
  퍼센트 표시: [on]
  
[색상]
  정상: [🟢]  경고: [🟡]  위험: [🔴]
  
[알림 설정]
  (기존 유지)
```

### 1-6. ccmaxokApp.swift 변경

```swift
// Before: switch menuBarStyle { case .simple: ... case .bar: ... }
// After:
let renderer = RendererRegistry.current
let output = renderer.render(context: renderContext)
// output에 따라 Text 또는 Image 표시
```

### 수정 파일 목록

| 파일 | 작업 |
|---|---|
| `Sources/CCMaxOKCore/Rendering/UsageRenderer.swift` | 신규 — 프로토콜 + RenderContext |
| `Sources/CCMaxOKCore/Rendering/SimpleRenderer.swift` | 신규 |
| `Sources/CCMaxOKCore/Rendering/BlockRenderer.swift` | 신규 — 커스텀 옵션 포함 |
| `Sources/CCMaxOKCore/Rendering/BatteryRenderer.swift` | 신규 |
| `Sources/CCMaxOKCore/Rendering/TimeRenderer.swift` | 신규 |
| `Sources/CCMaxOKCore/Rendering/CompactRenderer.swift` | 신규 |
| `Sources/CCMaxOKCore/Rendering/DualRenderer.swift` | 신규 |
| `Sources/CCMaxOKCore/Rendering/RendererRegistry.swift` | 신규 — 렌더러 관리/선택 |
| `ccmaxok/ccmaxokApp.swift` | 수정 — enum 제거, 렌더러 기반으로 전환 |
| `ccmaxok/Views/SettingsView.swift` | 수정 — 동적 옵션 패널 |

---

## Phase 2 — 사용자 에셋 지원

**목표**: 사용자가 자기 이미지를 업로드해서 메뉴바 아이콘으로 쓸 수 있게 한다.

### 2-1. ImageRenderer

- 사용자가 PNG/JPG 업로드 → `~/Library/Application Support/CCMaxOK/themes/` 저장
- 메뉴바 크기(22pt 높이)에 맞게 리사이즈
- `Image(nsImage:)`로 렌더링 (메뉴바에서 동작 확인됨)

### 2-2. 얼굴 자동 감지 + 크롭

사진 업로드 시 Vision 프레임워크로 얼굴을 자동 감지하여 크롭한다. 추가 라이브러리 불필요, 온디바이스 처리, Intel Mac에서도 동작.

**처리 흐름**:
```
사진 업로드 → VNDetectFaceRectanglesRequest → 얼굴 영역 감지
→ 감지된 얼굴 주변 여백 포함 크롭 → 원형 마스크 적용 (선택)
→ 22pt 리사이즈 → 메뉴바 아이콘
```

**구현**:
```swift
import Vision

let request = VNDetectFaceRectanglesRequest()
let handler = VNImageRequestHandler(cgImage: image)
try handler.perform([request])

if let face = request.results?.first {
    let faceRect = face.boundingBox  // 정규화된 좌표 (0~1)
    // 여백 20% 추가 후 크롭
    let cropped = image.cropping(to: expandedRect)
}
```

**UX 옵션**:
- 얼굴 감지 성공 시: 자동 크롭 미리보기 + 수동 조정 가능
- 여러 얼굴 감지 시: 사용자가 선택
- 얼굴 미감지 시: 원본 이미지 그대로 사용
- 마스크 형태: 원형 / 둥근 사각형 / 없음 선택

### 2-3. 상태별 이미지 매핑

```
high (51~100%): happy.png
mid  (21~50%):  neutral.png  
low  (0~20%):   sad.png
```

### 2-4. 단일 이미지 + 효과

이미지 1개만 업로드하고 잔여량에 따라:
- opacity 변화 (100%→불투명, 0%→반투명)
- grayscale 전환 (low일 때)
- NSImage 레벨에서 처리 후 `Image(nsImage:)`로 전달

### 2-5. 반복 아이콘 바

사용자 이미지를 세그먼트로 반복:
- 예: 🐶🐶🐶🐶🐶👻👻👻👻👻 (5/10 잔여)
- BlockRenderer의 문자 대신 미니 이미지 사용
- NSImage로 10칸 합성 → `Image(nsImage:)`

### 수정/추가 파일

| 파일 | 작업 |
|---|---|
| `Sources/CCMaxOKCore/Rendering/ImageRenderer.swift` | 신규 |
| `Sources/CCMaxOKCore/Rendering/SegmentedImageRenderer.swift` | 신규 |
| `Sources/CCMaxOKCore/Rendering/FaceCropper.swift` | 신규 — Vision 기반 얼굴 감지 + 크롭 |
| `Sources/CCMaxOKCore/ThemeManager.swift` | 신규 — 에셋 저장/로드 |
| `ccmaxok/Views/SettingsView.swift` | 수정 — 이미지 업로드 UI, 얼굴 크롭 미리보기 |

---

## Phase 3 — 상태 연출 / 애니메이션

**목표**: 정적 표시를 넘어 잔여량에 따른 시각 효과를 추가한다.

### macOS 메뉴바 애니메이션 방법

`MenuBarExtra` label에서는 SwiftUI 애니메이션이 불가. 대신:
- `NSStatusBarButton.image`를 Timer로 교체하는 프레임 애니메이션
- `NSStatusItem`을 직접 제어

### 3-1. 효과 유형

| 효과 | 조건 | 구현 |
|---|---|---|
| glow/pulse | 100% 잔여 | NSImage 밝기 변화 프레임 2~3장 교체 |
| dim | 20% 이하 | NSImage opacity 낮춤 |
| shake | 10% 이하 | NSStatusBarButton position 미세 변동 |
| blink | 5% 이하 | 아이콘 on/off 토글 |

### 3-2. 프리셋

- `none`: 효과 없음
- `subtle`: glow at full, dim at low
- `lively`: pulse + shake + blink

---

## 테마 데이터 모델

Phase 1부터 이 구조로 저장. Phase 2, 3에서 필드 확장.

```json
{
  "id": "custom_1",
  "name": "My Theme",
  "rendererType": "block",
  "showPercentage": true,
  "config": {
    "segments": 10,
    "filledChar": "❤️",
    "emptyChar": "🤍"
  },
  "colors": {
    "normal": "#00FF00",
    "warning": "#FFFF00",
    "critical": "#FF0000"
  },
  "assets": {},
  "effects": { "full": "none", "low": "none" }
}
```

저장 위치: `~/.claude/ccmaxok/themes/`
형식: JSON, import/export 가능

---

## 저작권 정책

- 앱 기본 제공: SF Symbols + 유니코드 이모지만 (직접 제작 또는 라이선스 확인된 것)
- 유명 캐릭터 기본 제공 금지
- 사용자 업로드는 허용, 약관에 명시: "사용자는 권리를 보유한 이미지만 업로드해야 합니다"
- 커뮤니티 공유 기능 시 신고/삭제 구조 필요

---

## 구현 우선순위

| 버전 | 내용 | 핵심 가치 |
|---|---|---|
| **v1.1** | Phase 1 전체 (렌더러 리팩터링 + 색상/문자/칸수 커스텀) | "내 스타일로 바꿨다" |
| **v1.2** | Phase 2-1~2-3 (단일 이미지 + 상태별 효과) | "내 사진을 넣었다" |
| **v1.3** | Phase 2-4 + 테마 저장/로드/내보내기 | "테마를 만들고 공유한다" |
| **v2.0** | Phase 3 (애니메이션 + NSStatusItem 직접 제어) | "살아있는 아이콘" |

---

## 검증 방법

1. **Phase 1 검증**: 6개 기존 스타일이 렌더러로 동일하게 동작하는지 확인. BlockRenderer에서 칸수/문자 변경 후 메뉴바 반영 확인.
2. **Phase 2 검증**: 테스트 PNG 업로드 → 메뉴바에 22pt 아이콘 표시 → 잔여량 변화 시 이미지 전환/opacity 변화 확인.
3. **Phase 3 검증**: Timer 기반 프레임 교체가 메뉴바에서 깜빡임 없이 동작하는지 확인. 배터리 소모 측정.
