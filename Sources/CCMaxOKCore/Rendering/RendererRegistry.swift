import Foundation

public enum RendererRegistry: Sendable {
    public static let allRenderers: [any UsageRenderer] = [
        SimpleRenderer(),
        BlockRenderer(),
    ]

    public static func renderer(forId id: String) -> any UsageRenderer {
        allRenderers.first { $0.id == id } ?? SimpleRenderer()
    }

    public static var current: any UsageRenderer {
        let id = UserDefaults.standard.string(forKey: "renderer_id") ?? "simple"
        return renderer(forId: id)
    }
}
