import Foundation
import CoreGraphics

// MARK: - 条目模型

/// 桌面上的一个 App 快捷方式（以 bundle identifier 为主键）
struct AppEntry: Codable, Hashable, Identifiable {
    var bundleID: String
    var name: String
    var path: String

    var id: String { bundleID }
}

/// 文件夹（v1 不支持嵌套，items 里只能是 .app）
struct FolderEntry: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var items: [HomeItem]

    init(id: UUID = UUID(), name: String, items: [HomeItem] = []) {
        self.id = id
        self.name = name
        self.items = items
    }
}

/// 桌面格子：App 或文件夹
enum HomeItem: Codable, Hashable, Identifiable {
    case app(AppEntry)
    case folder(FolderEntry)

    var id: String {
        switch self {
        case .app(let a): return "app:" + a.bundleID
        case .folder(let f): return "folder:" + f.id.uuidString
        }
    }

    var displayName: String {
        switch self {
        case .app(let a): return a.name
        case .folder(let f): return f.name
        }
    }

    var appEntry: AppEntry? {
        if case .app(let a) = self { return a }
        return nil
    }
}

// MARK: - 设置

enum IconSize: String, Codable, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: return "小"
        case .medium: return "中"
        case .large: return "大"
        }
    }

    var iconPt: CGFloat {
        switch self {
        case .small: return 40
        case .medium: return 48
        case .large: return 56
        }
    }
}

/// Carbon 全局热键描述（修饰键用 Carbon 掩码）
enum CarbonMods {
    static let cmd = 1 << 8
    static let shift = 1 << 10
    static let option = 1 << 11
    static let control = 1 << 12
}

struct HotKeySpec: Codable, Equatable {
    var keyCode: Int
    var modifiers: Int
    var keyChar: String

    /// 默认 ⌥⌘H
    static let `default` = HotKeySpec(
        keyCode: 0x04, // kVK_ANSI_H
        modifiers: CarbonMods.option | CarbonMods.cmd,
        keyChar: "H"
    )

    var displayString: String {
        var out = ""
        if modifiers & CarbonMods.control != 0 { out += "⌃" }
        if modifiers & CarbonMods.option != 0 { out += "⌥" }
        if modifiers & CarbonMods.shift != 0 { out += "⇧" }
        if modifiers & CarbonMods.cmd != 0 { out += "⌘" }
        out += keyChar
        return out
    }
}

struct AppSettings: Codable, Equatable {
    var columns: Int = 5
    var rows: Int = 5
    var iconSize: IconSize = .medium
    var launchClosesPanel: Bool = true
    var showRunningDot: Bool = true
    var launchAtLogin: Bool = false
    var hotkey: HotKeySpec = .default

    init(columns: Int = 5, rows: Int = 5, iconSize: IconSize = .medium,
         launchClosesPanel: Bool = true, showRunningDot: Bool = true,
         launchAtLogin: Bool = false, hotkey: HotKeySpec = .default) {
        self.columns = columns
        self.rows = rows
        self.iconSize = iconSize
        self.launchClosesPanel = launchClosesPanel
        self.showRunningDot = showRunningDot
        self.launchAtLogin = launchAtLogin
        self.hotkey = hotkey
    }

    // 兼容旧 layout.json：缺新字段（如 rows）取默认值，避免整份解码失败
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        columns = try c.decodeIfPresent(Int.self, forKey: .columns) ?? 5
        rows = try c.decodeIfPresent(Int.self, forKey: .rows) ?? 5
        iconSize = try c.decodeIfPresent(IconSize.self, forKey: .iconSize) ?? .medium
        launchClosesPanel = try c.decodeIfPresent(Bool.self, forKey: .launchClosesPanel) ?? true
        showRunningDot = try c.decodeIfPresent(Bool.self, forKey: .showRunningDot) ?? true
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        hotkey = try c.decodeIfPresent(HotKeySpec.self, forKey: .hotkey) ?? .default
    }
}

/// 持久化文件根结构（~/Library/Application Support/MenuHome/layout.json）
struct LayoutFile: Codable {
    var version: Int = 1
    var pages: [[HomeItem]] = []
    var settings: AppSettings = AppSettings()
}

// MARK: - 栅格几何

