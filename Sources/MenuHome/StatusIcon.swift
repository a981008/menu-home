import AppKit

/// 状态栏图标：迷你 App 图标 —— 彩色渐变圆角底 + 玻璃高光 + 白色房子，
/// 让状态栏入口看起来就像点开一个 App 的菜单（非模板图，保留彩色）
enum StatusIcon {

    static func appIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { _ in
            let bounds = NSRect(origin: .zero, size: size)
            let squircle = NSBezierPath(roundedRect: bounds, xRadius: 4.5, yRadius: 4.5)

            // 1. 底色渐变：系统蓝（上）→ 靛蓝（下）
            NSGradient(colors: [.systemBlue, .systemIndigo])?
                .draw(in: squircle, angle: -90)

            // 2. 玻璃高光：顶部一层上亮下无的白色渐变（裁剪进圆角内）
            NSGraphicsContext.saveGraphicsState()
            squircle.addClip()
            NSGradient(colors: [NSColor.white.withAlphaComponent(0.06),
                                NSColor.white.withAlphaComponent(0.32)])?
                .draw(in: NSRect(x: 0, y: 9, width: 18, height: 9), angle: 90)
            NSGraphicsContext.restoreGraphicsState()

            // 3. 细描边：浅色菜单栏上提供轮廓感
            squircle.lineWidth = 0.5
            NSColor.black.withAlphaComponent(0.15).setStroke()
            squircle.stroke()

            // 4. 白色房子：屋顶三角 + 墙体（白色描边同色加圆角感）+ 靛蓝门
            let white = NSColor.white
            let roof = NSBezierPath()
            roof.move(to: NSPoint(x: 3.3, y: 9.6))
            roof.line(to: NSPoint(x: 9, y: 14.4))
            roof.line(to: NSPoint(x: 14.7, y: 9.6))
            roof.close()
            white.setFill()
            roof.fill()
            roof.lineWidth = 1
            roof.lineJoinStyle = .round
            white.setStroke()
            roof.stroke()

            let body = NSBezierPath(rect: NSRect(x: 4.7, y: 3.8, width: 8.6, height: 6.6))
            white.setFill()
            body.fill()

            let door = NSBezierPath(rect: NSRect(x: 7.85, y: 3.8, width: 2.3, height: 3.6))
            NSColor.systemIndigo.setFill()
            door.fill()

            return true
        }
        img.isTemplate = false
        img.accessibilityDescription = "MenuHome"
        return img
    }
}
