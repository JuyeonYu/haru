import AppKit
import Foundation

public struct SimpleRenderer: UsageRenderer {
    public let id = "simple"
    public let displayName = "Simple"
    public let previewText = "⬤ 85%"

    public init() {}

    public var isCustomImage: Bool {
        UserDefaults.standard.bool(forKey: "simple_use_custom_image")
    }

    public var icon: String {
        UserDefaults.standard.string(forKey: "simple_icon") ?? "⬤"
    }

    public func render(context: RenderContext) -> RenderedOutput {
        let pct = Int(context.remainPct)

        if isCustomImage {
            return renderWithImage(pct: pct, remainPct: context.remainPct)
        }

        return .text("\(icon) \(pct)%")
    }

    private func renderWithImage(pct: Int, remainPct: Double) -> RenderedOutput {
        let tm = ThemeManager.shared
        let mask = FaceCropper.MaskShape(rawValue: UserDefaults.standard.string(forKey: "image_mask") ?? "circle") ?? .circle

        let imageFile = UserDefaults.standard.string(forKey: "image_high") ?? ""

        guard !imageFile.isEmpty, var img = tm.loadImage(named: imageFile) else {
            return .symbolAndText(symbol: "photo", text: "\(pct)%")
        }

        // 잔여량 기반 이미지 효과
        switch remainPct {
        case 80...:
            // 여유: 밝게
            img = tm.applyBrightness(img, amount: 0.05)
        case 50..<80:
            // 보통: 원본
            break
        case 20..<50:
            // 주의: 채도 낮춤
            img = tm.applySaturation(img, amount: 0.5)
        default:
            // 위험: 흑백 + 흐림
            img = tm.applyGrayscale(img)
            img = tm.applyOpacity(img, opacity: 0.6)
        }

        img = FaceCropper.applyShapeMask(to: img, mask: mask)
        let resized = tm.resizeForMenuBar(img)
        return .imageAndText(image: resized, text: "\(pct)%")
    }
}
