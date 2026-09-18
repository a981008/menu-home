import AppKit
import SwiftUI

/// 搜索覆盖层（由顶部常驻搜索栏 / 键盘直入 / ⌘F 呼出）。
/// 与「添加 App」覆盖层**完全同构**：顶栏（图标 + 居中输入框 + 取消）/ 分隔线 / 行列表；
/// 只列本机 App（不含 MenuHome 文件夹），空查询 = 全量，点行即启动。
struct SearchOverlay: View {
    @EnvironmentObject var store: HomeStore

    // 手工脱糖的 @State（本机 CLT 缺宏插件）
    private var _query: State<String> = State(initialValue: "")
    private var query: String {
        get { _query.wrappedValue }
        nonmutating set { _query.wrappedValue = newValue }
    }
    private var _apps: State<[AppEntry]> = State(initialValue: [])
    private var apps: [AppEntry] {
        get { _apps.wrappedValue }
        nonmutating set { _apps.wrappedValue = newValue }
    }
    @FocusState private var focused: Bool

    /// 结果 = 全部本机 App；按名称过滤（空查询 = 全量）。不含 MenuHome 文件夹
    private var results: [AppEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Divider()
                list
            }
            .liquidGlass(cornerRadius: Theme.overlayRadius)
            .padding(1)
        }
    }

    // MARK: 顶栏（与「添加 App」一致：图标 + 居中输入框 + 取消，无标题文字）

    private var topBar: some View {
        ZStack {
            // 输入框在顶栏正中
            TextField("搜索 App…", text: _query.projectedValue)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .frame(width: 200)
                .focused($focused)
                .onSubmit { activateFirst() }
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消") {
                    store.closeSearch()
                }
                .glassButton()
                .controlSize(.small)
            }
        }
        .padding(12)
        .onAppear {
            query = store.searchSeedText
            focused = true
        }
    }

    // MARK: 列表（与「添加 App」同一套行样式）

    private var list: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(results) { entry in
                    SearchRow(entry: entry)
                }
                if results.isEmpty {
                    Text(apps.isEmpty ? "正在扫描本机 App…" : "没有匹配「\(query)」的 App")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 24)
                    if !apps.isEmpty {
                        Button("添加 App…") {
                            store.addTarget = .desktop
                            store.closeSearch()
                        }
                        .glassButton()
                        .controlSize(.small)
                        .padding(.bottom, 16)
                    }
                }
            }
        }
        // 滚动内容与滚轴裁剪进浮层圆角内（与面板圆角对齐，圆角外不露直角）
        .clipShape(RoundedRectangle(cornerRadius: Theme.overlayRadius, style: .continuous))
        .task {
            // 打开覆盖层时取本机 App 列表（带缓存：首次扫描后不再重复走盘）
            if apps.isEmpty {
                apps = AppScanner.cachedApps()
            }
        }
    }

    private func activateFirst() {
        guard let first = results.first else { return }
        store.closeSearch()
        store.launch(first)
    }
}

// MARK: - 结果行（与「添加 App」行样式一致：图标 32 + 名称/副行，悬停高亮）

private struct SearchRow: View {
    let entry: AppEntry
    @EnvironmentObject var store: HomeStore
    private var _hovering: State<Bool> = State(initialValue: false)
    private var hovering: Bool {
        get { _hovering.wrappedValue }
        nonmutating set { _hovering.wrappedValue = newValue }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: AppScanner.cachedIcon(forPath: entry.path))
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text((entry.path as NSString).deletingLastPathComponent)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(hovering ? 0.06 : 0))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            store.closeSearch()
            store.launch(entry)
        }
    }
}
