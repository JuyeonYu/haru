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

    @State private var facePickerData: FacePickerData?
    @State private var pendingSlot: String = ""

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

                Toggle("리셋 시간 표시", isOn: $showResetTime)
                    .onChange(of: showResetTime) { _, _ in notifyRendererChanged() }

            }

            if rendererId == "simple" {
                Section("Simple 옵션") {
                    Picker("아이콘", selection: $simpleIcon) {
                        ForEach(simpleIconOptions, id: \.icon) { opt in
                            Text("\(opt.icon) \(opt.label)").tag(opt.icon)
                        }
                    }
                    .onChange(of: simpleIcon) { _, _ in notifyRendererChanged() }

                    Toggle("커스텀 이미지 사용", isOn: $simpleUseCustomImage)
                        .onChange(of: simpleUseCustomImage) { _, _ in notifyRendererChanged() }

                    if simpleUseCustomImage {
                        imageRow(label: "이미지", filename: imageHigh, slot: "high")

                        Picker("마스크", selection: $imageMask) {
                            Text("없음").tag("none")
                            Text("원형").tag("circle")
                            Text("둥근 사각형").tag("roundedRect")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: imageMask) { _, _ in notifyRendererChanged() }
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
                            Text(set.label).tag(set.filled)
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
                        imageRow(label: "이미지", filename: imageHigh, slot: "high")

                        Picker("마스크", selection: $imageMask) {
                            Text("없음").tag("none")
                            Text("원형").tag("circle")
                            Text("둥근 사각형").tag("roundedRect")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: imageMask) { _, _ in notifyRendererChanged() }
                    }
                }
            }

        }
        .formStyle(.grouped)
        .frame(width: 450, height: 500)
        .sheet(item: $facePickerData) { data in
            FacePickerSheet(candidates: data.candidates) { selected in
                facePickerData = nil
                saveImageToSlot(selected, slot: pendingSlot)
            }
        }
    }

    private func pickAndSaveImage(slot: String) {
        DispatchQueue.main.async {
            self._pickAndSaveImage(slot: slot)
        }
    }

    private func _pickAndSaveImage(slot: String) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url,
              let originalImage = NSImage(contentsOf: url) else { return }

        let faces = FaceCropper.detectFaces(in: originalImage)

        if faces.count > 1 {
            // 얼굴 선택용 미리보기는 마스크 없이 크롭
            let candidates = faces.compactMap { rect in
                FaceCropper.cropFace(from: originalImage, faceRect: rect, mask: .none)
            }
            if candidates.count > 1 {
                pendingSlot = slot
                facePickerData = FacePickerData(candidates: candidates)
                return
            }
        }

        // 0~1개 얼굴 또는 크롭 실패 → 마스크 없이 저장
        let imageToSave: NSImage
        if let first = faces.first,
           let cropped = FaceCropper.cropFace(from: originalImage, faceRect: first, mask: .none) {
            imageToSave = cropped
        } else {
            imageToSave = originalImage
        }
        saveImageToSlot(imageToSave, slot: slot)
    }

    private func saveImageToSlot(_ image: NSImage, slot: String) {
        let tm = ThemeManager.shared
        let processed = image
        guard let filename = tm.saveImage(processed, name: "user_\(slot)") else { return }

        switch slot {
        case "high": imageHigh = filename
        case "mid": imageMid = filename
        case "low": imageLow = filename
        default: break
        }

        notifyRendererChanged()
    }

    @ViewBuilder
    private func imageRow(label: String, filename: String, slot: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            if !filename.isEmpty {
                maskedThumbnail(filename: filename, height: 32)
            }
            Button(filename.isEmpty ? "선택..." : "변경...") {
                pickAndSaveImage(slot: slot)
            }
            if !filename.isEmpty {
                Button("삭제") {
                    switch slot {
                    case "high": imageHigh = ""
                    case "mid": imageMid = ""
                    case "low": imageLow = ""
                    default: break
                    }
                    notifyRendererChanged()
                }
            }
        }
    }

    @ViewBuilder
    private func maskedThumbnail(filename: String, height: CGFloat) -> some View {
        let mask = FaceCropper.MaskShape(rawValue: imageMask) ?? .none
        if let img = ThemeManager.shared.loadImage(named: filename) {
            let masked = FaceCropper.applyShapeMask(to: img, mask: mask)
            let resized = ThemeManager.shared.resizeForMenuBar(masked, height: height)
            Image(nsImage: resized)
        }
    }

    private func notifyRendererChanged() {
        NotificationCenter.default.post(name: .rendererSettingsChanged, object: nil)
    }

    private var blockPreview: String {
        let pct = 72
        let filled = pct * blockSegments / 100
        let empty = blockSegments - filled
        var result = String(repeating: blockFilled, count: filled) + String(repeating: blockEmpty, count: empty)
        if blockShowPercent {
            result += " \(pct)%"
        }
        return "미리보기: \(result)"
    }

}

extension Notification.Name {
    static let rendererSettingsChanged = Notification.Name("rendererSettingsChanged")
}
