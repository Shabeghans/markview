import Cocoa
import WebKit

/// Forwards script messages without the user content controller retaining the window controller.
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(c, didReceive: message)
    }
}

private extension NSToolbarItem.Identifier {
    static let toc = NSToolbarItem.Identifier("toc")
    static let edit = NSToolbarItem.Identifier("edit")
    static let reload = NSToolbarItem.Identifier("reload")
    static let copyMarkdown = NSToolbarItem.Identifier("copyMarkdown")
    static let appearance = NSToolbarItem.Identifier("appearance")
}

private enum Defaults {
    static let showTOC = "showTOC"
    static let pageZoom = "pageZoom"
}

final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate,
    WKNavigationDelegate, WKScriptMessageHandler, NSTextViewDelegate, NSMenuItemValidation
{
    private let webView: WKWebView
    private let editorScrollView: NSScrollView
    private let editor: NSTextView
    private let findBar = FindBar()
    /// Preview mode content: the find bar (hidden until ⌘F) above the web view.
    private let previewContainer: NSStackView
    private weak var copyButton: NSButton?
    private weak var editItem: NSToolbarItem?
    private weak var appearanceItem: NSToolbarItem?
    private var appearanceObservation: NSKeyValueObservation?

    private var pageLoaded = false
    private var previewIsStale = false
    private(set) var isEditing = false
    private var showTOC = UserDefaults.standard.bool(forKey: Defaults.showTOC)

    private var markdownDocument: MarkdownDocument? { document as? MarkdownDocument }

    init() {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(LocalSchemeHandler(), forURLScheme: LocalSchemeHandler.scheme)
        webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = true
        let zoom = UserDefaults.standard.double(forKey: Defaults.pageZoom)
        if zoom > 0 { webView.pageZoom = zoom }

        editorScrollView = NSTextView.scrollableTextView()
        editor = editorScrollView.documentView as! NSTextView

        findBar.isHidden = true
        previewContainer = NSStackView(views: [findBar, webView])
        previewContainer.orientation = .vertical
        previewContainer.alignment = .leading
        previewContainer.spacing = 0
        previewContainer.detachesHiddenViews = true
        for view in [findBar, webView] {
            view.widthAnchor.constraint(equalTo: previewContainer.widthAnchor).isActive = true
        }
        webView.setContentHuggingPriority(.defaultLow, for: .vertical)
        webView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.minSize = NSSize(width: 420, height: 300)
        window.tabbingMode = .preferred
        window.contentView = previewContainer
        window.center()
        super.init(window: window)

        findBar.onSearch = { [weak self] query in self?.runFind("MV.find(\(Self.jsonString(query)))") }
        findBar.onStep = { [weak self] step in self?.runFind("MV.findStep(\(step))") }
        findBar.onClose = { [weak self] in self?.hideFindBar() }
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.effectiveAppearanceDidChange() }
        }

        windowFrameAutosaveName = "MarkViewDocument"
        window.delegate = self
        config.userContentController.add(WeakScriptHandler(self), name: "copy")
        webView.navigationDelegate = self
        configureEditor()

        let toolbar = NSToolbar(identifier: "MarkViewToolbar.v2")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        window.toolbar = toolbar
        window.toolbarStyle = .unified
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func configureEditor() {
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.usesFindBar = true
        editor.isIncrementalSearchingEnabled = true
        editor.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        editor.textContainerInset = NSSize(width: 16, height: 16)
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.smartInsertDeleteEnabled = false
        editor.delegate = self
    }

    // MARK: - Content

    func loadInitialContent() {
        loadPage()
        window?.makeFirstResponder(webView)
        #if DEBUG
        // Test hook (debug builds only): MARKVIEW_TEST_EXPORT=1 runs Export as PDF right after opening.
        if ProcessInfo.processInfo.environment["MARKVIEW_TEST_EXPORT"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.exportPDF(nil)
            }
        }
        // MARKVIEW_TEST_FIND="query[;steps]" opens the find bar, types the query, then steps forward.
        if let spec = ProcessInfo.processInfo.environment["MARKVIEW_TEST_FIND"] {
            let parts = spec.split(separator: ";").map(String.init)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self else { return }
                self.showFindBar()
                self.findBar.simulateTyping(parts[0])
                for _ in 0..<(parts.count > 1 ? Int(parts[1]) ?? 0 : 0) { self.runFind("MV.findStep(1)") }
            }
        }
        #endif
    }

    /// Called after the document re-read its file (⌘R or a change on disk).
    func documentTextDidReload() {
        guard let doc = markdownDocument else { return }
        if isEditing {
            editor.string = doc.text
            doc.undoManager?.removeAllActions()
            previewIsStale = true
        } else {
            renderInPlace()
        }
    }

    private func loadPage() {
        guard let doc = markdownDocument else { return }
        let body = MarkdownRenderer.html(from: doc.text)
        let base = doc.fileURL.map(LocalSchemeHandler.url(for:))
            ?? LocalSchemeHandler.url(for: URL(fileURLWithPath: NSHomeDirectory() + "/"))
        pageLoaded = false
        webView.loadHTMLString(PageTemplate.page(body: body, showTOC: showTOC), baseURL: base)
    }

    /// Swaps in new HTML without reloading the page, so scroll position is kept.
    private func renderInPlace(completion: (() -> Void)? = nil) {
        guard let doc = markdownDocument else { return }
        guard pageLoaded else {
            loadPage()
            if let completion { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: completion) }
            return
        }
        let body = MarkdownRenderer.html(from: doc.text)
        // MV.render re-runs any active search and returns its state.
        webView.evaluateJavaScript("MV.render(\(Self.jsonString(body)))") { [weak self] result, error in
            if error != nil { self?.loadPage() } else { self?.updateFindStatus(result) }
            completion?()
        }
        previewIsStale = false
    }

    private static func jsonString(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed])) ?? Data("\"\"".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Actions

    @objc func reloadDocument(_ sender: Any?) {
        markdownDocument?.reloadFromDisk(window: window)
    }

    @objc func copyMarkdown(_ sender: Any?) {
        guard let doc = markdownDocument else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(doc.text, forType: .string)
        flashCopied()
    }

    private func flashCopied() {
        guard let button = copyButton else { return }
        button.title = "Copied"
        button.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak button] in
            button?.title = "Copy Markdown"
            button?.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        }
    }

    @objc func toggleEditMode(_ sender: Any?) {
        guard let window, let doc = markdownDocument else { return }
        isEditing.toggle()
        if isEditing {
            editor.string = doc.text
            doc.undoManager?.removeAllActions()
            window.contentView = editorScrollView
            window.makeFirstResponder(editor)
        } else {
            window.contentView = previewContainer
            window.makeFirstResponder(webView)
            renderInPlace()
        }
        updateEditItem()
    }

    private func updateEditItem() {
        editItem?.label = isEditing ? "Preview" : "Edit"
        editItem?.toolTip = isEditing ? "Show the rendered preview (⌘E)" : "Edit the Markdown source (⌘E)"
        editItem?.image = NSImage(systemSymbolName: isEditing ? "eye" : "pencil",
                                  accessibilityDescription: editItem?.label)
    }

    @objc func toggleTableOfContents(_ sender: Any?) {
        showTOC.toggle()
        UserDefaults.standard.set(showTOC, forKey: Defaults.showTOC)
        webView.evaluateJavaScript("MV.setTOC(\(showTOC))")
    }

    @objc func zoomIn(_ sender: Any?) { setZoom(webView.pageZoom * 1.1) }
    @objc func zoomOut(_ sender: Any?) { setZoom(webView.pageZoom / 1.1) }
    @objc func actualSize(_ sender: Any?) { setZoom(1.0) }

    private func setZoom(_ value: CGFloat) {
        let z = min(max(value, 0.5), 3.0)
        webView.pageZoom = z
        UserDefaults.standard.set(z, forKey: Defaults.pageZoom)
    }

    // MARK: - Find

    /// Edit > Find items. The editor uses AppKit's find bar; the preview uses ours.
    @objc func findAction(_ sender: NSMenuItem) {
        if isEditing {
            editor.performTextFinderAction(sender)
            return
        }
        switch NSTextFinder.Action(rawValue: sender.tag) {
        case .nextMatch?, .previousMatch?:
            let step = sender.tag == NSTextFinder.Action.previousMatch.rawValue ? -1 : 1
            if findBar.isHidden || findBar.query.isEmpty {
                showFindBar()
            } else {
                runFind("MV.findStep(\(step))")
            }
        default:
            showFindBar()
        }
    }

    private func showFindBar() {
        if findBar.isHidden {
            findBar.isHidden = false
            if !findBar.query.isEmpty { runFind("MV.find(\(Self.jsonString(findBar.query)))") }
        }
        findBar.focus()
    }

    private func hideFindBar() {
        findBar.isHidden = true
        webView.evaluateJavaScript("MV.findClear()")
        window?.makeFirstResponder(webView)
    }

    private func runFind(_ script: String) {
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            self?.updateFindStatus(result)
        }
    }

    private func updateFindStatus(_ result: Any?) {
        guard !findBar.isHidden, let state = result as? [String: Any] else { return }
        let count = (state["count"] as? NSNumber)?.intValue ?? 0
        let index = (state["index"] as? NSNumber)?.intValue ?? 0
        findBar.show(count: count, index: index)
    }

    // MARK: - Print & PDF export

    @objc func printDocument(_ sender: Any?) {
        runPrintJob(info: NSPrintInfo.shared.copy() as! NSPrintInfo, showPanels: true)
    }

    @objc func exportPDF(_ sender: Any?) {
        guard let doc = markdownDocument else { return }
        let baseName = doc.fileURL?.deletingPathExtension().lastPathComponent ?? doc.displayName ?? "Untitled"
        let url = PDFSettings.uniqueDownloadsURL(baseName: baseName)
        runPrintJob(info: PDFSettings.saveInfo(to: url), showPanels: false) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    /// Prints the rendered preview (paginated). Always uses light colours so
    /// dark mode doesn't produce white text on white paper.
    private func runPrintJob(info: NSPrintInfo, showPanels: Bool, completion: (() -> Void)? = nil) {
        if isEditing { toggleEditMode(nil) }
        PDFSettings.configure(info)

        let savedAppearance = webView.appearance
        webView.appearance = NSAppearance(named: .aqua)
        renderInPlace { [weak self] in
            // Wait for Mermaid to redraw diagrams in the light theme.
            self?.whenPageReady {
                guard let self, let window = self.window else { return }
                let op = self.webView.printOperation(with: info)
                op.view?.frame = self.webView.bounds
                op.showsPrintPanel = showPanels
                op.showsProgressPanel = true
                self.printCompletion = { [weak self] ok in
                    self?.webView.appearance = savedAppearance
                    self?.renderInPlace()
                    if ok { completion?() }
                }
                // WKWebView needs the asynchronous variant; run() produces blank pages.
                op.runModal(for: window, delegate: self,
                            didRun: #selector(self.printOperationDidRun(_:success:contextInfo:)),
                            contextInfo: nil)
            }
        }
    }

    /// Calls `body` once images and Mermaid diagrams have finished (max ~10 s).
    private func whenPageReady(polls: Int = 0, _ body: @escaping () -> Void) {
        webView.evaluateJavaScript("MV.isReady()") { [weak self] result, _ in
            if (result as? Bool) == true || polls > 100 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: body)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self?.whenPageReady(polls: polls + 1, body)
                }
            }
        }
    }

    // MARK: - Appearance

    @objc func toggleAppearance(_ sender: Any?) {
        AppearanceSettings.toggle()
    }

    /// Re-render when light/dark changes so Mermaid diagrams pick the matching theme.
    private func effectiveAppearanceDidChange() {
        updateAppearanceItem()
        if pageLoaded && printCompletion == nil { renderInPlace() }
    }

    private func updateAppearanceItem() {
        let dark = AppearanceSettings.isDark
        appearanceItem?.image = NSImage(systemSymbolName: dark ? "sun.max" : "moon",
                                        accessibilityDescription: dark ? "Light mode" : "Dark mode")
        appearanceItem?.label = dark ? "Light Mode" : "Dark Mode"
        appearanceItem?.toolTip = dark ? "Switch to light mode" : "Switch to dark mode"
    }

    private var printCompletion: ((Bool) -> Void)?

    @objc private func printOperationDidRun(_ op: NSPrintOperation, success: Bool,
                                            contextInfo: UnsafeMutableRawPointer?)
    {
        let completion = printCompletion
        printCompletion = nil
        completion?(success)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleEditMode(_:)):
            item.title = isEditing ? "Show Preview" : "Edit Markdown"
            return true
        case #selector(toggleTableOfContents(_:)):
            item.state = showTOC ? .on : .off
            return !isEditing
        case #selector(zoomIn(_:)), #selector(zoomOut(_:)), #selector(actualSize(_:)):
            return !isEditing
        case #selector(findAction(_:)):
            // Find and Replace only makes sense in the editor.
            return isEditing || NSTextFinder.Action(rawValue: item.tag) != .showReplaceInterface
        case #selector(reloadDocument(_:)):
            return markdownDocument?.fileURL != nil
        default:
            return true
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        markdownDocument?.undoManager
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        markdownDocument?.textDidChangeInEditor(editor.string)
        previewIsStale = true
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageLoaded = true
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loadPage()
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void)
    {
        guard action.navigationType == .linkActivated, let url = action.request.url else {
            decisionHandler(.allow)
            return
        }
        // In-page anchors (table of contents, footnotes).
        if let current = webView.url, Self.stripFragment(url) == Self.stripFragment(current) {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        if url.scheme == LocalSchemeHandler.scheme {
            let fileURL = LocalSchemeHandler.fileURL(for: url)
            let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdtxt", "text"]
            if markdownExtensions.contains(fileURL.pathExtension.lowercased()) {
                NSDocumentController.shared.openDocument(withContentsOf: fileURL, display: true) { _, _, _ in }
            } else {
                NSWorkspace.shared.open(fileURL)
            }
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private static func stripFragment(_ url: URL) -> String {
        var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
        c?.fragment = nil
        return c?.string ?? url.absoluteString
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "copy", let text = message.body as? String {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
        }
    }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toc, .edit, .flexibleSpace, .appearance, .reload, .copyMarkdown]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toc, .edit, .appearance, .reload, .copyMarkdown, .flexibleSpace, .space]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem?
    {
        let item = NSToolbarItem(itemIdentifier: id)
        item.target = self
        switch id {
        case .toc:
            item.label = "Contents"
            item.toolTip = "Show or hide the table of contents (⌥⌘T)"
            item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Contents")
            item.action = #selector(toggleTableOfContents(_:))
        case .edit:
            item.action = #selector(toggleEditMode(_:))
            editItem = item
            updateEditItem()
        case .appearance:
            item.action = #selector(toggleAppearance(_:))
            appearanceItem = item
            updateAppearanceItem()
        case .reload:
            item.label = "Reload"
            item.toolTip = "Reload the file from disk (⌘R)"
            item.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reload")
            item.action = #selector(reloadDocument(_:))
        case .copyMarkdown:
            let button = NSButton(title: "Copy Markdown",
                                  image: NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)!,
                                  target: self, action: #selector(copyMarkdown(_:)))
            button.imagePosition = .imageLeading
            button.bezelStyle = .toolbar
            button.toolTip = "Copy the raw Markdown to the clipboard (⇧⌘C)"
            copyButton = button
            item.view = button
            item.label = "Copy Markdown"
        default:
            return nil
        }
        return item
    }
}
