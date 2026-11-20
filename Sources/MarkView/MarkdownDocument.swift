import Cocoa

@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument {
    /// The current Markdown source (including unsaved edits).
    var text = ""
    private var watcher: FileWatcher?

    // Classic Save model: changes are only written when you press ⌘S.
    override class var autosavesInPlace: Bool { false }

    override func makeWindowControllers() {
        let controller = DocumentWindowController()
        addWindowController(controller)
        controller.loadInitialContent()
        restartWatcher()
    }

    // MARK: Reading & writing

    override func read(from data: Data, ofType typeName: String) throws {
        text = Self.decode(data)
        for case let controller as DocumentWindowController in windowControllers {
            controller.documentTextDidReload()
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        Data(text.utf8)
    }

    private static func decode(_ data: Data) -> String {
        if let s = String(data: data, encoding: .utf8) { return s }
        var converted: NSString?
        _ = NSString.stringEncoding(for: data, encodingOptions: nil, convertedString: &converted, usedLossyConversion: nil)
        return (converted as String?) ?? String(decoding: data, as: UTF8.self)
    }

    /// The edited/unedited state is tracked by the document's undo manager,
    /// which the editor's text view uses, so undoing back to the saved text
    /// clears the "Edited" marker.
    func textDidChangeInEditor(_ newText: String) {
        text = newText
    }

    // MARK: Reloading

    /// ⌘R: reload from disk, asking first if there are unsaved edits.
    func reloadFromDisk(window: NSWindow?) {
        guard let url = fileURL, let type = fileType else { return }
        if isDocumentEdited, let window {
            let alert = NSAlert()
            alert.messageText = "Discard your unsaved changes?"
            alert.informativeText = "Reloading replaces your edits with the version on disk."
            alert.addButton(withTitle: "Reload")
            alert.addButton(withTitle: "Cancel")
            alert.beginSheetModal(for: window) { [weak self] response in
                guard response == .alertFirstButtonReturn else { return }
                self?.revertQuietly(url: url, type: type, beepOnFailure: true)
            }
            return
        }
        revertQuietly(url: url, type: type, beepOnFailure: true)
    }

    /// Called by the file watcher when the file changes on disk.
    private func fileChangedOnDisk() {
        // Never clobber unsaved edits; the user can press ⌘R to reload explicitly.
        guard !isDocumentEdited, let url = fileURL, let type = fileType else { return }
        guard let data = try? Data(contentsOf: url) else { return }
        if Self.decode(data) == text { return }   // e.g. our own save
        revertQuietly(url: url, type: type, beepOnFailure: false)
    }

    private func revertQuietly(url: URL, type: String, beepOnFailure: Bool) {
        do {
            try revert(toContentsOf: url, ofType: type)
        } catch {
            if beepOnFailure { NSSound.beep() }
        }
    }

    // MARK: Watching

    override var fileURL: URL? {
        didSet {
            guard oldValue != fileURL, !windowControllers.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in self?.restartWatcher() }
        }
    }

    private func restartWatcher() {
        watcher?.stop()
        watcher = nil
        guard let url = fileURL else { return }
        watcher = FileWatcher(url: url) { [weak self] in self?.fileChangedOnDisk() }
    }

    override func close() {
        watcher?.stop()
        watcher = nil
        super.close()
    }
}
