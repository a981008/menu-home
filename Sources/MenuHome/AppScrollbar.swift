import SwiftUI

/// App 式滚动指示器：隐藏系统滚轴，在滚动容器右缘叠加一枚胶囊拇指 ——
/// 滚动时出现、停顿约 0.6s 后淡出，观感与 macOS 原生 App 的 overlay 滚轴一致。
/// 必须配合 `.clipShape` 使用：拇指与内容一起被裁剪进容器圆角内。
private struct ScrollInfo: Equatable {
    let offset: CGFloat      // 已滚动距离（顶部为 0）
    let viewport: CGFloat    // 可视高度
    let content: CGFloat     // 内容总高度（含安全区 insets）
}

private struct AppScrollbar: ViewModifier {
    // 手工脱糖的 @State（本机 CLT 缺宏插件）
    private var _progress: State<CGFloat> = State(initialValue: 0)
    private var progress: CGFloat {
        get { _progress.wrappedValue }
        nonmutating set { _progress.wrappedValue = newValue }
    }
    private var _thumbFraction: State<CGFloat> = State(initialValue: 1)
    private var thumbFraction: CGFloat {
        get { _thumbFraction.wrappedValue }
        nonmutating set { _thumbFraction.wrappedValue = newValue }
    }
    private var _visible: State<Bool> = State(initialValue: false)
    private var visible: Bool {
        get { _visible.wrappedValue }
        nonmutating set { _visible.wrappedValue = newValue }
    }
    private var _fadeTask: State<Task<Void, Never>?> = State(initialValue: nil)
    private var fadeTask: Task<Void, Never>? {
        get { _fadeTask.wrappedValue }
        nonmutating set { _fadeTask.wrappedValue = newValue }
    }

    private let thumbWidth: CGFloat = 7
    private let edgeInset: CGFloat = 3
    private let minThumbHeight: CGFloat = 30

    func body(content: Content) -> some View {
        content
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: ScrollInfo.self) { geo in
                ScrollInfo(
                    offset: geo.contentOffset.y + geo.contentInsets.top,
                    viewport: geo.containerSize.height,
                    content: geo.contentSize.height + geo.contentInsets.top + geo.contentInsets.bottom
                )
            } action: { _, now in
                let maxOffset = max(1, now.content - now.viewport)
                progress = min(1, max(0, now.offset / maxOffset))
                thumbFraction = min(1, now.viewport / max(1, now.content))
                if thumbFraction >= 1 {
                    visible = false
                } else {
                    show()
                }
            }
            .overlay(alignment: .trailing) {
                if visible {
                    GeometryReader { geo in
                        let trackH = geo.size.height - edgeInset * 2
                        let thumbH = max(minThumbHeight, trackH * thumbFraction)
                        Capsule()
                            .fill(Color.primary.opacity(0.32))
                            .frame(width: thumbWidth, height: thumbH)
                            .position(x: geo.size.width - thumbWidth / 2 - edgeInset,
                                      y: edgeInset + (trackH - thumbH) * progress + thumbH / 2)
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
    }

    private func show() {
        if !visible {
            withAnimation(.easeIn(duration: 0.08)) { visible = true }
        }
        fadeTask?.cancel()
        fadeTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { visible = false }
        }
    }
}

extension View {
    /// App 式滚轴：隐藏系统指示器，叠加胶囊拇指（滚动时出现、停顿淡出）
    func appScrollbar() -> some View {
        modifier(AppScrollbar())
    }
}
