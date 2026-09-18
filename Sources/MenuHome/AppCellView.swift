import SwiftUI
import AppKit

/// App 格子内容：真实系统图标（自带 macOS 圆角）+ 名称，
/// 右下角「正在运行」圆点、右上角「缺失」问号角标
struct AppCellView: View {

    let app: AppEntry
    let metrics: GridMetrics

    @EnvironmentObject var store: HomeStore

    /// 图标边长（格宽 - 30）
    private var iconPt: CGFloat { metrics.cellW - 30 }

    var body: some View {
        VStack(spacing: 4) {
            iconArea
            Text(app.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary)
        }
    }

    // MARK: - 图标区

    private var iconArea: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
            .resizable()
            .frame(width: iconPt, height: iconPt)
            .overlay(alignment: .bottomTrailing) { runningDot }
            .overlay(alignment: .topTrailing) { missingBadge }
    }

    /// 正在运行圆点：⌀7，label 色 60% + 1pt 面板底色描边（同 Dock 语义，可在设置关闭）
    @ViewBuilder
    private var runningDot: some View {
        if store.settings.showRunningDot,
           store.runningBundleIDs.contains(app.bundleID) {
            Circle()
                .fill(Color.primary.opacity(0.6))
                .frame(width: 7, height: 7)
                .overlay(
                    Circle()
                        .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1)
                )
        }
    }

    /// 缺失角标：App 路径失效时右上角灰色「?」
    @ViewBuilder
    private var missingBadge: some View {
        if store.missingBundleIDs.contains(app.bundleID) {
            Circle()
                .fill(Color(nsColor: .systemGray))
                .frame(width: 12, height: 12)
                .overlay(
                    Text("?")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                )
        }
    }
}
