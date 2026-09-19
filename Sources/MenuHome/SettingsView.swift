import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

// MARK: - 设置窗口内容

/// 设置窗口内容视图。运行在普通 NSWindow 中（400pt 宽窗口由外部 SettingsWindowController 提供，
/// 本视图不创建窗口）。所有设置项即时生效：写入统一走 store.settings 的 Binding，
/// settings 的 didSet 会自动持久化并触发面板 resize 回调。
struct SettingsView: View {
    @EnvironmentObject var store: HomeStore

    // 登录启动：经 SMAppService 注册/注销，不直接用 settings.launchAtLogin 存取
    // （以下 6 个均为手工脱糖的 @State —— 本机 CLT 缺 SwiftUIMacros 插件）
    private var _loginEnabled: State<Bool> = State(initialValue: false)
    private var loginEnabled: Bool {
        get { _loginEnabled.wrappedValue }
        nonmutating set { _loginEnabled.wrappedValue = newValue }
    }
    private var _loginError: State<String?> = State(initialValue: nil)
    private var loginError: String? {
        get { _loginError.wrappedValue }
        nonmutating set { _loginError.wrappedValue = newValue }
    }

    // 全局快捷键录制
    private var _recording: State<Bool> = State(initialValue: false)
    private var recording: Bool {
        get { _recording.wrappedValue }
        nonmutating set { _recording.wrappedValue = newValue }
    }
    private var _monitor: State<Any?> = State(initialValue: nil)
    private var monitor: Any? {
        get { _monitor.wrappedValue }
        nonmutating set { _monitor.wrappedValue = newValue }
    }

    // 导入布局的结果提示
    private var _importMessage: State<String?> = State(initialValue: nil)
    private var importMessage: String? {
        get { _importMessage.wrappedValue }
        nonmutating set { _importMessage.wrappedValue = newValue }
    }

