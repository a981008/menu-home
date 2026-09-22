import AppKit
import SwiftUI

/// 文件夹卡片玻璃留白（v1.3 用户调参：**框变大**、图标与桌面同大）：
/// 卡片在网格四周加固定玻璃留白（28 = 卡片圆角，视觉干净），框比网格大一圈。
/// 注意几何权衡：框变大后角部图标不再贴角（四角均匀内留白 28+格子留白 20.5/21.5，
/// 圆弧走向一致）；「图标圆角与卡片圆角同心贴合」要求框贴住网格 ——
/// 框变大 / 图标同大 / 贴角三者几何上只能同时满足两个，本轮按用户要求取前两个
private enum FolderCardGeometry {
    /// 卡片四周玻璃留白（与卡片圆角同值）
    static let glassInset: CGFloat = 28
}

/// 文件夹展开覆盖层（面板内，iPhone 同款卡片）
struct FolderOverlay: View {
    let folderID: UUID
    @EnvironmentObject var store: HomeStore

    /// 卡片专用网格（v1.3 用户调参）：**图标与桌面完全一致**（跟随图标大小设置，
    /// 用户明确要求「图标要和外面的一样大」），仅把间隙收紧 —— 12/14 → 6/6
    /// （相邻图标可见间距 53/56 → 47/49）；3 列 × 3 行
    private var folderMetrics: GridMetrics {
        var m = store.metrics
        m.hGap = 6
        m.vGap = 6
        return m
    }

    /// 卡片宽度：3 列卡片格子 + 2×列距 + 四周玻璃留白（框比网格大一圈）
    private var cardWidth: CGFloat {
        3 * folderMetrics.cellW + 2 * folderMetrics.hGap
            + 2 * FolderCardGeometry.glassInset
    }

    /// 标题行高与标题—卡片间距（标题在卡片外）。
    /// 标题块由「卡片下方的等高隐形补白」平衡（见 content）—— 卡片自身在面板内正中
    private let titleRowHeight: CGFloat = 28
    private let titleCardGap: CGFloat = 8
    private var titleBlock: CGFloat { titleRowHeight + titleCardGap }

    /// iOS 同款开合动画：从文件夹图标位置缩放展开，收起时缩回图标。
    /// 开 = 带回弹弹簧淡入；收 = 卡片**全程实体**缩回图标、最后 0.12s 才淡出
    /// （「缩进图标」而不是「边缩边隐」——边缩边隐是生硬感主因）。
    /// 各段 .animation() 自带时序，不依赖外层 withAnimation
    private var cardZoom: AnyTransition {
        let m = store.metrics
        let src = store.folderSourceRect
        // 玻璃卡片最终位置：卡片自身（标准 3×3）在「搜索栏下方内容区」内**正中** ——
        // 视觉居中以搜索栏为顶界（整面板几何中心会显得偏上）；标题悬浮在卡片上方。
        // 卡高按卡片专用网格（folderMetrics）计算；面板坐标系仍用主 metrics
        let cardH: CGFloat = 3 * folderMetrics.cellH + 2 * folderMetrics.vGap
            + 2 * FolderCardGeometry.glassInset
        let cardX = (m.pageW - cardWidth) / 2
        let cardY = m.searchBarArea + (m.panelH - m.searchBarArea - cardH) / 2
        guard src.width > 0, src.height > 0 else { return .opacity }
        let ax = min(1, max(0, (src.midX - cardX) / cardWidth))
        let ay = min(1, max(0, (src.midY - cardY) / cardH))
        let s = max(0.12, min(0.5, src.width / cardWidth))
        let open: AnyTransition = .scale(scale: s, anchor: UnitPoint(x: ax, y: ay))
            .animation(.spring(response: 0.52, dampingFraction: 0.8))
            .combined(with: .opacity.animation(.spring(response: 0.52, dampingFraction: 0.8)))
        let close: AnyTransition = .scale(scale: s, anchor: UnitPoint(x: ax, y: ay))
            .animation(.spring(response: 0.48, dampingFraction: 0.86))
            .combined(with: .opacity.animation(.easeIn(duration: 0.16).delay(0.34)))
        return .asymmetric(insertion: open, removal: close)
    }

