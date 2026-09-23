// Placeholder app icon: rounded blue square with a white "S" glyph.
// Usage: swift scripts/make-icon.swift App/Resources/AppIcon.icns
import AppKit

let out = CommandLine.arguments.dropFirst().first ?? "AppIcon.icns"
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: tmp)
try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let size = NSSize(width: px, height: px)
    let img = NSImage(size: size)
    img.lockFocus()
    let s = CGFloat(px)
    let inset = s * 0.08   // macOS icons leave margin around the tile
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.22, yRadius: rect.width * 0.22)
    let grad = NSGradient(starting: NSColor(calibratedRed: 0.20, green: 0.50, blue: 1.00, alpha: 1),
                          ending:   NSColor(calibratedRed: 0.05, green: 0.30, blue: 0.85, alpha: 1))!
    grad.draw(in: path, angle: -90)
    let font = NSFont.systemFont(ofSize: rect.height * 0.62, weight: .bold)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
    let str = NSAttributedString(string: "S", attributes: attrs)
    let ts = str.size()
    str.draw(at: NSPoint(x: rect.midX - ts.width / 2, y: rect.midY - ts.height / 2 + rect.height * 0.02))
    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: tmp.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: tmp.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", tmp.path, "-o", out]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "wrote \(out)" : "iconutil failed")
