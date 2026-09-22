import SwiftUI

/// 编辑模式顶部提示条：左侧引导文案，右侧「删除」（有选中时）、「＋ 添加」与「✓ 完成」
/// 由 HomeView 作为浮层放置；自身把内容顶对齐到面板顶部。
/// 文件夹卡片展开时同样悬浮显示（v1.3：卡片内多选与桌面同款）——
/// 「删除」变为「移出」（选中项移出文件夹回桌面），「＋ 添加」把 App 加入当前文件夹（v1.4）
struct EditBar: View {

    @EnvironmentObject var store: HomeStore

    /// 文件夹卡片展开中（整理条切换为卡片上下文）
    private var folderContext: Bool { store.expandedFolderID != nil }

    var body: some View {
        HStack(spacing: 8) {
            Text(store.selectedIDs.isEmpty
                 ? (folderContext ? "拖动排序 · 点选图标多选" : "拖动排序 · 拖到图标上可建文件夹 · 点选图标多选")
                 : "已选 \(store.selectedIDs.count) 项")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            if !store.selectedIDs.isEmpty {
                Button {
                    if folderContext {
                        // 文件夹内选中：移出文件夹（回到桌面末尾），非破坏性
                        store.removeSelectedFromFolder(store.expandedFolderID!)
                    } else {
                        // 无二次确认（iOS 同款）；文件夹连同内容一起移除
                        store.removeSelectedFromDesktop()
                    }
                } label: {
                    Label(folderContext ? "移出" : "删除",
                          systemImage: folderContext ? "rectangle.portrait.and.arrow.right" : "trash")
                        .font(.system(size: 12))
                }
                .tint(folderContext ? .accentColor : .red)
                .glassButton()
            }
            // ＋ 添加：桌面上下文添加到桌面；文件夹上下文添加到当前文件夹（v1.4）
            Button("＋ 添加") {
                if let fid = store.expandedFolderID {
                    store.addTarget = .folder(fid)
                } else {
                    store.addTarget = .desktop
                }
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
