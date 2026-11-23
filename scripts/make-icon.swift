// Renders Resources/AppIcon.icns from the same lens logo the app shows next to the notch.
// Usage: swift scripts/make-icon.swift   (run from the repo root)
import AppKit
import SwiftUI

let colors: [Color] = [
    Color(red: 0.35, green: 0.85, blue: 1.0), Color(red: 0.36, green: 0.42, blue: 1.0),
    Color(red: 0.75, green: 0.35, blue: 1.0), Color(red: 1.0, green: 0.38, blue: 0.62),
    Color(red: 1.0, green: 0.66, blue: 0.3), Color(red: 0.35, green: 0.85, blue: 1.0),
]

struct Icon: View {
    var body: some View {
        let gradient = AngularGradient(colors: colors, center: .center, angle: .degrees(-40))
        let s: CGFloat = 470 // logo diameter
        ZStack {
            // macOS icon grid: 824pt squircle centred in a 1024 canvas
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.03)], startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
            // the notch
            UnevenRoundedRectangle(bottomLeadingRadius: 34, bottomTrailingRadius: 34)
                .fill(.black)
                .frame(width: 330, height: 74)
                .offset(y: -375)
            ZStack {
                Circle().fill(gradient).blur(radius: s * 0.2).opacity(0.55)
                Circle().strokeBorder(gradient, lineWidth: s * 0.15)
                Circle().fill(Color(white: 0.06)).padding(s * 0.15)
                Circle().fill(gradient).frame(width: s * 0.3, height: s * 0.3).opacity(0.95)
                Circle().fill(.white.opacity(0.9)).frame(width: s * 0.13, height: s * 0.13)
                    .offset(x: -s * 0.16, y: -s * 0.16)
            }
            .frame(width: s, height: s)
            .offset(y: 30)
        }
        .frame(width: 1024, height: 1024)
        .clipShape(RoundedRectangle(cornerRadius: 185, style: .continuous).size(width: 824, height: 824).offset(x: 100, y: 100))
        .padding(0)
    }
}

@MainActor func render() throws {
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = 1
    guard let cg = renderer.cgImage else { fatalError("render failed") }
    let fm = FileManager.default
    let set = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
    try? fm.removeItem(at: set)
    try fm.createDirectory(at: set, withIntermediateDirectories: true)
    for base in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let px = base * scale
            let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.interpolationQuality = .high
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: px, height: px))
            let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
            let data = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
            try data.write(to: set.appendingPathComponent(name))
        }
    }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    p.arguments = ["-c", "icns", set.path, "-o", "Resources/AppIcon.icns"]
    try p.run(); p.waitUntilExit()
    print(p.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
}

try MainActor.assumeIsolated { try render() }