    // 重置确认弹窗
    private var _showResetConfirm: State<Bool> = State(initialValue: false)
    private var showResetConfirm: Bool {
        get { _showResetConfirm.wrappedValue }
        nonmutating set { _showResetConfirm.wrappedValue = newValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            generalGroup
            appearanceGroup
            dataGroup
            aboutGroup
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            loginEnabled = (SMAppService.mainApp.status == .enabled)
        }
        .onDisappear {
            stopHotkeyRecording()
        }
        .confirmationDialog(
            "确定重置全部布局与设置？此操作不可撤销。",
            isPresented: _showResetConfirm.projectedValue,
            titleVisibility: .visible
        ) {
            Button("重置", role: .destructive) {
                withAnimation {
                    store.pages = [[]]
                    store.settings = AppSettings()
                }
            }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: 通用

    private var generalGroup: some View {
        GroupBox(label: Text("通用")) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("登录时启动 MenuHome", isOn: loginBinding)
                    .toggleStyle(.switch)
                hotkeyRow
                Toggle("启动 App 后自动收起面板", isOn: launchClosesPanelBinding)
                    .toggleStyle(.switch)
                Toggle("显示「正在运行」圆点", isOn: showRunningDotBinding)
                    .toggleStyle(.switch)
                if let err = loginError {
                    Text(err)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var hotkeyRow: some View {
        HStack(spacing: 6) {
            Text("全局快捷键")
            Spacer()
            Button {
                toggleHotkeyRecording()
            } label: {
                Text(recording ? "请按下组合键… (Esc 取消)" : store.settings.hotkey.displayString)
                    .monospaced()
                    .frame(minWidth: 120)
            }
            .buttonStyle(.bordered)
            Button {
                stopHotkeyRecording()
                store.settings.hotkey = .default
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            .help("恢复默认快捷键 ⌥⌘H")
        }
    }

    // MARK: 外观

    private var appearanceGroup: some View {
        GroupBox(label: Text("外观")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("列数")
                    Spacer()
                    Picker("", selection: columnsBinding) {
                        Text("4").tag(4)
                        Text("5").tag(5)
                        Text("6").tag(6)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
                HStack {
                    Text("行数")
                    Spacer()
                    Picker("", selection: rowsBinding) {
                        Text("4").tag(4)
                        Text("5").tag(5)
                        Text("6").tag(6)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
                HStack {
                    Text("图标大小")
                    Spacer()
                    Picker("", selection: iconSizeBinding) {
                        ForEach(IconSize.allCases) { size in
                            Text(size.label).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
                Text("更改列数/行数会同时调整面板尺寸；超出可视区域的 App 可滚动查看。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: 数据

    private var dataGroup: some View {
        GroupBox(label: Text("数据")) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Button("导出布局…") { exportLayout() }
                    Button("导入布局…") { importLayout() }
                    Spacer()
                    Button("重置全部…", role: .destructive) { showResetConfirm = true }
                }
                if let msg = importMessage {
                    Text(msg)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: 关于

    private var aboutGroup: some View {
        GroupBox(label: Text("关于")) {
            VStack(alignment: .leading, spacing: 4) {
                // 版本号单一来源是仓库根的 VERSION 文件（build_app.sh 注入 Info.plist）；
                // 直跑裸二进制没有 Info.plist 时显示「开发版」
                Text("MenuHome \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "开发版")")
                    .font(.system(size: 12, weight: .medium))
                Text("状态栏上的个人桌面 · 布局保存在 ~/Library/Application Support/MenuHome/layout.json")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Bindings（写入统一走 store.settings，didSet 自动持久化）

    private var columnsBinding: Binding<Int> {
        Binding(get: { store.settings.columns }, set: { store.settings.columns = $0 })
    }

    private var rowsBinding: Binding<Int> {
        Binding(get: { store.settings.rows }, set: { store.settings.rows = $0 })
    }

    private var iconSizeBinding: Binding<IconSize> {
        Binding(get: { store.settings.iconSize }, set: { store.settings.iconSize = $0 })
    }

    private var launchClosesPanelBinding: Binding<Bool> {
        Binding(get: { store.settings.launchClosesPanel }, set: { store.settings.launchClosesPanel = $0 })
    }

    private var showRunningDotBinding: Binding<Bool> {
        Binding(get: { store.settings.showRunningDot }, set: { store.settings.showRunningDot = $0 })
    }

    /// 登录启动绑定：SMAppService 注册/注销成功后同步 settings.launchAtLogin 便于持久化展示；
    /// 失败（如 app 不在固定位置）时提示错误，并把开关回弹到真实状态。
    private var loginBinding: Binding<Bool> {
        Binding(
            get: { loginEnabled },
            set: { v in
                loginEnabled = v
                do {
                    if v {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    loginError = nil
                    store.settings.launchAtLogin = v
                } catch {
                    loginEnabled = !v
                    loginError = "需要把 MenuHome.app 放到固定位置后再试（\(error.localizedDescription)）"
                }
            }
        )
    }

    // MARK: - 快捷键录制

    private func toggleHotkeyRecording() {
        if recording {
            stopHotkeyRecording()
        } else {
            startHotkeyRecording()
        }
    }

    private func startHotkeyRecording() {
        guard monitor == nil else { return }
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                self.handleRecordedKey(event)
            }
        }
    }

    private func stopHotkeyRecording() {
        recording = false
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    /// 录制中的按键处理：返回 nil 表示拦截该按键，返回 event 表示放行。
    private func handleRecordedKey(_ event: NSEvent) -> NSEvent? {
        // Esc（keyCode 53）：结束录制，不写入
        if event.keyCode == 53 {
            stopHotkeyRecording()
            return nil
        }
        // 必须包含 ⌘/⌥/⌃ 之一，否则放行
        let flags = event.modifierFlags
        guard flags.contains(.command) || flags.contains(.option) || flags.contains(.control) else {
            return event
        }
        var mask = 0
        if flags.contains(.command) { mask |= CarbonMods.cmd }
        if flags.contains(.shift) { mask |= CarbonMods.shift }
        if flags.contains(.option) { mask |= CarbonMods.option }
        if flags.contains(.control) { mask |= CarbonMods.control }
        let raw = event.charactersIgnoringModifiers?.uppercased() ?? ""
        let keyChar = String(raw.prefix(1))
        store.settings.hotkey = HotKeySpec(keyCode: Int(event.keyCode), modifiers: mask, keyChar: keyChar)
        stopHotkeyRecording()
        return nil
    }

    // MARK: - 导入 / 导出

    private func exportLayout() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "menuhome-layout.json"
        panel.canCreateDirectories = true
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            let file = LayoutFile(version: 1, pages: store.pages, settings: store.settings)
            if let data = try? JSONEncoder().encode(file) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func importLayout() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(LayoutFile.self, from: data) else {
            importMessage = "导入失败：不是有效的 MenuHome 布局文件。"
            return
        }
        withAnimation {
            store.pages = file.pages.isEmpty ? [[]] : file.pages
            store.settings = file.settings
        }
        importMessage = "已导入 \(file.pages.count) 页布局。"
    }
}
