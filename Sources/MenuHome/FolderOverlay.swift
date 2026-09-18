import AppKit
import SwiftUI

/// 文件夹展开覆盖层（面板内，iPhone 同款卡片）
struct FolderOverlay: View {
    let folderID: UUID
    @EnvironmentObject var store: HomeStore

    var body: some View {
        if let folder = store.folder(withID: folderID) {
            content(folder: folder)
        } else {
            Color.clear.onAppear { store.collapseFolder() }
        }
    }

    @ViewBuilder
    private func content(folder: FolderEntry) -> some View {
        ZStack {
            // 背景：点击收起
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { store.collapseFolder() }

            VStack(spacing: 0) {
                titleRow(folder: folder)
                itemArea(folder: folder)
            }
            .frame(width: 374)
            .liquidGlass(cornerRadius: Theme.cardRadius)
            .offset(y: -12)
        }
    }

    // MARK: - 标题（点击重命名）

    @ViewBuilder
    private func titleRow(folder: FolderEntry) -> some View {
        Group {
            if store.renamingFolderID == folder.id {
                RenameField(folderID: folder.id, initial: folder.name)
            } else {
                Button {
                    withAnimation { store.renamingFolderID = folder.id }
                } label: {
                    HStack(spacing: 4) {
                        Text(folder.name)
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 44)
    }

    // MARK: - 内容网格（iPhone 式：固定 3×3 一页，图标从左上角排起，>9 个翻页）

    @ViewBuilder
    private func itemArea(folder: FolderEntry) -> some View {
        if folder.items.isEmpty {
            VStack(spacing: 10) {
                Text("把 App 拖进来，或点击添加")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Button("＋ 添加 App") {
                    store.addTarget = .folder(folder.id)
                }
                .glassButton()
            }
            .padding(.vertical, 28)
            .padding(.bottom, 10)
        } else {
            FolderPagedGrid(items: folder.items, folderID: folder.id)
        }
    }
}

// MARK: - 文件夹卡片分页网格

/// iPhone 同款：卡片固定 3 列 × 3 行，App 从左上角排起；
/// 超过 9 个分页（横滑或点页点），卡片高度恒定、内容永远完整显示
private struct FolderPagedGrid: View {
    let items: [HomeItem]
    let folderID: UUID
    @EnvironmentObject var store: HomeStore

    private let cols = 3
    private let rowsPerPage = 3
    private let cellH: CGFloat = 80
    private let cardInnerWidth: CGFloat = 374 - 28   // 卡片左右各 14pt 内边距

    private var perPage: Int { cols * rowsPerPage }
    private var pageCount: Int { max(1, (items.count + perPage - 1) / perPage) }
    private var page: Int { min(max(store.folderPage, 0), pageCount - 1) }
    private var pageHeight: CGFloat {
        CGFloat(rowsPerPage) * cellH + CGFloat(rowsPerPage - 1) * 10
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                HStack(spacing: 0) {
                    ForEach(0..<pageCount, id: \.self) { p in
                        pageGrid(p)
                            .frame(width: cardInnerWidth, height: pageHeight, alignment: .top)
                    }
                }
                .offset(x: -CGFloat(page) * cardInnerWidth)
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: page)
                .contentShape(Rectangle())
                .gesture(swipeGesture)
            }
            .frame(width: cardInnerWidth, height: pageHeight, alignment: .top)
            .clipped()

            if pageCount > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<pageCount, id: \.self) { i in
                        Circle()
                            .fill(i == page ? Color.primary.opacity(0.55) : Color.primary.opacity(0.18))
                            .frame(width: 6, height: 6)
                            .contentShape(Circle())
                            .onTapGesture { withAnimation { store.folderPage = i } }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    /// 一页：3×3 固定尺寸格子，从左上角排起，最后一页留白
    private func pageGrid(_ p: Int) -> some View {
        let slice = Array(items.dropFirst(p * perPage).prefix(perPage))
        let cellW = (cardInnerWidth - 20) / 3
        return LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(cellW), spacing: 10), count: cols),
            spacing: 10
        ) {
            ForEach(slice) { item in
                FolderItemCell(item: item, folderID: folderID, iconSize: 52)
            }
        }
        .frame(width: cardInnerWidth, height: pageHeight, alignment: .topLeading)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 25)
            .onEnded { v in
                if v.translation.width < -30, page < pageCount - 1 {
                    withAnimation { store.folderPage = page + 1 }
                } else if v.translation.width > 30, page > 0 {
                    withAnimation { store.folderPage = page - 1 }
                }
            }
    }
}

// MARK: - 行内重命名输入框

private struct RenameField: View {
    let folderID: UUID
    let initial: String
    @EnvironmentObject var store: HomeStore
    // 手工脱糖的 @State（本机 CLT 缺宏插件）
    private var _text: State<String> = State(initialValue: "")
    private var text: String {
        get { _text.wrappedValue }
        nonmutating set { _text.wrappedValue = newValue }
    }
    @FocusState private var focused: Bool

    var body: some View {
        TextField("文件夹名称", text: _text.projectedValue)
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .semibold))
            .multilineTextAlignment(.center)
            .focused($focused)
            .onSubmit { commit() }
            .onChange(of: focused) { value in
                if value == false { commit() }
            }
            .onAppear {
                text = initial
                focused = true
            }
    }

    private func commit() {
        guard store.renamingFolderID != nil else { return }
        store.renameFolder(folderID, to: text)
        store.renamingFolderID = nil
    }
}

// MARK: - 文件夹内的 App 格子

private struct FolderItemCell: View {
    let item: HomeItem
    let folderID: UUID
    var iconSize: CGFloat = 48
    @EnvironmentObject var store: HomeStore
    private var _hovering: State<Bool> = State(initialValue: false)
    private var hovering: Bool {
        get { _hovering.wrappedValue }
        nonmutating set { _hovering.wrappedValue = newValue }
    }

    var body: some View {
        Group {
            if let entry = item.appEntry {
                appCell(entry)
            } else {
                Text(item.displayName).font(.system(size: 11))
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func appCell(_ entry: AppEntry) -> some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topLeading) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: entry.path))
                    .resizable()
                    .frame(width: iconSize, height: iconSize)

                if store.editMode {
                    Button {
                        store.removeFromFolder(itemID: item.id, folderID: folderID)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary, Color(nsColor: .controlBackgroundColor))
                    }
                    .buttonStyle(.plain)
                    .offset(x: -6, y: -6)
                    .help("移出文件夹")
                }
            }
            Text(entry.name)
                .font(.system(size: 11))
                .lineLimit(1)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(hovering ? 0.06 : 0)))
        .scaleEffect(hovering && !store.editMode ? 1.04 : 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            guard !store.editMode else { return }
            store.launch(entry)
        }
        .contextMenu {
            Button("打开") { store.launch(entry) }
            Button("移出文件夹") {
                store.removeFromFolder(itemID: item.id, folderID: folderID)
            }
        }
    }
}
