import SwiftUI
import AppKit

/// 面板毛玻璃背景：包装 NSVisualEffectView（.popover 材质，behindWindow 混合）
struct VisualEffectBackground: NSViewRepresentable {

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        // 材质参数固定，无需随状态更新
    }
}
