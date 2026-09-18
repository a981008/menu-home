import Foundation
import AppKit

/// 扫描本机安装的 App
/// - 根目录：/Applications、~/Applications、/System/Applications、
///   /System/Volumes/Preboot/Cryptexes/App/System/Applications（新 macOS 上 Safari 等的实际位置）
/// - 递归两层子目录（覆盖 /System/Applications/Utilities、/Applications/Setapp/Apps 等）
/// - 不进入 .app 内部；按 bundle id 去重，先出现的根目录优先
/// - 显示名按用户语言偏好解析本地化（InfoPlist.strings / InfoPlist.loctable），
///   保证「终端」「活动监视器」这类系统 App 能用中文名搜到
enum AppScanner {

    private static let roots = [
        "/Applications",
        NSString(string: "~/Applications").expandingTildeInPath,
        "/System/Applications",
        "/System/Volumes/Preboot/Cryptexes/App/System/Applications",
    ]

    /// 最大递归层数：0 = 根目录本身，2 = 允许两层子目录
    private static let maxDepth = 2

    // MARK: - 图标缓存

    private static let iconCache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 400
        return c
    }()

    /// 带缓存的图标读取：拖拽/悬停等重渲染热路径不再反复走 NSWorkspace 查询
    static func cachedIcon(forPath path: String) -> NSImage {
        if let hit = iconCache.object(forKey: path as NSString) { return hit }
        let img = NSWorkspace.shared.icon(forFile: path)
        iconCache.setObject(img, forKey: path as NSString)
        return img
    }

    private static var appsCache: [AppEntry]?

    /// 全量 App 列表（带缓存）：搜索覆盖层每次打开都要用，首次扫描后复用，不再重复走盘
    static func cachedApps() -> [AppEntry] {
        if let appsCache { return appsCache }
        let list = scanApps()
        appsCache = list
        return list
    }

    /// 从路径构造 AppEntry（Finder 拖入 .app 用）；非 .app 或无 bundle id 返回 nil
    static func entry(atPath path: String) -> AppEntry? {
        guard path.hasSuffix(".app"),
              let bundle = Bundle(url: URL(fileURLWithPath: path)),
              let bundleID = bundle.bundleIdentifier else { return nil }
        let fallback =
            bundle.infoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle.infoDictionary?["CFBundleName"] as? String
            ?? ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        return AppEntry(bundleID: bundleID, name: displayName(for: bundle, fallback: fallback), path: path)
    }

    static func scanApps() -> [AppEntry] {
        let selfBundleID = Bundle.main.bundleIdentifier

        var byID: [String: AppEntry] = [:]
        var order: [String] = []

        func addApp(at path: String, name: String) {
            guard let bundle = Bundle(url: URL(fileURLWithPath: path)),
                  let bundleID = bundle.bundleIdentifier else { return }
            guard bundleID != selfBundleID, byID[bundleID] == nil else { return }

            let fallback =
                bundle.infoDictionary?["CFBundleDisplayName"] as? String
                ?? bundle.infoDictionary?["CFBundleName"] as? String
                ?? (name as NSString).deletingPathExtension

            byID[bundleID] = AppEntry(bundleID: bundleID, name: displayName(for: bundle, fallback: fallback), path: path)
            order.append(bundleID)
        }

        func enumerate(_ dir: String, depth: Int) {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
            for name in names where !name.hasPrefix(".") {
                let path = dir + "/" + name
                if name.hasSuffix(".app") {
                    addApp(at: path, name: name)
                } else if depth < maxDepth,
                          (try? FileManager.default.attributesOfItem(atPath: path)[.type]) as? FileAttributeType == .typeDirectory {
                    enumerate(path, depth: depth + 1)
                }
            }
        }

        for root in roots {
            enumerate(root, depth: 0)
        }

        return order.compactMap { byID[$0] }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - 本地化显示名

    /// 按用户语言偏好解析 App 的本地化显示名
    private static func displayName(for bundle: Bundle, fallback: String) -> String {
        // 1) 按用户语言偏好排序可用本地化，逐个尝试资源文件
        //    （注意：不能先信 localizedInfoDictionary —— 系统 App 无 zh 的 InfoPlist.strings 时
        //    它会回退到英文值，导致「终端」变成 "Terminal"）
        let candidates = preferredLocalizations(of: bundle.localizations)
        for loc in candidates {
            if let n = readName(inStrings: bundle, localization: loc) ?? readName(inLocTable: bundle, localization: loc) {
                return n
            }
        }

        // 2) 兜底：Bundle 已解析的 localizedInfoDictionary
        if let d = bundle.localizedInfoDictionary {
            if let n = d["CFBundleDisplayName"] as? String, !n.isEmpty { return n }
            if let n = d["CFBundleName"] as? String, !n.isEmpty { return n }
        }
        return fallback
    }

    /// 用户偏好的本地化列表（与 App 可用本地化求交，保持偏好顺序）
    private static func preferredLocalizations(of available: [String]) -> [String] {
        var wants: [String] = []
        for lang in Locale.preferredLanguages {
            wants.append(lang)
            let parts = lang.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
            if parts.count > 1 {
                wants.append(parts.prefix(2).joined(separator: "-"))
                wants.append(parts[0])
            }
        }
        var seen = Set<String>()
        var result: [String] = []
        for want in wants {
            for avail in available where avail != "Base" {
                let availBase = avail.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? avail
                if (avail == want || availBase == want) && !seen.contains(avail) {
                    seen.insert(avail)
                    result.append(avail)
                }
            }
        }
        // 末尾兜底英文
        for avail in available where avail.hasPrefix("en") {
            if !seen.contains(avail) { result.append(avail) }
        }
        return result
    }

    /// InfoPlist.strings（普通 / 二进制 plist 皆可由 NSDictionary 读）
    private static func readName(inStrings bundle: Bundle, localization: String) -> String? {
        guard let path = bundle.path(forResource: "InfoPlist", ofType: "strings", inDirectory: nil, forLocalization: localization),
              let d = NSDictionary(contentsOfFile: path) else { return nil }
        return name(from: d as! [String: Any])
    }

    /// InfoPlist.loctable（Apple 系统 App 用）：单一文件含全部语言，顶层键为语言代码（zh_CN / en 等）
    private static func readName(inLocTable bundle: Bundle, localization: String) -> String? {
        // loctable 通常在 Resources 根目录（不在 .lproj 内），不能带 forLocalization: 查找
        guard let path = bundle.path(forResource: "InfoPlist", ofType: "loctable"),
              let table = NSDictionary(contentsOfFile: path) else { return nil }

        let variants = localeKeyVariants(localization)
        for key in variants {
            if let sub = table[key] as? [String: Any], let n = name(from: sub) { return n }
        }
        // 前缀兜底：zh_CN 匹配偏好 zh-Hans 等
        for case let (key as String, sub as [String: Any]) in table {
            if variants.contains(where: { key.hasPrefix($0) }), let n = name(from: sub) { return n }
        }
        return nil
    }

    /// loctable 的键变体：zh-Hans-CN → [zh-Hans-CN, zh_Hans_CN, zh-Hans, zh-Hans_CN, zh, zh_Hans]
    private static func localeKeyVariants(_ loc: String) -> [String] {
        var out = [loc, loc.replacingOccurrences(of: "-", with: "_")]
        let parts = loc.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
        if parts.count > 1 {
            out.append(parts.prefix(2).joined(separator: "-"))
            out.append(parts.prefix(2).joined(separator: "_"))
            out.append(parts[0])
        }
        return out
    }

    private static func name(from dict: [String: Any]) -> String? {
        if let n = dict["CFBundleDisplayName"] as? String, !n.isEmpty { return n }
        if let n = dict["CFBundleName"] as? String, !n.isEmpty { return n }
        return nil
    }
}
