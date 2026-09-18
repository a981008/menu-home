import SwiftUI

/// 主面板「桌面」根视图：毛玻璃 + 分页网格 + 页点，按需叠加
/// 编辑条 / 文件夹展开 / 搜索 / 添加 App 覆盖层（后三者为其他模块实现）
struct HomeView: View {

    @EnvironmentObject var store: HomeStore

    private var metrics: GridMetrics { store.metrics }

    /// 有覆盖层展开（文件夹 / 搜索 / 添加 App）时压暗模糊桌面
    private var dim: Bool {
        store.expandedFolderID != nil || store.searchActive || store.addTarget != nil
    }

    var body: some View {
        ZStack {
            // 分页桌面网格：有覆盖层时压暗 + 模糊，且不响应点击
            GridCarousel()
                .blur(radius: dim ? 16 : 0)
                .opacity(dim ? 0.45 : 1)
                .allowsHitTesting(!dim)

            // 页点浮在底部
            VStack {
                Spacer()
                PageDotsView()
                    .padding(.bottom, 8)
            }

            // 空状态引导（首次启动 / 桌面被清空）
            if store.isEmpty {
                EmptyStateView()
            }

            // 编辑模式提示条（浮在顶部；有覆盖层时随桌面一起隐藏）
            if store.editMode && !dim {
                EditBar()
            }

            // 文件夹展开覆盖层（另一模块实现）
            if let fid = store.expandedFolderID {
                FolderOverlay(folderID: fid)
            }

            // 搜索覆盖层（另一模块实现）
            if store.searchActive {
                SearchOverlay()
            }

            // 添加 App 覆盖层（另一模块实现）
            if let t = store.addTarget {
                AddAppOverlay(target: t)
            }
        }
        .frame(width: metrics.pageW, height: metrics.panelH)
        // 面板本体：液态玻璃大圆角（macOS 26+ glassEffect / 旧系统厚材质）
        .liquidGlass(cornerRadius: Theme.panelRadius)
        // 面板坐标系：格子拖拽手势与拖影均以此为基准
        .coordinateSpace(name: "homePanel")
        .animation(.easeInOut(duration: 0.2), value: dim)
        // 启动失败弹窗：App 可能已被删除或移动
        .alert(
            "未找到 App",
            isPresented: Binding(
                get: { store.launchFailure != nil },
                set: { if !$0 { store.launchFailure = nil } }
            )
        ) {
            Button("从桌面移除", role: .destructive) {
                store.dismissLaunchFailure(remove: true)
            }
            Button("保留", role: .cancel) {
                store.launchFailure = nil
            }
        } message: {
            Text("找不到「\(store.launchFailure?.name ?? "")」，它可能已被删除或移动。是否从桌面移除？")
        }
    }
}