/// 主网格与文件夹卡片共用的栅格计算
struct GridMetrics: Equatable {
    var columns: Int
    var rows: Int
    var cellW: CGFloat
    var cellH: CGFloat
    var hGap: CGFloat = 12
    var vGap: CGFloat = 14
    var hPad: CGFloat = 20
    var topPad: CGFloat = 16
    var dotsHeight: CGFloat = 0

    /// 常驻搜索栏顶部区（含上边距）：10 + 栏高 30 + 呼吸 2
    var searchBarArea: CGFloat = 42

    /// 单页（整面板）宽度
    var pageW: CGFloat { hPad * 2 + CGFloat(columns) * cellW + CGFloat(columns - 1) * hGap }
    var gridH: CGFloat { CGFloat(rows) * (cellH + vGap) - vGap }
    var panelH: CGFloat { searchBarArea + topPad + gridH + 12 }
    var capacity: Int { columns * rows }

    /// 主网格：列数/行数 4/5/6，格子宽 = 图标 + 30，高 = 图标 + 32
    static func make(columns: Int, rows: Int, iconSize: IconSize) -> GridMetrics {
        let icon = iconSize.iconPt
        return GridMetrics(
            columns: max(4, min(6, columns)),
            rows: max(4, min(6, rows)),
            cellW: icon + 30,
            cellH: icon + 32
        )
    }

    /// 格子左上角（面板坐标系）
    func cellOrigin(row: Int, col: Int) -> CGPoint {
        CGPoint(x: hPad + CGFloat(col) * (cellW + hGap),
                y: topPad + CGFloat(row) * (cellH + vGap))
    }

    /// 点所在的格子（面板坐标系）；间隙计入所属格子
    func slot(at point: CGPoint) -> (row: Int, col: Int)? {
        let x = point.x - hPad
        let y = point.y - topPad
        guard x >= 0, y >= 0 else { return nil }
        let col = Int(x / (cellW + hGap))
        let row = Int(y / (cellH + vGap))
        // 只钳列数：单页滚动后内容行数随条目增长（可超出设置的可见行数），
        // 行越界交给调用方处理（落点在网格下方空白 = 追加到末尾）
        guard col < columns else { return nil }
        return (row, col)
    }

    /// 点对应的条目索引（滚动内容坐标系）；间隙计入所属格子
    func index(at point: CGPoint) -> Int? {
        guard let s = slot(at: point) else { return nil }
        return s.row * columns + s.col
    }

    /// 半格判定：点在格子中心竖线的哪一侧（true = 右半 → 插到该格占用者之后）。
    /// iOS 式插入：两半格分别对应「插到图标前 / 图标后」，实现真正的图标间落位
    func isAfterHalf(point: CGPoint, row: Int, col: Int) -> Bool {
        let o = cellOrigin(row: row, col: col)
        return point.x > o.x + cellW / 2
    }

    /// 点是否落在格子中心合并区（iOS 式：中心 = 合并候选悬停区，边缘 = 插入让位区）
    func isInMergeZone(point: CGPoint, row: Int, col: Int) -> Bool {
        let o = cellOrigin(row: row, col: col)
        let dx = abs(point.x - (o.x + cellW / 2))
        let dy = abs(point.y - (o.y + cellH / 2))
        return dx < cellW * 0.28 && dy < cellH * 0.3
    }
}

// MARK: - 面板内交互状态

/// 「添加 App」的目标位置
enum AddTarget: Equatable {
    case desktop
    case folder(UUID)
}

/// 桌面网格的拖拽会话（编辑模式；文件夹卡片内的拖拽由 FolderOverlay 本地管理）
struct DragSession: Equatable {
    var item: HomeItem
    /// 拖起时的扁平索引（取消拖拽时回原位）
    var originIndex: Int
    /// 当前所在的扁平索引（live reorder 实时更新）
    var currentIndex: Int
    /// 拖拽点（homePanel 坐标系）
    var point: CGPoint = .zero
    /// 悬停合并候选（悬停同一目标 0.4s 后设置）
    var mergeCandidateID: String?
    /// iOS 式插入空位：提起后的扁平索引，该格撑开留白、其后条目让位一格
    /// （nil = 不撑开 —— 合并悬停中 / 落点在网格下方追加区，无可见空位）
    var gapIndex: Int?

    var itemID: String { item.id }
}
