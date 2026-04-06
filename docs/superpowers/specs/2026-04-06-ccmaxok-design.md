# CCMaxOK — Claude Code Usage Monitor for macOS

## Overview

macOS 메뉴바 앱으로, Claude Code Max/Pro 플랜 사용자의 토큰 사용량을 실시간 모니터링한다. 과다 사용 경고, 낭비 방지 알림, 스마트 활용 추천, Max vs Pro 플랜 비교 분석을 제공한다.

## Problem

Max 플랜($100/월)을 결제했지만 실제로는 Pro($20/월)로 충분했을 수 있다. 반대로 rate limit에 자주 걸리면 사용 패턴을 조절해야 한다. 현재 Claude Code에는 이런 인사이트를 제공하는 도구가 없다.

## Tech Stack

- **언어/프레임워크**: Swift + SwiftUI
- **최소 지원**: macOS 14 (Sonoma)
- **데이터 저장**: SQLite (히스토리/분석용)
- **빌드**: Xcode / Swift Package Manager

## Architecture

### 데이터 소스 (3개)

1. **Statusline API (실시간, 주 데이터)**
   - Claude Code는 `~/.claude/settings.json`의 `statusLine` 설정에 등록된 스크립트를 매 응답마다 호출
   - stdin으로 JSON 전달: `rate_limits.five_hour.used_percentage`, `rate_limits.seven_day.used_percentage`, `resets_at` 등
   - 스크립트가 `~/.claude/ccmaxok/live-status.json`에 기록
   - Max/Pro 구독자에서만 rate_limits 필드 제공

2. **stats-cache.json (히스토리)**
   - 경로: `~/.claude/stats-cache.json`
   - 내용: `dailyActivity` (일별 메시지/세션 수), `dailyModelTokens` (일별 모델별 토큰), `modelUsage` (누적 통계)
   - 캐시 기반이라 실시간성은 낮음

3. **Session JSONL 파일 (상세 데이터)**
   - 경로: `~/.claude/projects/<project-path>/<session-id>.jsonl`
   - assistant 타입 메시지에 `usage` 블록 포함: `input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens`
   - 메시지별 timestamp, model, sessionId 포함

### 핵심 컴포넌트

```
┌─────────────────────────────────────────────────┐
│ Data Sources                                     │
│  statusline.sh → live-status.json               │
│  stats-cache.json                                │
│  projects/**/*.jsonl                             │
└──────────────┬──────────────────────────────────┘
               │
┌──────────────▼──────────────────────────────────┐
│ FileWatcher                                      │
│  FSEvents (foreground) / Timer 5분 (background)  │
└──────────────┬──────────────────────────────────┘
               │
┌──────────────▼──────────────────────────────────┐
│ UsageAnalyzer                                    │
│  - 현재 rate limit 상태 계산                      │
│  - 일별/주별 트렌드 분석                           │
│  - 패턴 기반 추천 생성                             │
│  - Pro vs Max 비교 분석                           │
└──────────────┬──────────────────────────────────┘
               │
┌──────────────▼──────────────────────────────────┐
│ NotificationManager                              │
│  macOS UserNotifications 프레임워크               │
│  알림 중복 방지 (쿨다운 타이머)                     │
└──────────────┬──────────────────────────────────┘
               │
┌──────────────▼──────────────────────────────────┐
│ UI Layer                                         │
│  MenuBarExtra (SwiftUI)                          │
│  - 메뉴바 아이콘 + 사용률 텍스트                    │
│  - 팝오버 패널                                    │
└─────────────────────────────────────────────────┘
```

## UI Design

### 메뉴바 아이콘

- 색상 원(●) + 사용률 퍼센트(예: `● 42%`)
- 5시간 rate limit 사용률 표시
- 색상 변화: 초록(0-60%) → 노랑(60-80%) → 빨강(80%+)

### 팝오버 패널 (클릭 시)

4개 섹션으로 구성:

1. **Rate Limits**
   - 5시간 한도: 프로그레스 바 + 퍼센트 + 리셋까지 남은 시간
   - 7일 한도: 프로그레스 바 + 퍼센트 + 리셋까지 남은 시간

2. **오늘 통계**
   - 세션 수, 메시지 수, 총 토큰 수

3. **스마트 추천** (💡)
   - 남은 한도와 사용 패턴에 맞는 활용 제안

4. **플랜 인사이트** (📊)
   - Pro 한도 초과일 수 / 30일
   - Max 유지 vs Pro 전환 추천

## Notification System

### 과다 사용 경고 (🔴)

| 조건 | 메시지 |
|------|--------|
| 5시간 한도 80% 도달 | "5시간 한도의 80%를 사용했어요. 리셋까지 N시간 남았습니다." |
| 5시간 한도 95% 도달 | "곧 rate limit에 걸립니다! 중요한 작업을 먼저 마무리하세요." |
| 7일 한도 70% 도달 | "7일 한도의 70% 소진. 리셋까지 N일 남았어요. 페이스 조절 필요." |

### 낭비 방지 알림 (💚)

| 조건 | 메시지 |
|------|--------|
| 5시간 리셋 1시간 내 + 사용률 <40% | "1시간 뒤 리셋인데 아직 N%나 남았어요! 지금 쓰면 공짜예요." |
| 7일 리셋 1일 내 + 사용률 <50% | "7일 한도 리셋까지 1일인데 N%밖에 안 썼어요." |
| 주간 리포트 (매주 월요일) | "이번 주 평균 일일 사용률 N%." |

### 알림 규칙

- 같은 종류의 알림은 최소 1시간 간격 (쿨다운)
- 사용자가 알림 종류별로 on/off 가능
- 임계값(80%, 95%, 70% 등) 사용자 커스터마이징 가능

## Smart Recommendation Engine

### 패턴 기반 추천

사용 이력의 `dailyModelTokens`와 세션 JSONL의 tool call 패턴을 분석:
- 주로 코딩만 사용 → "코드 리뷰, 문서화, 테스트 작성에도 활용해보세요"
- 특정 시간대 집중 사용 → "오후 2-6시에 몰아서 사용하시네요. 분산하면 rate limit 여유가 생겨요"
- 단일 모델만 사용 → "간단한 작업은 Haiku로 처리하면 Opus 한도에 여유가 생겨요"

### 잔여 토큰 기반 제안

리셋까지 남은 시간과 잔여 한도를 조합:
- 여유 많음 (>50% 남음, 리셋 >2시간) → "프로젝트 리팩토링이나 테스트 커버리지 올리기 좋은 때예요"
- 보통 (20-50% 남음) → "코드 리뷰나 버그 수정에 활용해보세요"
- 적음 (<20% 남음) → "짧은 질문이나 문서 검토 위주로 사용하세요"

### 플랜 비교 분석 (30일 롤링 윈도우)

- **사용량 기반**: Pro 한도를 초과한 날 수 / 30일
- **비용 효율**: Max($100/월) vs Pro($20/월), 초과일의 사용량을 금액으로 환산
- **판단**: 초과일이 5일 이하이고 초과량이 적으면 "Pro 전환 추천", 아니면 "Max 유지 추천"

## Initial Setup (자동)

앱 첫 실행 시 자동으로 수행:

1. `~/.claude/ccmaxok/` 디렉토리 생성
2. `~/.claude/ccmaxok/statusline.sh` 스크립트 배포
   ```bash
   #!/bin/bash
   # stdin으로 받은 JSON을 그대로 저장 (jq 의존성 제거)
   cat /dev/stdin > ~/.claude/ccmaxok/live-status.json
   ```
   - JSON 파싱은 앱(Swift) 측에서 수행하여 외부 의존성 없음
