import SwiftUI
import AppKit

/// 编辑模式拖拽的拖影：跟随手指/光标移动，悬停到合并候选上时描边高亮
struct DragGhostView: View {

    let item: HomeItem
    /// 拖拽点（homePanel 坐标系）
    let point: CGPoint
    /// 是否悬停在合并候选上（描边提示）
    var merging: Bool = false

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
        .position(point)
    }

    // MARK: - 拖影图标

    @ViewBuilder
    private var ghostIcon: some View {
        switch item {
        case .app(let a):
            // App：真实系统图标
            Image(nsImage: NSWorkspace.shared.icon(forFile: a.path))
                .resizable()
                .frame(width: 48, height: 48)
        case .folder(let f):
            // 文件夹：简版圆角盒 + 首个 App 微缩图标（空则「＋」占位）
            ZStack {
                RoundedRectangle(cornerRadius: 48 * 0.22)
                    .fill(Color.primary.opacity(0.06))
                if let first = f.items.compactMap({ $0.appEntry }).first {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: first.path))
                        .resizable()
                        .frame(width: 48 * 0.5, height: 48 * 0.5)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 48, height: 48)
        }
    }
}
