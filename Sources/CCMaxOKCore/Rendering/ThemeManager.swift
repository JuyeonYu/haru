import AppKit
import Foundation

public final class ThemeManager: Sendable {
    public static let shared = ThemeManager()

    private let themesDir: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        themesDir = appSupport.appendingPathComponent("CCMaxOK/themes", isDirectory: true)
        try? FileManager.default.createDirectory(at: themesDir, withIntermediateDirectories: true)
    }

    // MARK: - 이미지 저장/로드

    /// 이미지를 저장하고 파일명을 반환한다.
    public func saveImage(_ image: NSImage, name: String) -> String? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }

        let filename = "\(name).png"
        let url = themesDir.appendingPathComponent(filename)
        do {
            try png.write(to: url)
            return filename
        } catch {
            return nil
        }
    }

    /// 저장된 이미지를 로드한다.
    public func loadImage(named filename: String) -> NSImage? {
        let url = themesDir.appendingPathComponent(filename)
        return NSImage(contentsOf: url)
    }

    /// 메뉴바 크기(22pt)에 맞게 리사이즈한다.
    public func resizeForMenuBar(_ image: NSImage, height: CGFloat = 22) -> NSImage {
        let aspect = image.size.width / image.size.height
        let newSize = NSSize(width: height * aspect, height: height)
        let resized = NSImage(size: newSize)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .sourceOver,
                   fraction: 1.0)
        resized.unlockFocus()
        resized.isTemplate = false
        return resized
    }

    // MARK: - 이미지 효과

    /// opacity 적용
    public func applyOpacity(_ image: NSImage, opacity: CGFloat) -> NSImage {
        let result = NSImage(size: image.size)
        result.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: image.size),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .sourceOver,
                   fraction: opacity)
        result.unlockFocus()
        result.isTemplate = false
        return result
    }

    /// grayscale 변환
    public func applyGrayscale(_ image: NSImage) -> NSImage {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let ciImage = CIImage(bitmapImageRep: rep) else { return image }

        let filter = CIFilter(name: "CIColorMonochrome")!
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIColor(red: 0.7, green: 0.7, blue: 0.7), forKey: "inputColor")
        filter.setValue(1.0, forKey: "inputIntensity")

        guard let output = filter.outputImage else { return image }
        let ciContext = CIContext()
        guard let cgImage = ciContext.createCGImage(output, from: output.extent) else { return image }

        let result = NSImage(cgImage: cgImage, size: image.size)
        result.isTemplate = false
        return result
    }

    // MARK: - 세그먼트 합성

    /// 이미지를 N칸 세그먼트로 합성한다. filled 개수만 원본, 나머지는 dimmed.
    public func compositeSegments(image: NSImage, segments: Int, filledCount: Int, height: CGFloat = 18) -> NSImage {
        let cellSize = NSSize(width: height, height: height)
        let spacing: CGFloat = 2
        let totalWidth = CGFloat(segments) * (cellSize.width + spacing) - spacing
        let result = NSImage(size: NSSize(width: totalWidth, height: height))

        let resized = resizeForMenuBar(image, height: height)
        let dimmed = applyOpacity(resized, opacity: 0.25)

        result.lockFocus()
        for i in 0..<segments {
            let x = CGFloat(i) * (cellSize.width + spacing)
            let rect = NSRect(origin: NSPoint(x: x, y: 0), size: cellSize)
            let img = i < filledCount ? resized : dimmed
            img.draw(in: rect)
        }
        result.unlockFocus()
        result.isTemplate = false
        return result
    }
}
