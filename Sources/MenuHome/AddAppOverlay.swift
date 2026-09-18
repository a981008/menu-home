import AppKit
import SwiftUI

/// 「添加 App」覆盖层：列出本机 App，单击即加入桌面/文件夹
struct AddAppOverlay: View {
    let target: AddTarget
    @EnvironmentObject var store: HomeStore

    // 注：本机 CLT 缺 SwiftUIMacros 插件，@State 宏无法展开 —— 这里手工脱糖（等价于 @State）
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

    private var filtered: [AppEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let list = q.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(q) }
        return list
    }

    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Divider()
                if case .folder(let fid) = target, let folder = store.folder(withID: fid) {
                    Text("添加到「\(folder.name)」")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                }
                list
            }
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.thickMaterial)
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            )
            .padding(1)
        }
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle")
                .foregroundStyle(.secondary)
            Text(headerTitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            TextField("搜索要添加的 App…", text: _query.projectedValue)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .frame(maxWidth: 200)
            Button("取消") {
                store.addTarget = nil
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
    }

    private var headerTitle: String {
        if case .folder(let fid) = target, let folder = store.folder(withID: fid) {
            return "添加到「\(folder.name)」"
        }
        return "添加 App 到桌面"
    }

    // MARK: - 列表

    private var list: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(filtered) { entry in
                    AddAppRow(entry: entry, target: target)
                }
            }
        }
    }
}

// MARK: - 单行

private struct AddAppRow: View {
    let entry: AppEntry
    let target: AddTarget
    @EnvironmentObject var store: HomeStore
    private var _hovering: State<Bool> = State(initialValue: false)
    private var hovering: Bool {
        get { _hovering.wrappedValue }
        nonmutating set { _hovering.wrappedValue = newValue }
    }

    private var already: Bool {
        store.allBundleIDs.contains(entry.bundleID)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: entry.path))
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.system(size: 13))
                Text((entry.path as NSString).deletingLastPathComponent)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if already {
                Image(systemName: "checkmark")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("已在桌面")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(hovering ? 0.06 : 0))
        .opacity(already ? 0.55 : 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            guard !already else { return }
            store.addApp(entry, to: target)
        }
    }
}
