# MenuHome

常驻 macOS 状态栏的「个人桌面」：像 iPhone 桌面一样收纳常用 App，支持文件夹分类，一键直达。

> 设计文档：[docs/ui-design.md](docs/ui-design.md)

## 技术栈

- SwiftUI + AppKit（NSStatusItem / NSPanel / 系统液态玻璃 glassEffect / Carbon 热键）
- 零第三方依赖；Swift 5 语言模式，部署目标 **macOS 26+**（美术：macOS 27 Tahoe 液态玻璃 + 大圆角）
- 构建：`swiftc` 直接编译（`Package.swift` 保留供 Xcode/SwiftPM 使用）

## 构建与运行

```bash
# 打包成 .app（release 构建 + ad-hoc 签名）并运行
bash scripts/build_app.sh && open build/MenuHome.app

# debug 构建（不做签名打包）
bash scripts/build_app.sh debug
```

脚本用 `swiftc` 把 `Sources/MenuHome/*.swift` 直接编译为通用可执行文件再组装 .app，不经过 SwiftPM。

> 环境备注：在只装 Command Line Tools 的机器上（如开发本机，CLT 6.4 / macOS 27 SDK），SwiftPM 存在两个工具链缺陷——任意 `Package.swift` 清单都无法链接（libPackageDescription 缺旧签名符号），且新 SDK 把 `@State` 宏化而 CLT 未随附 SwiftUIMacros 插件。因此脚本绕开 SwiftPM，源码中的 `@State` 均已手工脱糖为显式 `State<T>` 存储属性（与宏展开结果等价），在 CLT 与完整 Xcode 下均可编译。

> 首次运行 ad-hoc 签名的 app 可能被 Gatekeeper 拦截：到 系统设置 → 隐私与安全性 点「仍要打开」放行即可。

## 功能清单

- 状态栏图标与面板：点击开/关面板，点击面板外自动收起（non-activating，不打断当前 App）
- 滚动桌面网格：4 / 5 / 6 列、4 / 5 / 6 行可选，图标小 / 中 / 大三档，更改列数/行数会同时调整面板尺寸；内容超出可视区直接滚动（不分页）
- 文件夹：拖拽合并创建（或右键 App「移入新文件夹」/ 空白处「新建文件夹」），展开、重命名、移除（内容自动退回桌面）
- 拖拽：**随时**拖动图标排序（不必先进编辑模式），拖到图标上悬停片刻合并建文件夹；从 Finder 拖入 .app 即添加到桌面末尾
- 编辑模式（抖动）：长按图标或右键「整理桌面…」进入，纯视觉提示
- 键盘直入搜索覆盖层：顶部常驻搜索栏（居中）点击进入，或面板打开时按任意字符直接搜索；输入框与「添加 App」搜索框同款样式
- 添加 App：扫描本机应用列表加入桌面，可加入文件夹
- 运行中 App 圆点指示（可在设置中关闭）
- 全局热键 ⌥⌘H 随时呼出（可在设置中录制）
- JSON 持久化：`~/Library/Application Support/MenuHome/layout.json`
- 导入 / 导出布局 JSON，可手工备份迁移；「重置全部」恢复初始状态

## 快捷键

| 按键 | 作用 |
|------|------|
| ⌥⌘H | 呼出 / 收起面板（可在设置中录制） |
| 任意字符 / ⌘F | 打开搜索覆盖层 |
| Esc | 逐级回退：搜索 → 文件夹 → 编辑模式 → 关面板 |
| ⌘, | 打开设置 |

## 开发结构

`Sources/MenuHome/` 下的文件：

| 文件 | 说明 |
|------|------|
| Models.swift | 数据模型：AppEntry / FolderEntry / HomeItem / IconSize / HotKeySpec / AppSettings / LayoutFile / GridMetrics / DragSession |
| HomeStore.swift | 全局状态中枢：桌面布局（单列表）、设置、拖拽会话、JSON 持久化 |
| main.swift | 程序入口 |
| AppDelegate.swift | NSApplication 生命周期与各组件接线 |
| PanelController.swift | NSPanel 面板控制（non-activating、外部点击收起、随设置 resize） |
| StatusIcon.swift | 状态栏图标 NSStatusItem 与菜单 |
| HotKeyCenter.swift | Carbon RegisterEventHotKey 全局热键注册 |
| RunningMonitor.swift | 监听 NSWorkspace 正在运行的 App（运行中圆点） |
| AppScanner.swift | 扫描本机应用目录生成 App 列表（添加 App 用） |
| SettingsWindowController.swift | 设置窗口控制器（400pt 宽普通 NSWindow） |
| SettingsView.swift | 设置窗口 SwiftUI 视图（通用 / 外观 / 数据 / 关于） |
| 其他视图文件 | 桌面网格、文件夹展开覆盖层、搜索覆盖层、添加 App 覆盖层等 SwiftUI 视图 |

## 已知限制

- 启动目标 App 时面板总会因失焦而收起，即使关闭「启动 App 后自动收起面板」也是如此（激活目标 App 必然让面板失去焦点）
- 文件夹卡片内容多于 9 个时在卡片内 3×3 分页（iPhone 同款）
- 拖拽过程中桌面不会自动滚动，超出可视区域的格子需先滚动到位再拖放
- 「登录时启动」依赖 SMAppService，需要 MenuHome.app 位于磁盘固定路径；移动位置后需重新开关一次该开关
