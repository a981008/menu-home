import AppKit

/// 监听系统 App 启动/退出，维护「正在运行」bundle id 集合（驱动格子右下角圆点）
enum RunningMonitor {

    @MainActor
    static func start(store: HomeStore) {
        func snapshot() -> Set<String> {
            Set(
                NSWorkspace.shared.runningApplications
                    .filter { $0.activationPolicy == .regular }
                    .compactMap { $0.bundleIdentifier }
            )
        }

        store.runningBundleIDs = snapshot()

        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { store.runningBundleIDs = snapshot() }
        }
        nc.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { store.runningBundleIDs = snapshot() }
        }
    }
}
