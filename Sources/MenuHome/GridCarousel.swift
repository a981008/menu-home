import SwiftUI

/// 分页桌面轮播：横向 HStack 摆放所有页，按 store.page 偏移；拖拽时叠加拖影
struct GridCarousel: View {

    @EnvironmentObject var store: HomeStore

    private var metrics: GridMetrics { store.metrics }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 分页网格
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(store.pages.indices, id: \.self) { p in
                        PageGrid(pageIndex: p, metrics: metrics)
                            .frame(width: geo.size.width,
                                   height: geo.size.height,
                                   alignment: .topLeading)
                            .clipped()
                    }
                }
                .offset(x: -CGFloat(store.page) * geo.size.width)
                .animation(.spring(response: 0.3, dampingFraction: 0.92), value: store.page)
            }

            // 拖影跟随（编辑模式拖拽中；不拦截事件）
            if let d = store.drag {
                DragGhostView(item: d.item, point: d.point, merging: d.mergeCandidateID != nil)
                    .allowsHitTesting(false)
            }
        }
    }
}
