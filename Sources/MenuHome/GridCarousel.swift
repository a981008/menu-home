import SwiftUI

/// 桌面网格：单页可滚动 —— 行数 4/5/6 可设，内容超出可视区即滚动（不再分页）。
/// 拖影与拖拽手势都使用滚动内容坐标系（"homePanel"）：坐标随滚动一致，滚到哪拖到哪。
struct GridCarousel: View {

    @EnvironmentObject var store: HomeStore

    private var metrics: GridMetrics { store.metrics }

    /// 内容高度：随条目数增长；不足一屏时保持满屏。
    /// 拖拽中插入空位占据可见格（不在末尾时）按多一行预留，避免让位后的末行被裁
    private var contentHeight: CGFloat {
        let gapExtra = store.drag?.gapIndex.map { $0 < store.flatItems.count ? 1 : 0 } ?? 0
        let rowsNeeded = max(metrics.rows,
                             (store.flatItems.count + gapExtra + metrics.columns - 1) / metrics.columns)
        return metrics.topPad + CGFloat(rowsNeeded) * (metrics.cellH + metrics.vGap) - metrics.vGap + 12
    }

    /// 空白按下日志节流（临时诊断）
    private static var lastBlankLog: CFTimeInterval = 0

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
            // 拖拽唯一驱动：内容层单一手势全程掌控（按下格提起 → 移动 → 松手落位）。
            // 宿主在拖拽全程存活，事件绝不丢失；不用格子上的手势（提起即移除宿主，交付不可靠）
            .simultaneousGesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .named("homePanel"))
                    .onChanged { v in
                        if store.drag == nil {
                            // 按下位置所在格的条目提起（空白处按下不启动拖拽）
                            if let idx = metrics.index(at: v.startLocation),
                               idx < store.flatItems.count {
                                dragDebugLog("gesture start=\(v.startLocation) → idx=\(idx) → beginDrag")
                                store.beginDrag(itemID: store.flatItems[idx].id)
                            } else if CACurrentMediaTime() - Self.lastBlankLog > 1 {
                                Self.lastBlankLog = CACurrentMediaTime()
                                dragDebugLog("gesture 空白按下 start=\(v.startLocation) count=\(store.flatItems.count)")
                            }
                        }
                        if store.drag != nil {
                            store.dragMoved(to: v.location, metrics: metrics)
                        }
                    }
                    .onEnded { _ in
                        dragDebugLog("gesture onEnded hasDrag=\(store.drag != nil)")
                        if store.drag != nil {
                            store.endDrag()
                        }
                    }
            )
            .simultaneousGesture(
                // iOS 同款：长按 0.5s 进入整理模式（抖动），随后继续拖动即整理排列；
                // 移动超过 8pt 判定失败（正常拖动交给上方拖拽手势，二者并行互不干扰）。
                // 空白处长按同样进入（iOS 桌面同款）
                LongPressGesture(minimumDuration: 0.5, maximumDistance: 8)
                    .onEnded { _ in
                        store.suppressTapUntil = CACurrentMediaTime() + 0.4
                        if !store.editMode {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                store.editMode = true
                            }
                        }
                    }
            )
            // 顶部让出搜索栏高度：滚动内容从液态玻璃搜索栏下穿过（iOS 同款玻璃栏下滚动）。
            // padding 在 "homePanel" 命名坐标系之外 —— 手势坐标仍是内容坐标，拖拽换算不受影响
            .padding(.top, metrics.searchBarArea)
        }
        // App 式胶囊滚轴 + 滚动内容与滚轴都裁剪进面板圆角内（圆角外不露直角）
        .appScrollbar()
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
    }
}
