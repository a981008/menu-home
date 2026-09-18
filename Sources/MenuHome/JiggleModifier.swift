import SwiftUI

/// 编辑模式（抖动）修饰器：
/// - active && !reduceMotion：±1.6° 摆动（easeInOut 0.16s 往复循环），seed 决定随机相位
/// - active && reduceMotion：改为 0.75↔1 透明度呼吸（同样往复循环）
/// - 非 active：原样返回（角度 0、透明度 1，不产生任何视觉差异）
struct JiggleModifier: ViewModifier {

    var active: Bool
    /// 0...1 稳定伪随机种子，决定启动延迟（避免整排格子同步抖动）
    var seed: Double
    var reduceMotion: Bool

    /// 动画开关：active 期间以随机相位延迟翻为 true，触发往复循环动画
    /// （手工脱糖的 @State —— 本机 CLT 缺 SwiftUIMacros 插件）
    private var _on: State<Bool> = State(initialValue: false)
    private var on: Bool {
        get { _on.wrappedValue }
        nonmutating set { _on.wrappedValue = newValue }
    }

    func body(content: Content) -> some View {
        content
            // 非 active 时角度恒为 0、透明度恒为 1，等效于原样返回；
            // 用统一修饰而不是 if/else 分支，保证视图身份稳定、onChange 能正常触发
            .rotationEffect(.degrees(angle))
            .opacity(breathingOpacity)
            .task(id: active) {
                // active 变 true（含视图首次出现即处于编辑态）时启动；变 false 时任务自动取消
                guard active else { return }
                try? await Task.sleep(nanoseconds: UInt64(seed * 0.25 * 1_000_000_000))
                guard !Task.isCancelled else { return }
                on = false // 先复位，保证重复进入编辑模式时动画能重新启动
                withAnimation(.easeInOut(duration: 0.16).repeatForever(autoreverses: true)) {
                    on = true
                }
            }
            .onChange(of: active) { isActive in
                if !isActive { on = false }
            }
    }

    /// 抖动角度：仅 active && !reduceMotion 时在 -1.6° ↔ 1.6° 间摆动
    private var angle: Double {
        guard active, !reduceMotion else { return 0 }
        return on ? 1.6 : -1.6
    }

    /// 呼吸透明度：仅 active && reduceMotion 时在 1 ↔ 0.75 间呼吸
    private var breathingOpacity: Double {
        guard active, reduceMotion else { return 1 }
        return on ? 0.75 : 1
    }
}
