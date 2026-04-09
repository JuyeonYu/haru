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

            if !state.isConnected {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Claude Code 연결 안 됨")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("Claude Code를 실행하면 자동으로 연결됩니다")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                RateLimitCard(
                    fiveHourPct: state.fiveHourUsedPct,
                    fiveHourResetsAt: state.fiveHourResetsAt,
                    sevenDayPct: state.sevenDayUsedPct,
                    sevenDayResetsAt: state.sevenDayResetsAt
                )
                .padding(12)
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
                    Text(statusMessage(remainPct))
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("\(Int(remainPct))% 남음")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
        } else {
            VStack(spacing: 2) {
                Text("FaceFuel")
                    .font(.headline)
                Text("Claude Code Usage Monitor")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statusMessage(_ remainPct: Double) -> String {
        switch remainPct {
        case 80...: return "여유롭네요"
        case 50..<80: return "괜찮아요"
        case 20..<50: return "절반 지났어요"
        case 10..<20: return "아껴쓰세요"
        default: return "거의 다 썼어요"
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
