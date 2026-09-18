import SwiftUI

/// 分页页点：多于 1 页时浮在面板底部；当前页实心，其余弱化；点击跳页
struct PageDotsView: View {

    @EnvironmentObject var store: HomeStore

    var body: some View {
        if store.pages.count > 1 {
            HStack(spacing: 6) {
                ForEach(0..<store.pages.count, id: \.self) { i in
                    Circle()
                        .frame(width: 7, height: 7)
                        .foregroundStyle(i == store.page ? Color.primary : Color.primary.opacity(0.3))
                        .onTapGesture {
                            store.goToPage(i)
                        }
                }
            }
        } else {
            // 单页时不占位
            Color.clear.frame(height: 0)
        }
    }
}
