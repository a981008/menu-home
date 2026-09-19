import SwiftUI

/// 编辑模式顶部提示条：左侧引导文案，右侧「删除」（有选中时）、「＋ 添加」与「✓ 完成」
/// 由 HomeView 作为浮层放置；自身把内容顶对齐到面板顶部
struct EditBar: View {

    @EnvironmentObject var store: HomeStore

    var body: some View {
        HStack(spacing: 8) {
            Text(store.selectedIDs.isEmpty
                 ? "拖动排序 · 拖到图标上可建文件夹 · 点选图标多选"
                 : "已选 \(store.selectedIDs.count) 项")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            if !store.selectedIDs.isEmpty {
                Button {
                    // 无二次确认（iOS 同款）；文件夹连同内容一起移除
                    store.removeSelectedFromDesktop()
                } label: {
                    Label("删除", systemImage: "trash")
                        .font(.system(size: 12))
                }
                .tint(.red)
                .glassButton()
            }
            Button("＋ 添加") {
                store.addTarget = .desktop
            }
            .glassButton()
            Button("✓ 完成") {
                store.exitEditMode()
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
        .animation(.easeOut(duration: 0.15), value: store.selectedIDs.isEmpty)
    }
}
