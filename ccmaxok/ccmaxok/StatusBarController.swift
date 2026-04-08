import AppKit
import SwiftUI
import CCMaxOKCore

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()

        setupPopover()
        updateIcon()

        NotificationCenter.default.addObserver(
            forName: .rendererSettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateIcon()
        }
    }

    // MARK: - Popover

    private func setupPopover() {
        popover.contentSize = NSSize(width: 320, height: 400)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(state: appState).frame(width: 320)
        )

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Icon Rendering

    func updateIcon() {
        guard let button = statusItem.button else { return }

        // 이전 상태 클리어
        button.image = nil
        button.title = ""
        button.imagePosition = .imageLeading

        guard appState.isConnected else {
            button.attributedTitle = NSAttributedString(
                string: "⬤ —",
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                    .foregroundColor: NSColor.tertiaryLabelColor
                ]
            )
            return
        }

        let renderer = RendererRegistry.renderer(
            forId: UserDefaults.standard.string(forKey: "renderer_id") ?? "simple"
        )
        let output = renderer.render(context: makeRenderContext())

        let resetTime = UserDefaults.standard.bool(forKey: "show_reset_time")
        let resetSuffix = resetTime ? " ↻\(RenderHelpers.shortTime(appState.fiveHourResetsAt))" : ""

        switch output {
        case .text(let text):
            let fullText = text + resetSuffix
            let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            let attributed = NSMutableAttributedString(string: fullText, attributes: [.font: font])

            // Block 렌더러: 채움/빈칸 이모지 크기 균일화
            let emptyChar = UserDefaults.standard.string(forKey: "block_empty_char") ?? "□"
            let filledChar = UserDefaults.standard.string(forKey: "block_filled_char") ?? "■"
            if !emptyChar.isEmpty && filledChar != "__custom_image__" {
                let nsString = fullText as NSString
                // 빈칸 이모지에 살짝 작은 폰트 + 베이스라인 보정
                let smallFont = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .regular)
                var searchRange = NSRange(location: 0, length: nsString.length)
                while searchRange.location < nsString.length {
                    let foundRange = nsString.range(of: emptyChar, range: searchRange)
                    guard foundRange.location != NSNotFound else { break }
                    attributed.addAttributes([.font: smallFont, .baselineOffset: 0.5], range: foundRange)
                    searchRange.location = foundRange.location + foundRange.length
                    searchRange.length = nsString.length - searchRange.location
                }
            }

            // 리셋 아이콘(↻) 크기 보정
            let nsFullString = fullText as NSString
            let arrowRange = nsFullString.range(of: "↻")
            if arrowRange.location != NSNotFound {
                attributed.addAttribute(.font, value: NSFont.systemFont(ofSize: 13, weight: .regular), range: arrowRange)
            }

            // Simple: 아이콘 색상 + 크기 적용
            if let firstChar = fullText.first,
               "●◆▲⬤■⚡🔴🟡🟢".contains(firstChar) || firstChar.unicodeScalars.first?.value ?? 0 > 127 {
                let iconRange = NSRange(location: 0, length: String(firstChar).utf16.count)
                attributed.addAttribute(.foregroundColor, value: alertColor(), range: iconRange)
                // ■는 기본 폰트에서 작게 보이므로 키움
                if firstChar == "■" {
                    attributed.addAttribute(.font, value: NSFont.systemFont(ofSize: 15, weight: .regular), range: iconRange)
                    attributed.addAttribute(.baselineOffset, value: -1.5, range: iconRange)
                }
            }
            button.attributedTitle = attributed

        case .symbolAndText(let symbol, let text):
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
            if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                let tint = alertColor()
                let size: CGFloat = 12
                let colored = NSImage(size: NSSize(width: size, height: size))
                colored.lockFocus()
                tint.set()
                let rect = NSRect(x: 0, y: 0, width: size, height: size)
                img.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
                rect.fill(using: .sourceAtop)
                colored.unlockFocus()
                colored.isTemplate = false
                button.image = colored
            }
            button.title = text + resetSuffix

        case .imageAndText(let nsImage, let text):
            button.image = nsImage
            button.imagePosition = .imageLeading
            button.title = text + resetSuffix

        case .imageOnly(let nsImage):
            button.image = nsImage
            button.title = resetSuffix
        }
    }

    // MARK: - Helpers

    private func alertColor() -> NSColor {
        let remainPct = max(0, 100 - appState.fiveHourUsedPct)
        if remainPct <= 0 { return .systemRed }
        if remainPct < 50 { return .systemYellow }
        return .systemGreen
    }

    private func makeRenderContext() -> RenderContext {
        RenderContext(
            remainPct: max(0, 100 - appState.fiveHourUsedPct),
            sevenDayRemainPct: max(0, 100 - appState.sevenDayUsedPct),
            fiveHourResetsAt: appState.fiveHourResetsAt,
            sevenDayResetsAt: appState.sevenDayResetsAt,
            alertLevel: appState.fiveHourAlertLevel
        )
    }
}

