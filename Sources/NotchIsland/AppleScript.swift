import AppKit

/// Runs AppleScript on a single serial queue (NSAppleScript is not thread-safe).
enum AppleScript {
    private static let queue = DispatchQueue(label: "notchisland.applescript", qos: .userInitiated)

    /// Compiled scripts, keyed by source (compiling is the expensive part). Only accessed on `queue`.
    private static var cache: [String: NSAppleScript] = [:]

    static func run(_ source: String, completion: ((NSAppleEventDescriptor?) -> Void)? = nil) {
        queue.async {
            var error: NSDictionary?
            let script: NSAppleScript?
            if let cached = cache[source] {
                script = cached
            } else {
                script = NSAppleScript(source: source)
                if script?.compileAndReturnError(&error) == true, cache.count < 64 { cache[source] = script }
            }
            let result = error == nil ? script?.executeAndReturnError(&error) : nil
            if let error { NSLog("[NotchIsland] AppleScript error: %@", error) }
            let output = error == nil ? result : nil
            if let completion { DispatchQueue.main.async { completion(output) } }
        }
    }
}

enum Shell {
    static func run(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try? p.run()
    }

    /// Runs a command synchronously and returns its stdout (call off the main thread).
    static func output(_ path: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}

extension NSImage {
    /// Average color of the image, brightened so it reads well on black.
    var vibrantAverageColor: NSColor? {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        let ok: Bool = px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                      bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard ok else { return nil }
        let c = NSColor(srgbRed: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(hue: h, saturation: min(s * 1.2, 0.85), brightness: max(b, 0.8), alpha: 1)
    }
}
