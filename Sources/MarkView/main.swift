import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    func applicationWillFinishLaunching(_ notification: Notification) {
        AppearanceSettings.apply()
        NSApp.mainMenu = MainMenu.build()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Launched without a file (e.g. from the Dock): show the Open panel.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if NSDocumentController.shared.documents.isEmpty {
                NSDocumentController.shared.openDocument(nil)
            }
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NSDocumentController.shared.openDocument(nil) }
        return false
    }

    /// View > Appearance items; the menu item's tag is an AppearanceMode.
    @objc func setAppearanceMode(_ sender: NSMenuItem) {
        AppearanceSettings.mode = AppearanceMode(rawValue: sender.tag) ?? .system
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(setAppearanceMode(_:)) {
            item.state = item.tag == AppearanceSettings.mode.rawValue ? .on : .off
        }
        return true
    }
}

let app = NSApplication.shared
let arguments = CommandLine.arguments

if let flag = arguments.firstIndex(of: "--pdf") {
    // Headless mode for scripts and agents: MarkView --pdf <input.md> [output]
    guard let exporter = CommandLineExporter(arguments: Array(arguments[(flag + 1)...])) else { exit(2) }
    app.setActivationPolicy(.accessory)
    app.delegate = exporter
    app.run()
} else {
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
