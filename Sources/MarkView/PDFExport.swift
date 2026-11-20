import Cocoa
import WebKit

/// Settings shared by File > Export as PDF and the `--pdf` command line mode,
/// so both produce identical PDFs.
enum PDFSettings {
    static func configure(_ info: NSPrintInfo) {
        info.topMargin = 40
        info.bottomMargin = 40
        info.leftMargin = 36
        info.rightMargin = 36
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = false
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
    }

    static func saveInfo(to url: URL) -> NSPrintInfo {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        configure(info)
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        return info
    }

    /// ~/Downloads/<name>.pdf, or "<name> 2.pdf", "<name> 3.pdf"… if taken.
    static func uniqueDownloadsURL(baseName: String) -> URL {
        let fm = FileManager.default
        let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        var url = downloads.appendingPathComponent(baseName + ".pdf")
        var n = 2
        while fm.fileExists(atPath: url.path) {
            url = downloads.appendingPathComponent("\(baseName) \(n).pdf")
            n += 1
        }
        return url
    }
}

/// Headless Markdown → PDF conversion: `MarkView --pdf <input.md> [output.pdf | output-dir]`.
/// Prints the PDF's path on stdout and exits 0, or prints an error on stderr and exits 1.
final class CommandLineExporter: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    static let usage = """
        usage: md2pdf <input.md> [output.pdf | output-directory]

        Renders Markdown to PDF exactly like MarkView's File > Export as PDF
        (GitHub style, light theme, syntax colours, Mermaid diagrams, paginated).
        Default output: ~/Downloads/<name>.pdf (never overwrites; adds " 2", " 3"...).
        Prints the PDF path on success.
        """

    private let input: URL
    private let output: URL
    private var webView: WKWebView!
    private var window: NSWindow!
    private var readyPolls = 0

    /// Parses arguments after `--pdf`. Returns nil (after printing usage) if invalid.
    init?(arguments: [String]) {
        let args = arguments.filter { !$0.hasPrefix("-psn_") }
        if args.isEmpty || args.contains("-h") || args.contains("--help") || args.count > 2 {
            FileHandle.standardError.write(Data((Self.usage + "\n").utf8))
            return nil
        }
        input = URL(fileURLWithPath: (args[0] as NSString).expandingTildeInPath).standardizedFileURL
        let baseName = input.deletingPathExtension().lastPathComponent
        if args.count == 2 {
            var out = URL(fileURLWithPath: (args[1] as NSString).expandingTildeInPath).standardizedFileURL
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: out.path, isDirectory: &isDir), isDir.boolValue {
                out = out.appendingPathComponent(baseName + ".pdf")
            }
            output = out
        } else {
            output = PDFSettings.uniqueDownloadsURL(baseName: baseName)
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let data = try? Data(contentsOf: input) else {
            fail("cannot read \(input.path)")
        }
        // Overall safety timeout.
        DispatchQueue.main.asyncAfter(deadline: .now() + 90) { [weak self] in self?.fail("timed out") }

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(LocalSchemeHandler(), forURLScheme: LocalSchemeHandler.scheme)
        let frame = NSRect(x: 0, y: 0, width: 1000, height: 1400)
        webView = WKWebView(frame: frame, configuration: config)
        webView.appearance = NSAppearance(named: .aqua)   // PDFs are always light
        webView.navigationDelegate = self
        window = NSWindow(contentRect: frame.offsetBy(dx: -30000, dy: -30000),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = webView

        let body = MarkdownRenderer.html(from: MarkdownDocument.decode(data))
        webView.loadHTMLString(PageTemplate.page(body: body, showTOC: false),
                               baseURL: LocalSchemeHandler.url(for: input))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        waitUntilReady()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail("render failed: \(error.localizedDescription)")
    }

    /// Waits for images and Mermaid diagrams to finish before printing.
    private func waitUntilReady() {
        webView.evaluateJavaScript("MV.isReady()") { [weak self] result, _ in
            guard let self else { return }
            self.readyPolls += 1
            if (result as? Bool) == true || self.readyPolls > 150 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.printPDF() }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.waitUntilReady() }
            }
        }
    }

    private func printPDF() {
        try? FileManager.default.createDirectory(at: output.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let op = webView.printOperation(with: PDFSettings.saveInfo(to: output))
        op.view?.frame = webView.bounds
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        op.runModal(for: window, delegate: self,
                    didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
    }

    @objc private func printOperationDidRun(_ op: NSPrintOperation, success: Bool,
                                            contextInfo: UnsafeMutableRawPointer?)
    {
        guard success, FileManager.default.fileExists(atPath: output.path) else {
            fail("could not write \(output.path)")
        }
        FileHandle.standardOutput.write(Data((output.path + "\n").utf8))
        exit(0)
    }

    private func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("md2pdf: \(message)\n".utf8))
        exit(1)
    }
}
