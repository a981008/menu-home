import Foundation
import AppKit
import SwiftUI

/// 全局状态中枢：桌面布局、设置、面板内瞬态（编辑/搜索/文件夹/添加/拖拽）
@MainActor
final class HomeStore: ObservableObject {

    // MARK: - Published 状态

    /// 桌面分页布局（页 → 项）
    @Published var pages: [[HomeItem]] = [[]] {
        didSet { schedulePersist() }
    }

    @Published var settings: AppSettings = AppSettings() {
        didSet {
            guard oldValue != settings else { return }
            persistNow()
            onSettingsChanged?()
        }
    }

    // 编辑模式（抖动）
    @Published var editMode = false
    // 整理模式多选（批量移除；退出整理/收起面板即清空）
    @Published var selectedIDs: Set<String> = []
    /// 长按进入整理模式后短暂压制格子 tap：长按松手的那次 click 不算点按
    /// （否则会误触启动 App / 切换多选）。非发布瞬态
    var suppressTapUntil: CFTimeInterval = 0

    // 面板显隐动画（控制中心式：从状态栏图标弹出/缩回）
    @Published var panelVisible = false
    /// 弹出动画锚点（状态栏图标相对面板的水平位置，0=左 1=右）
    @Published var panelAnchor = UnitPoint(x: 0.8, y: 0)

    // Finder 拖入 .app 悬停高亮
    @Published var dropTargeted = false

    // 文件夹展开覆盖层
    @Published var expandedFolderID: UUID?
    @Published var renamingFolderID: UUID?
    /// 展开来源：文件夹图标在面板坐标系中的矩形（iOS 式缩放动画的起点）
    @Published var folderSourceRect: CGRect = .zero

    // 搜索覆盖层
    @Published var searchActive = false
    /// 打开搜索层时带入的初始字符（键盘直入）
    @Published var searchSeedText = ""

    // 添加 App 覆盖层
    @Published var addTarget: AddTarget?

    // 正在运行 / 已缺失（路径失效）的 bundle id
    @Published var runningBundleIDs: Set<String> = []
    @Published var missingBundleIDs: Set<String> = []

    // 桌面拖拽会话（提起模型：只存结构性状态；高频光标位置在 ghost tracker）
    @Published var drag: DragSession?
    /// 拖影位置跟踪（独立 ObservableObject：鼠标移动只重渲染拖影，不触发整树重渲染）
    let ghost = GhostTracker()
    /// 拖动中的实时插入索引（非发布态；endDrag 用，避免逐事件发布）
    private var liveIndex = 0

    // 减弱动态效果
    @Published var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    // 启动失败弹窗
    @Published var launchFailure: AppEntry?

    // 由 AppDelegate 接线
    var onSettingsChanged: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onHidePanel: (() -> Void)?

