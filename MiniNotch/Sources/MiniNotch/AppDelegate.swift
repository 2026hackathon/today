import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NotchPanel?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // accessory 模式：不占 Dock、不出现在 ⌘Tab 切换里
        NSApp.setActivationPolicy(.accessory)

        setupStatusBar()
        showPanel()
    }

    // MARK: - 菜单栏

    private func setupStatusBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.topthird.inset.filled",
                accessibilityDescription: "MiniNotch"
            )
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "显示/隐藏面板", action: #selector(togglePanel), keyEquivalent: "t")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 MiniNotch", action: #selector(quitApp), keyEquivalent: "q")
        item.menu = menu

        self.statusItem = item
    }

    // MARK: - 刘海面板

    private func showPanel() {
        guard let screen = NSScreen.main else { return }

        let notchSize = NotchGeometry.notchSize(on: screen)
        let expandedSize = CGSize(width: 380, height: 320)
        let panelFrame = NotchGeometry.panelFrame(on: screen, panelSize: expandedSize)

        let panel = NotchPanel(contentRect: panelFrame)
        let hostingView = NSHostingView(
            rootView: NotchView(notchSize: notchSize, expandedSize: expandedSize)
        )
        hostingView.frame = NSRect(origin: .zero, size: expandedSize)
        panel.contentView = hostingView

        panel.setFrame(panelFrame, display: true)
        panel.orderFrontRegardless()

        self.panel = panel
    }

    // MARK: - Actions

    @objc private func togglePanel() {
        guard let panel = panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