    var body: some View {
        if let folder = store.folder(withID: folderID) {
            content(folder: folder)
        } else {
            Color.clear.onAppear { store.collapseFolder() }
        }
    }

    /// 卡片内容显现（iOS 同款两段式：卡片先弹开，内容稍后淡入）—— 手工脱糖 @State
    private var _contentShown: State<Bool> = State(initialValue: false)
    private var contentShown: Bool {
        get { _contentShown.wrappedValue }
        nonmutating set { _contentShown.wrappedValue = newValue }
    }

    @ViewBuilder
    private func content(folder: FolderEntry) -> some View {
        ZStack {            // 背景：点击收起
            // 压暗层必须与面板玻璃同形（连续圆角矩形）：glassEffect 只裁玻璃材质、
            // 不裁内容，整幅矩形压暗层的四个直角会从面板圆角外露出来
            // （「点开文件夹后圆角容器四周出现直角/矩形边界」的根因）
            RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                .fill(Color.black.opacity(0.3))
                .contentShape(Rectangle())
                .onTapGesture { store.collapseFolder() }
                .transition(.opacity)

            // 标题在卡片外（iOS 同款：名称悬浮在卡片上方左上角，不占玻璃卡片内部空间）。
            // VStack 必须钉在 cardWidth：标题的 maxWidth .infinity 是贪婪的，
            // 不钉住会被 ZStack 撑到整面板宽，左对齐就跑到面板左缘了
            VStack(spacing: titleCardGap) {
                titleRow(folder: folder)
                    .opacity(contentShown ? 1 : 0)
                    .transition(.opacity.animation(.easeIn(duration: 0.25)))

                itemArea(folder: folder)
                    .opacity(contentShown ? 1 : 0)
                    .scaleEffect(contentShown ? 1 : 0.92)
                    .transition(.opacity.animation(.easeIn(duration: 0.25)))
                    .frame(width: cardWidth)
                    .liquidGlass(cornerRadius: Theme.panelRadius)
                    .transition(cardZoom)
            }
            .frame(width: cardWidth)
            // 垂直定位：顶部让出搜索栏区域 → 卡片在「搜索栏下方内容区」内居中
            // （内容区中心比整面板几何中心低 searchBarArea/2，这才是视觉上的居中）；
            // 底部补白 = 标题块等高，平衡悬浮标题，让卡片本体成为居中主体
            .padding(.top, store.metrics.searchBarArea)
            .padding(.bottom, titleBlock)
            .onAppear {
                // 卡片弹出后内容再登场（错开 0.12s 的两段节奏）
                withAnimation(.spring(response: 0.45, dampingFraction: 0.9).delay(0.12)) {
                    contentShown = true
                }
            }
        }
        // 容器不做整体淡出（默认 opacity 会在卡片自己转场之外再叠一层「边缩边隐」，
        // 是收起发糊/生硬的另一个来源）—— 开合节奏全部交给子视图各自的 transition
        .transition(.identity)
    }

    // MARK: - 标题（卡片外左上角；点击重命名）

