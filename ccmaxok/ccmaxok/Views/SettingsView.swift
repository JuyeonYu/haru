import SwiftUI
import CCMaxOKCore
import UniformTypeIdentifiers

struct SettingsView: View {
    // 렌더러 선택
    @AppStorage("renderer_id") private var rendererId = "simple"
    @AppStorage("show_reset_time") private var showResetTime = false
    // Simple 커스텀
    @AppStorage("simple_icon") private var simpleIcon = "⬤"
    @AppStorage("simple_use_custom_image") private var simpleUseCustomImage = false

    // Block 커스텀
    @AppStorage("block_segment_count") private var blockSegments = 10
    @AppStorage("block_filled_char") private var blockFilled = "■"
    @AppStorage("block_empty_char") private var blockEmpty = "□"
    @AppStorage("block_show_percent") private var blockShowPercent = true

    // Image 커스텀
    @AppStorage("image_high") private var imageHigh = ""
    @AppStorage("image_mid") private var imageMid = ""
    @AppStorage("image_low") private var imageLow = ""
    @AppStorage("image_show_percent") private var imageShowPercent = true
    @AppStorage("image_mask") private var imageMask = "circle"
    @AppStorage("seg_image_count") private var segImageCount = 10

    // 얼굴 갤러리
    @AppStorage("face_gallery") private var faceGalleryJSON = "[]"

    @State private var facePickerData: FacePickerData?
    @State private var pendingSlot: String = ""
    @State private var thumbnailCache: [String: NSImage] = [:]

    private var faceGallery: [String] {
        (try? JSONDecoder().decode([String].self, from: Data(faceGalleryJSON.utf8))) ?? []
    }

    private func setFaceGallery(_ gallery: [String]) {
        faceGalleryJSON = (try? String(data: JSONEncoder().encode(gallery), encoding: .utf8)) ?? "[]"
    }

    private let blockCharSets: [(filled: String, empty: String, label: String)] = [
        ("🟩", "⬜", "🟩⬜ 컬러"),
        ("❤️", "🤍", "❤️🤍 하트"),
        ("__custom_image__", "", "🖼 커스텀"),
    ]

    private let simpleIconOptions: [(icon: String, label: String)] = [
        ("⬤", "원"),
    ]
    private let segmentOptions = [5, 10]

