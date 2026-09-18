import AppKit
import SwiftUI

/// 可以成为 key window 的无边框面板（无边框窗口默认不能成为 key，否则收不到键盘）
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// 主面板控制器：弹出/定位/失焦关闭 + 面板内的键盘与滚轮处理
@MainActor
final class PanelController: NSObject, NSWindowDelegate {

    private let store: HomeStore
    private let panel: KeyablePanel
    private var lastIconFrame: NSRect = .zero

    private var scrollAccum: CGFloat = 0
    private var keyMonitor: Any?
    private var scrollMonitor: Any?

    init(store: HomeStore) {
        self.store = store
        let m = store.metrics
        self.panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: m.pageW, height: m.panelH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: HomeView().environmentObject(store))

        installMonitors()
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
    }

    // MARK: - 显隐与定位

    func toggle(statusIconFrame: NSRect) {
        if panel.isVisible {
            hide()
        } else {
            lastIconFrame = statusIconFrame
            resize(to: store.metrics)
            positionPanel()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func hide() {
        store.resetTransientState()
        panel.orderOut(nil)
    }

    func resize(to metrics: GridMetrics) {
        panel.setContentSize(NSSize(width: metrics.pageW, height: metrics.panelH))
        if panel.isVisible { positionPanel() }
    }

    private func positionPanel() {
        let screen = NSScreen.screens.first { $0.frame.contains(lastIconFrame.origin) } ?? NSScreen.main
        guard let screen else { return }
        let w = panel.frame.width
        let h = panel.frame.height
        var x = lastIconFrame.midX - w / 2
        x = max(screen.visibleFrame.minX + 8, min(x, screen.visibleFrame.maxX - w - 8))
        let y = lastIconFrame.minY - 6 - h
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - 失焦自动关闭（点击面板外 = 关闭）

    func windowDidResignKey(_ notification: Notification) {
        if panel.isVisible { hide() }
    }

    // MARK: - 面板内键盘 / 滚轮

    private func installMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated {
                guard self.panel.isVisible, NSApp.keyWindow === self.panel else { return event }
                return self.handleKey(event) ?? event
            }
        }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated {
                guard self.panel.isVisible, NSApp.keyWindow === self.panel else { return event }
                guard !self.store.searchActive,
                      self.store.addTarget == nil,
                      self.store.expandedFolderID == nil else { return event }
                if !event.momentumPhase.isEmpty { return event }
                self.scrollAccum += event.scrollingDeltaX + event.scrollingDeltaY
                if self.scrollAccum >= 25 {
                    self.scrollAccum = 0
                    self.store.changePage(by: -1)
                } else if self.scrollAccum <= -25 {
                    self.scrollAccum = 0
                    self.store.changePage(by: 1)
                }
                return event
            }
        }
    }

    /// 返回 nil 表示吞掉该按键
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        // Esc：逐级回退（搜索 → 添加 → 重命名 → 文件夹 → 编辑模式 → 关面板）
        if event.keyCode == 53 {
            if store.searchActive {
                store.closeSearch()
            } else if store.addTarget != nil {
                store.addTarget = nil
            } else if store.renamingFolderID != nil {
                store.renamingFolderID = nil
            } else if store.expandedFolderID != nil {
                store.collapseFolder()
            } else if store.editMode {
                store.editMode = false
            } else {
                hide()
            }
            return nil
        }

        // 文本框有焦点（搜索/重命名）时，其余按键交给输入框
        if panel.firstResponder is NSTextView {
            return event
        }

        let chars = event.charactersIgnoringModifiers ?? ""
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // ⌘F 打开搜索覆盖层
        if mods.contains(.command), chars.lowercased() == "f" {
            if !store.searchActive, store.addTarget == nil, store.expandedFolderID == nil {
                store.openSearch(seed: "")
                return nil
            }
            return event
        }

        // ⌘← / ⌘→ 翻页
        if mods.contains(.command), event.keyCode == 123 {
            store.changePage(by: -1)
            return nil
        }
        if mods.contains(.command), event.keyCode == 124 {
            store.changePage(by: 1)
            return nil
        }

        // ⌘, 打开设置
        if mods.contains(.command), chars == "," {
            store.onOpenSettings?()
            return nil
        }

        // 任意字符 → 直接搜索（面板打开后敲键盘即搜）
        if !store.searchActive, store.addTarget == nil, store.expandedFolderID == nil, !store.editMode,
           chars.count == 1, let c = chars.first,
           c.isLetter || c.isNumber || "!@#$%^&*()-_=+.,;:'\"/?\\| ".contains(c) {
            store.openSearch(seed: chars)
            return nil
        }

        return event
    }
}
