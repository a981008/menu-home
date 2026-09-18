import SwiftUI
import AppKit

/// 桌面格子（App 或文件夹）：负责悬停缩放、编辑抖动、点按、右键菜单与编辑模式拖拽
struct CellView: View {

    let item: HomeItem
    let metrics: GridMetrics

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
        .scaleEffect(isMergeTarget ? 1.15 : (hovering && !store.editMode ? 1.04 : 1))
        .opacity(isDragging ? 0.25 : 1)
        .onHover { hovering = $0 }
        .modifier(JiggleModifier(active: store.editMode && !isDragging,
                                 seed: seed,
                                 reduceMotion: store.reduceMotion))
        .contentShape(Rectangle())
        .onTapGesture { tap() }
        .contextMenu { menu }
        .help(item.displayName)
        .simultaneousGesture(editDrag)
        // 长按进入编辑模式（iPhone 桌面同款入口）
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35)
                .onEnded { _ in
                    guard !store.editMode else { return }
                    withAnimation { store.editMode = true }
                }
        )
        // 悬停缩放 / 合并候选放大动效（设计稿 4.2：120ms）
        .animation(.easeInOut(duration: 0.12), value: hovering)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isMergeTarget)
    }

    // MARK: - 点按

    /// 编辑模式下点击无效（避免误触启动）
    private func tap() {
        if store.editMode { return }
        switch item {
        case .app(let a):    store.launch(a)
        case .folder(let f): store.expandFolder(f.id)
        }
    }

    // MARK: - 编辑模式拖拽

    /// 编辑模式的拖拽手势（homePanel 坐标系）；
    /// 非编辑模式返回一个永不触发的占位手势，保持视图类型一致、避免悬空分支
    private var editDrag: AnyGesture<DragGesture.Value> {
        let gesture = DragGesture(minimumDistance: 6, coordinateSpace: .named("homePanel"))
            .onChanged { v in
                guard store.editMode else { return }
                if store.drag == nil {
                    store.beginDrag(itemID: item.id)
                }
                if store.drag != nil {
                    store.dragMoved(to: v.location, metrics: metrics)
                }
            }
            .onEnded { _ in
                if store.drag != nil {
                    store.endDrag()
                }
            }
        guard store.editMode else {
            // 最小拖动距离设为无穷大：手势永远不满足触发条件
            return AnyGesture(DragGesture(minimumDistance: .infinity,
                                          coordinateSpace: .named("homePanel")))
        }
        return AnyGesture(gesture)
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
            Button("打开") { store.expandFolder(f.id) }
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
