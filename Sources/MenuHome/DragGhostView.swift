import SwiftUI
import AppKit

/// 编辑模式拖拽的拖影：跟随手指/光标移动，悬停到合并候选上时描边高亮
struct DragGhostView: View {

    let item: HomeItem
    /// 拖拽点跟踪器（独立于 HomeStore：鼠标移动只重渲染拖影本身）
    @ObservedObject var tracker: GhostTracker
    /// 是否悬停在合并候选上（描边提示）
    var merging: Bool = false

    @EnvironmentObject var store: HomeStore

    /// 图标边长：与主网格一致（格宽 - 30）
    private var iconPt: CGFloat { store.metrics.cellW - 30 }

    var body: some View {
        VStack(spacing: 4) {
            ghostIcon
            Text(item.displayName)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary)
        }
        .padding(8)
        .liquidGlass(cornerRadius: Theme.ghostRadius)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.ghostRadius)
                .stroke(merging ? Color.primary.opacity(0.5) : .clear, lineWidth: 2)
        )
        .scaleEffect(1.1)
        .shadow(color: .black.opacity(0.25), radius: 12)
        .position(tracker.point)
    }

    // MARK: - 拖影图标

    @ViewBuilder
    private var ghostIcon: some View {
        switch item {
        case .app(let a):
            // App：真实系统图标
            Image(nsImage: AppScanner.cachedIcon(forPath: a.path))
                .resizable()
                .frame(width: iconPt, height: iconPt)
        case .folder(let f):
            // 文件夹：简版圆角盒 + 首个 App 微缩图标（空则「＋」占位）
            ZStack {
                RoundedRectangle(cornerRadius: iconPt * 0.22)
                    .fill(Color.primary.opacity(0.06))
                if let first = f.items.compactMap({ $0.appEntry }).first {
                    Image(nsImage: AppScanner.cachedIcon(forPath: first.path))
                        .resizable()
                        .frame(width: iconPt * 0.5, height: iconPt * 0.5)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: iconPt, height: iconPt)
        }
    }
}
