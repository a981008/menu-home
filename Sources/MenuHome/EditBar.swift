import SwiftUI

/// 编辑模式顶部提示条：左侧引导文案，右侧「＋ 添加」与「✓ 完成」
/// 由 HomeView 作为浮层放置；自身把内容顶对齐到面板顶部
struct EditBar: View {

    @EnvironmentObject var store: HomeStore

    var body: some View {
        HStack {
            Text("拖动排序 · 拖到图标上可建文件夹")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button("＋ 添加") {
                store.addTarget = .desktopPage(store.page)
            }
            .glassButton()
            Button("✓ 完成") {
                withAnimation {
                    store.editMode = false
                }
            }
            .glassButton()
        }
        .padding(.horizontal, 16)
        .frame(height: 42)
        // 液态玻璃悬浮胶囊（macOS 26+ glassEffect / 旧系统厚材质）
        .liquidGlass(cornerRadius: Theme.pillRadius)
        .padding(.horizontal, 14)
        // 撑满面板高度并把内容顶对齐（作为浮层由 HomeView 放入 ZStack）
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 10)
    }
}
