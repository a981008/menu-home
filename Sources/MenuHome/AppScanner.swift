import Foundation

/// 扫描本机安装的 App（/Applications、~/Applications、/System/Applications 顶层）
enum AppScanner {

    static func scanApps() -> [AppEntry] {
        let dirs = [
            "/Applications",
            NSString(string: "~/Applications").expandingTildeInPath,
            "/System/Applications",
        ]
        let selfBundleID = Bundle.main.bundleIdentifier

        var byID: [String: AppEntry] = [:]
        var order: [String] = []

        for dir in dirs {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for name in names where name.hasSuffix(".app") {
                let path = dir + "/" + name
                guard let bundle = Bundle(url: URL(fileURLWithPath: path)),
                      let bundleID = bundle.bundleIdentifier else { continue }
                // 跳过自身；同一 bundle id 先出现的优先（/Applications 优先于 /System）
                guard bundleID != selfBundleID, byID[bundleID] == nil else { continue }

                let displayName =
                    bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String
                    ?? bundle.infoDictionary?["CFBundleDisplayName"] as? String
                    ?? bundle.localizedInfoDictionary?["CFBundleName"] as? String
                    ?? bundle.infoDictionary?["CFBundleName"] as? String
                    ?? (name as NSString).deletingPathExtension

                byID[bundleID] = AppEntry(bundleID: bundleID, name: displayName, path: path)
                order.append(bundleID)
            }
        }

        return order.compactMap { byID[$0] }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
