# AGENTS.md

> 给在本仓库工作的 **coding agent** 的必读指南。
> 改任何代码之前先读完这一页 —— 特别是第 2 节「硬性环境约束」，违反 = 构建必失败。

## 1. 项目速览

**MenuHome**：常驻 macOS 状态栏的「个人桌面」启动器 —— 像 iPhone 桌面一样收纳常用 App，支持文件夹分类、随时拖拽、3×3 分页文件夹、搜索、Finder 拖入。桌面为**单页滚动网格**（列数/行数 4/5/6 可设，超出可视区滚动，不分页）。

- 技术：SwiftUI + AppKit（NSStatusItem + NSPanel），**零第三方依赖**
- 部署目标：**macOS 26+**（`glassEffect` 等液态玻璃 API 直接可用）；开发机 macOS 27 + CLT 6.4（Apple Swift 6.4，**无完整 Xcode**）
- 语言模式：Swift 5（`Package.swift` 里 `.swiftLanguageMode(.v5)`，供 Xcode 用户参考）
- UI 设计文档：`docs/ui-design.md`（v1.0，与实现对齐）

## 2. 硬性环境约束（违反 = 构建必失败）

### 2.1 禁用 SwiftPM

本机 CLT 的 SwiftPM 清单链接损坏：**任何 Package.swift 都无法链接**（缺 `Package.__allocating_init` 符号，最小复现包也复现；tools 5.9–6.2 各种写法全挂）。

- ❌ 永远不要运行 `swift build` / `swift test` / `swift package *`
- ✅ 一律走 `./scripts/build_app.sh`（内部 `xcrun swiftc` 直编，支持 debug/release，组装 `build/MenuHome.app` + ad-hoc 签名）

### 2.2 禁用带宏的 property wrapper

27 SDK 把 `@State` 等宏化，但本机缺 **SwiftUIMacros 插件** → 报 `plugin for module 'SwiftUIMacros' not found`。

视图里写本地状态**必须手工脱糖**：

```swift
// ❌ 禁止
@State private var hovering = false

// ✅ 手工脱糖（nonmutating set）
private var _hovering: State<Bool> = State(initialValue: false)
private var hovering: Bool {
    get { _hovering.wrappedValue }
    nonmutating set { _hovering.wrappedValue = newValue }
}
```

范本：`CellView._hovering`、`FolderPagedGrid._dragItem/_dragPoint`、`AddAppOverlay`。
**不需要**脱糖：`@EnvironmentObject`、`@Published`、`@FocusState`、普通存储属性。

### 2.3 其他

- 部署目标 26：不要写 `#available` 回退分支
- 仅允许的编译警告：`NSEvent` Sendable（PanelController / SettingsView，Swift 5 模式残留）；出现任何 **error** 必须修完才算完成
- 编辑文件前先 read；edit 报 "file changed since read" 就重读再试

## 3. 常用命令

```bash
./scripts/build_app.sh                        # 编译 + 组装 build/MenuHome.app（约 1–2 分钟）
pkill -x MenuHome; sleep 1; open build/MenuHome.app   # 重启到新版
pgrep -x MenuHome                             # 确认在跑
```

标准流程：**build（0 error）→ 重启 → 手测 → 提交 → push**。

提交与推送（环境缺 `GIT_AUTHOR_*` 时）：

```bash
git -c user.name="${GIT_AUTHOR_NAME:-wang}" -c user.email="${GIT_AUTHOR_EMAIL:-wang@local}" commit -m "…"
GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new" git push
```

- 提交信息用**简体中文**
- 远程 `origin = git@github.com:a981008/menu-home.git`（main，SSH BatchMode 可用）
- ⚠️ 别把编译失败/未验证的改动 commit 上去（先 build 确认再提交）

## 4. 架构地图

```
Sources/MenuHome/
├── main.swift / AppDelegate          入口；LSUIElement 无 Dock 图标
├── StatusIcon / HotKeyCenter         菜单栏图标（左键 toggle/右键菜单）；Carbon 全局热键 ⌥⌘H
├── PanelController                   NSPanel（borderless + nonactivating + canBecomeKey）：
│                                     开合动画时序、位置钳制、键盘监听、失焦关闭
├── HomeStore ★                       唯一状态源（@MainActor ObservableObject）：
│                                     pages/settings/拖拽会话/覆盖层状态/持久化
├── Models                            HomeItem / AppEntry / FolderEntry / GridMetrics / IconSize / AppSettings
├── HomeView                          面板根：玻璃面板 + ZStack 覆盖层 + .onDrop(Finder 拖入)
├── GridCarousel / PageGrid           滚动容器（单页、注册 "homePanel" 内容坐标系）/ 单页栅格（.position 按 cellOrigin 摆放）
├── CellView / AppCellView / FolderCellView   格子（拖拽手势在 CellView）；App 格；文件夹格
├── FolderOverlay                     文件夹卡片：3×3 分页网格 + 卡片内拖拽 + 行内重命名
├── SearchOverlay / AddAppOverlay     搜索 / 添加 App 覆盖层
├── EditBar / EmptyStateView / DragGhostView / JiggleModifier
├── AppScanner                        递归扫 4 目录（两层）+ 系统 App 本地化名（loctable/strings）
├── RunningMonitor                    NSWorkspace 运行中监听（圆点）
├── SettingsView / SettingsWindowController
└── Theme                             圆角体系 + liquidGlass 修饰符（唯一玻璃入口）
scripts/build_app.sh                  唯一构建入口
docs/ui-design.md                     UI 设计文档（v1.0）
```

