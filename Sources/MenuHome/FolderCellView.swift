import SwiftUI
import AppKit

/// 文件夹格子内容：iOS 同款隐喻 —— 圆角矩形盒内 3×3 微缩图标（最多前 9 个），
/// 空文件夹显示「＋」；下方一行名称
struct FolderCellView: View {

    let folder: FolderEntry
    let metrics: GridMetrics

    /// 盒子边长（格宽 - 30）
    private var iconPt: CGFloat { metrics.cellW - 30 }

    var body: some View {
        VStack(spacing: 4) {
            box
            Text(folder.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    // MARK: - 文件夹盒子

    private var box: some View {
        ZStack {
            // 盒子底板
            RoundedRectangle(cornerRadius: iconPt * 0.22)
                .fill(Color.primary.opacity(0.06))

            if folder.items.isEmpty {
                // 空文件夹：加号占位
                Image(systemName: "plus")
                    .font(.system(size: iconPt * 0.4, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                // 3×3 微缩图标（v1 文件夹内只会是 App，compactMap 兜底）
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3),
                          spacing: 2) {
                    ForEach(folder.items.compactMap { $0.appEntry }.prefix(9)) { mini in
                        Image(nsImage: NSWorkspace.shared.icon(forFile: mini.path))
                            .resizable()
                            .frame(width: iconPt * 0.26, height: iconPt * 0.26)
                    }
                }
                .padding(iconPt * 0.08)
            }
        }
        .frame(width: iconPt, height: iconPt)
    }
}
