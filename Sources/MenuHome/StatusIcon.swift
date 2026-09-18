import AppKit

/// 状态栏图标：18×18 圆角小房子轮廓（模板图，自动适配深浅色与高亮态）
enum StatusIcon {

    static func house() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { _ in
            let path = NSBezierPath()
            path.lineWidth = 1.6
            path.lineCapStyle = .round
            path.lineJoinStyle = .round

            // 屋顶
            path.move(to: NSPoint(x: 2.4, y: 8.6))
            path.line(to: NSPoint(x: 9, y: 2.6))
            path.line(to: NSPoint(x: 15.6, y: 8.6))

            // 墙体
            path.move(to: NSPoint(x: 4.2, y: 7.4))
            path.line(to: NSPoint(x: 4.2, y: 15.2))
            path.line(to: NSPoint(x: 13.8, y: 15.2))
            path.line(to: NSPoint(x: 13.8, y: 7.4))

            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        img.isTemplate = true
        return img
    }
}
