import SwiftUI

/// macOS 27（Tahoe）液态玻璃设计语言（部署目标 macOS 26+，glassEffect 原生可用）
/// - 大的连续圆角：主要玻璃面统一 28（面板 / 文件夹卡片 / 搜索 / 添加浮层）；
///   胶囊 21 / 搜索栏 15 / 拖影 16 / 内滚区 10
/// - 液态玻璃材质：折射 + 高光，由系统实时渲染
enum Theme {
    static let panelRadius: CGFloat = 28    // 主要玻璃面统一圆角（面板 / 卡片 / 浮层）
    static let pillRadius: CGFloat = 21     // 编辑条胶囊（高度 42 的一半）
    static let searchBarRadius: CGFloat = 15 // 常驻搜索栏胶囊（高度 30 的一半）
    static let ghostRadius: CGFloat = 16    // 拖影
    static let scrollClipRadius: CGFloat = 10 // 玻璃容器内滚动区裁剪（滚轴/内容不得溢出圆角）

    // 手绘窗口阴影（系统阴影在玻璃渲染路径下按整窗矩形采样、圆角外露直角，已禁用 —— 见 PanelController）
    static let shadowMargin: CGFloat = 40    // 窗口四周透明边距：容纳阴影外溢 + 点击穿透区
    static let shadowBlur: CGFloat = 16      // 阴影模糊半径
    static let shadowOffsetY: CGFloat = 8    // 阴影向下偏移
    static let shadowOpacity: Double = 0.32  // 阴影浓度

    // 面板与状态栏的间隙：玻璃顶边悬停在菜单栏下缘之上，不直接压住
    // （对齐控制中心等系统状态栏弹窗的呼吸距离；面板定位见 PanelController.positionPanel）
    static let statusBarGap: CGFloat = 6
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
