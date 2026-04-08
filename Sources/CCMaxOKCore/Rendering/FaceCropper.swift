import AppKit
import Vision

public enum FaceCropper {

    public enum MaskShape: String, CaseIterable, Sendable {
        case none
        case circle
        case roundedRect
    }

    /// 이미지에서 사람 얼굴 또는 동물을 감지한다.
    /// 사람 얼굴 우선, 없으면 동물 감지. 감지 실패 시 빈 배열.
    public static func detectFaces(in image: NSImage) -> [CGRect] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }

        // 1. 사람 얼굴 감지
        let faceRequest = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([faceRequest])

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)

        if let results = faceRequest.results, !results.isEmpty {
            return results.map { convertBoundingBox($0.boundingBox, imageSize: imageSize) }
        }

        // 2. 동물 감지 (사람 없을 때)
        let animalRequest = VNRecognizeAnimalsRequest()
        try? handler.perform([animalRequest])

        if let results = animalRequest.results, !results.isEmpty {
            return results.compactMap { observation in
                observation.labels.isEmpty ? nil : convertBoundingBox(observation.boundingBox, imageSize: imageSize)
            }
        }

        return []
    }

    /// Vision 정규화 좌표(좌하단 원점, 0~1) → 픽셀 좌표(좌상단 원점)
    private static func convertBoundingBox(_ box: CGRect, imageSize: CGSize) -> CGRect {
        CGRect(
            x: box.origin.x * imageSize.width,
            y: (1 - box.origin.y - box.height) * imageSize.height,
            width: box.width * imageSize.width,
            height: box.height * imageSize.height
        )
    }

    /// 얼굴 영역을 여백 포함해서 크롭한다.
    public static func cropFace(from image: NSImage, faceRect: CGRect, padding: CGFloat = 0.3, mask: MaskShape = .none) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let imageW = CGFloat(cgImage.width)
        let imageH = CGFloat(cgImage.height)

        // 여백 추가
        let padW = faceRect.width * padding
        let padH = faceRect.height * padding
        var expanded = faceRect.insetBy(dx: -padW, dy: -padH)

        // 정사각형으로 맞추기
        let side = max(expanded.width, expanded.height)
        expanded = CGRect(
            x: expanded.midX - side / 2,
            y: expanded.midY - side / 2,
            width: side,
            height: side
        )

        // 이미지 범위 클램프
        expanded = expanded.intersection(CGRect(x: 0, y: 0, width: imageW, height: imageH))

        guard let cropped = cgImage.cropping(to: expanded) else { return nil }
        let croppedImage = NSImage(cgImage: cropped, size: NSSize(width: expanded.width, height: expanded.height))

        switch mask {
        case .none:
            return croppedImage
        case .circle:
            return applyMask(to: croppedImage, cornerRadius: expanded.width / 2)
        case .roundedRect:
            return applyMask(to: croppedImage, cornerRadius: expanded.width * 0.2)
        }
    }

    /// 첫 번째 얼굴을 자동으로 감지 + 크롭하는 편의 메서드
    public static func autoCrop(image: NSImage, mask: MaskShape = .none) -> NSImage? {
        let faces = detectFaces(in: image)
        guard let first = faces.first else { return nil }
        return cropFace(from: image, faceRect: first, mask: mask)
    }

    /// 이미지에 마스크 형태를 적용한다.
    public static func applyShapeMask(to image: NSImage, mask: MaskShape) -> NSImage {
        switch mask {
        case .none: return image
        case .circle: return applyMask(to: image, cornerRadius: image.size.width / 2)
        case .roundedRect: return applyMask(to: image, cornerRadius: image.size.width * 0.2)
        }
    }

    private static func applyMask(to image: NSImage, cornerRadius: CGFloat) -> NSImage {
        let size = image.size
        let result = NSImage(size: size)
        result.lockFocus()

        let path = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: cornerRadius, yRadius: cornerRadius)
        path.addClip()
        image.draw(in: NSRect(origin: .zero, size: size))

        result.unlockFocus()
        return result
    }
}
