# Homebrew Cask 배포 계획

## 현재 상태

| 항목 | 상태 |
|------|------|
| Bundle ID | `com.tah.haru` |
| 버전 | 1.0 (Build 1) |
| 서명 | Apple Development (Team: DUV8UP2WXU) |
| Developer ID | 가입 완료, 서명/공증 가능 |
| Sandbox | 비활성 (Homebrew Cask 배포에 적합) |
| CI/CD | 미구성 |
| Git Tag | 없음 |
| GitHub | https://github.com/JuyeonYu/face_fuel |

## 배포 흐름

```
코드 변경 → git tag v1.0.0 → GitHub Actions 트리거
  → xcodebuild archive → Developer ID 서명 → 공증(notarize)
  → .app을 .zip으로 패키징 → GitHub Release 업로드
  → Homebrew Cask formula 업데이트 (SHA256 갱신)
```

---

## Step 1: 빌드 스크립트 작성

`scripts/build-release.sh` 생성:

```bash
#!/bin/bash
set -euo pipefail

APP_NAME="haru"
SCHEME="ccmaxok"
PROJECT="ccmaxok/ccmaxok.xcodeproj"
ARCHIVE_PATH="build/${APP_NAME}.xcarchive"
EXPORT_PATH="build/export"
ZIP_PATH="build/${APP_NAME}.zip"

# Archive
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM="DUV8UP2WXU"

# Export
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist scripts/export-options.plist

# Zip
ditto -c -k --keepParent "${EXPORT_PATH}/${SCHEME}.app" "$ZIP_PATH"

echo "SHA256: $(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
echo "Build complete: $ZIP_PATH"
```

`scripts/export-options.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>DUV8UP2WXU</string>
</dict>
</plist>
```

## Step 2: 공증 (Notarization)

Apple 공증은 macOS Gatekeeper 통과에 필수.

```bash
# .zip 공증 제출
xcrun notarytool submit build/haru.zip \
  --apple-id "your-apple-id@example.com" \
  --team-id DUV8UP2WXU \
  --password "@keychain:AC_PASSWORD" \
  --wait

# Staple (xcarchive에서 export한 .app에)
xcrun stapler staple "build/export/haru.app"

# Staple 후 다시 zip
ditto -c -k --keepParent "build/export/haru.app" build/haru.zip
```

> `AC_PASSWORD`는 App Store Connect용 앱 전용 암호를 키체인에 저장한 이름.  
> `xcrun notarytool store-credentials "AC_PASSWORD"` 로 미리 저장.

## Step 3: GitHub Actions 자동화

`.github/workflows/release.yml`:

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4

      - name: Import certificates
        env:
          CERTIFICATE_P12: ${{ secrets.CERTIFICATE_P12 }}
          CERTIFICATE_PASSWORD: ${{ secrets.CERTIFICATE_PASSWORD }}
        run: |
          echo "$CERTIFICATE_P12" | base64 --decode > cert.p12
          security create-keychain -p "" build.keychain
          security default-keychain -s build.keychain
          security unlock-keychain -p "" build.keychain
          security import cert.p12 -k build.keychain -P "$CERTIFICATE_PASSWORD" -T /usr/bin/codesign
          security set-key-partition-list -S apple-tool:,apple: -s -k "" build.keychain

      - name: Build & Archive
        run: |
          xcodebuild archive \
            -project ccmaxok/ccmaxok.xcodeproj \
            -scheme ccmaxok \
            -configuration Release \
            -archivePath build/haru.xcarchive \
            CODE_SIGN_IDENTITY="Developer ID Application" \
            DEVELOPMENT_TEAM="DUV8UP2WXU"

      - name: Export
        run: |
          xcodebuild -exportArchive \
            -archivePath build/haru.xcarchive \
            -exportPath build/export \
            -exportOptionsPlist scripts/export-options.plist

      - name: Notarize
        env:
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APPLE_TEAM_ID: DUV8UP2WXU
          NOTARY_PASSWORD: ${{ secrets.NOTARY_PASSWORD }}
        run: |
          ditto -c -k --keepParent "build/export/haru.app" build/haru.zip
          xcrun notarytool submit build/haru.zip \
            --apple-id "$APPLE_ID" \
            --team-id "$APPLE_TEAM_ID" \
            --password "$NOTARY_PASSWORD" \
            --wait
          xcrun stapler staple "build/export/haru.app"
          ditto -c -k --keepParent "build/export/haru.app" build/haru.zip

      - name: Upload to GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          files: build/haru.zip

  update-cask:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - name: Trigger cask update
        run: echo "Update homebrew-haru tap with new SHA256 and version"
```

### GitHub Secrets 설정 필요

| Secret | 설명 |
|--------|------|
| `CERTIFICATE_P12` | Developer ID Application 인증서 (.p12 base64) |
| `CERTIFICATE_PASSWORD` | .p12 파일 암호 |
| `APPLE_ID` | Apple ID 이메일 |
| `NOTARY_PASSWORD` | App Store Connect 앱 전용 암호 |

## Step 4: Homebrew Tap 생성

### 4.1: Tap 저장소 생성

GitHub에 `homebrew-haru` 저장소 생성.

### 4.2: Cask Formula

`Casks/haru.rb`:

```ruby
cask "haru" do
  version "1.0.0"
  sha256 "PLACEHOLDER_SHA256"

  url "https://github.com/JuyeonYu/face_fuel/releases/download/v#{version}/haru.zip"
  name "haru"
  desc "Claude Code usage monitor for macOS menu bar"
  homepage "https://github.com/JuyeonYu/face_fuel"

  depends_on macos: ">= :sequoia"

  app "haru.app", target: "haru.app"

  zap trash: [
    "~/Library/Application Support/CCMaxOK",
    "~/.claude/ccmaxok",
  ]
end
```

### 4.3: 사용자 설치 명령

```bash
brew tap JuyeonYu/haru
brew install --cask haru
```

## Step 5: 버전 관리 규칙

| 변경 유형 | 버전 예시 |
|-----------|-----------|
| 버그 수정 | 1.0.1 |
| 기능 추가 | 1.1.0 |
| 호환성 깨짐 | 2.0.0 |

릴리스 절차:
1. `Info.plist`에서 `MARKETING_VERSION` 업데이트
2. `git tag v1.0.0 && git push --tags`
3. GitHub Actions가 자동으로 빌드 → 공증 → Release 생성
4. `homebrew-haru` Cask formula에서 version/sha256 업데이트

## Step 6: 사전 준비 체크리스트

- [ ] Developer ID Application 인증서 발급 (Keychain에 설치)
- [ ] App Store Connect 앱 전용 암호 생성
- [ ] `scripts/build-release.sh`, `scripts/export-options.plist` 생성
- [ ] 로컬에서 수동 빌드 → 서명 → 공증 테스트
- [ ] GitHub Secrets 설정
- [ ] `.github/workflows/release.yml` 추가
- [ ] `homebrew-haru` 저장소 생성
- [ ] `git tag v1.0.0` → 첫 릴리스 테스트
