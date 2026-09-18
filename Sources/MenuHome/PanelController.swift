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

    private var keyMonitor: Any?

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
    }

    // MARK: - 显隐与定位（控制中心式弹出动画）

    /// 收起动画的延迟 orderOut 任务（非 nil = 正在收起）
    private var closeWork: DispatchWorkItem?

    func toggle(statusIconFrame: NSRect) {
        if panel.isVisible {
            if closeWork != nil {
                // 正在收起 → 反向弹回：closeWork 里挂着的 orderOut + resetTransientState
                // 会随 cancel 一并作废，必须在这里补复位，否则编辑模式/拖拽会话
                // 会原样带回面板（「重开后抖动残留」的根因）
                closeWork?.cancel()
                closeWork = nil
                store.resetTransientState()
                store.panelVisible = true
                refreshShadow()
            } else {
                hide()
            }
        } else {
            lastIconFrame = statusIconFrame
            resize(to: store.metrics)
            positionPanel()
            updateAnchor()
            closeWork?.cancel()
            closeWork = nil
            // 防御性复位：保证每次弹出都是干净状态（不依赖上次关闭路径是否执行了复位）
            store.resetTransientState()
            store.panelVisible = false          // 首帧以缩小 + 透明状态出现
            panel.makeKeyAndOrderFront(nil)
            refreshShadow()
            DispatchQueue.main.async { [weak self] in
                self?.store.panelVisible = true // 下一帧向图标锚点弹开
            }
        }
    }

    func hide() {
        guard closeWork == nil else { return }  // 已在收起动画中
        store.panelVisible = false              // 触发 SwiftUI 缩回动画
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.panel.orderOut(nil)
                self.store.resetTransientState()
                self.closeWork = nil
            }
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// 计算弹出锚点：状态栏图标在面板宽度上的相对位置
    private func updateAnchor() {
        let f = panel.frame
        guard f.width > 0 else { return }
        let rx = lastIconFrame == .zero
            ? 0.8
            : (lastIconFrame.midX - f.minX) / f.width
        store.panelAnchor = UnitPoint(x: min(0.85, max(0.15, rx)), y: 0)
    }

    /// 强制 AppKit 按当前内容可见形状重算窗口阴影。
    /// 无边框透明窗口的阴影形状会被缓存（首次采样常为整窗矩形），
    /// 不重算就会在圆角外留下直角阴影边界 —— 「圆角外矩形溢出」的根因。
    private func refreshShadow() {
        panel.invalidateShadow()
        // 首帧渲染与弹出缩放动画期间可见形状仍在变化，延迟补采样两次
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            MainActor.assumeIsolated { self?.panel.invalidateShadow() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            MainActor.assumeIsolated { self?.panel.invalidateShadow() }
        }
    }

    func resize(to metrics: GridMetrics) {
        panel.setContentSize(NSSize(width: metrics.pageW, height: metrics.panelH))
        if panel.isVisible {
            positionPanel()
            panel.invalidateShadow()
        }
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
        // 滚轮：桌面为原生滚动网格（不再分页），交给 ScrollView 自行处理
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
