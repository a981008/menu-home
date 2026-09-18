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

    // MARK: - 内容网格

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
            ScrollView(.vertical) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                    spacing: 12
                ) {
                    ForEach(folder.items) { item in
                        FolderItemCell(item: item, folderID: folder.id)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
            .frame(maxHeight: folder.items.count > 12 ? 320 : .infinity)
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
                    .frame(width: 48, height: 48)

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
