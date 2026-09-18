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

    /// iOS 同款开合动画：从文件夹图标位置缩放展开，收起时缩回图标
    private var cardZoom: AnyTransition {
        let m = store.metrics
        let src = store.folderSourceRect
        // 卡片最终位置（面板内正中）
        let cardH: CGFloat = 44 + 3 * m.cellH + 2 * m.vGap + 12   // 标题 + 3 行可视网格 + 底距
        let cardX = (m.pageW - cardWidth) / 2
        let cardY = (m.panelH - cardH) / 2
        guard src.width > 0, src.height > 0 else { return .opacity }
        let ax = min(1, max(0, (src.midX - cardX) / cardWidth))
        let ay = min(1, max(0, (src.midY - cardY) / cardH))
        let s = max(0.12, min(0.5, src.width / cardWidth))
        return .scale(scale: s, anchor: UnitPoint(x: ax, y: ay)).combined(with: .opacity)
    }

    var body: some View {
        if let folder = store.folder(withID: folderID) {
            content(folder: folder)
        } else {
            Color.clear.onAppear { store.collapseFolder() }
        }
    }

    @ViewBuilder
    private func content(folder: FolderEntry) -> some View {
        ZStack {            // 背景：点击收起
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { store.collapseFolder() }
                .transition(.opacity)

            VStack(spacing: 0) {
                titleRow(folder: folder)
                itemArea(folder: folder)
            }
            .frame(width: cardWidth)
            .liquidGlass(cornerRadius: Theme.panelRadius)
            .transition(cardZoom)
        }
    }

    // MARK: - 标题（点击重命名）

    @ViewBuilder
    private func titleRow(folder: FolderEntry) -> some View {
        Group {
            if store.renamingFolderID == folder.id {
                RenameField(folderID: folder.id, initial: folder.name)
            } else {
                Button {
                    withAnimation { store.renamingFolderID = folder.id }
                } label: {
                    HStack(spacing: 4) {
                        Text(folder.name)
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 44)
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

/// 卡片固定 3 列 × 可视 3 行，App 从左上角排起；
/// 超过 3×3 在卡片内垂直滚动（不再分页），卡片高度恒定；
/// 卡片内可拖动排序，拖出卡片 = 移出文件夹回到桌面
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

    /// 拖动中：光标所在格的内容扁平索引（卡片外为 nil）
    private var highlightOffset: Int? {
        guard dragItem != nil, let pt = dragPoint else { return nil }
        return localIndex(at: pt)
    }

    var body: some View {
        ZStack {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(metrics.cellW), spacing: metrics.hGap), count: cols),
                    spacing: metrics.vGap
                ) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { off, item in
                        let isDragged = dragItem?.id == item.id
                        FolderItemCell(item: item, folderID: folderID, iconSize: iconPt,
                                       onDragChanged: { pt in handleDrag(itemID: item.id, pt: pt) },
                                       onDragEnded: { pt in handleDrop(item: item, pt: pt) })
                            .opacity(isDragged ? 0.25 : 1)
                            .scaleEffect(highlightOffset == off && !isDragged ? 1.08 : 1)
                            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: highlightOffset)
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

    // MARK: - 卡片内拖拽

    private func handleDrag(itemID: String, pt: CGPoint) {
        if dragItem == nil, let it = items.first(where: { $0.id == itemID }) {
            dragItem = it
        }
        dragPoint = pt
    }

    private func handleDrop(item: HomeItem, pt: CGPoint) {
        defer { dragItem = nil; dragPoint = nil }
        guard let di = dragItem, di.id == item.id else { return }
        if let li = localIndex(at: pt) {
            // 卡片内：放到光标格（越过末尾由 store 钳制到末尾）
            store.moveWithinFolder(folderID: folderID, itemID: di.id, toLocalIndex: li)
        } else {
            // 拖出卡片：移出文件夹，回到桌面末尾
            store.removeFromFolder(itemID: di.id, folderID: folderID)
        }
    }

    /// 光标 → 内容扁平格子索引；拖出卡片（可视区外）返回 nil。
    /// 手势坐标在卡片空间，内容纵向坐标 = 卡片坐标 + 滚动偏移
    private func localIndex(at pt: CGPoint) -> Int? {
        guard pt.x >= 0, pt.y >= 0, pt.x < cardInnerWidth, pt.y < visibleHeight else { return nil }
        let col = min(cols - 1, max(0, Int(pt.x / (metrics.cellW + metrics.hGap))))
        let row = max(0, Int((pt.y + scrollOffset) / (metrics.cellH + metrics.vGap)))
        return row * cols + col
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
            .font(.system(size: 13, weight: .semibold))
            .multilineTextAlignment(.center)
            .focused($focused)
            .onSubmit { commit() }
            .onChange(of: focused) { value in
                if value == false { commit() }
            }
            .onAppear {
                text = initial
                focused = true
            }
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
