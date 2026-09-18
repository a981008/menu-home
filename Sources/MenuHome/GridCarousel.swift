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
        ScrollView(.vertical, showsIndicators: false) {
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
            // 兜底拖拽流：拖拽项提起后其格子视图被移除，格子上的手势流可能中断；
            // 内容层手势宿主在拖拽全程存活，保证移动/松手事件不丢。双路同驱幂等，互不冲突
            .simultaneousGesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .named("homePanel"))
                    .onChanged { v in
                        if store.drag != nil {
                            store.dragMoved(to: v.location, metrics: metrics)
                        }
                    }
                    .onEnded { _ in
                        if store.drag != nil {
                            store.endDrag()
                        }
                    }
            )
        }
        // App 式胶囊滚轴 + 滚动内容与滚轴都裁剪进面板圆角内（圆角外不露直角）
        .appScrollbar()
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
    }
}