## 5. 不变量与设计约定（改代码别破坏）

1. **HomeStore 是唯一状态源**：跨视图状态一律 `@EnvironmentObject var store`；不要自建单例。
2. **布局一律 metrics 驱动，禁止硬编码尺寸**：`GridMetrics`（cellW = 图标+30，cellH = 图标+32，hGap 12，vGap 14，hPad 20，topPad 16；图标 40/48/56 跟随 `IconSize` 设置；列数/行数 4/5/6 跟随 `settings.columns/rows`）。桌面是**单列表**（`store.pages == [items]`），超出可视行数由 GridCarousel 的 ScrollView 滚动 —— 别再引入分页。文件夹卡片、图标缩略图、拖影都已与主网格等比例 —— 调整尺寸只改 `GridMetrics.make` / `IconSize.iconPt`，别在视图里写死数字。
3. **玻璃统一走 `Theme.liquidGlass`**：内部为 `glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius:, style: .continuous))`。圆角常量集中在 `Theme`（面板 28 / 卡片 26 / 浮层 24 / 搜索 22 / 胶囊 21 / 拖影 16）。
4. **拖拽是「提起」模型**（消除「图标来回移动」的关键，别改回 live-move）：
   - `beginDrag` 把图标从网格移出（其余立即补位）→ 只有拖影跟随光标
   - `dragMoved` 只更新 currentIndex + 合并候选（占用者稳定不动）
   - `endDrag` 插入光标格或合并；`cancelDrag` 回原位；合并 = 悬停占用者 400ms（`holdWork` 计时）
   - 合并时拖拽项**不在** items 里 → `performMerge(dragged:target:)` 直接在目标位置生成
   - **性能红线**：光标高频移动只写 `store.ghost`（独立 GhostTracker，只重渲染拖影）与非发布态 `liveIndex`；`@Published` 仅在跨格/合并态等结构变化时更新。鼠标移动事件可达数百 Hz，逐事件发布会让整棵视图树重渲染（卡顿根因）。图标读取一律用 `AppScanner.cachedIcon(forPath:)`（NSCache），别直接调 `NSWorkspace.icon(forFile:)`
5. **拖拽坐标系**：桌面拖拽的 `"homePanel"` 由 **GridCarousel 的滚动内容**注册 —— 手势坐标随滚动一致；文件夹卡片内拖拽用 `.named("folderCard")`。
6. **面板开合动画**：`store.panelVisible` + `store.panelAnchor`（状态栏图标在面板上的相对锚点）驱动 scale/opacity；窗口先出现、下一帧置 visible。收起 = 先收缩、0.3s 后 `orderOut` + `resetTransientState()`（`closeWork` 延迟任务；收起途中再点图标会反向弹回）。
7. **文件夹开合**：`folderSourceRect`（点击时记录的图标矩形）作为动画锚点，卡片 transition 以它缩放展开/缩回；卡片分页用 `store.folderPage`（展开时归零）。
8. **持久化**：`~/Library/Application Support/MenuHome/layout.json`（pages + settings，文件夹有稳定 UUID）。**pages 现在恒为单元素数组**（旧多页文件在 load 时扁平迁移）；`AppSettings.init(from:)` 用 decodeIfPresent 兼容旧文件缺字段。拖拽期间落盘会被推迟（`persistPending`），拖拽结束统一补写；写盘在后台队列执行（`persistNow`），别把文件 I/O 挪回主线程。**做会改动布局的自动化测试前先备份该文件，测完还原**。
9. **UI 文案全部简体中文**，代码注释也用中文。
10. 新增 `@Published` 瞬态时，确认是否要在 `resetTransientState()` 里复位（面板收起后不留脏状态）。

## 6. 已知坑

- `NSDictionary` 遍历 key 是 Any：用 `for case let (key as String, sub as [String: Any]) in table`
- 系统 App 本地化名：先按候选语言读 `InfoPlist.loctable`/`.strings`；`Bundle.localizedInfoDictionary` 只作兜底（它对无中文 strings 的系统 App 会回退英文）；loctable 查路径**不能**带 `forLocalization:`
- 文件夹卡片横滑翻页 vs 图标拖拽：swipe 的 `onEnded` 里 `guard dragItem == nil`
- `glassEffect` 形状必须用显式 `RoundedRectangle(cornerRadius:style: .continuous)`（`.rect(cornerRadius:)` 在玻璃合成下圆角可能不完整）
- `NSEvent.momentumPhase` 是 OptionSet：判空用 `!event.momentumPhase.isEmpty`（没有 `.zero`）
- 终端无屏幕录制权限（TCC），`screencapture` 截不了屏 —— 验证视觉改动靠构建 + 用户确认

## 7. 验证清单（每次 UI 改动后）

- [ ] `./scripts/build_app.sh` 0 error（Sendable 警告可忽略）
- [ ] 重启后：左键点图标 → 面板从图标位置弹出；点 App 启动；Esc / 点外部收起
- [ ] 拖动图标排序；拖到另一图标悬停建文件夹；App 多于可视行数时可滚动查看
- [ ] 文件夹：点开（从图标缩放展开）、卡片内拖动排序、拖出卡片移出、>9 个分页
- [ ] Finder 拖 .app 入面板；⌥⌘H 全局热键
- [ ] 设置改列数/行数/图标大小 → 面板尺寸与桌面 / 文件夹卡片 / 缩略图同步变化
