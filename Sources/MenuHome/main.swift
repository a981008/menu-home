import AppKit

// MenuHome 入口：无 Dock 图标的常驻状态栏应用
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
