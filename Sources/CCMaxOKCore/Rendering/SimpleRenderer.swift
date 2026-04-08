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

        if remainPct <= 20 {
            img = tm.applyGrayscale(img)
        }
        let opacity = max(0.3, remainPct / 100)
        img = tm.applyOpacity(img, opacity: opacity)
        img = FaceCropper.applyShapeMask(to: img, mask: mask)
        let resized = tm.resizeForMenuBar(img)
        return .imageAndText(image: resized, text: "\(pct)%")
    }
}
