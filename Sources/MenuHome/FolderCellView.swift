import SwiftUI
import AppKit

/// 文件夹格子内容：iOS 同款隐喻 —— 圆角矩形盒内 3×3 微缩图标（最多前 9 个），
/// 空文件夹显示「＋」；下方一行名称
struct FolderCellView: View {

    let folder: FolderEntry
    let metrics: GridMetrics

    /// 盒子边长（格宽 - 30，与 App 图标同尺寸）
    private var iconPt: CGFloat { metrics.cellW - 30 }

    /// 桌面相邻图标的边缘间隙（格内边距 15×2 + 列距 12）
    private var gridGap: CGFloat { 30 + metrics.hGap }

    /// 缩略图间隙：与桌面「图标:间隙」严格等比例（3×mini + 4×gap = 盒边长）
    private var thumbGap: CGFloat { iconPt * gridGap / (3 * iconPt + 4 * gridGap) }

    /// 缩略图边长：等比例对应桌面图标（mini:gap = 图标:桌面间隙）
    private var thumbSize: CGFloat { iconPt * thumbGap / gridGap }

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
                // 3×3 微缩图标（最多前 9 个）：与桌面网格等比例、从左上角排起（iPhone 同款）
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(thumbSize), spacing: thumbGap), count: 3),
                    spacing: thumbGap
                ) {
                    ForEach(folder.items.compactMap { $0.appEntry }.prefix(9)) { mini in
                        Image(nsImage: NSWorkspace.shared.icon(forFile: mini.path))
                            .resizable()
                            .frame(width: thumbSize, height: thumbSize)
                    }
                }
                .padding(thumbGap)
                .frame(width: iconPt, height: iconPt, alignment: .topLeading)
            }
        }
        .frame(width: iconPt, height: iconPt)
    }
}
