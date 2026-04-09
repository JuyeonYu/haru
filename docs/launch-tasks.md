# 출시 준비 태스크

## Task 1: 앱 내 GitHub Sponsors 표시

### 위치
MenuBarView 팝오버 하단 푸터 바 (Settings... / Quit 사이)

### 구현
- SF Symbol `heart.fill` 아이콘 + "Sponsor" 텍스트
- 클릭 시 `https://github.com/sponsors/JuyeonYu` 브라우저 오픈
- 스타일: `.pink` 색상, `.caption` 폰트, 기존 Settings/Quit과 동일한 `.plain` 버튼

### 레이아웃
```
Settings...    ♥ Sponsor    Quit
```

### 로컬라이제이션
- "Sponsor" → Localizable.xcstrings에 추가 (ko: "후원", en: "Sponsor")

### 수정 파일
- `ccmaxok/ccmaxok/Views/MenuBarView.swift` — 푸터 HStack에 버튼 추가
- `ccmaxok/ccmaxok/Localizable.xcstrings` — 번역 추가

---

## Task 2: README.md 작성

### 위치
프로젝트 루트 `/README.md`

### 구조

```markdown
# haru

Claude Code 사용량을 실시간으로 모니터링하는 macOS 메뉴바 앱

(영문 한 줄 설명도 병기)

## Features
- 5시간/7일 rate limit 실시간 모니터링
- 사용량 기반 스마트 알림 (과다 사용, 낭비 방지)
- 얼굴 인식 커스텀 메뉴바 아이콘
- 영문/한글 지원

## Installation

### Homebrew (추후)
brew tap JuyeonYu/haru
brew install --cask haru

### Manual Build
git clone https://github.com/JuyeonYu/haru.git
Xcode에서 ccmaxok.xcodeproj 열고 빌드

## Requirements
- macOS 15.0+
- Claude Code (Max 또는 Pro 플랜)

## How it works
1. Claude Code statusline hook으로 사용량 데이터 수집
2. 메뉴바에서 실시간 잔여량 표시
3. 임계값 기반 알림 자동 발송

## Screenshots
(추후 추가)

## Tech Stack
- Swift / SwiftUI
- SQLite (SQLite.swift)
- Vision framework (얼굴 인식)

## Support
GitHub Sponsors 링크

## License
(라이선스 선택 필요)
```

### 수정 파일
- `/README.md` (신규 생성)

---

## 실행 순서
1. Task 1: Sponsor 버튼 추가 (코드 변경 소량)
2. Task 2: README 작성
3. 커밋 & 푸시