    var body: some View {
        Form {
            Section("메뉴바 표시") {
                Picker("렌더러", selection: $rendererId) {
                    ForEach(RendererRegistry.allRenderers, id: \.id) { renderer in
                        Text("\(renderer.displayName)  \(renderer.previewText)")
                            .tag(renderer.id)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: rendererId) { _, _ in notifyRendererChanged() }

                Toggle("리셋 시간 표시", isOn: $showResetTime)
                    .onChange(of: showResetTime) { _, _ in notifyRendererChanged() }

            }

            if rendererId == "simple" {
                Section("Simple 옵션") {
//                    Picker("아이콘", selection: $simpleIcon) {
//                        ForEach(simpleIconOptions, id: \.icon) { opt in
//                            Text("\(opt.icon) \(opt.label)").tag(opt.icon)
//                        }
//                    }
//                    .onChange(of: simpleIcon) { _, _ in notifyRendererChanged() }

                    Toggle("얼굴로 표시", isOn: $simpleUseCustomImage)
                        .onChange(of: simpleUseCustomImage) { _, _ in notifyRendererChanged() }

                    if simpleUseCustomImage {
                        Picker("마스크", selection: $imageMask) {
                            Text("없음").tag("none")
                            Text("원형").tag("circle")
                            Text("둥근 사각형").tag("roundedRect")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: imageMask) { _, _ in notifyRendererChanged() }

                        faceGalleryView
                    }
                }
            }

            if rendererId == "block" {
                Section("Block 옵션") {
                    Picker("칸 수", selection: $blockSegments) {
                        ForEach(segmentOptions, id: \.self) { n in
                            Text("\(n)칸").tag(n)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: blockSegments) { _, _ in notifyRendererChanged() }

                    Picker("문자 세트", selection: $blockFilled) {
                        ForEach(blockCharSets, id: \.filled) { set in
                            Text(LocalizedStringKey(set.label)).tag(set.filled)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: blockFilled) { _, newValue in
                        if let set = blockCharSets.first(where: { $0.filled == newValue }) {
                            blockEmpty = set.empty
                        }
                        notifyRendererChanged()
                    }

                    Toggle("퍼센트 표시", isOn: $blockShowPercent)
                        .onChange(of: blockShowPercent) { _, _ in notifyRendererChanged() }

                    if blockFilled != "__custom_image__" {
                        Text(blockPreview)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 4)
                    }

                    if blockFilled == "__custom_image__" {
                        Divider()

                        Picker("마스크", selection: $imageMask) {
                            Text("없음").tag("none")
                            Text("원형").tag("circle")
                            Text("둥근 사각형").tag("roundedRect")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: imageMask) { _, _ in notifyRendererChanged() }

                        faceGalleryView
                    }
                }
            }

            Section("정보") {
                LabeledContent("버전") {
                    Text("\(appVersion) (\(appBuild))")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if let wrapped = wrappedStatusline {
                    LabeledContent("감싼 statusline") {
                        Text(wrapped)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .help(wrapped)
                    }
                }
                if let repoURL = URL(string: "https://github.com/JuyeonYu/haru") {
                    Link(destination: repoURL) {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                            Text("GitHub")
                        }
                    }
                }
            }

            Section("진단") {
                LabeledContent("최근 경고·오류") {
                    Text("\(DiagnosticsLogger.shared.errorCount)건")
                        .foregroundStyle(DiagnosticsLogger.shared.errorCount > 0 ? .orange : .secondary)
                        .monospacedDigit()
                }
                LabeledContent("로그 파일") {
                    Text(DiagnosticsLogger.shared.logFileURL.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                HStack {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([DiagnosticsLogger.shared.logFileURL])
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                            Text("Finder에서 열기")
                        }
                    }
                    Button {
                        copyLogToClipboard()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                            Text("로그 복사")
                        }
                    }
                    Button {
                        openGithubIssueWithDiagnostics()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "ladybug")
                            Text("이슈 제출")
                        }
                    }
                    Spacer()
                    Button("지우기", role: .destructive) {
                        DiagnosticsLogger.shared.clear()
                    }
                    .controlSize(.small)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

        }
        .formStyle(.grouped)
        .frame(width: 450)
        .frame(minHeight: 300, idealHeight: 500)
        .sheet(item: $facePickerData) { data in
            FacePickerSheet(candidates: data.candidates) { selected in
                facePickerData = nil
                saveImageToSlot(selected, slot: pendingSlot)
            }
        }
    }

    private func pickAndSaveImage(slot: String) {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.png, .jpeg]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            guard panel.runModal() == .OK, let url = panel.url,
                  let originalImage = NSImage(contentsOf: url) else { return }
            processPickedImage(originalImage, slot: slot)
        }
    }

    private func processPickedImage(_ originalImage: NSImage, slot: String) {
        Task.detached(priority: .userInitiated) {
            let faces = FaceCropper.detectFaces(in: originalImage)

            if faces.count > 1 {
                let candidates = faces.compactMap { rect in
                    FaceCropper.cropFace(from: originalImage, faceRect: rect, mask: .none)
                }
                if candidates.count > 1 {
                    await MainActor.run {
                        pendingSlot = slot
                        facePickerData = FacePickerData(candidates: candidates)
                    }
                    return
                }
            }

            let imageToSave: NSImage
            if let first = faces.first,
               let cropped = FaceCropper.cropFace(from: originalImage, faceRect: first, mask: .none) {
                imageToSave = cropped
            } else {
                imageToSave = originalImage
            }
            await MainActor.run {
                saveImageToSlot(imageToSave, slot: slot)
            }
        }
    }

    private func saveImageToSlot(_ image: NSImage, slot: String) {
        let tm = ThemeManager.shared
        guard let filename = tm.saveImageUnique(image) else { return }

        // 갤러리에 추가
        var gallery = faceGallery
        gallery.append(filename)
        setFaceGallery(gallery)

        // 활성 얼굴로 설정
        imageHigh = filename
        notifyRendererChanged()
        rebuildThumbnails()
    }

    @ViewBuilder
    private var faceGalleryView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("얼굴 갤러리")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("추가...") {
                    pickAndSaveImage(slot: "high")
                }
                .controlSize(.small)
            }

            if faceGallery.isEmpty {
                Text("저장된 얼굴이 없습니다")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(faceGallery, id: \.self) { filename in
                            faceGalleryItem(filename: filename)
                        }
                    }
                }
            }
        }
        .onAppear { rebuildThumbnails() }
        .onChange(of: imageMask) { _, _ in rebuildThumbnails() }
    }

    @ViewBuilder
    private func faceGalleryItem(filename: String) -> some View {
        let isSelected = imageHigh == filename

        Button {
            imageHigh = filename
            notifyRendererChanged()
        } label: {
            VStack(spacing: 4) {
                if let cached = thumbnailCache[filename] {
                    Image(nsImage: cached)
                        .frame(width: 48, height: 48)
                } else if let img = ThemeManager.shared.loadImage(named: filename) {
                    let resized = ThemeManager.shared.resizeForMenuBar(img, height: 48)
                    Image(nsImage: resized)
                        .frame(width: 48, height: 48)
                }
            }
            .padding(4)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("삭제", role: .destructive) {
                removeFace(filename: filename)
            }
        }
    }

    private func rebuildThumbnails() {
        let gallery = faceGallery
        let remainPct = max(0, 100 - currentUsedPct)
        let maskShape = FaceCropper.MaskShape(rawValue: imageMask) ?? .circle

        var cache: [String: NSImage] = [:]
        for filename in gallery {
            guard let img = ThemeManager.shared.loadImage(named: filename) else { continue }
            let effected = applyStatusEffect(to: img, remainPct: remainPct)
            let masked = FaceCropper.applyShapeMask(to: effected, mask: maskShape)
            let resized = ThemeManager.shared.resizeForMenuBar(masked, height: 48)
            cache[filename] = resized
        }
        thumbnailCache = cache
    }

    private func removeFace(filename: String) {
        ThemeManager.shared.deleteImage(named: filename)
        var gallery = faceGallery
        gallery.removeAll { $0 == filename }
        setFaceGallery(gallery)
        if imageHigh == filename {
            imageHigh = gallery.first ?? ""
            notifyRendererChanged()
        }
    }

    private var currentUsedPct: Double {
        UserDefaults.standard.double(forKey: "ccmaxok_five_hour_used_pct")
    }

    private func applyStatusEffect(to image: NSImage, remainPct: Double) -> NSImage {
        let tm = ThemeManager.shared
        switch remainPct {
        case 80...:
            return tm.applyBrightness(image, amount: 0.05)
        case 50..<80:
            return image
        case 20..<50:
            return tm.applySaturation(image, amount: 0.5)
        default:
            let gray = tm.applyGrayscale(image)
            return tm.applyOpacity(gray, opacity: 0.6)
        }
    }

    private func notifyRendererChanged() {
        NotificationCenter.default.post(name: .rendererSettingsChanged, object: nil)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    private var wrappedStatusline: String? {
        StatuslineSetup.wrappedCommand(fileAccess: FileAccessManager())
    }

    private func copyLogToClipboard() {
        let lines = DiagnosticsLogger.shared.recentEntries(limit: 500)
        let header = diagnosticsHeader()
        let body = lines.isEmpty ? "(로그가 비어 있습니다)" : lines.joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("\(header)\n\n\(body)", forType: .string)
    }

    private func openGithubIssueWithDiagnostics() {
        let title = "[bug] 사용량 표시 문제"
        let lines = DiagnosticsLogger.shared.recentEntries(limit: 40)
        let logBlock = lines.isEmpty ? "(로그가 비어 있습니다)" : lines.joined(separator: "\n")
        let body = """
        \(diagnosticsHeader())

        **증상 / 재현 방법**

        (여기에 메뉴바·팝업에서 관찰된 현상을 적어주세요)

        **최근 로그 (\(lines.count)줄)**

        ```
        \(logBlock)
        ```
        """
        var components = URLComponents(string: "https://github.com/JuyeonYu/haru/issues/new")!
        components.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "body", value: body)
        ]
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }

    private func diagnosticsHeader() -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osStr = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        return """
        **버전**: \(appVersion) (\(appBuild)) · core \(CCMaxOKCore.version)
        **macOS**: \(osStr)
        **로그 경로**: `\(DiagnosticsLogger.shared.logFileURL.path)`
        """
    }

    private var blockPreview: String {
        let pct = 72
        let filled = pct * blockSegments / 100
        let empty = blockSegments - filled
        var result = String(repeating: blockFilled, count: filled) + String(repeating: blockEmpty, count: empty)
        if blockShowPercent {
            result += " \(pct)%"
        }
        return String(localized: "미리보기: \(result)")
    }

}

extension Notification.Name {
    static let rendererSettingsChanged = Notification.Name("rendererSettingsChanged")
}
