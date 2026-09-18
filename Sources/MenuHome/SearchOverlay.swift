import AppKit
import SwiftUI

/// 搜索覆盖层（非常驻：键盘直入或 ⌘F 呼出，从顶部滑下）
struct SearchOverlay: View {
    @EnvironmentObject var store: HomeStore

    // 手工脱糖的 @State（本机 CLT 缺宏插件）
    private var _query: State<String> = State(initialValue: "")
    private var query: String {
        get { _query.wrappedValue }
        nonmutating set { _query.wrappedValue = newValue }
    }
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { store.closeSearch() }

            sheet
                .padding(.horizontal, 12)
                .padding(.top, 10)
        }
    }

    private var sheet: some View {
        VStack(spacing: 10) {
            searchField
            resultArea
        }
        .padding(12)
        .liquidGlass(cornerRadius: Theme.sheetRadius)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索 App…", text: _query.projectedValue)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .onSubmit { activateFirst() }
            if !query.isEmpty {
                Button {
                    query = ""
                    focused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
        .onAppear {
            query = store.searchSeedText
            focused = true
        }
        .onChange(of: query) { store.searchQuery = $0 }
    }

    @ViewBuilder
    private var resultArea: some View {
        let results = store.searchResults()
        if results.isEmpty {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("输入以搜索")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 16)
            } else {
                VStack(spacing: 10) {
                    Text("没有找到“\(query)”")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button("添加 App…") {
                        store.addTarget = .desktopPage(store.page)
                        store.closeSearch()
                    }
                    .glassButton()
                    .controlSize(.small)
                }
                .padding(.vertical, 14)
            }
        } else {
            ScrollView(.vertical) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible()), count: store.metrics.columns),
                    spacing: 12
                ) {
                    ForEach(results) { item in
                        SearchResultCell(item: item)
                    }
                }
                .padding(.bottom, 4)
            }
            .frame(maxHeight: store.metrics.panelH - 130)
        }
    }

    private func activateFirst() {
        guard let first = store.searchResults().first else { return }
        activate(first)
    }

    private func activate(_ item: HomeItem) {
        switch item {
        case .app(let entry):
            store.closeSearch()
            store.launch(entry)
        case .folder(let folder):
            store.closeSearch()
            store.expandFolder(folder.id)
        }
    }
}

// MARK: - 搜索结果格子

private struct SearchResultCell: View {
    let item: HomeItem
    @EnvironmentObject var store: HomeStore
    private var _hovering: State<Bool> = State(initialValue: false)
    private var hovering: Bool {
        get { _hovering.wrappedValue }
        nonmutating set { _hovering.wrappedValue = newValue }
    }

    var body: some View {
        VStack(spacing: 4) {
            icon
                .frame(width: 40, height: 40)
            Text(item.displayName)
                .font(.system(size: 11))
                .lineLimit(1)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(hovering ? 0.06 : 0)))
        .scaleEffect(hovering ? 1.04 : 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { activate() }
    }

    @ViewBuilder
    private var icon: some View {
        switch item {
        case .app(let entry):
            Image(nsImage: NSWorkspace.shared.icon(forFile: entry.path))
                .resizable()
        case .folder(let folder):
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.primary.opacity(0.08))
                .overlay(
                    Image(systemName: "folder")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                )
                .overlay(
                    Text("\(folder.items.count)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .offset(y: 12),
                    alignment: .bottom
                )
        }
    }

    private func activate() {
        switch item {
        case .app(let entry):
            store.closeSearch()
            store.launch(entry)
        case .folder(let folder):
            store.closeSearch()
            store.expandFolder(folder.id)
        }
    }
}
