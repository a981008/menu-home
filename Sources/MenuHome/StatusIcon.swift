import AppKit

/// 状态栏图标：透明底的「App 图标」—— 圆角矩形轮廓内一枚房子，
/// 模板图渲染（黑 + alpha），自动适配菜单栏深浅色与高亮态
enum StatusIcon {

    static func appIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { _ in
            let black = NSColor.black

            // App 图标轮廓：圆角矩形描边（底色透明）
            let squircle = NSBezierPath(roundedRect: NSRect(x: 0.75, y: 0.75, width: 16.5, height: 16.5),
                                        xRadius: 4.5, yRadius: 4.5)
            squircle.lineWidth = 1.4
            black.setStroke()
            squircle.stroke()

            // 房子：屋顶（描边加重量）+ 墙体（门用 even-odd 挖空，门底与墙底齐平）
            let roof = NSBezierPath()
            roof.move(to: NSPoint(x: 5.6, y: 9.4))
            roof.line(to: NSPoint(x: 9, y: 12.2))
            roof.line(to: NSPoint(x: 12.4, y: 9.4))
            roof.close()
            roof.lineWidth = 0.8
            roof.lineJoinStyle = .round
            black.setFill()
            roof.fill()
            black.setStroke()
            roof.stroke()

            let bodyDoor = NSBezierPath()
            bodyDoor.append(NSBezierPath(rect: NSRect(x: 6.4, y: 5.9, width: 5.2, height: 3.9)))
            bodyDoor.append(NSBezierPath(rect: NSRect(x: 8.3, y: 5.9, width: 1.4, height: 1.6)))
            bodyDoor.windingRule = .evenOdd
            black.setFill()
            bodyDoor.fill()

            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "MenuHome"
        return img
    }
}
