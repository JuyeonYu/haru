import AppKit
import CoreImage
import Foundation

public final class ThemeManager: @unchecked Sendable {
    public static let shared = ThemeManager()

    private let themesDir: URL
    private let imageCache = NSCache<NSString, NSImage>()
    private let ciContext = CIContext()

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        themesDir = appSupport.appendingPathComponent("CCMaxOK/themes", isDirectory: true)
        try? FileManager.default.createDirectory(at: themesDir, withIntermediateDirectories: true)
        imageCache.countLimit = 50
    }

    /// 이미지 캐시를 무효화한다.
    public func clearImageCache() {
        imageCache.removeAllObjects()
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

    /// 고유 이름으로 이미지를 저장하고 파일명을 반환한다.
    public func saveImageUnique(_ image: NSImage, prefix: String = "face") -> String? {
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        return saveImage(image, name: "\(prefix)_\(timestamp)")
    }

    /// 저장된 이미지를 로드한다 (캐시 사용).
    public func loadImage(named filename: String) -> NSImage? {
        let key = filename as NSString
        if let cached = imageCache.object(forKey: key) {
            return cached
        }
        let url = themesDir.appendingPathComponent(filename)
        guard let image = NSImage(contentsOf: url) else { return nil }
        imageCache.setObject(image, forKey: key)
        return image
    }

    /// 저장된 이미지를 삭제한다.
    public func deleteImage(named filename: String) {
        imageCache.removeObject(forKey: filename as NSString)
        let url = themesDir.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }

    /// 메뉴바 크기(22pt)에 맞게 리사이즈한다.
    public func resizeForMenuBar(_ image: NSImage, height: CGFloat = 22) -> NSImage {
        let aspect = image.size.width / image.size.height
        let newSize = NSSize(width: height * aspect, height: height)
        let resized = NSImage(size: newSize, flipped: false) { rect in
            image.draw(in: rect,
                       from: NSRect(origin: .zero, size: image.size),
                       operation: .sourceOver,
                       fraction: 1.0)
            return true
        }
        resized.isTemplate = false
        return resized
    }

    // MARK: - 이미지 효과

    /// opacity 적용
    public func applyOpacity(_ image: NSImage, opacity: CGFloat) -> NSImage {
        let result = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect,
                       from: NSRect(origin: .zero, size: image.size),
                       operation: .sourceOver,
                       fraction: opacity)
            return true
        }
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
        guard let cgImage = ciContext.createCGImage(output, from: output.extent) else { return image }

        let result = NSImage(cgImage: cgImage, size: image.size)
        result.isTemplate = false
        return result
    }

    /// 밝기 조정 (-1.0 ~ 1.0)
    public func applyBrightness(_ image: NSImage, amount: Double) -> NSImage {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let ciImage = CIImage(bitmapImageRep: rep) else { return image }

        let filter = CIFilter(name: "CIColorControls")!
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(amount, forKey: kCIInputBrightnessKey)

        guard let output = filter.outputImage else { return image }
        guard let cgImage = ciContext.createCGImage(output, from: output.extent) else { return image }

        let result = NSImage(cgImage: cgImage, size: image.size)
        result.isTemplate = false
        return result
    }

    /// 채도 조정 (0.0 = 흑백, 1.0 = 원본, 2.0 = 과채도)
    public func applySaturation(_ image: NSImage, amount: Double) -> NSImage {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let ciImage = CIImage(bitmapImageRep: rep) else { return image }

        let filter = CIFilter(name: "CIColorControls")!
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(amount, forKey: kCIInputSaturationKey)

        guard let output = filter.outputImage else { return image }
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

        let resized = resizeForMenuBar(image, height: height)
        let dimmed = applyOpacity(resized, opacity: 0.25)

        let result = NSImage(size: NSSize(width: totalWidth, height: height), flipped: false) { _ in
            for i in 0..<segments {
                let x = CGFloat(i) * (cellSize.width + spacing)
                let rect = NSRect(origin: NSPoint(x: x, y: 0), size: cellSize)
                let img = i < filledCount ? resized : dimmed
                img.draw(in: rect)
            }
            return true
        }
        result.isTemplate = false
        return result
    }
}