    @ViewBuilder
    private func titleRow(folder: FolderEntry) -> some View {
        Group {
            if store.renamingFolderID == folder.id {
                RenameField(folderID: folder.id, initial: folder.name)
            } else {
                Button {
                    withAnimation { store.renamingFolderID = folder.id }
                } label: {
                    Text(folder.name)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .background(
                            // 悬浮在压暗背景上：与桌面图标标签同款「黑字模糊垫」保证可读
                            Text(folder.name)
                                .font(.system(size: 20, weight: .semibold))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(Color.black.opacity(0.5))
                                .blur(radius: 4)
                        )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)   // 与卡片内图标列左缘对齐
        .frame(height: titleRowHeight)
    }

    // MARK: - 内容网格（固定 3 列可视 3 行，从左上角排起，超出在卡片内滚动）

    @ViewBuilder
    private func itemArea(folder: FolderEntry) -> some View {
        if folder.items.isEmpty {
            VStack(spacing: 10) {
                Text("把 App 拖进来，或点击添加")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Button("＋ 添加 App") {
                    store.addTarget = .folder(folder.id)
                }
                .glassButton()
            }
            .padding(.vertical, 28)
            .padding(.bottom, 10)
        } else {
            FolderScrollGrid(items: folder.items, folderID: folder.id, grid: folderMetrics)
        }
    }
}

// MARK: - 文件夹卡片滚动网格

/// 卡片网格显示条目：item = nil 表示插入空位（拖拽落点预览）
private struct FolderDisplayEntry: Identifiable {
    let id: String
    let item: HomeItem?
}

/// 卡片固定 3 列 × 可视 3 行（标准 3×3，卡片本体在「搜索栏下方内容区」内正中）；
/// 条目不足 3×3 时**从左上角排起、与 3×3 完全相同**（不做垂直居中 —— 用户要求：
/// 第一行图标圆角永远贴卡片顶角）；超过 3×3 在卡片内垂直滚动（不再分页），卡片高度恒定；
/// 卡片内可拖动排序（iOS 式空位让位），拖出卡片 = 移出文件夹回到桌面
private struct FolderScrollGrid: View {
    let items: [HomeItem]
    let folderID: UUID
    let grid: GridMetrics
    @EnvironmentObject var store: HomeStore

    private let cols = 3

    // 卡片专用网格（格子/图标与桌面一致、间隙收紧，见 FolderOverlay.folderMetrics）；
    // 拖拽落点换算也用它 —— 格子钉死 cellH 后逐像素严格一致
    private var iconPt: CGFloat { grid.cellW - 30 }
    private var cardInnerWidth: CGFloat {
        CGFloat(cols) * grid.cellW + CGFloat(cols - 1) * grid.hGap
    }
    /// 卡片内可视高度：固定 3 行（其余滚动）
    private var visibleHeight: CGFloat {
        3 * grid.cellH + 2 * grid.vGap
    }

    // 卡片内拖拽会话（手工脱糖 @State）
    private var _dragItem: State<HomeItem?> = State(initialValue: nil)
    private var dragItem: HomeItem? {
        get { _dragItem.wrappedValue }
        nonmutating set { _dragItem.wrappedValue = newValue }
    }
    private var _dragPoint: State<CGPoint?> = State(initialValue: nil)
    private var dragPoint: CGPoint? {
        get { _dragPoint.wrappedValue }
        nonmutating set { _dragPoint.wrappedValue = newValue }
    }
    /// 滚动位置：卡片坐标 ↔ 内容坐标换算用（拖拽手势在卡片空间）
    private var _scrollOffset: State<CGFloat> = State(initialValue: 0)
    private var scrollOffset: CGFloat {
        get { _scrollOffset.wrappedValue }
        nonmutating set { _scrollOffset.wrappedValue = newValue }
    }
    /// 插入落点（提起坐标 = 先移除被拖项再插入的索引；nil = 不撑开空位）
    private var _gapIndex: State<Int?> = State(initialValue: nil)
    private var gapIndex: Int? {
        get { _gapIndex.wrappedValue }
        nonmutating set { _gapIndex.wrappedValue = newValue }
    }

    private var gapAnim: Animation { .spring(response: 0.28, dampingFraction: 0.85) }

    var body: some View {
        ZStack {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(grid.cellW), spacing: grid.hGap), count: cols),
                    spacing: grid.vGap
                ) {
                    ForEach(displayItems) { entry in
                        if let item = entry.item {
                            let isDragged = dragItem?.id == item.id
                            FolderItemCell(item: item, folderID: folderID, iconSize: iconPt,
                                           isDragging: isDragged,
                                           onDragChanged: { pt in handleDrag(itemID: item.id, pt: pt) },
                                           onDragEnded: { pt in handleDrop(item: item, pt: pt) })
                                // 钉死格子高度 = grid.cellH 且内容顶对齐：
                                // appCell 自带固定 frame(格宽×格高)，内容在框内居中
                                //（与桌面同款），3 行正好填满视口；拖拽落点换算按
                                // cellH 也严格一致
                                .frame(height: grid.cellH, alignment: .top)
                                .opacity(isDragged ? 0.25 : 1)
                                .animation(.easeOut(duration: 0.15), value: store.editMode)
                        } else {
                            // 插入空位：两侧条目让位（iOS 式落点预览）
                            Color.clear
                                .frame(width: grid.cellW, height: grid.cellH)
                        }
                    }
                }
                .frame(width: cardInnerWidth, alignment: .topLeading)
                .frame(minHeight: visibleHeight, alignment: .top)
            }
            .frame(width: cardInnerWidth, height: visibleHeight)
            // App 式胶囊滚轴 + 滚动内容与滚轴裁剪进圆角容器（圆角外不露直角）。
            // 悬停缩放（1.04）会溢出格子 ~1.8pt：ScrollView 自带裁剪会把边缘格子的
            // 悬停高亮切成平边（与桌面观感不一致的根因）—— 禁掉自身裁剪、把圆角
            // 裁剪外扩 3pt（仍在四周 28pt 玻璃留白之内），溢出完整渲染
            .appScrollbar()
            .scrollClipDisabled()
            .clipShape(RoundedRectangle(cornerRadius: Theme.scrollClipRadius, style: .continuous).inset(by: -3))
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top
            } action: { _, newValue in
                scrollOffset = newValue
            }

            // 卡片内拖影
            if let di = dragItem, let pt = dragPoint {
                ghost(for: di)
                    .position(pt)
                    .allowsHitTesting(false)
            }
        }
        .coordinateSpace(name: "folderCard")
        .frame(width: cardInnerWidth, height: visibleHeight)
        // 四周玻璃留白：框比网格大一圈（v1.3 框变大；角部图标不再贴角，四角均匀）
        .padding(.horizontal, FolderCardGeometry.glassInset)
        .padding(.top, FolderCardGeometry.glassInset)
        .padding(.bottom, FolderCardGeometry.glassInset)
    }

    // MARK: - 卡片内拖拽（iOS 式：空位跟随光标 + 半格判定；卡片内无合并）

    /// 显示序列：被拖项**保持原格半透明**（手势宿主必须存活 —— 别改成移出网格，
    /// 卡片内拖拽手势挂在格子视图上，见 AGENTS.md 不变量 4），在插入点的
    /// 显示位置放一个空占位让两侧让位。
    /// gapIndex 存「提起坐标」落点 h，显示位置折算回含被拖项的坐标：h ≤ from ? h : h + 1
    private var displayItems: [FolderDisplayEntry] {
        guard dragItem != nil, let h = gapIndex,
              let from = items.firstIndex(where: { $0.id == dragItem?.id }) else {
            return items.map { FolderDisplayEntry(id: $0.id, item: $0) }
        }
        let dg = h <= from ? h : h + 1
        var arr: [FolderDisplayEntry] = []
        for (i, it) in items.enumerated() {
            if i == dg { arr.append(FolderDisplayEntry(id: "gap", item: nil)) }
            arr.append(FolderDisplayEntry(id: it.id, item: it))
        }
        if dg >= items.count { arr.append(FolderDisplayEntry(id: "gap", item: nil)) }
        return arr
    }

    private func handleDrag(itemID: String, pt: CGPoint) {
        if dragItem == nil, let it = items.first(where: { $0.id == itemID }),
           let fi = items.firstIndex(where: { $0.id == itemID }) {
            dragItem = it
            // 初始空位在被拖项右侧一格：半透明原格 + 其后留白 = 「已提起」的视觉
            gapIndex = min(fi + 1, max(0, items.count - 1))
            // 提起即进入整理模式（与桌面 beginDrag 完全同款，iOS 同一行为）；
            // 并压制 tap，防止拖完松手被当成点按（误多选）
            store.suppressTapUntil = CACurrentMediaTime() + 0.4
            if !store.editMode {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    store.editMode = true
                }
            }
        }
        dragPoint = pt
        updateGap(at: pt)
    }

    private func handleDrop(item: HomeItem, pt: CGPoint) {
        defer { dragItem = nil; dragPoint = nil; gapIndex = nil }
        guard let di = dragItem, di.id == item.id else { return }
        if isInsideCard(pt) {
            // 空位即落点（提起坐标，与 moveWithinFolder 的「先移除后插入」语义一致）
            let g = gapIndex ?? localIndex(at: pt) ?? 0
            store.moveWithinFolder(folderID: folderID, itemID: di.id, toLocalIndex: g)
        } else {
            // 拖出卡片：移出文件夹，回到桌面末尾
            store.removeFromFolder(itemID: di.id, folderID: folderID)
        }
    }

    /// 点是否在卡片（含四周玻璃留白）内 —— 留白也算卡片内部：
    /// 拖到玻璃边缘内侧松手仍是合法落点（钳到最近的格子），越过玻璃才算拖出
    private func isInsideCard(_ pt: CGPoint) -> Bool {
        let inset = FolderCardGeometry.glassInset
        return pt.x >= -inset && pt.y >= -inset
            && pt.x < cardInnerWidth + inset && pt.y < visibleHeight + inset
    }

    /// 光标 → 内容扁平格子索引；拖出卡片（可视区外）返回 nil。
    /// 手势坐标在卡片空间，内容纵向坐标 = 卡片坐标 + 滚动偏移
    private func localIndex(at pt: CGPoint) -> Int? {
        guard isInsideCard(pt) else { return nil }
        let col = min(cols - 1, max(0, Int(pt.x / (grid.cellW + grid.hGap))))
        let row = max(0, Int((pt.y + scrollOffset) / (grid.cellH + grid.vGap)))
        return row * cols + col
    }

    /// 半格判定更新落点（换算成提起坐标）：左半 = 插到该格占用者前，右半 = 之后；
    /// 光标 → 格子是纯几何映射，不随空位让位变化（无回摆）
    private func updateGap(at pt: CGPoint) {
        guard dragItem != nil,
              let from = items.firstIndex(where: { $0.id == dragItem?.id }) else { return }
        guard isInsideCard(pt) else {
            if gapIndex != nil { withAnimation(gapAnim) { gapIndex = nil } }
            return
        }
        let col = min(cols - 1, max(0, Int(pt.x / (grid.cellW + grid.hGap))))
        let row = max(0, Int((pt.y + scrollOffset) / (grid.cellH + grid.vGap)))
        let k = row * cols + col
        let after = pt.x > CGFloat(col) * (grid.cellW + grid.hGap) + grid.cellW / 2
        let h = after ? (k < from ? k + 1 : k)
                      : (k <= from ? k : k - 1)
        let g = max(0, min(h, max(0, items.count - 1)))
        if gapIndex != g {
            withAnimation(gapAnim) { gapIndex = g }
        }
    }

    /// 卡片内拖影：与桌面 DragGhostView 完全同款（液态玻璃胶囊 + scale 1.1，
    /// 无黑投影 —— 立体感来自玻璃材质本身；此前是厚材质 + 黑阴影，观感不一致）
    private func ghost(for item: HomeItem) -> some View {
        VStack(spacing: 4) {
            if let e = item.appEntry {
                Image(nsImage: AppScanner.cachedIcon(forPath: e.path))
                    .resizable()
                    .frame(width: iconPt, height: iconPt)
            } else {
                Image(systemName: "folder")
                    .font(.system(size: 30))
            }
            Text(item.displayName)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary)
        }
        .padding(8)
        .liquidGlass(cornerRadius: Theme.ghostRadius)
        .scaleEffect(1.1)
    }
}

