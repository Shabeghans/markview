import Cocoa

/// App-wide light/dark choice. "System" follows macOS.
enum AppearanceMode: Int {
    case system = 0, light = 1, dark = 2
}

enum AppearanceSettings {
    private static let key = "appearanceMode"

    static var mode: AppearanceMode {
        get { AppearanceMode(rawValue: UserDefaults.standard.integer(forKey: key)) ?? .system }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
            apply()
        }
    }

    static func apply() {
        switch mode {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    static var isDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// The toolbar toggle: switch to the opposite of what is showing now.
    static func toggle() {
        mode = isDark ? .light : .dark
    }
}
