import SwiftUI
import CCMaxOKCore
import UniformTypeIdentifiers

struct MenuBarView: View {
    let state: AppState

    @AppStorage("renderer_id") private var rendererId = "simple"
    @AppStorage("simple_use_custom_image") private var simpleUseCustomImage = false
    @AppStorage("block_filled_char") private var blockFilled = "■"
    @AppStorage("image_high") private var imageHigh = ""
    @AppStorage("image_mask") private var imageMask = "circle"

    var body: some View {
        VStack(spacing: 0) {
            profileHeader
                .padding(.vertical, 12)

            Divider()

            switch state.connectionState {
            case .noClaudeDir:
                VStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Claude Code 미설치")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("Claude Code를 먼저 설치해주세요")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)

            case .waitingFirstRun:
                VStack(spacing: 8) {
                    Image(systemName: "arrow.trianglehead.2.clockwise")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("데이터 대기 중")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("haru는 Claude Code의 statusline 훅을 통해\n데이터를 받습니다. Claude Code를 한 번\n실행하면 자동으로 표시됩니다.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    Button("Re-setup") {
                        state.retrySetup()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .font(.caption2)

                    if !state.statuslineConflicts.isEmpty {
                        conflictsBanner
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)

            case .stale(let asOf):
                VStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("마지막 업데이트: \(staleRelativeLabel(asOf)) · Claude Code 실행 시 갱신")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    RateLimitCard(
                        fiveHourPct: state.fiveHourUsedPct,
                        fiveHourResetsAt: state.fiveHourResetsAt,
                        sevenDayPct: state.sevenDayUsedPct,
                        sevenDayResetsAt: state.sevenDayResetsAt,
                        hasData: state.hasRateLimitsData
                    )
                    .padding(12)
                    .opacity(0.75)
                }

            case .derived(let asOf):
                VStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("파생 데이터 · rate limit 없음 (기준: \(staleRelativeLabel(asOf)))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("오늘 세션")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(state.todaySessionCount)개 · \(state.todayMessageCount)메시지")
                                .font(.caption)
                        }
                        HStack {
                            Text("오늘 토큰")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(state.todayTotalTokens.formatted())")
                                .font(.caption)
                        }
                        HStack {
                            Text("이번주 Sonnet")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(state.weekSonnetTokens.formatted())")
                                .font(.caption)
                        }
                    }
                    .padding(12)
                    .opacity(0.85)
                }

            case .connectedNoLimits:
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.title2)
                        .foregroundStyle(.green)
                    Text("연결됨")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("현재 플랜에서는 rate limit 정보가\n제공되지 않을 수 있습니다")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)

            case .connected where state.hasRateLimitsData:
                RateLimitCard(
                    fiveHourPct: state.fiveHourUsedPct,
                    fiveHourResetsAt: state.fiveHourResetsAt,
                    sevenDayPct: state.sevenDayUsedPct,
                    sevenDayResetsAt: state.sevenDayResetsAt,
                    hasData: state.hasRateLimitsData
                )
                .padding(12)

            default:
                EmptyView()
            }

            Divider()

            HStack {
                SettingsLink {
                    Text("Settings...")
                }
                .simultaneousGesture(TapGesture().onEnded {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NSApp.activate(ignoringOtherApps: true)
                        for window in NSApp.windows {
                            if String(describing: type(of: window)).contains("Settings")
                                || window.title.contains("Settings")
                                || window.title.contains("설정") {
                                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                                window.makeKeyAndOrderFront(nil)
                                window.orderFrontRegardless()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    window.collectionBehavior = [.fullScreenAuxiliary]
                                }
                            }
                        }
                    }
                })
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            HStack(spacing: 4) {
                Button {
                    if let url = URL(string: "https://github.com/sponsors/JuyeonYu?frequency=one-time&amount=5") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(Color(nsColor: NSColor(red: 0xEA/255, green: 0x4A/255, blue: 0xAA/255, alpha: 1)))
                        Text("Support development")
                    }
                }
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    private var shouldShowOnboarding: Bool {
        let dismissed = UserDefaults.standard.bool(forKey: "onboarding_dismissed")
        let hasImage = !(UserDefaults.standard.string(forKey: "image_high") ?? "").isEmpty
        let useCustom = UserDefaults.standard.bool(forKey: "simple_use_custom_image")
        return !dismissed && !(useCustom && hasImage)
    }

    private var onboardingCard: some View {
        VStack(spacing: 8) {
            Text("📸")
                .font(.title)
            Text("사진 한 장으로\n나만의 메뉴바를 만들어보세요")
                .font(.caption)
                .multilineTextAlignment(.center)
            Button("사진 선택하기") {
                pickOnboardingImage()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Button("건너뛰기") {
                UserDefaults.standard.set(true, forKey: "onboarding_dismissed")
            }
            .buttonStyle(.plain)
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func pickOnboardingImage() {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.png, .jpeg]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false

            guard panel.runModal() == .OK, let url = panel.url,
                  let originalImage = NSImage(contentsOf: url) else { return }

            let faces = FaceCropper.detectFaces(in: originalImage)
            let imageToSave: NSImage
            if let first = faces.first,
               let cropped = FaceCropper.cropFace(from: originalImage, faceRect: first, mask: .none) {
                imageToSave = cropped
            } else {
                imageToSave = originalImage
            }

            if let filename = ThemeManager.shared.saveImageUnique(imageToSave) {
                // 갤러리에 추가
                let galleryJSON = UserDefaults.standard.string(forKey: "face_gallery") ?? "[]"
                var gallery = (try? JSONDecoder().decode([String].self, from: Data(galleryJSON.utf8))) ?? []
                gallery.append(filename)
                if let data = try? JSONEncoder().encode(gallery), let json = String(data: data, encoding: .utf8) {
                    UserDefaults.standard.set(json, forKey: "face_gallery")
                }
                UserDefaults.standard.set(filename, forKey: "image_high")
                UserDefaults.standard.set(true, forKey: "simple_use_custom_image")
                UserDefaults.standard.set(true, forKey: "onboarding_dismissed")
                NotificationCenter.default.post(name: .rendererSettingsChanged, object: nil)
            }
        }
    }

    @ViewBuilder
    private var profileHeader: some View {
        let usesCustomImage = (rendererId == "simple" && simpleUseCustomImage)
            || (rendererId == "block" && blockFilled == "__custom_image__")
        let remainPct = max(0, 100 - state.fiveHourUsedPct)

        if usesCustomImage && !imageHigh.isEmpty,
           let img = ThemeManager.shared.loadImage(named: imageHigh) {
            let mask = FaceCropper.MaskShape(rawValue: imageMask) ?? .circle
            let masked = FaceCropper.applyShapeMask(to: img, mask: mask)
            let effected = applyStatusEffect(to: masked, remainPct: remainPct)
            let resized = ThemeManager.shared.resizeForMenuBar(effected, height: 48)

            HStack(spacing: 10) {
                Image(nsImage: resized)
                VStack(alignment: .leading, spacing: 2) {
                    Text("haru")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("Claude Code Usage Monitor")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("\(statusMessage(remainPct)) · \(Int(remainPct))% 남음")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
        } else {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("haru")
                        .font(.headline)
                    Text("Claude Code Usage Monitor")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
        }
    }

    private var conflictsBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Text("프로젝트 로컬 statusline 감지됨")
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            Text("다음 프로젝트의 `.claude/settings.json`에서 statusline이 다른 스크립트로 설정되어 haru 데이터가 들어오지 않을 수 있습니다:")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(state.statuslineConflicts.prefix(3), id: \.settingsPath) { c in
                Text("· \(c.projectPath.lastPathComponent)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if state.statuslineConflicts.count > 3 {
                Text("· 외 \(state.statuslineConflicts.count - 3)건")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 12)
    }

    private func staleRelativeLabel(_ date: Date) -> String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .short
        fmt.locale = Locale.current
        return fmt.localizedString(for: date, relativeTo: Date())
    }

    private func statusMessage(_ remainPct: Double) -> String {
        switch remainPct {
        case 80...: return String(localized: "여유롭네요")
        case 50..<80: return String(localized: "괜찮아요")
        case 20..<50: return String(localized: "절반 지났어요")
        case 10..<20: return String(localized: "아껴쓰세요")
        default: return String(localized: "거의 다 썼어요")
        }
    }

    private func applyStatusEffect(to image: NSImage, remainPct: Double) -> NSImage {
        let tm = ThemeManager.shared
        switch remainPct {
        case 50...: return image
        case 20..<50: return tm.applyOpacity(image, opacity: 0.7)
        default:
            let gray = tm.applyGrayscale(image)
            return tm.applyOpacity(gray, opacity: 0.6)
        }
    }
}