// MARK: - 行内重命名输入框

private struct RenameField: View {
    let folderID: UUID
    let initial: String
    @EnvironmentObject var store: HomeStore
    // 手工脱糖的 @State（本机 CLT 缺宏插件）
    private var _text: State<String> = State(initialValue: "")
    private var text: String {
        get { _text.wrappedValue }
        nonmutating set { _text.wrappedValue = newValue }
    }
    @FocusState private var focused: Bool

    var body: some View {
        TextField("文件夹名称", text: _text.projectedValue)
            .textFieldStyle(.plain)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
            .focused($focused)
            .onSubmit { commit() }
            .onChange(of: focused) { value in
                if value == false { commit() }
            }
            .onAppear {
                text = initial
                focused = true
            }
            // 输入框同样悬浮在压暗背景上：白字 + 轻微黑晕保证可读（瞬时状态）
            .shadow(color: .black.opacity(0.45), radius: 3)
    }

    private func commit() {
        guard store.renamingFolderID != nil else { return }
        store.renameFolder(folderID, to: text)
        store.renamingFolderID = nil
    }
}

// MARK: - 文件夹内的 App 格子

private struct FolderItemCell: View {
    let item: HomeItem
    let folderID: UUID
    var iconSize: CGFloat = 48
    /// 本格正在被拖拽（原格半透明、不抖动）
    var isDragging: Bool = false
    var onDragChanged: ((CGPoint) -> Void)? = nil
    var onDragEnded: ((CGPoint) -> Void)? = nil
    @EnvironmentObject var store: HomeStore
    private var _hovering: State<Bool> = State(initialValue: false)
    private var hovering: Bool {
        get { _hovering.wrappedValue }
        nonmutating set { _hovering.wrappedValue = newValue }
    }

