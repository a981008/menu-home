import SwiftUI

/// 单页网格：空白处右键菜单 + 按栅格坐标摆放格子（.position 定位到格子中心）
struct PageGrid: View {

    var pageIndex: Int
    var metrics: GridMetrics

    @EnvironmentObject var store: HomeStore

    /// 本页条目（页索引越界时返回空，避免翻页动画中崩溃）
    private var items: [HomeItem] {
        pageIndex < store.pages.count ? store.pages[pageIndex] : []
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 空白区域：撑满整页，提供右键菜单
            Color.clear
                .contentShape(Rectangle())
                .contextMenu { blankMenu }

            // 格子：按扁平索引换算行/列，用 .position 放到格子中心
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                CellView(item: item, metrics: metrics, index: idx)
                    .position(position(of: item))
            }
        }
    }

    // MARK: - 桌面空白处右键菜单

    @ViewBuilder
    private var blankMenu: some View {
        Button("添加 App…") { store.addTarget = .desktopPage(store.page) }
        Button("新建文件夹") { store.newFolder() }
        Divider()
        Button("整理桌面…") { store.editMode = true }
        Button("按名称排列") { store.sortByName() }
        Divider()
        Button("设置…") { store.onOpenSettings?() }
    }

    // MARK: - 栅格定位

    /// 格子中心（本页坐标系）：cellOrigin + 半格宽高
    private func position(of item: HomeItem) -> CGPoint {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else {
            // 兜底：理论上不会发生（item 必来自本页）
            let o = metrics.cellOrigin(row: 0, col: 0)
            return CGPoint(x: o.x + metrics.cellW / 2, y: o.y + metrics.cellH / 2)
        }
        let row = idx / metrics.columns
        let col = idx % metrics.columns
        let origin = metrics.cellOrigin(row: row, col: col)
        return CGPoint(x: origin.x + metrics.cellW / 2,
                       y: origin.y + metrics.cellH / 2)
    }
}
