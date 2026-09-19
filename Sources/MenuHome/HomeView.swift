import SwiftUI
import UniformTypeIdentifiers

/// 主面板「桌面」根视图：手绘窗口阴影 + 毛玻璃 + 顶部常驻搜索栏 + 滚动网格，按需叠加
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
            // 手绘窗口阴影（系统阴影按整窗矩形采样、圆角外露直角，已禁用 —— 见 PanelController）
            PanelShadowBackdrop(metrics: metrics)

            panelContent
        }
        // 四周留 shadowMargin 透明边距容纳阴影外溢（窗口即此尺寸，见 PanelController）
        .frame(width: metrics.pageW + Theme.shadowMargin * 2,
               height: metrics.panelH + Theme.shadowMargin * 2)
        // 窗口上探进菜单栏区域时系统会注入顶部安全区 inset 把内容推低（贴不上状态栏）——
        // 双保险：宿主视图已清零安全区，这里再显式忽略
        .ignoresSafeArea()
        // 控制中心式弹出动画：以状态栏图标为锚点缩放 + 淡入
        .scaleEffect(store.panelVisible ? 1 : 0.7, anchor: store.panelAnchor)
        .opacity(store.panelVisible ? 1 : 0)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: store.panelVisible)
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

    /// 玻璃面板本体（尺寸 = 可见玻璃：pageW × panelH，在含边距的窗口内居中）
    private var panelContent: some View {
        ZStack {
            // 滚动桌面网格：有覆盖层时压暗 + 模糊，且不响应点击。
            // 常驻搜索栏浮在网格上层（液态玻璃）：图标滚动时从栏下穿过、被玻璃折射。
            // 压暗模糊的结果必须裁进面板同形圆角：blur 不裁剪，模糊内容会从玻璃边界
            // 向外渗出（矩形光晕，与 ScrollView 直角外露同一类问题）
            GridCarousel()
                .blur(radius: dim ? 16 : 0)
                .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
                .opacity(dim ? 0.45 : 1)
                .allowsHitTesting(!dim)
                .overlay(alignment: .top) {
                    if !store.editMode {
                        ResidentSearchBar()
                            .padding(.top, 10)
                    }
                }

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
        // Finder 拖入 .app 悬停高亮（面板描边）
        .overlay(
            RoundedRectangle(cornerRadius: Theme.panelRadius)
                .stroke(Color.accentColor.opacity(store.dropTargeted ? 0.9 : 0), lineWidth: 3)
                .animation(.easeInOut(duration: 0.15), value: store.dropTargeted)
                .allowsHitTesting(false)
        )
        // 接收 Finder 拖入的 .app：加入桌面末尾（拖放区 = 可见玻璃范围）
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

/// 手绘窗口阴影：与玻璃面板同形的圆角矩形经模糊成柔影，再用反向遮罩把玻璃矩形以内镂空。
/// - 不用系统窗口阴影的原因：无边框玻璃窗口的阴影形状被 AppKit 按整窗矩形采样
///   （invalidateShadow 重采样无效），圆角外出现直角阴影边界
/// - 镂空的原因：玻璃是半透明材质，阴影垫在玻璃正后方会被采进玻璃观感（整体发暗）
private struct PanelShadowBackdrop: View {

    let metrics: GridMetrics

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
        return shape
            .fill(Color.black.opacity(Theme.shadowOpacity))
            .blur(radius: Theme.shadowBlur)
            .offset(y: Theme.shadowOffsetY)
            .frame(width: metrics.pageW, height: metrics.panelH)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .mask {
                Rectangle()
                    .overlay(
                        shape
                            .fill(Color.black)
                            .frame(width: metrics.pageW, height: metrics.panelH)
                            .blendMode(.destinationOut)
                    )
                    .compositingGroup()
            }
    }
}

/// 常驻搜索栏：面板顶部居中；点击进入搜索覆盖层
/// （覆盖层输入框与「添加 App」搜索框同款样式：roundedBorder / 12pt / 宽 200）
struct ResidentSearchBar: View {

    @EnvironmentObject var store: HomeStore

    // 手工脱糖的 @State（本机 CLT 缺宏插件）
    private var _hovering: State<Bool> = State(initialValue: false)
    private var hovering: Bool {
        get { _hovering.wrappedValue }
        nonmutating set { _hovering.wrappedValue = newValue }
    }

    var body: some View {
        Button {
            store.openSearch(seed: "")
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                Text("搜索 App")
                    .font(.system(size: 12))
            }
            .foregroundStyle(.secondary)
            .padding(.leading, 12)
            .frame(width: 200, height: 30, alignment: .leading)
            .contentShape(Rectangle())
            .liquidGlass(cornerRadius: Theme.searchBarRadius)
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering ? 1.03 : 1)
        .animation(.easeInOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
    }
}