    /// 本格被多选（整理模式，与桌面 CellView 同一套 selectedIDs）
    private var isSelected: Bool { store.selectedIDs.contains(item.id) }

    /// 稳定伪随机种子 0...1（与桌面同款抖动相位，由 item id 哈希而来）
    private var seed: Double {
        Double(UInt(bitPattern: item.id.hashValue) % 100) / 100
    }

    var body: some View {
        Group {
            if let entry = item.appEntry {
                appCell(entry)
            } else {
                Text(item.displayName).font(.system(size: 11))
            }
        }
        .frame(maxWidth: .infinity)
        // 整理模式抖动与桌面完全一致（iOS 文件夹展开后同样抖动）
        .modifier(JiggleModifier(active: store.editMode && !isDragging,
                                 seed: seed,
                                 reduceMotion: store.reduceMotion))
    }

    @ViewBuilder
    private func appCell(_ entry: AppEntry) -> some View {
        // 内容结构与桌面 AppCellView 完全一致：VStack(spacing: 4){图标; 标签}，
        // 由下方固定 frame(格宽×格高) 自动居中 —— 图标上方 = 标签下方留空（各约 7.5pt），
        // 与桌面格子内部布局逐点相同；不再使用「图标下沉」结构（那是为第三行图标
        // 圆角同心设计的，但导致框内上 16.5 / 下 0.5 的不居中，用户要求与桌面一致）
        VStack(spacing: 4) {
            ZStack(alignment: .topLeading) {
                Image(nsImage: AppScanner.cachedIcon(forPath: entry.path))
                    .resizable()
                    .frame(width: iconSize, height: iconSize)

                // 整理模式角标：与桌面 CellView.editBadge 完全同款（红 ⊖ 移出 / 蓝 ✓ 已选），
                // 悬在图标左上角相同相对位（桌面角标中心 = 图标角内 (0, 6)，此处一致）
                if store.editMode {
                    Button {
                        if isSelected {
                            store.toggleSelected(id: item.id)
                        } else {
                            store.removeFromFolder(itemID: item.id, folderID: folderID)
                        }
                    } label: {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "minus.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white, isSelected ? Color.accentColor : Color.red)
                    }
                    .buttonStyle(.plain)
                    .offset(x: -8, y: -2)
                    .transition(.scale.combined(with: .opacity))
                    .help(isSelected ? "取消选择" : "移出文件夹")
                }
            }
            Text(entry.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.white)
                .background(
                    // 与桌面图标标签同款「模糊垫」（iOS 风格）
                    Text(entry.name)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(Color.black.opacity(0.5))
                        .blur(radius: 4)
                )
        }
        // 悬停框与桌面 CellView 完全一致：套在固定「格宽×格高」frame 上 ——
        // 否则框随标签自然宽度收缩（短名 App 的框窄成长方形、逐格不同）；
        // 内容在此 frame 内居中（与桌面 AppCellView 同款）
        .frame(width: iconSize + 30, height: iconSize + 32)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(hovering ? 0.06 : 0)))
        .scaleEffect(hovering && !store.editMode ? 1.04 : 1)
        // 已选压暗：与桌面 CellView 同款（0.85）
        .opacity(isSelected ? 0.85 : 1)
        .animation(.easeInOut(duration: 0.12), value: hovering)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            // 拖完松手 / 长按松手不算点按（与桌面 CellView.tap 同款防护）
            if CACurrentMediaTime() < store.suppressTapUntil { return }
            if store.editMode {
                // 整理模式：点格子本体 = 多选切换（与桌面一致）
                withAnimation(.easeInOut(duration: 0.15)) { store.toggleSelected(id: item.id) }
                return
            }
            store.launch(entry)
        }
        .contextMenu {
            Button("打开") { store.launch(entry) }
            Button("移出文件夹") {
                store.removeFromFolder(itemID: item.id, folderID: folderID)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .named("folderCard"))
                .onChanged { v in onDragChanged?(v.location) }
                .onEnded { v in onDragEnded?(v.location) }
        )
    }
}
