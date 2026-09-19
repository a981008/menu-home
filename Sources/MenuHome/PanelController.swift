import AppKit
import SwiftUI

/// 可以成为 key window 的无边框面板（无边框窗口默认不能成为 key，否则收不到键盘）
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// 玻璃要贴住状态栏，窗口顶边（含阴影边距）必然上探进菜单栏区域；
    /// AppKit 在窗口显示（makeKeyAndOrderFront 等）时机会调 constrainFrameRect(_:to:)
    /// 把上探的顶边钳回 visibleFrame.maxY，整个窗口被下推一个边距（实测 y 1527→1487），
    /// 玻璃随之滑进菜单栏底下（「贴不上状态栏」的根因）。本面板自管几何，禁用钳制。
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// 面板宿主视图：玻璃区域以外（四周 shadowMargin 阴影边距）不做命中测试，
/// 点击穿透到下层内容 —— 「点面板外收起」的有效范围与玻璃可见边界保持一致
private final class PanelHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let glassRect = bounds.insetBy(dx: Theme.shadowMargin, dy: Theme.shadowMargin)
        return glassRect.contains(local) ? super.hitTest(point) : nil
    }

    override var safeAreaInsets: NSEdgeInsets {
        get {
            // 玻璃要贴住状态栏，窗口顶边必然上探进菜单栏区域（还要给手绘阴影留边距）；
            // 系统会按上探量给宿主视图顶部安全区 inset，把 SwiftUI 内容整体推低，
            // 表现为「面板贴不上状态栏、间隙 ≈ shadowMargin」。本面板自管几何，安全区清零。
            NSEdgeInsets()
        }
        set {}
    }
}

/// 主面板控制器：弹出/定位/失焦关闭 + 面板内的键盘与滚轮处理
@MainActor
final class PanelController: NSObject, NSWindowDelegate {

    private let store: HomeStore
    private let panel: KeyablePanel
    private var lastIconFrame: NSRect = .zero

    private var keyMonitor: Any?
    private var mouseUpMonitor: Any?

    init(store: HomeStore) {
        self.store = store
        let m = store.metrics
        self.panel = KeyablePanel(
            // 窗口比可见玻璃大一圈（四周 shadowMargin 透明边距）：容纳手绘阴影外溢
            contentRect: NSRect(x: 0, y: 0,
                                width: m.pageW + Theme.shadowMargin * 2,
                                height: m.panelH + Theme.shadowMargin * 2),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        // 系统窗口阴影不可用：无边框玻璃窗口的阴影形状被 AppKit 按整窗矩形采样
        // （invalidateShadow 重采样也无效），圆角外会出现直角阴影边界。
        // 阴影改由 HomeView 的 PanelShadowBackdrop 手绘（与玻璃同形、玻璃以内镂空），
        // 窗口四周的透明边距就是给它的外溢空间
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.contentView = PanelHostingView(rootView: HomeView().environmentObject(store))

        installMonitors()
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let mouseUpMonitor { NSEvent.removeMonitor(mouseUpMonitor) }
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
        // y 锚在玻璃顶边（窗口顶边向内缩 shadowMargin），x 仍按整窗宽换算
        store.panelAnchor = UnitPoint(x: min(0.85, max(0.15, rx)),
                                      y: Theme.shadowMargin / f.height)
    }

    func resize(to metrics: GridMetrics) {
        panel.setContentSize(NSSize(width: metrics.pageW + Theme.shadowMargin * 2,
                                    height: metrics.panelH + Theme.shadowMargin * 2))
        if panel.isVisible {
            positionPanel()
        }
    }

    private func positionPanel() {
        let screen = NSScreen.screens.first { $0.frame.contains(lastIconFrame.origin) } ?? NSScreen.main
        guard let screen else { return }
        let w = panel.frame.width
        let h = panel.frame.height
        var x = lastIconFrame.midX - w / 2
        x = max(screen.visibleFrame.minX + 8, min(x, screen.visibleFrame.maxX - w - 8))
        // 玻璃顶边 = 窗口顶边 - shadowMargin；窗口顶边锚定 visibleFrame.maxY
        // （AppKit 定义的菜单栏下缘，即状态栏底边），再上浮 statusBarGap ——
        // 玻璃悬停在状态栏下方一点而不直接压住（对齐控制中心式系统弹窗）。
        // 不用状态条按钮的 frame：其高度/在菜单栏内的位置随系统样式变化，对齐不稳定
        let y = screen.visibleFrame.maxY + Theme.shadowMargin - Theme.statusBarGap - h
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        dragDebugLog("position icon=\(lastIconFrame) visMaxY=\(screen.visibleFrame.maxY) y=\(y) h=\(h)")
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
        // 松手兜底：拖拽手势的 onEnded 若被取消/丢失（视图更新竞态等），
        // 会话将永久卡死 —— 表现为「能拖着走、永远放不下」。
        // 本地监视器在事件派发前执行；endDrag 幂等（drag 已空则无操作），
        // 与手势的 onEnded 双保险，松手必然落位。
        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated {
                if self.store.drag != nil {
                    dragDebugLog("mouseUp 兜底落位（手势 onEnded 未触发）")
                    self.store.endDrag()
                }
                return event
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
                store.exitEditMode()
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
