import SwiftUI

/// 单页网格：空白处右键菜单 + 按栅格坐标摆放格子（.position 定位到格子中心）
struct PageGrid: View {

    var metrics: GridMetrics

    @EnvironmentObject var store: HomeStore

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 空白区域：撑满整页，提供右键菜单；整理模式下点击空白即退出（iOS 同款）
            Color.clear
                .contentShape(Rectangle())
                .contextMenu { blankMenu }
                .onTapGesture {
                    if store.editMode {
                        store.exitEditMode()
                    }
                }

            // 格子：按扁平索引换算行/列，用 .position 放到格子中心
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                CellView(item: item, metrics: metrics, index: idx)
                    .position(displayPosition(closedIndex: idx))
            }
        }
    }

    /// 桌面条目（单列表）
    private var items: [HomeItem] {
        store.pages.first ?? []
    }

    // MARK: - 桌面空白处右键菜单

    @ViewBuilder
    private var blankMenu: some View {
        Button("添加 App…") { store.addTarget = .desktop }
        Button("新建文件夹") { store.newFolder() }
        Divider()
        Button("整理桌面…") { store.editMode = true }
        Button("按名称排列") { store.sortByName() }
        Divider()
        Button("设置…") { store.onOpenSettings?() }
    }

    // MARK: - 栅格定位

    /// 格子中心（本页坐标系）。拖拽中：插入空位之后的条目整体让位一格，
    /// 空位处留白（iOS 式落点预览，随 applyGap 弹簧动画）
    private func displayPosition(closedIndex idx: Int) -> CGPoint {
        let display = idx + (store.drag?.gapIndex.map { idx >= $0 ? 1 : 0 } ?? 0)
        let row = display / metrics.columns
        let col = display % metrics.columns
        let origin = metrics.cellOrigin(row: row, col: col)
        return CGPoint(x: origin.x + metrics.cellW / 2,
                       y: origin.y + metrics.cellH / 2)
    }
}
