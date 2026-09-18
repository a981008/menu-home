import SwiftUI

/// 桌面网格：单页可滚动 —— 行数 4/5/6 可设，内容超出可视区即滚动（不再分页）。
/// 拖影与拖拽手势都使用滚动内容坐标系（"homePanel"）：坐标随滚动一致，滚到哪拖到哪。
struct GridCarousel: View {

    @EnvironmentObject var store: HomeStore

    private var metrics: GridMetrics { store.metrics }

    /// 内容高度：随条目数增长；不足一屏时保持满屏
    private var contentHeight: CGFloat {
        let rowsNeeded = max(metrics.rows, (store.flatItems.count + metrics.columns - 1) / metrics.columns)
        return metrics.topPad + CGFloat(rowsNeeded) * (metrics.cellH + metrics.vGap) - metrics.vGap + 12
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            ZStack(alignment: .topLeading) {
                PageGrid(metrics: metrics)
                    .frame(width: metrics.pageW, height: contentHeight, alignment: .topLeading)

                // 拖影跟随（拖拽中；不拦截事件），位置在内容坐标系
                if let d = store.drag, store.ghost.started {
                    DragGhostView(item: d.item, tracker: store.ghost, merging: d.mergeCandidateID != nil)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: metrics.pageW, height: contentHeight, alignment: .topLeading)
            .coordinateSpace(name: "homePanel")
        }
        // 滚动内容与滚轴都裁剪进面板圆角内（App 式滚轴，圆角外不露直角）
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
    }
}
