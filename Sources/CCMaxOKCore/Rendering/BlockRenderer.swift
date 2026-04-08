import AppKit
import Foundation

public struct BlockRenderer: UsageRenderer {
    public let id = "block"
    public let displayName = "Block"
    public let previewText = "■■■■■■■■□□ 85%"

    public init() {}

    public var segments: Int {
        let val = UserDefaults.standard.integer(forKey: "block_segment_count")
        return val > 0 ? val : 10
    }

    public var filledChar: String {
        UserDefaults.standard.string(forKey: "block_filled_char") ?? "■"
    }

    public var emptyChar: String {
        UserDefaults.standard.string(forKey: "block_empty_char") ?? "□"
    }

    public var showPercent: Bool {
        if UserDefaults.standard.object(forKey: "block_show_percent") == nil { return true }
        return UserDefaults.standard.bool(forKey: "block_show_percent")
    }

    public var isCustomImage: Bool {
        filledChar == "__custom_image__"
    }

    public func render(context: RenderContext) -> RenderedOutput {
        let pct = Int(context.remainPct)
        let filled = pct * segments / 100

        if isCustomImage {
            return renderWithImage(pct: pct, filledCount: filled)
        }

        let empty = segments - filled
        var result = String(repeating: filledChar, count: filled) + String(repeating: emptyChar, count: empty)
        if showPercent {
            result += " \(pct)%"
        }
        return .text(result)
    }

    private func renderWithImage(pct: Int, filledCount: Int) -> RenderedOutput {
        let tm = ThemeManager.shared
        let imageFile = UserDefaults.standard.string(forKey: "image_high") ?? ""
        let mask = FaceCropper.MaskShape(rawValue: UserDefaults.standard.string(forKey: "image_mask") ?? "circle") ?? .circle

        guard !imageFile.isEmpty, var image = tm.loadImage(named: imageFile) else {
            return .symbolAndText(symbol: "photo", text: "\(pct)%")
        }

        image = FaceCropper.applyShapeMask(to: image, mask: mask)
        let composite = tm.compositeSegments(image: image, segments: segments, filledCount: filledCount)

        if showPercent {
            return .imageAndText(image: composite, text: "\(pct)%")
        } else {
            return .imageOnly(image: composite)
        }
    }
}
