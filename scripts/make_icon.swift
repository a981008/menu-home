// MenuHome 应用图标生成器：与状态栏图标同源的设计语言
// （systemBlue → systemIndigo 渐变圆角矩形 + 顶部高光 + 白色房子），
// 按 macOS 大图标规范绘制（1024 画布 / 824 图块 / 连续大圆角），
// 输出全套 iconset PNG，随后由 make_icon.sh 用 iconutil 合成 .icns。
// 运行：xcrun swiftc -O scripts/make_icon.swift -o .build/make_icon && .build/make_icon
import AppKit

let canvas: CGFloat = 1024
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)   // 图标主体（四周各留 100）
let cornerRadius: CGFloat = 185

let img = NSImage(size: NSSize(width: canvas, height: canvas))
img.lockFocus()

let squircle = NSBezierPath(roundedRect: tile, xRadius: cornerRadius, yRadius: cornerRadius)

// 1. 背景：蓝 → 靛对角渐变（与状态栏图标同色系）
NSGradient(colors: [NSColor.systemBlue, NSColor.systemIndigo])!
    .draw(in: squircle, angle: -70)

// 2. 顶部玻璃高光：裁剪进圆角矩形，仅上半部白色渐隐
if let ctx = NSGraphicsContext.current?.cgContext {
    ctx.saveGState()
    squircle.addClip()
    let band = CGRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2)
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.06), NSColor.white.withAlphaComponent(0.30)])!
        .draw(in: band, angle: 90)
    ctx.restoreGState()
}

// 3. 内缘细描边（裁剪内画，避免外半圈落在透明画布上形成暗晕）
if let ctx = NSGraphicsContext.current?.cgContext {
    ctx.saveGState()
    squircle.addClip()
    squircle.lineWidth = 6
    NSColor.black.withAlphaComponent(0.12).setStroke()
    squircle.stroke()
    ctx.restoreGState()
}

// 4. 白色房子（状态栏图标的房子等比放大、居中于图块）
//    状态栏画布 18pt → 缩放系数 k；房子占图块约 44% 高 / 47% 宽
let k: CGFloat = 57.2
func P(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
    NSPoint(x: tile.midX + (x - 9) * k, y: tile.midY + (y - 9) * k)
}
let white = NSColor.white

// 屋顶（圆角连接的描边增加字重，同状态栏画法）
let roof = NSBezierPath()
roof.move(to: P(5.6, 9.4))
roof.line(to: P(9, 12.2))
roof.line(to: P(12.4, 9.4))
roof.close()
white.setFill()
roof.fill()
white.setStroke()
roof.lineWidth = 0.6 * k
roof.lineJoinStyle = .round
roof.stroke()

// 墙体 + 门（even-odd 挖空，门底与墙底齐平）
let bodyDoor = NSBezierPath()
bodyDoor.append(NSBezierPath(rect: NSRect(x: P(6.4, 5.9).x, y: P(6.4, 5.9).y,
                                          width: 5.2 * k, height: 3.9 * k)))
bodyDoor.append(NSBezierPath(rect: NSRect(x: P(8.3, 5.9).x, y: P(8.3, 5.9).y,
                                          width: 1.4 * k, height: 1.6 * k)))
bodyDoor.windingRule = .evenOdd
white.setFill()
bodyDoor.fill()

img.unlockFocus()

// 5. 输出 iconset 全尺寸 PNG
let sizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

let fm = FileManager.default
let outDir = "Assets/AppIcon.iconset"
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

for (name, px) in sizes {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(px), pixelsHigh: Int(px),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px),
             from: NSRect(x: 0, y: 0, width: canvas, height: canvas),
             operation: .sourceOver, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    try data.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}
print("✅ iconset 已生成：\(outDir)（\(sizes.count) 个尺寸）")
