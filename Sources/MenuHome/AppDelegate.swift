import AppKit

/// 应用装配：状态栏图标、面板、设置窗口、全局热键
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let store = HomeStore()

    private var statusItem: NSStatusItem?
    private var panelController: PanelController?
    private var settingsController: SettingsWindowController?
    private var statusMenuDelegate: StatusMenuDelegate?

    private let statusMenu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 状态中枢回调接线
        store.onSettingsChanged = { [weak self] in
            guard let self else { return }
            self.panelController?.resize(to: self.store.metrics)
            self.registerHotKey()
        }
        store.onOpenSettings = { [weak self] in self?.showSettings() }
        store.onHidePanel = { [weak self] in self?.panelController?.hide() }

        panelController = PanelController(store: store)

        setupStatusItem()
        setupStatusMenu()
        RunningMonitor.start(store: store)
        registerHotKey()
    }

    // MARK: - 状态栏图标

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = StatusIcon.appIcon()
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "MenuHome"
        }
        statusItem = item
    }

    private func setupStatusMenu() {
        let open = statusMenu.addItem(withTitle: "打开面板", action: #selector(openPanelFromMenu), keyEquivalent: "")
        open.target = self
        statusMenu.addItem(.separator())
        let settings = statusMenu.addItem(withTitle: "设置…", action: #selector(showSettingsFromMenu), keyEquivalent: ",")
        settings.target = self
        let quit = statusMenu.addItem(withTitle: "退出 MenuHome", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
    }

    /// 左键 = 开/关面板；右键 = 快捷菜单
    @objc private func statusClicked() {
        guard let event = NSApp.currentEvent else {
            togglePanel()
            return
        }
        if event.type == .rightMouseUp || event.type == .otherMouseUp {
            // 临时挂上菜单（关闭后由 delegate 摘除，恢复左键行为）
            let delegate = StatusMenuDelegate { [weak self] in self?.statusItem?.menu = nil }
            statusMenuDelegate = delegate
            statusMenu.delegate = delegate
            statusItem?.menu = statusMenu
            statusItem?.button?.performClick(nil)
        } else {
            togglePanel()
        }
    }

    @objc private func openPanelFromMenu() { togglePanel() }
    @objc private func showSettingsFromMenu() { showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - 面板 / 设置 / 热键

    private func iconFrame() -> NSRect {
        guard let button = statusItem?.button, let window = button.window else { return .zero }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private func togglePanel() {
        panelController?.toggle(statusIconFrame: iconFrame())
    }

    private func showSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(store: store)
        }
        panelController?.hide()
        settingsController?.show()
    }

    private func registerHotKey() {
        let hk = store.settings.hotkey
        HotKeyCenter.shared.register(keyCode: hk.keyCode, modifiers: hk.modifiers) { [weak self] in
            MainActor.assumeIsolated { self?.togglePanel() }
        }
    }
}

/// 右键菜单关闭后摘除 statusItem.menu（否则左键也会弹菜单）
final class StatusMenuDelegate: NSObject, NSMenuDelegate {
    private let onEnd: () -> Void
    init(onEnd: @escaping () -> Void) { self.onEnd = onEnd }
    func menuDidClose(_ menu: NSMenu) { onEnd() }
}
