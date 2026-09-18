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
        // 卡片最终位置（面板内居中，上移 12pt）
        let cardH: CGFloat = 44 + 3 * m.cellH + 2 * m.vGap + 30   // 标题 + 3 行网格 + 页点/底距
        let cardX = (m.pageW - cardWidth) / 2
        let cardY = (m.panelH - cardH) / 2 - 12
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
            .liquidGlass(cornerRadius: Theme.cardRadius)
            .offset(y: -12)
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

    // MARK: - 内容网格（iPhone 式：固定 3×3 一页，图标从左上角排起，>9 个翻页）

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
            FolderPagedGrid(items: folder.items, folderID: folder.id)
        }
    }
}

// MARK: - 文件夹卡片分页网格

/// iPhone 同款：卡片固定 3 列 × 3 行，App 从左上角排起；
/// 超过 9 个分页（横滑或点页点），卡片高度恒定、内容永远完整显示；
/// 卡片内可拖动排序，拖出卡片 = 移出文件夹回到桌面
private struct FolderPagedGrid: View {
    let items: [HomeItem]
    let folderID: UUID
    @EnvironmentObject var store: HomeStore

    private let cols = 3
    private let rowsPerPage = 3

    // 与主网格同一套 metrics：格子、间隙、图标尺寸完全一致（跟随设置的图标大小）
    private var metrics: GridMetrics { store.metrics }
    private var iconPt: CGFloat { metrics.cellW - 30 }
    private var cardInnerWidth: CGFloat {
        CGFloat(cols) * metrics.cellW + CGFloat(cols - 1) * metrics.hGap
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

    private var perPage: Int { cols * rowsPerPage }
    private var pageCount: Int { max(1, (items.count + perPage - 1) / perPage) }
    private var page: Int { min(max(store.folderPage, 0), pageCount - 1) }
    private var pageHeight: CGFloat {
        CGFloat(rowsPerPage) * metrics.cellH + CGFloat(rowsPerPage - 1) * metrics.vGap
    }

    /// 拖动中：光标所在格在本页内的偏移（卡片外为 nil）
    private var highlightOffset: Int? {
        guard dragItem != nil, let pt = dragPoint else { return nil }
        return localIndex(at: pt)
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                HStack(spacing: 0) {
                    ForEach(0..<pageCount, id: \.self) { p in
                        pageGrid(p)
                            .frame(width: cardInnerWidth, height: pageHeight, alignment: .top)
                    }
                }
                .offset(x: -CGFloat(page) * cardInnerWidth)
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: page)
                .contentShape(Rectangle())
                .gesture(swipeGesture)

                // 卡片内拖影
                if let di = dragItem, let pt = dragPoint {
                    ghost(for: di)
                        .position(pt)
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: "folderCard")
            .frame(width: cardInnerWidth, height: pageHeight, alignment: .top)
            .clipped()

            if pageCount > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<pageCount, id: \.self) { i in
                        Circle()
                            .fill(i == page ? Color.primary.opacity(0.55) : Color.primary.opacity(0.18))
                            .frame(width: 6, height: 6)
                            .contentShape(Circle())
                            .onTapGesture { withAnimation { store.folderPage = i } }
                    }
                }
            }
        }
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
            // 卡片内：放到光标格（绝对位置 = 页偏移 + 页内偏移）
            store.moveWithinFolder(folderID: folderID, itemID: di.id,
                                   toLocalIndex: page * perPage + li)
        } else {
            // 拖出卡片：移出文件夹，回到桌面末尾
            store.removeFromFolder(itemID: di.id, folderID: folderID)
        }
    }

    /// 光标 → 本页内格子偏移；在卡片外返回 nil
    private func localIndex(at pt: CGPoint) -> Int? {
        guard pt.x >= 0, pt.y >= 0, pt.x < cardInnerWidth, pt.y < pageHeight else { return nil }
        let col = min(cols - 1, max(0, Int(pt.x / (metrics.cellW + metrics.hGap))))
        let row = min(rowsPerPage - 1, max(0, Int(pt.y / (metrics.cellH + metrics.vGap))))
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

    // MARK: - 页面

    /// 一页：3×3 与主网格同尺寸的格子，从左上角排起，最后一页留白
    private func pageGrid(_ p: Int) -> some View {
        let slice = Array(items.dropFirst(p * perPage).prefix(perPage))
        return LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(metrics.cellW), spacing: metrics.hGap), count: cols),
            spacing: metrics.vGap
        ) {
            ForEach(Array(slice.enumerated()), id: \.element.id) { off, item in
                let isDragged = dragItem?.id == item.id
                FolderItemCell(item: item, folderID: folderID, iconSize: iconPt,
                               onDragChanged: { pt in handleDrag(itemID: item.id, pt: pt) },
                               onDragEnded: { pt in handleDrop(item: item, pt: pt) })
                    .opacity(isDragged ? 0.25 : 1)
                    .scaleEffect(highlightOffset == off && !isDragged ? 1.08 : 1)
                    .animation(.spring(response: 0.22, dampingFraction: 0.8), value: highlightOffset)
            }
        }
        .frame(width: cardInnerWidth, height: pageHeight, alignment: .topLeading)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 25)
            .onEnded { v in
                guard dragItem == nil else { return }   // 正在拖动图标时不翻页
                if v.translation.width < -30, page < pageCount - 1 {
                    withAnimation { store.folderPage = page + 1 }
                } else if v.translation.width > 30, page > 0 {
                    withAnimation { store.folderPage = page - 1 }
                }
            }
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
