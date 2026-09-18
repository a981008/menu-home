import AppKit
import SwiftUI

/// 独立设置窗口（400×560，承载 SettingsView）
@MainActor
final class SettingsWindowController {

    private let store: HomeStore
    private var window: NSWindow?

    init(store: HomeStore) {
        self.store = store
    }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 560),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            w.title = "MenuHome 设置"
            w.isReleasedWhenClosed = false
            w.center()
            w.contentView = NSHostingView(rootView: SettingsView().environmentObject(store))
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
