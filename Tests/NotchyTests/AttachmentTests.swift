import AppKit
import Foundation
import Testing
@testable import NotchIsland

/// A fresh temporary folder per test.
final class TempDir {
    let url: URL
    init() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("NotchyTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }

    @discardableResult
    func file(_ name: String, _ data: Data) -> URL {
        let u = url.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: u.path, contents: data)
        return u
    }

    func file(_ name: String, _ text: String) -> URL { file(name, Data(text.utf8)) }

    func png(_ name: String, width: Int, height: Int) -> URL {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        return file(name, rep.representation(using: .png, properties: [:])!)
    }

    func pdf(_ name: String) -> URL {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 200, height: 200)
        let consumer = CGDataConsumer(data: data as CFMutableData)!
        let ctx = CGContext(consumer: consumer, mediaBox: &box, nil)!
        ctx.beginPDFPage(nil); ctx.endPDFPage(); ctx.closePDF()
        return file(name, data as Data)
    }
}

@Suite("Attachments")
struct AttachmentTests {
    @Test func classifiesCommonFiles() throws {
        let t = TempDir()
        #expect(ClaudeAttachment.classify(t.png("shot.png", width: 4, height: 4)) == .image)
        #expect(ClaudeAttachment.classify(t.pdf("doc.pdf")) == .pdf)
        #expect(ClaudeAttachment.classify(t.file("notes.txt", "hello")) == .text)
        #expect(ClaudeAttachment.classify(t.file("main.swift", "let x = 1")) == .text)
        #expect(ClaudeAttachment.classify(t.file("data.json", #"{"a":1}"#)) == .text)
        #expect(ClaudeAttachment.classify(t.file("Makefile", "all:\n\techo hi")) == .text)
        #expect(ClaudeAttachment.classify(t.file("blob.bin", Data([0, 1, 2, 0, 255]))) == .unsupported("Claude can't read .bin files"))
        #expect(ClaudeAttachment.classify(t.url.appendingPathComponent("missing.txt")) == .unsupported("File not found"))
        let folder = t.url.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(ClaudeAttachment.classify(folder) == .folder)
    }

    @Test func appBundlesAreNotFolders() throws {
        let t = TempDir()
        let app = t.url.appendingPathComponent("Thing.app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        #expect(!ClaudeAttachment.make(t.url.appendingPathComponent("Thing.app")).isUsable)
    }

    @Test func oversizedTextIsRejectedNotTruncated() {
        let t = TempDir()
        let big = t.file("huge.log", String(repeating: "a", count: ClaudeAttachment.maxTextBytes + 1))
        #expect(ClaudeAttachment.classify(big) == .unsupported("Text file is over 2 MB"))
        #expect(throws: (any Error).self) { try ClaudeAttachment.make(big).contentBlock() }
    }

    @Test func textBecomesPlainTextDocument() throws {
        let t = TempDir()
        let b = try ClaudeAttachment.make(t.file("notes.md", "# Hi\nBuy milk")).contentBlock()
        #expect(b["type"] as? String == "document")
        #expect(b["title"] as? String == "notes.md")
        let src = try #require(b["source"] as? [String: Any])
        #expect(src["type"] as? String == "text")
        #expect(src["media_type"] as? String == "text/plain")
        #expect(src["data"] as? String == "# Hi\nBuy milk")
        // An empty file still sends a non-empty block (the API rejects empty text).
        let empty = try ClaudeAttachment.make(t.file("empty.txt", "")).contentBlock()
        #expect((empty["source"] as? [String: Any])?["data"] as? String == "(empty file)")
    }

    @Test func pdfBecomesBase64Document() throws {
        let t = TempDir()
        let url = t.pdf("report.pdf")
        let b = try ClaudeAttachment.make(url).contentBlock()
        let src = try #require(b["source"] as? [String: Any])
        #expect(b["type"] as? String == "document")
        #expect(src["type"] as? String == "base64")
        #expect(src["media_type"] as? String == "application/pdf")
        #expect(Data(base64Encoded: src["data"] as? String ?? "") == (try Data(contentsOf: url)))
    }

    @Test func smallPNGIsSentAsIs() throws {
        let t = TempDir()
        let url = t.png("small.png", width: 64, height: 32)
        let b = try ClaudeAttachment.make(url).contentBlock()
        let src = try #require(b["source"] as? [String: Any])
        #expect(b["type"] as? String == "image")
        #expect(src["media_type"] as? String == "image/png")
        #expect(Data(base64Encoded: src["data"] as? String ?? "") == (try Data(contentsOf: url)))
    }

    @Test func largeImageIsScaledToJPEG() throws {
        let t = TempDir()
        let (data, type) = try ClaudeAttachment.imageData(t.png("big.png", width: 3200, height: 1600))
        #expect(type == "image/jpeg")
        let rep = try #require(NSBitmapImageRep(data: data))
        #expect(rep.pixelsWide == 1568)
        #expect(rep.pixelsHigh == 784)
        #expect(data.count <= ClaudeAttachment.maxImageBytes)
    }

    @Test func folderIsSentAsAListing() throws {
        let t = TempDir()
        t.file("site/index.html", "<p>hi</p>")
        t.file("site/css/app.css", "body{}")
        t.file("site/.secret", "hidden")
        let listing = ClaudeAttachment.folderListing(t.url.appendingPathComponent("site"))
        #expect(listing.contains("index.html"))
        #expect(listing.contains("css/"))
        #expect(listing.contains("css/app.css"))
        #expect(!listing.contains(".secret"))
        let b = try ClaudeAttachment.make(t.url.appendingPathComponent("site")).contentBlock()
        #expect(b["title"] as? String == "site/")
    }
}

@Suite("Markdown")
struct MarkdownTests {
    @Test func bulletsAndBold() {
        let s = String(Markdown.render("**Plan:** ship it\n- one\n- two").characters)
        #expect(s == "Plan: ship it\n• one\n• two")
        #expect(String(Markdown.render("- first").characters) == "• first")
    }

    @Test func firstLineForPopUp() {
        #expect(ClaudeService.firstLine("**Short answer:** yes\nMore detail") == "Short answer: yes")
        #expect(ClaudeService.firstLine("") == "")
    }
}
