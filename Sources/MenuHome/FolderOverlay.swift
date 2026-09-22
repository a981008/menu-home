import AppKit
import SwiftUI

/// 文件夹展开覆盖层（面板内，iPhone 同款卡片）
struct FolderOverlay: View {
    let folderID: UUID
    @EnvironmentObject var store: HomeStore

    /// 卡片宽度：3 列主网格格子 + 2×列距 + 左右各 16pt 内边距（间隔与桌面一致）
    private var cardWidth: CGFloat {
        3 * store.metrics.cellW + 2 * store.metrics.hGap + 32
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
        // 玻璃卡片最终位置：卡片自身（标准 3×3）在面板内**正中**，
        // 标题悬浮在卡片上方，由卡片下方的等高隐形补白平衡，不影响居中
        let cardH: CGFloat = 3 * m.cellH + 2 * m.vGap + 12   // 3 行可视网格 + 底距（标题已移出卡片）
        let cardX = (m.pageW - cardWidth) / 2
        let cardY = (m.panelH - cardH) / 2
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
            // 卡片下方的隐形补白 = 标题块等高：让「卡片」本体（标准 3×3）成为
            // 被居中的主体，精确落在面板正中；标题悬浮在上方，视觉上下对称
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
            FolderScrollGrid(items: folder.items, folderID: folder.id)
        }
    }
}

// MARK: - 文件夹卡片滚动网格

/// 卡片网格显示条目：item = nil 表示插入空位（拖拽落点预览）
private struct FolderDisplayEntry: Identifiable {
    let id: String
    let item: HomeItem?
}

/// 卡片固定 3 列 × 可视 3 行（标准 3×3，卡片本体在面板内正中），App 从左上角
/// 按「从左到右、从上到下」排起，不足 3×3 底部留白；
/// 超过 3×3 在卡片内垂直滚动（不再分页），卡片高度恒定；
/// 卡片内可拖动排序（iOS 式空位让位），拖出卡片 = 移出文件夹回到桌面
private struct FolderScrollGrid: View {
    let items: [HomeItem]
    let folderID: UUID
    @EnvironmentObject var store: HomeStore

    private let cols = 3

    // 与主网格同一套 metrics：格子、间隙、图标尺寸完全一致（跟随设置的图标大小）
    private var metrics: GridMetrics { store.metrics }
    private var iconPt: CGFloat { metrics.cellW - 30 }
    private var cardInnerWidth: CGFloat {
        CGFloat(cols) * metrics.cellW + CGFloat(cols - 1) * metrics.hGap
    }
    /// 卡片内可视高度：固定 3 行（其余滚动）
    private var visibleHeight: CGFloat {
        3 * metrics.cellH + 2 * metrics.vGap
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
                    columns: Array(repeating: GridItem(.fixed(metrics.cellW), spacing: metrics.hGap), count: cols),
                    spacing: metrics.vGap
                ) {
                    ForEach(displayItems) { entry in
                        if let item = entry.item {
                            let isDragged = dragItem?.id == item.id
                            FolderItemCell(item: item, folderID: folderID, iconSize: iconPt,
                                           onDragChanged: { pt in handleDrag(itemID: item.id, pt: pt) },
                                           onDragEnded: { pt in handleDrop(item: item, pt: pt) })
                                .opacity(isDragged ? 0.25 : 1)
                        } else {
                            // 插入空位：两侧条目让位（iOS 式落点预览）
                            Color.clear
                                .frame(width: metrics.cellW, height: metrics.cellH)
                        }
                    }
                }
                .frame(width: cardInnerWidth, alignment: .topLeading)
            }
            .frame(width: cardInnerWidth, height: visibleHeight)
            // App 式胶囊滚轴 + 滚动内容与滚轴裁剪进圆角容器（圆角外不露直角）
            .appScrollbar()
            .clipShape(RoundedRectangle(cornerRadius: Theme.scrollClipRadius, style: .continuous))
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
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
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

    /// 点是否在卡片可视区内
    private func isInsideCard(_ pt: CGPoint) -> Bool {
        pt.x >= 0 && pt.y >= 0 && pt.x < cardInnerWidth && pt.y < visibleHeight
    }

    /// 光标 → 内容扁平格子索引；拖出卡片（可视区外）返回 nil。
    /// 手势坐标在卡片空间，内容纵向坐标 = 卡片坐标 + 滚动偏移
    private func localIndex(at pt: CGPoint) -> Int? {
        guard isInsideCard(pt) else { return nil }
        let col = min(cols - 1, max(0, Int(pt.x / (metrics.cellW + metrics.hGap))))
        let row = max(0, Int((pt.y + scrollOffset) / (metrics.cellH + metrics.vGap)))
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
        let col = min(cols - 1, max(0, Int(pt.x / (metrics.cellW + metrics.hGap))))
        let row = max(0, Int((pt.y + scrollOffset) / (metrics.cellH + metrics.vGap)))
        let k = row * cols + col
        let after = pt.x > CGFloat(col) * (metrics.cellW + metrics.hGap) + metrics.cellW / 2
        let h = after ? (k < from ? k + 1 : k)
                      : (k <= from ? k : k - 1)
        let g = max(0, min(h, max(0, items.count - 1)))
        if gapIndex != g {
            withAnimation(gapAnim) { gapIndex = g }
        }
    }

    private func ghost(for item: HomeItem) -> some View {
        VStack(spacing: 2) {
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
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
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
    var onDragChanged: ((CGPoint) -> Void)? = nil
    var onDragEnded: ((CGPoint) -> Void)? = nil
    @EnvironmentObject var store: HomeStore
    private var _hovering: State<Bool> = State(initialValue: false)
    private var hovering: Bool {
        get { _hovering.wrappedValue }
        nonmutating set { _hovering.wrappedValue = newValue }
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
    }

    @ViewBuilder
    private func appCell(_ entry: AppEntry) -> some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topLeading) {
                Image(nsImage: AppScanner.cachedIcon(forPath: entry.path))
                    .resizable()
                    .frame(width: iconSize, height: iconSize)

                if store.editMode {
                    Button {
                        store.removeFromFolder(itemID: item.id, folderID: folderID)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary, Color(nsColor: .controlBackgroundColor))
                    }
                    .buttonStyle(.plain)
                    .offset(x: -6, y: -6)
                    .help("移出文件夹")
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
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(hovering ? 0.06 : 0)))
        .scaleEffect(hovering && !store.editMode ? 1.04 : 1)
        .animation(.easeInOut(duration: 0.12), value: hovering)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            guard !store.editMode else { return }
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
