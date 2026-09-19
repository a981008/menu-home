import SwiftUI
import AppKit

/// 桌面格子（App 或文件夹）：负责悬停缩放、编辑抖动、点按、右键菜单与编辑模式拖拽
struct CellView: View {

    let item: HomeItem
    let metrics: GridMetrics
    /// 本格在页内的扁平索引（用于换算文件夹图标位置，动画起点）
    var index: Int = 0

    @EnvironmentObject var store: HomeStore
    // 手工脱糖的 @State（本机 CLT 缺宏插件）
    private var _hovering: State<Bool> = State(initialValue: false)
    private var hovering: Bool {
        get { _hovering.wrappedValue }
        nonmutating set { _hovering.wrappedValue = newValue }
    }

    /// 本格正在被拖拽（原格半透明）
    private var isDragging: Bool { store.drag?.itemID == item.id }
    /// 本格是拖拽悬停合并候选（放大示意）
    private var isMergeTarget: Bool { store.drag?.mergeCandidateID == item.id }
    /// 本格被多选（整理模式批量移除）
    private var isSelected: Bool { store.selectedIDs.contains(item.id) }

    /// 稳定伪随机种子 0...1：由 item id 哈希取模而来，保证每次渲染抖动相位一致
    private var seed: Double {
        Double(UInt(bitPattern: item.id.hashValue) % 100) / 100
    }

    var body: some View {
        Group {
            switch item {
            case .app(let a):  AppCellView(app: a, metrics: metrics)
            case .folder(let f): FolderCellView(folder: f, metrics: metrics)
            }
        }
        .frame(width: metrics.cellW, height: metrics.cellH)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(hovering ? 0.06 : 0)))
        .scaleEffect(isMergeTarget ? 1.15 : (hovering && !store.editMode ? 1.04 : 1))
        .opacity(isDragging ? 0.25 : (isSelected ? 0.85 : 1))
        .overlay(alignment: .topLeading) { editBadge }
        .onHover { hovering = $0 }
        .modifier(JiggleModifier(active: store.editMode && !isDragging,
                                 seed: seed,
                                 reduceMotion: store.reduceMotion))
        .contentShape(Rectangle())
        .onTapGesture { tap() }
        .contextMenu { menu }
        .help(item.displayName)
        .animation(.easeInOut(duration: 0.12), value: hovering)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isMergeTarget)
        .animation(.easeOut(duration: 0.15), value: store.editMode)
    }

    // MARK: - 整理模式角标（iOS 式）：未选中 = 红 ⊖ 移除，选中 = 蓝 ✓

    /// 角标悬在图标左上角（图标距格左 15pt、距顶约 6pt，半径 8pt 内收）
    @ViewBuilder
    private var editBadge: some View {
        if store.editMode, !isDragging {
            Button {
                if isSelected {
                    store.toggleSelected(id: item.id)
                } else {
                    // 文件夹连同内容一起移出桌面（见 removeFromDesktop）
                    store.removeFromDesktop(id: item.id)
                }
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "minus.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white, isSelected ? Color.accentColor : Color.red)
            }
            .buttonStyle(.plain)
            .offset(x: 7, y: 4)
            .transition(.scale.combined(with: .opacity))
            .help(isSelected ? "取消选择" : "从桌面移除")
        }
    }

    // MARK: - 点按

    /// 点击
    private func tap() {
        // 长按进入整理模式的那次松手不算点按（suppressTapUntil 见 HomeStore）
        if CACurrentMediaTime() < store.suppressTapUntil { return }
        if store.editMode {
            // 整理模式：点格子本体 = 多选切换
            withAnimation(.easeInOut(duration: 0.15)) { store.toggleSelected(id: item.id) }
            return
        }
        switch item {
        case .app(let a):    store.launch(a)
        case .folder(let f): store.expandFolder(f.id, sourceRect: iconRect)
        }
    }

    /// 文件夹图标盒子在面板坐标系中的矩形（iOS 式展开动画的起点）
    private var iconRect: CGRect {
        let row = index / metrics.columns
        let col = index % metrics.columns
        let o = metrics.cellOrigin(row: row, col: col)
        let box = metrics.cellW - 30
        return CGRect(x: o.x + (metrics.cellW - box) / 2, y: o.y, width: box, height: box)
    }

    // MARK: - 右键菜单（见设计稿 4.7）

    @ViewBuilder
    private var menu: some View {
        switch item {
        case .app(let a):
            Button("打开") { store.launch(a) }
            Button("在 Finder 中显示") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: a.path)])
            }
            Divider()
            Button("移入新文件夹") { store.moveIntoNewFolder(itemID: item.id) }
            Button("从桌面移除", role: .destructive) {
                // 仅移除快捷方式，不卸载 App
                store.removeItem(id: item.id)
            }
            Button("整理桌面…") { store.editMode = true }

        case .folder(let f):
            Button("打开") { store.expandFolder(f.id, sourceRect: iconRect) }
            Button("重命名…") {
                store.expandedFolderID = f.id
                store.renamingFolderID = f.id
            }
            Divider()
            Button("移除文件夹（内容退回桌面）", role: .destructive) {
                store.removeItem(id: item.id)
            }
            Button("整理桌面…") { store.editMode = true }
        }
    }
}
