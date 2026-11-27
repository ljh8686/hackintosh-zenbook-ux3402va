import AppKit
let sz: CGFloat = 1024
let img = NSImage(size: NSSize(width: sz, height: sz))
img.lockFocus()
let rect = NSRect(x: 0, y: 0, width: sz, height: sz)
let path = NSBezierPath(roundedRect: rect.insetBy(dx: sz*0.06, dy: sz*0.06), xRadius: sz*0.22, yRadius: sz*0.22)
let grad = NSGradient(colors: [NSColor(srgbRed:0.13,green:0.35,blue:0.75,alpha:1), NSColor(srgbRed:0.10,green:0.60,blue:0.90,alpha:1)])!
grad.draw(in: path, angle: -90)
// 三条白色滑块
let white = NSColor.white
func slider(_ y: CGFloat, _ frac: CGFloat) {
    let x0 = sz*0.20, x1 = sz*0.80, h = sz*0.035
    let track = NSBezierPath(roundedRect: NSRect(x: x0, y: y, width: x1-x0, height: h), xRadius: h/2, yRadius: h/2)
    white.withAlphaComponent(0.55).setFill(); track.fill()
    let kx = x0 + (x1-x0)*frac
    let kd = sz*0.11
    let knob = NSBezierPath(ovalIn: NSRect(x: kx-kd/2, y: y + h/2 - kd/2, width: kd, height: kd))
    white.setFill(); knob.fill()
}
slider(sz*0.58, 0.85)
slider(sz*0.44, 0.45)
slider(sz*0.30, 0.68)
img.unlockFocus()
if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
    try! png.write(to: URL(fileURLWithPath: "/tmp/asusconsole/icon_1024.png"))
    print("icon png ok")
}
