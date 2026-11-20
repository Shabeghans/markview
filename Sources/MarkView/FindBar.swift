import Cocoa

/// Find bar shown above the rendered preview (the editor uses AppKit's own find bar).
final class FindBar: NSView, NSSearchFieldDelegate {
    var onSearch: ((String) -> Void)?
    var onStep: ((Int) -> Void)?
    var onClose: (() -> Void)?

    private let field = NSSearchField()
    private let status = NSTextField(labelWithString: "")
    private var lastQuery = ""

    var query: String { field.stringValue }

    override init(frame: NSRect) {
        super.init(frame: frame)

        field.placeholderString = "Find in document"
        field.sendsWholeSearchString = true      // action fires on Return only
        field.delegate = self
        field.target = self
        field.action = #selector(fieldAction(_:))
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true

        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.setContentHuggingPriority(.required, for: .horizontal)

        let nav = NSSegmentedControl(
            images: [NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "Previous match")!,
                     NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Next match")!],
            trackingMode: .momentary, target: self, action: #selector(navAction(_:)))
        nav.setToolTip("Previous match (⇧⌘G)", forSegment: 0)
        nav.setToolTip("Next match (⌘G)", forSegment: 1)

        let done = NSButton(title: "Done", target: self, action: #selector(doneAction(_:)))
        done.bezelStyle = .rounded
        done.controlSize = .small

        let row = NSStackView(views: [field, status, nav, done])
        row.orientation = .horizontal
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        row.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        addSubview(row)
        addSubview(separator)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: separator.topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    #if DEBUG
    func simulateTyping(_ text: String) {
        field.stringValue = text
        controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    }
    #endif

    func focus() {
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    /// Updates the "3 of 12" / "Not found" label.
    func show(count: Int, index: Int) {
        if field.stringValue.isEmpty {
            status.stringValue = ""
        } else if count == 0 {
            status.stringValue = "Not found"
            status.textColor = .systemRed
        } else {
            status.stringValue = "\(index + 1) of \(count)"
            status.textColor = .secondaryLabelColor
        }
    }

    // MARK: Actions

    func controlTextDidChange(_ obj: Notification) {
        lastQuery = field.stringValue
        onSearch?(field.stringValue)
    }

    @objc private func fieldAction(_ sender: Any?) {
        if field.stringValue != lastQuery {          // e.g. the clear (x) button
            lastQuery = field.stringValue
            onSearch?(field.stringValue)
            return
        }
        let backwards = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
        onStep?(backwards ? -1 : 1)
    }

    @objc private func navAction(_ sender: NSSegmentedControl) {
        onStep?(sender.selectedSegment == 0 ? -1 : 1)
    }

    @objc private func doneAction(_ sender: Any?) {
        onClose?()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            onClose?()
            return true
        }
        return false
    }
}
