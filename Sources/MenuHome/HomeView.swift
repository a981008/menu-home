import SwiftUI
import UniformTypeIdentifiers

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

            // 空状态引导（首次启动 / 桌面被清空）
            if store.isEmpty {
                EmptyStateView()
            }

            // 编辑模式提示条（浮在顶部；有覆盖层时随桌面一起隐藏）
            if store.editMode && !dim {
                EditBar()
            }

            // 文件夹展开覆盖层（另一模块实现；开合动画在卡片内部以图标为锚点）
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
        // 面板本体：液态玻璃大圆角
        .liquidGlass(cornerRadius: Theme.panelRadius)
        // 控制中心式弹出动画：以状态栏图标为锚点缩放 + 淡入
        .scaleEffect(store.panelVisible ? 1 : 0.7, anchor: store.panelAnchor)
        .opacity(store.panelVisible ? 1 : 0)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: store.panelVisible)
        // 面板坐标系由 GridCarousel 的滚动内容注册（"homePanel"）
        .animation(.easeInOut(duration: 0.2), value: dim)
        // Finder 拖入 .app 悬停高亮（面板描边）
        .overlay(
            RoundedRectangle(cornerRadius: Theme.panelRadius)
                .stroke(Color.accentColor.opacity(store.dropTargeted ? 0.9 : 0), lineWidth: 3)
                .animation(.easeInOut(duration: 0.15), value: store.dropTargeted)
                .allowsHitTesting(false)
        )
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
        // 接收 Finder 拖入的 .app：加入当前页末尾
        .onDrop(of: [.fileURL], isTargeted: $store.dropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        store.handleDroppedApp(at: url.path)
                    }
                }
            }
            return true
        }
    }
}
