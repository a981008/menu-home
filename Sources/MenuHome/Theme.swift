import SwiftUI

/// macOS 27（Tahoe）液态玻璃设计语言（部署目标 macOS 26+，glassEffect 原生可用）
/// - 大的连续圆角：面板 28 / 卡片 26 / 浮层 22-24 / 胶囊 21 / 拖影 16
/// - 液态玻璃材质：折射 + 高光，由系统实时渲染
enum Theme {
    static let panelRadius: CGFloat = 28    // 主面板
    static let cardRadius: CGFloat = 26     // 文件夹展开卡片
    static let overlayRadius: CGFloat = 24  // 添加 App 浮层
    static let sheetRadius: CGFloat = 22    // 搜索浮层
    static let pillRadius: CGFloat = 21     // 编辑条胶囊（高度 42 的一半）
    static let ghostRadius: CGFloat = 16    // 拖影
}

/// 液态玻璃圆角背景
private struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    var interactive: Bool

    func body(content: Content) -> some View {
        let glass: Glass = interactive ? .regular.interactive() : .regular
        // 连续曲率圆角（squircle，Apple HIG）：glassEffect 内部形状显式指定
        content.glassEffect(glass, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    /// 液态玻璃圆角容器（默认 interactive：随指针产生液态高光反馈）
    func liquidGlass(cornerRadius: CGFloat, interactive: Bool = true) -> some View {
        modifier(LiquidGlassModifier(cornerRadius: cornerRadius, interactive: interactive))
    }

    /// 玻璃按钮
    func glassButton() -> some View {
        buttonStyle(.glass)
    }

    /// 玻璃主按钮
    func glassProminentButton() -> some View {
        buttonStyle(.glassProminent)
    }
}
