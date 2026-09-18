import SwiftUI

/// 空状态引导（首次启动 / 桌面被清空时居中显示）
struct EmptyStateView: View {

    @EnvironmentObject var store: HomeStore

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "house")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("还没有 App")
                .font(.system(size: 13, weight: .semibold))
            Text("把常用的 App 放进你的状态栏桌面")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button("＋ 添加第一个 App") {
                store.addTarget = .desktopPage(store.page)
            }
            .glassProminentButton()
        }
    }
}