    // MARK: - 持久化

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MenuHome", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("layout.json")
    }()

    init() {
        load()
    }

    private var persistWork: DispatchWorkItem?
    /// 拖拽期间被推迟的落盘请求
    private var persistPending = false

    private func schedulePersist() {
        persistWork?.cancel()
        // 拖拽期间不落盘：结束（放置/取消）后统一补写，避免拖动中途主线程 I/O
        guard drag == nil else {
            persistPending = true
            return
        }
        let wi = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // 触发时若又回到拖拽中（如 beginDrag 的 setFlat 先于 drag 赋值调度），继续顺延
            if self.drag != nil {
                self.persistPending = true
                return
            }
            self.persistNow()
        }
        persistWork = wi
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: wi)
    }

    /// 拖拽结束后补写被推迟的持久化
    private func flushPendingPersist() {
        guard persistPending else { return }
        persistPending = false
        schedulePersist()
    }

    private func persistNow() {
        let file = LayoutFile(version: 1, pages: pages, settings: settings)
        guard let data = try? JSONEncoder().encode(file) else { return }
        let url = fileURL
        // 写盘放后台队列：杜绝交互过程中的主线程 I/O 卡顿
        DispatchQueue.global(qos: .utility).async {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(LayoutFile.self, from: data) else {
            pages = [[]]
            return
        }
        // 旧版多页布局扁平迁移：合并为单列表（桌面已改为滚动，不分页）
        let merged = file.pages.flatMap { $0 }
        pages = [merged]
        settings = file.settings
        refreshMissing()
    }

    /// 关闭面板时清理面板内瞬态（由 PanelController.hide() 调用）
    func resetTransientState() {
        editMode = false
        selectedIDs = []
        expandedFolderID = nil
        renamingFolderID = nil
        if searchActive { closeSearch() }
        addTarget = nil
        if drag != nil { cancelDrag() }
    }

    /// 退出整理模式（清掉多选残留）
    func exitEditMode() {
        withAnimation { editMode = false }
        selectedIDs = []
    }

    /// 整理模式点选 / 取消多选
    func toggleSelected(id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    // MARK: - 栅格（单列表，超出可视行数即滚动）

    var metrics: GridMetrics { .make(columns: settings.columns, rows: settings.rows, iconSize: settings.iconSize) }
    var flatItems: [HomeItem] { pages.flatMap { $0 } }
    var isEmpty: Bool { flatItems.isEmpty }

    private func setFlat(_ items: [HomeItem]) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            pages = [items]
        }
    }

    // MARK: - 查询

    func item(withID id: String) -> HomeItem? {
        flatItems.first { $0.id == id }
    }

    func appEntry(withID id: String) -> AppEntry? {
        item(withID: id)?.appEntry
    }

    func folder(withID id: UUID) -> FolderEntry? {
        for it in flatItems {
            if case .folder(let f) = it, f.id == id { return f }
        }
        return nil
    }

    var allBundleIDs: Set<String> {
        var out: Set<String> = []
        func walk(_ items: [HomeItem]) {
            for it in items {
                switch it {
                case .app(let a): out.insert(a.bundleID)
                case .folder(let f): walk(f.items)
                }
            }
        }
        walk(flatItems)
        return out
    }

    private func flatIndexOf(id: String) -> Int? {
        flatItems.firstIndex { $0.id == id }
    }

    private func folderIndex(id: UUID, in items: [HomeItem]) -> Int? {
        items.firstIndex { item in
            if case .folder(let f) = item { return f.id == id }
            return false
        }
    }

    // MARK: - 搜索覆盖层

    func openSearch(seed: String) {
        guard !editMode else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            searchActive = true
            searchSeedText = seed
        }
    }

    func closeSearch() {
        withAnimation(.easeIn(duration: 0.15)) {
            searchActive = false
            searchSeedText = ""
        }
    }

    // MARK: - 启动 App

    func launch(_ entry: AppEntry) {
        guard FileManager.default.fileExists(atPath: entry.path) else {
            missingBundleIDs.insert(entry.bundleID)
            launchFailure = entry
            return
        }
        if settings.launchClosesPanel { onHidePanel?() }
        let url = URL(fileURLWithPath: entry.path)
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        Task { [weak self] in
            do {
                try await NSWorkspace.shared.openApplication(at: url, configuration: cfg)
            } catch {
                self?.missingBundleIDs.insert(entry.bundleID)
                self?.launchFailure = entry
            }
        }
    }

    func dismissLaunchFailure(remove: Bool) {
        if remove, let entry = launchFailure {
            var items = flatItems
            if let idx = items.firstIndex(where: { $0.id == "app:" + entry.bundleID }) {
                items.remove(at: idx)
                setFlat(items)
            }
            missingBundleIDs.remove(entry.bundleID)
        }
        launchFailure = nil
    }

    /// 启动时/加载后校验路径有效性
    func refreshMissing() {
        var missing: Set<String> = []
        func walk(_ items: [HomeItem]) {
            for it in items {
                switch it {
                case .app(let a):
                    if !FileManager.default.fileExists(atPath: a.path) { missing.insert(a.bundleID) }
                case .folder(let f):
                    walk(f.items)
                }
            }
        }
        walk(flatItems)
        missingBundleIDs = missing
    }

    // MARK: - 桌面增删改

    func addApp(_ entry: AppEntry, to target: AddTarget) {
        var items = flatItems
        switch target {
        case .desktop:
            items.append(.app(entry))
        case .folder(let fid):
            guard let fi = folderIndex(id: fid, in: items),
                  case .folder(var f) = items[fi] else { return }
            f.items.append(.app(entry))
            items[fi] = .folder(f)
        }
        setFlat(items)
        missingBundleIDs.remove(entry.bundleID)
    }

    /// 移除（文件夹则内容退回桌面；仅移除快捷方式，不卸载 App）
    func removeItem(id: String) {
        var items = flatItems
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        switch items[idx] {
        case .app:
            items.remove(at: idx)
        case .folder(let f):
            items.remove(at: idx)
            items.insert(contentsOf: f.items, at: min(idx, items.count))
        }
        if drag?.itemID == id { drag = nil }
        setFlat(items)
    }

    /// 整理模式移除（X 徽章 / 批量删除用）：App 删快捷方式；
    /// 文件夹**连同内容**一起移出桌面（App 本体不受影响，可重新添加）。
    /// 与 removeItem(id:)（右键，文件夹内容退回桌面）语义不同
    func removeFromDesktop(id: String) {
        guard drag == nil else { return }
        var items = flatItems
        items.removeAll { $0.id == id }
        setFlat(items)
    }

    /// 整理模式批量移除选中条目（无二次确认；文件夹连同内容）
    func removeSelectedFromDesktop() {
        guard drag == nil, !selectedIDs.isEmpty else { return }
        var items = flatItems
        items.removeAll { selectedIDs.contains($0.id) }
        setFlat(items)
        selectedIDs = []
    }

    /// 在桌面末尾新建空文件夹，并打开进入重命名
    func newFolder() {
        var items = flatItems
        let folder = FolderEntry(name: "新建文件夹")
        items.append(.folder(folder))
        setFlat(items)
        expandedFolderID = folder.id
        renamingFolderID = folder.id
        editMode = false
    }

    func renameFolder(_ id: UUID, to newName: String) {
        var items = flatItems
        guard let fi = folderIndex(id: id, in: items),
              case .folder(var f) = items[fi] else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        f.name = trimmed.isEmpty ? "新建文件夹" : trimmed
        items[fi] = .folder(f)
        setFlat(items)
    }

    /// 从当前展开的文件夹移出 App 到桌面末尾（文件夹空了则一并删除）
    func removeFromFolder(itemID: String) {
        guard let fid = expandedFolderID else { return }
        removeFromFolder(itemID: itemID, folderID: fid)
    }

    func removeFromFolder(itemID: String, folderID: UUID) {
        var items = flatItems
        guard let fi = folderIndex(id: folderID, in: items),
              case .folder(var f) = items[fi],
              let li = f.items.firstIndex(where: { $0.id == itemID }) else { return }
        let it = f.items.remove(at: li)
        let becameEmpty = f.items.isEmpty
        if becameEmpty {
            items.remove(at: fi)
        } else {
            items[fi] = .folder(f)
        }
        items.append(it)
        setFlat(items)
        if becameEmpty && expandedFolderID == folderID {
            expandedFolderID = nil
            renamingFolderID = nil
        }
    }

    /// 整理模式批量「移出文件夹」：选中项全部回到桌面末尾（卡片内多选的删除键）
    func removeSelectedFromFolder(_ folderID: UUID) {
        guard drag == nil, !selectedIDs.isEmpty else { return }
        // 先收集再逐个移除（removeFromFolder 不动 selectedIDs，逐个调用安全）
        let ids = selectedIDs
        for id in ids {
            removeFromFolder(itemID: id, folderID: folderID)
        }
        selectedIDs = []
    }

    func sortByName() {
        var items = flatItems
        items.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        setFlat(items)
    }

    // MARK: - 文件夹展开

    func expandFolder(_ id: UUID, sourceRect: CGRect = .zero) {
        folderSourceRect = sourceRect
        // iOS 同款手感：弹簧稍带回弹，卡片从图标位置「弹」开（与 cardZoom 展开时序一致）
        withAnimation(.spring(response: 0.52, dampingFraction: 0.8)) {
            expandedFolderID = id
        }
    }

    func collapseFolder() {
        // 收起更利落（回弹小），内容淡出后卡片缩回图标（与 cardZoom 收起时序一致）
        withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
            expandedFolderID = nil
            renamingFolderID = nil
        }
    }

    /// 文件夹内拖拽排序（由 FolderOverlay 调用）
    func moveWithinFolder(folderID: UUID, itemID: String, toLocalIndex target: Int) {
        var items = flatItems
        guard let fi = folderIndex(id: folderID, in: items),
              case .folder(var f) = items[fi],
              let from = f.items.firstIndex(where: { $0.id == itemID }),
              target != from else { return }
        let it = f.items.remove(at: from)
        f.items.insert(it, at: max(0, min(target, f.items.count)))
        items[fi] = .folder(f)
        setFlat(items)
    }

    // MARK: - 桌面拖拽（编辑模式）

    private var holdWork: DispatchWorkItem?
    private var holdTargetID: String?

    /// 拖影提交节流时间戳（~80fps）
    private var lastGhostCommit: CFTimeInterval = 0

    /// 诊断日志：上一个已记录的落点格（跨格才记录，避免刷屏）
    private var lastLoggedIdx: Int?
    /// 诊断日志：上一个已发布的插入空位（变化才记录）
    private var lastLoggedGap: Int?

    func beginDrag(itemID: String) {
        guard drag == nil else { return }
        guard let idx = flatIndexOf(id: itemID), let item = item(withID: itemID) else {
            dragDebugLog("beginDrag 失败：找不到 \(itemID)")
            return
        }
        // 提起：从网格中暂时移除（其余图标立即补位，拖动过程零换位）
        var items = flatItems
        items.remove(at: idx)
        setFlat(items)
        liveIndex = idx
        lastLoggedIdx = nil
        lastLoggedGap = nil
        // 提起即进入整理模式（iOS 同款：拖动图标 → 全桌面抖动）；
        // 并压制 tap，防止拖完松手被当成点按（误启动/误多选）
        suppressTapUntil = CACurrentMediaTime() + 0.4
        if !editMode {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                editMode = true
            }
        }
        // 空位初始 = 让出的原格（iOS 同款：提起后原位留白）
        drag = DragSession(item: item, originIndex: idx, currentIndex: idx, gapIndex: idx)
        dragDebugLog("beginDrag \(item.displayName) origin=\(idx) editMode=\(editMode)")
    }

    /// 拖拽移动中（point 为 homePanel 坐标系）。
    /// 高频热路径：只写 ghost tracker 与非发布态；@Published 仅在结构变化（跨格/合并态）时更新，
    /// 否则每个鼠标事件都会触发整棵视图树重渲染（卡顿根因）。
    ///
    /// iOS 式落点：光标在占用格**中心区** → 网格闭合、悬停 0.4s 合并；
    /// **边缘区** → 半格判定插入点、撑开空位两侧让位（跨格才发布）；
    /// 网格下方空白 → 追加到末尾（无可见空位）；出界保持当前空位（防边缘抖动）。
    func dragMoved(to point: CGPoint, metrics: GridMetrics) {
        guard drag != nil else { return }
        // 拖影提交节流（~80fps）：高报告率鼠标（125–1000Hz）下限制拖影重渲染频率
        let now = CACurrentMediaTime()
        if !ghost.started || now - lastGhostCommit >= 0.012 {
            ghost.point = point
            ghost.started = true
            lastGhostCommit = now
        }
        if let s = metrics.slot(at: point) {
            let cellIdx = s.row * metrics.columns + s.col
            if cellIdx >= flatItems.count {
                // 落点在已有条目之外 = 追加到末尾
                applyGap(nil)
                liveIndex = flatItems.count
                cancelMergeHold()
            } else if metrics.isInMergeZone(point: point, row: s.row, col: s.col) {
                // 中心合并区：网格闭合，维持悬停计时
                applyGap(nil)
                liveIndex = cellIdx
                updateMergeHold(targetID: flatItems[cellIdx].id)
            } else {
                // 边缘插入区：半格判定（左半 = 插到占用者前，右半 = 之后）
                let g = min(cellIdx + (metrics.isAfterHalf(point: point, row: s.row, col: s.col) ? 1 : 0),
                            flatItems.count)
                applyGap(g)
                liveIndex = g
                cancelMergeHold()
            }
        } else {
            // 出界（网格左右/上方）：保持当前空位，仅取消合并悬停
            cancelMergeHold()
        }
        // 诊断日志：仅在空位/落点变化时记录（避免高频刷屏）
        if let d = drag, d.gapIndex != lastLoggedGap {
            lastLoggedGap = d.gapIndex
            dragDebugLog("moved p=(\(Int(point.x)),\(Int(point.y))) gap=\(d.gapIndex.map(String.init) ?? "nil") live=\(liveIndex) count=\(flatItems.count)")
        }
    }

    /// 更新插入空位（仅在变化时发布，跨格频率；弹簧动画与增删一致）
    private func applyGap(_ idx: Int?) {
        guard var d = drag, d.gapIndex != idx else { return }
        d.gapIndex = idx
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            drag = d
        }
    }

    func endDrag() {
        holdWork?.cancel()
        holdWork = nil
        holdTargetID = nil
        ghost.started = false
        lastLoggedIdx = nil
        lastLoggedGap = nil
        guard let d = drag else {
            dragDebugLog("endDrag 时会话已空（可能已被取消）")
            return
        }
        drag = nil
        if let mc = d.mergeCandidateID, mc != d.itemID, let target = item(withID: mc) {
            dragDebugLog("endDrag → merge \(d.item.displayName) → \(target.displayName)")
            performMerge(dragged: d.item, target: target)
            flushPendingPersist()
            return
        }
        // 放置：插入到光标所在格（该格图标向后让位）
        var items = flatItems
        let idx = max(0, min(liveIndex, items.count))
        items.insert(d.item, at: idx)
        setFlat(items)
        dragDebugLog("endDrag → insert@\(idx) count=\(items.count)")
        flushPendingPersist()
    }

    /// 拖拽取消（松手在无效区域）：放回原位
    func cancelDrag() {
        holdWork?.cancel()
        holdWork = nil
        holdTargetID = nil
        ghost.started = false
        lastLoggedIdx = nil
        lastLoggedGap = nil
        guard let d = drag else { return }
        drag = nil
        var items = flatItems
        items.insert(d.item, at: max(0, min(d.originIndex, items.count)))
        setFlat(items)
        dragDebugLog("cancelDrag → 回原位 \(d.originIndex)")
        flushPendingPersist()
    }

    /// 光标所在格的占用者变化时，重排「悬停 0.4s 合并」等待
    private func updateMergeHold(targetID: String?) {
        guard let d = drag else { return }
        guard let targetID, targetID != d.itemID else {
            cancelMergeHold()
            return
        }
        // 同一目标：保留进行中的等待（不重置计时）
        guard holdTargetID != targetID else { return }
        holdWork?.cancel()
        // 离开上一个候选：清掉已亮出的合并标记
        if var d = drag, d.mergeCandidateID != nil {
            d.mergeCandidateID = nil
            drag = d
        }
        holdTargetID = targetID
        let wi = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, var d = self.drag, d.mergeCandidateID != targetID else { return }
                d.mergeCandidateID = targetID
                self.drag = d
                dragDebugLog("mergeHold armed target=\(targetID)")
            }
        }
        holdWork = wi
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: wi)
    }

    private func cancelMergeHold() {
        holdWork?.cancel()
        holdWork = nil
        holdTargetID = nil
        if var d = drag, d.mergeCandidateID != nil {
            d.mergeCandidateID = nil
            drag = d
        }
    }

    /// 把单个 App 收进一个新文件夹（App 右键菜单「移入新文件夹」）
    func moveIntoNewFolder(itemID: String) {
        guard let idx = flatIndexOf(id: itemID),
              case .app(let entry) = flatItems[idx] else { return }
        var items = flatItems
        let folder = FolderEntry(name: "新建文件夹", items: [.app(entry)])
        items[idx] = .folder(folder)
        setFlat(items)
        // 卡片从原格子位置展开
        let m = metrics
        let row = idx / m.columns, col = idx % m.columns
        let o = m.cellOrigin(row: row, col: col)
        let box = m.cellW - 30
        folderSourceRect = CGRect(x: o.x + (m.cellW - box) / 2, y: o.y, width: box, height: box)
        expandFolder(folder.id, sourceRect: folderSourceRect)
        renamingFolderID = folder.id
    }

    /// Finder 拖入 .app：构造 AppEntry 并加入桌面末尾；已在桌面则忽略
    func handleDroppedApp(at path: String) {
        guard let entry = AppScanner.entry(atPath: path),
              !allBundleIDs.contains(entry.bundleID) else { return }
        addApp(entry, to: .desktop)
    }

    /// 拖拽合并（拖拽项已提起、不在网格中）：app+app 建新夹；app 入夹；夹收 App / 夹并夹
    private func performMerge(dragged: HomeItem, target: HomeItem) {
        var items = flatItems
        guard let ti = items.firstIndex(where: { $0.id == target.id }) else { return }
        switch (dragged, target) {
        case (.app, .app):
            items[ti] = .folder(FolderEntry(name: "新建文件夹", items: [target, dragged]))
        case (.app, .folder(var f)):
            f.items.append(dragged)
            items[ti] = .folder(f)
        case (.folder(var f), .app):
            f.items.append(target)
            items[ti] = .folder(f)
        case (.folder(var f), .folder(let g)):
            f.items.append(contentsOf: g.items)
            items[ti] = .folder(f)
        }
        setFlat(items)
    }
}

/// 拖影位置跟踪：独立轻量 ObservableObject。
/// 鼠标移动（可达数百 Hz）只重渲染拖影本身；若挂在 HomeStore 的 @Published 上，
/// 每个事件都会让整棵视图树重评估 —— 这是拖拽卡顿的根因，别把 point 搬回去。
@MainActor
final class GhostTracker: ObservableObject {
    @Published var point: CGPoint = .zero
    /// 是否已收到首个移动事件（拖起瞬间避免拖影闪现在原点）
    @Published var started = false
}

// MARK: - 拖拽诊断日志（临时：定位「无法自定义排列」后移除）

/// 追加一行到 Application Support/MenuHome/drag-debug.log（拖拽均在主线程调用）
func dragDebugLog(_ s: String) {
    let path = NSHomeDirectory() + "/Library/Application Support/MenuHome/drag-debug.log"
    let line = String(format: "%.3f %@\n", CACurrentMediaTime(), s)
    if FileManager.default.fileExists(atPath: path), let fh = FileHandle(forWritingAtPath: path) {
        defer { try? fh.close() }
        fh.seekToEndOfFile()
        if let d = line.data(using: .utf8) { fh.write(d) }
    } else {
        try? line.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
