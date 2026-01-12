import AppKit
import SwiftUI

/// Observable class that tracks system appearance and user color scheme preferences.
/// Uses AppKit to reliably detect system appearance changes for MenuBarExtra windows.
@MainActor
class AppearanceManager: ObservableObject {
    @Published var systemColorScheme: ColorScheme = .dark
    @Published var colorSchemeMode: String {
        didSet {
            UserDefaults.standard.set(colorSchemeMode, forKey: ThemeManager.colorSchemeModeKey)
        }
    }

    /// KVO observer for system appearance changes (nonisolated for deinit access)
    nonisolated(unsafe) private var appearanceObserver: NSKeyValueObservation?
    /// NotificationCenter observer for UserDefaults changes (nonisolated for deinit access)
    nonisolated(unsafe) private var userDefaultsObserver: NSObjectProtocol?

    init() {
        // Load initial color scheme mode from UserDefaults
        self.colorSchemeMode =
            UserDefaults.standard.string(forKey: ThemeManager.colorSchemeModeKey)
            ?? ColorSchemeMode.system.rawValue

        // Detect initial system appearance
        updateSystemColorScheme()

        // Observe system appearance changes via NSApp
        appearanceObserver = NSApp.observe(\.effectiveAppearance, options: [.new]) {
            [weak self] _, _ in
            Task { @MainActor in
                self?.updateSystemColorScheme()
            }
        }

        // Observe UserDefaults changes (from SettingsView's @AppStorage)
        userDefaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                let newMode =
                    UserDefaults.standard.string(forKey: ThemeManager.colorSchemeModeKey)
                    ?? ColorSchemeMode.system.rawValue
                if self.colorSchemeMode != newMode {
                    self.colorSchemeMode = newMode
                }
            }
        }
    }

    deinit {
        appearanceObserver?.invalidate()
        if let observer = userDefaultsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func updateSystemColorScheme() {
        let appearance = NSApp.effectiveAppearance
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        systemColorScheme = isDark ? .dark : .light
    }

    /// The effective color scheme combining user preference with system setting
    var effectiveColorScheme: ColorScheme {
        let mode = ColorSchemeMode(rawValue: colorSchemeMode) ?? .system
        return mode.effectiveColorScheme(systemScheme: systemColorScheme)
    }

    /// The color scheme preference to pass to SwiftUI (nil means follow system)
    var preferredColorScheme: ColorScheme? {
        let mode = ColorSchemeMode(rawValue: colorSchemeMode) ?? .system
        return mode.colorScheme
    }
}