3. `~/.claude/settings.json`에 statusline 설정 추가 (기존 설정이 있으면 사용자 확인 후 진행)
   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "~/.claude/ccmaxok/statusline.sh"
     }
   }
   ```
4. `stats-cache.json` + 기존 JSONL 파싱으로 `history.sqlite` 초기 데이터 구축
5. FSEvents 감시 + 백그라운드 폴링 타이머 시작

## Data Refresh Strategy

- **Foreground**: FSEvents로 `~/.claude/ccmaxok/live-status.json` 변경 즉시 감지
- **Background**: 5분마다 Timer로 폴링
- **히스토리 갱신**: 앱 시작 시 + 매 1시간마다 stats-cache.json 및 새 JSONL 파일 파싱

## File Structure

### 읽기 (입력)
- `~/.claude/stats-cache.json` — 일별 토큰, 모델별 통계
- `~/.claude/projects/**/*.jsonl` — 세션별 상세 토큰 데이터
- `~/.claude/ccmaxok/live-status.json` — statusline에서 기록한 실시간 rate limit

### 쓰기 (출력)
- `~/.claude/ccmaxok/history.sqlite` — 분석용 히스토리 DB
- `~/.claude/ccmaxok/statusline.sh` — statusline 스크립트
- `~/.claude/settings.json` — statusline 설정 등록 (초기 1회)

## SQLite Schema

```sql
-- rate limit 스냅샷 (statusline에서 수집)
CREATE TABLE rate_limit_snapshots (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  timestamp REAL NOT NULL,
  five_hour_used_pct REAL,
  five_hour_resets_at REAL,
  seven_day_used_pct REAL,
  seven_day_resets_at REAL,
  model TEXT
);

-- 일별 사용량 요약 (stats-cache + JSONL에서 집계)
CREATE TABLE daily_usage (
  date TEXT PRIMARY KEY,  -- YYYY-MM-DD
  session_count INTEGER DEFAULT 0,
  message_count INTEGER DEFAULT 0,
  total_input_tokens INTEGER DEFAULT 0,
  total_output_tokens INTEGER DEFAULT 0,
  total_cache_read_tokens INTEGER DEFAULT 0,
  total_cache_creation_tokens INTEGER DEFAULT 0,
  models_used TEXT  -- JSON array
);

-- 알림 히스토리 (중복 방지용)
CREATE TABLE notification_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  timestamp REAL NOT NULL,
  type TEXT NOT NULL,  -- 'overuse_5h_80', 'waste_5h', 'weekly_report' 등
  message TEXT
);
```

## Xcode Project Structure

```
CCMaxOK/
├── CCMaxOKApp.swift              -- @main, MenuBarExtra 정의
├── Models/
│   ├── RateLimitStatus.swift     -- rate limit 데이터 모델
│   ├── DailyUsage.swift          -- 일별 사용량 모델
│   └── Recommendation.swift      -- 추천 모델
├── Services/
│   ├── FileWatcher.swift         -- FSEvents + Timer 기반 파일 감시
│   ├── StatuslineSetup.swift     -- 초기 설정 (스크립트 배포, settings.json 수정)
│   ├── UsageParser.swift         -- stats-cache.json, JSONL 파싱
│   ├── UsageAnalyzer.swift       -- 트렌드 분석, 추천 생성, 플랜 비교
│   ├── NotificationManager.swift -- macOS 알림 관리
│   └── DatabaseManager.swift     -- SQLite CRUD
├── Views/
│   ├── MenuBarView.swift         -- 메뉴바 아이콘 + 팝오버 컨테이너
│   ├── RateLimitCard.swift       -- rate limit 프로그레스 바 카드
│   ├── TodayStatsCard.swift      -- 오늘 통계 카드
│   ├── RecommendationCard.swift  -- 스마트 추천 카드
│   ├── PlanInsightCard.swift     -- 플랜 비교 카드
│   └── SettingsView.swift        -- 알림 임계값 설정
└── Resources/
    └── statusline.sh             -- 번들에 포함, 첫 실행 시 배포
```

## Out of Scope

- 다른 OS 지원 (Windows, Linux)
- Claude API 직접 호출 (모든 데이터는 로컬 파일에서)
- 팀/조직 사용량 모니터링
- App Store 배포 (로컬 빌드)
